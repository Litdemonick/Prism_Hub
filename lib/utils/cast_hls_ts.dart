import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:prismhub/utils/log.dart';

/// Convierte una lista HLS en un vídeo continuo que un televisor viejo entiende.
///
/// El problema: las extensiones sirven casi todo en HLS (`.m3u8`), y **ningún
/// televisor DLNA lo reproduce** — HLS es de 2009 y DLNA es anterior, nunca lo
/// incorporó. Medido en la red del usuario: Kodi publica `mpegurl` entre sus
/// formatos y reproduce; el televisor no lo publica y se queda en negro.
///
/// La salida: una lista HLS **ya es** MPEG-TS por dentro. Los pedacitos `.ts`
/// que la componen son trozos de un flujo MPEG-TS normal, cortados en pedazos.
/// Pegarlos uno atrás de otro devuelve un MPEG-TS válido, y `video/mpeg` sí
/// está en la lista de formatos del televisor. **No se recodifica nada**: los
/// bytes salen tal cual llegan, así que no cuesta procesador ni pierde calidad.
///
/// Lo que se pierde: no se puede adelantar. Al televisor se le manda un flujo
/// de largo desconocido, así que la barra de progreso no le sirve para saltar.
/// Se avisa antes de empezar en vez de dejar que lo descubra probando.
///
/// Cuándo NO se puede, y hay que decirlo en vez de mandar basura:
///
///  - **Pedacitos cifrados** (`#EXT-X-KEY`): habría que descifrarlos primero.
///  - **Pedacitos en formato MP4** (`#EXT-X-MAP`, el HLS moderno): no son
///    MPEG-TS, y pegarlos no da nada reproducible.
class CastHlsATs {
  /// Cuántas veces se reintenta un pedacito antes de saltearlo.
  static const _reintentos = 2;

