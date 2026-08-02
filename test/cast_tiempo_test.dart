// Cómo se lee el tiempo que informa un televisor DLNA.
//
// Parece trivial y no lo es: lo que un aparato contesta cuando NO sabe algo se
// parecía demasiado a un cero legítimo, y tratarlo como cero dejaba la barra de
// progreso muerta —sin recorrido, sin poder arrastrarla— durante todo el
// episodio, con el vídeo avanzando en la pantalla grande.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/cast_aparato.dart';

void main() {
  Duration? t(String s) => AparatoDlna.tiempo(s);

  test('un tiempo normal se lee bien', () {
    expect(t('00:00:00'), Duration.zero);
    expect(t('00:01:30'), const Duration(minutes: 1, seconds: 30));
    expect(t('01:23:45'),
        const Duration(hours: 1, minutes: 23, seconds: 45));
    expect(t('  00:10:00  '), const Duration(minutes: 10));
  });

  test('los segundos con decimales no se pierden', () {
    // Hay aparatos que informan "00:00:12.500".
    expect(t('00:00:12.500'), const Duration(seconds: 12, milliseconds: 500));
  });

  test('lo que no es un tiempo devuelve null, no cero', () {
    // Esta es la distinción que importa. Un aparato que no lleva esa cuenta
    // contesta así, y confundirlo con cero hacía que la barra volviera al
    // principio en cada consulta.
    expect(t('NOT_IMPLEMENTED'), isNull);
    expect(t(''), isNull);
    expect(t('00:00'), isNull);
    expect(t('hh:mm:ss'), isNull);
  });
}
