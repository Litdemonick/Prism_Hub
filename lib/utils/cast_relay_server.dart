import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prismhub/utils/cast_hls_ts.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

// Un dispositivo DLNA/Chromecast pide la URL del stream por su cuenta con
// SU PROPIO cliente HTTP — no hay forma de decirle "mandá este Referer/
// User-Agent". Muchas fuentes de anime (voe, streamwish, etc.) rechazan
// el pedido sin esos headers, así que casteá esas URLs directo fallaba en
// silencio en el TV/Chromecast aunque anduvieran perfecto localmente.
//
// Este servidor corre en la LAN (127.0.0.1 no sirve — el dispositivo que
// castea es OTRA máquina) y hace de intermediario: el dispositivo le pide
// a ESTE servidor, que a su vez pide la URL real con los headers
// correctos y le reenvía la respuesta tal cual (incluyendo Range, para
// que el seek siga funcionando).
class CastRelayServer {
  static HttpServer? _server;
  static int? _port;
  static final Map<String, _RelayTarget> _targets = {};

  // Contador para que dos registros del mismo microsegundo no se pisen: al
  // reescribir una lista HLS se registran cientos de segmentos de un saque.
  static int _correlativo = 0;

  /// User-Agent con el que sale el relay cuando la extensión no manda uno.
  ///
  /// NO es cosmético. Medido contra la fuente del registro del usuario
  /// (nika.playmudos.com, detrás de Cloudflare): con el User-Agent que pone
  /// dart:io por defecto responde **403**, y con uno de navegador responde
  /// **200** — con Referer o sin él, da igual. El puente de red de la app ya
  /// rellena uno cuando la extensión no lo trae (ver getUASetting), así que el
  /// relay sin esto pedía de una forma que la app nunca usa.
  static String get uaPorDefecto => _uaPorDefecto;

  static String get _uaPorDefecto {
    try {
      final delAjuste = PrismHubStorage.getUASetting();
      if (delAjuste is String && delAjuste.isNotEmpty) return delAjuste;
    } catch (_) {
      // Si los ajustes todavia no estan listos, vale el de abajo: lo que no
      // puede pasar es que el relay se caiga por leer una preferencia.
    }
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  // Registra una URL+headers y devuelve la URL local (LAN) que hay que
  // pasarle al dispositivo de cast en vez de la real.
  static Future<String> registerAndGetUrl({
    required String targetUrl,
    Map<String, String>? headers,
    PlanTs? planTs,
  }) async {
    await _ensureRunning();
    // El token lleva adelante un identificador de sesion para poder soltar de
    // una vez el maestro Y todos los segmentos que cuelgan de el (ver
    // unregister). Sin eso, cada episodio casteado dejaba cientos de entradas.
    final sesion = '${DateTime.now().microsecondsSinceEpoch}';
    final token = '$sesion-0';
    _targets[token] =
        _RelayTarget(targetUrl, headers ?? const {}, sesion, planTs: planTs);
    final ip = await _localLanAddress();
    if (ip == null) {
      // Sin una IP de red real no hay relay posible: lo unico que se le podria
      // dar al televisor es 127.0.0.1, que apunta a ESTE dispositivo y nunca
      // va a resolver desde el otro lado. Antes se devolvia igual, asi que el
      // cast fallaba en silencio y desde afuera parecia que el televisor no
      // soportaba el video.
      //
      // Se avisa con una excepcion para que el llamador lo registre y siga con
      // la URL directa: sin cabeceras puede fallar tambien, pero al menos
      // tiene una chance real.
      _targets.remove(token);
      throw StateError(
        'Sin direccion de red alcanzable: el dispositivo de cast no podria '
        'llegar a este equipo',
      );
    }
    _base = 'http://$ip:$_port';
    return '$_base/relay/$token';
  }

  // Direccion base del relay, cacheada: al reescribir una lista HLS hay que
  // armar cientos de direcciones y consultar las interfaces de red en cada una
  // seria carisimo.
  static String? _base;

  /// UN solo cliente HTTP para todo el relay, reusado entre pedidos.
  ///
  /// Antes se creaba uno nuevo en cada pedido y se cerraba al terminar, asi que
  /// no se reusaba ninguna conexion: con HLS, donde el receptor pide un
  /// pedacito por segundo, eso significaba un saludo TCP + TLS COMPLETO por
  /// cada pedacito. Cientos de milisegundos de ida y vuelta antes de empezar a
  /// bajar cada uno — el video se veia a tirones aunque la red estuviera bien.
  ///
  /// Compartiendolo, dart:io mantiene las conexiones vivas y el segundo
  /// pedacito y los que siguen viajan por la que ya estaba abierta.
  static final HttpClient _cliente = HttpClient()
    // Passthrough fiel: si se descomprime aca pero se reenvia el
    // content-encoding de la fuente, el receptor intenta descomprimir de nuevo
    // algo que ya viene descomprimido.
    ..autoUncompress = false
    // Varias en paralelo: el receptor suele pedir el siguiente pedacito
    // mientras todavia esta bajando el actual.
    ..maxConnectionsPerHost = 8
    // Que no las cierre entre pedacito y pedacito.
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 15);

