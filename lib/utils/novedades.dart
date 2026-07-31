import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Detecta capítulos o episodios nuevos en lo que el usuario ya terminó de ver.
///
/// Es el ÚNICO flujo de seguimiento que hace red por su cuenta, así que está
/// deliberadamente acotado: es una petición por obra a extensiones que ya
/// sabemos que son lentas y que a veces fallan.
///
/// Las reglas, todas por el mismo motivo — que esto no se note:
/// - Solo mira lo `completed`. Lo pendiente ya está en "Continuar", no hace
///   falta avisar de nada.
/// - Como mucho una vez cada [_cadaHoras] por obra.
/// - [_enParalelo] a la vez, no todas de golpe.
/// - En segundo plano: nunca bloquea el Home.
/// - Si falla, se ignora en silencio y se reintenta al vencer la ventana. Una
///   extensión caída no puede alterar el estado guardado.
class Novedades {
  Novedades._();

  static const _cadaHoras = 12;
  static const _enParalelo = 3;

  static bool _corriendo = false;

  /// true si el usuario dejó la comprobación activada (viene encendida).
  static bool get activada =>
      PrismHubStorage.getSetting(SettingKey.checkNewEpisodes) != false;

  /// Revisa y devuelve true si encontró alguna novedad, para que quien llame
  /// sepa si vale la pena releer las listas.
  ///
  /// Se llama sin await desde el refresco del Home.
  static Future<bool> comprobar(List<History> historial) async {
    if (!activada || _corriendo) return false;
    _corriendo = true;
    try {
      final ahora = DateTime.now();
      final pendientesDeRevisar = historial.where((h) {
        // Solo lo terminado: es lo único que puede "volver" a Continuar.
        if (h.watchState != WatchState.completed) return false;
        // Ya tiene una novedad sin abrir — no hace falta volver a preguntar.
        if (h.hasNewEpisode) return false;
        // La extensión tiene que estar instalada y activa.
        if (!ExtensionUtils.enabledRuntimes.containsKey(h.package)) {
          return false;
        }
        final ultima = h.lastCheckedAt;
        if (ultima == null) return true;
        return ahora.difference(ultima).inHours >= _cadaHoras;
      }).toList();

      if (pendientesDeRevisar.isEmpty) return false;

      var huboNovedad = false;
      var siguiente = 0;

      Future<void> trabajador() async {
        while (siguiente < pendientesDeRevisar.length) {
          // Dart es de un solo hilo: leer e incrementar acá es atómico, no hay
          // await en el medio, así que dos trabajadores nunca toman el mismo.
          final item = pendientesDeRevisar[siguiente++];
          if (await _revisarUno(item)) huboNovedad = true;
        }
      }

      await Future.wait([
        for (var i = 0; i < _enParalelo && i < pendientesDeRevisar.length; i++)
          trabajador(),
      ]);
      return huboNovedad;
    } finally {
      _corriendo = false;
    }
  }

  static Future<bool> _revisarUno(History h) async {
    final runtime = ExtensionUtils.enabledRuntimes[h.package];
    if (runtime == null) return false;
    try {
      final detalle = await runtime.detail(h.url);
      final total = (detalle.episodes ?? [])
          .fold<int>(0, (n, g) => n + (g.urls?.length ?? 0));
      // La marca de tiempo se pone SIEMPRE que la consulta responda, haya
      // novedad o no: si solo se guardara al encontrar algo, una obra sin
      // novedades se consultaría en cada refresco del Home.
      h.lastCheckedAt = DateTime.now();

      // Primera vez que se cuenta esta obra: solo se guarda la referencia.
      // Sin esto, al estrenar la función TODO el historial viejo aparecería
      // como novedad de golpe, que es exactamente lo contrario de avisar.
      if (h.knownEpisodeCount == 0) {
        h.knownEpisodeCount = total;
        await DatabaseService.putHistoryRaw(h);
        return false;
      }

      if (total <= h.knownEpisodeCount) {
        await DatabaseService.putHistoryRaw(h);
        return false;
      }

      // Hay algo nuevo.
      h.knownEpisodeCount = total;
      h.newEpisodeLabel = _nombreDelUltimo(detalle);
      h.watchState = WatchState.pending;
      // Se quita la marca de obra finalizada: que lleguen capítulos demuestra
      // que no lo estaba, o que volvió. Era una creencia del usuario y la
      // realidad la contradijo. Si de verdad terminó y esto era un especial,
      // vuelve a marcarla en dos toques.
      h.seriesFinished = false;
      await DatabaseService.putHistoryRaw(h);
      return true;
    } catch (e) {
      // Extensión caída, sitio sin responder, formato raro. No se toca el
      // estado guardado ni se marca como revisada: se reintenta la próxima.
      logger.info('Sin poder comprobar novedades de ${h.title}: $e');
      return false;
    }
  }

  static String? _nombreDelUltimo(ExtensionDetail detalle) {
    final grupos = detalle.episodes ?? [];
    for (final g in grupos.reversed) {
      final urls = g.urls;
      if (urls != null && urls.isNotEmpty) return urls.last.name;
    }
    return null;
  }
}
