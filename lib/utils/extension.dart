import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/controllers/settings_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/extension_signature.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/router/router.dart' show router;
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:path/path.dart' as path;

class ExtensionUtils {
  static Map<String, ExtensionService> runtimes = {};
  static Map<String, String> extensionErrorMap = {};

  // Runtime failures: the extension loaded fine but failed when used (site down,
  // extraction failed, etc.). Surfaced in the UI so the user sees a source is
  // currently not working.
  static Map<String, String> runtimeErrors = {};

  static void reportRuntimeError(String package, String reason) {
    if (package.isEmpty) return;
    runtimeErrors[package] = reason;
    _safeReloadPage();
  }

  static void clearRuntimeError(String package) {
    if (runtimeErrors.remove(package) != null) _safeReloadPage();
  }

  // True if this extension is currently failing (loaded but unusable).
  static bool isFailing(String package) => runtimeErrors.containsKey(package);

  // Caché de versiones publicadas en el índice del repo (package -> version),
  // usada para bloquear el uso de una extensión desactualizada (ver
  // ExtensionTile). TTL corto: evita golpear el repo en cada tile, pero no
  // deja quedar una versión vieja cacheada por toda la sesión.
  static Map<String, String>? _remoteVersionsCache;
  // Packages que el índice remoto marca `unstable` (string "true" en el
  // manifest, igual convención que nsfw) — se llena en el MISMO fetch que
  // _remoteVersionsCache, sin pedir el índice dos veces. Ver hasExtensionUpdate.
  static Map<String, bool>? _remoteUnstableCache;
  // Motivo por el que el índice la marcó inestable — lo setea solo el chequeo
  // de salud de prism-plus (scripts/health-check.mjs) o se pone a mano al
  // subir un arreglo en curso. Valores conocidos: 'site-down' (la página está
  // caída), 'broken' (responde pero no entrega contenido), 'outdated'
  // (necesita actualizarse). Un valor desconocido o ausente cae al aviso
  // genérico de siempre, así que un índice más nuevo nunca rompe un app viejo.
  static Map<String, String>? _remoteUnstableReasonCache;
  static List<dynamic>? _repoIndexCache;
  static DateTime? _repoIndexFetchedAt;
  static Future<List<dynamic>>? _repoIndexInFlight;
  static const _repoIndexTtl = Duration(minutes: 2);
  static StreamSubscription<FileSystemEvent>? _extensionDirWatcher;
  // Dedup de llamadas EN VUELO — el cache de arriba solo evita refetches
  // una vez que YA hay un resultado completo, pero con N extensiones
  // instaladas, sus ExtensionTile montan en el mismo frame y todas llaman
  // hasExtensionUpdate() antes de que la primera termine: sin esto, cada
  // una disparaba su PROPIO dio.get(index.json) en paralelo (confirmado en
  // vivo: 8 pedidos idénticos en menos de 1s con 8 extensiones instaladas).
  static Future<Map<String, String>>? _remoteVersionsInFlight;

  // Invalida el cache de versiones remotas para forzar una consulta fresca.
  // Lo usa el "deslizar para actualizar" de Extensiones instaladas: sin
  // esto, una extensión recién actualizada seguía apareciendo como
  // "actualización requerida" hasta que venciera el TTL de 10 minutos o se
  // reiniciara la app (reportado en vivo con Olympus).
  static void clearRemoteVersionsCache() {
    _remoteVersionsCache = null;
    _remoteUnstableCache = null;
    _repoIndexCache = null;
    _repoIndexFetchedAt = null;
  }

  static Future<Map<String, String>> _fetchRemoteVersions() async {
    final inFlight = _remoteVersionsInFlight;
    if (inFlight != null) return inFlight;
    final future = _doFetchRemoteVersions();
    _remoteVersionsInFlight = future;
    try {
      return await future;
    } finally {
      _remoteVersionsInFlight = null;
    }
  }

  // Sin TTL propio a propósito — antes tenía uno independiente de 10
  // minutos, separado del TTL de 2 minutos de fetchRepoIndex(). Esto
  // desincronizaba Instaladas vs Repositorio: refrescar el catálogo desde
  // una de las dos páginas no se reflejaba en la otra hasta que venciera
  // por separado (confirmado: "actualización requerida" tardaba hasta 10
  // min en aparecer aunque el repositorio ya mostrara la versión nueva).
  // Ahora reusa el MISMO caché/TTL de fetchRepoIndex, así que ambas
  // pantallas siempre están mirando el mismo índice.
  static Future<Map<String, String>> _doFetchRemoteVersions() async {
    final cached = _remoteVersionsCache;
    try {
      final list = await fetchRepoIndex();
      final map = <String, String>{};
      final unstableMap = <String, bool>{};
      final reasonMap = <String, String>{};
      for (final e in list) {
        final pkg = e['package'] as String?;
        final ver = e['version'] as String?;
        if (pkg != null && ver != null) map[pkg] = ver;
        if (pkg != null) {
          unstableMap[pkg] = e['unstable'] == 'true' || e['unstable'] == true;
          final reason = e['unstableReason'];
          if (reason is String && reason.isNotEmpty) reasonMap[pkg] = reason;
        }
      }
      _remoteVersionsCache = map;
      _remoteUnstableCache = unstableMap;
      _remoteUnstableReasonCache = reasonMap;
      return map;
    } catch (e) {
      // Sin conexión / repo caído: no bloquear extensiones por no poder
      // chequear — devolver la última caché conocida (o vacío).
      return cached ?? {};
    }
  }

  static Future<List<dynamic>> fetchRepoIndex({
    bool forceRefresh = false,
    bool cacheBust = false,
  }) async {
    final cached = _repoIndexCache;
    final fetchedAt = _repoIndexFetchedAt;
    if (!forceRefresh &&
        cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _repoIndexTtl) {
      return cached;
    }
    final inFlight = _repoIndexInFlight;
    if (inFlight != null) return inFlight;

    final future = _doFetchRepoIndex(cacheBust: cacheBust || forceRefresh);
    _repoIndexInFlight = future;
    try {
      return await future;
    } finally {
      _repoIndexInFlight = null;
    }
  }

