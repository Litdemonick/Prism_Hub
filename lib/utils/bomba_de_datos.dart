import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:prismhub/utils/log.dart';

/// Le sirve un archivo remoto al reproductor de ESTE equipo desde una sola
/// lectura abierta río arriba.
///
/// ── Para qué existe ─────────────────────────────────────────────────────────
///
/// Hay fuentes que cobran carísimo **cada pedido nuevo**. Medido en mp4upload el
/// 2026-08-06, mismo archivo y misma red:
///
///     pedido abierto (`bytes=0-`), leyendo de corrido   1812 KB/s
///     lo mismo desde el medio, tras un salto            1789 KB/s
///     un trozo cerrado de 1 MB                           514 KB/s
///     un trozo cerrado de 256 KB                         171 KB/s
///
/// La fuente tarda cerca de un segundo y medio en empezar a contestar y recién
/// ahí toma velocidad. O sea que lo que hunde el caudal no es el ancho de banda
/// sino CUÁNTOS pedidos se hacen. A mpv le entraban 109-119 KB/s con un archivo
/// que necesita 206, y la imagen quedaba congelada con el colchón clavado en
/// 2,7 s: nunca llegaba a los 3 s que pide `cache-pause-wait`.
///
/// Esto se pone en el medio y da vuelta la ecuación: mantiene una lectura
/// abierta contra la fuente y le va entregando al reproductor los tramos que
/// pida, sin volver a pedir nada río arriba mientras siga leyendo hacia
/// adelante. El reproductor pide de a poco, como siempre; la fuente entrega de
/// corrido, que es lo único que sabe hacer rápido.
///
/// ── Por qué no está dentro del relay local ──────────────────────────────────
///
/// [RelayLocal] sirve para lo mismo por fuera —un servidor local que hace de
/// intermediario— pero reenvía el `Range` tal cual río arriba, que es
/// justamente lo que acá no sirve, y comparte servidor, cliente HTTP y estado
/// con el rodeo de nodos caídos. Metiendo esto adentro, cualquier error de acá
/// podría llevárselo puesto. Van separados a propósito.
///
/// ── Qué pasa si algo falla ──────────────────────────────────────────────────
///
/// Se sirve como siempre: se le pide a la fuente el mismo tramo que pidió el
/// reproductor y se reenvía. Se pierde la ventaja, no la reproducción.
class BombaDeDatos {
  BombaDeDatos._();

  /// Con qué se sale cuando la extensión no manda User-Agent.
  ///
  /// El que pone dart:io por defecto (`Dart/x.y`) lo rechazan varios CDNs.
  static const _uaPorDefecto =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  /// Cuánto se le aguanta a la fuente al abrir y en cada bloque.
  ///
  /// Generoso a propósito: estas fuentes tardan más de un segundo solo en
  /// arrancar, y cortar temprano sería provocar justo el pedido de más que se
  /// está tratando de evitar.
  static const _plazo = Duration(seconds: 20);

  /// Cuántos bytes conviene TIRAR antes que abrir una lectura nueva.
  ///
  /// Sale de la medición de arriba: abrir cuesta ~1,5 s, y en ese tiempo una
  /// lectura ya abierta entrega unos 2,7 MB. Por debajo de eso sale más barato
  /// adelantar la lectura descartando bytes que pagar el arranque otra vez.
  static const _saltoTolerable = 2 * 1024 * 1024;

  // ── Cortar la respuesta en tramos: SE PROBÓ Y SE SACÓ ─────────────────────
  //
  // El 2026-08-06 se hizo que la bomba nunca entregara más de 4 MiB de una vez,
  // aunque el reproductor pidiera abierto. La idea era buena sobre el papel: la
  // lectura no se escapaba hacia adelante y el pedido siguiente caía siempre
  // dentro de lo guardado.
  //
  // **Empeoró la reproducción, y en las dos plataformas.** Medido en la
  // computadora, que hasta entonces iba bien: del MB 2,0 al 4,8 en diez
  // segundos, unos 280 KB/s. Cortando la respuesta, el reproductor pierde la
  // única forma que tenía de tirar de corrido —una sola respuesta larga que él
  // consume a su ritmo— y pasa a pedir de a pedacitos otra vez, que es
  // exactamente el problema que la bomba venía a resolver.
  //
  // Queda anotado para no volver a intentarlo. Lo de que la lectura se escapa
  // hacia adelante es cierto y sigue sin resolverse, pero el remedio no es
  // éste: cuesta más de lo que arregla.

