import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/views/widgets/detail/detail_extension_tile.dart';
import 'package:prismhub/views/widgets/detail/portada_con_relevo.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Las medidas de la cabecera de la ficha, en un solo lugar.
///
/// Antes el alto era un número fijo que vivía en `detail_page.dart` (440 en
/// vertical, 200 en horizontal) y las piezas de adentro se calculaban aparte a
/// partir de ese mismo número. Los dos lados tenían que coincidir a mano y no
/// coincidían: en horizontal la portada terminaba de 80 puntos —"ni se ve la
/// imagen"— y en vertical el bloque quedaba DEBAJO de la barra de pestañas,
/// porque nadie descontaba su alto.
///
/// Ahora las dos cosas salen de acá, del tamaño real que hay disponible: la
/// página pide [alto] para el SliverAppBar y la cabecera dibuja adentro con
/// las mismas medidas. No hay dos números que puedan discrepar.
class MedidasCabecera {
  MedidasCabecera({
    required this.disponible,
    required double proporcionPortada,
    this.reservaInferior = 48,
  }) : proporcion = proporcionPortada > 0 ? proporcionPortada : 0.7;

  /// Lo que hay para trabajar, SIN la barra de estado: el SliverAppBar le suma
  /// esa altura por su cuenta (`maxExtent = topPadding + expandedHeight`).
  final Size disponible;

  /// Ancho por cada unidad de alto de la portada. Ver
  /// [DetailPageController.portadaProporcion].
  final double proporcion;

  /// Alto de la barra de pestañas.
  ///
  /// Flutter la dibuja pegada ABAJO DE TODO del SliverAppBar, no debajo del
  /// toolbar: en `app_bar.dart` el toolbar y el `bottom:` van en un Column con
  /// `spaceBetween` que ocupa la caja entera, y el `flexibleSpace` va detrás de
  /// esa caja completa. Sin descontarla acá, la fila de botones queda tapada
  /// por las pestañas. Va en 0 cuando la página no dibuja pestañas.
  final double reservaInferior;

  /// Alto del toolbar (la fila del botón de atrás).
  static const double barraSuperior = 56;

  /// Aire entre el toolbar y el contenido.
  static const double aireSuperior = 10;

  /// Aire contra el borde de abajo del bloque. 24 y no 18: los botones
  /// quedaban rozando la barra de pestañas y el bloque se veía apretado
  /// contra el final de la cabecera.
  static const double aireInferior = 24;

  /// Margen lateral.
  static const double margen = 20;

  /// La cabecera se arma en UNA FILA (portada a la izquierda, título y botones
  /// a la derecha) cuando hay poco alto.
  ///
  /// Se decide por el alto disponible y no por la orientación del aparato: con
  /// dos paneles la columna de la ficha puede ser angosta y alta o ancha y
  /// baja, y lo que manda es cuánto alto queda, no cómo está puesto el
  /// teléfono.
  bool get enFila => disponible.height < 480;

  /// Lo que se llevan las piezas de alto fijo.
  double get _reservado =>
      barraSuperior + aireSuperior + aireInferior + reservaInferior;

  /// El piso: lo que pide el texto aunque la portada sea chiquita.
  ///
  /// Va medido, no a ojo, porque de acá salía que en el teléfono el título se
  /// cortara. En columna son 3 líneas de título (21 × 1,2 × 3 = 76), el aire
  /// de 8, y la línea de la extensión, que con el nombre, el tipo y el
  /// distintivo de estado baja a dos renglones (78). En fila el título entra
  /// en 2 líneas (41) y la línea de la extensión es la misma.
  double get _minimoTexto => enFila ? 125 : 162;

