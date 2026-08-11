import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:prismhub/utils/log.dart';

/// Sirve una lista HLS de pedacitos **fMP4** como si fuera UN archivo.
///
/// ── Para qué ────────────────────────────────────────────────────────────────
///
/// Porque el reproductor **no puede adelantar** en este tipo de listas, y no es
/// algo que se pueda ajustar: es un fallo de ffmpeg, reportado contra el propio
/// ejemplo oficial de Apple y **cerrado sin arreglo**:
///
///   mpv-player/mpv#15184 — «HLS MP4 Video seek freezes with invalid NAL unit
///   size errors», etiquetado `down-upstream:ffmpeg`, "not planned".
///
/// Reproduce impecable de corrido y al saltar a una zona todavía no cargada se
/// congela. Se probaron nueve caminos por el lado de las opciones del
/// reproductor y ninguno sirvió — era esperable, el fallo no está ahí.
///
/// ── Cómo lo esquiva ─────────────────────────────────────────────────────────
///
/// Si el reproductor nunca abre esto **como lista**, nunca entra en ese código.
/// Así que se le entrega un archivo: la cabecera del `#EXT-X-MAP` seguida de
/// todos los pedacitos, uno atrás del otro. Eso **es** un fMP4 válido —medido:
/// da `ftyp moov` + un `styp/sidx/moof/mdat` por pedacito, sin cajas cortadas—
/// y **no se recodifica nada**, los bytes salen tal cual llegan.
///
/// Desde ahí, adelantar es pedir un tramo de un archivo, que es lo que el
/// reproductor hace todos los días.
///
/// ── El truco para saber cuánto pesa sin bajarlo ─────────────────────────────
///
/// Para servir un archivo hay que declarar su tamaño, y estos pedacitos no lo
/// dicen: vienen `Transfer-Encoding: chunked`, sin `Content-Length`, y encima
/// **ignoran los rangos** (se les pide un tramo y mandan el archivo entero).
///
/// Pero cada uno lleva un `sidx` en los primeros bytes que declara **su tamaño
/// exacto y su duración**. Así que se abre la conexión, se leen unos 6 KB y se
/// corta. Medido: 8 de 8 lo entregan así, y el total del episodio son unos
/// 850 KB en vez de medio giga.
///
/// ── Y por qué no bloquea la apertura ────────────────────────────────────────
///
/// De a uno serían 26 s, que es inaceptable antes de reproducir. Van en
/// paralelo, con un tope de tiempo: si no se llega, se devuelve null y la app
/// abre la fuente como siempre. **Nunca deja al usuario esperando ni sin
/// vídeo.**
class HlsFmp4AArchivo {
  static HttpServer? _servidor;
  static final Map<String, _Sesion> _sesiones = {};

  static final HttpClient _cliente = HttpClient()
    ..maxConnectionsPerHost = 8
    ..idleTimeout = const Duration(seconds: 30);

  /// Cuántos pedacitos se miden a la vez. Ocho es lo que aguanta el CDN sin
  /// ponerse a cortar respuestas (medido: con ráfagas mayores empieza a
  /// devolver pedacitos a medias).
  static const _deAVarios = 8;

  /// Tope para tener el archivo listo. Pasado esto se abandona y la app abre la
  /// fuente como siempre: más vale reproducir sin poder adelantar que hacer
  /// esperar mirando una rueda.
  static const _tope = Duration(seconds: 12);

  /// ¿Esta lista es de pedacitos fMP4, o sea de las que no se pueden adelantar?
  static bool esDeLasQueNoSaltan(String lista) => lista.contains('#EXT-X-MAP');

  /// Prepara el archivo y devuelve la dirección local, o null si no se pudo.
  ///
  /// Ante cualquier problema devuelve null y el que llama sigue como siempre.
  static Future<String?> preparar({
    required String listaUrl,
    required String lista,
    required Map<String, String> cabeceras,
  }) async {
    try {
      final base = Uri.parse(listaUrl);
      final mapa = RegExp(r'#EXT-X-MAP:URI="([^"]+)"').firstMatch(lista)?.group(1);
      if (mapa == null) return null;

      final trozos = <Uri>[];
      for (final linea in lista.split('\n')) {
        final l = linea.trim();
        if (l.isEmpty || l.startsWith('#')) continue;
        trozos.add(base.resolve(l));
      }
      if (trozos.isEmpty) return null;

      final inicio = await _bajarEntero(base.resolve(mapa), cabeceras);
      if (inicio == null || inicio.isEmpty) return null;

      final tamanos = await _medirTodos(trozos, cabeceras);
      if (tamanos == null) return null;

      // Dónde arranca cada pedacito dentro del archivo, para poder traducir un
      // tramo pedido a los pedacitos que lo contienen.
      final desde = <int>[];
      var acumulado = inicio.length;
      for (final t in tamanos) {
        desde.add(acumulado);
        acumulado += t;
      }

      final ficha = _iniciarServidor();
      final servidor = await ficha;
      if (servidor == null) return null;

      final token = '${DateTime.now().microsecondsSinceEpoch}'
          '${Random().nextInt(99999)}';
      _sesiones[token] = _Sesion(
        inicio: inicio,
        trozos: trozos,
        tamanos: tamanos,
        desde: desde,
        total: acumulado,
        cabeceras: cabeceras,
      );
      logger.info('fMP4 a archivo: ${trozos.length} pedacitos · '
          '${(acumulado / 1048576).toStringAsFixed(1)} MB · listo para adelantar');
      return 'http://127.0.0.1:${servidor.port}/fmp4/$token.mp4';
    } catch (e) {
      logger.info('fMP4 a archivo: no se pudo preparar, se abre como siempre: $e');
      return null;
    }
  }

