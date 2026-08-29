import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/dibujado_de_video.dart';
import 'package:prismhub/controllers/watch/motor/motor_de_video.dart';
import 'package:prismhub/controllers/watch/motor/motor_exo.dart';
import 'package:prismhub/controllers/watch/motor/motor_mpv.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Qué motor de vídeo usar.
///
/// ── El criterio: plataforma y formato, NUNCA extensión ──────────────────────
///
/// Es la decisión de fondo y conviene dejarla escrita porque es fácil
/// equivocarse: **el motor no se elige por extensión**. jkanime sola tiene once
/// servidores de once proveedores distintos, y VOE aparece en jkanime, latanime
/// y animefenix — es el mismo flujo, no puede cambiar de motor según de dónde
/// venga el enlace.
///
/// Lo que decide es:
///
///  - **La plataforma.** En Windows y Linux no hay ExoPlayer: siempre mpv.
///  - **El formato.** HLS con fMP4 es donde mpv se queda clavado al saltar.
///
/// Si la regla fuera por extensión, mañana otra sirve fMP4 y vuelve a fallar.
/// Por formato queda cubierta sola.
///
/// ── El interruptor de Ajustes es TEMPORAL ───────────────────────────────────
///
/// Está en la versión publicada a propósito, para poder recorrer las veinte
/// extensiones probando los dos motores en un televisor y un teléfono reales,
/// sin publicar una versión por prueba. Se saca cuando el recorrido termine y
/// el automático esté confirmado.
class EleccionDeMotor {
  EleccionDeMotor._();

  static const autom = 'auto';
  static const mpv = 'mpv';
  static const exo = 'exoplayer';

  /// Lo que el usuario eligió, o [autom] si no tocó nada.
  static String get elegido {
    final guardado = PrismHubStorage.getSetting(SettingKey.motorDeVideo);
    if (guardado is String &&
        (guardado == mpv || guardado == exo || guardado == autom)) {
      return guardado;
    }
    return autom;
  }

  /// Si en este aparato se puede elegir.
  ///
  /// ── APAGADO a propósito, y esto hay que arreglarlo antes de encenderlo ───
  ///
  /// Salió en la 1.0.42 y estaba roto: al elegir ExoPlayer se escuchaba el
  /// audio pero la pantalla quedaba NEGRA. Reportado en vivo en un televisor.
  ///
  /// La causa, medida: el commit que metió la fachada enganchó la VISTA al
  /// motor, pero no la REPRODUCCIÓN. El controlador sigue abriendo el vídeo
  /// con `player.open()` de media_kit en los siete sitios donde abre, y lee
  /// todo su estado —posición, duración, si reproduce— de `player.state`. Así
  /// que al elegir ExoPlayer pasaba esto:
  ///
  ///   - la vista era la de ExoPlayer, que no tenía nada cargado → negro;
  ///   - mpv seguía reproduciendo por debajo → se escuchaba.
  ///
  /// Encenderlo de nuevo pide llevar a la fachada las aperturas Y todo el
  /// estado que el controlador lee del reproductor. Es el paso 3.2 del plan
  /// (partir el reproductor), que justamente por eso iba antes.
  ///
  /// Mientras tanto se apaga: un interruptor que deja la pantalla en negro es
  /// peor que no tenerlo.
  static bool get sePuedeElegir => false;

  /// Arma el motor que corresponde.
  ///
  /// [player] y [videoController] son los de media_kit, que se crean igual
  /// siempre: el reproductor los sigue usando para cosas propias de mpv
  /// (propiedades de libmpv, pistas, captura). Si el motor elegido es ExoPlayer
  /// quedan sin usarse para reproducir, pero crearlos no cuesta nada y evita
  /// tener que hacer condicionales por todo el controlador.
  static MotorDeVideo armar({
    required Player player,
    required VideoController videoController,
  }) {
    final cual = _decidir();
    logger.info('Motor de vídeo: $cual '
        '(ajuste: $elegido, plataforma: ${Platform.operatingSystem})');
    if (cual == exo) return MotorExo();
    return MotorMpv(player: player, videoController: videoController);
  }

  static String _decidir() {
    // Fuera de Android no hay alternativa, pase lo que pase en el ajuste.
    if (!Platform.isAndroid) return mpv;
    final pedido = elegido;
    if (pedido == exo) return exo;
    if (pedido == mpv) return mpv;
    // Automático: por ahora mpv, que es lo probado.
    //
    // El automático va a pasar a elegir por formato —ExoPlayer cuando la lista
    // sea fMP4, que es donde mpv se traba— pero eso se enciende cuando el
    // recorrido de extensiones confirme que ExoPlayer se comporta bien. Hasta
    // entonces, dejar el automático en lo conocido es lo honesto: nadie recibe
    // un motor sin probar por una actualización.
    return mpv;
  }

  /// La configuración de dibujado, solo si el motor la usa.
  ///
  /// Es de media_kit; ExoPlayer dibuja por su cuenta. Se pide igual porque el
  /// `VideoController` se crea siempre.
  static VideoControllerConfiguration dibujado() =>
      DibujadoDeVideo.paraEsteAparato();
}
