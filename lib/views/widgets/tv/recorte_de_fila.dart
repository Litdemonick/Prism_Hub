import 'package:flutter/widgets.dart';

/// Recorta una fila horizontal a izquierda y derecha, y la deja abierta
/// arriba y abajo.
///
/// ── Para qué ────────────────────────────────────────────────────────────
///
/// Una fila de tarjetas necesita dos cosas contradictorias:
///
///   · Que NO se corte arriba y abajo, porque por ahí sale el resplandor del
///     foco y el marco de selección, que sobresalen de la tarjeta a propósito.
///   · Que SÍ se corte a los costados, porque las tarjetas que se van
///     desplazando fuera de la fila se siguen dibujando: sin recorte se
///     pintan sobre el margen y, en televisor, encima del rail de categorías.
///
/// `clipBehavior: Clip.none` a secas resuelve lo primero y rompe lo segundo —
/// no distingue ejes. Reportado con foto: «las cards se comen la zona del
/// panel izquierdo» y «los botones están atrás del card».
///
/// Este recortador devuelve un rectángulo más alto que la fila y apenas más
/// ancho: corta donde molesta y deja pasar donde hace falta.
class RecorteDeFila extends CustomClipper<Rect> {
  const RecorteDeFila({this.aireLateral = 0});

  /// Cuánto se deja escapar arriba y abajo. Con el resplandor actual sobra.
  static const _aire = 60.0;

  /// Y cuánto a los costados.
  ///
  /// Cero en teléfono y escritorio: ahí el recorte lateral existe justamente
  /// para que una tarjeta que sale de la fila no se dibuje sobre el margen.
  ///
  /// En televisor no puede ser cero: la tarjeta enfocada lleva un marco que
  /// sobresale por fuera de ella, y con el corte al ras quedaba mordido por
  /// los dos lados — reportado en vivo: «se corta el borde de selección de la
  /// card». El aire tiene que ser mayor que ese marco y menor que la
  /// distancia hasta el rail, así que cualquier valor holgado en el medio
  /// sirve; se usa 24.
  final double aireLateral;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        -aireLateral,
        -_aire,
        size.width + aireLateral,
        size.height + _aire,
      );

  @override
  bool shouldReclip(covariant RecorteDeFila oldClipper) =>
      oldClipper.aireLateral != aireLateral;
}

/// Un desvanecido a los dos costados de una fila, para televisor.
///
/// ── Para qué ────────────────────────────────────────────────────────────
///
/// Sin esto, la tarjeta del borde termina en un filo recto contra el margen
/// y la fila se lee como si ahí se acabara. Con el degradado se sigue viendo
/// entera pero atenuada, como asomando — que es lo que dice «esto sigue para
/// el costado». Pedido explícito: «dale ese degradado de que se pierden las
/// cards», y después: «me gusta ese difuminado del Inicio, replicalo a las
/// demás zonas».
///
/// No recorta nada nuevo: sobre lo que ya deja pasar [RecorteDeFila], baja
/// la opacidad hacia los dos extremos.
///
/// ── Por qué vive acá ────────────────────────────────────────────────────
///
/// Nació dentro de la fila del Inicio y las zonas lo copiaban… o no: las de
/// Películas, Series y Anime se quedaron sin él, y por eso ahí las tarjetas
/// se cortaban en seco. Estando al lado del recorte que ya comparten las
/// dos, la próxima fila que se escriba lo tiene disponible sin tener que
/// acordarse de dónde estaba.
/// ── Y solo del lado donde SIGUE habiendo fila ───────────────────────────
///
/// El degradado fijo atenúa los dos bordes siempre, también cuando de ese
/// lado ya no queda nada: la PRIMERA tarjeta se ve apagada estando la fila
/// al principio, y la ÚLTIMA igual, aunque no haya nada más que anunciar.
/// Con el marco de foco encima se nota todavía más — se ve fino y comido.
/// Reportado con foto: «a la izquierda se ve delgado» y «a la derecha, que
/// se vea bien cuando es la última y no difumine tanto».
///
/// Pasándole el [scroll] de la fila, cada lado se desvanece solo si por ahí
/// hay algo más. Al principio el borde izquierdo queda nítido, al final el
/// derecho, y en el medio los dos difuminan como corresponde.
class DesvanecidoDeFila extends StatefulWidget {
  const DesvanecidoDeFila({super.key, required this.child, this.scroll});

