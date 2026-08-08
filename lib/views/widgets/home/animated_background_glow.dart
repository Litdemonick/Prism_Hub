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

  /// ── El fondo ya NO se mueve ─────────────────────────────────────────────
  ///
  /// El reloj se queda en cero y nadie lo arranca: el degradado se dibuja una
  /// vez, en su posición de siempre, y ahí se queda. Se conserva el degradado
  /// —es lo que hace que el fondo no sea un negro plano— y se va únicamente el
  /// movimiento.
  ///
  /// El motivo es el costo. Esto latía a sesenta cuadros por segundo en TODAS
  /// las zonas a la vez, y en cada uno de esos cuadros se vuelve a pintar lo
  /// que haya encima que no tenga capa propia. Era el fondo de la app entera
  /// gastando batería para un movimiento que casi no se nota, y ya había
  /// obligado a escribir un vigilante del ciclo de vida solo para que no
  /// siguiera latiendo en segundo plano.
  ///
  /// El controlador se queda declarado a propósito, sin arrancar: el
  /// AnimatedBuilder de más abajo lo lee, y sacarlo entero obligaba a rehacer
  /// el dibujado por un cambio que es de una línea. Sin `repeat()` no pide un
  /// solo cuadro.
  @override
  void initState() {
    super.initState();
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

  /// Un manchón que se corre, con su degradado ya rasterizado.
  ///
  /// El `Align` sigue posicionando, pero el hijo es siempre EL MISMO widget
  /// —mismo color, mismo tamaño— así que Flutter puede reusar su capa en vez
  /// de volver a pintar el degradado.
  Widget _blobMovil({
    required Color color,
    required double size,
    required Alignment hacia,
  }) {
    return Align(
      alignment: hacia,
      child: RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, color.withValues(alpha: 0)],
                stops: const [0, 1],
              ),
            ),
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
              // Los dos manchones se MUEVEN, no se vuelven a dibujar.
              //
              // Antes cada cuadro rearmaba el `Alignment` de cada uno, y eso
              // obliga a repintar el degradado radial entero sesenta veces por
              // segundo, a pantalla completa. Ahora el degradado se rasteriza
              // una vez —de eso se encarga el RepaintBoundary de cada
              // manchón— y lo único que cambia por cuadro es un corrimiento,
              // que la GPU resuelve sin volver a calcular nada.
              return Stack(
                children: [
                  _blobMovil(
                    color: widget.accent.withValues(alpha: 0.16),
                    size: blobSize,
                    hacia: Alignment(0.7 * math.cos(t), 0.6 * math.sin(t)),
                  ),
                  _blobMovil(
                    color: const Color(0xFF3D5AFE).withValues(alpha: 0.14),
                    size: blobSize * 0.94,
                    hacia: Alignment(
                      -0.75 * math.cos(t * 0.7 + 2),
                      -0.6 * math.sin(t * 0.8 + 1),
                    ),
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
