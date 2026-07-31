import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:isar/isar.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:path/path.dart' as p;

class PrismHubStorage {
  // Fuente única de la URL del repositorio: la usa tanto la inicialización de
  // ajustes como el respaldo de ExtensionUtils cuando el ajuste guardado no
  // sirve. Antes era una constante local acá, así que el otro lado no tenía
  // de dónde sacarla si el ajuste venía en null.
  static const String _defaultAndroidUA =
      "Mozilla/5.0 (Linux; Android 13; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.43 Mobile Safari/537.36";
  static const String _defaultDesktopUA =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0";

  static const String defaultRepoUrl =
      "https://raw.githubusercontent.com/Litdemonick/prism-plus/main";

  // Espejo reactivo del switch de NSFW de Ajustes. Leer el ajuste al
  // construir no alcanza: en Android el shell mantiene las páginas vivas en
  // un IndexedStack, así que apagar el switch y volver a Buscar NO
  // reconstruye esa página — el botón +18 seguía visible (la puerta sí
  // bloqueaba al tocarlo, pero visualmente parecía habilitado).
  static final RxBool nsfwEnabled = false.obs;

  static late final Isar database;
  static late final Box settings;
  static const int _lastDatabaseVersion = 2;
  static late String _path;

  static ensureInitialized() async {
    _path = PrismHubDirectory.getDirectory;
    await Hive.initFlutter(_path);
    try {
      settings = await Hive.openBox("settings");
    } catch (e, st) {
      // La caja quedó ilegible. El caso visto en vivo fue
      // "unknown typeId: 115": el archivo de Hive se escribe agregando al
      // final, así que si el sistema mata el proceso a mitad de una escritura
      // (por ejemplo apagando la pantalla durante la reproducción) queda un
      // registro truncado que ya no se puede leer.
      logger.severe('La caja de ajustes está corrupta', e, st);
      try {
        // Se APARTA el archivo, no se borra: los ajustes viejos ya son
        // ilegibles de todos modos, pero dejarlos guardados permite
        // recuperarlos después si hiciera falta.
        await _quarantineCorruptBox('settings');
        settings = await Hive.openBox("settings");
        logger.warning('Ajustes reiniciados a los valores de fábrica');
      } catch (e2, st2) {
        // Último recurso. Ojo: una caja temporal se pierde en cada arranque,
        // así que esto NO es una solución, solo evita quedarse sin nada.
        logger.severe('No se pudo recrear la caja de ajustes', e2, st2);
        settings = await Hive.openBox("settings_tmp");
      }
    }

    // SIEMPRE, pase lo que pase arriba. Antes esto vivía DENTRO del try, así
    // que al caer a la caja temporal no se ejecutaba nunca y la app arrancaba
    // sin un solo valor por defecto: la URL del repositorio quedaba en null
    // ("No host specified in URI null/index.json") y el proxy también
    // ("Invalid proxy configuration null null"), o sea que no cargaba
    // absolutamente nada y parecía que no había internet.
    try {
      await _initSettings();
    } catch (e, st) {
      logger.severe('No se pudieron inicializar los ajustes', e, st);
    }

    try {
      database = await Isar.open(
        [
          FavoriteSchema,
          HistorySchema,
          ExtensionSettingSchema,
          MangaSettingSchema,
          PrismHubDetailSchema,
          TMDBSchema,
        ],
        directory: _path,
        inspector: false,
      );
      await performMigrationIfNeeded();
    } catch (e) {
      debugPrint('ERROR: Isar init falló, usando DB temporal: $e');
      final tmpPath = Directory.systemTemp.createTempSync('prismhub_isar_');
      database = await Isar.open(
        [
          FavoriteSchema,
          HistorySchema,
          ExtensionSettingSchema,
          MangaSettingSchema,
          PrismHubDetailSchema,
          TMDBSchema,
        ],
        directory: tmpPath.path,
        inspector: false,
      );
    }
  }