  /// Cuánto se espera a una lectura que está terminando de soltarse.
  ///
  /// Menos de lo que cuesta abrir otra (~950 ms medidos), así que esperar
  /// siempre conviene: en el peor caso se pierde esto, y abrir pierde el doble.
  static const _esperaSiEstaOcupada = Duration(milliseconds: 400);

  /// Cuánto de lo ya servido se guarda para poder volver un poco atrás.
  ///
  /// **Sin esto la bomba no servía para nada, y así se vio en vivo.** El
  /// reproductor corta la respuesta en cuanto llenó lo suyo, pero para entonces
  /// nosotros ya leímos más de lo que él alcanzó a recibir —lo que quedó en los
  /// búferes de salida y del socket—, así que la lectura queda ADELANTADA. El
  /// pedido siguiente cae unos cientos de KB atrás, ninguna lectura sirve
  /// (adelantar se puede, retroceder no) y se reabre. Medido el 2026-08-06 con
  /// mp4upload: reabría cada 1,4 s, siempre en el mismo MB 2,1, y el caudal se
  /// quedó igual de mal que sin bomba — 115 KB/s.
  ///
  /// Guardando lo último servido, ese pedido "de atrás" se contesta de memoria
  /// y se sigue con la MISMA lectura.
  ///
  /// **Cuatro megas y no dos.** Con dos alcanzaba en la computadora, pero el
  /// registro de Android del 2026-08-06 mostró pedidos que caían hasta 1,15 MB
  /// POR DETRÁS de la ventana — o sea, la lectura iba más de tres megas
  /// adelantada. Los avisos «faltan 1157747 bytes más atrás», «faltan 299065»,
  /// «faltan 40657» son todos de esos. Con cuatro entran.
  ///
  /// Son hasta 12 MiB con las tres lecturas abiertas. Al lado de los 96 MiB que
  /// ya usa el reproductor en el teléfono, es barato para lo que evita.
  static const _retenido = 4 * 1024 * 1024;

  /// Cuántas lecturas abiertas se mantienen a la vez para un mismo archivo.
  ///
  /// Con una sola alcanzaría si el archivo se leyera siempre de corrido. Pero un
  /// MP4 con el audio entero al final se lee alternando entre DOS zonas muy
  /// lejanas —medido en FuegoCine: vídeo del MB 0 al 568, audio del 568 al
  /// 608—, y ahí una sola lectura se estaría reabriendo en cada cambio, que es
  /// exactamente lo que se quiere evitar. Con tres entran las dos zonas y sobra
  /// una, y de mp4upload todavía no se sabe en cuál de los dos casos cae.
  static const _bombasALaVez = 3;

  static HttpServer? _servidor;
  static Future<HttpServer>? _arranque;
  static final Map<String, _Archivo> _archivos = {};
  static int _correlativo = 0;