  static Future<List<dynamic>> _doFetchRepoIndex({
    required bool cacheBust,
  }) async {
    // Con el ajuste en null esto construía "null/index.json" y dio fallaba
    // con "No host specified in URI" — que en pantalla se ve igual que estar
    // sin internet, así que el síntoma no tenía nada que ver con la causa.
    final savedRepoUrl = PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl);
    final repoUrl = savedRepoUrl is String && savedRepoUrl.isNotEmpty
        ? savedRepoUrl
        : PrismHubStorage.defaultRepoUrl;
    final bust = DateTime.now().millisecondsSinceEpoch;
    final url =
        cacheBust ? '$repoUrl/index.json?t=$bust' : '$repoUrl/index.json';
    final res = await dio.get<String>(
      url,
      options: Options(receiveTimeout: const Duration(seconds: 20)),
    );
    // El índice es contenido EXTERNO: viene de un repo público que el usuario
    // puede incluso cambiar por otro en Ajustes. No se asume nada de su forma.
    // Antes, `res.data!` reventaba con una respuesta vacía, y
    // List.from() con un `extensions` que no fuera lista (ej. un número o un
    // objeto) tiraba una excepción que salía de acá — y este método lo llaman
    // varias pantallas sin try, así que un índice roto o manipulado podía
    // dejar el catálogo inusable en vez de simplemente vacío.
    final body = res.data;
    if (body == null || body.isEmpty) return const [];
    final dynamic decoded;
    try {
      decoded = await compute(jsonDecode, body);
    } catch (e) {
      logger.warning('index.json no es JSON válido: $e');
      return const [];
    }
    final list = decoded is Map ? (decoded['extensions'] ?? const []) : decoded;
    if (list is! Iterable) {
      logger.warning('index.json: "extensions" no es una lista');
      return const [];
    }
    final normalized = List<dynamic>.from(list);
    // Contrato app <-> repo. El índice ya publicaba `protocolVersion` desde
    // siempre, pero el app nunca lo miraba: hoy funciona porque nada rompió el
    // contrato todavía, y el día que se rompa habría fallado de forma confusa
    // (extensiones que se instalan y se comportan raro) en vez de decirlo. Esto
    // es lo que hace SEGURO publicar extensiones sin actualizar el app.
    _repoProtocolVersion =
        decoded is Map ? _parseProtocolVersion(decoded['protocolVersion']) : 1;
    _rememberOfficialCatalogEntries(normalized);
    _repoIndexCache = normalized;
    _repoIndexFetchedAt = DateTime.now();
    return normalized;
  }

  // El repo lo escribe como string ("1"), pero se acepta número por si cambia.
  // Si no se entiende, se asume la versión soportada: un índice raro no debería
  // dejar al usuario sin extensiones.
  static int _parseProtocolVersion(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? supportedProtocolVersion;
    return supportedProtocolVersion;
  }

  // Máxima versión del contrato que este app entiende. Se sube a mano cuando se
  // agregue algo al contrato (un tipo de filtro nuevo, un campo nuevo que el
  // app tenga que interpretar), junto con el `protocolVersion` de prism-plus.
  static const int supportedProtocolVersion = 1;
  static int? _repoProtocolVersion;

  // true cuando el repo habla un contrato más nuevo que este app. En ese caso
  // no se rompe nada ni se bloquea el catálogo entero: las extensiones que ya
  // andan siguen andando, pero quien muestre el repositorio puede avisar que
  // conviene actualizar PrismHub para tener todo.
  static bool get repoNeedsNewerApp =>
      (_repoProtocolVersion ?? supportedProtocolVersion) >
      supportedProtocolVersion;

  // Una extensión puede declarar `minProtocol` en su manifest si usa algo que
  // solo entiende un app más nuevo. Se chequea antes de instalar, para decirlo
  // claro en vez de instalarla y que falle raro después.
  static bool entryNeedsNewerApp(Map entry) {
    final raw = entry['minProtocol'];
    final min = raw == null ? 1 : _parseProtocolVersion(raw);
    return min > supportedProtocolVersion;
  }

  static void _rememberOfficialCatalogEntries(List<dynamic> list) {
    for (final e in list) {
      if (e is! Map) continue;
      final pkg = e['package']?.toString();
      if (pkg != null && pkg.isNotEmpty) officialPackages.add(pkg);
      final officialName = e['name']?.toString().toLowerCase().trim();
      if (officialName != null && officialName.isNotEmpty) {
        officialNames.add(officialName);
      }
    }
  }

  // True si el package instalado tiene una versión más nueva en el índice
  // remoto del repo, O si el catálogo remoto la marca `unstable` (ver
  // build.mjs/disabled-extensions) — reutiliza el mismo badge/diálogo
  // bloqueante de "actualización requerida" para una extensión que quedó
  // rota y en espera de que se arregle, sin necesitar UI nueva. Comparación
  // de versión por desigualdad de string (igual que ExtensionCard en el
  // repositorio) — no hay parsing semver hoy.
  /// SOLO compara versiones. Antes devolvía true también cuando el catálogo
  /// marcaba la extensión `unstable`, y eso mezclaba dos cosas que se arreglan
  /// distinto:
  ///
  /// - versión nueva → se soluciona actualizando;
  /// - inestable → NO se soluciona actualizando, porque el problema está del
  ///   otro lado (la página caída, la extensión sin entregar contenido).
  ///
  /// Mezcladas, una extensión marcada inestable con la versión YA al día
  /// mostraba "Actualización requerida" para siempre: al tocar Actualizar se
  /// reinstalaba lo mismo, el motivo real seguía ahí y el botón no se iba
  /// nunca. Pasó en vivo con ShadeManga, TuMangaOnline y VeoHentai, marcadas
  /// por un falso positivo del chequeo de salud.
  ///
  /// El estado inestable se muestra aparte, con su propio aviso y su motivo
  /// (ver [isRemoteUnstable] y [remoteUnstableReason]).
  static Future<bool> hasExtensionUpdate(String package) async {
    final installed = runtimes[package]?.extension.version;
    if (installed == null) return false;
    final remote = await _fetchRemoteVersions();
    final remoteVersion = remote[package];
    return remoteVersion != null && remoteVersion != installed;
  }

  // Igual que hasExtensionUpdate pero devuelve SOLO el motivo "inestable"
  // (no versión) — usado para el badge naranja "Inestable" en ExtensionTile,
  // separado del badge rojo genérico de "actualización requerida". Comparte
  // el mismo caché/TTL, no pega de nuevo al índice.
  /// Igual que [isRemoteUnstable] pero SIN esperar: usa lo que ya haya en
  /// caché. Sirve para filtrar una lista mientras se construye, donde no se
  /// puede await. Si el índice todavía no se descargó devuelve false, y el
  /// filtro se corrige solo en cuanto llega (la página se reconstruye).
  static bool isRemoteUnstableCached(String package) =>
      _remoteUnstableCache?[package] == true;

  static Future<bool> isRemoteUnstable(String package) async {
    await _fetchRemoteVersions();
    return _remoteUnstableCache?[package] == true;
  }

  // Motivo del "inestable" tal como lo publica el índice, o null si no vino
  // ninguno. Comparte el caché de arriba, no pega de nuevo al índice.
  static Future<String?> remoteUnstableReason(String package) async {
    await _fetchRemoteVersions();
    if (_remoteUnstableCache?[package] != true) return null;
    return _remoteUnstableReasonCache?[package];
  }

  // Texto para mostrarle al usuario según el motivo. Un motivo desconocido
  // (índice más nuevo que este app) cae al genérico en vez de mostrar la clave
  // cruda o quedar en blanco.
  static String unstableReasonLabel(String? reason) {
    switch (reason) {
      case 'site-down':
        return 'extension.unstable-site-down'.i18n;
      case 'broken':
        return 'extension.unstable-broken'.i18n;
      case 'outdated':
        return 'extension.unstable-outdated'.i18n;
      default:
        return 'extension.unstable-generic'.i18n;
    }
  }

  // Chequeo compartido de "esta extensión necesita actualizarse" antes de
  // dejar entrar a su contenido — antes este aviso solo vivía en
  // ExtensionTile (Instaladas) y en ExtensionSearcherPage (buscar dentro de
  // una extensión), cada uno con su propia copia del diálogo. Tocar una
  // card desde Home, Zona +18, Favoritos (standalone o dentro de
  // Historial) o la búsqueda general no pasaba por NINGÚN chequeo y
  // entraba directo aunque la extensión estuviera desactualizada.
  // Devuelve true si BLOQUEÓ (ya mostró el aviso, no hay que seguir),
  // false si está todo bien y se puede continuar.
  static Future<bool> blockedByPendingUpdate(
    BuildContext context,
    String package,
  ) async {
    // 1. No instalada / 2. desactivada — se chequean ANTES que la versión,
    // porque en esos casos no tiene sentido hablar de actualizar. Antes esto
    // no estaba acá: tocar una card de una extensión desactivada ABRÍA
    // DetailPage y recién adentro fallaba (detail_controller deja el runtime
    // en null y tira 'common.extension-disabled'), así que el usuario veía la
    // pantalla abrirse y romperse en vez de un aviso claro. Ahora se corta
    // antes de entrar, y como todos los caminos a contenido pasan por esta
    // función, vale igual desde Home, Zona +18, Historial, Favoritos, la
    // búsqueda, "Continuar" y "Ver detalle" del reproductor.
    final installed = runtimes[package];
    if (installed == null) {
      if (!context.mounted) return true;
      showPlatformSnackbar(
        context: context,
        content: FlutterI18n.translate(
          context,
          'common.extension-missing',
          translationParams: {'package': package},
        ),
        severity: InfoBarSeverity.error,
      );
      return true;
    }
    if (!isEnabled(package)) {
      if (!context.mounted) return true;
      await _showDisabledDialog(context, package);
      return true;
    }

    // 3. Inestable o desactualizada. Se consultan por SEPARADO: desde que
    // hasExtensionUpdate mira solo la versión, el estado inestable hay que
    // pedirlo aparte o una extensión marcada rota dejaría de avisar acá. Las
    // dos siguen bloqueando el contenido, pero el aviso que se muestra —y si
    // se ofrece actualizar— depende de cuál sea.
    final needsUpdate = await hasExtensionUpdate(package);
    if (!context.mounted) return true;
    final reason = await remoteUnstableReason(package);
    if (!context.mounted) return true;
    final isUnstable = reason != null || await isRemoteUnstable(package);
    if (!context.mounted) return true;

    if (!needsUpdate && !isUnstable) return false;

    // Actualizar solo se ofrece cuando de verdad puede arreglar algo: si la
    // página está caída o la extensión está rota esperando corrección,
    // reinstalar la misma versión no cambia nada, así que se ofrece solo
    // cerrar en vez de prometer un arreglo que no va a pasar.
    final canFixByUpdating = !isUnstable || reason == 'outdated';

    final update = await showPlatformDialog(
      context: context,
      title: isUnstable
          ? 'extension.unstable-title'.i18n
          : 'extension.update-required'.i18n,
      content: Text(
        isUnstable
            ? unstableReasonLabel(reason)
            : 'extension.update-required-dialog'.i18n,
      ),
      actions: [
        if (canFixByUpdating)
          PlatformTextButton(
            onPressed: () => RouterUtils.pop(false),
            child: Text('common.cancel'.i18n),
          ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(canFixByUpdating),
          child: Text(
            canFixByUpdating
                ? 'extension.update-now'.i18n
                : 'common.understood'.i18n,
          ),
        ),
      ],
    );
    if (update != true || !context.mounted) return true;
    // El botón actualiza ACÁ MISMO en vez de navegar al repositorio. Antes
    // hacía `router.push('/extension_repo')`, que en Android no hace nada
    // (router es go_router, solo se usa en escritorio; en Android el
    // repositorio es una pestaña del shell y además el usuario suele estar
    // YA en la pantalla de extensiones cuando toca esto) — reportado en
    // vivo: "ir a actualizar... pero ya estoy ahí, no hace nada".
    try {
      await updateInstalledFromRepo(package, context);
    } catch (e) {
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          content: friendlyError(e),
          severity: InfoBarSeverity.error,
        );
      }
    }
    return true;
  }

  // Aviso de "extensión desactivada" con acción para ir a activarla. La
  // navegación se ramifica por plataforma porque en Android Extensiones es una
  // pestaña del shell principal (router/go_router solo se usa en escritorio) —
  // mismo criterio que el botón "Ir a Ajustes" de la Zona +18.
  static Future<void> _showDisabledDialog(
    BuildContext context,
    String package,
  ) async {
    final go = await showPlatformDialog(
      context: context,
      title: 'extension.disabled-title'.i18n,
      content: Text('extension.disabled-dialog'.i18n),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('extension.go-to-installed'.i18n),
        ),
      ],
    );
    if (go != true) return;
    if (Platform.isAndroid) {
      Get.find<MainController>().changeTab(2);
      return;
    }
    router.go('/extension');
  }

  // Navegación compartida a DetailPage — antes duplicada (con pequeñas
  // variaciones de copy/paste) en ExtensionItemCard, home_page.dart,
  // nsfw18_zone_page.dart y history_page.dart, ninguna con chequeo de
  // actualización. Ahora todas pasan por acá: si hace falta actualizar,
  // corta con el aviso de blockedByPendingUpdate en vez de entrar.
  static Future<void> openExtensionDetail(
    BuildContext context, {
    required String package,
    required String url,
    bool isAdultOption = false,
  }) async {
    if (await blockedByPendingUpdate(context, package)) return;
    if (!context.mounted) return;
    if (Platform.isAndroid) {
      Get.to(DetailPage(
        key: ValueKey('$package|$url'),
        url: url,
        package: package,
        tag: '$package|$url',
        isAdultOption: isAdultOption,
      ));
      return;
    }
    router.push(
      Uri(
        path: '/detail',
        queryParameters: {
          'url': url,
          'package': package,
          if (isAdultOption) 'adult': '1',
        },
      ).toString(),
    );
  }

  // Actualiza una extensión YA instalada bajando la versión del catálogo
  // remoto y reinstalándola — usado por el botón "Actualizar" de
  // ExtensionTile (Extensiones instaladas), para no obligar a navegar al
  // repositorio solo para eso. Misma verificación de firma que ExtensionCard.
  static Future<void> updateInstalledFromRepo(
    String package,
    BuildContext context,
  ) async {
    final bust = DateTime.now().millisecondsSinceEpoch;
    final smallFetch = Options(receiveTimeout: const Duration(seconds: 20));
    final list = await fetchRepoIndex(forceRefresh: true);
    final entry = list.cast<Map>().firstWhere(
          (e) => e['package'] == package,
          orElse: () => {},
        );
    final scriptUrl = (entry['script'] ?? entry['url'])?.toString();
    if (scriptUrl == null) throw Exception('extension.invalid'.i18n);
    final sep = scriptUrl.contains('?') ? '&' : '?';
    final js =
        await dio.get<String>('$scriptUrl${sep}t=$bust', options: smallFetch);
    if (js.data == null || js.data!.isEmpty) {
      throw Exception('extension.invalid'.i18n);
    }
    final signature = entry['signature']?.toString();
    var officialVerified = false;
    if (signature != null && signature.isNotEmpty) {
      if (!ExtensionSignature.isOfficial(js.data!, signature)) {
        throw Exception('extension.invalid-signature'.i18n);
      }
      officialVerified = true;
    }
    // ignore: use_build_context_synchronously
    await installByScript(js.data!, context,
        officialVerified: officialVerified);
  }

  static String get extensionsDir => path.join(
        PrismHubDirectory.getDirectory,
        'extensions',
      );

  // 已禁用的扩展 (enable/disable). Disabled extensions stay installed but are
  // excluded from search/discovery.
  static List<String> get disabledExtensions =>
      ((PrismHubStorage.getSetting(SettingKey.disabledExtensions) as List?)
          ?.cast<String>()) ??
      <String>[];

  static bool isEnabled(String package) =>
      !disabledExtensions.contains(package);

  // Único punto de verdad para "¿se puede ver esta extensión NSFW fuera de
  // la Zona +18?" — antes esta misma condición estaba reimplementada por
  // separado en home_controller, search_controller y
  // extension_repo_controller, cada una con matices ligeramente distintos.
  static bool isNsfwVisibleOutsideZone(bool extensionIsNsfw) =>
      !extensionIsNsfw || PrismHubStorage.getSetting(SettingKey.enableNSFW);

  // Join an extension's webSite with a possibly-relative url, guaranteeing
  // exactly one slash. Extensions are inconsistent: some return '/path', some
  // a bare slug ('foo-bar'), some an absolute URL. Naive `webSite + url`
  // produces broken hosts like 'https://site.comfoo-bar'.
  static String joinWebUrl(String webSite, String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = webSite.endsWith('/')
        ? webSite.substring(0, webSite.length - 1)
        : webSite;
    final path = url.startsWith('/') ? url : '/$url';
    return '$base$path';
  }

  static Future<void> setExtensionEnabled(String package, bool enabled) async {
    final list = disabledExtensions;
    if (enabled) {
      list.remove(package);
    } else if (!list.contains(package)) {
      list.add(package);
    }
    await PrismHubStorage.setSetting(SettingKey.disabledExtensions, list);
    _reloadPage();
  }

  // Only enabled runtimes — used for search/discovery so disabled sources hide.
  static Map<String, ExtensionService> get enabledRuntimes =>
      Map.fromEntries(runtimes.entries.where((e) => isEnabled(e.key)));

  // Extensiones que se auto-instalan en el primer launch.
  // Solo las publicadas en prism+ index.json; añadir aquí solo cuando ya
  // exista la entrada firmada en el catálogo.
  static const Set<String> defaultPackages = {
    'io.prismhub.jkanime', // anime ES — múltiples servidores confiables
    // Las demás extensiones oficiales (manhwaweb, shademanga, etc.) ya NO se
    // auto-instalan: el usuario debe instalarlas y activarlas a mano desde
    // el repositorio (varias tienen contenido +18, ver nsfw gating en
    // ExtensionCard/ExtensionTile).
  };

  // Todos los paquetes oficiales de prism+. Bloqueados de instalar externamente
  // si colisionan con el nombre — se prefiere siempre la build oficial.
  static const Set<String> nativePackages = {
    ...defaultPackages,
    // Nuevas extensiones se agregan aquí una vez publicadas y firmadas en prism+.
  };

  // Extensiones que se eliminaron del catálogo y deben borrarse del dispositivo
  // incluso sin conexión. Añadir aquí cualquier package que se retire de prism+.
  static const Set<String> _removedPackages = {
    'io.prismhub.mangadex', // retirado antes del release v1.0.0 — no firmado
  };

  // Catálogo oficial vivo: se llena desde el index.json de prism+ en cada
  // arranque. Permite bloquear el sideload de CUALQUIER extensión oficial
  // (por package o por nombre), no solo las 3 hardcodeadas, a medida que prism+
  // crece. Una oficial solo se instala por el canal firmado del catálogo.
  static final Set<String> officialPackages = {};
  static final Set<String> officialNames = {};

  static bool isNativePackage(String package) =>
      nativePackages.contains(package) || officialPackages.contains(package);

  // Único lugar con esta validación — antes solo corría dentro de
  // _saveAndInit (instalación vía UI/URL). installByPath() (usado al
  // arrancar y por el file watcher cuando aparece/cambia un .js en la
  // carpeta) tomaba ext.package sin este chequeo y lo usaba tal cual para
  // construir rutas de archivo (extension_service.dart, request.dart) — un
  // .js puesto ahí por cualquier vía que no sea el instalador (arrastrar y
  // soltar, carpeta sincronizada, ZIP extraído) con un @package
  // "../../../algo" evadía el traversal check.
  static final RegExp _validPackagePattern = RegExp(r'^[a-zA-Z0-9._-]+$');
  static bool isValidPackage(String pkg) =>
      pkg.isNotEmpty && _validPackagePattern.hasMatch(pkg);

  static final RegExp _versionHeader = RegExp(r'@version\s+([^\s\r\n]+)');

  static String? _scriptVersion(String script) =>
      _versionHeader.firstMatch(script)?.group(1)?.replaceFirst('v', '').trim();

  // Sync prism+ native default extensions from the repo on every launch:
  //  - first run: install the curated natives so they appear ready to use
  //  - later: re-download a native if the repo has a newer version (so fixes
  //    to resolvers/scrapers reach the app without reinstalling by hand)
  //  - respects user removals: a native the user deleted is not re-added
  // prism+ stays the single source of truth (no bundled copies). Offline-safe.
  static Future<void> _installDefaultsFromRepo() async {
    try {
      // Cache-bust: GitHub raw caches index.json/dist for minutes, which would
      // hide a freshly pushed extension/resolver fix.
      final bust = DateTime.now().millisecondsSinceEpoch;
      // receiveTimeout acá (no global en dio): esto es JSON/JS chico, así que
      // en una red restrictiva (universidad, etc.) preferimos fallar rápido
      // y reintentar en el próximo arranque, en vez de quedar colgados.
      final smallFetch = Options(receiveTimeout: const Duration(seconds: 20));
      final list = await fetchRepoIndex(forceRefresh: true);
      for (final e in list) {
        final pkg = e['package']?.toString();
        if (pkg == null) continue;
        // Registrar TODA extensión del catálogo oficial (no solo las default,
        // e incluso una marcada `unstable` sin script real todavía — ej.
        // LaMovie en disabled-extensions/) para bloquear sideloads que
        // dupliquen su nombre/package.
        officialPackages.add(pkg);
        final officialName = e['name']?.toString().toLowerCase().trim();
        if (officialName != null && officialName.isNotEmpty) {
          officialNames.add(officialName);
        }
        final scriptUrl = (e['script'] ?? e['url'])?.toString();
        // Solo los paquetes por defecto se auto-instalan en primer launch, y
        // solo si de verdad traen un bundle (una unstable sin script no se
        // auto-instala nunca). Los demás nativos están disponibles en el
        // catálogo del repo para instalar a mano.
        if (scriptUrl == null || !defaultPackages.contains(pkg)) continue;

        final dest = File(path.join(extensionsDir, '$pkg.js'));
        final exists = await dest.exists();
        // Los 3 defaults se garantizan siempre presentes: si falta uno (p.ej.
        // cambió el set de defaults tras el primer arranque), se instala. Así el
        // equipo siempre tiene exactamente las 3 oficiales por defecto.
        // Already installed: only re-download when the repo version is different.
        if (exists) {
          final repoVersion = e['version']?.toString().replaceFirst('v', '');
          final localVersion = _scriptVersion(await dest.readAsString());
          if (repoVersion == null || repoVersion == localVersion) continue;
        }
        final sep = scriptUrl.contains('?') ? '&' : '?';
        final js = await dio.get<String>('$scriptUrl${sep}t=$bust',
            options: smallFetch);
        if (js.data != null && js.data!.isNotEmpty) {
          // Seguridad: los defaults son oficiales y DEBEN traer firma válida de
          // prism+. Si falta o no valida, es manipulación → no se instala.
          final signature = e['signature']?.toString();
          if (!ExtensionSignature.isOfficial(js.data!, signature)) {
            debugPrint(
                'Firma inválida o ausente para $pkg — no se instala (posible manipulación).');
            continue;
          }
          await dest.writeAsString(js.data!);
        }
      }
      await PrismHubStorage.setSetting(
          SettingKey.defaultExtensionsInstalled, true);

      // Purga de oficiales huérfanas: una extensión del namespace oficial
      // `io.prismhub.*` que ya NO está en el catálogo de prism+ (la quitamos del
      // repo, p.ej. animeflv) se elimina del equipo. NO toca extensiones externas
      // de terceros (otro namespace) — prism_hub permite sideload. Solo corre si
      // el catálogo se descargó bien (officialPackages no vacío), para no borrar
      // nada estando offline.
      if (officialPackages.isNotEmpty) {
        await for (final f in Directory(extensionsDir).list()) {
          if (path.extension(f.path) != '.js') continue;
          final pkg = path.basenameWithoutExtension(f.path);
          if (pkg.startsWith('io.prismhub.') &&
              !officialPackages.contains(pkg) &&
              !nativePackages.contains(pkg)) {
            try {
              await File(f.path).delete();
              runtimes.remove(pkg);
              debugPrint('Extensión oficial huérfana eliminada: $pkg');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      // Offline / repo unreachable — keep working with what's installed and
      // retry next launch (the first-run flag stays unset until it succeeds).
      debugPrint('No se pudieron sincronizar las extensiones por defecto: $e');
    }
  }

  // 初始化扩展
  static ensureInitialized() async {
    // 创建目录
    Directory(extensionsDir).createSync(recursive: true);
    // Purga offline de paquetes retirados: se elimina el JS aunque no haya red,
    // así el usuario no ve extensiones obsoletas al abrir la app.
    await _purgeRemovedPackages();
    // Descarga defaults (I/O, no bloquea el isolate).
    await _installDefaultsFromRepo();
    // Limpia el Hive disabled-list de entradas muertas (paquetes sin JS).
    await _cleanStaleDisabledList();
    // 监听目录变化
    await _extensionDirWatcher?.cancel();
    _extensionDirWatcher =
        Directory(extensionsDir).watch().listen((event) async {
      if (path.extension(event.path) == '.js') {
        final package = path.basenameWithoutExtension(event.path);
        debugPrint('extension event: ${event.path} ${event.type}');
        switch (event.type) {
          case FileSystemEvent.delete:
            runtimes.remove(package);
            extensionErrorMap.remove(event.path);
            _safeReloadPage();
            break;
          case FileSystemEvent.create:
          case FileSystemEvent.modify:
            if (_loading.contains(package)) break;
            runtimes.remove(package);
            extensionErrorMap.remove(event.path);
            await installByPath(event.path);
            _safeReloadPage();
            break;
        }
      }
    });
    // Carga secuencial con yields: se espera a que terminen para que el
    // splash oculte la carga de extensiones (en vez de que jankeen la UI
    // después). El yield entre cada una permite que la animación del splash
    // se renderice sin congelarse 800ms seguidos.
    await _loadExtensions();
    // Recién ahora runtimes está poblado — necesario para saber qué
    // packages son nsfw:true.
    await _migrateNsfwHistoryFavorites();
  }

  // Ver DatabaseService.markNsfwByPackages: marca retroactivamente el
  // History/Favorite ya guardado de una extensión 100% nsfw SIN partición
  // segura/+18 (osea, TODO lo que devuelve es +18 — no hay filtro
  // adultOption que separe algo "normal" dentro de ella). Para una
  // extensión MIXTA (ShadeManga, ManhwaWeb: tienen contenido normal Y +18,
  // separados por un filtro con adultOption) no se puede migrar en bloque:
  // el History/Favorite guardado ANTES de este campo no registró si vino
  // de la sección +18 o de la normal, así que no hay forma de saber cuál
  // ítem viejo es cuál — se deja tal cual (sigue en Continuar/Favoritos
  // normal) en vez de arriesgarse a mover contenido normal a la Zona +18
  // por error. Solo lo NUEVO (a partir de esta versión) separa bien.
  // Corre una sola vez por instalación (flag en Hive).
  static Future<void> _migrateNsfwHistoryFavorites() async {
    if (PrismHubStorage.getSetting(SettingKey.nsfw18RetroactiveMigrationDone) ==
        true) {
      return;
    }
    try {
      final fullyAdultPackages = <String>{};
      for (final entry in runtimes.entries) {
        if (!entry.value.extension.nsfw) continue;
        var hasAdultPartition = false;
        try {
          final filters = await entry.value.createFilter();
          hasAdultPartition = filters.values.any((f) => f.adultOption != null);
        } catch (_) {
          // No se pudo determinar (createFilter falló) — más seguro asumir
          // que SÍ podría tener partición y no migrarla en bloque.
          hasAdultPartition = true;
        }
        if (!hasAdultPartition) fullyAdultPackages.add(entry.key);
      }
      await DatabaseService.markNsfwByPackages(fullyAdultPackages);
    } catch (e) {
      debugPrint('ERROR: migración retroactiva de NSFW falló: $e');
    }
    await PrismHubStorage.setSetting(
        SettingKey.nsfw18RetroactiveMigrationDone, true);
  }

  static _loadExtensions() async {
    final d = Directory(extensionsDir);
    if (!await d.exists()) return;
    final extensionsList =
        await d.list().where((e) => path.extension(e.path) == '.js').toList();
    extensionsList.sort((a, b) => a.path.compareTo(b.path));
    // Secuencial con yield entre cada una: Future.wait no acelera porque
    // initRuntime es CPU-bound (QuickJS) — bloquea el isolate entero.
    // El yield permite al UI renderizar frames entre extensiones.
    // Se salta archivos que no son .js (cachés, temporales, etc.).
    for (final e in extensionsList) {
      await installByPath(e.path);
      await _yieldToNextFrame();
    }
    _reloadPage();
  }

  static Future<void> _yieldToNextFrame() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }

  static uninstall(String package) async {
    final file = File(path.join(extensionsDir, '$package.js'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Borra sin necesidad de red los .js de paquetes retirados del catálogo.
  static Future<void> _purgeRemovedPackages() async {
    for (final pkg in _removedPackages) {
      try {
        final f = File(path.join(extensionsDir, '$pkg.js'));
        if (await f.exists()) {
          await f.delete();
          debugPrint('Paquete retirado eliminado del dispositivo: $pkg');
        }
      } catch (_) {}
    }
  }

  // Elimina del Hive disabled-list los package IDs que ya no tienen JS en disco,
  // evitando datos muertos que confundan el estado de la UI.
  static Future<void> _cleanStaleDisabledList() async {
    final raw = PrismHubStorage.getSetting(SettingKey.disabledExtensions);
    if (raw == null) return;
    final List<String> list = raw is List ? List<String>.from(raw) : <String>[];
    final existingPkgs = <String>{};
    await for (final e in Directory(extensionsDir).list()) {
      if (path.extension(e.path) == '.js') {
        existingPkgs.add(path.basenameWithoutExtension(e.path));
      }
    }
    final cleaned = list.where(existingPkgs.contains).toList();
    if (cleaned.length != list.length) {
      PrismHubStorage.setSetting(SettingKey.disabledExtensions, cleaned);
    }
  }

  // True if an external extension collides with a native/official prism+ one
  // (by package id or by name) — those are blocked from external/sideload
  // install. Una oficial solo entra por el canal firmado del catálogo.
  static bool isDuplicateOfNative(Extension ext) {
    if (isNativePackage(ext.package)) return true;
    final name = ext.name.toLowerCase().trim();
    if (name.isEmpty) return false;
    // Mismo nombre que una oficial del catálogo de prism+.
    if (officialNames.contains(name)) return true;
    return runtimes.values.any((r) =>
        isNativePackage(r.extension.package) &&
        r.extension.name.toLowerCase().trim() == name);
  }

  static Future<void> _saveAndInit(
    String script,
    BuildContext context, {
    bool safeReload = false,
    bool officialVerified = false,
  }) async {
    // Parse defensively: a .js without a valid @package header otherwise throws
    // an ugly "Null is not a subtype of String" instead of a clean notice.
    Extension ext;
    try {
      ext = ExtensionUtils.parseExtension(script);
    } catch (_) {
      throw Exception('extension.invalid'.i18n);
    }
    // Validate: reject garbage so a malformed paste can't write junk files,
    // and reject unsafe package ids (path traversal) so a malicious extension
    // can't escape the extensions directory.
    final pkg = ext.package.trim();
    if (!isValidPackage(pkg)) {
      throw Exception('extension.invalid'.i18n);
    }
    // Black-box filter: an extension already shipped natively by prism+ must
    // not be installed externally — the native build is preferred. La instalación
    // oficial firmada (officialVerified) sí pasa: es la legítima del catálogo.
    if (!officialVerified && isDuplicateOfNative(ext)) {
      throw Exception('extension.already-native'.i18n);
    }
    final savePath = path.join(extensionsDir, '$pkg.js');
    _loading.add(pkg);
    await File(savePath).writeAsString(script);
    try {
      runtimes[pkg] = await ExtensionService().initRuntime(ext);
    } catch (e) {
      // Init failed — remove the bad runtime and file so it doesn't persist
      // and break loading on the next launch.
      runtimes.remove(pkg);
      try {
        await File(savePath).delete();
      } catch (_) {}
      rethrow;
    } finally {
      _loading.remove(pkg);
    }
    safeReload ? _safeReloadPage() : _reloadPage();
  }

  static void _showInstallError(BuildContext context, Object e) {
    if (!context.mounted) return;
    showPlatformDialog(
      context: context,
      title: 'extension-install-error'.i18n,
      content: Text(e.toString()),
      actions: [
        PlatformButton(
          onPressed: RouterUtils.pop,
          child: Text('common.close'.i18n),
        )
      ],
    );
  }

  static install(String url, BuildContext context) async {
    try {
      final res = await dio.get<String>(url);
      if (res.data == null) throw Exception("Does not seem to be an extension");
      // ignore: use_build_context_synchronously
      await _saveAndInit(res.data!, context, safeReload: true);
    } catch (e) {
      // ignore: use_build_context_synchronously
      _showInstallError(context, e);
      rethrow;
    }
  }

  // officialVerified=true cuando la firma oficial del catálogo ya fue validada
  // (extension_card): en ese caso se permite instalar la oficial aunque coincida
  // con una nativa — ES la oficial. El sideload externo nunca pasa este flag.
  static installByScript(String script, BuildContext context,
      {bool officialVerified = false}) async {
    try {
      await _saveAndInit(script, context, officialVerified: officialVerified);
    } catch (e) {
      // ignore: use_build_context_synchronously
      _showInstallError(context, e);
      rethrow;
    }
  }

  static final Set<String> _loading = {};

  static installByPath(String p) async {
    if (path.extension(p) == '.js') {
      try {
        final file = File(p);
        final content = await file.readAsString();
        final ext = ExtensionUtils.parseExtension(content);
        // Mismo chequeo que _saveAndInit — acá el .js pudo llegar por
        // cualquier vía (arrastrar y soltar, carpeta sincronizada, ZIP
        // extraído), no solo por el instalador de la app.
        if (!isValidPackage(ext.package.trim())) return;
        // Skip if already loaded with same version (prevents Isar unique index violation
        // when file watcher fires multiple events during install)
        if (runtimes.containsKey(ext.package) &&
            runtimes[ext.package]!.extension.version == ext.version) {
          return;
        }
        // Prevent concurrent loads of the same package
        if (_loading.contains(ext.package)) return;
        _loading.add(ext.package);
        try {
          runtimes[ext.package] = await ExtensionService().initRuntime(ext);
        } finally {
          _loading.remove(ext.package);
        }
      } catch (e) {
        extensionErrorMap[p] = e.toString();
      }
    }
  }

  static _safeReloadPage() {
    try {
      _reloadPage();
    } catch (_) {}
  }

  static _reloadPage() {
    // 重载扩展页面
    if (Get.isRegistered<ExtensionPageController>()) {
      Get.find<ExtensionPageController>().callRefresh();
    }
    // 重载搜索页面
    if (Get.isRegistered<SearchPageController>()) {
      Get.find<SearchPageController>().callRefresh();
    }
    // Home (Continuar/Favoritos/fondo del hero) — sin esto, desactivar o
    // desinstalar una extensión dejaba su contenido visible en Home hasta
    // el próximo refresco manual o hasta reabrir la página.
    HomePageController.callRefreshAll();
  }

  static final RegExp _episodeNumberPattern = RegExp(r'\d+(?:\.\d+)?');

  // El número real de episodio/capítulo, extraído del título guardado —
  // NO la posición en la lista (episodeId+1). La posición asume que el
  // índice local coincide 1:1 con la numeración real de la fuente, y eso
  // se rompe apenas hay un special/capítulo no secuencial o un offset
  // distinto por extensión (confirmado: mostraba "Episodio 4" para lo que
  // en verdad era el episodio 3). Si el título guardado no tiene ningún
  // número (algunas fuentes ahí guardan el título de la serie repetido en
  // vez del episodio puntual), se cae a la posición como última opción.
  static String episodeNumberLabel(String? episodeTitle, int episodeId) {
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      final matches = _episodeNumberPattern.allMatches(episodeTitle).toList();
      if (matches.isNotEmpty) return matches.last.group(0)!;
    }
    return (episodeId + 1).toString();
  }

  // Manga y novela (fikushon) se muestran igual — "Lectura" — de cara al
  // usuario: ambos son texto para leer, y manga en particular es muy
  // versátil (manhwa/manhua/cómic caen ahí también). El ExtensionType
  // interno sigue distinguiendo los dos (el lector usa una UI distinta
  // para cada uno); esto solo unifica la ETIQUETA visible.
  static String typeToString(ExtensionType type) {
    switch (type) {
      case ExtensionType.bangumi:
        return 'extension-type.video'.i18n;
      case ExtensionType.fikushon:
      case ExtensionType.manga:
        return 'extension-type.reading'.i18n;
      case ExtensionType.mixed:
        return 'extension-type.mixed'.i18n;
    }
  }

  // Extensiones normales declaran un ExtensionType fijo (manga/bangumi/
  // fikushon) que alcanza para decidir lector-vs-reproductor. Una extensión
  // "mixed" (ej. ShadeManga: manga Y anime reales en el mismo sitio) no
  // puede hacerlo — necesita el tipo de CADA título puntual, que la
  // extensión manda en ExtensionDetail.type (ver detail() en el SDK). Este
  // helper es el único lugar que resuelve esa ambigüedad, para no repetir
  // la misma lógica en DetailPageController, resumeHistoryItem, etc.
  static ExtensionType resolveType(
      Extension extension, ExtensionDetail? detail) {
    if (extension.type != ExtensionType.mixed) return extension.type;
    return detail?.type ?? ExtensionType.bangumi;
  }

  // Único lugar con esta regla — antes estaba duplicada palabra por palabra
  // en search_page.dart y extension_repo_page.dart ("mixed entra en las
  // dos"), con el riesgo de que se actualizara en un lado y no en el otro.
  static const videoTypes = {ExtensionType.bangumi, ExtensionType.mixed};
  static const readingTypes = {
    ExtensionType.manga,
    ExtensionType.fikushon,
    ExtensionType.mixed,
  };

  static addLog(
    Extension ext,
    ExtensionLogLevel level,
    String logContent,
  ) async {
    if (!Get.isRegistered<SettingsController>()) {
      return;
    }
    final windowId = Get.find<SettingsController>().extensionLogWindowId.value;
    if (windowId == -1) {
      return;
    }
    try {
      DesktopMultiWindow.invokeMethod(
        windowId,
        "addLog",
        jsonEncode(
          ExtensionLog(
            extension: ext,
            content: logContent,
            time: DateTime.now(),
            level: level,
          ).toJson(),
        ),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  static addNetworkLog(
    String key,
    ExtensionNetworkLog log,
  ) {
    if (!Get.isRegistered<SettingsController>()) {
      return;
    }
    final windowId = Get.find<SettingsController>().extensionLogWindowId.value;
    if (windowId == -1) {
      return;
    }
    try {
      DesktopMultiWindow.invokeMethod(
        windowId,
        "addNetworkLog",
        jsonEncode({
          'key': key,
          'log': log.toJson(),
        }),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // 解析扩展为元数据
  static Extension parseExtension(String extension) {
    Map<String, dynamic> result = {};
    RegExp exp = RegExp(r'@(\w+)\s+(.*)');
    Iterable<RegExpMatch> matches = exp.allMatches(extension);
    for (RegExpMatch match in matches) {
      result[match.group(1)!] = match.group(2);
    }
    result['nsfw'] = result['nsfw'] == "true";
    return Extension.fromJson(result);
  }
}
