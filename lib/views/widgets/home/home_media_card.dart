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

    Widget cover;
    if (widget.hidden) {
      cover = Image.asset('assets/carddefaultoffline.png',
          fit: BoxFit.cover, cacheWidth: imgW);
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
      // Las portadas de red son de aspecto DESCONOCIDO: en "Continuar" suelen
      // ser 16:9, pero en Favoritos son pósters 2:3. Con BoxFit.cover un póster
      // en un marco 16:9 pierde cabeza y pies. Con contain sobre un fondo
      // borroso de la misma imagen, el 16:9 llena exacto (el fondo ni se ve) y
      // el póster se muestra entero — sirve para los dos sin saber el aspecto.
      final blurred = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: CacheNetWorkImagePic(widget.cover!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            headers: widget.headers,
            cacheWidth: (imgW / 4).ceil().clamp(1, 4096)),
      );
      cover = Stack(fit: StackFit.expand, children: [
        blurred,
        const ColoredBox(color: Color(0x66000000)),
        // El margen NO es decorativo: con contain a secas, un póster alto
        // ocupa EXACTAMENTE el alto del marco, así que queda pegado al borde
        // de arriba y al de abajo y se lee como si estuviera cortado (fue
        // justo el reclamo: "se come la imagen"). Con este respiro se ve que
        // la portada entra entera y termina donde tiene que terminar.
        Padding(
          padding: const EdgeInsets.all(_coverInset),
          child: CacheNetWorkImagePic(widget.cover!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              headers: widget.headers,
              cacheWidth: imgW),
        ),
      ]);
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
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
                        // El badge de tipo y el pill de extensión siguen siendo
                        // los MISMOS widgets que en la card vertical — el tag
                        // tiene que verse igual en las dos formas.
                        if (widget.type != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: ExtensionTypeBadge(type: widget.type!),
                          ),
                        if (widget.extensionName?.isNotEmpty == true)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: _extensionNamePill(),
                            ),
                          ),
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
                          if (widget.subtitle?.isNotEmpty == true)
                            Text(
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
                          const SizedBox(height: 3),
                          Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HomeTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
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
    final defaultCover = ColoredBox(
      color: const Color(0xFF15151C),
      child: Padding(
        padding: EdgeInsets.all(width * 0.18),
        child: Image.asset(
          'assets/carddefaultoffline.png',
          fit: BoxFit.contain,
          cacheWidth: cacheWidth,
        ),
      ),
    );
    // Tarjeta "oculta": mismo asset (carddefaultoffline.png) que el resto de
    // los placeholders default de la app, pero a pantalla completa (cover,
    // sin caja oscura ni padding) — el pedido fue sacar el recuadro, no la
    // imagen en sí.
    final hiddenCover = Image.asset(
      'assets/carddefaultoffline.png',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheWidth,
    );

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
                        // Mismo criterio que el frame de vídeo de arriba, y por
                        // el mismo motivo: la card es ~0.72:1 y un póster de
                        // lectura es 2:3 (0.667), así que con cover se le
                        // comían los bordes. Se muestra ENTERA sobre un fondo
                        // borroso de sí misma — llena la card igual, sin
                        // recortar nada. Sirve para cualquier aspecto: una
                        // portada que ya venga con la forma de la card llena
                        // exacto y el fondo ni se ve.
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: CacheNetWorkImagePic(
                                widget.cover!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                headers: widget.headers,
                                cacheWidth:
                                    (cacheWidth / 4).ceil().clamp(1, 4096),
                              ),
                            ),
                            const ColoredBox(color: Color(0x66000000)),
                            Padding(
                              padding: const EdgeInsets.all(_coverInset),
                              child: CacheNetWorkImagePic(
                                widget.cover!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                headers: widget.headers,
                                cacheWidth: cacheWidth,
                              ),
                            ),
                          ],
                        ),
                      // Badge de tipo + pill de extensión — comparten Row (o
                      // Column en cards angostas) para saber cuánto espacio
                      // le queda a cada uno en vez de superponerse sin
                      // avisar. En landscape Android (card de 112px) los dos
                      // lado a lado no entraban — el pill de extensión
                      // quedaba recortado a 2-3 letras ("JK...", ilegible).
                      // Apilados en columna, cada uno usa el ANCHO completo
                      // de la card en vez de competir por él.
                      if (widget.type != null || widget.extensionName != null)
                        Positioned(
                          top: 10,
                          left: 10,
                          // Deja libre la esquina superior derecha para el
                          // menú de tres puntos, que ahora está siempre.
                          right: hasMenu ? 40 : 10,
                          child: isAndroidLandscape
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.type != null)
                                      ExtensionTypeBadge(type: widget.type!),
                                    if (widget.type != null &&
                                        widget.extensionName != null)
                                      const SizedBox(height: 4),
                                    if (widget.extensionName != null)
                                      _extensionNamePill(),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.type != null)
                                      ExtensionTypeBadge(type: widget.type!),
                                    if (widget.type != null &&
                                        widget.extensionName != null)
                                      const SizedBox(width: 6),
                                    if (widget.extensionName != null)
                                      Flexible(child: _extensionNamePill()),
                                  ],
                                ),
                        ),
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
                if (widget.subtitle != null) ...[
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