  /// UN solo cliente para todo, reusado entre pedidos: así dart:io mantiene las
  /// conexiones vivas en vez de saludar de nuevo en cada tramo.
  static final HttpClient _cliente = HttpClient()
    // Passthrough fiel: si se descomprimiera acá y se reenviara el
    // content-encoding de la fuente, el reproductor intentaría descomprimir de
    // nuevo algo que ya viene descomprimido.
    ..autoUncompress = false
    ..maxConnectionsPerHost = 4
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 15);

  /// Deja el archivo listo y devuelve la dirección local para el reproductor.
  ///
  /// Devuelve null si el servidor local no se pudo levantar: ahí quien llama
  /// abre la dirección de siempre y no se pierde nada.
  static Future<String?> registrar({
    required String url,
    Map<String, String>? cabeceras,
  }) async {
    try {
      final servidor = await _levantar();
      final token = '${DateTime.now().microsecondsSinceEpoch}-${++_correlativo}';
      _archivos[token] = _Archivo(url, cabeceras ?? const {});
      // Loopback y nada más: esto es para el reproductor de este equipo.
      // Anunciar la LAN sería servir el vídeo a toda la casa sin ningún
      // motivo.
      return 'http://127.0.0.1:${servidor.port}/bomba/$token';
    } catch (e) {
      logger.info('bomba · no se pudo levantar el servidor local: $e');
      return null;
    }
  }

  /// Suelta un archivo y cierra sus lecturas abiertas.
  ///
  /// Hay que llamarlo sí o sí al cambiar de fuente: cada lectura abierta es un
  /// socket contra la fuente que nadie más va a cerrar.
  static void soltar(String? direccionLocal) {
    if (direccionLocal == null) return;
    final partes = Uri.tryParse(direccionLocal)?.pathSegments;
    if (partes == null || partes.length < 2) return;
    _archivos.remove(partes[1])?.cerrar();
    _cerrarSiSobra();
  }

  static Future<HttpServer> _levantar() async {
    final ya = _servidor;
    if (ya != null) return ya;
    final futuro =
        _arranque ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final servidor = await futuro;
    if (_servidor == null) {
      _servidor = servidor;
      servidor.listen(
        (pedido) => unawaited(_atender(pedido)),
        onError: (Object e) => logger.info('bomba · el servidor local falló: $e'),
      );
      logger.info('bomba · servidor local escuchando en '
          '127.0.0.1:${servidor.port}');
    }
    return _servidor!;
  }

  /// Cierra el servidor cuando ya no queda nada que servir, para no dejar un
  /// puerto escuchando toda la vida de la app.
  static void _cerrarSiSobra() {
    if (_archivos.isNotEmpty) return;
    final servidor = _servidor;
    if (servidor == null) return;
    _servidor = null;
    _arranque = null;
    // Sin force: si justo hay una respuesta a medio mandar, se la deja
    // terminar en vez de cortarla por la mitad.
    unawaited(servidor.close().catchError((Object e) {
      logger.info('bomba · no se pudo cerrar el servidor local: $e');
      return servidor;
    }));
  }

  static Future<void> _atender(HttpRequest pedido) async {
    final res = pedido.response;
    final partes = pedido.uri.pathSegments;
    final archivo = partes.length >= 2 && partes[0] == 'bomba'
        ? _archivos[partes[1]]
        : null;
    if (archivo == null) {
      res.statusCode = HttpStatus.notFound;
      await _cerrarCallando(res);
      return;
    }
    try {
      // El HEAD y los `Range` raros (los de sufijo, los múltiples) van por el
      // camino de siempre: son cuatro pedidos contados y no vale la pena
      // atenderlos desde una lectura abierta.
      if (pedido.method == 'GET') {
        final rango = _Rango.de(pedido.headers.value(HttpHeaders.rangeHeader));
        if (rango != null && await _servirConLaBomba(archivo, rango, res)) {
          return;
        }
      }
      await _servirComoSiempre(archivo, pedido, res);
    } catch (e) {
      // Que el reproductor corte la conexión es lo NORMAL cada vez que salta de
      // posición: no es un fallo y no ensucia el registro.
      if (!_esUnCorteDelReproductor(e)) {
        logger.info('bomba · no se pudo servir el tramo: $e');
      }
      await _cerrarCallando(res);
    }
  }

  /// Sirve el tramo desde una lectura abierta.
  ///
  /// Devuelve false **sin haber escrito nada** cuando no se puede hacer por acá;
  /// ahí quien llama sigue por el camino de siempre. Una vez que empezó a
  /// escribir ya no puede volverse atrás, así que a partir de ese punto los
  /// fallos se propagan como excepción.
  static Future<bool> _servirConLaBomba(
      _Archivo archivo, _Rango rango, HttpResponse res) async {
    var bomba = archivo.bombaPara(rango.inicio);
    // La que sirve está todavía terminando de soltarse: el reproductor corta y
    // vuelve a pedir casi al instante, y llegar un pelo temprano no puede
    // costar los 950 ms de abrir otra. Se la espera un momento.
    if (bomba == null && archivo.hayOcupadaPara(rango.inicio)) {
      final hasta = DateTime.now().add(_esperaSiEstaOcupada);
      while (bomba == null &&
          DateTime.now().isBefore(hasta) &&
          archivo.hayOcupadaPara(rango.inicio)) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
        bomba = archivo.bombaPara(rango.inicio);
      }
    }
    if (bomba == null) {
      // POR QUÉ no sirvió ninguna, no solo que no sirvió. Sin esto, un registro
      // lleno de "lectura abierta" no dice si es que el reproductor saltó lejos,
      // si estaban todas ocupadas o si quedaron adelantadas — y son tres
      // problemas distintos con tres arreglos distintos.
      logger.info('bomba · hay que reabrir para el byte ${rango.inicio}: '
          '${archivo.porQueNinguna(rango.inicio)}');
      bomba = await _abrir(archivo, rango.inicio);
      if (bomba == null) return false;
    }
    // Se reserva ANTES de cualquier espera: si entra otro pedido mientras este
    // se prepara, no puede llevarse la misma lectura por delante.
    bomba.ocupada = true;
    // **Quién suelta la reserva, y por qué importa tanto.**
    //
    // Si la entrega llegó a arrancar, la suelta ELLA al terminar del todo, no
    // este `finally`. Medido en Android el 2026-08-06: soltándola acá, la
    // lectura quedaba libre mientras su generador todavía estaba esperando un
    // bloque de la fuente. El pedido siguiente la agarraba, pedía otro bloque, y
    // se juntaban dos lecturas sobre el mismo sitio — «Bad state: Already
    // waiting for next», 29 veces en un episodio. Cada una mataba la lectura y
    // obligaba a reabrir, que es justo lo que la bomba existe para evitar.
    //
    // Pasa en el teléfono y no en la computadora porque allá los bloques tardan
    // más en llegar, así que la ventana entre «terminó de entregar» y «terminó
    // de leer» es mucho más ancha.
    var laSueltaLaEntrega = false;
    try {
      // Venía un poco atrasada: se la adelanta tirando lo que sobra, que cuesta
      // menos que volver a abrir (ver _saltoTolerable).
      if (bomba.posicion < rango.inicio) {
        final tirados = rango.inicio - bomba.posicion;
        if (!await bomba.adelantarHasta(rango.inicio)) {
          bomba.viva = false;
          return false;
        }
        logger.info('bomba · se adelantó ${(tirados / 1024).round()} KiB para '
            'llegar al byte ${rango.inicio} sin volver a abrir');
      }

      final total = bomba.total;
      var ultimo =
          (rango.fin == null || rango.fin! >= total) ? total - 1 : rango.fin!;
      if (rango.inicio > ultimo) return false;
      final cuantos = ultimo - rango.inicio + 1;

      res.statusCode = rango.pedido ? HttpStatus.partialContent : HttpStatus.ok;
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      res.headers.set(HttpHeaders.contentTypeHeader, bomba.tipo);
      if (rango.pedido) {
        res.headers.set(HttpHeaders.contentRangeHeader,
            'bytes ${rango.inicio}-$ultimo/$total');
      }
      res.headers.contentLength = cuantos;
      // Desde acá la reserva es de la entrega: la suelta su propio `finally`,
      // que corre recién cuando el generador terminó de verdad — incluida la
      // espera del bloque que estuviera en vuelo.
      laSueltaLaEntrega = true;
      await res.addStream(bomba.entregar(rango.inicio, cuantos));
      await res.close();
      return true;
    } finally {
      if (!laSueltaLaEntrega) bomba.soltar();
    }
  }

  /// El camino de siempre: se le pide a la fuente lo mismo que pidió el
  /// reproductor y se reenvía tal cual.
  static Future<void> _servirComoSiempre(
      _Archivo archivo, HttpRequest pedido, HttpResponse res) async {
    final uri = Uri.parse(archivo.url);
    final esHead = pedido.method == 'HEAD';
    final req =
        esHead ? await _cliente.headUrl(uri) : await _cliente.getUrl(uri);
    _ponerCabeceras(req, archivo);
    final rango = pedido.headers.value(HttpHeaders.rangeHeader);
    if (rango != null) req.headers.set(HttpHeaders.rangeHeader, rango);
    final arriba = await req.close().timeout(_plazo);

    res.statusCode = arriba.statusCode;
    arriba.headers.forEach((nombre, valores) {
      // transfer-encoding se recalcula solo; reenviar el de arriba deja la
      // respuesta declarando un troceado que no es el que se está usando.
      if (nombre.toLowerCase() == HttpHeaders.transferEncodingHeader) return;
      res.headers.set(nombre, valores.join(', '));
    });
    if (esHead) {
      await arriba.drain<void>().catchError((Object _) {});
      await res.close();
      return;
    }
    await res.addStream(arriba);
    await res.close();
  }

  /// Abre una lectura nueva desde [desde] y la deja corriendo.
  static Future<_Bomba?> _abrir(_Archivo archivo, int desde) async {
    final reloj = Stopwatch()..start();
    HttpClientResponse? arriba;
    try {
      final req = await _cliente.getUrl(Uri.parse(archivo.url));
      _ponerCabeceras(req, archivo);
      // SIEMPRE abierta hasta el final del archivo, sin importar cuánto pidió
      // el reproductor: es justamente lo que hace que la fuente entregue de
      // corrido en vez de cobrar el arranque en cada tramo.
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$desde-');
      arriba = await req.close().timeout(_plazo);

      if (arriba.statusCode >= 400) {
        logger.info('bomba · la fuente rechazó la lectura desde $desde '
            '(HTTP ${arriba.statusCode}) · se sirve como siempre');
        return null;
      }
      // Contestó 200 a un pedido con desplazamiento: ignoró el `Range` y está
      // mandando desde el byte cero. Servir eso como si empezara en `desde`
      // entregaría el archivo corrido, o sea vídeo roto.
      if (arriba.statusCode == HttpStatus.ok && desde != 0) {
        logger.info('bomba · la fuente ignoró el rango (HTTP 200 pidiendo '
            'desde $desde) · se sirve como siempre');
        return null;
      }
      final total = _tamanoTotal(arriba);
      // Sin saber cuánto mide no se puede declarar el largo, y sin largo el
      // reproductor no puede saltar dentro del archivo.
      if (total == null) {
        logger.info('bomba · la fuente no dice cuánto mide el archivo · se '
            'sirve como siempre');
        return null;
      }

      final bomba = _Bomba(
        desde,
        arriba,
        total,
        // mp4upload no declara `video/mp4` sino `application/octet-stream`, y
        // el reproductor lo toma igual: se reenvía lo que dijo la fuente en vez
        // de inventarle un tipo.
        arriba.headers.contentType?.toString() ?? 'application/octet-stream',
      );
      arriba = null; // Ya es de la bomba: no hay que drenarla acá.
      archivo.sumar(bomba, _bombasALaVez);
      logger.info('bomba · lectura abierta en el MB '
          '${(desde / 1024 / 1024).toStringAsFixed(1)} de '
          '${(total / 1024 / 1024).toStringAsFixed(1)} · '
          '${reloj.elapsedMilliseconds} ms · '
          '${archivo.bombas.length} abierta(s)');
      return bomba;
    } catch (e) {
      logger.info('bomba · no se pudo abrir la lectura desde $desde: $e');
      return null;
    } finally {
      // Lo que no llegó a ser una bomba hay que drenarlo, o la conexión queda a
      // medio usar y no vuelve al pozo.
      final suelta = arriba;
      if (suelta != null) {
        unawaited(suelta.drain<void>().catchError((Object _) {}));
      }
    }
  }

  static void _ponerCabeceras(HttpClientRequest req, _Archivo archivo) {
    archivo.cabeceras.forEach((k, v) => req.headers.set(k, v));
    if (!archivo.cabeceras.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      req.headers.set(HttpHeaders.userAgentHeader, _uaPorDefecto);
    }
  }

  /// Cuánto mide el archivo entero, según lo que haya dicho la fuente.
  static int? _tamanoTotal(HttpClientResponse res) {
    final rango = res.headers.value(HttpHeaders.contentRangeHeader);
    if (rango != null) {
      // `bytes 1000-2999/5000` — lo que interesa es lo de después de la barra.
      final m = RegExp(r'/\s*(\d+)\s*$').firstMatch(rango.trim());
      final total = m == null ? null : int.tryParse(m.group(1)!);
      if (total != null && total > 0) return total;
    }
    if (res.statusCode == HttpStatus.ok && res.contentLength > 0) {
      return res.contentLength;
    }
    return null;
  }

  /// Si el error es del reproductor cortando la conexión, que es lo esperable.
  static bool _esUnCorteDelReproductor(Object e) =>
      e is SocketException || e is HttpException || e is StateError;

  static Future<void> _cerrarCallando(HttpResponse res) async {
    try {
      await res.close();
    } catch (_) {
      // La respuesta ya estaba cerrada o el otro lado se fue: no hay nada que
      // hacer ni nada que contar.
    }
  }
}

