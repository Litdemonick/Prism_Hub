import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

/// Wraps a horizontally-scrolling [child] with a visible "there's more"
/// indicator — a soft edge fade plus a chevron that bounces gently toward
/// the hidden content — on whichever side still has more to reveal. On
/// touch devices there's no visible scrollbar, so a fully-cropped last card
/// alone gives no hint that swiping reveals more; the animation makes it
/// unmistakable without needing to read anything.
class HorizontalScrollFade extends StatefulWidget {
  const HorizontalScrollFade({
    super.key,
    required this.controller,
    required this.child,
    this.fadeWidth = 40,
    this.arrowCenterFromTop,
    this.pageScroll = false,
    this.showFade = true,
    this.arrowColor,
  });
  final ScrollController controller;
  final Widget child;
  final double fadeWidth;
  // Dónde centrar verticalmente la flecha, medido desde arriba. Sin esto se
  // centra en TODO el alto de la fila — que en el Home incluye el título y
  // el subtítulo de debajo de la portada, así que la flecha quedaba más
  // abajo que las imágenes con las que se supone que está alineada.
  final double? arrowCenterFromTop;
  // true = cada toque avanza una pantalla entera en vez de 260px. Es la
  // división pedida: estas flechas de los costados pasan RÁPIDO, mientras
  // los botones ‹ › del encabezado del Home siguen avanzando de a poco.
  final bool pageScroll;
  // false = solo la flecha, sin el degradado de fondo. En las filas del Home
  // ese velo tapaba el borde de la portada sin aportar nada: las flechas ya
  // se ven solas sobre la imagen gracias a su propio círculo oscuro.
  final bool showFade;
  // Color del círculo de la flecha. Sin esto queda negro semitransparente,
  // que sobre una portada oscura casi no se distingue. El Home le pasa su
  // acento (morado en el normal, rojo en la Zona +18).
  final Color? arrowColor;

  @override
  State<HorizontalScrollFade> createState() => _HorizontalScrollFadeState();
}

class _HorizontalScrollFadeState extends State<HorizontalScrollFade>
    with SingleTickerProviderStateMixin {
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  late final AnimationController _bounce;
  late final Animation<double> _bounceOffset;

  @override
  void initState() {
    super.initState();
    // Antes solo corría en touch (Platform.isAndroid etc, "!_isDesktop") —
    // en desktop las flechas quedaban quietas, sin ningún indicio animado de
    // que hay más contenido para el costado. El mismo rebote sutil funciona
    // igual de bien con mouse que con dedo, así que ya no hay razón para
    // cortarlo por plataforma.
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _bounceOffset = CurvedAnimation(parent: _bounce, curve: Curves.easeInOut);
    _bounce.repeat(reverse: true);
    widget.controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(covariant HorizontalScrollFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El listener del ScrollController solo dispara con eventos de scroll,
    // no cuando cambia la CANTIDAD de contenido (ej: la lista pasa de vacía
    // a poblada tras cargar datos async) — sin esto, _canScrollRight se
    // quedaba pegado con el valor calculado en el primer frame (a veces
    // antes de que el contenido real existiera), mostrando la flecha
    // flotando aunque ya no hubiera nada para desplazar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    _bounce.dispose();
    super.dispose();
  }

  void _update() {
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    final canLeft = pos.pixels > pos.minScrollExtent + 1;
    final canRight = pos.pixels < pos.maxScrollExtent - 1;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scrollBy(double dir) {
    final pos = widget.controller.position;
    // Menos 80px para que quede una card de referencia a la vista y no se
    // pierda el hilo de dónde estabas.
    final step = widget.pageScroll
        ? (pos.viewportDimension - 80).clamp(200.0, 2000.0)
        : 260.0;
    final delta = step * dir;
    final target = (widget.controller.offset + delta)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _edge({required bool right}) {
    // OJO: Theme.of() a secas daba BLANCO en escritorio. Ahí la raíz es
    // FluentApp, que no pone un Theme de Material en el árbol, así que
    // Theme.of cae al tema CLARO por defecto — y el degradado, que debía
    // fundirse con el fondo, aparecía como un resplandor blanco sobre una
    // interfaz oscura. En escritorio hay que preguntarle a FluentTheme.
    final bg = Platform.isAndroid
        ? Theme.of(context).scaffoldBackgroundColor
        : fluent.FluentTheme.of(context).scaffoldBackgroundColor;
    final dir = right ? 1 : -1;
    return Positioned(
      right: right ? 0 : null,
      left: right ? null : 0,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _scrollBy(dir.toDouble()),
        child: Container(
          width: widget.fadeWidth,
          alignment: widget.arrowCenterFromTop == null
              ? Alignment.center
              : Alignment.topCenter,
          padding: widget.arrowCenterFromTop == null
              ? null
              : EdgeInsets.only(
                  // 13 = medio alto del círculo de la flecha (26).
                  top: (widget.arrowCenterFromTop! - 13).clamp(0.0, 4096.0),
                ),
          decoration: widget.showFade
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: right ? Alignment.centerRight : Alignment.centerLeft,
                    end: right ? Alignment.centerLeft : Alignment.centerRight,
                    colors: [
                      bg.withValues(alpha: 0.85),
                      bg.withValues(alpha: 0),
                    ],
                  ),
                )
              : null,
          child: AnimatedBuilder(
            animation: _bounceOffset,
            builder: (context, child) => Transform.translate(
              offset: Offset(dir * 5 * _bounceOffset.value, 0),
              child: child,
            ),
            child: _edgeIcon(right),
          ),
        ),
      ),
    );
  }

  Widget _edgeIcon(bool right) {
    final color = widget.arrowColor;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? Colors.black.withValues(alpha: 0.55),
        boxShadow: [
          BoxShadow(
            color: (color ?? Colors.black).withValues(alpha: 0.45),
            blurRadius: 8,
          ),
        ],
      ),
      child: Icon(
        right ? Icons.chevron_right : Icons.chevron_left,
        color: HomeTheme.contraste,
        size: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_canScrollLeft) _edge(right: false),
        if (_canScrollRight) _edge(right: true),
      ],
    );
  }
}