  /// Alto del bloque portada + texto.
  double get _bloque {
    final anchoIdeal =
        (disponible.width * (enFila ? 0.24 : 0.30)).clamp(96.0, 220.0);
    final pedido = math.max(anchoIdeal / proporcion, _minimoTexto);
    // Techo: la cabecera no se puede comer la pantalla. Con el número fijo de
    // antes, en una ventana baja el bloque no entraba, se salía por arriba y se
    // metía debajo del botón de atrás.
    // 0,62 en fila y no 0,70: en una pantalla baja la cabecera se llevaba casi
    // dos tercios del alto y lo que quedaba abajo no alcanzaba para nada — el
    // contenido empujaba hacia arriba y se metía debajo de las pestañas.
    final techo = disponible.height * 0.62 - _reservado;
    return pedido.clamp(72.0, math.max(72.0, techo));
  }

  /// El alto que hay que pedirle al SliverAppBar.
  double get alto => _reservado + _bloque;

  double get altoPortada {
    // La portada no se lleva más de una parte del ancho: con una apaisada
    // (proporción > 1) el alto del bloque la haría enorme y el título se
    // quedaría sin lugar.
    final porElAncho = disponible.width * (enFila ? 0.30 : 0.42) / proporcion;
    return math.min(_bloque, porElAncho);
  }

  double get anchoPortada => altoPortada * proporcion;

  /// Alto del título. En fila comparte espacio con los botones, así que entra
  /// menos texto.
  int get lineasTitulo => enFila ? 2 : 3;

  double get tamanoTitulo => enFila ? 17 : 21;

  /// Cuánto hay que desplazar para que la cabecera termine de plegarse.
  ///
  /// Sale del alto real y no de un número suelto: de esta distancia dependen
  /// dos cosas que tienen que estar sincronizadas —cuándo se desvanece el
  /// bloque de la cabecera y cuándo aparece el título en la barra— y con
  /// valores distintos había un tramo con el título en ningún lado.
  double get recorridoDePlegado =>
      (alto - barraSuperior - reservaInferior).clamp(50.0, 400.0);

  /// El punto en el que la barra recoge el título que suelta la cabecera.
  double get relevoDelTitulo => recorridoDePlegado * 0.55;
}

class DetailAppbarflexibleSpace extends StatefulWidget {
  const DetailAppbarflexibleSpace({
    super.key,
    this.tag,
    required this.medidas,
  });

  final String? tag;

  /// Las mismas medidas con las que la página pidió el alto del SliverAppBar.
  /// Se pasan armadas en vez de recalcularlas acá para que no puedan diferir.
  final MedidasCabecera medidas;

  @override
  State<DetailAppbarflexibleSpace> createState() =>
      _DetailAppbarflexibleSpaceState();
}

class _DetailAppbarflexibleSpaceState extends State<DetailAppbarflexibleSpace> {
  late DetailPageController c = Get.find(tag: widget.tag);

  double _offset = 1;
  /// Cuánto se ve el bloque de la cabecera, de 1 a 0 según el desplazamiento.
  ///
  /// ── Por qué un ValueNotifier y no un campo con setState ────────────────
  ///
  /// Era un campo, y `_handleScroll` hacía `setState` en cada cuadro del
  /// desplazamiento. Eso rehacía la cabecera ENTERA sesenta veces por segundo:
  /// el fondo, la portada, la línea de la extensión y el título — y el título
  /// se mide con un TextPainter antes de dibujarse, para saber si hace falta el
  /// botón de «ver completo». O sea que cada cuadro del scroll pagaba una
  /// medición de texto que siempre daba lo mismo.
  ///
  /// Con el notificador, deslizar no reconstruye nada: solo se vuelven a armar
  /// las dos piezas que de verdad dependen del valor —el velo y la caja que se
  /// desvanece— y el contenido de adentro se pasa ya hecho, por `child`.
  final _opacidad = ValueNotifier<double>(1);

  MedidasCabecera get _m => widget.medidas;

  @override
  void initState() {
    super.initState();
    c.scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    c.scrollController.removeListener(_handleScroll);
    _opacidad.dispose();
    super.dispose();
  }

  void _handleScroll() {
    _offset = c.scrollController.offset;
    final next = _scrollListener();
    if ((next - _opacidad.value).abs() < 0.02) return;
    _opacidad.value = next;
  }