  static final HttpClient _cliente = HttpClient()
    ..maxConnectionsPerHost = 4
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 15);

  /// Pone las cabeceras de la extensión y se asegura de que salga un
  /// User-Agent de navegador.
  ///
  /// El User-Agent NO es cosmético: medido contra la fuente del usuario
  /// (nika.playmudos.com, detrás de Cloudflare), con el que pone dart:io por
  /// defecto la respuesta es **403** y con uno de navegador es **200**.
  ///
  /// Y hay que mirar las cabeceras de la extensión, no las del pedido: dart:io
  /// **siempre** deja puesto su `Dart/x.y (dart:io)`, así que preguntar si el
  /// pedido ya trae uno da que sí SIEMPRE y el de navegador no se aplicaba
  /// nunca. Eso hacía que no se pudiera leer ni la lista, y desde afuera se
  /// veía como "este aparato no soporta el formato".
  static void _preparar(
    HttpClientRequest req,
    Map<String, String> headers,
    String userAgent,
  ) {
    headers.forEach((k, v) => req.headers.set(k, v));
    final loTraeLaExtension =
        headers.keys.any((k) => k.toLowerCase() == 'user-agent');
    if (!loTraeLaExtension && userAgent.isNotEmpty) {
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
  }

  /// Mira la lista y decide si se puede reempaquetar.
  ///
  /// Devuelve null cuando no se puede — el motivo queda en el registro.
  static Future<PlanTs?> analizar(
    String url,
    Map<String, String> headers,
    String userAgent,
  ) async {
    try {
      var uri = Uri.parse(url);
      var texto = await _bajarTexto(uri, headers, userAgent);
      if (texto == null) return null;

      // Lista maestra: no trae pedacitos, trae una lista por calidad. Hay que
      // elegir una y volver a bajar.
      if (texto.contains('#EXT-X-STREAM-INF')) {
        final variante = _mejorVariante(texto, uri);
        if (variante == null) {
          logger.info('Reempaquetado a TS: la lista maestra no traía calidades');
          return null;
        }
        uri = variante;
        texto = await _bajarTexto(uri, headers, userAgent);
        if (texto == null) return null;
      }

      if (RegExp(r'#EXT-X-KEY:[^\r\n]*METHOD=(?!NONE)').hasMatch(texto)) {
        logger.info('Reempaquetado a TS: los pedacitos están cifrados');
        return null;
      }
      if (texto.contains('#EXT-X-MAP')) {
        logger.info('Reempaquetado a TS: los pedacitos son MP4, no MPEG-TS');
        return null;
      }

      final pedacitos = <Uri>[];
      final duraciones = <double>[];
      double? ultimoExtinf;
      for (final linea in const LineSplitter().convert(texto)) {
        final limpia = linea.trim();
        if (limpia.isEmpty) continue;
        if (limpia.startsWith('#EXTINF:')) {
          ultimoExtinf =
              double.tryParse(limpia.substring(8).split(',').first.trim());
          continue;
        }
        if (limpia.startsWith('#')) continue;
        pedacitos.add(uri.resolve(limpia));
        // Cada pedacito con SU duracion, no una suma: es lo que permite saber
        // en cual cae un minuto concreto cuando el usuario adelanta.
        duraciones.add(ultimoExtinf ?? 0);
        ultimoExtinf = null;
      }
      if (pedacitos.isEmpty) {
        logger.info('Reempaquetado a TS: la lista no tenía pedacitos');
        return null;
      }

      // Comprobación de verdad, no por el nombre del archivo: se bajan los
      // primeros bytes del primer pedacito y se mira si son MPEG-TS. Fiarse de
      // que termine en ".ts" es lo que haría mandarle basura al televisor
      // cuando la fuente usa otra extensión.
      if (!await _esMpegTs(pedacitos.first, headers, userAgent)) {
        logger.info('Reempaquetado a TS: el primer pedacito no es MPEG-TS');
        return null;
      }

      final plan = PlanTs(
        pedacitos: pedacitos,
        duraciones: duraciones,
        headers: headers,
        userAgent: userAgent,
      );
      logger.info('Reempaquetado a TS: ${pedacitos.length} pedacitos, '
          '${plan.duracion.inSeconds}s');
      return plan;
    } catch (e) {
      logger.info('Reempaquetado a TS: no se pudo analizar la lista — $e');
      return null;
    }
  }

  /// Cuántos pedacitos se van bajando POR DELANTE del que se está entregando.
  ///
  /// Antes no había ninguno: se bajaba uno, se entregaba, y recién cuando el
  /// televisor terminaba de tragarlo se empezaba a pedir el siguiente. O sea que
  /// el tiempo de bajar cada pedacito se sumaba entero al de reproducirlo, y el
  /// televisor se quedaba sin datos entre uno y otro — exactamente el "va lento
  /// y se para" que se ve al castear. Con dos por delante, mientras el aparato
  /// consume uno ya hay otros dos descargados esperando, y el bache solo se nota
  /// si la conexión no llega ni a seguirle el ritmo al vídeo.
  ///
  /// Dos y no veinte porque cada uno se guarda entero en memoria mientras
  /// espera: son unos pocos megas por pedacito, y con este número el techo
  /// queda en el orden de la decena de megas.
  static const _porDelante = 2;

  /// Los bytes del vídeo, en orden y sin cortes.
  ///
  /// Se bajan varios pedacitos a la vez pero se entregan SIEMPRE en orden: un
  /// MPEG-TS es un flujo continuo y un pedacito fuera de lugar lo rompe.
  static Stream<List<int>> servir(PlanTs plan) async* {
    // Desde donde diga el plan: adelantar es servir el mismo video empezando
    // por otro pedacito.
    final enVuelo = <Future<List<int>?>>[];
    var proximo = plan.desde;

    void llenarLaCola() {
      while (enVuelo.length <= _porDelante &&
          proximo < plan.pedacitos.length) {
        enVuelo.add(_bajarPedacito(plan, proximo));
        proximo++;
      }
    }

    // El PRIMER pedacito se entrega a medida que llega, sin esperar a tenerlo
    // entero.
    //
    // Esperarlo completo dejaba la respuesta HTTP en silencio desde que el
    // televisor la pedía hasta que terminaba de bajar ese pedacito — varios
    // segundos con un CDN lento. Muchos televisores dan por muerta una conexión
    // que no manda un solo byte en ese rato: la cierran, vuelven a pedir la
    // misma dirección, y como el flujo se arma desde el principio, el vídeo
    // arranca de cero otra vez. Y otra. Ese es el bucle de reinicios.
    //
    // Los siguientes SÍ se bajan enteros por delante (es lo que evita el corte
    // entre uno y otro), pero para entonces ya hay bytes viajando y el
    // televisor no tiene motivo para cortar.
    if (proximo < plan.pedacitos.length) {
      final primero = proximo;
      proximo++;
      // La cola de los que vienen detrás arranca YA, en paralelo con este.
      llenarLaCola();
      yield* _servirPedacitoEnVivo(plan, primero);
    }

    while (enVuelo.isNotEmpty) {
      final bytes = await enVuelo.removeAt(0);
      // Se pide el reemplazo apenas se saca uno de la cola, no después de
      // entregarlo: si se esperara a que el televisor lo consuma, volveríamos a
      // tener la descarga y la reproducción una detrás de la otra.
      llenarLaCola();
      // null es un pedacito que no se pudo bajar ni reintentando: se saltea. Se
      // nota como un saltito y el vídeo sigue; cortar la transmisión entera por
      // uno sería mucho peor.
      if (bytes == null) continue;
      yield bytes;
    }
  }

  /// Un pedacito servido a medida que llega, sin juntarlo antes en memoria.
  ///
  /// Solo se reintenta si TODAVÍA no salió nada: una vez que hay bytes en
  /// camino, volver a empezar el pedacito los duplicaría dentro del flujo, y un
  /// MPEG-TS con bytes repetidos se rompe. Si se corta a mitad, es preferible el
  /// saltito.
  static Stream<List<int>> _servirPedacitoEnVivo(PlanTs plan, int indice) async* {
    final trozo = plan.pedacitos[indice];
    for (var intento = 0; intento <= _reintentos; intento++) {
      var salioAlgo = false;
      try {
        final req = await _cliente.getUrl(trozo);
        _preparar(req, plan.headers, plan.userAgent);
        final res = await req.close().timeout(const Duration(seconds: 30));
        if (res.statusCode >= 400) {
          await res.drain<void>();
          throw HttpException('HTTP ${res.statusCode}');
        }
        await for (final bloque in res) {
          salioAlgo = true;
          yield bloque;
        }
        return;
      } catch (e) {
        if (salioAlgo) {
          logger.warning('Reempaquetado a TS: el pedacito ${indice + 1} se '
              'cortó a mitad, se sigue con el siguiente — $e');
          return;
        }
        if (intento == _reintentos) {
          logger.warning(
              'Reempaquetado a TS: se saltea el pedacito ${indice + 1} — $e');
        }
      }
    }
  }

  /// Un pedacito entero en memoria, o null si no se pudo bajar.
  ///
  /// Nunca tira: quien lo espera está sirviendo un vídeo en marcha y una
  /// excepción ahí cortaría la transmisión completa.
  static Future<List<int>?> _bajarPedacito(PlanTs plan, int indice) async {
    final trozo = plan.pedacitos[indice];
    for (var intento = 0; intento <= _reintentos; intento++) {
      try {
        final req = await _cliente.getUrl(trozo);
        _preparar(req, plan.headers, plan.userAgent);
        final res = await req.close().timeout(const Duration(seconds: 30));
        if (res.statusCode >= 400) {
          await res.drain<void>();
          throw HttpException('HTTP ${res.statusCode}');
        }
        final juntado = BytesBuilder(copy: false);
        await for (final bloque in res) {
          juntado.add(bloque);
        }
        return juntado.takeBytes();
      } catch (e) {
        if (intento == _reintentos) {
          logger.warning(
              'Reempaquetado a TS: se saltea el pedacito ${indice + 1} — $e');
        }
      }
    }
    return null;
  }

  /// Baja una lista y la devuelve como texto, o null si no se pudo.
  static Future<String?> _bajarTexto(
    Uri uri,
    Map<String, String> headers,
    String userAgent,
  ) async {
    final req = await _cliente.getUrl(uri);
    _preparar(req, headers, userAgent);
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      await res.drain<void>();
      logger.info('Reempaquetado a TS: la lista contestó ${res.statusCode}');
      return null;
    }
    return res.transform(utf8.decoder).join();
  }

  /// La calidad más alta de una lista maestra.
  static Uri? _mejorVariante(String texto, Uri base) {
    final lineas = const LineSplitter().convert(texto);
    Uri? mejor;
    var mejorAncho = -1;
    for (var i = 0; i < lineas.length; i++) {
      if (!lineas[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final ancho = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(lineas[i])?.group(1) ??
                  '') ??
          0;
      for (var j = i + 1; j < lineas.length; j++) {
        final destino = lineas[j].trim();
        if (destino.isEmpty || destino.startsWith('#')) continue;
        if (ancho > mejorAncho) {
          mejorAncho = ancho;
          mejor = base.resolve(destino);
        }
        break;
      }
    }
    return mejor;
  }

  /// Si los bytes que llegan son de verdad MPEG-TS.
  ///
  /// Un MPEG-TS son paquetes de 188 bytes que empiezan siempre con 0x47. Se
  /// comprueban dos seguidos: que el primer byte sea 0x47 puede ser suerte, que
  /// además lo sea el byte 188 no lo es.
  static Future<bool> _esMpegTs(
    Uri trozo,
    Map<String, String> headers,
    String userAgent,
  ) async {
    try {
      final req = await _cliente.getUrl(trozo);
      _preparar(req, headers, userAgent);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-375');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode >= 400) {
        await res.drain<void>();
        return false;
      }
      final bytes = <int>[];
      await for (final b in res) {
        bytes.addAll(b);
        if (bytes.length >= 189) break;
      }
      if (bytes.length < 189) return false;
      return bytes[0] == 0x47 && bytes[188] == 0x47;
    } catch (_) {
      return false;
    }
  }
}

