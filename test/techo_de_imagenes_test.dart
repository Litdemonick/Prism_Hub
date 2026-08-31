import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/alivio_de_memoria.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Cuánta memoria puede guardar la caché de imágenes en cada aparato.
///
/// ── Por qué esto tiene prueba ───────────────────────────────────────────────
///
/// Era un número fijo por nivel: 48 MB para cualquier aparato «modesto». En un
/// televisor real de 893 MB que Android marca como de poca memoria, el sistema
/// le da a la app un montón de alrededor de 96 MB — o sea que ese techo se
/// llevaba la mitad de todo lo que la app tiene para existir.
///
/// El registro de ese televisor lo muestra entero: el sistema pidió memoria
/// tres veces, se bajó el techo a 28 MB, y doce segundos después Android mató
/// la app en medio de la navegación.
///
/// Equivocarse acá no da un fallo que se vea: da una app que se cierra sola.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int techoDe({required int memoriaMb, required NivelDeAparato nivel}) {
    PerfilDeAparato.memoriaTotalMb = memoriaMb;
    PerfilDeAparato.nivel = nivel;
    AlivioDeMemoria.aplicarTechoDeImagenes();
    return PaintingBinding.instance.imageCache.maximumSizeBytes >> 20;
  }

  group('el techo sale de la memoria que hay', () {
    test('el televisor de 893 MB no pasa de 22', () {
      // El aparato donde se midió el cierre. Antes eran 48.
      expect(techoDe(memoriaMb: 893, nivel: NivelDeAparato.bajo), 22);
    });

    test('uno de 2 GB puede más, pero no más que su nivel', () {
      // 2048/40 son 51, y el nivel bajo tope en 48: manda el más chico.
      expect(techoDe(memoriaMb: 2048, nivel: NivelDeAparato.bajo), 48);
    });

    test('un teléfono de 8 GB usa el de su nivel', () {
      // 8192/40 son 204, por debajo de los 220 de un aparato capaz.
      expect(techoDe(memoriaMb: 8192, nivel: NivelDeAparato.alto), 204);
    });

    test('uno de 16 GB no se dispara: manda el tope del nivel', () {
      expect(techoDe(memoriaMb: 16384, nivel: NivelDeAparato.alto), 220);
    });
  });

  group('los bordes', () {
    test('sin saber la memoria se usa el del nivel, como antes', () {
      // Un 0 es «no se pudo averiguar», no «no tiene». Recortar por no saber
      // sería empeorar la app de todo el mundo por una medición que falló.
      expect(techoDe(memoriaMb: 0, nivel: NivelDeAparato.bajo), 48);
      expect(techoDe(memoriaMb: 0, nivel: NivelDeAparato.alto), 220);
    });

    test('nunca baja de 16 MB, por chico que sea el aparato', () {
      // Por debajo de eso la caché deja de servir de caché: las portadas se
      // vuelven a decodificar sin parar, que cuesta más CPU de la que ahorra
      // en memoria.
      expect(techoDe(memoriaMb: 400, nivel: NivelDeAparato.bajo), 16);
      expect(techoDe(memoriaMb: 64, nivel: NivelDeAparato.bajo), 16);
    });

    test('la cuenta de imágenes acompaña al techo de megas', () {
      // Permitir doscientas imágenes cuando en megas entran veinte solo hace
      // que la caché se pase de largo entre una purga y la siguiente.
      techoDe(memoriaMb: 893, nivel: NivelDeAparato.bajo);
      expect(PaintingBinding.instance.imageCache.maximumSize, 88);
    });
  });
}
