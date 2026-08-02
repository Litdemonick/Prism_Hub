// Comprueba que el reempaquetado de HLS a MPEG-TS produce un vídeo válido.
//
// Es lo que hace posible castear a un televisor que no entiende HLS, así que
// no alcanza con que compile: hay que ver que lo que sale del otro lado sean
// paquetes MPEG-TS de verdad y en orden. Se prueba contra un HLS público real
// (el de ejemplo de Apple, con pedacitos .ts) y no contra uno inventado,
// porque lo que se está verificando es justamente la lectura de una lista de
// las que hay en la calle.
//
// Necesita internet. Si no hay, el test se salta en vez de fallar.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/cast_hls_ts.dart';

const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const _listaReal = 'https://devstreaming-cdn.apple.com/videos/streaming/'
    'examples/img_bipbop_adv_example_ts/master.m3u8';

Future<bool> _hayInternet() async {
  try {
    final s = await Socket.connect('devstreaming-cdn.apple.com', 443,
        timeout: const Duration(seconds: 5));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('una lista HLS real se reempaqueta en MPEG-TS válido', () async {
    if (!await _hayInternet()) {
      markTestSkipped('sin internet');
      return;
    }

    final plan = await CastHlsATs.analizar(_listaReal, const {}, _ua);
    expect(plan, isNotNull, reason: 'no se pudo leer la lista');
    expect(plan!.pedacitos, isNotEmpty);
    expect(plan.duracion.inSeconds, greaterThan(0),
        reason: 'sin duración el televisor no dibuja la barra de progreso');

    // Se consumen unos megas del flujo y se comprueba la alineación: un
    // MPEG-TS son paquetes de exactamente 188 bytes que empiezan con 0x47. Si
    // el pegado de los pedacitos estuviera mal, esa cuenta se rompe.
    final bytes = <int>[];
    await for (final b in CastHlsATs.servir(plan)) {
      bytes.addAll(b);
      if (bytes.length > 2 * 1024 * 1024) break;
    }
    expect(bytes.length, greaterThan(1024 * 1024), reason: 'no bajó vídeo');

    var desalineados = 0;
    for (var i = 0; i + 188 <= bytes.length; i += 188) {
      if (bytes[i] != 0x47) desalineados++;
    }
    expect(desalineados, 0, reason: 'el MPEG-TS resultante está roto');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('una lista con pedacitos cifrados no se reempaqueta', () async {
    // Se sirve una lista falsa en local: lo que se prueba acá es la decisión,
    // no la red.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      req.response.write('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="clave.bin"\n'
          '#EXTINF:10.0,\n'
          'a.ts\n');
      await req.response.close();
    });
    final plan = await CastHlsATs.analizar(
        'http://127.0.0.1:${server.port}/lista.m3u8', const {}, _ua);
    expect(plan, isNull,
        reason: 'mandarle pedacitos cifrados al televisor sería mandarle ruido');
    await server.close(force: true);
  });

  test('una lista con pedacitos MP4 no se reempaqueta', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.write('#EXTM3U\n'
          '#EXT-X-MAP:URI="init.mp4"\n'
          '#EXTINF:10.0,\n'
          'a.m4s\n');
      await req.response.close();
    });
    final plan = await CastHlsATs.analizar(
        'http://127.0.0.1:${server.port}/lista.m3u8', const {}, _ua);
    expect(plan, isNull, reason: 'esos pedacitos no son MPEG-TS');
    await server.close(force: true);
  });
}
