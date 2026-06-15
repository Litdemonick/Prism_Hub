import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:logging/logging.dart';

/// Proxy HLS/streaming local (solo loopback) que **garantiza** que las cabeceras
/// de resolución (Referer, Origin, User-Agent, Cookie…) lleguen a *cada* request
/// del reproductor — incluidos los segmentos `.ts`, las sub-playlists, las claves
/// `EXT-X-KEY` y los `EXT-X-MAP`.
///
/// Por qué hace falta: media_kit/libmpv aplica `http-header-fields` de forma
/// global y, en algunas plataformas, no las propaga de forma fiable al demuxer
/// HLS de ffmpeg. Resultado: el CDN devuelve 403 en los segmentos y el vídeo se
/// queda en buffering infinito. El proxy reescribe el playlist para que todo
/// vuelva a pasar por aquí con las cabeceras correctas.
///
/// Mejoras sobre el proxy de Miru:
///   • Política de cabeceras por-host ([_headersForHost]) — extensible para
///     CDNs que rechazan ciertos Referer/Origin.
///   • HLS cifrado AES-128 de primera clase: las URIs de `EXT-X-KEY` también se
///     enrutan con cabeceras, así los streams cifrados se reproducen.
///   • Streaming de segmentos (sin bufferizar en memoria) → bajo consumo de RAM.
///   • Cookie jar de sesión compartido entre el playlist y sus segmentos.
abstract final class HlsProxyService {
  static final _log = Logger('HlsProxyService');

  static HttpServer? _server;
  static int _port = 0;