  final Widget child;

  /// El desplazamiento de la fila. Sin él se desvanecen los dos lados
  /// siempre, que es como se comportaba antes.
  final ScrollController? scroll;

  @override
  State<DesvanecidoDeFila> createState() => _DesvanecidoDeFilaState();
}

class _DesvanecidoDeFilaState extends State<DesvanecidoDeFila> {
  /// Cuánto mide el borde difuminado, en puntos.
  ///
  /// Suficiente para que la tarjeta del costado se lea como «sigue» sin que
  /// llegue a apagarse: es un borde, no una sombra encima de la tarjeta.
  ///
  /// ── Por qué bajó de 38 ──────────────────────────────────────────────
  ///
  /// Es una medida en PUNTOS, fija, y una tarjeta angosta —las del
  /// buscador miden bastante menos que las de Inicio o una zona— se come
  /// una porción mucho mayor de su propio ancho con el mismo borde.
  /// Contra un póster con una cara o un detalle justo ahí, esos 38 puntos
  /// se leían como una sombra negra encima de la imagen, no como un borde
  /// que se pierde. Reportado en vivo con foto: «esa franja como una
  /// sombra negra ahí al frente de la cara».
  ///
  /// Con un borde más angosto sigue notándose que la fila sigue —que es
  /// para lo que existe— pero se lleva puesto mucho menos de cada
  /// tarjeta, sea grande o chica.
  static const _anchoDelBorde = 22.0;