  /// Suelta una sesión y lo que tenía guardado.
  static void soltar(String? url) {
    if (url == null) return;
    final token = RegExp(r'/fmp4/([^.]+)\.mp4').firstMatch(url)?.group(1);
    if (token != null) _sesiones.remove(token);
  }

  // ── El tamaño de cada pedacito, sin bajarlo ───────────────────────────────

  static Future<List<int>?> _medirTodos(
    List<Uri> trozos,
    Map<String, String> cabeceras,
  ) async {
    final reloj = Stopwatch()..start();
    final tamanos = List<int>.filled(trozos.length, 0);
    for (var i = 0; i < trozos.length; i += _deAVarios) {
      if (reloj.elapsed > _tope) {
        logger.info('fMP4 a archivo: se pasó de ${_tope.inSeconds} s midiendo, '
            'se abre como siempre');
        return null;
      }
      final hasta = min(i + _deAVarios, trozos.length);
      final tanda = <Future<void>>[];
      for (var j = i; j < hasta; j++) {
        final n = j;
        tanda.add(() async {
          tamanos[n] = await _medirUno(trozos[n], cabeceras);
        }());
      }
      await Future.wait(tanda);
    }
    if (tamanos.any((t) => t <= 0)) {
      logger.info('fMP4 a archivo: algún pedacito no dijo su tamaño, se abre '
          'como siempre');
      return null;
    }
    logger.info('fMP4 a archivo: medidos ${trozos.length} pedacitos en '
        '${reloj.elapsedMilliseconds} ms');
    return tamanos;
  }

  /// Abre, lee lo justo para ver el `sidx` y corta.
  static Future<int> _medirUno(Uri url, Map<String, String> cabeceras) async {
    HttpClientResponse? res;
    try {
      final req = await _cliente.getUrl(url);
      cabeceras.forEach(req.headers.set);
      res = await req.close();
      final buf = BytesBuilder();
      await for (final trozo in res) {
        buf.add(trozo);
        if (buf.length >= 8192) break;
      }
      return _tamanoDelPedacito(buf.toBytes());
    } catch (_) {
      return 0;
    } finally {
      // Cortar: no interesa el resto del pedacito.
      unawaited(res?.detachSocket().then((s) => s.destroy()).catchError((_) {}));
    }
  }

  /// Cuánto ocupa el pedacito entero, leyendo solo su cabeza.
  ///
  /// Un pedacito de estos viene así: `styp` · `sidx` · `sidx` · `moof` · `mdat`.
  /// El primer `sidx` declara en `referenced_size` cuánto ocupa el contenido,
  /// **pero medido desde el final del ÚLTIMO índice**, no desde el principio
  /// del archivo. Por eso hay que sumarle todo lo que va antes.
  ///
  /// Comprobado contra el tamaño real de tres pedacitos, y da EXACTO:
  ///
  ///   fin del último sidx (128) + referenced_size (3.270.459) = 3.270.587
  ///
  /// **Ojo con quedarse en el primer índice**: son dos, y el segundo ocupa 52
  /// bytes. Contando solo hasta el primero, cada pedacito sale 52 bytes corto y
  /// el archivo entero queda mal armado — pasó, y el vídeo salía con una
  /// duración de diez segundos.
  static int _tamanoDelPedacito(Uint8List b) {
    final d = ByteData.sublistView(b);
    var off = 0;
    var refPrimero = 0;
    var finDeIndices = 0;
    while (off + 8 <= b.length) {
      final sz = d.getUint32(off);
      if (sz < 8 || off + sz > b.length) break;
      final tipo = String.fromCharCodes(b.sublist(off + 4, off + 8));
      if (tipo == 'sidx') {
        if (refPrimero == 0) {
          final version = b[off + 8];
          var p = off + 20; // tamaño+tipo+version/flags+referenceID+timescale
          p += version == 0 ? 8 : 16; // earliest_presentation_time+first_offset
          p += 2; // reservado
          p += 2; // cuántas referencias
          if (p + 4 > b.length) return 0;
          // El bit de arriba dice si la referencia es a otro índice; el resto
          // es el tamaño.
          refPrimero = d.getUint32(p) & 0x7fffffff;
        }
        finDeIndices = off + sz;
      } else if (finDeIndices > 0) {
        // Ya pasaron los índices: acá empieza el contenido.
        break;
      }
      off += sz;
    }
    if (refPrimero == 0 || finDeIndices == 0) return 0;
    return finDeIndices + refPrimero;
  }

