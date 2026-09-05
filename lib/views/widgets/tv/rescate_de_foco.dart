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

  /// Cuándo se apretó esa flecha.
  ///
  /// ── Por qué hace falta, y no alcanza con consumirlo una vez ──────────
  ///
  /// Antes el eje se leía y se ponía en null en el PRIMER cambio de foco
  /// posterior. El problema es que una sola pulsación puede provocar VARIOS
  /// cambios de foco: `FocoConTopes` deshace los movimientos que no
  /// corresponden devolviendo el foco a donde estaba, y eso es un segundo
  /// cambio. Ese segundo llegaba con el eje ya consumido —o sea en null—,
  /// que es el caso de «lo puso el código, acomodá los dos ejes»: la lista
  /// vertical se acomodaba al 35% aunque el usuario hubiera apretado
  /// derecha, o rebotaba estando quieto. Reportado en vivo: «al bajar me
  /// sube arriba, se pierde el foco».
  ///
  /// Con la marca de tiempo, el eje vale para TODOS los cambios de foco que
  /// dispare esa misma pulsación, y deja de valer solo, sin que nadie tenga
  /// que acordarse de limpiarlo.
  static DateTime? _cuandoSeApreto;

  /// Cuánto sigue valiendo la dirección de la última flecha. Alcanza de
  /// sobra para los cambios de foco encadenados de una misma pulsación
  /// (todos pasan en el mismo cuadro o el siguiente) y es mucho menos que
  /// lo que tarda cualquier persona en pasar de navegar con el mando a que
  /// el foco lo mueva el código por entrar a otra pantalla.
  static const _validezDelEje = Duration(milliseconds: 400);

  /// El eje de la última flecha, si todavía cuenta como «este movimiento».
  static Axis? get _ejeVigente {
    final cuando = _cuandoSeApreto;
    if (cuando == null) return null;
    if (DateTime.now().difference(cuando) > _validezDelEje) return null;
    return _ultimoEje;
  }

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
  /// El último sitio donde el foco estuvo de verdad.
  ///
  /// Sirve para devolverlo ahí si se pierde — ver `_recuperarElFoco`.
  static FocusNode? _ultimoBueno;

  /// Devuelve el foco apenas se pierde, sin esperar a la tecla siguiente.
  ///
  /// ── Por qué no alcanzaba con el rescate por tecla ────────────────────
  ///
  /// El manejador de teclas de más abajo ya recuperaba el foco perdido,
  /// pero recién cuando el usuario apretaba OTRA flecha. Entre una cosa y
  /// la otra la selección sencillamente NO SE VE: uno se queda mirando una
  /// pantalla sin nada resaltado sin saber si se rompió algo. Reportado en
  /// vivo, reincidente: «sigue desapareciendo la selección».
  ///
  /// Y el foco se pierde por motivos normales que no son culpa de nadie: la
  /// lista recicla la tarjeta que lo tenía cuando el desplazamiento la saca
  /// de la vista, o la fila se rearma al llegar contenido nuevo.
  ///
  /// Devolverlo al ÚLTIMO SITIO BUENO es mejor que buscar el primer
  /// enfocable que haya (que es lo que hace el rescate por tecla, y por eso
  /// termina saltando lejos): si ese sitio sigue existiendo, la selección
  /// vuelve exactamente donde estaba y desde afuera no pasó nada.
  void _recuperarElFoco() {
    // ── A qué ámbito cayó el foco ─────────────────────────────────────────
    //
    // Cuando se navega a una pantalla nueva que todavía no puso el foco en
    // nada —ningún `autofocus`, nada pedido en su `initState`— el foco cae
    // acá igual que cuando se pierde por un motivo normal (una tarjeta que
    // se recicla, un panel que se cierra). Los dos casos entran por el mismo
    // lado, pero NO son lo mismo: en el primero no hay nada que rescatar
    // porque nunca hubo nada enfocado EN ESTA pantalla.
    final actual = FocusManager.instance.primaryFocus;
    final ambito = actual is FocusScopeNode
        ? actual
        : (actual?.nearestScope ?? FocusManager.instance.rootScope);
    final ultimo = _ultimoBueno;
    // ── Por qué no alcanza con `ultimo.canRequestFocus` ──────────────────
    //
    // Cada pantalla de Navigator sigue viva DEBAJO de la que se acaba de
    // abrir encima —Flutter no la destruye, solo deja de mostrarla— así que
    // el último nodo bueno de la pantalla ANTERIOR sigue teniendo un
    // `context` válido y `canRequestFocus` en true. Devolverle el foco ahí
    // es justo el bug reportado en vivo: «se pone la pantalla pero se
    // navega por detrás, en la zona donde estaba» — el repositorio de
    // extensiones y el historial, las dos sin ningún `autofocus` propio,
    // se quedaban recibiendo las flechas del Inicio de atrás.
    //
    // La pertenencia al MISMO ámbito que acaba de quedar activo es lo que
    // distingue los dos casos: si el último nodo bueno vive en otro ámbito
    // —la pantalla de atrás—, no es un rescate, es una pantalla nueva sin
    // nada puesto todavía.
    if (ultimo != null &&
        ultimo.context != null &&
        ultimo.canRequestFocus &&
        ultimo.nearestScope == ambito) {
      // Después del cuadro: si el foco se perdió porque algo se estaba
      // desmontando, pedirlo en el mismo instante puede volver a perderse
      // cuando ese desmontaje termine.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final actual2 = FocusManager.instance.primaryFocus;
        // Alguien ya lo recuperó por su cuenta: no se pisa.
        if (actual2 != null &&
            actual2 is! FocusScopeNode &&
            actual2.context != null) {
          return;
        }
        if (ultimo.context == null || !ultimo.canRequestFocus) return;
        ultimo.requestFocus();
      });
      return;
    }
    // ── Pantalla nueva: se busca el primer enfocable DENTRO de ella ──────
    //
    // El mismo camino que ya usa el rescate por tecla (`_alLlegarUnaTecla`,
    // más abajo) para el caso "el mando parece muerto": pedírselo al ámbito
    // que tiene el foco encuentra lo primero enfocable de la pantalla que
    // se está viendo, nunca de otra.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final actual2 = FocusManager.instance.primaryFocus;
      if (actual2 != null &&
          actual2 is! FocusScopeNode &&
          actual2.context != null) {
        return;
      }
      ambito.nextFocus();
    });
  }

  void _alCambiarElFoco() {
    final nodo = FocusManager.instance.primaryFocus;
    final ctx = nodo?.context;
    if (ctx == null || nodo is FocusScopeNode) {
      _recuperarElFoco();
      return;
    }
    _ultimoBueno = nodo;
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
      // El eje NO se consume acá: caduca solo (ver _ejeVigente). Una misma
      // pulsación puede provocar varios cambios de foco —FocoConTopes
      // deshace los que no corresponden— y todos son parte del MISMO
      // movimiento, así que todos tienen que respetar la misma dirección.
      _traerALaVista(ctx, duracion, _ejeVigente);
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
  /// ── Cada scroll se acomoda contra SU PROPIO objetivo ──────────────────
  ///
  /// Una tarjeta vive dentro de una fila que desliza de costado, y esa fila
  /// vive dentro de la lista que desliza hacia abajo. Son dos scrolls, uno
  /// adentro del otro.
  ///
  /// Acá había un fallo feo: se usaba SIEMPRE la misma tarjeta como objetivo
  /// para los dos niveles. Y las cuentas de `_acomodar` salen del viewport
  /// que envuelve al objetivo, que para una tarjeta es SIEMPRE el de más
  /// adentro —la fila horizontal—, nunca el de la lista vertical. O sea que
  /// al acomodar la lista vertical se le pedían offsets calculados contra
  /// otro viewport: números que no significan nada para ella. El destino que
  /// salía de ahí podía quedar fuera de rango y terminaba recortado contra
  /// el principio de la lista, que se ve como que el scroll «se vuelve
  /// arriba solo». Reportado en vivo justo donde hay filas anidadas: las de
  /// las extensiones.
  ///
  /// Lo correcto es lo que hace el propio `ensureVisible` de Flutter por
  /// dentro: al subir un nivel, lo que hay que traer a la vista ya no es la
  /// tarjeta sino LA FILA ENTERA que la contiene. Así cada scroll recibe un
  /// objetivo que de verdad es hijo suyo, y sus cuentas vuelven a
  /// significar lo que dicen.
  static void _traerALaVista(BuildContext ctx, Duration duracion, Axis? eje) {
    RenderObject? objetivo = ctx.findRenderObject();
    if (objetivo == null) return;
    var contexto = ctx;
    var scroll = Scrollable.maybeOf(contexto);
    while (scroll != null) {
      final posicion = scroll.position;
      // Este scroll no es del eje en el que el usuario se movió: no se
      // toca. Pero se sigue subiendo por los ancestros, porque más arriba
      // puede haber otro que SÍ lo sea.
      final actual = objetivo;
      if (actual != null && (eje == null || posicion.axis == eje)) {
        _acomodar(posicion, actual, duracion);
      }
      contexto = scroll.context;
      // El objetivo del siguiente nivel es este scroll: para la lista
      // vertical, lo que tiene que entrar en pantalla es la fila completa.
      final siguiente = contexto.findRenderObject();
      if (siguiente == null) return;
      objetivo = siguiente;
      scroll = Scrollable.maybeOf(contexto);
    }
  }

  /// Acomoda UN scroll —da igual el eje— con una sola regla: si lo enfocado
  /// ya se ve entero, no se toca nada; si no, se mueve lo justo para que
  /// entre, más un asomo de la vecina.
  ///
  /// ── Por qué el vertical dejó de ir «al 35%» ──────────────────────────
  ///
  /// Antes el eje vertical usaba `ensureVisible(alignment: 0.35)`, o sea
  /// «poné lo enfocado a un tercio desde arriba». Eso mueve la lista SIEMPRE,
  /// incluso cuando la tarjeta que se acaba de enfocar ya se veía perfecta —
  /// y ese es exactamente el salto que se reportó en vivo: «quiero ir abajo y
  /// se mueve hacia abajo automático», «al bajar me sube arriba», «debe ir
  /// poco a poco cada card, no saltar».
  ///
  /// La regla nueva es la que ya usaba el eje horizontal y funcionaba bien:
  /// preguntarle al viewport los dos offsets límite —el que deja la tarjeta
  /// tocando el filo de entrada y el que la deja tocando el de salida— para
  /// distinguir tres casos. Si la posición actual cae ENTRE los dos, la
  /// tarjeta se ve entera y no hay nada que hacer. Si se pasó de uno de los
  /// dos lados, se mueve hasta ese filo y un poco más, para que la de al lado
  /// asome y se note que la lista sigue.
  ///
  /// Con esto la cámara solo se mueve cuando de verdad hace falta —cuando lo
  /// que se enfocó no entra en pantalla— y se mueve una tarjeta por vez, que
  /// es lo que se pidió.
  static void _acomodar(
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
    final alFinal = viewport.getOffsetToReveal(objetivo, 1).offset;
    final alPrincipio = viewport.getOffsetToReveal(objetivo, 0).offset;
    final actual = posicion.pixels;
    // Lo que se deja asomar de la vecina. Sale del tamaño de la propia
    // tarjeta en el eje que corresponde, no de un número fijo, así vale
    // igual para un póster angosto que para una fila alta.
    final caja = objetivo.paintBounds;
    final asomo =
        (posicion.axis == Axis.vertical ? caja.height : caja.width) * 0.35;
    // ── Los dos límites, ordenados ──────────────────────────────────────
    //
    // Con lo enfocado más chico que la pantalla —el caso normal— el límite
    // de salida es el menor de los dos, y todo el rango entre ambos es «se
    // ve entero». Pero si lo enfocado es MÁS ALTO que la pantalla (una fila
    // grande en un televisor de poca altura) los dos límites se dan vuelta,
    // y comparándolos en el orden fijo de antes la cuenta decidía justo lo
    // contrario: mandaba a desplazarse hacia atrás. Ordenándolos primero,
    // el caso normal queda exactamente igual que antes y el raro deja de
    // poder mandar el scroll para el lado equivocado.
    final limiteBajo = alFinal < alPrincipio ? alFinal : alPrincipio;
    final limiteAlto = alFinal < alPrincipio ? alPrincipio : alFinal;
    final double destino;
    if (actual < limiteBajo) {
      destino = limiteBajo + asomo; // quedó pasado el filo de salida
    } else if (actual > limiteAlto) {
      destino = limiteAlto - asomo; // quedó antes del filo de entrada
    } else {
      return; // ya se ve entero: no se toca nada
    }
    final acotado =
        destino.clamp(posicion.minScrollExtent, posicion.maxScrollExtent);
    // En los extremos, el acotado puede dejar el destino donde ya estamos.
    // Animar cero píxeles no se ve, pero igual arranca un `ScrollActivity`
    // que cancela el desplazamiento en curso — y encadenando pulsaciones
    // rápidas del mando eso sí se siente como un tirón.
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
    _cuandoSeApreto = _ultimoEje == null ? null : DateTime.now();
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
