import 'package:flutter/material.dart';

/// El fondo de PrismHub en Android TV.
///
/// ── Por qué es plano y no el resplandor de siempre ──────────────────────
///
/// En teléfono y en PC el fondo son dos manchones de color difuminados
/// (`AnimatedBackgroundGlow`). En un televisor eso no funcionó: visto de
/// lejos, esas dos manchas violeta quedan estáticas en el mismo sitio toda
/// la sesión y se leen como suciedad de la pantalla, no como diseño. Pedido
/// textual: «no me gusta ese morado con luces así, estáticas».
///
/// Después de mirar catorce alternativas en el boceto, la elegida fue
/// «Carbón»: un gris muy oscuro, neutro, sin color propio. Y es la decisión
/// correcta por algo más que el gusto — un fondo de televisor tiene una sola
/// obligación, que es DESAPARECER. Todo lo que hay encima son portadas, o
/// sea imágenes de colores fuertes compitiendo entre sí; cualquier fondo con
/// personalidad se les pone en el medio. El degradado apenas se nota, y esa
/// es exactamente la idea: da profundidad sin pedir atención.
///
/// ── Y por qué no cuesta nada ────────────────────────────────────────────
///
/// Un degradado lineal lo resuelve el shader de un tirón, sin capas
/// intermedias ni desenfoques. No hay animación, así que no repinta nunca:
/// el `RepaintBoundary` lo deja como una textura fija que el compositor
/// reusa cuadro a cuadro. En el televisor de 0,9 GB eso importa — el fondo
/// anterior componía dos gradientes radiales con transparencia en cada
/// pantalla, y esas son de las que se pagan en el `raster=` del registro.
class FondoTv extends StatelessWidget {
  const FondoTv({super.key});

  /// El «Carbón» del boceto, tal cual quedó aprobado.
  static const _degradado = LinearGradient(
    // 160° en CSS es casi vertical, cayendo apenas hacia la izquierda. Acá
    // eso son estas dos esquinas: entra por arriba a la derecha y termina
    // abajo a la izquierda.
    begin: Alignment(0.35, -1),
    end: Alignment(-0.35, 1),
    colors: [Color(0xFF16171A), Color(0xFF101114), Color(0xFF0B0C0E)],
    stops: [0, 0.6, 1],
  );

  @override
  Widget build(BuildContext context) {
    // `IgnorePointer` porque es decoración: no puede robarle un toque ni un
    // foco a nada de lo que tiene encima.
    return const RepaintBoundary(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: _degradado),
          // Sin hijo: quien lo usa lo pone en un `Positioned.fill`, así que
          // ya recibe el tamaño de la pantalla desde afuera.
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}