  static Future<void> _ensureRunning() async {
    if (_server != null) return;
    _server = await shelf_io.serve(_handleRequest, InternetAddress.anyIPv4, 0);
    _port = _server!.port;
  }

  /// Lo último que respondió la fuente cuando rechazó un pedido del relay.
  ///
  /// El aparato que castea solo sabe decir "no se pudo reproducir": el motivo
  /// real (una dirección vencida, un 403 de la fuente) queda del lado nuestro y
  /// sin esto se perdía. Se guarda para poder mostrarlo en el aviso de error.
  static String? ultimoError;

  /// Sesiones para las que el aparato YA pidio algo, y desde que direccion.
  ///
  /// Distingue los dos motivos por los que un televisor puede quedarse en negro,
  /// que desde afuera se ven identicos:
  ///
  ///  - Nunca pidio nada: no llega hasta aca. Es red — otra subred, o un
  ///    cortafuegos tapando el puerto.
  ///  - Pidio y bajo datos: llega perfecto y el problema es que no puede con el
  ///    formato.
  ///
  /// Sin esto no habia forma de saber cual de las dos era, y se terminaba
  /// probando a ciegas.
  static final Map<String, String> pedidosPorSesion = {};

  /// Si el aparato pidio algo para esta transmision.
  static bool huboPedido(String? relayUrl) {
    final sesion = _sesionDe(relayUrl);
    return sesion != null && pedidosPorSesion.containsKey(sesion);
  }

  /// Desde que direccion pidio, para poder decirlo en el aviso.
  static String? quienPidio(String? relayUrl) {
    final sesion = _sesionDe(relayUrl);
    return sesion == null ? null : pedidosPorSesion[sesion];
  }

  static String? _sesionDe(String? relayUrl) {
    if (relayUrl == null) return null;
    final uri = Uri.tryParse(relayUrl);
    if (uri == null || uri.pathSegments.length < 2) return null;
    return _targets[uri.pathSegments[1]]?.sesion;
  }

  /// Cabeceras de permiso para que un receptor web pueda bajar el video.
  ///
  /// El receptor del Chromecast es una APLICACION WEB: para HLS baja cada
  /// pedacito con una peticion de navegador, y sin este permiso el propio
  /// navegador la bloquea antes de salir. El resultado era que el aparato
  /// aceptaba el video, mostraba el titulo, y no dibujaba nunca nada.
  ///
  /// No molesta a nadie mas: un televisor DLNA baja el video con su propio
  /// cliente HTTP y estas cabeceras las ignora.
  // Cabeceras que pide el estándar DLNA y que no estábamos mandando.
  //
  // Sin ellas, un LG con webOS acepta la orden, muestra el título y la barra
  // de carga… y nunca dibuja la imagen: aceptó el transporte pero no sabe
  // cómo consumir el flujo. Kodi y Samsung son permisivos y andan igual, por
  // eso el fallo parecía cosa de un televisor roto. Comprobado en vivo que ese
  // mismo LG (55UT8050PSB, 2025) SÍ recibe por DLNA desde otras apps, así que
  // el que estaba incompleto era este servidor.
  //
  // transferMode: "Streaming" es lo que corresponde a vídeo que se mira
  // mientras llega, en vez de "Interactive" (imágenes) o "Background"
  // (descarga).
  //
  // DLNA.ORG_OP=00: no se puede saltar, ni por tiempo ni por byte. Es la
  // verdad —el TS se arma sobre la marcha y por eso va Accept-Ranges: none— y
  // decirlo evita que el televisor intente un salto que va a fallar.
  //
  // DLNA.ORG_FLAGS=0x01700000: streaming + transferencia en segundo plano +
  // aguantar pausas de conexión + DLNA v1.5. Los ceros de atrás son parte del
  // formato (son 32 dígitos hexadecimales en total, no un relleno inventado).
  //
  // A propósito NO se declara DLNA.ORG_PN: es opcional, y poner un perfil
  // equivocado es peor que no poner ninguno — el televisor intentaría decodificar
  // como ese perfil en vez de mirar el flujo.
  static const _dlna = {
    'transferMode.dlna.org': 'Streaming',
    'contentFeatures.dlna.org':
        'DLNA.ORG_OP=00;DLNA.ORG_CI=0;'
        'DLNA.ORG_FLAGS=01700000000000000000000000000000',
  };

