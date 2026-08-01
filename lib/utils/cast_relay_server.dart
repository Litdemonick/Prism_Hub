import 'dart:async';
import 'dart:io';

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

  // Registra una URL+headers y devuelve la URL local (LAN) que hay que
  // pasarle al dispositivo de cast en vez de la real.
  static Future<String> registerAndGetUrl({
    required String targetUrl,
    Map<String, String>? headers,
  }) async {
    await _ensureRunning();
    final token = '${DateTime.now().microsecondsSinceEpoch}';
    _targets[token] = _RelayTarget(targetUrl, headers ?? const {});
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
    return 'http://$ip:$_port/relay/$token';
  }

  static Future<void> _ensureRunning() async {
    if (_server != null) return;
    _server = await shelf_io.serve(_handleRequest, InternetAddress.anyIPv4, 0);
    _port = _server!.port;
  }

  static Future<Response> _handleRequest(Request request) async {
    final segments = request.url.pathSegments;
    if (segments.length < 2 || segments[0] != 'relay') {
      return Response.notFound('not found');
    }
    final target = _targets[segments[1]];
    if (target == null) return Response.notFound('unknown relay token');

    final client = HttpClient();
    try {
      final upstreamReq = await client.getUrl(Uri.parse(target.url));
      target.headers.forEach((key, value) => upstreamReq.headers.set(key, value));
      final range = request.headers['range'];
      if (range != null) upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      final upstreamRes = await upstreamReq.close();

      final resHeaders = <String, String>{};
      upstreamRes.headers.forEach((name, values) {
        // transfer-encoding/content-length quedan mal si el body se
        // re-transmite chunked — dejar que shelf/HttpServer los recalcule.
        final lower = name.toLowerCase();
        if (lower == 'transfer-encoding' || lower == 'content-length') return;
        resHeaders[name] = values.join(', ');
      });

      return Response(
        upstreamRes.statusCode,
        body: upstreamRes,
        headers: resHeaders,
      );
    } catch (e) {
      client.close(force: true);
      return Response.internalServerError(body: 'relay error: $e');
    }
  }

  // Libera la memoria de un target una vez que ya no hace falta (al
  // desconectar el cast) — sin esto los tokens viejos quedan colgados
  // hasta reiniciar la app.
  static void unregister(String relayUrl) {
    final uri = Uri.tryParse(relayUrl);
    if (uri == null || uri.pathSegments.length < 2) return;
    _targets.remove(uri.pathSegments[1]);
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
  _RelayTarget(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
}
