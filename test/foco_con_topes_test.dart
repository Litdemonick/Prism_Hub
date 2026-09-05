import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/views/widgets/tv/foco_con_topes.dart';
import 'package:prismhub/views/widgets/tv/rescate_de_foco.dart';
import 'package:prismhub/views/widgets/tv/region_de_foco.dart';

/// Los topes del mando, medidos en vez de supuestos.
///
/// ── Por qué existe este archivo ─────────────────────────────────────────
///
/// «Al llegar al final de una fila y seguir apretando derecha, la selección
/// se va bajando sola» es el fallo que más veces volvió del televisor —y
/// cada arreglo se hacía a ciegas, porque el comportamiento del mando no se
/// podía comprobar acá: hace falta un televisor y un control remoto.
///
/// No hace falta. `FocoConTopes` es una `Action` común y las flechas se
/// pueden mandar desde un test. Armando un árbol con la misma FORMA que
/// tiene la pantalla de televisor —el rail a la izquierda marcado como su
/// región, y el contenido con filas horizontales dentro de una lista
/// vertical— se puede apretar la flecha y mirar dónde quedó el foco.
///
/// Cada caso de acá salió de un reporte en vivo, textual.

/// Una tarjeta enfocable, del tamaño de un póster de televisor.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.nombre, required this.foco});

  final String nombre;
  final FocusNode foco;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: foco,
      child: Container(
        width: 150,
        height: 170,
        margin: const EdgeInsets.all(5),
        color: Colors.grey,
        child: Text(nombre),
      ),
    );
  }
}

void main() {
  /// Los nodos del árbol de prueba, por nombre.
  late Map<String, FocusNode> nodos;

  FocusNode nodo(String nombre) =>
      nodos.putIfAbsent(nombre, () => FocusNode(debugLabel: nombre));

  /// Quién tiene el foco ahora mismo, por nombre.
  String? enfocado() {
    final actual = FocusManager.instance.primaryFocus;
    if (actual == null) return null;
    for (final e in nodos.entries) {
      if (identical(e.value, actual)) return e.key;
    }
    return 'otro(${actual.debugLabel})';
  }

  setUp(() => nodos = {});

  tearDown(() {
    for (final n in nodos.values) {
      try {
        n.dispose();
      } catch (_) {
        // El árbol ya se desmontó con el test; lo único que importa acá es
        // no dejar nodos colgados entre un caso y el siguiente.
      }
    }
  });

  /// La misma forma que la pantalla de Inicio de televisor: el rail pegado
  /// a la izquierda en su propia región, y el contenido —filas horizontales
  /// dentro de una lista vertical— en la suya.
  Widget arbol({int filas = 3, int porFila = 4, bool conRescate = false}) {
    Widget envolver(Widget hijo) =>
        conRescate ? RescateDeFoco(child: hijo) : hijo;
    return MaterialApp(
      home: Actions(
        actions: <Type, Action<Intent>>{
          DirectionalFocusIntent: FocoConTopes(),
        },
        child: envolver(Scaffold(
          body: Stack(
            children: [
              RegionDeFocoTv(
                nombre: RegionDeFocoTv.contenido,
                child: Padding(
                  // El mismo hueco que deja el rail contraído en la app.
                  padding: const EdgeInsets.only(left: 80),
                  child: ListView(
                    children: [
                      for (var f = 0; f < filas; f++)
                        SizedBox(
                          height: 190,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (var c = 0; c < porFila; c++)
                                _Tarjeta(
                                  nombre: 'f$f-c$c',
                                  foco: nodo('f$f-c$c'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: RegionDeFocoTv(
                  nombre: RegionDeFocoTv.rail,
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      children: [
                        for (var i = 0; i < 4; i++)
                          Focus(
                            focusNode: nodo('rail$i'),
                            child: Container(
                              width: 50,
                              height: 50,
                              margin: const EdgeInsets.all(5),
                              color: Colors.blueGrey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }

  group('la derecha se frena al final de la fila', () {
    testWidgets('en la última tarjeta, la derecha no mueve nada', (t) async {
      await t.pumpWidget(arbol());
      await t.pumpAndSettle();

      nodo('f0-c3').requestFocus();
      await t.pumpAndSettle();
      expect(enfocado(), 'f0-c3');

      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();

      // Reportado en vivo, reincidente: «cuando llego al final de una fila y
      // le doy a la derecha, no me tiene que bajar automáticamente a las
      // cards de abajo; se queda ahí con ese tope».
      expect(enfocado(), 'f0-c3');
    });

    testWidgets('insistir con la derecha tampoco la va bajando de fila',
        (t) async {
      await t.pumpWidget(arbol());
      await t.pumpAndSettle();

      nodo('f0-c3').requestFocus();
      await t.pumpAndSettle();

      // «Sigo presionando la flecha de la derecha y me sigue bajando las
      // cards hacia abajo automáticamente cuando yo no estoy bajando».
      for (var i = 0; i < 5; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
      }

      expect(enfocado(), 'f0-c3');
    });
  });

  group('la izquierda entra al panel de categorías', () {
    testWidgets('en la primera tarjeta, la izquierda va al rail', (t) async {
      await t.pumpWidget(arbol());
      await t.pumpAndSettle();

      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();
      expect(enfocado(), 'f0-c0');

      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();

      // «Toda la izquierda es ir al panel izquierdo: va pasando las cards y
      // llego hasta el panel izquierdo».
      expect(enfocado(), startsWith('rail'));
    });

    testWidgets('y desde el rail se vuelve al contenido con la derecha',
        (t) async {
      await t.pumpWidget(arbol());
      await t.pumpAndSettle();

      nodo('rail0').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();

      // Si esto no vuelve, el panel se queda desplegado para siempre: se
      // despliega mientras el foco está adentro. Reportado en vivo: «el
      // panel izquierdo sale todo el rato mostrándose, no se quita».
      expect(enfocado(), startsWith('f'));
    });
  });

  group('el rescate no cambia de fila', () {
    testWidgets('si la tarjeta enfocada se recicla, vuelve a SU fila',
        (t) async {
      await t.pumpWidget(arbol(conRescate: true));
      await t.pumpAndSettle();

      // Se recorre la fila 0 de verdad: el historial del rescate se llena
      // con las tarjetas de ESA fila, igual que cuando alguien va apretando
      // la derecha con el mando.
      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(enfocado(), 'f0-c2');

      // Y ahora pasa lo que pasa de verdad en el televisor: la lista recicla
      // la tarjeta que tenía el foco (el desplazamiento la saca de la vista)
      // y el foco queda en la nada.
      nodos['f0-c2']!.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();

      // Lo que NO puede pasar: terminar en la fila de abajo. `nextFocus()`
      // -el rescate anterior- hacía exactamente eso, porque en orden de
      // lectura lo que sigue a una fila es la siguiente.
      expect(enfocado(), startsWith('f0-'));
    });
  });

  group('lo vertical sigue funcionando', () {
    testWidgets('abajo baja de fila', (t) async {
      await t.pumpWidget(arbol());
      await t.pumpAndSettle();

      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();

      expect(enfocado(), startsWith('f1-'));
    });

    testWidgets('abajo NO se escapa al rail', (t) async {
      await t.pumpWidget(arbol());
      await t.pumpAndSettle();

      // En la última fila, abajo no tiene a dónde ir: no puede terminar en
      // el panel de categorías. Reportado en vivo: «al ir presionando el
      // scroll en una zona me saca y me manda al panel izquierdo».
      nodo('f2-c0').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();

      expect(enfocado(), isNot(startsWith('rail')));
    });
  });
}