  // Mueve los archivos de una caja ilegible a un nombre con marca de tiempo,
  // para que Hive pueda crear una limpia sin destruir lo anterior.
  static Future<void> _quarantineCorruptBox(String name) async {
    await Hive.close();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final ext in const ['.hive', '.lock']) {
      final file = File(p.join(_path, '$name$ext'));
      if (await file.exists()) {
        await file.rename(p.join(_path, '$name.corrupt-$stamp$ext'));
      }
    }
    await Hive.initFlutter(_path);
  }

  static performMigrationIfNeeded() async {
    final currentVersion = await getDatabaseVersion();
    debugPrint(currentVersion.toString());
    switch (currentVersion) {
      case 1:
        await migrateV1ToV2();
        break;
      case 2:
        return;
      default:
        throw Exception('Unknown version: $currentVersion');
    }

    // 更新到最新版本
    await settings.put(SettingKey.databaseVersion, _lastDatabaseVersion);
  }

  static migrateV1ToV2() async {
    // 获取所有的 TMDB 数据
    final tmdbList = await database.tMDBs.where().findAll();
    database.writeTxn(() async {
      // 给所有的 TMDB 数据添加 mediaType 字段
      for (final tmdb in tmdbList) {
        final tmdbdetail = TMDBDetail.fromJson(jsonDecode(tmdb.data));
        tmdb.mediaType = tmdbdetail.mediaType;
        await database.tMDBs.put(tmdb);
      }
    });

    // 修改所有 PrismDetail 的 tmdbId 字段为本地的 TMDB id
    final prismList = await database.prismHubDetails.where().findAll();
    database.writeTxn(() async {
      for (final detail in prismList) {
        final tmdb = await database.tMDBs
            .where()
            .filter()
            .tmdbIDEqualTo(detail.tmdbID!)
            .findFirst();
        if (tmdb != null) {
          detail.tmdbID = tmdb.id;
          await database.prismHubDetails.put(detail);
        }
      }
    });
  }

  // 获取数据库版本
  static Future<int> getDatabaseVersion() async {
    // 先获取数据库版本
    final version = await settings.get(SettingKey.databaseVersion);
    // 如果没有版本号，并且没有数据库文件说明是第一次使用，返回最新的数据库版本
    if (version == null) {
      final path = PrismHubDirectory.getDirectory;
      final dbPath = p.join(path, 'default.isar');
      if (File(dbPath).existsSync()) {
        return 1;
      }
      // 设置数据库版本并返回最新版本
      await settings.put(SettingKey.databaseVersion, _lastDatabaseVersion);
      return _lastDatabaseVersion;
    }
    // 如果有版本号，返回版本号
    return version;
  }

  static _initSettings() async {
    const correctRepoUrl = defaultRepoUrl;
    final savedUrl = settings.get(SettingKey.prismhubRepoUrl);
    if (savedUrl != null &&
        (savedUrl.toString().contains("jephersonrd.github.io") ||
            savedUrl.toString().contains("jephersonRD/JiruHub"))) {
      await settings.put(SettingKey.prismhubRepoUrl, correctRepoUrl);
    }
    await _initSetting(SettingKey.prismhubRepoUrl, correctRepoUrl);
    // La URL del repositorio quedó bloqueada en Ajustes (el oficial es el
    // único soportado), así que se fuerza de vuelta — mismo criterio que con
    // proxyType y videoPlayer más abajo, que también se bloquearon.
    //
    // Hace falta forzar el valor ENTERO y no solo validar que tenga host:
    // borrando unos caracteres se llega a algo como
    // "raw.githubusercontent.com/Litdemonick/pri", que pasa cualquier chequeo
    // de forma —el host existe— pero apunta a una ruta que no existe, así que
    // el índice da 404 y el app se queda sin catálogo. Y _initSetting no
    // ayuda: la clave existe, solo que con un valor equivocado.
    if (settings.get(SettingKey.prismhubRepoUrl) != correctRepoUrl) {
      await settings.put(SettingKey.prismhubRepoUrl, correctRepoUrl);
    }
    await _initSetting(SettingKey.tmdbKey, "");
    await _initSetting(SettingKey.autoCheckUpdate, true);
    // Solo se guarda el idioma del sistema si la app lo tiene traducido; con
    // cualquier otro se dejaba guardado un código sin archivo (ej. 'pt' en un
    // teléfono en portugués), y el selector de Ajustes quedaba sin ninguna
    // opción marcada. La lista de idiomas soportados vive en I18nUtils.
    final systemLang = Platform.localeName.split('_').first;
    await _initSetting(
      SettingKey.language,
      I18nUtils.supportedLanguages.contains(systemLang) ? systemLang : 'en',
    );
    await _initSetting(SettingKey.novelFontSize, 18.0);
    await _initSetting(SettingKey.theme, 'system');
    await _initSetting(SettingKey.enableNSFW, false);
    nsfwEnabled.value = getSetting(SettingKey.enableNSFW) == true;
    await _initSetting(SettingKey.videoPlayer, 'built-in');
    await _initSetting(SettingKey.listMode, "grid");
    await _initSetting(SettingKey.keyI, 10.0);
    await _initSetting(SettingKey.keyJ, -10.0);
    await _initSetting(SettingKey.arrowLeft, -2.0);
    await _initSetting(SettingKey.arrowRight, 2.0);
    await _initSetting(SettingKey.readingMode, "standard");
    await _initSetting(SettingKey.aniListToken, '');
    await _initSetting(SettingKey.aniListUserId, '');
    await _initSetting(SettingKey.autoTracking, true);
    await _initSetting(SettingKey.windowSize, "1280,720");
    await _initSetting(SettingKey.androidWebviewUA, _defaultAndroidUA);
    await _initSetting(SettingKey.windowsWebviewUA, _defaultDesktopUA);
    // Los User-Agent quedaron bloqueados en Ajustes: se fuerzan de vuelta si
    // quedó guardado uno vacío o recortado de antes del bloqueo. Con un UA
    // inválido los sitios rechazan todo y el síntoma es "sin conexión", que
    // no se parece en nada a la causa.
    for (final entry in {
      SettingKey.androidWebviewUA: _defaultAndroidUA,
      SettingKey.windowsWebviewUA: _defaultDesktopUA,
    }.entries) {
      final stored = settings.get(entry.key);
      if (stored is! String || stored.trim().length < 20) {
        await settings.put(entry.key, entry.value);
      }
    }
    await _initSetting(SettingKey.proxy, '');
    await _initSetting(SettingKey.proxyType, 'DIRECT');
    // El tipo de proxy quedó bloqueado en Ajustes (SOCKS5/SOCKS4/PROXY
    // activan flutter_socks_proxy, una reimplementación pura en Dart de
    // HttpClient que enruta TODA la app por su parser vía
    // HttpOverrides.global — causa confirmada en vivo de lentitud general).
    // Quien ya tenía guardado un valor distinto de "DIRECT" de antes de este
    // bloqueo queda forzado de vuelta, para no dejarlo atascado en un modo
    // que ya no puede cambiar desde la UI.
    if (settings.get(SettingKey.proxyType) != 'DIRECT') {
      await settings.put(SettingKey.proxyType, 'DIRECT');
    }
    // Ídem con el reproductor: por ahora toda la app usa el incorporado
    // (la opción quedó bloqueada en Ajustes), así que quien tuviera VLC/
    // PotPlayer/mpv guardado de antes vuelve a "built-in" — si no, quedaba
    // atascado en un reproductor externo que ya no puede cambiar desde la
    // UI.
    if (settings.get(SettingKey.videoPlayer) != 'built-in') {
      await settings.put(SettingKey.videoPlayer, 'built-in');
    }
    await _initSetting(SettingKey.saveLog, true);
    await _initSetting(SettingKey.subtitleFontSize, 46.0);
    await _initSetting(SettingKey.subtitleFontColor, Colors.white.toARGB32());
    await _initSetting(SettingKey.subtitleFontWeight, 'bold');
    await _initSetting(
        SettingKey.subtitleBackgroundColor, Colors.black.toARGB32());
    await _initSetting(SettingKey.subtitleBackgroundOpacity, 0.5);
    await _initSetting(SettingKey.subtitleTextAlign, TextAlign.center.index);
  }

  // OJO con containsKey a secas: una clave que EXISTE con valor null pasaba
  // el chequeo y nunca se corregía. Ese fue el fallo real de "type 'Null' is
  // not a subtype of type 'bool'" en main_page: autoCheckUpdate estaba
  // guardado como null y getSetting lo devolvía crudo a un `if`.
  static _initSetting(String key, dynamic value) async {
    if (!settings.containsKey(key) || settings.get(key) == null) {
      await settings.put(key, value);
    }
    _defaults[key] = value;
  }

  // Último valor por defecto conocido de cada ajuste, para que getSetting
  // NUNCA devuelva null en una clave que tiene default. Se llena desde el
  // mismo _initSetting, así que no hay una segunda lista que mantener en
  // sincronía (y por lo tanto no puede quedar desactualizada).
  static final Map<String, dynamic> _defaults = {};

  static setSetting(String key, dynamic value) async {
    await settings.put(key, value);
    // Se mantiene en sincronía desde acá —el único punto de escritura— para
    // que no pueda quedar desfasado del valor real.
    if (key == SettingKey.enableNSFW) {
      nsfwEnabled.value = value == true;
    }
  }

  // Devolver null desde acá es peligroso: casi todos los llamadores usan el
  // resultado directamente como bool/String/double (`if (getSetting(x))`,
  // `Locale(getSetting(y))`), así que un null no da un valor raro — tumba la
  // pantalla entera con un error de tipo. Con el default de respaldo, un
  // ajuste corrupto o borrado degrada al comportamiento de fábrica en vez de
  // romper el app.
  static getSetting(String key) {
    final value = settings.get(key);
    if (value != null) return value;
    return _defaults[key];
  }

  static getUASetting() {
    if (Platform.isAndroid) {
      return getSetting(SettingKey.androidWebviewUA);
    }
    return getSetting(SettingKey.windowsWebviewUA); // Windows & Linux
  }

  static setUASetting(String value) async {
    if (Platform.isAndroid) {
      await setSetting(SettingKey.androidWebviewUA, value);
    } else {
      await setSetting(SettingKey.windowsWebviewUA, value);
    }
  }

  // Recuerda el último servidor que reprodujo bien un episodio concreto, para
  // probarlo primero la próxima vez y no re-buscar entre todos (carga más rápido).
  static String? getLastWorkingServer(String package, String episodeUrl) {
    final v = settings.get('lastServer:$package:$episodeUrl');
    return v is String && v.isNotEmpty ? v : null;
  }

  static setLastWorkingServer(
      String package, String episodeUrl, String server) async {
    await settings.put('lastServer:$package:$episodeUrl', server);
  }

  static String? getLastPlaybackMode(String package, String episodeUrl) {
    final v = settings.get('lastPlaybackMode:$package:$episodeUrl');
    return v is String && v.isNotEmpty ? v : null;
  }

  static setLastPlaybackMode(
      String package, String episodeUrl, String mode) async {
    await settings.put('lastPlaybackMode:$package:$episodeUrl', mode);
  }

  // Recuerda el embed URL del page-sniff que reprodujo bien el episodio.
  // Permite saltarse el escaneo de toda la página y probar ese embed directo.
  static String? getPageSniffEmbed(String package, String episodeUrl) {
    final v = settings.get('pageSniffEmbed:$package:$episodeUrl');
    return v is String && v.isNotEmpty ? v : null;
  }

  static Future<void> setPageSniffEmbed(
      String package, String episodeUrl, String embedUrl) async {
    await settings.put('pageSniffEmbed:$package:$episodeUrl', embedUrl);
  }
}

