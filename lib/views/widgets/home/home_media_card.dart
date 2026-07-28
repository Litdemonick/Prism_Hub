import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/extension_type_badge.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Tarjeta de medio — calca el spec exacto del diseño (MediaCard.dc.html):
// 180x250, radio 14, degradado de fondo si no hay portada, badge arriba a
// la izquierda, barra de progreso abajo si corresponde, título+subtítulo
// debajo en una sola línea con ellipsis.
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
  static const double androidLandscapeWidth = 112;
  static const double androidLandscapeHeight = 155;

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
  // No se usa junto con onDelete (comparten la esquina superior derecha).
  final String? extensionName;
  final String? cover;
  // Portadas locales (capturas de video) en vez de una URL de red — usado
  // por Historial para los ítems de tipo video.
  final File? coverFile;
  final Map<String, String>? headers;
  // 0.0–1.0, null = sin barra de progreso.
  final double? progress;
  final VoidCallback? onTap;
  // Si se pasa, muestra un botón de borrar siempre visible arriba a la
  // derecha (usado por Historial/Favoritos) — sin esto no hay badge ahí.
  final VoidCallback? onDelete;
  // Para elegir el degradado por posición cuando no hay portada — si no se
  // pasa, se deriva del título (mismo criterio que ColorUtils.getColorByText).
  final int? gradientSeed;
  // Tapa la portada real con el arte genérico de PRISM_HUB (privacidad —
  // alguien mirando de reojo no ve de qué es). Si onToggleHide es null, no
  // se muestra el botón de ojo (la card no es "ocultable" en ese contexto).
  final bool hidden;
  final VoidCallback? onToggleHide;

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

  @override
  Widget build(BuildContext context) {
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
    final cacheHeight = (height * dpr).ceil().clamp(1, 4096).toInt();
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
      cacheHeight: cacheHeight,
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
                        // cover (no contain): estas son capturas del video
                        // (horizontales, ~16:9) mostradas en una card
                        // vertical (~0.72:1) — con contain quedaban
                        // chiquitas con barras negras arriba/abajo en vez de
                        // llenar la card como cualquier portada de red.
                        // cover recorta a los costados (se pierde parte del
                        // frame) pero se ve consistente con el resto.
                        ColoredBox(
                          color: Colors.black,
                          child: Image.file(
                            widget.coverFile!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            cacheWidth: cacheWidth,
                            cacheHeight: cacheHeight,
                            errorBuilder: (context, error, stackTrace) =>
                                defaultCover,
                          ),
                        )
                      else if (hasCover)
                        CacheNetWorkImagePic(
                          widget.cover!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          headers: widget.headers,
                          cacheWidth: cacheWidth,
                          cacheHeight: cacheHeight,
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
                          right: 10,
                          child: isAndroidLandscape
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.type != null)
                                      ExtensionTypeBadge(type: widget.type!),
                                    if (widget.type != null &&
                                        widget.onDelete == null &&
                                        widget.extensionName != null)
                                      const SizedBox(height: 4),
                                    if (widget.onDelete == null &&
                                        widget.extensionName != null)
                                      _extensionNamePill(),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.type != null)
                                      ExtensionTypeBadge(type: widget.type!),
                                    if (widget.type != null &&
                                        widget.onDelete == null &&
                                        widget.extensionName != null)
                                      const SizedBox(width: 6),
                                    if (widget.onDelete == null &&
                                        widget.extensionName != null)
                                      Flexible(child: _extensionNamePill()),
                                  ],
                                ),
                        ),
                      if (widget.onDelete != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: const Color(0x99202030),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onDelete,
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: HomeTheme.textPrimary,
                                  size: 16,
                                ),
                              ),
                            ),
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
                              child: Container(color: HomeTheme.accentPink),
                            ),
                          ),
                        ),
                      if (widget.onToggleHide != null)
                        Positioned(
                          bottom: widget.progress != null ? 12 : 8,
                          right: 8,
                          child: Material(
                            color: const Color(0x99202030),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onToggleHide,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  widget.hidden
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: HomeTheme.textPrimary,
                                  size: 16,
                                ),
                              ),
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