  @override
  void initState() {
    super.initState();
    widget.scroll?.addListener(_alDesplazarse);
    // ── Y una comprobación al arrancar, no solo al mover ────────────────
    //
    // `_quedaAdelante` nace en `true` —una suposición razonable antes de
    // medir nada— y lo único que la corrige es `_alDesplazarse`, que
    // cuelga de un scroll que se mueve. Una fila CORTA, con todos sus
    // ítems ya visibles de entrada, no dispara ni un solo evento de
    // scroll en toda su vida: nunca hay nada que desplazar. El resultado
    // era ese difuminado del lado derecho quedando puesto PARA SIEMPRE, en
    // una fila que ya mostraba todo lo que tenía. Reportado en vivo, con
    // foto, muchas veces, como «una sombra estática que no se mueve» —y
    // no se movía porque nada la estaba actualizando.
    //
    // Después del primer cuadro, cuando el scroll ya sabe cuánto mide de
    // verdad, se hace la misma cuenta una vez más — así una fila corta
    // arranca sabiendo que no le queda nada por ningún lado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _alDesplazarse();
    });
  }

  @override
  void didUpdateWidget(DesvanecidoDeFila viejo) {
    super.didUpdateWidget(viejo);
    if (!identical(viejo.scroll, widget.scroll)) {
      viejo.scroll?.removeListener(_alDesplazarse);
      widget.scroll?.addListener(_alDesplazarse);
    }
    // ── Y también cuando cambia el CONTENIDO, no solo cuando se mueve ──
    //
    // `_alDesplazarse` solo lo dispara el propio ScrollController cuando
    // la POSICIÓN cambia — pero una fila de resultados de búsqueda puede
    // cambiar de CONTENIDO (una letra nueva trae una lista distinta, más
    // corta o más larga) mientras el scroll se queda clavado en el mismo
    // punto, típicamente el 0. Con menos ítems que antes, `_quedaAdelante`
    // seguía en `true` de la búsqueda anterior aunque la nueva lista
    // completa ya entrara sin necesidad de desplazarse; con más ítems,
    // podía quedar en `false` aunque ahora sí sobrara para el lado
    // contrario. En los dos casos el difuminado quedaba mostrando algo
    // que no correspondía a lo que hay ahora. Reportado en vivo con foto,
    // en el buscador: «sigue estando esa franja negra en la card, cuando
    // algo se escribe en el search».
    //
    // El mismo remedio que ya usa `initState` para la primera medición:
    // esperar al cuadro siguiente (para que el nuevo contenido ya esté
    // dispuesto, con su `maxScrollExtent` real) y volver a medir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _alDesplazarse();
    });
  }

  @override
  void dispose() {
    widget.scroll?.removeListener(_alDesplazarse);
    super.dispose();
  }

  /// Solo se redibuja cuando de verdad cambia si hay o no hay más de un
  /// lado, no en cada píxel del desplazamiento: en un televisor modesto
  /// repintar la fila entera a cada paso se paga caro.
  bool _quedaAtras = false;
  bool _quedaAdelante = true;

  void _alDesplazarse() {
    final s = widget.scroll;
    if (s == null || !s.hasClients || !mounted) return;
    final p = s.position;
    // Un par de píxeles de tolerancia: en los extremos el desplazamiento no
    // cae siempre en el número exacto.
    final atras = p.pixels > p.minScrollExtent + 2;
    final adelante = p.pixels < p.maxScrollExtent - 2;
    if (atras == _quedaAtras && adelante == _quedaAdelante) return;
    setState(() {
      _quedaAtras = atras;
      _quedaAdelante = adelante;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sin scroll del que colgarse, se desvanecen los dos lados: es lo que
    // hacía antes y sigue siendo razonable para una fila que no se mueve.
    final izquierda = widget.scroll == null || _quedaAtras;
    final derecha = widget.scroll == null || _quedaAdelante;
    return ShaderMask(
      shaderCallback: (rect) {
        // ── El borde se mide en PÍXELES, no en porcentaje ───────────────
        //
        // Estaba en un 4% del ancho de la fila. En el Inicio, que ocupa la
        // pantalla entera, eso son unos pocos puntos y se ve como un borde
        // suave. Pero en una fila angosta —los resultados del buscador
        // viven en poco más de medio ancho— ese mismo 4% se come una
        // tarjeta entera: en vez de un degradado se veía una sombra plana y
        // fea encima de la primera y la última, y el marco de selección de
        // esa tarjeta quedaba lavado. Reportado con foto: «la difuminación
        // está mal, es una sombra toda estática fea; replicalo como en el
        // Inicio».
        //
        // Con una medida fija el borde se ve igual en cualquier fila, sea
        // del ancho que sea, y nunca alcanza a apagar una tarjeta entera.
        final borde = (_anchoDelBorde / rect.width).clamp(0.0, 0.12);
        // ── Y la curva, suave: no una rampa recta ───────────────────────
        //
        // Con solo dos paradas por lado, el degradado sube de golpe y sobre
        // una portada clara se lee como una BANDA oscura pegada al borde,
        // no como algo que se desvanece. Reportado con foto: «se ve esa
        // sombra ahí, no se ve como en las cards de Inicio».
        //
        // Con paradas intermedias la opacidad arranca despacio y termina
        // despacio, que es lo que hace que la tarjeta parezca perderse
        // detrás del borde en vez de tener una sombra encima.
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Color(0x00000000),
            Color(0x59000000),
            Color(0xC4000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0xC4000000),
            Color(0x59000000),
            Color(0x00000000),
          ],
          // Un lado sin nada más allá no difumina: sus paradas se pegan al
          // borde y el degradado de ese extremo deja de existir.
          stops: [
            0,
            izquierda ? borde * 0.35 : 0,
            izquierda ? borde * 0.7 : 0,
            izquierda ? borde : 0,
            derecha ? 1 - borde : 1,
            derecha ? 1 - borde * 0.7 : 1,
            derecha ? 1 - borde * 0.35 : 1,
            1,
          ],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: widget.child,
    );
  }
}