/// Un archivo remoto y las lecturas que se le tienen abiertas.
class _Archivo {
  _Archivo(this.url, this.cabeceras);
  final String url;
  final Map<String, String> cabeceras;
  final List<_Bomba> bombas = [];

  /// La lectura que mejor sirve para empezar a entregar desde [inicio].
  ///
  /// Sirve una lectura cuando [inicio] cae en cualquiera de estos dos lados:
  ///
  ///  - **un poco adelante** de donde va: se adelanta tirando bytes, que cuesta
  ///    menos que volver a abrir mientras no pase de `_saltoTolerable`;
  ///  - **un poco atrás**, pero dentro de lo que todavía está guardado: ese
  ///    tramo se contesta de memoria y después se sigue con la misma lectura.
  ///
  /// El segundo caso es el que hace que esto funcione: el reproductor casi
  /// siempre vuelve a pedir un poco atrás de donde quedó la lectura (ver
  /// `_retenido`). Sin él, ninguna lectura se reusaba nunca.
  ///
  /// Entre varias posibles gana la que menos bytes obligue a tirar.
  _Bomba? bombaPara(int inicio) {
    _Bomba? elegida;
    var mejor = 0;
    for (final b in bombas) {
      if (!b.viva || b.ocupada) continue;
      if (inicio < b.primerByteGuardado) continue;
      final tirar = inicio - b.posicion;
      if (tirar > BombaDeDatos._saltoTolerable) continue;
      // Volver atrás no cuesta nada: sale de memoria.
      final cuesta = tirar < 0 ? 0 : tirar;
      if (elegida == null || cuesta < mejor) {
        elegida = b;
        mejor = cuesta;
      }
    }
    return elegida;
  }

