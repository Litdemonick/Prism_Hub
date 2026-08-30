// Que el registro se pueda compartir sin filtrar nada.
//
// El registro se exporta, se pega en un reporte y se manda por mensaje. Estas
// pruebas existen porque un fallo acá no se nota: la línea se ve bien, se
// comparte, y recién después se descubre que llevaba un token o el nombre de
// lo que alguien estaba viendo. Es la clase de cosa que hay que comprobar
// automáticamente, no mirando.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/log.dart';

void main() {
  group('las direcciones no salen enteras', () {
    test('se va la firma que trae la consulta', () {
      final salida = PrismLog.sanear(
        'switchServer: VOE → https://cdn7.ejemplo.com/hls/abc123/index.m3u8'
        '?token=SECRETO&expires=1799999999',
      );
      expect(salida, contains('cdn7.ejemplo.com'));
      expect(salida, isNot(contains('SECRETO')));
      expect(salida, isNot(contains('token')));
      expect(salida, isNot(contains('expires')));
    });

    test('se va la ruta, que es la que dice qué se estaba viendo', () {
      final salida = PrismLog.sanear(
        'abriendo https://sitio.com/anime/un-titulo-cualquiera/episodio-12.mp4',
      );
      expect(salida, isNot(contains('un-titulo-cualquiera')));
      expect(salida, isNot(contains('episodio-12')));
    });

    test('el servidor SÍ se conserva: es el diagnóstico', () {
      final salida =
          PrismLog.sanear('falló https://cdn3.playmudos.com/x/y/seg-1.ts');
      expect(salida, contains('cdn3.playmudos.com'));
    });

    test('el formato SÍ se conserva: distingue un HLS de un MP4', () {
      expect(PrismLog.sanear('https://a.com/x/y/lista.m3u8'), contains('.m3u8'));
      expect(PrismLog.sanear('https://a.com/x/y/video.mp4'), contains('.mp4'));
    });

    test('el puerto se conserva: delata al relay local', () {
      final salida = PrismLog.sanear('sirviendo http://127.0.0.1:8431/relay/x');
      expect(salida, contains('127.0.0.1:8431'));
    });

    test('varias direcciones en la misma línea', () {
      final salida = PrismLog.sanear(
        'de https://uno.com/a/b.ts?k=1 a https://dos.com/c/d.ts?k=2',
      );
      expect(salida, contains('uno.com'));
      expect(salida, contains('dos.com'));
      expect(salida, isNot(contains('k=1')));
      expect(salida, isNot(contains('k=2')));
    });

    test('una dirección rota no rompe el saneado', () {
      // No tiene que lanzar: una línea de registro mal formada no puede
      // impedir que se registre.
      expect(() => PrismLog.sanear('https://'), returnsNormally);
    });
  });

  group('el nombre de usuario del sistema no sale', () {
    test('en una ruta de Windows', () {
      final salida = PrismLog.sanear(
        r'no se pudo abrir C:\Users\Fulano\AppData\PrismHub\x.log',
      );
      expect(salida, isNot(contains('Fulano')));
    });

    test('en una ruta de Linux', () {
      expect(PrismLog.sanear('leyendo /home/fulano/.prismhub/x'),
          isNot(contains('fulano')));
    });
  });

  test('una línea sin nada sensible queda igual', () {
    const linea = 'medición (arrancó) · colchón: 12 s · cuadros tirados: 0';
    expect(PrismLog.sanear(linea), linea);
  });
}
