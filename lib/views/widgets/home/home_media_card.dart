import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/extension_type_badge.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Tarjeta de medio — calca el spec exacto del diseño (MediaCard.dc.html):
// 180x250, radio 14, degradado de fondo si no hay portada, badge arriba a
// la izquierda, barra de progreso abajo si corresponde, título+subtítulo
// debajo en una sola línea con ellipsis.
// Margen entre la portada mostrada entera y el borde del marco. Ver el
// comentario donde se usa: sin él la imagen toca los bordes y parece cortada.
const double _coverInset = 8;

// Borde dibujado ENCIMA del contenido, como última capa del Stack. Puesto en
// la decoración del Container que recorta la portada, el propio recorte lo
// pisaba y en las esquinas redondeadas la línea desaparecía a trozos. Como
// capa de arriba queda entera y del color correcto.
Widget _bordeCard(Color accent, double radio) {
  return Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radio),
          // Color SÓLIDO, sin transparencia: a 0.7 el borde se mezclaba con
          // la portada de abajo, y contra una imagen clara o de colores
          // fuertes directamente desaparecía. Opaco se ve igual sobre
          // cualquier portada.
          border: Border.all(color: accent, width: 1.4),
        ),
      ),
    ),
  );
}

// Arte de respaldo (portada que no cargó, o card ocultada por el usuario)
// mostrado ENTERO pero sin caja oscura detrás: el fondo es la misma imagen
// ampliada y desenfocada, igual que se hace con las portadas. Con contain
// sobre un ColoredBox quedaba como un logo chico dentro de un recuadro, y con
// cover a pantalla completa se le cortaban las puntas —el logo no es
// rectangular—. Así llena la card y se ve completo.
Widget _arteRespaldo(int cacheWidth) {
  // La imagen sola, llenando la card entera. Sin ColoredBox detrás ni margen:
  // el pedido fue que ocupe toda la tarjeta, igual que una portada real.
  return Image.asset(
    'assets/carddefaultoffline.png',
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    cacheWidth: cacheWidth,
  );
}

class HomeMediaCard extends StatefulWidget {
  // Expuestas como static para que HomeSection sepa cuánto alto reservar
  // para la fila entera (portada + título/subtítulo debajo) sin duplicar
  // el número a mano en dos archivos distintos.
  static const double androidWidth = 150;
  static const double androidHeight = 208;
  static const double desktopWidth = 210;
  static const double desktopHeight = 292;
  // Android landscape: la tarjeta a tamaño "vertical" (208 de alto) no
  // entraba entera en el poco alto disponible (confirmado en vivo, sobre
  // todo en Historial) — más chica en horizontal, mismo aspecto ~0.72:1.
  // Variante HORIZONTAL (escritorio): 16:9, la misma forma que los frames de
  // vídeo, así la portada de "Continuar" ya no se recorta.
  static const double wideWidth = 316;
  // Las portadas de lectura (2:3) se muestran enteras, sin recortar, así que
  // lo que decide qué tan grandes se ven es el ALTO del marco. A 200 la card
  // quedaba demasiado grande —entraban pocas por fila y el bloque dominaba
  // la pantalla—, así que se baja a 186: el póster sigue en 124 de ancho
  // (bastante más que los 120 originales) y los frames de vídeo entran casi
  // exactos (1.70 contra 1.78 de 16:9), o sea sin recorte apreciable.
  static const double wideImageHeight = 186;
  // Imagen + separación + dos líneas de título + la línea del subtítulo.
  static const double wideTotalHeight = 248;

  // 112 quedaba MUY chico: en horizontal entraban ocho cards por fila y no se
  // leía ni el pill de la extensión. El apretón real venía del hero, que a
  // tamaño normal se comía toda la ventana en horizontal — ya se pone
  // compacto (ver HomeHeroBanner), así que acá sobra lugar para agrandarlas.
  // Se mantiene el mismo aspecto ~0.72:1 que las otras dos variantes.
  static const double androidLandscapeWidth = 132;
  static const double androidLandscapeHeight = 183;