  /// Si hay una que serviría pero está entregando otra cosa en este momento.
  bool hayOcupadaPara(int inicio) => bombas.any((b) =>
      b.viva &&
      b.ocupada &&
      inicio >= b.primerByteGuardado &&
      inicio - b.posicion <= BombaDeDatos._saltoTolerable);

  /// Por qué ninguna lectura pudo con este pedido, para poder leerlo después.
  String porQueNinguna(int inicio) {
    if (bombas.isEmpty) return 'no había ninguna abierta';
    return bombas.map((b) {
      if (!b.viva) return 'una muerta';
      if (b.ocupada) return 'una ocupada (va en ${b.posicion})';
      if (inicio < b.primerByteGuardado) {
        return 'una que ya pasó: va en ${b.posicion} y solo guarda desde '
            '${b.primerByteGuardado}, faltan ${b.primerByteGuardado - inicio} '
            'bytes más atrás';
      }
      return 'una atrasada ${inicio - b.posicion} bytes, más de lo tolerable';
    }).join(' · ');
  }

  /// Suma una lectura y suelta las que sobran.
  ///
  /// Se descartan primero las muertas y después la que hace más rato que no se
  /// usa. Nunca una que esté entregando algo en este momento.
  void sumar(_Bomba nueva, int cuantasCaben) {
    bombas.add(nueva);
    bombas.removeWhere((b) {
      if (b.viva || b.ocupada) return false;
      b.cerrar();
      return true;
    });
    while (bombas.length > cuantasCaben) {
      _Bomba? vieja;
      for (final b in bombas) {
        if (b.ocupada || identical(b, nueva)) continue;
        if (vieja == null || b.usadaEn < vieja.usadaEn) vieja = b;
      }
      if (vieja == null) break;
      bombas.remove(vieja);
      vieja.cerrar();
    }
  }

