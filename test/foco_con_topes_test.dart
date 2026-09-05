import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/tv/foco_con_topes.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
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
///
/// Usa `FocusableCard` de verdad y no un `Focus` pelado: es lo que envuelve
/// a CADA tarjeta en el televisor, y trae por dentro su propio manejo de
/// teclas, su marco por fuera de los límites y su `RepaintBoundary`. Probar
/// con otra cosa sería probar una app que no existe.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.nombre, required this.foco});

  final String nombre;
  final FocusNode foco;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusNode: foco,
      onTap: () {},
      altoMarco: 150,
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

  setUp(() {
    nodos = {};
    // ── En modo TELEVISOR, que es lo que hay que probar ────────────────
    //
    // Media app se bifurca por acá: `FocusableCard` cambia su marco, su
    // resplandor, si crece al enfocarse y —lo que importa para esto— si
    // hace su propio `ensureVisible` o se lo deja a `RescateDeFoco`. Con
    // esto en false se estaría probando la versión de PC, que no es la que
    // corre en el televisor ni la que tiene los fallos que se reportan.
    PlatformTv.esTelevisionSync = true;
  });

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
  Widget arbol({
    int filas = 3,
    int porFila = 4,
    bool conRescate = false,
    // El panel de categorías desplegado tapa el contenido: es más ancho que
    // el hueco que este le deja y se dibuja ENCIMA. Es el estado de la foto
    // que se reportó, así que hay que poder probarlo.
    double anchoDelRail = 60,
  }) {
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
                    width: anchoDelRail,
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

    testWidgets('DESPLEGADO no se puede entrar: por eso tiene que contraerse',
        (t) async {
      // ── El motivo por el que el panel SE CONTRAE, escrito como prueba ──
      //
      // Para mover el foco a la izquierda, Flutter exige que el CENTRO del
      // destino quede más a la izquierda que el BORDE del origen
      // (`_sortAndFilterHorizontally`). Con el panel desplegado sus botones
      // son anchos, así que su centro cae a la DERECHA del borde de las
      // tarjetas y Flutter los descarta: el panel se vuelve inalcanzable.
      //
      // Y ahí se muerde la cola: si no se puede entrar, nunca recibe el
      // foco; si nunca recibe el foco, nunca se entera de que tiene que
      // contraerse; y desplegado sigue siendo inalcanzable. Es exactamente
      // lo reportado en vivo, con foto: «el panel queda abierto todo el rato
      // y no me deja ni entrar».
      //
      // Por eso el arreglo no está acá sino en el panel (`_SidebarTVState`),
      // que ahora comprueba contra la realidad si tiene el foco en vez de
      // confiar en que su `autofocus` haya llegado a aplicarse. Este caso
      // queda escrito para que se entienda que un panel desplegado de forma
      // permanente NO es una opción de diseño: rompe la navegación.
      await t.pumpWidget(arbol(anchoDelRail: 220));
      await t.pumpAndSettle();

      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();

      expect(enfocado(), 'f0-c0');
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

  group('una fila LARGA, que de verdad se desplaza', () {
    /// ── Por qué hace falta este caso aparte ──────────────────────────────
    ///
    /// En los casos de arriba la fila entera entra en pantalla: apretar
    /// derecha mueve el foco pero NO desplaza nada. En el televisor eso no
    /// pasa nunca —una fila trae quince tarjetas y se ven cinco— así que
    /// cada paso a la derecha ADEMÁS desplaza la fila, y al desplazarse la
    /// lista recicla las tarjetas que salen de la vista.
    ///
    /// Reciclar es justo lo que dispara el fallo reportado: la tarjeta que
    /// tiene el foco deja de existir. Sin una fila que se desplace, el test
    /// pasaba sin haber probado el caso de verdad.
    Future<void> tvDe(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
    }

    testWidgets('recorrerla entera con la derecha no baja de fila', (t) async {
      await tvDe(t);
      await t.pumpWidget(arbol(porFila: 15, conRescate: true));
      await t.pumpAndSettle();

      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();

      // Se aprieta MÁS veces que tarjetas hay: las últimas son las que caen
      // en el tope, que es donde se reportó el fallo.
      for (var i = 0; i < 20; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
        expect(
          enfocado(),
          startsWith('f0-'),
          reason: 'se fue de la fila 0 en la pulsación ${i + 1}',
        );
      }
    });
  });

  group('dentro del panel, arriba y abajo no sacan de ahí', () {
    // «Si estoy en el panel izquierdo y estoy subiendo y bajando, no me debe
    // sacar a otro lugar: estoy eligiendo a qué zona entrar. No me puede
    // sacar hasta que yo vaya a la derecha.»
    testWidgets('bajando por el panel no se escapa al contenido', (t) async {
      await t.pumpWidget(arbol(conRescate: true));
      await t.pumpAndSettle();

      nodo('rail0').requestFocus();
      await t.pumpAndSettle();

      for (var i = 0; i < 8; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
        expect(
          enfocado(),
          startsWith('rail'),
          reason: 'se salió del panel bajando, en la pulsación ${i + 1}',
        );
      }
    });

    testWidgets('subiendo por el panel tampoco', (t) async {
      await t.pumpWidget(arbol(conRescate: true));
      await t.pumpAndSettle();

      nodo('rail3').requestFocus();
      await t.pumpAndSettle();

      for (var i = 0; i < 8; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pumpAndSettle();
        expect(
          enfocado(),
          startsWith('rail'),
          reason: 'se salió del panel subiendo, en la pulsación ${i + 1}',
        );
      }
    });
  });

  group('la izquierda llega al panel desde cualquier fila', () {
    for (final fila in [0, 1, 2]) {
      testWidgets('desde la fila $fila', (t) async {
        await t.binding.setSurfaceSize(const Size(1280, 720));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(arbol(conRescate: true));
        await t.pumpAndSettle();

        nodo('f$fila-c0').requestFocus();
        await t.pumpAndSettle();

        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pumpAndSettle();

        expect(enfocado(), startsWith('rail'));
      });
    }
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
