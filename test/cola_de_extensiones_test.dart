import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/cola_de_extensiones.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// El turno de las peticiones de extensiones.
///
/// Se prueba sin red a propósito: lo que hay que asegurar es el reparto —que
/// nunca pasen más de las permitidas, que el sitio se devuelva también cuando
/// algo falla, y que nadie se quede esperando para siempre—. Con peticiones de
/// verdad eso no se puede provocar a voluntad.
void main() {
  group('la cola', () {
    test('deja pasar hasta el tope sin esperar', () async {
      final cola = ColaDeConcurrencia(3);
      await cola.entrar();
      await cola.entrar();
      await cola.entrar();
      expect(cola.enVuelo, 3);
      expect(cola.haciendoCola, 0);
    });

    test('a partir del tope, hace esperar', () async {
      final cola = ColaDeConcurrencia(2);
      await cola.entrar();
      await cola.entrar();
      var paso = false;
      unawaited(cola.entrar().then((_) => paso = true));
      await Future<void>.delayed(Duration.zero);
      expect(paso, isFalse, reason: 'la tercera no puede pasar todavía');
      expect(cola.haciendoCola, 1);
    });

    test('al devolver el sitio entra el siguiente', () async {
      final cola = ColaDeConcurrencia(1);
      await cola.entrar();
      var paso = false;
      unawaited(cola.entrar().then((_) => paso = true));
      await Future<void>.delayed(Duration.zero);
      expect(paso, isFalse);
      cola.salir();
      await Future<void>.delayed(Duration.zero);
      expect(paso, isTrue);
      // Y sigue habiendo uno solo en el aire: el sitio pasó de mano en mano,
      // no se sumó otro.
      expect(cola.enVuelo, 1);
    });

    test('el orden se respeta: primero el que llegó antes', () async {
      final cola = ColaDeConcurrencia(1);
      await cola.entrar();
      final orden = <int>[];
      unawaited(cola.entrar().then((_) => orden.add(1)));
      unawaited(cola.entrar().then((_) => orden.add(2)));
      unawaited(cola.entrar().then((_) => orden.add(3)));
      for (var i = 0; i < 3; i++) {
        cola.salir();
        await Future<void>.delayed(Duration.zero);
      }
      expect(orden, [1, 2, 3]);
    });

    test('con la cola llena y todos saliendo, no queda nadie esperando',
        () async {
      // El fallo que esto atrapa: que un sitio se pierda y la cola se quede
      // trabada para el resto de la sesión, con la app sin poder pedir nada.
      final cola = ColaDeConcurrencia(2);
      var pasaron = 0;
      for (var i = 0; i < 6; i++) {
        unawaited(cola.entrar().then((_) => pasaron++));
      }
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
        cola.salir();
      }
      await Future<void>.delayed(Duration.zero);
      expect(pasaron, 6);
      expect(cola.haciendoCola, 0);
    });

    test('con tope 0 no hay cola: pasa todo', () async {
      final cola = ColaDeConcurrencia(0);
      for (var i = 0; i < 50; i++) {
        await cola.entrar();
      }
      expect(cola.haciendoCola, 0);
      // Y salir de más no rompe nada ni deja la cuenta en negativo.
      for (var i = 0; i < 60; i++) {
        cola.salir();
      }
      expect(cola.enVuelo, 0);
    });

    test('devolver más veces de las que se entró no rompe la cuenta', () async {
      final cola = ColaDeConcurrencia(2);
      await cola.entrar();
      cola.salir();
      cola.salir();
      cola.salir();
      expect(cola.enVuelo, 0);
      // Y después sigue funcionando igual.
      await cola.entrar();
      await cola.entrar();
      expect(cola.enVuelo, 2);
    });
  });

  group('el tope según el aparato', () {
    test('un aparato modesto tiene turno; uno capaz no', () {
      // El recorte es para donde se midió el problema. En un teléfono actual o
      // un PC las mismas peticiones entran en menos de un segundo, y poner un
      // tope ahí solo podría empeorarlo.
      expect(ColaDeExtensiones.topeParaNivel(NivelDeAparato.bajo), 4);
      expect(ColaDeExtensiones.topeParaNivel(NivelDeAparato.medio), 8);
      expect(ColaDeExtensiones.topeParaNivel(NivelDeAparato.alto), 0);
    });
  });
}