  const HomeMediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.type,
    this.extensionName,
    this.cover,
    this.coverFile,
    this.headers,
    this.progress,
    this.onTap,
    this.onDelete,
    this.gradientSeed,
    this.hidden = false,
    this.onToggleHide,
    this.accent = HomeTheme.accentPink,
    this.horizontal = false,
  });

  final String title;
  final String? subtitle;
  // Chip de tipo (video/manga/novela) — colores fijos por tipo (mismo
  // criterio que ExtensionTypeBadge en el grid de extensiones), en vez del
  // chip plano gris de antes que no distinguía nada de un vistazo.
  final ExtensionType? type;
  // De qué extensión viene — mostrado como pill arriba a la derecha (el
  // badge de tipo, video/manga/novela, va arriba a la izquierda). Útil
  // sobre todo en tarjetas armadas cruzando varias extensiones (Recomendado,
  // Tendencias, Nuevos capítulos, Categorías) donde el origen no es obvio.
  final String? extensionName;
  final String? cover;
  // Portadas locales (capturas de video) en vez de una URL de red — usado
  // por Historial para los ítems de tipo video.
  final File? coverFile;
  final Map<String, String>? headers;
  // 0.0–1.0, null = sin barra de progreso.
  final double? progress;
  final VoidCallback? onTap;
  // Si se pasa, agrega "Eliminar" al menú de tres puntos (usado por
  // Historial/Favoritos y los dos Homes).
  final VoidCallback? onDelete;
  // Para elegir el degradado por posición cuando no hay portada — si no se
  // pasa, se deriva del título (mismo criterio que ColorUtils.getColorByText).
  final int? gradientSeed;
  // Tapa la portada real con el arte genérico de PRISM_HUB (privacidad —
  // alguien mirando de reojo no ve de qué es). Si onToggleHide es null, el
  // menú no ofrece ocultar (la card no es "ocultable" en ese contexto).
  final bool hidden;
  final VoidCallback? onToggleHide;
  // Zona +18: se pasa HomeTheme.accentRed para diferenciar la barra de
  // progreso en esa pantalla.
  final Color accent;
  // true = variante horizontal 16:9 (solo Home de escritorio). La vertical
  // sigue siendo el default en todos los demás lugares.
  final bool horizontal;

  @override
  State<HomeMediaCard> createState() => _HomeMediaCardState();
}

class _HomeMediaCardState extends State<HomeMediaCard> {
  bool _hover = false;

