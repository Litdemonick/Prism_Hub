import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Bloques grises que brillan mientras se espera contenido.
///
/// ── Por qué esto y no una rueda girando ───────────────────────────────────
///
/// Porque una rueda solo dice «esperá». Estos bloques dicen **qué va a
/// aparecer y dónde**: tienen la forma y el lugar exactos de las tarjetas que
/// los van a reemplazar, así que cuando llega el contenido nada se mueve. Con
/// la rueda, en cambio, la pantalla salta entera en el momento en que carga.
///
/// Y se siente más rápido aunque tarde lo mismo, que es la mitad del asunto.
///
/// ── Cuándo NO usarlos ─────────────────────────────────────────────────────
///
/// Cuando ya se sabe que no va a llegar nada. Un esqueleto brillando para
/// siempre es peor que un mensaje de error: el usuario se queda esperando algo
/// que nunca va a venir. Para eso está la línea con el botón de reintentar.
class Esqueleto extends StatefulWidget {
  const Esqueleto({
    super.key,
    this.width,
    this.height,
    this.radio = 8,
    this.child,
  });

  final double? width;
  final double? height;
  final double radio;

  /// Para armar formas compuestas: el hijo se dibuja con el mismo brillo.
  final Widget? child;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final forma = widget.child ??
        DecoratedBox(
          decoration: BoxDecoration(
            color: HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(widget.radio),
          ),
          child: SizedBox(width: widget.width, height: widget.height),
        );

    // RepaintBoundary: el brillo corre en bucle, y sin la capa propia arrastra
    // a repintar todo lo que tenga alrededor sesenta veces por segundo.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        // La forma se pasa aparte para que no se reconstruya en cada cuadro:
        // lo único que cambia es por dónde va el reflejo.
        child: forma,
        builder: (context, hijo) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            // Un reflejo claro que cruza de izquierda a derecha. Va de -1 a 2
            // para que entre y salga del todo en vez de aparecer y
            // desaparecer en los bordes.
            final x = -1 + 3 * _c.value;
            return LinearGradient(
              begin: Alignment(x - 1, -0.3),
              end: Alignment(x + 1, 0.3),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.07),
                Colors.transparent,
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          child: hijo,
        ),
      ),
    );
  }
}

/// El esqueleto con forma de tarjeta de catálogo: póster y dos líneas.
///
/// Mide exactamente lo mismo que [TarjetaDeCatalogo] con el mismo ancho, así
/// que al llegar el contenido la grilla no se mueve ni un píxel.
class EsqueletoTarjeta extends StatelessWidget {
  const EsqueletoTarjeta({super.key, required this.ancho});

  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Esqueleto(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bloque(ancho, ancho * 3 / 2, 8),
          const SizedBox(height: 8),
          _bloque(ancho * 0.9, 12, 4),
          const SizedBox(height: 6),
          _bloque(ancho * 0.6, 12, 4),
        ],
      ),
    );
  }

  static Widget _bloque(double w, double h, double r) => DecoratedBox(
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(r),
        ),
        child: SizedBox(width: w, height: h),
      );
}
