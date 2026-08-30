// Que el registro se parta donde de verdad empieza cada apertura de la app.
//
// Es lo que separa "lo de ahora" de "lo de antes" en el visor, y un corte mal
// puesto no se ve como un error: se ve como líneas que faltan o como una
// sesión que arrastra la anterior pegada. Por eso se comprueba acá y no
// mirando la pantalla.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/sesiones_del_registro.dart';

/// Una presentación como la que escribe EncabezadoDeSesion.
List<String> _arranque(String cuando) => [
      '╔══════════════════════════════════════════╗',
      '║              P R I S M  H U B            ║',
      '╚══════════════════════════════════════════╝',
      'prismhub INFO $cuando: ═══ PrismHub 1.0.46 · ANDROID TV',
    ];

void main() {
  test('sin líneas no hay sesiones', () {
    expect(partirEnSesiones(const []), isEmpty);
  });

  test('un arranque es una sesión', () {
    final s = partirEnSesiones(_arranque('2026-08-29 21:45:03.100000'));
    expect(s, hasLength(1));
    expect(s.first.cuando, DateTime(2026, 8, 29, 21, 45, 3));
  });

  test('tres arranques son tres sesiones, en orden', () {
    final lineas = [
      ..._arranque('2026-08-27 10:00:00.000000'),
      'prismhub INFO 2026-08-27 10:00:01.000000: algo',
      ..._arranque('2026-08-28 20:30:00.000000'),
      ..._arranque('2026-08-29 09:15:00.000000'),
      'prismhub INFO 2026-08-29 09:15:02.000000: otra cosa',
    ];
    final s = partirEnSesiones(lineas);
    expect(s, hasLength(3));
    expect(s[0].cuando!.day, 27);
    expect(s[1].cuando!.day, 28);
    expect(s[2].cuando!.day, 29);
    // Ninguna se queda con líneas de la siguiente.
    expect(s[0].lineas.last, contains('algo'));
    expect(s[2].lineas.last, contains('otra cosa'));
  });

  test('lo que quedó antes de la primera marca no se tira', () {
    // Pasa de verdad: el archivo se recorta por tamaño y puede cortar a mitad
    // de una sesión. Esas líneas son registro real y tienen que verse.
    final lineas = [
      'prismhub INFO 2026-08-26 08:00:00.000000: cola de una sesión cortada',
      ..._arranque('2026-08-27 10:00:00.000000'),
    ];
    final s = partirEnSesiones(lineas);
    expect(s, hasLength(2));
    expect(s.first.lineas.single, contains('cortada'));
    expect(s.first.cuando!.day, 26);
  });

  test('sin ninguna marca, todo es una sola sesión', () {
    final s = partirEnSesiones(
      ['prismhub INFO 2026-08-29 09:15:02.000000: suelta'],
    );
    expect(s, hasLength(1));
    expect(s.single.cuantasLineas, 1);
  });

  test('una sesión sin hora legible no revienta, queda sin fecha', () {
    final s = partirEnSesiones(['╔══ recuadro ══╗', 'sin hora ninguna']);
    expect(s, hasLength(1));
    expect(s.single.cuando, isNull);
  });

  test('no se pierde ni una línea al partir', () {
    final lineas = [
      'suelta',
      ..._arranque('2026-08-27 10:00:00.000000'),
      'a',
      ..._arranque('2026-08-28 10:00:00.000000'),
      'b',
    ];
    final total =
        partirEnSesiones(lineas).fold<int>(0, (n, s) => n + s.cuantasLineas);
    expect(total, lineas.length);
  });
}
