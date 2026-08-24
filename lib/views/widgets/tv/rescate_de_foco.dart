import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// La red de seguridad del control remoto.
///
/// ── El problema que resuelve ────────────────────────────────────────────
///
/// Con un mando, TODO depende de que haya algo enfocado: si el foco queda en
/// la nada, las flechas no tienen desde dónde moverse y la app se siente
/// congelada — no hay dedo ni cursor con que rescatarla, hay que cerrarla.
///
/// Y quedarse sin foco pasa por motivos normales: se volvió de una pantalla
/// que se abrió encima, se cerró un panel y el widget que lo tenía dejó de
/// existir, cambió una lista debajo del foco. Cubrir cada uno de esos casos
/// por separado es una pelea perdida.
///
/// ── Por qué un manejador global y no un `Focus` que envuelva la app ─────
///
/// Fue el primer intento y no funciona: el `onKeyEvent` de un `Focus` solo
/// se llama si ese nodo está en la CADENA del que tiene el foco. Cuando no
/// hay foco no hay cadena, así que el widget que venía a rescatar la
/// situación era justamente el que nunca se enteraba.
///
/// `addEarlyKeyEventHandler` no depende del foco: recibe cada tecla antes
/// que el árbol, tenga o no tenga foco alguien.
class RescateDeFoco extends StatefulWidget {
  const RescateDeFoco({super.key, required this.child});

  final Widget child;

  @override
  State<RescateDeFoco> createState() => _RescateDeFocoState();
}

class _RescateDeFocoState extends State<RescateDeFoco> {
  static final _teclasDeNavegacion = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
  };

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_alLlegarUnaTecla);
    FocusManager.instance.addListener(_alCambiarElFoco);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_alLlegarUnaTecla);
    FocusManager.instance.removeListener(_alCambiarElFoco);
    super.dispose();
  }

  /// Trae a la vista lo que acaba de recibir el foco.
  ///
  /// ── Por qué va acá y no en cada pantalla ──────────────────────────────
  ///
  /// Mover el foco NO desplaza la lista: eso lo tiene que pedir alguien. Las
  /// tarjetas de TV ya lo hacían solas, pero los botones normales de
  /// Material —los de instalar del repositorio, los tiles de Ajustes— no, y
  /// ahí el foco se iba más allá del borde visible: la lista parecía trabada
  /// y el último elemento no se podía ver entero.
  ///
  /// Puesto una sola vez acá vale para TODA la app, incluidas las pantallas
  /// que no se tocaron.
  void _alCambiarElFoco() {
    final nodo = FocusManager.instance.primaryFocus;
    final ctx = nodo?.context;
    if (ctx == null || nodo is FocusScopeNode) return;
    // Después del cuadro: recién ahí el widget está ubicado en su lugar
    // definitivo, que es lo que `ensureVisible` necesita para medir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ctx.mounted) return;
      const duracion = Duration(milliseconds: 180);
      // Las dos políticas mueven lo MÍNIMO: una resuelve "quedó por encima
      // del borde" y la otra "quedó por debajo". Sobre algo que ya se ve
      // entero, ninguna hace nada — así el contenido no baila en cada paso.
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: duracion,
        curve: Curves.easeOut,
      );
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: duracion,
        curve: Curves.easeOut,
      );
    });
  }

  /// ¿El foco está en un widget de verdad, con el que se pueda navegar?
  ///
  /// No alcanza con que `primaryFocus` no sea null: cuando una pantalla se
  /// va, el foco cae al ÁMBITO (un `FocusScopeNode`), que no es un destino
  /// —es un contenedor— y desde ahí las flechas no tienen de dónde salir.
  /// Ese es justo el estado en el que el mando parece muerto.
  bool get _hayFocoUtil {
    final actual = FocusManager.instance.primaryFocus;
    if (actual == null) return false;
    if (actual is FocusScopeNode) return false;
    // Un nodo cuyo widget ya se fue del árbol tampoco sirve.
    return actual.context != null && actual.canRequestFocus;
  }

  KeyEventResult _alLlegarUnaTecla(KeyEvent evento) {
    if (evento is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_teclasDeNavegacion.contains(evento.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (_hayFocoUtil) return KeyEventResult.ignored;

    // ── Se rescata DESDE el ámbito que tiene el foco ──────────────────
    //
    // Medido en vivo: cuando la app se congela, el foco está en el ámbito
    // de la pantalla actual (`_ModalScopeState … Focus Scope`) y no en
    // ningún widget. Un ámbito no es un destino —es un contenedor— así que
    // las flechas no tienen desde dónde salir.
    //
    // El intento anterior llamaba a `nextFocus()` sobre el ámbito RAÍZ, y
    // no servía: desde ahí la búsqueda arranca en otro lado del árbol y no
    // baja a la pantalla que se está viendo. Pidiéndoselo al ámbito que
    // justamente tiene el foco, el primer enfocable que encuentra es uno de
    // lo que el usuario tiene delante.
    final actual = FocusManager.instance.primaryFocus;
    final ambito = actual is FocusScopeNode
        ? actual
        : (actual?.nearestScope ?? FocusManager.instance.rootScope);
    final movio = ambito.nextFocus();
    // La tecla se consume solo si de verdad se recuperó el foco: si no,
    // mejor dejarla pasar por si alguien más puede hacer algo con ella.
    return movio ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
