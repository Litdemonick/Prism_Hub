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
          body: Column(children: [
            // ── La barra de arriba ────────────────────────────────────────
            //
            // Buscar, extensiones, favoritos, historial y ajustes. Vive
            // FUERA de las dos regiones (rail y contenido), igual que en la
            // app: es de toda la pantalla, no de ninguna de las dos. Desde
            // la primera categoría del panel, la flecha arriba tiene que
            // llegar acá.
            SizedBox(
              height: 46,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < 5; i++)
                    Focus(
                      focusNode: nodo('barra$i'),
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: Colors.teal,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
            children: [
              RegionDeFocoTv(
                nombre: RegionDeFocoTv.contenido,
                child: Padding(
                  // El mismo hueco que deja el rail contraído en la app.
                  padding: const EdgeInsets.only(left: 80),
                  child: ListView(
                    children: [
                      for (var f = 0; f < filas; f++) ...[
                        // El nombre de la extensión, arriba de la tira. No
                        // es decorado: vive FUERA de lo que la cámara mide
                        // para traer la fila a la vista, así que es
                        // justamente lo que se cortaba.
                        SizedBox(
                          height: 34,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('titulo-f$f'),
                          ),
                        ),
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
            ),
          ]),
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

    testWidgets('también con el panel DESPLEGADO, tapando la tarjeta',
        (t) async {
      // ── Y desplegado también, que antes era imposible ──────────────
      //
      // Delegando en Flutter esto NO funcionaba: para mover el foco a la
      // izquierda exige que el CENTRO del destino quede más a la izquierda
      // que el BORDE del origen, y con el panel desplegado sus botones son
      // anchos, así que su centro cae a la derecha del borde de las
      // tarjetas y quedaban descartados.
      //
      // Eso se mordía la cola: si no se podía entrar, el panel nunca
      // recibía el foco; sin foco nunca se enteraba de que tenía que
      // contraerse; y desplegado seguía siendo inalcanzable. Reportado en
      // vivo con foto: «el panel queda abierto todo el rato y no me deja ni
      // entrar».
      //
      // Ahora la entrada al panel se resuelve sin delegar —se busca el
      // botón que esté a la altura de donde se venía— así que el ancho del
      // panel deja de importar y el bloqueo no puede volver.
      await t.pumpWidget(arbol(anchoDelRail: 220));
      await t.pumpAndSettle();

      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();

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

  group('al toparse no se mueve NADA', () {
    testWidgets('la derecha en la última no desplaza la pantalla', (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(arbol(porFila: 15, conRescate: true));
      await t.pumpAndSettle();

      // Hasta la última de la fila.
      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();
      for (var i = 0; i < 14; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
      }
      expect(enfocado(), 'f0-c14');

      // Dónde está todo ANTES de insistir contra el tope.
      final antesDeInsistir = t.getTopLeft(find.text('f1-c0'));

      for (var i = 0; i < 5; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
      }

      // Reportado con foto: «la selección se queda en la última tarjeta pero
      // se mueven las de abajo, como si moviera todo alrededor». Eso pasaba
      // porque el intento de salto igual desplazaba la pantalla, aunque el
      // foco se devolviera después.
      expect(enfocado(), 'f0-c14');
      expect(t.getTopLeft(find.text('f1-c0')), antesDeInsistir);
    });
  });

  group('la izquierda vuelve por la fila y termina en el panel', () {
    testWidgets('en una fila larga: se desanda entera y se entra al panel',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(arbol(porFila: 15, conRescate: true));
      await t.pumpAndSettle();

      // Se avanza hasta el final de la fila...
      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();
      for (var i = 0; i < 14; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
      }
      expect(enfocado(), 'f0-c14');

      // ...y se vuelve. Las catorce primeras tienen que recorrer la fila
      // hacia atrás, y la quince —ya sin vecino a la izquierda— tiene que
      // ENTRAR AL PANEL, no quedarse trabada.
      //
      // «A la derecha ya tiene el tope, pero a la izquierda, en vez de
      // bloquear, debe ir a la zona del panel izquierdo.»
      for (var i = 0; i < 14; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pumpAndSettle();
      }
      expect(enfocado(), 'f0-c0');

      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(enfocado(), startsWith('rail'));
    });
  });

  group('pantallas de dos columnas (Ajustes, repositorio, historial)', () {
    /// ── Por qué son un caso aparte ───────────────────────────────────────
    ///
    /// No tienen filas de tarjetas: son una columna de opciones a la
    /// izquierda y un panel a la derecha. Las reglas de «quedate en el mismo
    /// renglón» no tienen nada que decir acá —no hay renglones— y aplicarlas
    /// igual bloquea el cruce de una columna a la otra.
    ///
    /// Reportado en vivo: «bug crítico en Ajustes, no me deja desplazar a la
    /// derecha a las opciones de la derecha».
    Widget dosColumnas() {
      return MaterialApp(
        home: Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: FocoConTopes(),
          },
          child: RescateDeFoco(
            child: Scaffold(
              body: Row(
                children: [
                  // El menú, CENTRADO en vertical y con las tarjetas de
                  // verdad — igual que en Ajustes. Ese centrado es parte del
                  // fallo: el panel de al lado arranca arriba, así que las
                  // alturas no coinciden.
                  SizedBox(
                    width: 250,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 6; i++)
                            FocusableCard(
                              focusNode: nodo('opcion$i'),
                              onTap: () {},
                              child: Container(
                                height: 56,
                                margin: const EdgeInsets.all(6),
                                color: Colors.indigo,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < 10; i++)
                          FocusableCard(
                            focusNode: nodo('panel$i'),
                            onTap: () {},
                            child: Container(
                              height: 60,
                              margin: const EdgeInsets.all(8),
                              color: Colors.brown,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    /// El caso exacto de Ajustes: la categoría elegida está abajo del menú
    /// («Acerca de») y lo único enfocable del panel está arriba («Actualizar
    /// aplicación»). No comparten altura por ningún lado.
    ///
    /// Reportado en vivo: «estoy en Acerca de, le doy a la derecha y no me
    /// deja tocar el botón de actualizar; tengo que subir hasta Reproductor
    /// de vídeo y ahí sí la selección llega al botón».
    Widget menuAbajoBotonArriba() {
      return MaterialApp(
        home: Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: FocoConTopes(),
          },
          child: RescateDeFoco(
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 250,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 6; i++)
                          FocusableCard(
                            focusNode: nodo('opcion$i'),
                            onTap: () {},
                            child: Container(
                              height: 56,
                              margin: const EdgeInsets.all(6),
                              color: Colors.indigo,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FocusableCard(
                        focusNode: nodo('boton-actualizar'),
                        onTap: () {},
                        child: Container(
                          height: 60,
                          width: 300,
                          margin: const EdgeInsets.all(8),
                          color: Colors.brown,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('desde la última categoría se llega al botón de arriba',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(menuAbajoBotonArriba());
      await t.pumpAndSettle();

      nodo('opcion5').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();

      expect(enfocado(), 'boton-actualizar');
    });

    testWidgets('la derecha pasa de las opciones al panel', (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(dosColumnas());
      await t.pumpAndSettle();

      nodo('opcion4').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();

      // Y cae en la PRIMERA del panel, no en la que quede a la misma
      // altura: «si ya estoy en esa zona, debe enfocar la primera para ir
      // seleccionando».
      expect(enfocado(), 'panel0');
    });

    testWidgets('y la izquierda vuelve a las opciones', (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(dosColumnas());
      await t.pumpAndSettle();

      nodo('panel4').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();

      expect(enfocado(), startsWith('opcion'));
    });
  });

  group('la izquierda entra al panel SIN mover nada', () {
    testWidgets('estando abajo, no salta las tarjetas hacia arriba',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(arbol(filas: 6, conRescate: true));
      await t.pumpAndSettle();

      // Se baja unas cuantas filas, para estar «allá abajo».
      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
      }
      expect(enfocado(), startsWith('f3-'));

      final antesDeIrALaIzquierda = t.getTopLeft(find.text('f3-c0'));

      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();

      // Entra al panel...
      expect(enfocado(), startsWith('rail'));
      // ...y las tarjetas se quedan EXACTAMENTE donde estaban. Reportado en
      // vivo: «hacia la izquierda me sigue subiendo la selección y moviendo
      // las cards; nunca me tiene que hacer el salto automático de todas
      // las cards hacia arriba».
      expect(t.getTopLeft(find.text('f3-c0')), antesDeIrALaIzquierda);
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

    testWidgets('subiendo, nunca se escapa a las tarjetas', (t) async {
      await t.pumpWidget(arbol(conRescate: true));
      await t.pumpAndSettle();

      nodo('rail3').requestFocus();
      await t.pumpAndSettle();

      // Subiendo se recorre el panel y, en la primera categoría, se sale a
      // la barra de arriba — eso SÍ está bien (ver el caso siguiente). Lo
      // que no puede pasar nunca es terminar en una tarjeta: el contenido
      // está a la derecha, no arriba.
      for (var i = 0; i < 8; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pumpAndSettle();
        expect(
          enfocado(),
          isNot(startsWith('f')),
          reason: 'se fue a las tarjetas subiendo, en la pulsación ${i + 1}',
        );
      }
    });

    testWidgets('desde la primera categoría, arriba va a la barra de arriba',
        (t) async {
      // «Al estar arriba del panel y subir, debe llevarme a los botones de
      // arriba: buscar, extensiones, etc. Antes andaba.»
      await t.pumpWidget(arbol(conRescate: true));
      await t.pumpAndSettle();

      nodo('rail0').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();

      expect(enfocado(), startsWith('barra'));
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

  group('la cámara no corta la fila por arriba', () {
    testWidgets('subiendo de a una, el título de la fila se sigue viendo',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(arbol(filas: 6, conRescate: true));
      await t.pumpAndSettle();

      // Se baja hasta el fondo y se vuelve subiendo de a una fila, que es
      // como se reportó: «al ir subiendo poco a poco, la cámara corta las
      // cosas hacia arriba».
      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
      }

      for (var i = 4; i >= 0; i--) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pumpAndSettle();
        final donde = enfocado();
        if (donde == null || !donde.startsWith('f')) continue;
        final fila = donde.split('-').first; // «f2»
        // El título de la fila enfocada tiene que estar DENTRO de la
        // pantalla, no por encima del borde.
        final titulo = find.text('titulo-$fila');
        expect(titulo, findsOneWidget, reason: 'no se construyó $fila');
        expect(
          t.getTopLeft(titulo).dy,
          greaterThanOrEqualTo(0),
          reason: 'el título de $fila quedó cortado por arriba',
        );
      }
    });
  });

  group('los destacados de arriba: fila FIJA, con los mismos topes', () {
    /// Los dos grandes y las cuatro medianas de Inicio no son una fila que se
    /// desplaza: son `Row` comunes, marcados con `FranjaFijaTv`. Se recorren
    /// igual que cualquier fila y tienen que frenar igual en las puntas.
    /// Reportado en vivo: «las seis de arriba también necesitan topes».
    Widget conDestacados() {
      return MaterialApp(
        home: Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: FocoConTopes(),
          },
          child: RescateDeFoco(
            child: Scaffold(
              body: Stack(
                children: [
                  RegionDeFocoTv(
                    nombre: RegionDeFocoTv.contenido,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 80),
                      child: ListView(
                        children: [
                          FranjaFijaTv(
                            child: Row(
                              children: [
                                for (var i = 0; i < 2; i++)
                                  Expanded(
                                    child: FocusableCard(
                                      focusNode: nodo('grande$i'),
                                      onTap: () {},
                                      child: Container(
                                        height: 220,
                                        margin: const EdgeInsets.all(6),
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 190,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (var c = 0; c < 6; c++)
                                  _Tarjeta(
                                      nombre: 'abajo-c$c',
                                      foco: nodo('abajo-c$c')),
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
            ),
          ),
        ),
      );
    }

    testWidgets('en el último destacado, la derecha no mueve nada', (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(conDestacados());
      await t.pumpAndSettle();

      nodo('grande1').requestFocus();
      await t.pumpAndSettle();

      final antesDeInsistir = t.getTopLeft(find.text('abajo-c0'));
      for (var i = 0; i < 4; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
      }

      expect(enfocado(), 'grande1');
      expect(t.getTopLeft(find.text('abajo-c0')), antesDeInsistir);
    });

    testWidgets('y del primero, la izquierda va al panel', (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(conDestacados());
      await t.pumpAndSettle();

      nodo('grande0').requestFocus();
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();

      expect(enfocado(), startsWith('rail'));
    });

    testWidgets('dentro del panel, insistir con la izquierda no saca de ahí',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(conDestacados());
      await t.pumpAndSettle();

      nodo('rail1').requestFocus();
      await t.pumpAndSettle();

      final antesDeInsistir = t.getTopLeft(find.text('abajo-c0'));
      // «Cuando entro al panel y sigo presionando izquierda, me saca del
      // panel y comienza a scrollear toda la zona hacia abajo.»
      for (var i = 0; i < 4; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pumpAndSettle();
      }

      expect(enfocado(), 'rail1');
      expect(t.getTopLeft(find.text('abajo-c0')), antesDeInsistir);
    });
  });

  group('al entrar desde el panel no se mueve la pantalla', () {
    testWidgets('la derecha entra por lo que está enfrente',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(arbol(filas: 5, conRescate: true));
      await t.pumpAndSettle();

      // Se deja la zona recorrida y desplazada, como queda al volver: las
      // zonas se conservan vivas con su desplazamiento.
      nodo('f0-c0').requestFocus();
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
      }
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(enfocado(), startsWith('rail'));

      // Y al volver a entrar, se entra por lo que está ENFRENTE, sin que
      // la pantalla se desplace. «Cuando estoy en el panel y presiono la
      // derecha me redirige abajo automáticamente con otras cards pasando;
      // tiene que detectar en qué línea estoy y seguir por ahí.»
      final antesDeEntrar = t.getTopLeft(find.text('f1-c0'));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();

      expect(enfocado(), startsWith('f'));
      expect(t.getTopLeft(find.text('f1-c0')), antesDeEntrar);
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