class SettingKey {
  static const theme = "Theme";
  static const prismhubRepoUrl = "prismhubRepoUrl";
  static const defaultExtensionsInstalled = "DefaultExtensionsInstalled";
  static const disabledExtensions = "DisabledExtensions";
  static const hiddenCards = "HiddenCards";
  static const tmdbKey = 'TMDBKey';
  static const autoCheckUpdate = 'AutoCheckUpdate';
  static const language = 'Language';
  static const novelFontSize = 'NovelFontSize';
  static const enableNSFW = 'EnableNSFW';
  static const videoPlayer = 'VideoPlayer';
  static const databaseVersion = 'DatabaseVersion';
  static const listMode = 'ListMode';
  static const keyI = 'KeyI';
  static const keyJ = 'KeyJ';
  static const arrowLeft = 'Arrowleft';
  static const arrowRight = 'Arrowright';
  static const readingMode = 'ReadingMode';
  static const aniListToken = 'AniListToken';
  static const aniListUserId = 'AniListUserId';
  static const autoTracking = 'AutoTracking';
  static const windowSize = 'WindowsSize';
  static const windowPosition = 'WindowsPosition';
  static const androidWebviewUA = "AndroidWebviewUA";
  static const windowsWebviewUA = "WindowsWebviewUA";
  static const proxy = "Proxy";
  static const proxyType = "ProxyType";
  static const saveLog = "SaveLog";
  static const subtitleFontSize = "SubtitleFontSize";
  static const subtitleFontWeight = "SubtitleFontWeight";
  static const subtitleFontColor = "SubtitleFontColor";
  static const subtitleBackgroundColor = "SubtitleBackgroundColor";
  static const subtitleBackgroundOpacity = "SubtitleBackgroundOpacity";
  static const subtitleTextAlign = "SubtitleTextAlign";
  static const subtitleLastLanguageSelected = "SubtitleLastLanguageSelected";
  static const subtitleLastTitleSelected = "SubtitleLastTitleSelected";
  // Ver ExtensionUtils._migrateNsfwHistoryFavorites — corre una sola vez.
  static const nsfw18RetroactiveMigrationDone =
      "Nsfw18RetroactiveMigrationDone";
}
