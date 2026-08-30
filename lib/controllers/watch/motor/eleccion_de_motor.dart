import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/dibujado_de_video.dart';
import 'package:prismhub/controllers/watch/motor/motor_de_video.dart';
import 'package:prismhub/controllers/watch/motor/motor_mpv.dart';

/// Qué motor de vídeo usa la app: mpv, en las cuatro plataformas.
///
/// ── Hubo un segundo motor, y se volvió atrás ────────────────────────────────
///
/// Se escribió un motor propio para Android contra Media3, con el vídeo
/// dibujado en una capa aparte del sistema en vez de pasar por el dibujado de
/// la interfaz.
///
/// La parte técnica funcionó, y está medido en un teléfono: el tiempo de
/// dibujado de cada cuadro bajó de unos 140 ms a menos de 40, que era
/// exactamente lo que se buscaba.
///
/// Lo que lo tumbó fue otra cosa. Media docena de partes de la app le hablaban
/// a media_kit directo —los subtítulos, la lista de pistas de audio, el aviso
/// de que ya hay imagen, parar el vídeo al salir— y con un segundo motor cada
/// una de esas se rompía en silencio, de a una, y había que ir encontrándolas
/// probando en un aparato real. Cada una costaba una vuelta entera de prueba.
///
/// Se vuelve a un solo motor, que es lo que estaba probado y andando.
///
/// ── Qué queda de aquello, y por qué conviene que quede ──────────────────────
///
/// La fachada [MotorDeVideo]. Las partes de la app que antes le hablaban a
/// media_kit directo ahora le hablan a ella, así que si algún día se retoma un
/// segundo motor, ese trabajo de rastreo ya está hecho.
///
/// El motor de Media3 —con su lado nativo en Kotlin, sus subtítulos y su
/// selector de pistas— está en el historial del repositorio. No se perdió.
///
/// ── Y por qué esto no se elige a mano ───────────────────────────────────────
///
/// Un interruptor obliga a la persona a decidir algo sobre lo que no tiene
/// información. Con un solo motor, además, no habría nada que elegir.
class EleccionDeMotor {
  EleccionDeMotor._();

  static const mpv = 'mpv';

  /// No se elige: hay uno solo. Se conserva porque la pantalla de Ajustes
  /// pregunta antes de dibujar nada.
  static bool get sePuedeElegir => false;

  static MotorDeVideo armar({
    required Player player,
    required VideoController videoController,
  }) =>
      MotorMpv(player: player, videoController: videoController);

  /// La configuración de dibujado del vídeo, según el aparato.
  static VideoControllerConfiguration dibujado() =>
      DibujadoDeVideo.paraEsteAparato();
}