  void cerrar() {
    for (final b in bombas) {
      b.cerrar();
    }
    bombas.clear();
  }
}

/// Una lectura abierta contra la fuente, que se va sirviendo por tramos.
class _Bomba {
  _Bomba(this.posicion, HttpClientResponse res, this.total, this.tipo)
      : _lector = StreamIterator<List<int>>(res);

  /// El próximo byte del archivo que va a entregar esta lectura.
  int posicion;

  /// Cuánto mide el archivo entero.
  final int total;

  /// El tipo que declaró la fuente, tal cual.
  final String tipo;

  final StreamIterator<List<int>> _lector;

  /// Un pedido a la vez por lectura: dos a la par se pisarían la posición.
  bool ocupada = false;

  /// Se apaga cuando la fuente se acabó o se cortó. Una muerta ya no se elige.
  bool viva = true;

  /// Para poder descartar la que hace más rato que no se usa.
  int usadaEn = DateTime.now().microsecondsSinceEpoch;

  /// Lo que sobró del último bloque leído, para no perderlo entre pedidos.
  Uint8List? _resto;
  int _restoDesde = 0;

  /// Lo último que se sirvió, por si hay que volver un poco atrás. Ver
  /// `_retenido`: es lo que hace que la lectura se pueda reusar de verdad.
  final List<Uint8List> _yaServido = [];
  int _guardados = 0;

