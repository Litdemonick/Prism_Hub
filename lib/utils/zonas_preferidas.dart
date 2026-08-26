import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Qué zonas quiere ver el usuario mezcladas en Inicio.
///
/// ── Por qué vacío significa "todas" y no "ninguna" ──────────────────────
///
/// Inicio hoy mezcla todo sin distinción, y a nadie que nunca toque este
/// ajuste nuevo se le puede cambiar ese comportamiento sin avisar. Vacío es
/// el estado de quien nunca lo tocó: se sigue viendo exactamente igual que
/// siempre.
///
/// ── Por qué esto NO pide nada de red ────────────────────────────────────
///
/// Es un filtro sobre `c.filas`, que ya está en memoria (mismo `.where()`
/// que ya usa `HomeAndroid._visibles` para el estado activa/apagada) — ver
/// el mismo criterio en `home_page_android.dart`/`home_page_windows.dart`/
/// `home_page_tv.dart`. Cambiar la preferencia y volver a Inicio no
/// dispara ningún refresco de extensiones, solo recalcula qué filas se
/// dibujan.
class ZonasPreferidasEnInicio {
  ZonasPreferidasEnInicio._();

  static final RxSet<ZonaPrincipal> elegidas = <ZonaPrincipal>{}.obs;
  static bool _loaded = false;

  static void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = PrismHubStorage.getSetting(SettingKey.zonasEnInicio);
    if (raw is! List) return;
    for (final nombre in raw) {
      for (final zona in ZonaPrincipal.values) {
        if (zona.name == nombre) {
          elegidas.add(zona);
          break;
        }
      }
    }
  }

  static Future<void> alternar(ZonaPrincipal zona) async {
    ensureLoaded();
    if (elegidas.contains(zona)) {
      elegidas.remove(zona);
    } else {
      elegidas.add(zona);
    }
    await PrismHubStorage.setSetting(
      SettingKey.zonasEnInicio,
      elegidas.map((z) => z.name).toList(),
    );
  }

  /// ¿Esta extensión entra en lo que el usuario eligió ver en Inicio?
  ///
  /// Sin clasificar (`zonasDe` da vacío) SIEMPRE pasa — no es que el
  /// usuario la haya elegido, es que todavía no hay dato para decidir, y
  /// ocultarla sería perder contenido real por un `contentKind` que la
  /// extensión no declaró (ver el mismo principio en el resto del plan de
  /// rediseño).
  static bool pasaElFiltro(Set<ZonaPrincipal> zonasDeLaExtension) {
    ensureLoaded();
    if (elegidas.isEmpty) return true;
    if (zonasDeLaExtension.isEmpty) return true;
    return zonasDeLaExtension.any(elegidas.contains);
  }
}
