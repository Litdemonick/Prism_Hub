import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

class HomePageController extends GetxController {
  final RxList<History> resents = <History>[].obs;
  // All favorited types mixed together (Home shows one "Favoritos" section,
  // not one per type — the History page's Favoritos tab still lets you see
  // where each one came from).
  final RxList<Favorite> favorites = <Favorite>[].obs;

  // "Recomendado para ti" — UNA sola fila combinando lo último de cada
  // extensión habilitada (latest(1)), intercalado, en vez de una fila por
  // extensión. Reemplaza "Tendencias"/"Nuevos capítulos" del mockup, que no
  // tienen ninguna señal real de popularidad/actualización en ninguna
  // extensión.
  final RxList<RecommendedItem> recommended = <RecommendedItem>[].obs;

  // Géneros reales vistos en tu propia biblioteca de lectura (favoritos +
  // historial), sacados de la caché local de detalle (PrismHubDetail) — sin
  // llamadas de red nuevas. No hay catálogo de géneros unificado entre
  // extensiones (cada una tiene el suyo), así que esto filtra TU biblioteca,
  // no busca en las extensiones.
  final RxList<String> libraryGenres = <String>[].obs;
  // Uno por título (favorito o con historial), con sus géneros — para poder
  // filtrar al tocar un chip sin re-consultar la base de datos.
  final RxList<LibraryGenreEntry> libraryEntries = <LibraryGenreEntry>[].obs;

  List<LibraryGenreEntry> entriesForGenre(String genre) =>
      libraryEntries.where((e) => e.genres.contains(genre)).toList();

  // Portada real random para el fondo del hero — cambia cada vez que se
  // refresca el home (favoritos/continuar viendo/recomendado, en ese orden
  // de prioridad de pool combinado). Nunca se fabrica una imagen.
  final Rx<HeroBackground?> heroBackground = Rx(null);

  void _pickHeroBackground() {
    final pool = <(String, Map<String, String>?)>[
      ...recommended
          .where((r) => r.cover?.isNotEmpty == true)
          .map((r) => (r.cover!, r.headers)),
      ...resents
          .where((h) => h.cover?.isNotEmpty == true)
          .map((h) => (h.cover!, null)),
      ...favorites
          .where((f) => f.cover?.isNotEmpty == true)
          .map((f) => (f.cover!, null)),
    ];
    if (pool.isEmpty) {
      heroBackground.value = null;
      return;
    }
    final pick = pool[Random().nextInt(pool.length)];
    heroBackground.value = HeroBackground(cover: pick.$1, headers: pick.$2);
  }

  @override
  void onInit() {
    onRefresh();
    super.onInit();
  }

  refreshHistory() async {
    // Fetch first, THEN swap — clearing before the await let the "no
    // history" empty state flash on screen for every refresh (including
    // the one that fires on every visit to Home), even when there was
    // data the whole time.
    final data = await DatabaseService.getHistorysByType();
    resents.value = _onlyEnabled(data, (h) => h.package);
  }

  onRefresh() async {
    // Kick off all independent reads before awaiting any — corre todo en
    // paralelo en vez de uno atrás del otro.
    final historyFuture = DatabaseService.getHistorysByType();
    final favoritesFuture = DatabaseService.getFavoritesByType(limit: 20);

    // "Continuar viendo" mezcla todos los tipos (video + lectura) — un solo
    // lugar para retomar donde quedaste, sin separar por tipo.
    final resentsData = _onlyEnabled(await historyFuture, (h) => h.package);
    final favoritesData = _onlyEnabled(await favoritesFuture, (f) => f.package);
    resents.value = resentsData;
    favorites.value = favoritesData;
    _pickHeroBackground();
    unawaited(_loadLibraryGenres(favoritesData, resentsData));
    unawaited(refreshRecommended().then((_) => _pickHeroBackground()));
  }

