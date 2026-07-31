import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Fondo ambiental animado. Usa gradientes radiales en vez de blur gaussiano:
// el look sigue siendo suave, pero evita un ImageFilter.blur por frame.
class AnimatedBackgroundGlow extends StatefulWidget {
  const AnimatedBackgroundGlow({super.key, this.accent = HomeTheme.accentPink});

  // Zona +18: se pasa HomeTheme.accentRed para diferenciarla visualmente del
  // Home normal, reusando este mismo widget en vez de duplicarlo.
  final Color accent;

  @override
  State<AnimatedBackgroundGlow> createState() => _AnimatedBackgroundGlowState();
}

class _AnimatedBackgroundGlowState extends State<AnimatedBackgroundGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _blob({
    required Color color,
    required Alignment alignment,
    required double size,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value * 2 * math.pi;
              final blobSize =
                  Platform.isAndroid || Platform.isIOS ? 220.0 : 380.0;
              if (_isDesktop) {
                return Stack(
                  children: [
                    _blob(
                      color: widget.accent.withValues(alpha: 0.12),
                      alignment: const Alignment(0.72, 0.42),
                      size: blobSize,
                    ),
                    _blob(
                      color: const Color(0xFF3D5AFE).withValues(alpha: 0.1),
                      alignment: const Alignment(-0.68, -0.42),
                      size: blobSize * 0.94,
                    ),
                  ],
                );
              }
              return Stack(
                children: [
                  _blob(
                    color: widget.accent.withValues(alpha: 0.16),
                    alignment: Alignment(0.7 * math.cos(t), 0.6 * math.sin(t)),
                    size: blobSize,
                  ),
                  _blob(
                    color: const Color(0xFF3D5AFE).withValues(alpha: 0.14),
                    alignment: Alignment(
                      -0.75 * math.cos(t * 0.7 + 2),
                      -0.6 * math.sin(t * 0.8 + 1),
                    ),
                    size: blobSize * 0.94,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