  Widget _extensionNamePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xA6202030),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        widget.extensionName!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: HomeTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ─── Variante horizontal (escritorio) ────────────────────────────────────
  //
  // Camino de render SEPARADO del vertical a propósito: comparte el mismo
  // widget (mismos datos, mismas acciones) pero no reutiliza una sola línea de
  // su layout. Así la card vertical —que usan Historial, Favoritos y todo el
  // móvil— queda intacta mientras esta se prueba, y volver atrás es cambiar el
  // flag en una línea.
  Widget _buildHorizontal(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final imgW = (HomeMediaCard.wideWidth * dpr).ceil().clamp(1, 4096);
    final hasCover = !widget.hidden &&
        (widget.cover?.isNotEmpty == true || widget.coverFile != null);

    // Arte de respaldo cuando la portada no carga. Va con contain y margen:
    // el respaldo interno de CacheNetWorkImagePic lo pinta a pantalla completa
    // con cover, y este logo NO es rectangular, así que le cortaba las puntas
    // (se veía la estrella partida arriba y abajo en las cards del Home).
    final arteDefault = _arteRespaldo(imgW);

    Widget cover;
    if (widget.hidden) {
      cover = arteDefault;
    } else if (widget.coverFile != null) {
      // Los frames ya son 16:9, o sea la MISMA forma que la card: acá cover no
      // recorta casi nada y no hace falta el fondo borroso de la variante
      // vertical. Esa es justamente la ventaja de este diseño para "Continuar".
      cover = Image.file(widget.coverFile!,
          fit: BoxFit.cover,
          cacheWidth: imgW,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF15151C)));
    } else if (hasCover) {
      // cover y NO contain: una portada de lectura es ~2:3 y la card ~0.72:1,
      // formas casi iguales, así que llena el marco entero recortando apenas
      // un 7% a los costados —imperceptible— en vez de dejar franjas del
      // fondo arriba y abajo. Ahora que "Continuar" está partido en dos, cada
      // tipo va en la card con su forma, así que esto ya no perjudica al
      // vídeo. El arte de respaldo sigue con contain (ver arteDefault): ese
      // logo NO es rectangular y con cover se le cortan las puntas.
      cover = CacheNetWorkImagePic(widget.cover!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          headers: widget.headers,
          fallback: arteDefault,
          cacheWidth: imgW);
    } else {
      cover = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: HomeTheme.gradientFor(
                widget.gradientSeed ?? widget.title.hashCode),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: RepaintBoundary(
          child: SizedBox(
            width: HomeMediaCard.wideWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Borde con el acento de la zona (morado en el Home normal,
                // rojo en la Zona +18): sobre el panel de la sección, que es
                // de un tono muy parecido al de la card, no se veía dónde
                // terminaba cada tarjeta.
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SizedBox(
                    width: HomeMediaCard.wideWidth,
                    height: HomeMediaCard.wideImageHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        cover,
                        // Velo que se aclara con el hover — da la sensación de
                        // "se puede tocar" sin mover la card de lugar.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          color: Colors.black
                              .withValues(alpha: _hover ? 0.28 : 0.10),
                        ),
                        // El play ya no está siempre: tapaba el centro de la
                        // portada (justo donde suele estar lo que se quiere
                        // ver). Aparece solo cuando el mouse está encima, que
                        // es cuando de verdad indica "esto se puede abrir".
                        Center(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: _hover ? 1 : 0,
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 150),
                              scale: _hover ? 1.08 : 0.9,
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.45),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      width: 2),
                                ),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        ),
                        // Los distintivos ya no van ENCIMA de la portada: el
                        // de tipo lo dice el título de la sección, y el de la
                        // extensión pasó abajo, junto al título. Sobre la
                        // imagen tapaban justo las esquinas del contenido.
                        if (widget.progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: widget.progress!.clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                              valueColor: AlwaysStoppedAnimation(widget.accent),
                            ),
                          ),
                        _bordeCard(widget.accent, 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Subtítulo y pill en la MISMA línea: puestos uno
                          // debajo del otro la card crecía, y el alto de la
                          // fila tiene que quedar igual que antes.
                          Row(
                            children: [
                              if (widget.subtitle?.isNotEmpty == true)
                                Flexible(
                                  child: Text(
                                    widget.subtitle!.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: HomeTheme.textMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.title,
                            // Una línea y no dos: el pill de la extensión pasa
                            // a ir DEBAJO del título, y con el título en dos
                            // líneas el bloque no entraba en el alto de la
                            // fila y el pill quedaba cortado por el borde del
                            // panel.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HomeTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          if (widget.extensionName?.isNotEmpty == true) ...[
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _extensionNamePill(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Ocultar y eliminar viven los DOS en el menú de tres
                    // puntos: en la card horizontal el ojo suelto sobre la
                    // imagen tapaba parte del frame, que es justo lo que este
                    // diseño busca mostrar entero.
                    if (widget.onDelete != null || widget.onToggleHide != null)
                      _WideMenuButton(
                        hidden: widget.hidden,
                        onDelete: widget.onDelete,
                        onToggleHide: widget.onToggleHide,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.horizontal) return _buildHorizontal(context);
    final hasCover = !widget.hidden &&
        (widget.cover?.isNotEmpty == true || widget.coverFile != null);
    final gradient = HomeTheme.gradientFor(
      widget.gradientSeed ?? widget.title.hashCode,
    );
    // Desktop más grande (más espacio en pantalla, y deja lugar real para
    // que el tag/badge de tipo+extensión no quede apretado); Android un
    // poco más chico para que entren más columnas, mismo aspecto ~0.72:1.
    // En horizontal (Android), el tamaño "vertical" no entraba entero en
    // el poco alto disponible — se usa la variante landscape, más chica.
    final hasMenu = widget.onDelete != null || widget.onToggleHide != null;
    final isAndroidLandscape = Platform.isAndroid &&
        MediaQuery.of(context).orientation == Orientation.landscape;
    final width = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeWidth
        : Platform.isAndroid
            ? HomeMediaCard.androidWidth
            : HomeMediaCard.desktopWidth;
    final height = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeHeight
        : Platform.isAndroid
            ? HomeMediaCard.androidHeight
            : HomeMediaCard.desktopHeight;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * dpr).ceil().clamp(1, 4096).toInt();
    final defaultCover = _arteRespaldo(cacheWidth);
    // Tarjeta "oculta": mismo asset (carddefaultoffline.png) que el resto de
    // los placeholders default de la app, pero a pantalla completa (cover,
    // sin caja oscura ni padding) — el pedido fue sacar el recuadro, no la
    // imagen en sí.
    // Tarjeta oculta: el MISMO arte que el resto de los respaldos, con
    // contain y margen. Antes iba con cover a pantalla completa —"sacar el
    // recuadro"— pero el logo no es rectangular, así que al ocultar una card
    // se le cortaban las puntas y quedaba partido arriba y abajo.
    final hiddenCover = defaultCover;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: width,
                  height: height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: hasCover
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradient,
                          ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.hidden)
                        hiddenCover
                      else if (widget.coverFile != null)
                        // Capturas del vídeo: son horizontales (~16:9) dentro de
                        // una card vertical (~0.72:1). Ni cover ni contain solos
                        // funcionan — cover recortaba tanto a los costados que
                        // del cuadro quedaba una franja irreconocible, y contain
                        // deja dos barras negras enormes.
                        //
                        // Se muestra el frame ENTERO (contain) sobre un fondo
                        // borroso de la MISMA imagen estirada a cubrir. Llena la
                        // card, no recorta nada y no se ve estirado.
                        //
                        // El fondo se decodifica a un cuarto del tamaño: va
                        // desenfocado, así que más resolución no se notaría y sí
                        // costaría memoria en una lista con muchas cards.
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Image.file(
                                widget.coverFile!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                cacheWidth:
                                    (cacheWidth / 4).ceil().clamp(1, 4096),
                                // Sin errorBuilder acá: si la imagen falla, el
                                // de la capa de arriba ya muestra el default.
                                errorBuilder: (_, __, ___) =>
                                    const ColoredBox(color: Color(0xFF15151C)),
                              ),
                            ),
                            // Oscurece un poco el fondo para que el frame de
                            // adelante resalte y el texto de abajo siga legible.
                            const ColoredBox(color: Color(0x66000000)),
                            Padding(
                              padding: const EdgeInsets.all(_coverInset),
                              child: Image.file(
                                widget.coverFile!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                cacheWidth: cacheWidth,
                                errorBuilder: (context, error, stackTrace) =>
                                    defaultCover,
                              ),
                            ),
                          ],
                        )
                      else if (hasCover)
                        // El fondo borroso se puso cuando la imagen llegaba
                        // DEFORMADA (cacheWidth+cacheHeight juntos hacían que
                        // el decoder ignorara el aspecto original). Arreglado
                        // eso, un póster de lectura (2:3) contra una card de
                        // ~0.72:1 llena casi exacto con cover: se recorta un
                        // 7% a los costados, imperceptible, y se ve como una
                        // portada de verdad en vez de una imagen chica dentro
                        // de un marco. El fondo borroso queda SOLO para el
                        // caso donde de verdad hace falta: un frame de vídeo
                        // (16:9) metido en una card alta, donde cover dejaría
                        // una franja irreconocible.
                        // Ver el mismo caso en la card ancha: cover para
                        // que la portada llene la tarjeta, y el respaldo con
                        // contain para que el logo no se corte.
                        CacheNetWorkImagePic(
                          widget.cover!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          headers: widget.headers,
                          fallback: defaultCover,
                          cacheWidth: cacheWidth,
                        ),
                      // Ver la card ancha: los distintivos salieron de
                      // encima de la portada. Acá tapaban una esquina de cada
                      // lado, que en una card chica es bastante.
                      if (hasMenu)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _CardOverlayMenu(
                            hidden: widget.hidden,
                            onDelete: widget.onDelete,
                            onToggleHide: widget.onToggleHide,
                          ),
                        ),
                      if (widget.progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 4,
                            color: const Color(0x80000000),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: widget.progress!.clamp(0, 1),
                              child: Container(color: widget.accent),
                            ),
                          ),
                        ),
                      _bordeCard(widget.accent, 14),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomeTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.extensionName?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _extensionNamePill(),
                  ),
                ] else if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HomeTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Menú de tres puntos de la card horizontal. Agrupa ocultar y eliminar en vez
