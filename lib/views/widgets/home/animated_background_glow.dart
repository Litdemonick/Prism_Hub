import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Fondo ambiental animado — un par de manchas de luz difuminadas que se
// mueven despacio en bucle, detrás del contenido. Mismo efecto en Home,
// Historial y Buscar para que el fondo negro plano se sienta "vivo" en vez
// de estático, consistente en toda la app.
class AnimatedBackgroundGlow extends StatefulWidget {
  const AnimatedBackgroundGlow({super.key});

  @override
  State<AnimatedBackgroundGlow> createState() => _AnimatedBackgroundGlowState();
}

class _AnimatedBackgroundGlowState extends State<AnimatedBackgroundGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Sigma bajado de 90 a 40 — un blur gaussiano de sigma 90 sobre un círculo
  // de ~300px es una operación de GPU pesada, y al estar dentro de
  // AnimatedBuilder se recalcula en CADA frame (60 veces por segundo) todo
  // el tiempo que la página quede montada. Con 2 blobs por instancia y esta
  // misma animación repetida en Home/Buscar/Extensiones/Ajustes/Historial/
  // lector de manga, era un costo de GPU continuo enorme — se sentía como
  // tirones en CUALQUIER botón/scroll/animación de la app, no solo en el
  // fondo, porque competía por el mismo frame budget todo el tiempo. 40
  // sigue viéndose como un resplandor suave, a una fracción del costo.
  Widget _blob({required Color color, required Alignment alignment, required double size}) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: aísla el layer de este fondo (que se repinta todo el
    // tiempo por la animación) del resto del contenido de la página — sin
    // esto, el compositor podía terminar re-pintando el Stack entero
    // (contenido real incluido) en cada tick solo porque este fondo cambió.
    return RepaintBoundary(
      child: IgnorePointer(
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value * 2 * math.pi;
              return Stack(
                children: [
                  _blob(
                    color: HomeTheme.accentPink.withValues(alpha: 0.16),
                    alignment: Alignment(0.7 * math.cos(t), 0.6 * math.sin(t)),
                    size: 320,
                  ),
                  _blob(
                    color: const Color(0xFF3D5AFE).withValues(alpha: 0.14),
                    alignment: Alignment(
                      -0.75 * math.cos(t * 0.7 + 2),
                      -0.6 * math.sin(t * 0.8 + 1),
                    ),
                    size: 300,
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
