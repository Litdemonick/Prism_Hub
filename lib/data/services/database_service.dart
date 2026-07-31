// ignore_for_file: experimental_member_use
import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:isar/isar.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

class DatabaseService {
  static final db = PrismHubStorage.database;

  static toggleFavorite({
    required String package,
    required String url,
    required String name,
    String? cover,
    bool isNsfw = false,
  }) async {
    return db.writeTxn(() async {
      if (await isFavorite(
        package: package,
        url: url,
      )) {
        return db.favorites
            .filter()
            .packageEqualTo(package)
            .and()
            .urlEqualTo(url)
            .deleteAll();
      } else {
        final runtime = ExtensionUtils.runtimes[package];
        if (runtime == null) {
          throw Exception('extension not found');
        }
        final extension = runtime.extension;
        return db.favorites.put(
          Favorite()
            ..cover = cover
            ..title = name
            ..package = extension.package
            ..type = extension.type
            ..url = url
            ..isNsfw = isNsfw,
        );
      }
    });
  }

  static Future<bool> isFavorite({
    required String package,
    required String url,
  }) async {
    return (await db.favorites
            .filter()
            .packageEqualTo(package)
            .and()
            .urlEqualTo(url)
            .findFirst()) !=
        null;
  }

  static Future<Favorite?> getFavorite({
    required String package,
    required String url,
  }) async {
    return db.favorites
        .filter()
        .packageEqualTo(package)
        .and()
        .urlEqualTo(url)
        .findFirst();
  }

  static Future<List<Favorite>> getFavoritesByType({
    ExtensionType? type,
    int? limit,
  }) async {
    if (type == null) {
      final query = db.favorites.where().sortByDateDesc();
      if (limit != null) {
        return query.limit(limit).findAll();
      }
      return query.findAll();
    }
    final query = db.favorites.filter().typeEqualTo(type).sortByDateDesc();
    if (limit != null) {
      return query.limit(limit).findAll();
    }
    return query.findAll();
  }

  // 历史记录
  static Future<List<History>> getHistorysByType({ExtensionType? type}) async {
    if (type == null) {
      return db.historys.where().sortByDateDesc().findAll();
    }
    return db.historys.filter().typeEqualTo(type).sortByDateDesc().findAll();
  }

  static Future<History?> getHistoryByPackageAndUrl(
      String package, String url) async {
    return db.historys
        .filter()
        .packageEqualTo(package)
        .and()
        .urlEqualTo(url)
        .findFirst();
  }

  // Migración retroactiva (una sola vez, ver ExtensionUtils.ensureInitialized):
  // marca isNsfw=true en el History/Favorite YA guardado de extensiones que
  // son 100% nsfw. Los registros de ANTES de que existiera este campo se
  // leen con isNsfw=false por defecto — sin esto, ese contenido viejo se
  // quedaría en el Continuar/Favoritos normal en vez de la Zona +18 hasta
  // que se volviera a tocar. No puede recuperar el caso de una extensión
  // MIXTA (ej. ShadeManga) con la opción "adultos" del filtro: ese dato
  // nunca se guardó antes, no hay de dónde inferirlo retroactivamente.
  static Future<void> markNsfwByPackages(Set<String> packages) async {
    if (packages.isEmpty) return;
    await db.writeTxn(() async {
      final histories =
          await db.historys.filter().isNsfwEqualTo(false).findAll();
      for (final h in histories) {
        if (packages.contains(h.package)) {
          h.isNsfw = true;
          await db.historys.put(h);
        }
      }
      final favs = await db.favorites.filter().isNsfwEqualTo(false).findAll();
      for (final f in favs) {
        if (packages.contains(f.package)) {
          f.isNsfw = true;
          await db.favorites.put(f);
        }
      }
    });
  }

  // 更新历史

  /// Guarda un registro ya existente TAL CUAL, sin tocar la fecha ni arrastrar
  /// nada. Para cambios de estado (marcar visto, quitar una novedad) donde
  /// mover el ítem al principio del Historial sería mentir sobre cuándo se vio.
  static Future<void> putHistoryRaw(History history) async {
    // Se resuelve el registro REAL por package&url antes de escribir.
    //
    // Los objetos que llegan acá vienen de listas en memoria (Continuar,
    // Historial) que pueden estar desfasadas. Si el `id` de ese objeto no es
    // el de la base, `put` NO actualiza: inserta una fila nueva y deja la
    // original intacta. Se veía como que "quitar de Continuar" no hacía nada —
    // la tarjeta desaparecía un momento y volvía al refrescar, porque el
    // registro que la alimentaba nunca se había tocado.
    final actual =
        await getHistoryByPackageAndUrl(history.package, history.url);
    if (actual != null) history.id = actual.id;
    await db.writeTxn(() => db.historys.put(history));
  }

