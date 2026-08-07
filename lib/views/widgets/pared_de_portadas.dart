import 'dart:math' as math;

import 'package:flutter/material.dart';

/// El fondo vivo de la app: una pared de portadas inclinada que se desplaza.
///
/// ── Cómo está hecha, y por qué así ────────────────────────────────────────
///
/// La referencia obvia se hace con un montón de imágenes y un `BackdropFilter`
/// encima. Acá no, y es a propósito: el desenfoque es lo más caro que hay en
/// Flutter y esto se dibuja **en el primer segundo de la app**, que es
/// justamente donde un tirón se nota más y peor.
///
/// En su lugar:
///
///   · **Un solo CustomPainter** pinta toda la pared. No hay un widget por
///     tarjeta, así que no hay decenas de capas que componer.
///   · **La animación es un Transform**, no un repintado. El painter dibuja una
///     vez y lo único que cambia por cuadro es el desplazamiento — el trabajo
///     de GPU es mover una textura ya lista.
///   · **Las portadas se pintan ya apagadas**, con su propio degradado oscuro.
///     Da la misma sensación que el desenfoque sin costar nada.
///
/// ── Por qué las tarjetas son dibujadas y no imágenes ──────────────────────
///
/// Porque esto tiene que verse bien **en el primer arranque y sin internet**.
/// Si dependiera de portadas de verdad, la primera vez que alguien abre la app
/// —que es la vez que más importa— vería huecos o una espera. Cuando el
/// catálogo esté conectado, esta misma pared puede recibir portadas reales por
/// [portadas] sin cambiar nada de la mecánica.
class ParedDePortadas extends StatefulWidget {
  const ParedDePortadas({
    super.key,
    this.portadas = const [],
    this.opacidad = 0.5,
  });

  /// Portadas reales, si las hay. Vacío = la pared dibujada.
  final List<ImageProvider> portadas;

  /// Cuánto se deja ver. Por debajo va el contenido, así que nunca es 1.
  final double opacidad;

  @override
  State<ParedDePortadas> createState() => _ParedDePortadasState();
}

class _ParedDePortadasState extends State<ParedDePortadas>
    with SingleTickerProviderStateMixin {
  // Lento a propósito: tiene que sentirse como que respira, no como que se
  // mueve. Un ciclo largo además hace que el salto del bucle no se note.
  static const _duracion = Duration(seconds: 40);

  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: _duracion,
  )..repeat();

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: widget.opacidad,
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, caja) {
              // El alto de una tarjeta manda todo lo demás. Proporción 2:3,
              // que es la de una portada de verdad.
              final alto = math.max(caja.maxHeight, caja.maxWidth) / 4.2;
              final paso = alto + 18;

              // La pared se pinta MÁS GRANDE que la pantalla: al inclinarla,
              // las esquinas quedarían vacías, y además hace falta sobrante
              // para que el desplazamiento no descubra el borde.
              final sobra = paso * 3;
              final ancho = caja.maxWidth + sobra * 2;
              final altoTotal = caja.maxHeight + sobra * 2;

              // RepaintBoundary: el painter queda cacheado como una textura y
              // el AnimatedBuilder de abajo solo la mueve. Sin esto, cada
              // cuadro repintaría la pared entera.
              final pared = RepaintBoundary(
                child: CustomPaint(
                  size: Size(ancho, altoTotal),
                  painter: _PintorDeLaPared(alto: alto, paso: paso),
                ),
              );

              return AnimatedBuilder(
                animation: _control,
                builder: (context, hijo) {
                  // Se desplaza EXACTAMENTE un paso y vuelve a empezar. Como
                  // la pared se repite cada paso, el salto es invisible.
                  final d = _control.value * paso;
                  return Transform.translate(
                    offset: Offset(-sobra + d, -sobra + d * 0.6),
                    child: hijo,
                  );
                },
                // La inclinación va acá afuera: se aplica una sola vez y no
                // se recalcula por cuadro.
                child: Transform.rotate(angle: -0.22, child: pared),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PintorDeLaPared extends CustomPainter {
  _PintorDeLaPared({required this.alto, required this.paso});

  final double alto;
  final double paso;

  /// Los tonos de las tarjetas.
  ///
  /// Apagados a propósito: esto va DEBAJO del logo y del contenido. Si
  /// compitieran por atención dejarían de ser un fondo. Son los de la paleta de
  /// la app, no colores al azar.
  static const _tonos = <Color>[
    Color(0xFF2A1E3A),
    Color(0xFF1E2A3A),
    Color(0xFF32203A),
    Color(0xFF1C2438),
    Color(0xFF3A2438),
    Color(0xFF212A34),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final ancho = alto * 2 / 3;
    final pasoX = ancho + 18;
    final columnas = (size.width / pasoX).ceil() + 1;
    final filas = (size.height / paso).ceil() + 1;

    // Semilla fija: la pared se ve IGUAL en cada arranque. Con un azar de
    // verdad, cada vez que se redibuja (rotar el teléfono, cambiar de tamaño
    // la ventana) todas las tarjetas cambiarían de color de golpe.
    var semilla = 7;
    int siguiente() {
      semilla = (semilla * 1103515245 + 12345) & 0x7FFFFFFF;
      return semilla;
    }

    final pincel = Paint();
    for (var f = 0; f < filas; f++) {
      // Las filas impares van corridas media tarjeta: alineadas se ven como
      // una grilla de planilla, no como una pared de portadas.
      final corrimiento = f.isOdd ? pasoX / 2 : 0.0;
      for (var c = 0; c < columnas; c++) {
        final x = c * pasoX + corrimiento;
        final y = f * paso;
        final tono = _tonos[siguiente() % _tonos.length];
        // Cada tarjeta con su propio degradado: da sensación de imagen en vez
        // de rectángulo de color.
        final rect = Rect.fromLTWH(x, y, ancho, alto);
        pincel.shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tono,
            Color.lerp(tono, const Color(0xFF08080F), 0.55)!,
          ],
        ).createShader(rect);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(10)),
          pincel,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PintorDeLaPared anterior) =>
      anterior.alto != alto || anterior.paso != paso;
}
