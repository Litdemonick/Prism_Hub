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
/// ── Ya no se elige a mano ───────────────────────────────────────────────────
///
/// El interruptor de Ajustes existió para recorrer las extensiones probando
/// los dos motores en aparatos reales. Ese recorrido terminó con la decisión
/// tomada: **escritorio con mpv, Android con ExoPlayer**, que es lo mismo que
/// hacen las apps de vídeo del sistema.
///
/// Un interruptor obliga a la persona a decidir algo sobre lo que no tiene
/// información —cuál de dos motores va mejor con el servidor que le tocó— y
/// deja media base usando el camino equivocado sin saberlo.
///
/// ── Y con reserva automática ────────────────────────────────────────────────
///
/// Sacar el interruptor deja sin salida a quien se tope con una fuente que
/// ExoPlayer no sepa abrir. Por eso, si falla al abrir, se cae a mpv solo y
/// queda anotado en el registro. La persona ve el vídeo; nosotros vemos en el
/// registro con qué fuente pasó.
class EleccionDeMotor {
  EleccionDeMotor._();

  static const autom = 'auto';
  static const mpv = 'mpv';
  static const exo = 'exoplayer';

  /// Lo que quedó guardado de cuando se podía elegir.
  ///
  /// Ya no decide nada — se conserva solo para poder anotarlo en el registro
  /// si algún aparato viene de una versión donde sí se elegía, y entender por
  /// qué se comportaba distinto.
  static String get elegido {
    final guardado = PrismHubStorage.getSetting(SettingKey.motorDeVideo);
    if (guardado is String &&
        (guardado == mpv || guardado == exo || guardado == autom)) {
      return guardado;
    }
    return autom;
  }

  /// Ya no se elige a mano en ninguna plataforma. Ver la nota de la clase.
  static bool get sePuedeElegir => false;

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
    // Escritorio: mpv, que es el único que hay ahí.
    if (!Platform.isAndroid) return mpv;
    // Android —teléfono y televisor—: ExoPlayer.
    //
    // Es el motor del sistema, dibuja en superficie nativa y por eso el vídeo
    // y la interfaz van por carriles separados: la interfaz se redibuja solo
    // cuando algo cambia y el vídeo avanza a su ritmo. Con textura los dos
    // comparten carril y cada cuadro de vídeo es una pasada de dibujado de la
    // interfaz — que es lo que se medía como tirones en televisores.
    return exo;
  }

  /// Lo que queda del camino viejo, por si hiciera falta volver a mirarlo.
  // ignore: unused_element
  static String _decidirPorAjuste() {
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