// de dejar botones sueltos sobre la portada, que en 16:9 tapaban parte del
// frame. Colores propios (HomeTheme) y no los del tema Material por defecto,
// para que no desentone con el resto del Home.
class _WideMenuButton extends StatelessWidget {
  const _WideMenuButton({
    required this.hidden,
    this.onDelete,
    this.onToggleHide,
    this.iconColor = HomeTheme.textMuted,
    this.size = 28,
  });

  final bool hidden;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleHide;
  final Color iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    // En escritorio la raíz es FluentApp, que NO pone un Material en el árbol
    // (por eso el resto de los botones de la card se envuelven a mano). Sin
    // esto, PopupMenuButton revienta con "No Material widget found" en
    // Windows/Linux mientras en Android anda, porque ahí la raíz es
    // GetMaterialApp. MaterialLocalizations sí las da FluentApp.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: size,
        height: size,
        child: PopupMenuButton<int>(
          tooltip: '',
          padding: EdgeInsets.zero,
          splashRadius: 18,
          iconSize: 18,
          color: HomeTheme.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: HomeTheme.border),
          ),
          // OJO: `constraints` acá es el tamaño del MENÚ desplegado, no el del
          // botón. Ponerle el tamaño del botón (30x30) abría un menú de 30px,
          // que se ve como "no abre nada". El tamaño del botón se controla con
          // el SizedBox de abajo.
          constraints: const BoxConstraints(minWidth: 170),
          icon: Icon(Icons.more_vert, color: iconColor, size: 18),
          onSelected: (v) {
            if (v == 0) onToggleHide?.call();
            if (v == 1) onDelete?.call();
          },
          itemBuilder: (context) => [
            if (onToggleHide != null)
              PopupMenuItem<int>(
                value: 0,
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      hidden
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 17,
                      color: HomeTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      hidden ? 'home.show-card'.i18n : 'home.hide-card'.i18n,
                      style: const TextStyle(
                          color: HomeTheme.textPrimary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            if (onDelete != null)
              PopupMenuItem<int>(
                value: 1,
                height: 40,
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline,
                        size: 17, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Text(
                      'common.delete'.i18n,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Igual que _WideMenuButton pero para la card vertical: acá el menú va ENCIMA
// de la portada, así que necesita su propia chapa oscura para leerse sobre
// cualquier imagen (el de la card ancha vive sobre el fondo de la página).
class _CardOverlayMenu extends StatelessWidget {
  const _CardOverlayMenu({
    required this.hidden,
    this.onDelete,
    this.onToggleHide,
  });

  final bool hidden;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleHide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99202030),
      shape: const CircleBorder(),
      child: _WideMenuButton(
        hidden: hidden,
        onDelete: onDelete,
        onToggleHide: onToggleHide,
        iconColor: HomeTheme.textPrimary,
        // Área táctil cómoda en celular sin agrandar el círculo.
        size: 30,
      ),
    );
  }
}
