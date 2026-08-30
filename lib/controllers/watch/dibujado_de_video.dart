import 'dart:io';

import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_mas.dart';

/// Cómo se dibuja el vídeo en ESTE aparato.
///
/// ── El agujero que tapa ─────────────────────────────────────────────────────
///
/// Hasta ahora el reproductor se creaba con `VideoController(player)`, sin un
/// solo parámetro. Ese constructor acepta siete opciones que deciden quién
/// decodifica y cómo llega el cuadro a la pantalla, y las siete estaban en su
/// valor por omisión: **el televisor más barato y el PC más nuevo recibían
/// exactamente la misma configuración**.
///
/// ── Por qué importa en un televisor ─────────────────────────────────────────
///
/// En Android el camino por omisión es `vo=gpu`, que hace esto por cada cuadro:
///
///     MediaCodec decodifica
///       → mpv lo dibuja con su renderizador OpenGL ES   (pasada 1 de GPU)
///       → SurfaceTexture
///       → Flutter lo compone con el resto de la interfaz (pasada 2 de GPU)
///       → pantalla
///
/// Un teléfono con GPU decente se lo banca. Una caja de televisión no: ahí esas
/// dos pasadas por cuadro son la diferencia entre fluido y a tirones.
///
/// ── Lo que esto SÍ puede hacer, y lo que no ─────────────────────────────────
///
/// Puede bajar el trabajo de GPU por cuadro: decodificar a una resolución
/// acotada en aparatos modestos, en vez de dibujar siempre a la resolución
/// nativa del vídeo.
///
/// **No puede** dar dos cosas que un televisor necesita para verse bien de
/// verdad, y por eso hacen falta los pasos siguientes del plan:
///
///  - **Ajuste de frecuencia de pantalla.** El contenido va a 24 cuadros y el
///    televisor a 60; sin pedirle que cambie de modo, unos cuadros duran dos
///    refrescos y otros tres. Ese tirón es matemático y no mejora con menos
///    carga de GPU. Se pide aparte, al sistema.
///  - **Reproducción tunelizada.** Que el decodificador escriba directo al
///    hardware y la sincronía de audio y vídeo la haga el televisor. Necesita
///    una `SurfaceView`, imposible con el camino de textura.
///
/// ── Por qué escritorio no se toca ───────────────────────────────────────────
///
/// No hay ningún fallo reportado en Windows ni en Linux, y ahí el camino es
/// otro (`vo=libmpv`, sin la composición de Flutter en el medio). Cambiar algo
/// sin una medición que lo pida sería mover lo que anda: se deja el valor por
/// omisión, que es justamente lo que se probó todo este tiempo.
class DibujadoDeVideo {
  DibujadoDeVideo._();

  /// La configuración que le corresponde a este aparato.
  static VideoControllerConfiguration paraEsteAparato() {
    final config = _elegir();
    logger.info(
      'Dibujado del vídeo: escala ${config.scale}'
      '${config.width == null ? '' : ', ancho tope ${config.width}'}'
      ', hardware ${config.enableHardwareAcceleration ? 'sí' : 'no'}'
      ' (perfil ${PerfilDeAparato.nivel.name}'
      '${PlatformTv.esTelevisionSync ? ', televisor' : ''})',
    );
    return config;
  }

  static VideoControllerConfiguration _elegir() {
    // Escritorio: lo de siempre. Ver el comentario de arriba.
    if (!Platform.isAndroid) return const VideoControllerConfiguration();

    // Android que NO es televisor (teléfono, tablet): tampoco se toca.
    //
    // Mismo criterio que `PerfilDeAparato`, que deja a los teléfonos en `alto`
    // a propósito: el trabajo salió de que la app iba mal en televisores, y no
    // hay ninguna medición que diga que un teléfono necesite recortes. Meterlo
    // acá sin dato sería cambiarle el comportamiento a la mayoría a ciegas.
    if (!PlatformTv.esTelevisionSync) {
      return const VideoControllerConfiguration();
    }

    return PrismHubMas.nivel.elegir(
      // Un televisor que anda bien: se deja dibujar a resolución completa. El
      // recorte solo se justifica donde de verdad no da abasto.
      alto: const VideoControllerConfiguration(),
      medio: const VideoControllerConfiguration(),
      // Televisor viejo o stick barato.
      //
      // Se acota el ANCHO al que se dibuja, y con eso el alto sale solo
      // manteniendo la proporción. 1280 y no 1920 porque en estos aparatos la
      // pantalla suele ser 1080p pero la GPU no llega a componer 1080p por
      // cuadro sin tirones — y una imagen un poco menos nítida se nota mucho
      // menos que una que da saltos.
      //
      // `width` sin `height` es a propósito: media_kit calcula el que falta.
      // Si se fijaran los dos y no coincidieran con la proporción real del
      // vídeo, la imagen saldría estirada.
      bajo: const VideoControllerConfiguration(width: 1280),
    );
  }
}
