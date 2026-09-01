import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// En qué eje se movió el usuario recién.
  ///
  /// Arriba/abajo son `vertical`, izquierda/derecha `horizontal`. Cualquier
  /// otra cosa lo deja en null, que es «no fue una flecha»: el foco lo puso
  /// el código (entrar a una pantalla, un `autofocus`, el rescate de más
  /// abajo) y ahí no hay una dirección que respetar.
  ///
  /// Es estático y no de instancia porque `_traerALaVista` también lo es —
  /// `RescateDeFoco` está montado una sola vez, arriba de todo.
  static Axis? _ultimoEje;

  static Axis? _ejeDe(LogicalKeyboardKey tecla) {
    if (tecla == LogicalKeyboardKey.arrowUp ||
        tecla == LogicalKeyboardKey.arrowDown) {
      return Axis.vertical;
    }
    if (tecla == LogicalKeyboardKey.arrowLeft ||
        tecla == LogicalKeyboardKey.arrowRight) {
      return Axis.horizontal;
    }
    return null;
  }

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
      // El eje se consume acá y se apaga: vale para ESTE movimiento del foco
      // y nada más. Si no se limpiara, el próximo foco puesto por código
      // —volver de una pantalla, un `autofocus`— heredaría la última flecha
      // que alguien apretó hace rato y acomodaría un solo eje cuando lo que
      // corresponde es acomodar los dos.
      final eje = _ultimoEje;
      _ultimoEje = null;
      _traerALaVista(ctx, duracion, eje);
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
  ///
  /// ── Y el eje: se toca SOLO aquel en el que el usuario se movió ──────
  ///
  /// Tratar cada eje con su criterio arregló la mitad del problema, pero
  /// seguía tocando LOS DOS en cada movimiento. Yendo a la derecha dentro de
  /// una fila, el foco no cambia de altura — y sin embargo la lista vertical
  /// recibía igual su «ponela al 35%» y se desplazaba sola.
  ///
  /// Reportado en vivo: «al hacer scroll dentro de una zona, si presiono la
  /// flecha derecha esto baja automáticamente».
  ///
  /// Con [eje] se acomoda únicamente el eje de la flecha que se apretó: la
  /// derecha mueve la fila y no la lista, abajo mueve la lista y no la fila.
  /// En null (foco puesto por código, no por una flecha) se acomodan los dos,
  /// que es lo correcto ahí: no hay dirección que respetar y lo que se acaba
  /// de enfocar puede estar fuera de la vista en cualquiera de los dos.
  static void _traerALaVista(BuildContext ctx, Duration duracion, Axis? eje) {
    final objetivo = ctx.findRenderObject();
    if (objetivo == null) return;
    var contexto = ctx;
    var scroll = Scrollable.maybeOf(contexto);
    while (scroll != null) {
      final posicion = scroll.position;
      if (eje != null && posicion.axis != eje) {
        // Este scroll no es del eje en el que el usuario se movió: no se
        // toca. Pero se sigue subiendo por los ancestros, porque más arriba
        // puede haber otro que SÍ lo sea.
        contexto = scroll.context;
        scroll = Scrollable.maybeOf(contexto);
        continue;
      }
      if (posicion.axis == Axis.vertical) {
        posicion.ensureVisible(
          objetivo,
          alignment: 0.35,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: duracion,
          curve: Curves.easeOut,
        );
      } else {
        _acomodarDeCostado(posicion, objetivo, duracion);
      }
      contexto = scroll.context;
      scroll = Scrollable.maybeOf(contexto);
    }
  }

  /// Corre la fila de costado, dejando asomar la tarjeta que sigue.
  ///
  /// ── Por qué no alcanza con `ensureVisible` ──────────────────────────
  ///
  /// La política `keepVisibleAtEnd` hace lo que promete: mueve lo mínimo para
  /// que la tarjeta entre entera. El problema es justamente ese mínimo — deja
  /// la tarjeta enfocada PEGADA al filo derecho, con la siguiente entera
  /// afuera. Desde el sillón eso se ve como que la fila se terminó ahí, y no
  /// hay forma de saber que apretando derecha viene más.
  ///
  /// Reportado en vivo: «al ir a la derecha, mostrando cards de una
  /// extensión, que se muevan cuando está en la última y así se vea que hay
  /// más».
  ///
  /// Así que en vez de parar en el filo, se corre un poco de más: lo que
  /// mide un tercio de tarjeta. La que sigue queda asomando, que es la señal
  /// de «hay más de este lado» que usan todas las apps de televisor.
  ///
  /// ── Y por qué la cuenta se hace a mano ──────────────────────────────
  ///
  /// `ensureVisible` con `alignment` explícito sirve para poner algo en un
  /// punto fijo, pero mueve SIEMPRE, incluso sobre una tarjeta que ya se veía
  /// perfecta. Eso es el temblorcito que se reportó antes: «al seleccionar una
  /// card se mueve un poquito, y al desmarcarla se reacomoda otra vez».
  ///
  /// Preguntándole al viewport los dos offsets límite se puede distinguir los
  /// tres casos —se fue por la derecha, se fue por la izquierda, o ya se ve
  /// entera— y en el tercero NO SE MUEVE NADA, que es la mitad del arreglo.
  static void _acomodarDeCostado(
    ScrollPosition posicion,
    RenderObject objetivo,
    Duration duracion,
  ) {
    final viewport = RenderAbstractViewport.maybeOf(objetivo);
    if (viewport == null) {
      // Sin viewport no hay cuentas que hacer; queda el comportamiento de
      // antes, que al menos garantiza que se vea.
      posicion.ensureVisible(
        objetivo,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: duracion,
        curve: Curves.easeOut,
      );
      return;
    }
    // Los dos extremos: cuánto habría que desplazar para que la tarjeta
    // quede justo tocando el filo de salida (`alFinal`) o el de entrada
    // (`alPrincipio`). Con la tarjeta más angosta que la fila —el caso
    // normal— `alFinal` es el menor de los dos, y todo el rango entre ambos
    // es «la tarjeta se ve entera».
    final alFinal = viewport.getOffsetToReveal(objetivo, 1).offset;
    final alPrincipio = viewport.getOffsetToReveal(objetivo, 0).offset;
    final actual = posicion.pixels;
    // Lo que se deja asomar de la vecina. Sale del ancho de la propia
    // tarjeta y no de un número fijo, así vale igual para un póster angosto
    // de una zona que para una tarjeta ancha de Biblioteca.
    final asomo = objetivo.paintBounds.width * 0.35;
    final double destino;
    if (actual < alFinal) {
      destino = alFinal + asomo; // se fue por la derecha
    } else if (actual > alPrincipio) {
      destino = alPrincipio - asomo; // se fue por la izquierda
    } else {
      return; // ya se ve entera: no se toca nada
    }
    final acotado =
        destino.clamp(posicion.minScrollExtent, posicion.maxScrollExtent);
    // En los extremos de la fila el acotado puede dejar el destino donde ya
    // estamos. Animar cero píxeles no se ve, pero igual arranca un
    // `ScrollActivity` que cancela el desplazamiento en curso — y encadenando
    // pulsaciones rápidas del mando eso sí se siente como un tirón.
    if ((acotado - actual).abs() < 1) return;
    posicion.animateTo(acotado, duration: duracion, curve: Curves.easeOut);
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
    // Se anota ANTES de cualquier corte. Este manejador devuelve temprano en
    // el caso normal —cuando hay foco no hay nada que rescatar— y ese es
    // justamente el caso del que hay que registrar la dirección: es el
    // movimiento que después va a acomodar el scroll. Anotarlo más abajo lo
    // dejaba en null siempre y `_traerALaVista` seguía tocando los dos ejes.
    //
    // Y este es el sitio y no un `Focus` de la app: `addEarlyKeyEventHandler`
    // ve TODAS las teclas antes que el árbol, así que la dirección queda
    // registrada aunque la flecha la termine atendiendo otro.
    _ultimoEje = _ejeDe(evento.logicalKey);
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
