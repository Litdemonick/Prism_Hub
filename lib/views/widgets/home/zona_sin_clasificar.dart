import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Una zona (Películas/Series/Anime/Mangas) donde ninguna extensión ACTIVA
/// entra todavía, según `ExtensionUtils.zonasDe` — distinto de no tener
/// ninguna extensión instalada (`_SinExtensiones`, en `home_page.dart`).
///
/// ── Por qué es un estado propio y no el mismo "en construcción" ─────────
///
/// `ZonaEnCreacion` dice "esto todavía no existe en la app" — deja de ser
/// cierto en cuanto la zona funciona de verdad. Esto en cambio dice "la
/// zona funciona, pero tus extensiones no declaran nada para ella todavía"
/// — que es exactamente lo que va a pasar en la práctica hasta que las
/// extensiones reales (otro repo, `prism-plus`) declaren `@contentKind`.
/// Confundir los dos mensajes le haría creer al usuario que hay que
/// esperar una actualización de PrismHub, cuando en realidad lo que falta
/// es que sus extensiones se pongan al día.
///
/// Se muestra cuando la lista filtrada por zona da vacía pero SÍ hay filas
/// cargadas (`c.filas` no vacío) — quien llama decide esa distinción, este
/// widget solo dibuja el aviso.
class ZonaSinClasificar extends StatelessWidget {
  const ZonaSinClasificar({super.key});

  @override
  Widget build(BuildContext context) {
    // ── En televisor, dentro de su marco ───────────────────────────────
    //
    // Mismo criterio que `ZonaEnCreacion`: el aviso ocupa el área donde
    // iría el contenido, con su marco punteado, en vez de quedar como un
    // texto suelto flotando en una pantalla vacía. Pedido explícito:
    // «adaptalo como en la zona de televisión que está en creación, que
    // tiene el marco y el mensaje en el centro».
    final aviso = _aviso(context);
    if (!PlatformTv.esTelevisionSync) return aviso;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: HomeTheme.border),
        ),
        child: SizedBox.expand(child: aviso),
      ),
    );
  }

  Widget _aviso(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 44,
              color: HomeTheme.textMuted,
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'home.zona-sin-clasificar'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
            // Pedido explícito: sin este empujoncito, nada en esta pantalla
            // sugiere que se puede volver a pedir — el gesto ya funciona
            // (ver ZonaCatalogoPage._conRefresco), solo faltaba decirlo.
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'home.zona-sin-clasificar-refrescar'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: HomeTheme.textMuted.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