  /// Guarda el progreso. OJO: `putByIndex` REEMPLAZA el registro entero, no
  /// hace merge — así que todo campo que quien llama no complete se pierde.
  ///
  /// Por eso se arrastran acá los datos de seguimiento que el usuario puso a
  /// mano o que calculó otro flujo: sin esto, marcar una obra como finalizada
  /// y después leer un capítulo borraba la marca, y lo mismo pasaba con el
  /// contador de capítulos conocidos que sirve para detectar novedades.
  ///
  /// `watchState` y `newEpisodeLabel` NO se arrastran: los decide quien
  /// escribe, porque justamente cambian al leer/ver algo.
  static Future<Id> putHistory(History history) async {
    history.date = DateTime.now();
    final previo =
        await getHistoryByPackageAndUrl(history.package, history.url);
    if (previo != null) {
      history.seriesFinished = previo.seriesFinished;
      history.lastCheckedAt = previo.lastCheckedAt;
      // Si quien escribe no contó los capítulos, se conserva la cuenta previa
      // en vez de pisarla con 0 y perder la referencia de novedades.
      if (history.knownEpisodeCount == 0) {
        history.knownEpisodeCount = previo.knownEpisodeCount;
      }
    }
    return db.writeTxn(() => db.historys.putByIndex(r'package&url', history));
  }

  /// Marca o desmarca que la OBRA terminó de publicarse.
  ///
  /// Si todavía no hay historial de este título —se puede marcar algo sin
  /// haberlo empezado— se crea el registro con `completed`, NO con `pending`:
  /// así aparece en el Historial (que es donde se va a filtrar por finalizado)
  /// pero no en "Continuar", que es para lo que estás viendo ahora. Meterlo en
  /// Continuar sería empujar al usuario a seguir algo que nunca abrió.
  static Future<void> setSeriesFinished({
    required String package,
    required String url,
    required bool finished,
    required ExtensionType type,
    required String title,
    String? cover,
    required bool isNsfw,
  }) async {
    final existente = await getHistoryByPackageAndUrl(package, url);
    if (existente != null) {
      existente.seriesFinished = finished;
      // OJO: no se toca `date`. putHistory la pisa con "ahora" y eso mandaría
      // el título al principio del Historial por marcar una casilla, como si
      // lo acabaras de ver.
      await db.writeTxn(() => db.historys.put(existente));
      return;
    }
    if (!finished) return;
    final nuevo = History()
      ..package = package
      ..url = url
      ..cover = cover
      ..type = type
      ..episodeGroupId = 0
      ..episodeId = 0
      ..title = title
      ..episodeTitle = ''
      ..progress = ''
      ..totalProgress = ''
      ..isNsfw = isNsfw
      ..seriesFinished = true
      ..watchState = WatchState.completed;
    await putHistory(nuevo);
  }

  // 删除历史
  static Future<void> deleteHistoryByPackageAndUrl(
      String package, String url) async {
    return db.writeTxn(
      () => db.historys
          .filter()
          .packageEqualTo(package)
          .urlEqualTo(url)
          .deleteAll(),
    );
  }

  // 删除全部历史
  static Future<void> deleteAllHistory() async {
    return db.writeTxn(() => db.historys.where().deleteAll());
  }

  // 按类型删除历史 (null = 全部)
  static Future<void> deleteHistoryByType(ExtensionType? type) async {
    if (type == null) {
      return deleteAllHistory();
    }
    return db.writeTxn(
      () => db.historys.filter().typeEqualTo(type).deleteAll(),
    );
  }

  // 删除单个收藏
  static Future<void> deleteFavorite(String package, String url) async {
    return db.writeTxn(
      () => db.favorites
          .filter()
          .packageEqualTo(package)
          .and()
          .urlEqualTo(url)
          .deleteAll(),
    );
  }

  // 按类型删除收藏 (null = 全部)
  static Future<void> deleteFavoritesByType(ExtensionType? type) async {
    if (type == null) {
      return db.writeTxn(() => db.favorites.where().deleteAll());
    }
    return db.writeTxn(
      () => db.favorites.filter().typeEqualTo(type).deleteAll(),
    );
  }

  // 扩展设置
  // 获取扩展设置
  static Future<List<ExtensionSetting>> getExtensionSettings(String package) {
    return db.extensionSettings.filter().packageEqualTo(package).findAll();
  }