/// Todo lo que hace falta para servir una lista HLS como un MPEG-TS continuo.
class PlanTs {
  PlanTs({
    required this.pedacitos,
    required this.duraciones,
    required this.headers,
    required this.userAgent,
    this.desde = 0,
  });

  /// Las direcciones de los pedacitos, en orden de reproducción.
  final List<Uri> pedacitos;

  /// Cuánto dura cada pedacito, en segundos, sacado de los `#EXTINF`.
  ///
  /// Es lo que permite adelantar: sabiendo cuánto dura cada uno se sabe en
  /// cuál cae cualquier minuto del episodio. Ver [indiceDe].
  final List<double> duraciones;

  /// Desde qué pedacito arranca este flujo.
  ///
  /// Adelantar en un vídeo reempaquetado es empezar uno nuevo desde otro
  /// pedacito, porque el televisor no puede saltar dentro de un flujo que se
  /// va armando sobre la marcha.
  final int desde;

  final Map<String, String> headers;
  final String userAgent;

  /// Lo que dura el episodio entero.
  Duration get duracion => Duration(
      milliseconds:
          (duraciones.fold<double>(0, (a, b) => a + b) * 1000).round());

  /// En qué momento del episodio empieza este flujo.
  ///
  /// La app le suma esto a lo que informa el televisor, que cuenta desde cero
  /// porque para él es un vídeo nuevo.
  Duration get inicio => Duration(
      milliseconds: (duraciones
                  .take(desde)
                  .fold<double>(0, (a, b) => a + b) *
              1000)
          .round());

  /// Qué pedacito contiene ese momento del episodio.
  int indiceDe(Duration donde) {
    var acumulado = 0.0;
    final objetivo = donde.inMilliseconds / 1000.0;
    for (var i = 0; i < duraciones.length; i++) {
      acumulado += duraciones[i];
      if (acumulado > objetivo) return i;
    }
    // Más allá del final: el último, para no quedar fuera de la lista.
    return duraciones.isEmpty ? 0 : duraciones.length - 1;
  }

  /// El mismo vídeo, empezando desde otro pedacito.
  PlanTs recortadoDesde(int indice) => PlanTs(
        pedacitos: pedacitos,
        duraciones: duraciones,
        headers: headers,
        userAgent: userAgent,
        desde: indice.clamp(0, pedacitos.length - 1),
      );
}
