import 'package:flutter/services.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Vuelve a mostrar las barras del sistema al salir del reproductor o de un
/// lector — salvo en televisor, donde no hay ninguna barra que mostrar.
///
/// ── Por qué hace falta este desvío ────────────────────────────────────────
///
/// El reproductor y los dos lectores, al cerrarse, piden
/// `SystemUiMode.manual` con todos los `overlays`: es lo que hace que la hora
/// y la batería del teléfono vuelvan a verse después de ver algo en pantalla
/// completa. Son ocho llamadas repartidas entre los tres, cada una calibrada
/// en vivo contra bugs concretos (la barra que queda "comida", el estilo que
/// se resetea) — nada de eso se toca acá.
///
/// En un televisor esa restauración hace justo lo contrario de lo que hace
/// falta: no hay hora, ni batería, ni notificaciones que la app tenga que
/// dejar ver, así que "mostrar las barras" al cerrar un vídeo encendería una
/// franja que la Home de TV nunca tuvo puesta. Sin este desvío, cada vez que
/// alguien cerraba un episodio en el televisor la barra de estado del
/// sistema reaparecía sola.
///
/// Se llama en el mismo lugar exacto donde antes iba la llamada directa a
/// `SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, ...)` — nada
/// más cambia alrededor.
void restaurarBarrasDelSistema() {
  if (PlatformTv.esTelevisionSync) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return;
  }
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
}