  // Dio dedicado con cookie jar de sesión (en memoria): las cookies que ponga
  // el playlist se reenvían en los segmentos durante la reproducción.
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (_) => true,
    ),
  )..interceptors.add(CookieManager(CookieJar()));

  /// Devuelve una URL reproducible. **Todos** los HLS (.m3u8) se enrutan por el
  /// proxy local, traigan cabeceras o no. Motivo: media_kit/libmpv usa mbedtls y
  /// un User-Agent no-navegador para los segmentos, y muchos CDN responden 403 o
  /// rechazan el TLS. El proxy los baja con el Dio de Dart (TLS bueno) + un
  /// User-Agent de navegador + Referer, garantizando que reproduzcan.
  /// Los mp4 directos no se tocan (media_kit los abre bien en una sola petición).
  static Future<String> resolve(
    String url,
    Map<String, String>? headers,
  ) async {
    if (!url.contains('.m3u8')) return url;

    try {
      await start();
      return _proxyUrl(url, headers ?? const {});
    } catch (e) {
      _log.warning('No se pudo enrutar por el proxy, usando URL directa: $e');
      return url;
    }
  }

  /// Arranca el servidor loopback una sola vez (idempotente).
  static Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handle, onError: (e) => _log.warning('listen error: $e'));
    _log.info('Proxy HLS escuchando en 127.0.0.1:$_port');
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  // ── Construcción de URLs proxy ──────────────────────────────────────────────

  static String _proxyUrl(String target, Map<String, String> headers) {
    final h = base64Url.encode(utf8.encode(jsonEncode(headers)));
    final u = Uri.encodeComponent(target);
    return 'http://127.0.0.1:$_port/p?u=$u&h=$h';
  }

  // ── Handler ─────────────────────────────────────────────────────────────────

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final target = req.uri.queryParameters['u'];
      final hParam = req.uri.queryParameters['h'];
      if (target == null) {
        res.statusCode = HttpStatus.badRequest;
        await res.close();
        return;
      }

      final url = Uri.decodeComponent(target);
      final headers = _decodeHeaders(hParam);

      // Cabeceras de salida hacia el origen (política por-host) + passthrough de
      // Range para soportar el seek del reproductor.
      final outHeaders = _headersForHost(Uri.parse(url), headers);
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) outHeaders[HttpHeaders.rangeHeader] = range;

      final upstream = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: outHeaders,
          validateStatus: (_) => true,
        ),
      );

      final status = upstream.statusCode ?? HttpStatus.badGateway;
      final contentType = _firstHeader(upstream, HttpHeaders.contentTypeHeader);

      if (_isPlaylist(url, contentType)) {
        // Bufferizar el playlist (texto pequeño), reescribir y devolver.
        final body = await _readAll(upstream.data!.stream);
        final text = utf8.decode(body, allowMalformed: true);
        final rewritten = _rewritePlaylist(text, url, headers);
        res.statusCode = status;
        res.headers.contentType = ContentType.parse(
          'application/vnd.apple.mpegurl',
        );
        res.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
        res.add(utf8.encode(rewritten));
        await res.close();
        return;
      }

      // Segmento / clave / binario: stream directo sin bufferizar.
      res.statusCode = status;
      _copyHeader(upstream, res, HttpHeaders.contentTypeHeader);
      _copyHeader(upstream, res, HttpHeaders.contentLengthHeader);
      _copyHeader(upstream, res, HttpHeaders.contentRangeHeader);
      _copyHeader(upstream, res, HttpHeaders.acceptRangesHeader);
      res.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
      await upstream.data!.stream.forEach(res.add);
      await res.close();
    } catch (e) {
      _log.warning('proxy handler error: $e');
      try {
        res.statusCode = HttpStatus.badGateway;
        await res.close();
      } catch (_) {}
    }
  }

  // ── Reescritura de playlist m3u8 ────────────────────────────────────────────

  static String _rewritePlaylist(
    String playlist,
    String playlistUrl,
    Map<String, String> headers,
  ) {
    final base = Uri.parse(playlistUrl);
    final lines = playlist.split('\n');
    final out = StringBuffer();

    for (final raw in lines) {
      final line = raw.trimRight();

      if (line.isEmpty) {
        out.writeln(line);
        continue;
      }

      if (line.startsWith('#')) {
        // Atributos con URI="..." (EXT-X-KEY, EXT-X-MAP, EXT-X-MEDIA, etc.)
        if (line.contains('URI="')) {
          out.writeln(_rewriteUriAttr(line, base, headers));
        } else {
          out.writeln(line);
        }
        continue;
      }

      // Línea de recurso (segmento o sub-playlist).
      final abs = base.resolve(line).toString();
      out.writeln(_proxyUrl(abs, headers));
    }

    return out.toString();
  }

  static String _rewriteUriAttr(
    String line,
    Uri base,
    Map<String, String> headers,
  ) {
    return line.replaceAllMapped(RegExp(r'URI="([^"]*)"'), (m) {
      final abs = base.resolve(m.group(1)!).toString();
      return 'URI="${_proxyUrl(abs, headers)}"';
    });
  }

  // ── Política de cabeceras por-host ──────────────────────────────────────────
  // Garantiza un User-Agent de navegador (los CDN devuelven 403 al UA de libmpv)
  // y un Referer. Reenvía las cabeceras que ya traiga el stream; completa las que
  // falten. Esto es lo que hace que los segmentos dejen de dar 403.
  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static Map<String, String> _headersForHost(
    Uri target,
    Map<String, String> headers,
  ) {
    final out = Map<String, String>.from(headers);
    // Normalizar claves existentes a su forma canónica para no duplicar.
    final hasUa = out.keys.any((k) => k.toLowerCase() == 'user-agent');
    final hasRef = out.keys.any((k) => k.toLowerCase() == 'referer');
    if (!hasUa) out['User-Agent'] = _browserUa;
    if (!hasRef) out['Referer'] = '${target.scheme}://${target.host}/';
    return out;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Map<String, String> _decodeHeaders(String? h) {
    if (h == null || h.isEmpty) return {};
    try {
      final json = utf8.decode(base64Url.decode(h));
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  static bool _isPlaylist(String url, String? contentType) {
    final ct = contentType?.toLowerCase() ?? '';
    return url.contains('.m3u8') ||
        ct.contains('mpegurl') ||
        ct.contains('vnd.apple.mpegurl');
  }

  static String? _firstHeader(Response r, String name) {
    final v = r.headers.map[name.toLowerCase()];
    return (v == null || v.isEmpty) ? null : v.first;
  }

  static void _copyHeader(Response from, HttpResponse to, String name) {
    final v = _firstHeader(from, name);
    if (v != null) to.headers.set(name, v);
  }

  static Future<List<int>> _readAll(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await stream.forEach(builder.add);
    return builder.takeBytes();
  }
}
