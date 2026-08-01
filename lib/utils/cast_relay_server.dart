import 'dart:async';
import 'dart:io';

import 'package:prismhub/utils/log.dart';
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

  /// Lo último que respondió la fuente cuando rechazó un pedido del relay.
  ///
  /// El aparato que castea solo sabe decir "no se pudo reproducir": el motivo
  /// real (una dirección vencida, un 403 de la fuente) queda del lado nuestro y
  /// sin esto se perdía. Se guarda para poder mostrarlo en el aviso de error.
  static String? ultimoError;

  static Future<Response> _handleRequest(Request request) async {
    final segments = request.url.pathSegments;
    if (segments.length < 2 || segments[0] != 'relay') {
      return Response.notFound('not found');
    }
    final target = _targets[segments[1]];
    if (target == null) return Response.notFound('unknown relay token');

    // El receptor pregunta primero con HEAD (el "Stat" de Kodi) para saber
    // tamaño y tipo antes de bajar nada. Antes se le contestaba SIEMPRE con un
    // GET: se abría la descarga entera del vídeo solo para tirarla, y la
    // respuesta no traía lo que había preguntado.
    final esHead = request.method.toUpperCase() == 'HEAD';
    final client = HttpClient()
      // Passthrough fiel: si se descomprime acá pero se reenvía el
      // content-encoding de la fuente, el receptor intenta descomprimir de
      // nuevo algo que ya viene descomprimido.
      ..autoUncompress = false;
    try {
      final uri = Uri.parse(target.url);
      final upstreamReq =
          esHead ? await client.headUrl(uri) : await client.getUrl(uri);
      target.headers.forEach((key, value) => upstreamReq.headers.set(key, value));
      final range = request.headers['range'];
      if (range != null) upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      final upstreamRes = await upstreamReq.close();

      if (upstreamRes.statusCode >= 400) {
        // Se lee un pedazo del cuerpo porque ahí es donde la fuente explica el
        // motivo ("link expired", "forbidden"...). Sin esto el rechazo llegaba
        // al televisor como un número pelado y no se podía diagnosticar.
        var detalle = '';
        try {
          final trozos = <int>[];
          await for (final t in upstreamRes.timeout(const Duration(seconds: 5))) {
            trozos.addAll(t);
            if (trozos.length >= 400) break;
          }
          detalle = String.fromCharCodes(trozos.take(400))
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        } catch (_) {
          // Sin cuerpo legible el status ya dice bastante.
        }
        client.close(force: true);
        ultimoError = 'La fuente rechazó el vídeo (HTTP '
            '${upstreamRes.statusCode})${detalle.isEmpty ? '' : ': $detalle'}';
        logger.warning('Relay de casteo: $ultimoError — ${target.url}');
        return Response(upstreamRes.statusCode, body: detalle);
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

      if (esHead) {
        client.close(force: true);
        return Response(upstreamRes.statusCode, headers: resHeaders);
      }

      return Response(
        upstreamRes.statusCode,
        // Se cierra el cliente recién cuando el cuerpo terminó de pasar. Antes
        // solo se cerraba al fallar, así que cada pedido dejaba una conexión
        // abierta hasta reiniciar la app.
        body: upstreamRes.transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleDone: (sink) {
              sink.close();
              client.close(force: true);
            },
            handleError: (error, stack, sink) {
              sink.close();
              client.close(force: true);
            },
          ),
        ),
        headers: resHeaders,
      );
    } catch (e) {
      client.close(force: true);
      ultimoError = 'No se pudo alcanzar la fuente del vídeo: $e';
      logger.warning('Relay de casteo: $ultimoError — ${target.url}');
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
