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
      // ── Se deja AIRE alrededor, no se pega al borde ────────────────────
      //
      // Antes se movía lo MÍNIMO —dos políticas, una para "quedó por arriba"
      // y otra para "quedó por abajo"—. Eso deja lo enfocado justo tocando el
      // filo de la pantalla, y en un televisor eso se ve como que la tarjeta
      // está cortada: el halo del foco y el crecido se salen del borde, y no
      // hay forma de saber si abajo hay más contenido.
      //
      // Reportado en vivo: «que la cámara se posicione para que no se pierda
      // la card y no la corte» y «no sé si abajo hay más cosas o no».
      //
      // Con `alignment: 0.35` lo enfocado queda a poco más de un tercio
      // desde arriba: se ve entero con su marco, y por debajo queda pantalla
      // suficiente para que se note que la lista sigue. Es lo que hacen las
      // apps de televisor, y por eso ahí uno siempre sabe dónde está parado.
      //
      // ¿Y por qué no centrado? Porque centrar mueve la lista en CADA paso,
      // incluso sobre algo que ya se veía bien, y eso se siente como que la
      // pantalla se sacude sola.
      _traerALaVista(ctx, duracion);
    });
  }

  /// Trae lo enfocado a la vista, tratando cada eje como corresponde.
  ///
  /// ── El bug que esto arregla ─────────────────────────────────────────
  ///
  /// `Scrollable.ensureVisible` recorre TODOS los scrolls ancestros y
  /// acomoda cada uno con la misma regla. Una tarjeta vive dentro de una
  /// fila horizontal que a su vez vive dentro de la lista vertical, así que
  /// pedir «ponela al 35%» acomodaba las dos cosas: la lista bajaba —que es
  /// lo que se quería— y la FILA se corría de costado para dejar la tarjeta
  /// a un tercio desde la izquierda, aunque ya se estuviera viendo perfecta.
  ///
  /// Reportado en vivo: «cuando bajo, las cards se mueven hacia la
  /// izquierda y solamente estoy bajando; si es abajo, es abajo».
  ///
  /// Ahora cada eje va con su criterio:
  ///
  ///   vertical    al 35% desde arriba, para que se vea entera y se note
  ///               que la lista sigue abajo (ver el comentario de arriba).
  ///   horizontal  lo mínimo indispensable: si ya se ve, no se mueve nada.
  static void _traerALaVista(BuildContext ctx, Duration duracion) {
    final objetivo = ctx.findRenderObject();
    if (objetivo == null) return;
    var contexto = ctx;
    var scroll = Scrollable.maybeOf(contexto);
    while (scroll != null) {
      final posicion = scroll.position;
      if (posicion.axis == Axis.vertical) {
        posicion.ensureVisible(
          objetivo,
          alignment: 0.35,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: duracion,
          curve: Curves.easeOut,
        );
      } else {
        // Las dos políticas seguidas son el «lo mínimo»: la primera acerca
        // el principio si quedó cortado por la izquierda, la segunda el
        // final si quedó cortado por la derecha. Si ya entra entera, ninguna
        // de las dos mueve nada.
        posicion.ensureVisible(
          objetivo,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: duracion,
          curve: Curves.easeOut,
        );
        posicion.ensureVisible(
          objetivo,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: duracion,
          curve: Curves.easeOut,
        );
      }
      contexto = scroll.context;
      scroll = Scrollable.maybeOf(contexto);
    }
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
