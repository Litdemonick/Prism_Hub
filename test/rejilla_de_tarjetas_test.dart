import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/views/widgets/home/rejilla_de_tarjetas.dart';

/// Cuántas tarjetas entran por fila.
///
/// ── Por qué esto tiene prueba ───────────────────────────────────────────
///
/// Porque el fallo que arregla no se ve leyendo el código: la cuenta vieja
/// era correcta —metía todas las tarjetas de 320 px que entraran— y aun así
/// daba DOS columnas en el televisor donde se mide, con las portadas
/// ocupando la pantalla entera. Reportado con foto.
///
/// Lo que falla es la relación entre el ancho lógico que declara cada
/// televisor y lo que se ve desde el sillón, y eso solo se comprueba
/// pasándole los anchos de los aparatos de verdad.
void main() {
  ({int columnas, double ancho}) enTv(double disponible) =>
      RejillaDeTarjetas.calcular(
        disponible: disponible,
        separacion: 20,
        televisor: true,
        pantalla: Ancho.desde(disponible),
      );

  group('en televisor', () {
    test('el televisor donde se midió el problema da seis, no dos', () {
      // 960 lógicos menos la barra lateral y los márgenes.
      final r = enTv(822);
      expect(r.columnas, 6);
      // Y cada una entra en la franja legible: ni estampilla ni cartel.
      expect(r.ancho, greaterThan(112));
      expect(r.ancho, lessThan(210));
    });

    test('un televisor de 1280 lógicos también da seis', () {
      expect(enTv(1142).columnas, 6);
    });

    test('en uno muy ancho se agregan columnas en vez de agrandar', () {
      // Con seis, cada tarjeta pasaría de 280 px: vuelve el cartel.
      final r = enTv(1782);
      expect(r.columnas, greaterThan(6));
      expect(r.ancho, lessThanOrEqualTo(210));
    });

    test('en una franja angosta se sacan columnas en vez de achicar', () {
      // Una pantalla partida o un televisor que declara muy poco: seis
      // tarjetas de 60 px no se leerían desde el sillón.
      final r = enTv(400);
      expect(r.columnas, lessThan(6));
      expect(r.ancho, greaterThanOrEqualTo(112));
    });

    test('nunca baja de dos columnas ni se pasa de diez', () {
      expect(enTv(100).columnas, 2);
      expect(enTv(20000).columnas, RejillaDeTarjetas.columnasEnTv * 2 - 2);
    });

    test('las columnas y el ancho siempre llenan la franja', () {
      // El fallo que esto atrapa: que la cuenta devuelva un ancho que no
      // cierra con la separación y la última columna se salga de pantalla.
      for (final disponible in [400.0, 822.0, 1142.0, 1782.0, 2400.0]) {
        final r = enTv(disponible);
        final total = r.ancho * r.columnas + 20 * (r.columnas - 1);
        expect(total, closeTo(disponible, 0.001), reason: 'con $disponible');
      }
    });
  });

  group('fuera de televisor', () {
    test('un teléfono en vertical da dos columnas', () {
      final r = RejillaDeTarjetas.calcular(
        disponible: 360,
        separacion: 16,
        televisor: false,
        pantalla: Ancho.compacto,
      );
      expect(r.columnas, 2);
    });

    test('un escritorio ancho mete todas las que entren', () {
      final r = RejillaDeTarjetas.calcular(
        disponible: 1600,
        separacion: 16,
        televisor: false,
        pantalla: Ancho.enorme,
      );
      // 240 de ideal más 16 de separación: seis entran holgadas.
      expect(r.columnas, 6);
    });

    test('el tope se respeta', () {
      final r = RejillaDeTarjetas.calcular(
        disponible: 4000,
        separacion: 16,
        televisor: false,
        pantalla: Ancho.enorme,
        tope: 8,
      );
      expect(r.columnas, 8);
    });
  });
}
