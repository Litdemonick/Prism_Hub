import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/bomba_de_datos.dart';

/// Pruebas de la bomba de datos, que le sirve a mpv un archivo remoto desde una
/// sola lectura abierta río arriba.
///
/// Se prueban las DOS cosas que importan, y las dos hacen falta:
///
///  1. **Que los bytes sean los que son.** Un error de posición acá no se ve
///     como un error: se ve como un vídeo que se corta o se pixela, y en vivo
///     eso es indistinguible de un servidor lento. Cada byte del archivo de
///     prueba tiene un valor distinto según en qué posición está, así que
///     entregar el tramo equivocado se nota enseguida.
///  2. **Que de verdad NO vuelva a pedir.** Es todo el punto de esto. El
///     servidor de mentira cuenta los pedidos que recibe, así que la prueba
///     falla si la bomba reabre cuando no debía.

/// El valor que le toca al byte que está en la posición [i].
int _valor(int i) => (i * 7 + 13) % 251;

/// Un servidor que se porta como la fuente: entrega desde donde le pidan y
/// cuenta cuántas veces le pidieron.
class _Origen {
  _Origen(this.total);

  final int total;
  late final HttpServer _servidor;

  /// Cuántos pedidos recibió. Es la cuenta que dice si la bomba sirve.
  int pedidos = 0;
  final rangos = <String>[];

  Future<void> arrancar() async {
    _servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _servidor.listen((pedido) async {
      pedidos++;
      final rango = pedido.headers.value(HttpHeaders.rangeHeader);
      rangos.add(rango ?? 'sin rango');
      final desde = rango == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(rango)!.group(1)!);
      final res = pedido.response;
      res.statusCode = rango == null ? HttpStatus.ok : HttpStatus.partialContent;
      res.headers.contentType = ContentType('video', 'mp4');
      if (rango != null) {
        res.headers.set(
            HttpHeaders.contentRangeHeader, 'bytes $desde-${total - 1}/$total');
      }
      res.headers.contentLength = total - desde;
      res.add(Uint8List.fromList([
        for (var i = desde; i < total; i++) _valor(i),
      ]));
      await res.close();
    });
  }

  String get url => 'http://127.0.0.1:${_servidor.port}/pelicula.mp4';

  Future<void> parar() => _servidor.close(force: true);
}

/// Lo que contestó la bomba a un pedido.
class _Respuesta {
  _Respuesta(this.codigo, this.cabeceras, this.cuerpo);
  final int codigo;
  final Map<String, String> cabeceras;
  final Uint8List cuerpo;
}

Future<_Respuesta> _pedir(String url, String? rango) async {
  final cliente = HttpClient();
  try {
    final req = await cliente.getUrl(Uri.parse(url));
    if (rango != null) req.headers.set(HttpHeaders.rangeHeader, rango);
    final res = await req.close();
    final cabeceras = <String, String>{};
    res.headers.forEach((n, v) => cabeceras[n.toLowerCase()] = v.join(', '));
    final juntado = BytesBuilder(copy: false);
    await for (final trozo in res) {
      juntado.add(trozo);
    }
    return _Respuesta(res.statusCode, cabeceras, juntado.takeBytes());
  } finally {
    cliente.close();
  }
}

/// Pide un tramo y CORTA a los [leerHasta] bytes, como hace el reproductor en
/// cuanto llenó lo suyo. Devuelve lo que alcanzó a recibir.
///
/// Es la pieza que faltaba en las pruebas: mientras todos los pedidos se leían
/// enteros, la bomba nunca quedaba adelantada y el fallo no aparecía.
Future<int> _pedirYCortar(String url, String rango, int leerHasta) async {
  final cliente = HttpClient();
  final req = await cliente.getUrl(Uri.parse(url));
  req.headers.set(HttpHeaders.rangeHeader, rango);
  final res = await req.close();
  var leidos = 0;
  final listo = Completer<void>();
  late final StreamSubscription<List<int>> sub;
  sub = res.listen((trozo) {
    leidos += trozo.length;
    if (leidos >= leerHasta && !listo.isCompleted) {
      listo.complete();
      unawaited(sub.cancel());
    }
  }, onDone: () {
    if (!listo.isCompleted) listo.complete();
  }, onError: (Object _) {
    if (!listo.isCompleted) listo.complete();
  });
  await listo.future;
  cliente.close(force: true);
  return leidos;
}

