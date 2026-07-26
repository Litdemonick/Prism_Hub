import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/horizontal_scroll_fade.dart';

// Envoltorio de sección — calca el header del diseño (título + ›, botones
// prev/next redondeados) sin tocar HorizontalList, que es compartido con
// Búsqueda/otras páginas y no debía cambiar.
class HomeSection extends StatefulWidget {
  const HomeSection({
    super.key,
    required this.title,
    required this.onClickMore,
    required this.itemCount,
    required this.itemBuilder,
    this.showNavButtons = true,
  });

  final String title;
  final VoidCallback onClickMore;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final bool showNavButtons;

  @override
  State<HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends State<HomeSection> {
  final ScrollController _controller = ScrollController();
  bool _headerHover = false;

  void _move(bool left) {
    _controller.animateTo(
      (_controller.offset + (left ? -400 : 400))
          .clamp(0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.ease,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      scrollDirection: Axis.horizontal,
      controller: _controller,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: widget.itemBuilder(context, index),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: widget.onClickMore,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _headerHover = true),
                onExit: (_) => setState(() => _headerHover = false),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 150),
                      style: TextStyle(
                        color: _headerHover ? HomeTheme.accentPink : HomeTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      child: Text(widget.title),
                    ),
                    const SizedBox(width: 6),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 150),
                      style: TextStyle(
                        color: _headerHover ? HomeTheme.accentPink : HomeTheme.textMuted,
                        fontSize: 15,
                      ),
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 150),
                        offset: _headerHover ? const Offset(0.25, 0) : Offset.zero,
                        child: const Text('›'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (widget.showNavButtons) ...[
              _NavButton(icon: Icons.chevron_left, onTap: () => _move(true)),
              const SizedBox(width: 6),
              _NavButton(icon: Icons.chevron_right, onTap: () => _move(false)),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          // Alto de la portada (HomeMediaCard) + margen para el título y
          // subtítulo que van DEBAJO de eso — sin el margen, la fila
          // desborda (visto en vivo: "overflowed by 44/26 pixels"). En
          // Android horizontal, HomeMediaCard usa su variante más chica
          // (ver androidLandscapeHeight) — hay que matchear acá también.
          height: (Platform.isAndroid &&
                      MediaQuery.of(context).orientation ==
                          Orientation.landscape
                  ? HomeMediaCard.androidLandscapeHeight
                  : Platform.isAndroid
                      ? HomeMediaCard.androidHeight
                      : HomeMediaCard.desktopHeight) +
              50,
          child: HorizontalScrollFade(controller: _controller, child: list),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: HomeTheme.border),
          ),
          child: Icon(icon, size: 15, color: HomeTheme.textMuted),
        ),
      ),
    );
  }
}

// Estado vacío / ghost card — el diseño usa una tarjeta punteada con "+" y
// un texto de ayuda en vez de simplemente no mostrar nada.
class HomeGhostCard extends StatelessWidget {
  const HomeGhostCard({super.key, required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 140,
          height: 250,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: HomeTheme.textMuted.withValues(alpha: 0.35),
              width: 1.5,
              style: BorderStyle.solid,
            ),
            color: HomeTheme.cardSurface.withValues(alpha: 0.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HomeTheme.textMuted.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.add, color: HomeTheme.textMuted, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: HomeTheme.textMuted, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