  static Future<Uint8List?> _bajarEntero(
    Uri url,
    Map<String, String> cabeceras,
  ) async {
    try {
      final req = await _cliente.getUrl(url);
      cabeceras.forEach(req.headers.set);
      final res = await req.close();
      final buf = BytesBuilder();
      await for (final t in res) {
        buf.add(t);
      }
      return buf.toBytes();
    } catch (_) {
      return null;
    }
  }

  // ── El servidor local ─────────────────────────────────────────────────────

  static Future<HttpServer?>? _arrancando;

  static Future<HttpServer?> _iniciarServidor() {
    final yaEsta = _servidor;
    if (yaEsta != null) return Future.value(yaEsta);
    return _arrancando ??= () async {
      try {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        s.listen(_atender);
        _servidor = s;
        return s;
      } catch (e) {
        logger.info('fMP4 a archivo: no se pudo levantar el servidor local: $e');
        return null;
      }
    }();
  }

  static Future<void> _atender(HttpRequest req) async {
    final token = RegExp(r'/fmp4/([^.]+)\.mp4').firstMatch(req.uri.path)?.group(1);
    final s = token == null ? null : _sesiones[token];
    if (s == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    // Qué tramo pidió. Sin tramo, se sirve entero desde el principio.
    var inicio = 0;
    var fin = s.total - 1;
    final rango = req.headers.value(HttpHeaders.rangeHeader);
    final m = rango == null
        ? null
        : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rango);
    final parcial = m != null && (m.group(1)!.isNotEmpty || m.group(2)!.isNotEmpty);
    if (parcial) {
      if (m.group(1)!.isNotEmpty) inicio = int.parse(m.group(1)!);
      if (m.group(2)!.isNotEmpty) fin = int.parse(m.group(2)!);
    }
    if (inicio < 0 || inicio >= s.total) {
      req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await req.response.close();
      return;
    }
    if (fin >= s.total) fin = s.total - 1;

    final r = req.response;
    r.statusCode = parcial ? HttpStatus.partialContent : HttpStatus.ok;
    r.headers
      ..set(HttpHeaders.contentTypeHeader, 'video/mp4')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentLengthHeader, '${fin - inicio + 1}');
    if (parcial) {
      r.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $inicio-$fin/${s.total}',
      );
    }

    try {
      await for (final trozo in s.leer(inicio, fin, _cliente)) {
        r.add(trozo);
      }
      await r.close();
    } catch (_) {
      // El reproductor cortó (pasa en cada salto): no es un error.
      try {
        await r.close();
      } catch (_) {}
    }
  }
}

class _Sesion {
  _Sesion({
    required this.inicio,
    required this.trozos,
    required this.tamanos,
    required this.desde,
    required this.total,
    required this.cabeceras,
  });

  final Uint8List inicio;
  final List<Uri> trozos;
  final List<int> tamanos;
  final List<int> desde;
  final int total;
  final Map<String, String> cabeceras;

  /// Sirve el tramo pedido, bajando solo los pedacitos que hacen falta.
  Stream<List<int>> leer(int desdeByte, int hastaByte, HttpClient cliente) async* {
    var cursor = desdeByte;

    // La cabecera, si el tramo la incluye.
    if (cursor < inicio.length) {
      final hasta = min(hastaByte, inicio.length - 1);
      yield inicio.sublist(cursor, hasta + 1);
      cursor = hasta + 1;
    }

    while (cursor <= hastaByte) {
      final i = _cualToca(cursor);
      if (i < 0) return;
      final arranca = desde[i];
      final bytes = await _bajar(trozos[i], cliente);
      if (bytes == null) return;
      final dentroDesde = cursor - arranca;
      if (dentroDesde >= bytes.length) return;
      final dentroHasta = min(hastaByte - arranca, bytes.length - 1);
      yield bytes.sublist(dentroDesde, dentroHasta + 1);
      cursor = arranca + dentroHasta + 1;
    }
  }

  /// Qué pedacito contiene este byte. Búsqueda binaria: son cientos.
  int _cualToca(int byte) {
    var lo = 0, hi = desde.length - 1, res = -1;
    while (lo <= hi) {
      final medio = (lo + hi) >> 1;
      if (desde[medio] <= byte) {
        res = medio;
        lo = medio + 1;
      } else {
        hi = medio - 1;
      }
    }
    return res;
  }

  Future<Uint8List?> _bajar(Uri url, HttpClient cliente) async {
    try {
      final req = await cliente.getUrl(url);
      cabeceras.forEach(req.headers.set);
      final res = await req.close();
      final buf = BytesBuilder();
      await for (final t in res) {
        buf.add(t);
      }
      return buf.toBytes();
    } catch (_) {
      return null;
    }
  }
}