/// Comprueba que el tramo entregado sea EXACTAMENTE el que va en esa posición.
void esperarTramo(Uint8List cuerpo, int desde, int cuantos) {
  expect(cuerpo.length, cuantos, reason: 'largo del tramo desde $desde');
  for (var i = 0; i < cuerpo.length; i++) {
    if (cuerpo[i] != _valor(desde + i)) {
      fail('el byte ${desde + i} vale ${cuerpo[i]} y tendría que valer '
          '${_valor(desde + i)} — la bomba entregó el tramo equivocado');
    }
  }
}

void main() {
  const mib = 1024 * 1024;
  const total = 6 * mib;
  const trozo = 256 * 1024;

  late _Origen origen;
  late String local;

  setUp(() async {
    origen = _Origen(total);
    await origen.arrancar();
    final url = await BombaDeDatos.registrar(url: origen.url);
    expect(url, isNotNull, reason: 'la bomba tendría que haber levantado');
    local = url!;
  });

  tearDown(() async {
    BombaDeDatos.soltar(local);
    await origen.parar();
  });

  test('leyendo de corrido le pide UNA sola vez a la fuente', () async {
    for (var i = 0; i < 8; i++) {
      final desde = i * trozo;
      final res = await _pedir(local, 'bytes=$desde-${desde + trozo - 1}');
      expect(res.codigo, HttpStatus.partialContent);
      esperarTramo(res.cuerpo, desde, trozo);
    }
    expect(origen.pedidos, 1,
        reason: 'ocho tramos seguidos tendrían que salir de la MISMA lectura, '
            'y la fuente recibió ${origen.pedidos} pedidos: ${origen.rangos}');
    expect(origen.rangos.first, 'bytes=0-',
        reason: 'la lectura tiene que abrirse SIN tope, o la fuente vuelve a '
            'cobrar el arranque en cada tramo');
  });

  test('un salto corto hacia adelante tampoco vuelve a pedir', () async {
    final primero = await _pedir(local, 'bytes=0-${trozo - 1}');
    esperarTramo(primero.cuerpo, 0, trozo);

    // Un mega más adelante: por debajo de lo que cuesta reabrir, así que la
    // bomba tiene que adelantarse tirando bytes en vez de pedir de nuevo.
    const salto = trozo + mib;
    final segundo = await _pedir(local, 'bytes=$salto-${salto + trozo - 1}');
    esperarTramo(segundo.cuerpo, salto, trozo);

    expect(origen.pedidos, 1,
        reason: 'un salto de 1 MiB entra en lo tolerable y no tendría que '
            'abrir una lectura nueva: ${origen.rangos}');
  });

  test('un salto largo sí abre una lectura nueva, en el punto justo', () async {
    final primero = await _pedir(local, 'bytes=0-${trozo - 1}');
    esperarTramo(primero.cuerpo, 0, trozo);

    // Cuatro megas más adelante: pasa lo tolerable, así que conviene reabrir.
    const salto = 4 * mib;
    final segundo = await _pedir(local, 'bytes=$salto-${salto + trozo - 1}');
    esperarTramo(segundo.cuerpo, salto, trozo);

    expect(origen.pedidos, 2, reason: 'tendría que haber reabierto');
    expect(origen.rangos.last, 'bytes=$salto-',
        reason: 'la lectura nueva tiene que arrancar en el byte pedido');
  });

  test('volver hacia atrás reabre y entrega bien lo de atrás', () async {
    final adelante = await _pedir(local, 'bytes=${2 * mib}-${2 * mib + 1023}');
    esperarTramo(adelante.cuerpo, 2 * mib, 1024);

    // Hacia atrás no se puede adelantar una lectura: esa ya pasó por ahí.
    final atras = await _pedir(local, 'bytes=0-1023');
    esperarTramo(atras.cuerpo, 0, 1024);

    expect(origen.pedidos, 2);
    expect(origen.rangos.last, 'bytes=0-');
  });

  test('las dos zonas de un archivo mal entrelazado conviven', () async {
    // Un MP4 con el audio entero al final se lee alternando entre el principio
    // y el fondo. Con una sola lectura eso sería reabrir en cada cambio; con
    // varias abiertas, cada zona conserva la suya.
    const fondo = 5 * mib;
    for (var i = 0; i < 4; i++) {
      final principio = i * 1024;
      final res = await _pedir(local, 'bytes=$principio-${principio + 1023}');
      esperarTramo(res.cuerpo, principio, 1024);

      final atras = fondo + i * 1024;
      final res2 = await _pedir(local, 'bytes=$atras-${atras + 1023}');
      esperarTramo(res2.cuerpo, atras, 1024);
    }
    expect(origen.pedidos, 2,
        reason: 'las dos zonas tendrían que mantener UNA lectura cada una, y '
            'la fuente recibió ${origen.pedidos}: ${origen.rangos}');
  });

  test('si el reproductor corta y vuelve un poco atrás, NO reabre', () async {
    // Esto es lo que pasó en vivo con mp4upload el 2026-08-06 y dejó la bomba
    // sin servir para nada: mpv pide abierto, corta cuando llenó lo suyo, y
    // vuelve a pedir desde un punto que quedó DETRÁS de lo que ya se había
    // leído. Sin guardar lo último servido, ahí no había ninguna lectura
    // reusable y se reabría — cada 1,4 s, siempre en el mismo MB.
    final leidos = await _pedirYCortar(local, 'bytes=0-', 300 * 1024);
    expect(leidos, greaterThanOrEqualTo(300 * 1024));
    expect(origen.pedidos, 1);

    // Un pedido que cae atrás de donde quedó la lectura.
    const atras = 128 * 1024;
    final res = await _pedir(local, 'bytes=$atras-${atras + 4095}');
    esperarTramo(res.cuerpo, atras, 4096);

    expect(origen.pedidos, 1,
        reason: 'volver un poco atrás tiene que salir de lo guardado, y la '
            'fuente recibió ${origen.pedidos} pedidos: ${origen.rangos}');
  });

  test('y sigue leyendo bien después de volver atrás', () async {
    await _pedirYCortar(local, 'bytes=0-', 300 * 1024);

    // Un tramo que arranca atrás y TERMINA adelante de lo ya leído: la primera
    // parte sale de lo guardado y la segunda de la lectura viva. Es la costura
    // entre las dos, que es justo donde un error de posición no se vería.
    const atras = 200 * 1024;
    const largo = 400 * 1024;
    final res = await _pedir(local, 'bytes=$atras-${atras + largo - 1}');
    esperarTramo(res.cuerpo, atras, largo);
    expect(origen.pedidos, 1, reason: '${origen.rangos}');
  });

  test('dice bien cuánto mide y qué tramo entrega', () async {
    final res = await _pedir(local, 'bytes=1000-1999');
    expect(res.codigo, HttpStatus.partialContent);
    expect(res.cabeceras['content-range'], 'bytes 1000-1999/$total');
    expect(res.cabeceras['content-length'], '1000');
    expect(res.cabeceras['accept-ranges'], 'bytes');
    esperarTramo(res.cuerpo, 1000, 1000);
  });

  test('sin Range entrega el archivo entero con un 200', () async {
    final res = await _pedir(local, null);
    expect(res.codigo, HttpStatus.ok);
    expect(res.cabeceras['content-length'], '$total');
    expect(res.cabeceras.containsKey('content-range'), isFalse);
    esperarTramo(res.cuerpo, 0, total);
  });

  test('un pedido abierto hasta el final se sirve completo', () async {
    const desde = 5 * mib;
    final res = await _pedir(local, 'bytes=$desde-');
    expect(res.codigo, HttpStatus.partialContent);
    expect(res.cabeceras['content-range'], 'bytes $desde-${total - 1}/$total');
    esperarTramo(res.cuerpo, desde, total - desde);
  });
}
