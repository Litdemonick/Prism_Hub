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

  test('el User-Agent de navegador llega a la fuente', () async {
    // Esto no es un detalle: las fuentes detrás de Cloudflare contestan 403 al
    // User-Agent que pone dart:io por defecto, y 200 a uno de navegador.
    //
    // Y el fallo era invisible: dart:io deja SIEMPRE puesto su
    // "Dart/x.y (dart:io)", así que preguntarle al pedido si ya trae uno daba
    // que sí siempre y el de navegador no se aplicaba nunca. La lista volvía
    // 403, no se podía reempaquetar, y en pantalla salía "este dispositivo no
    // soporta el formato" — que apuntaba al televisor cuando el problema
    // estaba de este lado.
    //
    // Se levanta una fuente que rechaza igual que Cloudflare: sin el
    // User-Agent correcto, 403.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final vistos = <String?>[];
    server.listen((req) async {
      final ua = req.headers.value(HttpHeaders.userAgentHeader);
      vistos.add(ua);
      if (ua == null || !ua.contains('Mozilla')) {
        req.response.statusCode = 403;
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('.m3u8')) {
        req.response.write('#EXTM3U\n#EXTINF:10.0,\na.ts\n');
      } else {
        // Dos paquetes MPEG-TS validos, para que pase la comprobacion.
        final ts = List<int>.filled(376, 0)
          ..[0] = 0x47
          ..[188] = 0x47;
        req.response.add(ts);
      }
      await req.response.close();
    });

    final plan = await CastHlsATs.analizar(
        'http://127.0.0.1:${server.port}/lista.m3u8', const {}, _ua);
    expect(plan, isNotNull,
        reason: 'la fuente rechazó el pedido: el User-Agent no llegó');
    expect(vistos, everyElement(contains('Mozilla')),
        reason: 'algún pedido salió con el User-Agent de dart:io');
    await server.close(force: true);
  });

  test('el User-Agent de la extensión gana sobre el de por defecto', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? visto;
    server.listen((req) async {
      visto ??= req.headers.value(HttpHeaders.userAgentHeader);
      req.response.write('#EXTM3U\n');
      await req.response.close();
    });
    await CastHlsATs.analizar('http://127.0.0.1:${server.port}/lista.m3u8',
        const {'User-Agent': 'ElDeLaExtension/1.0'}, _ua);
    expect(visto, 'ElDeLaExtension/1.0',
        reason: 'si la extensión manda uno, ese es el que la fuente espera');
    await server.close(force: true);
  });

  group('adelantar en un vídeo reempaquetado', () {
    // Adelantar no es pedirle al televisor que salte —no puede, el flujo se va
    // armando sobre la marcha— sino rearmarle el flujo desde otro pedacito. Lo
    // que hace falta para eso es saber en cuál cae cada momento.
    PlanTs plan(List<double> d) => PlanTs(
          pedacitos: [
            for (var i = 0; i < d.length; i++) Uri.parse('http://x/$i.ts')
          ],
          duraciones: d,
          headers: const {},
          userAgent: _ua,
        );

    test('el largo total sale de la lista', () {
      expect(plan([10, 10, 10, 5.5]).duracion,
          const Duration(milliseconds: 35500));
    });

    test('cada momento cae en su pedacito', () {
      final p = plan([10, 10, 10, 10]);
      expect(p.indiceDe(Duration.zero), 0);
      expect(p.indiceDe(const Duration(seconds: 9)), 0);
      expect(p.indiceDe(const Duration(seconds: 10)), 1);
      expect(p.indiceDe(const Duration(seconds: 25)), 2);
      expect(p.indiceDe(const Duration(seconds: 39)), 3);
    });

    test('pasarse del final no se sale de la lista', () {
      final p = plan([10, 10]);
      expect(p.indiceDe(const Duration(hours: 3)), 1);
      expect(p.recortadoDesde(99).desde, 1);
      expect(p.recortadoDesde(-5).desde, 0);
    });

    test('el flujo recortado sabe en qué minuto empieza', () {
      final p = plan([10, 10, 10, 10]);
      // Es lo que la app le suma a lo que informa el televisor, que cuenta
      // desde cero porque para él es un vídeo nuevo. Si esto estuviera mal, la
      // barra diría un número y el televisor estaría en otro.
      expect(p.recortadoDesde(0).inicio, Duration.zero);
      expect(p.recortadoDesde(2).inicio, const Duration(seconds: 20));
      expect(p.recortadoDesde(3).inicio, const Duration(seconds: 30));
      // Y el largo total no cambia por haber recortado.
      expect(p.recortadoDesde(3).duracion, const Duration(seconds: 40));
    });

    test('el flujo recortado empieza a servir desde ahí', () async {
      // Se sirven pedacitos que dicen cual son, para ver por cual arranca.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.add('[${req.uri.path}]'.codeUnits);
        await req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final p = PlanTs(
        pedacitos: [
          for (var i = 0; i < 4; i++) Uri.parse('$base/$i.ts'),
        ],
        duraciones: const [10, 10, 10, 10],
        headers: const {},
        userAgent: _ua,
      ).recortadoDesde(2);

      final salida = <int>[];
      await for (final b in CastHlsATs.servir(p)) {
        salida.addAll(b);
      }
      expect(String.fromCharCodes(salida), '[/2.ts][/3.ts]',
          reason: 'tiene que arrancar en el pedacito del salto, no en el 0');
      await server.close(force: true);
    });
  });

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
