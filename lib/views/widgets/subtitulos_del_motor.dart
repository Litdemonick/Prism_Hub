import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/motor/motor_media3.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';

/// Los subtítulos, vengan del motor que vengan.
///
/// ── Por qué hace falta un widget para esto ──────────────────────────────────
///
/// Los dibujaba `SubtitleView`, que es de media_kit y lee del reproductor de
/// media_kit. Mientras hubo un solo motor eso alcanzaba. Con el de Android no:
/// ese reproductor nunca recibe la fuente, así que `SubtitleView` no tiene de
/// dónde sacar el texto y en Android no se veía ni un subtítulo — ni los del
/// archivo ni los que manda la extensión aparte.
///
/// Acá se elige el origen según el motor y se dibuja igual en los dos. El
/// aspecto sale de los mismos ajustes de la app (tamaño, color, fondo,
/// alineación), así que un subtítulo se ve igual en el televisor y en el PC.
class SubtitulosDelMotor extends StatelessWidget {
  const SubtitulosDelMotor({
    super.key,
    required this.controlador,
    required this.estilo,
    required this.alineacion,
    this.margen = const EdgeInsets.all(24),
  });

  final VideoPlayerController controlador;
  final TextStyle estilo;
  final TextAlign alineacion;
  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) {
    final motor = controlador.motor;
    if (motor is MotorMedia3) {
      return _DeMedia3(
        motor: motor,
        estilo: estilo,
        alineacion: alineacion,
        margen: margen,
      );
    }
    return SubtitleView(
      controller: controlador.videoController,
      configuration: SubtitleViewConfiguration(
        style: estilo,
        textAlign: alineacion,
        padding: margen,
      ),
    );
  }
}

class _DeMedia3 extends StatelessWidget {
  const _DeMedia3({
    required this.motor,
    required this.estilo,
    required this.alineacion,
    required this.margen,
  });

  final MotorMedia3 motor;
  final TextStyle estilo;
  final TextAlign alineacion;
  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder y no un Obx ni un StreamBuilder: acá llega una
    // línea nueva cada pocos segundos, y lo único que tiene que redibujarse es
    // el texto. Colgado de un observable del reproductor se reconstruiría todo
    // lo que lo envuelve —los controles incluidos— cada vez que cambia el
    // subtítulo, que es justo lo contrario de lo que se busca.
    return ValueListenableBuilder<List<String>>(
      valueListenable: motor.lineasDeSubtitulo,
      builder: (context, lineas, _) {
        if (lineas.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: margen,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final linea in lineas)
                Text(
                  linea,
                  style: estilo,
                  textAlign: alineacion,
                  // Sin tope de líneas: un subtítulo largo se parte en varias y
                  // recortarlo dejaría media frase. El que decide cuánto entra
                  // es el tamaño de letra que eligió la persona.
                  softWrap: true,
                ),
            ],
          ),
        );
      },
    );
  }
}
