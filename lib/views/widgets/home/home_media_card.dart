import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Tarjeta de medio — calca el spec exacto del diseño (MediaCard.dc.html):
// 180x250, radio 14, degradado de fondo si no hay portada, badge arriba a
// la izquierda, barra de progreso abajo si corresponde, título+subtítulo
// debajo en una sola línea con ellipsis.
class HomeMediaCard extends StatefulWidget {
  const HomeMediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.cover,
    this.headers,
    this.progress,
    this.onTap,
    this.gradientSeed,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final String? cover;
  final Map<String, String>? headers;
  // 0.0–1.0, null = sin barra de progreso.
  final double? progress;
  final VoidCallback? onTap;
  // Para elegir el degradado por posición cuando no hay portada — si no se
  // pasa, se deriva del título (mismo criterio que ColorUtils.getColorByText).
  final int? gradientSeed;

  @override
  State<HomeMediaCard> createState() => _HomeMediaCardState();
}

class _HomeMediaCardState extends State<HomeMediaCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hasCover = widget.cover?.isNotEmpty == true;
    final gradient = HomeTheme.gradientFor(
      widget.gradientSeed ?? widget.title.hashCode,
    );
    // 180x250 es el tamaño del diseño (desktop, más espacio); en Android se
    // achica un poco para que entren más columnas, mismo aspecto 0.72:1.
    final width = Platform.isAndroid ? 128.0 : 180.0;
    final height = Platform.isAndroid ? 178.0 : 250.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
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
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      CacheNetWorkImagePic(
                        widget.cover!,
                        fit: BoxFit.cover,
                        headers: widget.headers,
                      ),
                    if (widget.badge != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xA6202030),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.badge!,
                            style: const TextStyle(
                              color: HomeTheme.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
    );
  }
}