  /// El byte más atrás que esta lectura todavía puede entregar.
  int get primerByteGuardado => posicion - _guardados;

  void _guardar(Uint8List trozo) {
    _yaServido.add(trozo);
    _guardados += trozo.length;
    // Se suelta lo más viejo mientras siga quedando lo que se quiere retener.
    while (_yaServido.length > 1 &&
        _guardados - _yaServido.first.length >= BombaDeDatos._retenido) {
      _guardados -= _yaServido.removeAt(0).length;
    }
  }

  /// Los tramos guardados que cubren desde [desde], hasta [tope] bytes.
  Iterable<Uint8List> _deLoGuardado(int desde, int tope) sync* {
    var donde = primerByteGuardado;
    var quedan = tope;
    for (final trozo in _yaServido) {
      if (quedan <= 0) return;
      final fin = donde + trozo.length;
      if (fin > desde) {
        final saltar = desde > donde ? desde - donde : 0;
        final hay = trozo.length - saltar;
        yield hay <= quedan
            ? Uint8List.sublistView(trozo, saltar)
            : Uint8List.sublistView(trozo, saltar, saltar + quedan);
        quedan -= hay <= quedan ? hay : quedan;
      }
      donde = fin;
    }
  }

  /// Suelta la reserva. Ver quién la suelta y cuándo en _servirConLaBomba.
  void soltar() {
    ocupada = false;
    usadaEn = DateTime.now().microsecondsSinceEpoch;
  }

  /// Hay una lectura de la fuente en vuelo ahora mismo.
  bool _leyendo = false;

  /// El próximo trozo, de como mucho [tope] bytes. Null cuando no queda nada.
  ///
  /// NO mueve [posicion] a propósito: eso lo hace quien entrega, para que la
  /// cuenta refleje lo que salió de verdad y no lo que se leyó.
  Future<Uint8List?> _proximo(int tope) async {
    // Red de seguridad. No tendría que poder pasar —la reserva dura hasta que
    // la entrega termina del todo—, pero si pasa es preferible dar esta lectura
    // por perdida a corromperla: dos `moveNext()` encimados rompen el
    // StreamIterator con «Already waiting for next» y el error sale por un lado
    // que no dice nada del motivo.
    if (_leyendo) {
      logger.info('bomba · dos entregas a la vez sobre la misma lectura en '
          '$posicion: se descarta en vez de corromperla');
      viva = false;
      return null;
    }
    _leyendo = true;
    try {
      return await _proximoDeVerdad(tope);
    } finally {
      _leyendo = false;
    }
  }

