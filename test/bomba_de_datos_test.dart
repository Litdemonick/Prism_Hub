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
  _Origen(this.total, {this.demora = Duration.zero});

  final int total;

  /// Cuánto tarda en entregar cada trozo.
  ///
  /// Con cero, la fuente contesta al instante y NUNCA hay una lectura en vuelo
  /// cuando llega el pedido siguiente — que es justo la ventana donde estaba el
  /// fallo de Android. Poniéndole demora, la prueba puede meterse ahí.
  final Duration demora;
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
      // Se entrega por trozos y NO de un saque, a propósito.
      //
      // Escribiendo los megas enteros de una vez, la bomba se los lleva al
      // instante —no hay red que la frene— y queda corriendo muy por delante de
      // lo que el reproductor pidió. Eso no se parece en nada a un servidor de
      // verdad, donde el búfer del socket la sujeta, y hacía que la prueba
      // fallara o pasara según cómo viniera el día.
      await res.addStream(_porTrozos(desde));
      await res.close();
    });
  }

  /// El archivo desde [desde], en trozos de 64 KiB.
  Stream<List<int>> _porTrozos(int desde) async* {
    const trozo = 64 * 1024;
    for (var i = desde; i < total; i += trozo) {
      if (demora > Duration.zero) await Future<void>.delayed(demora);
      final hasta = (i + trozo > total) ? total : i + trozo;
      yield Uint8List.fromList([for (var j = i; j < hasta; j++) _valor(j)]);
    }
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

  test('cortar y volver a pedir EN EL ACTO sigue reusando la lectura', () async {
    // **Esta prueba NO reproduce el fallo de Android del 2026-08-06** («Bad
    // state: Already waiting for next», 29 veces en un episodio). Se intentó y
    // no se consiguió: por loopback, el corte del cliente no deja una lectura de
    // la fuente en vuelo en el instante justo, que es donde estaba la carrera.
    // Queda escrito para no volver a intentarlo creyendo que sirve.
    //
    // Lo que sí cubre, y por eso se deja: que cortar y volver a pedir enseguida
    // —con la fuente tardando de verdad— siga saliendo de la MISMA lectura en
    // vez de reabrir. Es el camino que el reproductor recorre todo el tiempo.
    BombaDeDatos.soltar(local);
    await origen.parar();
    origen = _Origen(total, demora: const Duration(milliseconds: 40));
    await origen.arrancar();
    local = (await BombaDeDatos.registrar(url: origen.url))!;

    for (var vuelta = 0; vuelta < 6; vuelta++) {
      // Se corta a mitad de un bloque que la fuente todavía está mandando...
      await _pedirYCortar(local, 'bytes=${vuelta * 4096}-', 96 * 1024);
      // ...y se vuelve a pedir en el acto, sin dejar respirar.
      //
      // El tramo tiene que ser lo bastante largo como para que HAYA QUE LEER de
      // la fuente. Pidiendo poquito se contesta entero de lo guardado, no se
      // toca la lectura, y la prueba pasaría aunque el fallo estuviera puesto
      // (comprobado: así pasaba).
      const largo = 256 * 1024;
      final desde = vuelta * 4096 + 32 * 1024;
      final res = await _pedir(local, 'bytes=$desde-${desde + largo - 1}');
      expect(res.codigo, HttpStatus.partialContent);
      esperarTramo(res.cuerpo, desde, largo);
    }

    // Con el fallo, cada colisión mataba una lectura y había que reabrir: se
    // veían muchos más pedidos que vueltas.
    expect(origen.pedidos, lessThanOrEqualTo(3),
        reason: 'seis cortes seguidos no tendrían que costar una lectura nueva '
            'cada vez; la fuente recibió ${origen.pedidos}: ${origen.rangos}');
  });

  test('un pedido abierto se sirve ENTERO, no cortado en tramos', () async {
    // Se probó cortarlo en tramos de 4 MiB el 2026-08-06 y hubo que sacarlo:
    // empeoró la reproducción en las dos plataformas. El reproductor necesita
    // poder tirar de una sola respuesta larga a su ritmo; cortándosela vuelve a
    // pedir de a pedacitos, que es el problema que la bomba viene a resolver.
    // Ver el bloque "Cortar la respuesta en tramos" en bomba_de_datos.dart.
    final abierto = await _pedir(local, 'bytes=0-');
    expect(abierto.codigo, HttpStatus.partialContent);
    expect(abierto.cuerpo.length, total,
        reason: 'tiene que venir el archivo entero desde el byte 0');
    expect(abierto.cabeceras['content-range'], 'bytes 0-${total - 1}/$total');
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