  // 更新扩展设置
  static Future<Id?> putExtensionSetting(
      String package, String key, String value) async {
    final extensionSetting = await getExtensionSetting(package, key);
    if (extensionSetting == null) {
      return null;
    }
    extensionSetting.value = value;
    debugPrint(extensionSetting.value);
    return db.writeTxn(() => db.extensionSettings.put(extensionSetting));
  }

  // 获取扩展设置
  static Future<ExtensionSetting?> getExtensionSetting(
      String package, String key) async {
    return db.extensionSettings
        .filter()
        .packageEqualTo(package)
        .and()
        .keyEqualTo(key)
        .findFirst();
  }

  // 添加扩展设置
  static Future<Id> registerExtensionSetting(
    ExtensionSetting extensionSetting,
  ) async {
    if (extensionSetting.type == ExtensionSettingType.radio &&
        extensionSetting.options == null) {
      throw Exception('options is null');
    }

    final extSetting = await getExtensionSetting(
        extensionSetting.package, extensionSetting.key);
    // 如果不存在相同设置，则添加
    if (extSetting == null) {
      return db.writeTxn(() => db.extensionSettings.put(extensionSetting));
    }

    extSetting.defaultValue = extensionSetting.defaultValue;

    // 如果类型不同，重置值
    if (extSetting.type != extensionSetting.type) {
      extSetting.type = extensionSetting.type;
      extSetting.value = extensionSetting.defaultValue;
    }
    extSetting.defaultValue = extensionSetting.defaultValue;
    extSetting.description = extensionSetting.description;
    extSetting.options = extensionSetting.options;
    extSetting.title = extensionSetting.title;

    return db.writeTxn(
      () => db.extensionSettings.putByIndex(r'package&key', extSetting),
    );
  }

  // 删除扩展设置
  static Future<void> deleteExtensionSetting(String package) async {
    return db.writeTxn(
      () => db.extensionSettings.filter().packageEqualTo(package).deleteAll(),
    );
  }

  // 清理不需要的扩展设置
  static Future<void> cleanExtensionSettings(
    String package,
    List<String> keys,
  ) async {
    // 需要删除的 id;
    final ids = <int>[];

    final extSettings =
        await db.extensionSettings.filter().packageEqualTo(package).findAll();

    for (final extSetting in extSettings) {
      if (!keys.contains(extSetting.key)) {
        ids.add(extSetting.id);
      }
    }

    return db.writeTxn(() => db.extensionSettings.deleteAll(ids));
  }

  // 获取漫画阅读模式
  static Future<MangaReadMode> getMnagaReaderType(
      String url, MangaReadMode defaultMode) {
    return db.mangaSettings.filter().urlEqualTo(url).findFirst().then(
          (value) => value?.readMode ?? defaultMode,
        );
  }

  // 设置漫画阅读模式
  static Future<Id> setMangaReaderType(
    String url,
    MangaReadMode readMode,
  ) {
    return db.writeTxn(
      () => db.mangaSettings.putByUrl(
        MangaSetting()
          ..url = url
          ..readMode = readMode,
      ),
    );
  }

  // 存储 PrismHubDetail
  static Future<Id> putPrismHubDetail(
    String package,
    String url,
    ExtensionDetail extensionDetail, {
    int? tmdbID,
    String? anilistID,
  }) {
    return db.writeTxn(
      () => db.prismHubDetails.putByIndex(
        r'package&url',
        PrismHubDetail()
          ..data = jsonEncode(extensionDetail.toJson())
          ..package = package
          ..tmdbID = tmdbID
          ..url = url
          ..aniListID = anilistID,
      ),
    );
  }

  // 获取 PrismHubDetail
  static Future<PrismHubDetail?> getPrismHubDetail(
    String package,
    String url,
  ) async {
    return await db.prismHubDetails
        .filter()
        .packageEqualTo(package)
        .and()
        .urlEqualTo(url)
        .findFirst();
  }

  // 更新 TMDB 数据
  static Future<Id> putTMDBDetail(
    int tmdbID,
    TMDBDetail tmdbDetail,
    String mediaType,
  ) {
    return db.writeTxn(
      () => db.tMDBs.putByTmdbID(
        TMDB()
          ..data = jsonEncode(tmdbDetail.toJson())
          ..tmdbID = tmdbID
          ..mediaType = mediaType,
      ),
    );
  }

  // 获取 TMDB 数据
  static Future<TMDBDetail?> getTMDBDetail(int tmdbID) async {
    final tmdb = await db.tMDBs.filter().idEqualTo(tmdbID).findFirst();
    if (tmdb == null) {
      return null;
    }
    try {
      return TMDBDetail.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(tmdb.data),
        ),
      );
    } catch (e) {
      return null;
    }
  }
}