  static const _permisos = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Expose-Headers': 'Content-Length, Content-Range',
  };

  static Future<Response> _handleRequest(Request request) async {
    // El navegador PREGUNTA antes de bajar nada de otro origen. Si esa
    // pregunta no se contesta, no llega a pedir el video.
    if (request.method.toUpperCase() == 'OPTIONS') {
      return Response.ok(null, headers: _permisos);
    }
    final segments = request.url.pathSegments;
    if (segments.length < 2 || segments[0] != 'relay') {
      return Response.notFound('not found');
    }
    final target = _targets[segments[1]];
    if (target == null) return Response.notFound('unknown relay token');

    // Se anota que el aparato llego hasta aca. Solo la primera vez de cada
    // transmision: despues son cientos de pedidos por episodio.
    if (!pedidosPorSesion.containsKey(target.sesion)) {
      final quien = (request.context['shelf.io.connection_info']
                  as HttpConnectionInfo?)
              ?.remoteAddress
              .address ??
          'desconocido';
      pedidosPorSesion[target.sesion] = quien;
      logger.info('El aparato pidio el video desde $quien');
    }

    // El receptor pregunta primero con HEAD (el "Stat" de Kodi) para saber
    // tamaño y tipo antes de bajar nada. Antes se le contestaba SIEMPRE con un
    // GET: se abría la descarga entera del vídeo solo para tirarla, y la
    // respuesta no traía lo que había preguntado.
    final esHead = request.method.toUpperCase() == 'HEAD';

    // Televisor que no entiende HLS: se le manda el vídeo ya pegado en un
    // MPEG-TS continuo en vez de la lista. Ver cast_hls_ts.dart.
    final plan = target.planTs;
    if (plan != null) {
      final cabeceras = {
        'Content-Type': 'video/mpeg',
        // De largo desconocido a propósito: se va armando sobre la marcha. Por
        // eso tampoco se puede adelantar, y se avisa antes de empezar.
        'Accept-Ranges': 'none',
        'Cache-Control': 'no-cache',
        ..._dlna,
        ..._permisos,
      };
      if (esHead) return Response.ok(null, headers: cabeceras);
      return Response.ok(CastHlsATs.servir(plan), headers: cabeceras);
    }

    final client = _cliente;
    try {
      final uri = Uri.parse(target.url);
      final esLista = _pareceHls(target.url);
      final upstreamReq =
          esHead ? await client.headUrl(uri) : await client.getUrl(uri);
      target.headers.forEach((key, value) => upstreamReq.headers.set(key, value));
      // Si la extension no mando User-Agent, el que pone dart:io hace que
      // Cloudflare conteste 403 (medido). Ver _uaPorDefecto.
      if (upstreamReq.headers.value(HttpHeaders.userAgentHeader) == null ||
          !target.headers.keys
              .any((k) => k.toLowerCase() == 'user-agent')) {
        upstreamReq.headers.set(HttpHeaders.userAgentHeader, _uaPorDefecto);
      }
      final range = request.headers['range'];
      // A una lista de reproduccion NO se le reenvia el Range: si la fuente
      // contesta un trozo, la lista llega cortada y el receptor se queda sin
      // los ultimos segmentos.
      if (range != null && !esLista) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      }
      final upstreamRes = await upstreamReq.close();

      if (upstreamRes.statusCode >= 400) {
        // El cuerpo del rechazo casi siempre viene comprimido y en HTML (una
        // página de bloqueo de Cloudflare, por ejemplo). Antes se mostraba tal
        // cual y en pantalla salía un chorro de caracteres ilegibles, porque
        // con autoUncompress apagado esos bytes son gzip crudo.
        final motivo = await _motivoLegible(upstreamRes);
        ultimoError = 'La fuente rechazó el vídeo (HTTP '
            '${upstreamRes.statusCode})${motivo.isEmpty ? '' : ': $motivo'}';
        logger.warning('Relay de casteo: $ultimoError — ${target.url}');
        return Response(upstreamRes.statusCode, body: motivo);
      }

      // Listas HLS: hay que reescribirlas.
      //
      // Una .m3u8 no trae vídeo, trae las direcciones de los pedacitos — y
      // suelen estar en OTRO host (medido: la lista de nika.playmudos.com
      // apunta a cdn6.ducvomes.com). Si se le pasa la lista tal cual, el
      // receptor pide esos pedacitos POR SU CUENTA, sin pasar por acá y sin las
      // cabeceras, y se come el mismo 403 que estábamos evitando. Reescribirla
      // hace que todo el flujo vuelva por el relay.
      if (esLista || _pareceHlsPorTipo(upstreamRes)) {
        final crudo = await _leerTodo(upstreamRes);
        final lista = await _reescribirLista(crudo, uri, target);
        return Response.ok(
          lista,
          headers: {
            'Content-Type': 'application/vnd.apple.mpegurl',
            // La lista cambió de tamaño, así que el largo de la fuente ya no
            // vale y el content-encoding tampoco (acá va en texto plano).
            'Cache-Control': 'no-cache',
            ..._permisos,
          },
        );
      }

      final resHeaders = <String, String>{};
      upstreamRes.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        // transfer-encoding se recalcula solo; reenviar el de arriba deja la
        // respuesta declarando un troceado que no es el que se está usando.
        //
        // content-length en cambio SÍ se conserva: es lo que le dice al
        // receptor cuánto dura y le permite adelantar. Antes se quitaba, así
        // que el vídeo llegaba como un flujo de largo desconocido.
        if (lower == 'transfer-encoding') return;
        resHeaders[name] = values.join(', ');
      });

      resHeaders.addAll(_permisos);

      if (esHead) {
        return Response(upstreamRes.statusCode, headers: resHeaders);
      }

      // El cuerpo va DIRECTO, sin envolverlo.
      //
      // Antes pasaba por un transformador cuyo unico trabajo era cerrar el
      // cliente al terminar. Ahora el cliente es compartido y no se cierra —
      // cerrarlo mataria las conexiones de los demas pedacitos en vuelo — asi
      // que ese envoltorio solo agregaba una copia de cada bloque de bytes en
      // el camino, en el punto por el que pasa TODO el video.
      return Response(
        upstreamRes.statusCode,
        body: upstreamRes,
        headers: resHeaders,
      );
    } catch (e) {
      ultimoError = 'No se pudo alcanzar la fuente del vídeo: $e';
      logger.warning('Relay de casteo: $ultimoError — ${target.url}');
      return Response.internalServerError(body: 'relay error: $e');
    }
  }

  static bool _pareceHls(String url) =>
      Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') ?? false;

  static bool _pareceHlsPorTipo(HttpClientResponse res) {
    final tipo = res.headers.contentType?.mimeType.toLowerCase() ?? '';
    return tipo.contains('mpegurl');
  }

  /// Deja el cuerpo de un rechazo en algo que se pueda leer en pantalla.
  ///
  /// Descomprime si hace falta, se queda con el texto visible del HTML y lo
  /// corta. Si no hay nada legible devuelve vacío: mejor mostrar solo el código
  /// que un chorro de símbolos.
  static Future<String> _motivoLegible(HttpClientResponse res) async {
    try {
      final trozos = <int>[];
      await for (final t in res.timeout(const Duration(seconds: 5))) {
        trozos.addAll(t);
        if (trozos.length >= 64 * 1024) break;
      }
      var bytes = trozos;
      final enc = res.headers.value(HttpHeaders.contentEncodingHeader);
      if (enc != null && enc.toLowerCase().contains('gzip')) {
        try {
          bytes = gzip.decode(bytes);
        } catch (_) {
          return '';
        }
      }
      var texto = utf8.decode(bytes, allowMalformed: true);
      // De una página de bloqueo solo interesa el texto, no el HTML entero.
      texto = texto
          .replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (texto.length > 200) texto = '${texto.substring(0, 200)}…';
      // Si quedó ilegible (binario), no se muestra nada.
      final raros = texto.runes.where((r) => r < 32 || r > 126 && r < 160).length;
      if (texto.isEmpty || raros > texto.length ~/ 10) return '';
      return texto;
    } catch (_) {
      return '';
    }
  }

  static Future<List<int>> _leerTodo(HttpClientResponse res) async {
    final bytes = <int>[];
    await for (final t in res.timeout(const Duration(seconds: 30))) {
      bytes.addAll(t);
      // Una lista de reproducción son unos pocos KB; si llega algo enorme es
      // que no era una lista y se corta antes de comerse la memoria.
      if (bytes.length > 8 * 1024 * 1024) break;
    }
    final enc = res.headers.value(HttpHeaders.contentEncodingHeader);
    if (enc != null && enc.toLowerCase().contains('gzip')) {
      try {
        return gzip.decode(bytes);
      } catch (_) {
        return bytes;
      }
    }
    return bytes;
  }

  /// Reapunta cada dirección de la lista al propio relay.
  ///
  /// Toca las líneas sueltas (segmentos y listas anidadas por calidad) y los
  /// atributos `URI="…"` de las etiquetas — ahí viven la clave de cifrado y las
  /// pistas de audio/subtítulos alternativas, que si no quedarían pidiéndose
  /// por fuera.
  static Future<String> _reescribirLista(
      List<int> crudo, Uri base, _RelayTarget padre) async {
    final texto = utf8.decode(crudo, allowMalformed: true);
    final relayBase = _base;
    if (relayBase == null) return texto;

    // Los pedacitos, DIRECTOS a la fuente cuando se puede.
    //
    // Hacerlos pasar por aca es lo unico que funciona si la fuente exige
    // Referer, pero cuesta caro: cada pedacito viaja dos veces (baja al
    // telefono y sube al televisor), y con un pedacito por segundo eso se nota
    // como tirones aunque la red este bien.
    //
    // Asi que primero se prueba: si un pedacito se puede bajar SIN nuestras
    // cabeceras, el receptor puede pedirlos el mismo y el relay se saca del
    // camino. Medido contra la fuente del registro del usuario, los pedacitos
    // contestan 200 sin ninguna cabecera, asi que ahi este atajo aplica.
    final directo = await _pedacitosVanDirecto(texto, base);
    final salida = StringBuffer();
    if (directo) {
      // Igual hay que reescribir: las direcciones relativas de la lista se
      // resolverian contra la direccion del RELAY, que no es de donde salio.
      for (final linea in const LineSplitter().convert(texto)) {
        final limpia = linea.trim();
        if (limpia.isEmpty || limpia.startsWith('#')) {
          salida.writeln(linea.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (m) => 'URI="${base.resolve(m[1]!)}"',
          ));
          continue;
        }
        salida.writeln(base.resolve(limpia).toString());
      }
      return salida.toString();
    }

    for (final linea in const LineSplitter().convert(texto)) {
      final limpia = linea.trim();
      if (limpia.isEmpty) {
        salida.writeln(linea);
        continue;
      }
      if (limpia.startsWith('#')) {
        salida.writeln(linea.replaceAllMapped(
          RegExp(r'URI="([^"]+)"'),
          (m) => 'URI="${_registrarHijo(base, m[1]!, padre, relayBase)}"',
        ));
        continue;
      }
      salida.writeln(_registrarHijo(base, limpia, padre, relayBase));
    }
    return salida.toString();
  }

  // Direccion ya registrada -> su token, por sesion.
  //
  // Una lista puede tener cientos de segmentos (medido: 498 en un episodio) y
  // el receptor puede volver a pedirla —en directo la repide cada pocos
  // segundos—. Sin esto cada relectura registraria todo de nuevo y el mapa
  // creceria sin techo mientras dure la transmision.
  static final Map<String, String> _tokensPorUrl = {};

  /// Prueba si un pedacito de la lista se puede bajar SIN nuestras cabeceras.
  ///
  /// Si se puede, el receptor los pide directo a la fuente y el relay deja de
  /// estar en el camino de todo el video. Ante cualquier duda —no se pudo
  /// probar, contesto mal— devuelve false y se sigue haciendolos pasar por
  /// aca, que es lo que siempre funciona aunque cueste mas.
  static Future<bool> _pedacitosVanDirecto(String lista, Uri base) async {
    String? primero;
    for (final linea in const LineSplitter().convert(lista)) {
      final t = linea.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      primero = t;
      break;
    }
    if (primero == null) return false;
    // Otra lista anidada (calidades): esa si tiene que pasar por aca, porque a
    // su vez hay que reescribirla.
    if (_pareceHls(base.resolve(primero).toString())) return false;
    try {
      final req = await _cliente.getUrl(base.resolve(primero));
      req.headers.set(HttpHeaders.userAgentHeader, _uaPorDefecto);
      // Solo los primeros bytes: alcanza para saber si deja o no.
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      final res = await req.close().timeout(const Duration(seconds: 6));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      // El cuerpo se descarta, pero hay que drenarlo para que la conexion
      // vuelva al pozo en vez de quedar a medio usar.
      await res.drain<void>().timeout(const Duration(seconds: 4),
          onTimeout: () {});
      if (ok) {
        logger.info('Los pedacitos van directo: el relay se saca del camino');
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  static String _registrarHijo(
      Uri base, String destino, _RelayTarget padre, String relayBase) {
    final absoluta = base.resolve(destino).toString();
    final clave = '${padre.sesion}|$absoluta';
    final yaEsta = _tokensPorUrl[clave];
    if (yaEsta != null) return '$relayBase/relay/$yaEsta';
    final token = '${padre.sesion}-${++_correlativo}';
    _targets[token] = _RelayTarget(absoluta, padre.headers, padre.sesion);
    _tokensPorUrl[clave] = token;
    return '$relayBase/relay/$token';
  }

  // Libera la memoria de un target una vez que ya no hace falta (al
  // desconectar el cast) — sin esto los tokens viejos quedan colgados
  // hasta reiniciar la app.
  //
  // Se sueltan el maestro Y todos los segmentos de la misma sesion: una lista
  // HLS registra cientos, y borrar solo el maestro los dejaba a todos colgados.
  static void unregister(String relayUrl) {
    final uri = Uri.tryParse(relayUrl);
    if (uri == null || uri.pathSegments.length < 2) return;
    final sesion = _targets[uri.pathSegments[1]]?.sesion;
    if (sesion == null) {
      _targets.remove(uri.pathSegments[1]);
      return;
    }
    _targets.removeWhere((_, t) => t.sesion == sesion);
    _tokensPorUrl.removeWhere((clave, _) => clave.startsWith('$sesion|'));
    pedidosPorSesion.remove(sesion);
    _cerrarSiSobra();
  }

  /// Cierra el servidor cuando ya no queda nada que servir.
  ///
  /// Se abria en el primer casteo y no se cerraba nunca: quedaba un puerto
  /// escuchando en la red local durante toda la vida de la app, aunque hiciera
  /// rato que no se transmitiera nada. Al volver a castear se levanta solo.
  static void _cerrarSiSobra() {
    if (_targets.isNotEmpty) return;
    final server = _server;
    if (server == null) return;
    _server = null;
    _port = null;
    _base = null;
    // Sin force: si justo hay una respuesta a medio mandar, se la deja
    // terminar en vez de cortarla por la mitad.
    unawaited(server.close().catchError((Object e) {
      logger.warning('No se pudo cerrar el servidor de casteo', e);
    }));
  }

  // Primera IPv4 no-loopback de una interfaz real — es la que un
  // dispositivo de la MISMA red puede alcanzar (127.0.0.1 solo sirve
  // dentro de esta máquina).
  /// Devuelve null si no hay ninguna: ver el uso en registerAndGetUrl.
  static Future<String?> _localLanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    // Nada alcanzable desde afuera. Devolver loopback seria peor que no
    // devolver nada: parece una direccion valida y no lo es.
    return null;
  }
}

class _RelayTarget {
  _RelayTarget(this.url, this.headers, this.sesion, {this.planTs});
  final String url;
  final Map<String, String> headers;

  /// Cuando viene, a este token no se le sirve la lista HLS sino los pedacitos
  /// pegados en un MPEG-TS continuo, que es lo único que entiende un televisor
  /// viejo. Ver cast_hls_ts.dart.
  final PlanTs? planTs;

  /// Agrupa el maestro con los segmentos que salieron de su lista, para poder
  /// soltarlos todos juntos al desconectar (ver unregister).
  final String sesion;
}
