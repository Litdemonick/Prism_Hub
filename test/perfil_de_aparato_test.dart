import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Cómo se clasifica un aparato para decidir cuánto puede gastar la app.
///
/// ── Por qué importa que esto esté probado ───────────────────────────────────
///
/// De este nivel cuelgan cuatro cosas: hasta qué calidad se pide vídeo, cuántas
/// peticiones de extensiones corren a la vez, cuánto colchón guarda el
/// reproductor y si el ajuste de «máxima calidad siempre» se puede activar.
/// Equivocarse hacia abajo empeora la app en aparatos capaces; equivocarse
/// hacia arriba la rompe en los modestos.
void main() {
  NivelDeAparato nivelDe({
    bool televisor = false,
    bool bajaMemoria = false,
    int memoriaMb = 0,
    int nucleos = 0,
  }) {
    PerfilDeAparato.resolver(
      esTelevision: televisor,
      bajaMemoria: bajaMemoria,
      memoriaTotalMb: memoriaMb,
      nucleos: nucleos,
    );
    return PerfilDeAparato.nivel;
  }

  group('televisores', () {
    test('el de 0,9 GB con cuatro núcleos es modesto', () {
      // El aparato real donde se midió todo esto: MediaTek, Android 9.
      expect(
        nivelDe(televisor: true, memoriaMb: 900, nucleos: 4),
        NivelDeAparato.bajo,
      );
    });

    test('uno de 1,4 GB también', () {
      expect(
        nivelDe(televisor: true, memoriaMb: 1400, nucleos: 4),
        NivelDeAparato.bajo,
      );
    });

    test('uno de 2 GB queda en el medio', () {
      expect(
        nivelDe(televisor: true, memoriaMb: 2048, nucleos: 4),
        NivelDeAparato.medio,
      );
    });

    test('un Fire TV 4K con 3 GB y ocho núcleos SÍ llega a capaz', () {
      // Es el pedido explícito: un televisor potente no puede recibir el mismo
      // trato que un stick de 1 GB. Antes ninguno pasaba de «medio».
      expect(
        nivelDe(televisor: true, memoriaMb: 3072, nucleos: 8),
        NivelDeAparato.alto,
      );
    });

    test('con memoria de sobra pero dos núcleos, es modesto igual', () {
      // Los dos datos cuentan: la memoria no decodifica vídeo.
      expect(
        nivelDe(televisor: true, memoriaMb: 4096, nucleos: 2),
        NivelDeAparato.bajo,
      );
    });
  });

  group('teléfonos, tablets y escritorio', () {
    test('el listón es más alto que en un televisor', () {
      // 1,8 GB en un televisor sería «medio»; en un teléfono es modesto. Un
      // televisor comparte casi todo con la interfaz del sistema y con el
      // decodificador; un teléfono tiene esa memoria para la app.
      expect(nivelDe(memoriaMb: 1800, nucleos: 4), NivelDeAparato.bajo);
      expect(
        nivelDe(televisor: true, memoriaMb: 1800, nucleos: 4),
        NivelDeAparato.medio,
      );
    });

    test('un teléfono de 3 GB queda en el medio', () {
      expect(nivelDe(memoriaMb: 3072, nucleos: 8), NivelDeAparato.medio);
    });

    test('uno de 8 GB con ocho núcleos es capaz', () {
      expect(nivelDe(memoriaMb: 8192, nucleos: 8), NivelDeAparato.alto);
    });

    test('un portátil viejo de dos núcleos es modesto', () {
      // Antes de esto, en escritorio TODO era «capaz» sin haber medido nada.
      expect(nivelDe(memoriaMb: 4096, nucleos: 2), NivelDeAparato.bajo);
    });
  });

  group('lo que dice el sistema y lo que no se sabe', () {
    test('si el sistema lo marca como modesto, manda eso', () {
      // `isLowRamDevice` la pone el fabricante: si él lo dice, no se discute
      // con números.
      expect(
        nivelDe(bajaMemoria: true, memoriaMb: 8192, nucleos: 8),
        NivelDeAparato.bajo,
      );
    });

    test('sin ningún dato no se recorta nada', () {
      // Un 0 es «no se pudo averiguar», no «no tiene». Recortar por no saber
      // sería empeorar la app de todo el mundo por una medición que falló.
      expect(nivelDe(), NivelDeAparato.alto);
      expect(nivelDe(televisor: true), NivelDeAparato.alto);
    });
  });

  group('el ajuste de máxima calidad', () {
    test('se bloquea solo en aparatos modestos', () {
      nivelDe(televisor: true, memoriaMb: 900, nucleos: 4);
      expect(PerfilDeAparato.puedeExigirMaximaCalidad, isFalse);

      nivelDe(televisor: true, memoriaMb: 3072, nucleos: 8);
      expect(PerfilDeAparato.puedeExigirMaximaCalidad, isTrue);

      nivelDe(memoriaMb: 3072, nucleos: 8);
      expect(PerfilDeAparato.puedeExigirMaximaCalidad, isTrue);
    });
  });
}
