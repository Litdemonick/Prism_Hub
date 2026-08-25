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
import 'package:prismhub/utils/watch_state.dart';
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
  static const int _lastDatabaseVersion = 4;
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

  // Migraciones ENCADENADAS: se aplican una tras otra desde la versión
  // guardada hasta la actual. Antes era un switch que atendía una sola versión
  // por arranque, así que quien viniera de la v1 con dos saltos pendientes
  // quedaba a medio migrar.
  //
  // Y el `default: throw` de antes era peligroso: con una versión MAYOR a la
  // soportada —alguien que instala una versión nueva, guarda datos y vuelve a
  // una vieja— la excepción salía hasta el catch de Isar y la app arrancaba
  // con una BASE TEMPORAL, o sea sin su historial y sin decir por qué. Ante
  // datos más nuevos de lo que este app entiende, lo correcto es no tocar
  // nada.
  static performMigrationIfNeeded() async {
    var version = await getDatabaseVersion();
    if (version > _lastDatabaseVersion) {
      logger.warning(
        'La base es de una versión más nueva ($version) que la que entiende '
        'este app ($_lastDatabaseVersion). No se migra nada.',
      );
      return;
    }
    if (version < 1) version = 1;

    if (version == 1) {
      await migrateV1ToV2();
      version = 2;
    }
    if (version == 2) {
      await _migrateV2ToV3();
      version = 3;
    }
    if (version == 3) {
      await _migrateV3ToV4();
      version = 4;
    }

    await settings.put(SettingKey.databaseVersion, version);
  }

  // v3 → v4: repara los "completado" que nunca debieron marcarse.
  //
  // Hasta la 1.0.11, `watchState` se decidía solo por la posición en la lista
  // (`index >= playList.length - 1`), y como el historial se escribe apenas
  // ARRANCA la reproducción, abrir el último episodio bastaba para marcarlo
  // al día. Una película, que tiene un solo episodio, quedaba completada en el
  // segundo uno y nunca aparecía en "Continuar viendo". Ver
  // calcularWatchState en utils/watch_state.dart.
  //
  // Acá se recalcula con la regla nueva, pero SOLO donde se puede demostrar
  // que el usuario no había terminado: hace falta saber cuántos capítulos
  // había (knownEpisodeCount) y cuánto duraba (totalProgress). Sin esos datos
  // no se toca nada — un registro viejo sin ellos se deja como está, porque
  // "revivir" a Continuar todo el historial de alguien sería mucho peor que
  // dejar algún completado de más.
  //
  // Nunca marca completado algo que estaba pendiente: solo va en la dirección
  // segura.
  static Future<void> _migrateV3ToV4() async {
    try {
      final completados = await database.historys
          .filter()
          .watchStateEqualTo(WatchState.completed)
          .findAll();
      final aReparar = completados.where((h) {
        if (h.knownEpisodeCount <= 0) return false;
        final total = num.tryParse(h.totalProgress) ?? 0;
        if (total <= 0) return false;
        return calcularWatchState(
              index: h.episodeId,
              total: h.knownEpisodeCount,
              progreso: num.tryParse(h.progress) ?? 0,
              progresoTotal: total,
            ) ==
            WatchState.pending;
      }).toList();
      if (aReparar.isEmpty) return;
      await database.writeTxn(() async {
        for (final h in aReparar) {
          h.watchState = WatchState.pending;
          await database.historys.put(h);
        }
      });
      logger.info(
        'Migración v3→v4: ${aReparar.length} registros volvieron a "en curso" '
        '(estaban marcados al día sin haberse terminado).',
      );
    } catch (e, st) {
      // Que falle la reparación no puede impedir que la app arranque: el dato
      // sigue ahí, solo queda sin corregir.
      logger.warning('No se pudo reparar el estado del historial: $e\n$st');
    }
  }

  // v2 → v3: campos de seguimiento en History (watchState, seriesFinished,
  // knownEpisodeCount, newEpisodeLabel, lastCheckedAt).
  //
  // No recorre ni reescribe nada, y es a propósito: Isar completa los campos
  // nuevos con su valor por defecto al leer un registro viejo, así que todo el
  // historial existente queda como `pending` sin novedades — que es justo lo
  // que corresponde. Tocar miles de registros para escribir el mismo valor que
  // ya se obtiene solo sería trabajo y riesgo de más.
  static Future<void> _migrateV2ToV3() async {}

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
    await _initSetting(SettingKey.mangaStripAlign, 'centro');
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
    await _initSetting(SettingKey.modoClaro, false);
    await _initSetting(SettingKey.checkNewEpisodes, true);
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
  // Paquetes del catalogo ya vistos, para poder marcar cuales son NUEVOS. El
  // indice del repositorio no trae fecha de publicacion, asi que "nueva" no se
  // puede deducir de los datos: se calcula contra lo que este dispositivo ya
  // habia visto.
  static const seenRepoPackages = "SeenRepoPackages";
  static const tmdbKey = 'TMDBKey';
  static const autoCheckUpdate = 'AutoCheckUpdate';
  static const language = 'Language';
  static const novelFontSize = 'NovelFontSize';
  // Dónde se pega la franja del manhwa cuando sobra ancho: 'izquierda',
  // 'centro' (de fábrica, como venía siendo) o 'derecha'. Va como preferencia
  // global y no por obra a propósito: depende de con qué mano se sostiene el
  // teléfono o de dónde está la ventana, no del título que se lee.
  static const mangaStripAlign = 'MangaStripAlign';
  static const enableNSFW = 'EnableNSFW';
  // Las últimas búsquedas escritas en el buscador de TV, para no tener que
  // volver a escribirlas letra por letra con el mando. Ver
  // busquedas_recientes.dart.
  static const busquedasRecientesTv = 'BusquedasRecientesTv';
  // Versión en la que el usuario aceptó el aviso de beta. Vacío = todavía no
  // lo aceptó, así que el aviso vuelve a salir en el próximo arranque.
  static const betaNoticeAccepted = 'BetaNoticeAccepted';
  // Paquetes +18 que el app desactivó SOLO al apagar el switch de NSFW, para
  // poder devolverlos a como estaban cuando se vuelva a encender.
  static const nsfw18AutoDisabled = 'Nsfw18AutoDisabled';
  // Comprobar si salieron capítulos/episodios nuevos de lo que ya terminaste.
  // Hace red por obra, así que se puede apagar.
  static const checkNewEpisodes = 'CheckNewEpisodes';
  // Cuándo el usuario declaró ser mayor de edad al activar el +18. Se guarda
  // la fecha de la DECLARACIÓN, no la de nacimiento: para el app alcanza con
  // saber que declaró y cuándo, y el otro dato es personal y no hace falta.
  static const adultDeclaredAt = 'AdultDeclaredAt';
  static const videoPlayer = 'VideoPlayer';
  static const databaseVersion = 'DatabaseVersion';
  static const listMode = 'ListMode';
  static const keyI = 'KeyI';
  static const keyJ = 'KeyJ';
  static const arrowLeft = 'Arrowleft';
  static const arrowRight = 'Arrowright';
  /// Si ya se mostro el tutorial de gestos del reproductor.
  static const tutorialReproductorVisto = 'TutorialReproductorVisto';

  /// Arrancar siempre en la maxima calidad disponible.
  ///
  /// Apagado, el reproductor empieza alrededor de 1080p: es lo que cualquier
  /// equipo de los ultimos años mueve sin problemas, y arrancar en 4K en uno
  /// que no lo aguanta se siente como que el reproductor va mal. No es un
  /// tope: el menu de calidades sigue ofreciendo todo, 4K incluido.
  static const empezarEnMaximaCalidad = 'EmpezarEnMaximaCalidad';

  /// Al terminar un episodio, pasar solo al siguiente.
  ///
  /// Vale igual mirando aca que transmitiendo a un televisor. Apagado deja el
  /// episodio terminado y no toca nada, que es lo que quiere quien mira de a
  /// uno o se queda dormido con el reproductor abierto.
  static const autoPlayNext = 'AutoPlayNext';

  /// Cuántas copias de seguridad se hicieron desde este equipo.
  ///
  /// Va en el archivo para poder decir cuál es: "copia n.º 3". Sin eso, con
  /// tres archivos guardados en la misma carpeta no hay forma de saber cuál es
  /// el último sin abrirlos uno por uno.
  static const copiasHechas = 'CopiasHechas';

  /// Con qué nombre se guardó la última copia, para proponerlo de nuevo.
  static const nombreDeCopia = 'NombreDeCopia';
  static const readingMode = 'ReadingMode';
  static const aniListToken = 'AniListToken';
  static const aniListUserId = 'AniListUserId';
  static const autoTracking = 'AutoTracking';

  /// Modo claro encendido. Por defecto apagado: la app nació oscura y así la
  /// vio siempre todo el mundo; el claro es una elección, no el arranque.
  static const modoClaro = 'ModoClaro';
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