  Future<Uint8List?> _proximoDeVerdad(int tope) async {
    while (_resto == null) {
      if (!await _lector.moveNext().timeout(BombaDeDatos._plazo)) return null;
      final bloque = _lector.current;
      if (bloque.isEmpty) continue;
      _resto = bloque is Uint8List ? bloque : Uint8List.fromList(bloque);
      _restoDesde = 0;
    }
    final resto = _resto!;
    final hay = resto.length - _restoDesde;
    // Vistas, no copias: por acá pasa TODO el vídeo y cada copia se pagaría en
    // cada bloque.
    if (hay <= tope) {
      final salida = Uint8List.sublistView(resto, _restoDesde);
      _resto = null;
      _restoDesde = 0;
      return salida;
    }
    final salida = Uint8List.sublistView(resto, _restoDesde, _restoDesde + tope);
    _restoDesde += tope;
    return salida;
  }

  /// Adelanta la lectura tirando lo que haya hasta [destino].
  Future<bool> adelantarHasta(int destino) async {
    while (posicion < destino) {
      final trozo = await _proximo(destino - posicion);
      if (trozo == null) return false;
      posicion += trozo.length;
    }
    return posicion == destino;
  }

  /// Entrega [cuantos] bytes a partir de [desde].
  ///
  /// Si [desde] cae detrás de donde va la lectura, ese tramo sale de lo
  /// guardado y recién después se sigue leyendo. Y si el reproductor corta antes
  /// de terminar —lo hace todo el tiempo—, la lectura queda donde estaba y sirve
  /// para el pedido siguiente: eso es todo el punto de esto.
  Stream<List<int>> entregar(int desde, int cuantos) async* {
    // La reserva se suelta ACÁ y no en quien llama.
    //
    // Si el reproductor corta la respuesta, este generador se cancela — pero la
    // cancelación no interrumpe el bloque que ya estaba pidiéndose a la fuente:
    // primero termina esa espera y RECIÉN AHÍ corre este `finally`. Soltando la
    // reserva antes, el pedido siguiente agarraba esta misma lectura mientras
    // seguía leyendo, y se juntaban dos. Ver el detalle en _servirConLaBomba.
    try {
      var quedan = cuantos;
      if (desde < posicion) {
        for (final trozo in _deLoGuardado(desde, quedan)) {
          quedan -= trozo.length;
          yield trozo;
        }
      }
      while (quedan > 0) {
        Uint8List? trozo;
        try {
          trozo = await _proximo(quedan);
        } catch (e) {
          viva = false;
          logger.info('bomba · se cortó la lectura río arriba en $posicion: $e');
          return;
        }
        if (trozo == null) {
          viva = false;
          return;
        }
        posicion += trozo.length;
        quedan -= trozo.length;
        _guardar(trozo);
        yield trozo;
      }
    } finally {
      soltar();
    }
  }

  void cerrar() {
    viva = false;
    unawaited(_lector.cancel().catchError((Object _) {}));
  }
}

/// El tramo que pidió el reproductor.
class _Rango {
  const _Rango(this.inicio, this.fin, this.pedido);

  final int inicio;

  /// El último byte pedido, incluido. Null cuando pidió hasta el final.
  final int? fin;

  /// Si venía cabecera `Range`: sin ella la respuesta va 200 y no 206.
  final bool pedido;

  /// Devuelve null cuando el rango no es de los que se atienden por acá — los
  /// de sufijo (`bytes=-500`) y los múltiples. Esos van por el camino de
  /// siempre, que los resuelve la fuente.
  static _Rango? de(String? cabecera) {
    final texto = cabecera?.trim() ?? '';
    if (texto.isEmpty) return const _Rango(0, null, false);
    final m = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(texto);
    if (m == null) return null;
    final inicio = int.tryParse(m.group(1)!);
    if (inicio == null) return null;
    final hasta = m.group(2)!;
    if (hasta.isEmpty) return _Rango(inicio, null, true);
    final fin = int.tryParse(hasta);
    if (fin == null || fin < inicio) return null;
    return _Rango(inicio, fin, true);
  }
}