  double _scrollListener() {
    // Se desvanece en el primer 55% del recorrido, no en todo.
    //
    // Llegando a 0 justo al final, el titulo y los botones seguian visibles a
    // media opacidad cuando ya estaban encima de la barra de pestañas: se veian
    // los dos textos superpuestos y quedaba sucio. Terminando antes, el bloque
    // ya no esta para cuando las piezas se cruzan. Es la misma distancia con
    // la que la barra recoge el título — ver relevoDelTitulo.
    final fadeDistance = _m.relevoDelTitulo;
    if (_offset <= 0) {
      return 1;
    } else if (_offset >= fadeDistance) {
      return 0;
    } else {
      return (_offset - fadeDistance) / (0 - fadeDistance);
    }
  }

  bool _needShowCover() {
    if (c.isLoading.value) return true;
    if (c.portada != null) return true;
    return false;
  }

  /// La imagen de fondo, ocupando la caja ENTERA.
  ///
  /// Antes iba en un `SizedBox(height: alto)`, que se queda corto: la caja del
  /// SliverAppBar mide `alto + barra de estado`, así que abajo quedaba una
  /// franja sin imagen.
  Widget _background() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Ya no se esconde mientras carga: con la portada que traía la
        // tarjeta hay algo que mostrar desde el primer fotograma, y el
        // relevo se encarga de que el cambio a la definitiva no se note.
        PortadaConRelevo(
          alt: c.data.value?.title ?? '',
          urlPrevia: c.portadaPrevia,
          cabecerasPrevias: c.portadaPreviaHeaders,
          urlFinal: c.portada,
          cabecerasFinales: c.portadaHeaders,
          noText: true,
          // 0.35 (hacia abajo) recortaba de más la parte de arriba
          // de la imagen de fondo — subido a 0 para mostrar más
          // esa zona en vez de sesgar hacia el centro/abajo.
          alignment: const Alignment(0, 0),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x3308090D),
                Color(0xE608090D),
                HomeTheme.bg,
              ],
            ),
          ),
        ),
        // Al plegarse, la imagen se OSCURECE, no desaparece.
        //
        // El velo llega hasta 0,78 y ahí se queda: con 1 la portada se perdía
        // del todo al bajar y volvía al subir, y parecía que la imagen se
        // hubiera ido. Con 0,78 el botón de atrás y el título se leen sobre
        // cualquier portada —arriba el degradado es casi transparente— y la
        // imagen sigue estando. Que la barra tape el cuerpo de la página no
        // depende de este velo sino del fondo del SliverAppBar, que es sólido.
        ValueListenableBuilder<double>(
          valueListenable: _opacidad,
          builder: (context, o, _) => ColoredBox(
            color: HomeTheme.bg.withValues(alpha: (1 - o) * 0.78),
          ),
        ),
      ],
    );
  }

  Widget _coverThumb({required double height, required double width}) {
    return Hero(
      tag: c.heroTag ?? '',
      // AnimatedContainer y no Container: la caja cambia de tamaño en dos
      // momentos —al girar el aparato y cuando se mide la portada de verdad,
      // que corrige la forma— y con un Container el salto es de un fotograma
      // al otro. Animándolo se acomoda en vez de pegar el tirón. La imagen no
      // se deforma en ningún caso: va con la imagen entera y relleno, nunca
      // estirada.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: height,
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HomeTheme.border),
          // La portada es la pieza más importante de la cabecera y va sobre su
          // propia imagen ampliada: sin una sombra que la despegue del fondo,
          // el borde se pierde justo en las portadas de colores oscuros.
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
            fit: StackFit.expand,
            children: [
              // Antes acá había una rueda ocupando toda la miniatura hasta que
              // la extensión contestara. Ahora se dibuja de una la portada que
              // traía la tarjeta, y la rueda pasa a ser una señal chica en la
              // esquina: sigue diciendo que falta algo, pero sin tapar lo que
              // ya se puede ver.
              PortadaConRelevo(
                alt: c.data.value?.title ?? '',
                urlPrevia: c.portadaPrevia,
                cabecerasPrevias: c.portadaPreviaHeaders,
                urlFinal: c.portada,
                cabecerasFinales: c.portadaHeaders,
                // topCenter: en la miniatura chica, BoxFit.cover con el
                // alignment por defecto (center) recortaba parejo arriba
                // y abajo — cortando la parte de arriba de la portada
                // (cara/cabeza, lo más reconocible). Sesgado hacia arriba
                // se ve más completa esa zona.
                alignment: Alignment.topCenter,
                canFullScreen: true,
                // Red de seguridad: la caja ya toma la forma que publica la
                // extensión, pero un título suelto puede traer una portada de
                // otra forma. Así se ve entera igual, con el resto de la caja
                // rellenado con la misma imagen desenfocada — nunca estirada.
                entera: true,
                // Y con la medida de la de verdad, la caja se le ajusta y ese
                // relleno deja de hacer falta. Ver
                // DetailPageController.anotarPortada.
                onTamanoReal: c.anotarPortada,
              ),
              if (c.isLoading.value)
                const Positioned(
                  right: 6,
                  bottom: 6,
                  child: _RuedaChica(),
                ),
            ],
          ),
      ),
    );
  }

  Widget _titulo() {
    return _TituloDeLaFicha(
      texto: c.isLoading.value ? "" : c.data.value!.title,
      lineas: _m.lineasTitulo,
      tamano: _m.tamanoTitulo,
    );
  }

  /// La cabecera: portada, título y la línea de la extensión. Nada más.
  ///
  /// Los botones se fueron de acá a propósito. Ocupaban 62 puntos de alto
  /// justo donde menos hay —un teléfono en vertical— y encima desaparecían al
  /// plegarse la cabecera, que es cuando uno ya está mirando la lista y
  /// quiere darle a leer. Ahora la acción principal es el botón flotante, que
  /// no se va nunca, y favorito y compartir viven en la barra de arriba.
  ///
  /// En columna la portada y el texto se apoyan abajo; en fila (poco alto) van
  /// uno al lado del otro, y así la portada se queda con la franja entera en
  /// vez de terminar en 80 puntos como antes en horizontal.
  Widget _contenido() {
    final portada = _needShowCover()
        ? _coverThumb(height: _m.altoPortada, width: _m.anchoPortada)
        : null;

    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment:
          _m.enFila ? MainAxisAlignment.center : MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _titulo()),
        const SizedBox(height: 8),
        DetailExtensionTile(tag: widget.tag),
      ],
    );

    return Row(
      crossAxisAlignment:
          _m.enFila ? CrossAxisAlignment.center : CrossAxisAlignment.end,
      children: [
        if (portada != null) ...[
          portada,
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: texto,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // La caja del SliverAppBar mide `alto + barra de estado`, y el toolbar
    // (con el botón de atrás) empieza DESPUÉS de esa barra. Sin sumarla, el
    // contenido se metía debajo del botón de atrás.
    final topPadding = MediaQuery.paddingOf(context).top;

    return Obx(
      () => Stack(
        children: [
          // El fondo NO se desvanece con el resto: es lo que tapa el cuerpo de
          // la página cuando la cabecera colapsa. El tema de la app deja la
          // barra transparente (appBarTheme.backgroundColor), así que con el
          // fondo desvanecido se veía la lista de capítulos pasando por encima
          // del botón de atrás.
          // RepaintBoundary: la imagen no cambia mientras se hace scroll, pero
          // el velo de encima sí. Sin esto, cada paso del desplazamiento
          // vuelve a pintar la portada entera.
          Positioned.fill(child: RepaintBoundary(child: _background())),
          Positioned(
            top: topPadding +
                MedidasCabecera.barraSuperior +
                MedidasCabecera.aireSuperior,
            left: MedidasCabecera.margen,
            right: MedidasCabecera.margen,
            bottom: _m.reservaInferior + MedidasCabecera.aireInferior,
            // IgnorePointer: cuando el bloque está desvanecido sigue estando
            // ahí, y sus botones seguían recibiendo toques. Con la cabecera
            // plegada se podía tocar "Continuar" sin verlo, a través de la
            // barra.
            child: ValueListenableBuilder<double>(
              valueListenable: _opacidad,
              // El contenido se arma UNA vez y se pasa hecho: deslizar solo
              // cambia la opacidad y el desplazamiento, no lo que hay adentro.
              child: _contenido(),
              builder: (context, o, contenido) => IgnorePointer(
                ignoring: o < 0.05,
                child: Opacity(
                  opacity: o,
                  // Además de desvanecerse, el bloque se va un poco hacia
                  // arriba. Solo con la opacidad el cambio se lee como un
                  // parpadeo; acompañándolo con un desplazamiento chico se
                  // entiende que la cabecera se está plegando.
                  child: Transform.translate(
                    offset: Offset(0, (1 - o) * -14),
                    child: contenido,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El título de la ficha y, si no entra entero, un botón para verlo completo.
///
/// Con puntos suspensivos y nada más, un título largo quedaba cortado sin
/// ninguna forma de leer el resto — y es lo primero que uno quiere leer. El
/// botón solo aparece cuando hace falta: se mide el texto antes de dibujarlo,
/// así que en los títulos que entran no hay ningún adorno de más.
class _TituloDeLaFicha extends StatelessWidget {
  const _TituloDeLaFicha({
    required this.texto,
    required this.lineas,
    required this.tamano,
  });

  final String texto;
  final int lineas;
  final double tamano;

  void _verCompleto(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: HomeTheme.cardSurface,
      showDragHandle: true,
      // Como el resto de las hojas de la app: en una tablet, un panel de lado
      // a lado para dos renglones de texto se ve perdido.
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
        child: SelectableText(
          texto,
          style: TextStyle(
            color: HomeTheme.sobrePortada,
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: tamano,
      height: 1.2,
      fontWeight: FontWeight.w800,
      color: HomeTheme.sobrePortada,
      // El título va sobre la propia portada ampliada. En una imagen clara el
      // texto blanco se comía con el fondo aunque el degradado ayude.
      shadows: const [
        Shadow(color: Color(0xCC000000), blurRadius: 12),
      ],
    );

    final linea = Text(
      texto,
      softWrap: true,
      maxLines: lineas,
      overflow: TextOverflow.ellipsis,
      style: estilo,
    );

    if (texto.isEmpty) return linea;

    return LayoutBuilder(
      builder: (context, cons) {
        if (!cons.hasBoundedWidth) return linea;
        // Se mide con el ancho ENTERO: si ya no entra teniendo todo el lugar,
        // tampoco va a entrar dejándole sitio al botón. Al revés sí podría
        // fallar (medir con el hueco descontado haría aparecer el botón en
        // títulos que sí entraban).
        final medidor = TextPainter(
          text: TextSpan(text: texto, style: estilo),
          maxLines: lineas,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: cons.maxWidth);
        final cortado = medidor.didExceedMaxLines;
        medidor.dispose();

        if (!cortado) return linea;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: linea),
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 20,
                // El propio título como ayuda: mantener pulsado ya lo muestra,
                // sin abrir nada y sin inventar una cadena nueva que traducir.
                tooltip: texto,
                color: HomeTheme.sobrePortada,
                icon: const Icon(Icons.more_horiz_rounded),
                onPressed: () => _verCompleto(context),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// La señal de "todavía falta algo", en la esquina de la portada.
///
/// Chica y con un fondo oscuro detrás a propósito: va encima de una imagen que
/// ya se ve, así que tiene que leerse sobre cualquier portada sin taparla.
/// Antes, mientras cargaba, una rueda grande ocupaba la miniatura entera y no
/// se veía nada más.
class _RuedaChica extends StatelessWidget {
  const _RuedaChica();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: HomeTheme.accentPink,
        ),
      ),
    );
  }
}
