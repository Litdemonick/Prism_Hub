import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/carrera_de_nodos.dart';

/// Pruebas del reparto entre nodos de un CDN.
///
/// Se prueba acá y no contra la red porque lo que hay que asegurar es el
/// REPARTO —cuándo se suma otro nodo, cuándo no, y que nunca se quede
/// esperando para siempre— y eso con peticiones de verdad no se puede
/// reproducir a voluntad. Los intentos son futuros de mentira que se completan
/// cuando esta prueba quiere.
void main() {
  // Plazos cortos: lo que importa es el orden de las cosas, no los segundos.
  const paciencia = Duration(milliseconds: 50);
  const tope = Duration(milliseconds: 600);

  group('la carrera entre nodos', () {
    test('con un nodo sano no se lanza ninguna petición de más', () async {
      final lanzados = <String>[];
      final r = await CarreraDeNodos.correr<String, String>(
        candidatos: const ['bueno', 'otro', 'tercero'],
        paciencia: paciencia,
        tope: tope,
        intentar: (cual, darSenales) async {
          lanzados.add(cual);
          darSenales();
          return cual;
        },
      );
      expect(r, 'bueno');
      // Los otros dos ni se tocaron: bajar lo mismo dos veces gasta los datos
      // de quien está mirando.
      expect(lanzados, ['bueno']);
    });

    test('un nodo muerto no se lleva el plazo entero: se suma otro', () async {
      final lanzados = <String>[];
      final reloj = Stopwatch()..start();
      final r = await CarreraDeNodos.correr<String, String>(
        candidatos: const ['muerto', 'bueno'],
        paciencia: paciencia,
        tope: tope,
        intentar: (cual, darSenales) async {
          lanzados.add(cual);
          if (cual == 'muerto') {
            // No contesta nunca. Lo corta el tope.
            return Completer<String>().future;
          }
          darSenales();
          return cual;
        },
      );
      expect(r, 'bueno');
      expect(lanzados, ['muerto', 'bueno']);
      // Lo que se está comprobando: NO se esperó el plazo entero del muerto.
      // Antes de esto, cada nodo caído costaba sus ocho segundos.
      expect(reloj.elapsed, lessThan(tope));
    });

    test('mientras uno manda bytes no se suma nadie más', () async {
      final lanzados = <String>[];
      final r = await CarreraDeNodos.correr<String, String>(
        candidatos: const ['lento', 'otro'],
        paciencia: paciencia,
        tope: tope,
        intentar: (cual, darSenales) async {
          lanzados.add(cual);
          // Da señales enseguida, pero tarda bastante más que la paciencia.
          darSenales();
          await Future<void>.delayed(paciencia * 4);
          return cual;
        },
      );
      expect(r, 'lento');
      // Un nodo lento NO es un nodo muerto. Sumar otro acá sería bajar el
      // mismo pedazo dos veces con los datos de quien está mirando.
      expect(lanzados, ['lento']);
    });

    test('si el que contestaba se cae, se sigue con el siguiente', () async {
      // Este es el caso que en una versión anterior dejaba la descarga
      // esperando para siempre: el que había dado señales fallaba después, y
      // como ya no se sumaban candidatos, no quedaba nadie que completara.
      final lanzados = <String>[];
      final r = await CarreraDeNodos.correr<String, String>(
        candidatos: const ['sedcae', 'bueno'],
        paciencia: paciencia,
        tope: tope,
        intentar: (cual, darSenales) async {
          lanzados.add(cual);
          darSenales();
          if (cual == 'sedcae') {
            await Future<void>.delayed(paciencia * 2);
            throw StateError('se cortó a mitad');
          }
          return cual;
        },
      );
      expect(r, 'bueno');
      expect(lanzados, ['sedcae', 'bueno']);
    });

    test('si fallan todos devuelve null, no se queda esperando', () async {
      final fallados = <String>[];
      final r = await CarreraDeNodos.correr<String, String>(
        candidatos: const ['a', 'b', 'c'],
        paciencia: paciencia,
        tope: tope,
        intentar: (cual, darSenales) async => throw StateError('no'),
        alFallar: (cual, e) => fallados.add(cual),
      );
      expect(r, isNull);
      expect(fallados, ['a', 'b', 'c']);
    });

    test('sin candidatos devuelve null sin intentar nada', () async {
      var intentos = 0;
      final r = await CarreraDeNodos.correr<String, String>(
        candidatos: const [],
        paciencia: paciencia,
        tope: tope,
        intentar: (cual, darSenales) async {
          intentos++;
          return cual;
        },
      );
      expect(r, isNull);
      expect(intentos, 0);
    });

    test('gana el primero que termina, aunque se hayan lanzado dos', () async {
      // Dos muertos aparentes: ninguno da señales, así que se suman los dos.
      // El segundo termina primero y es el que tiene que ganar.
      final ganadores = <String>[];
      final r = await CarreraDeNodos.correr<String, String>(
        candidatos: const ['tarda', 'rapido'],
        paciencia: paciencia,
        tope: tope,
        intentar: (cual, darSenales) async {
          await Future<void>.delayed(
            cual == 'tarda' ? paciencia * 6 : paciencia * 2,
          );
          return cual;
        },
        alGanar: (cual, r) => ganadores.add(cual),
      );
      expect(r, 'rapido');
      // Y el que llega segundo no vuelve a completar nada.
      await Future<void>.delayed(paciencia * 8);
      expect(ganadores, ['rapido']);
    });
  });
}
