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
  });
  final ScrollController controller;
  final Widget child;
  final double fadeWidth;

  @override
  State<HorizontalScrollFade> createState() => _HorizontalScrollFadeState();
}

class _HorizontalScrollFadeState extends State<HorizontalScrollFade>
    with SingleTickerProviderStateMixin {
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);
  late final Animation<double> _bounceOffset =
      CurvedAnimation(parent: _bounce, curve: Curves.easeInOut);

  @override
  void initState() {
    super.initState();
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

  void _scrollBy(double delta) {
    final pos = widget.controller.position;
    final target = (widget.controller.offset + delta)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _edge({required bool right}) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final dir = right ? 1 : -1;
    return Positioned(
      right: right ? 0 : null,
      left: right ? null : 0,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _scrollBy(260.0 * dir),
        child: Container(
          width: widget.fadeWidth,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: right ? Alignment.centerRight : Alignment.centerLeft,
              end: right ? Alignment.centerLeft : Alignment.centerRight,
              colors: [bg.withValues(alpha: 0.85), bg.withValues(alpha: 0)],
            ),
          ),
          child: AnimatedBuilder(
            animation: _bounceOffset,
            builder: (context, child) => Transform.translate(
              offset: Offset(dir * 5 * _bounceOffset.value, 0),
              child: child,
            ),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                right ? Icons.chevron_right : Icons.chevron_left,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
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