  // Oculta (no borra) historial/favoritos de extensiones desinstaladas o
  // desactivadas — si el usuario la vuelve a activar, vuelven a aparecer
  // solos porque el dato sigue intacto en la base, solo se filtra acá.
  List<T> _onlyEnabled<T>(List<T> list, String Function(T) packageOf) {
    return list
        .where((e) => ExtensionUtils.enabledRuntimes.containsKey(packageOf(e)))
        .toList();
  }

  Future<void> _loadLibraryGenres(
    List<Favorite> favs,
    List<History> hist,
  ) async {
    final seen = <String>{};
    final allGenres = <String>{};
    final entries = <LibraryGenreEntry>[];
    for (final (title, url, package, cover, type) in [
      ...favs.map((f) => (f.title, f.url, f.package, f.cover, f.type)),
      ...hist.map((h) => (h.title, h.url, h.package, h.cover, h.type)),
    ]) {
      final key = '$package|$url';
      if (!seen.add(key)) continue;
      final cached = await DatabaseService.getPrismHubDetail(package, url);
      if (cached == null) continue;
      try {
        final detail = ExtensionDetail.fromJson(jsonDecode(cached.data));
        final genres = detail.genres;
        if (genres == null || genres.isEmpty) continue;
        allGenres.addAll(genres);
        entries.add(LibraryGenreEntry(
          title: title,
          url: url,
          package: package,
          cover: cover,
          type: type,
          genres: genres,
        ));
      } catch (_) {}
    }
    libraryGenres.value = allGenres.toList()..sort();
    libraryEntries.value = entries;
  }

  // Adaptado del patrón de SearchPageController.getRuntime()/getResult() —
  // no se toca search_controller.dart, esta es una copia chica propia del
  // Home. Trae hasta 4 por extensión y los intercala (uno de cada una por
  // turno) en una sola lista — nada de filas separadas por extensión.
  Future<void> refreshRecommended() async {
    final exts = ExtensionUtils.enabledRuntimes.values.toList();
    if (!PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
      exts.removeWhere((element) => element.extension.nsfw);
    }
    if (exts.isEmpty) {
      recommended.value = [];
      return;
    }

    final perExtension = <List<RecommendedItem>>[];
    final futures = exts.map((runtime) async {
      try {
        final items = await runtime.latest(1).timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException('Tiempo de espera agotado'),
            );
        return items
            .take(4)
            .map((item) => RecommendedItem(
                  title: item.title,
                  url: item.url,
                  package: runtime.extension.package,
                  cover: item.cover,
                  headers: item.headers,
                  type: runtime.extension.type,
                ))
            .toList();
      } catch (_) {
        return <RecommendedItem>[];
      }
    });
    perExtension.addAll(await Future.wait(futures));

    final merged = <RecommendedItem>[];
    var i = 0;
    while (merged.length < 20 && perExtension.any((l) => i < l.length)) {
      for (final list in perExtension) {
        if (i < list.length) merged.add(list[i]);
      }
      i++;
    }
    recommended.value = merged;
  }
}

// Portada elegida al azar para el fondo del hero.
class HeroBackground {
  final String cover;
  final Map<String, String>? headers;
  HeroBackground({required this.cover, required this.headers});
}

// Un ítem de "Recomendado para ti" — de latest(1) de una extensión
// habilitada, no persistido.
class RecommendedItem {
  final String title;
  final String url;
  final String package;
  final String? cover;
  final Map<String, String>? headers;
  final ExtensionType type;

  RecommendedItem({
    required this.title,
    required this.url,
    required this.package,
    required this.cover,
    required this.headers,
    required this.type,
  });
}

// Título de tu biblioteca (favorito o con historial) con sus géneros reales
// cacheados — solo para armar los chips de género y su filtro en Home, no es
// un modelo persistido.
class LibraryGenreEntry {
  final String title;
  final String url;
  final String package;
  final String? cover;
  final ExtensionType type;
  final List<String> genres;

  LibraryGenreEntry({
    required this.title,
    required this.url,
    required this.package,
    required this.cover,
    required this.type,
    required this.genres,
  });
}
