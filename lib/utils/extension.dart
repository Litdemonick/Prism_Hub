import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/controllers/settings_controller.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/extension_signature.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/utils/router.dart';
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
  static DateTime? _remoteVersionsFetchedAt;
  static const _remoteVersionsTtl = Duration(minutes: 10);
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
    _remoteVersionsFetchedAt = null;
    _repoIndexCache = null;
    _repoIndexFetchedAt = null;
  }

  static Future<Map<String, String>> _fetchRemoteVersions() async {
    final cached = _remoteVersionsCache;
    final fetchedAt = _remoteVersionsFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _remoteVersionsTtl) {
      return cached;
    }
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

  static Future<Map<String, String>> _doFetchRemoteVersions() async {
    final cached = _remoteVersionsCache;
    try {
      final list = await fetchRepoIndex();
      final map = <String, String>{};
      final unstableMap = <String, bool>{};
      for (final e in list) {
        final pkg = e['package'] as String?;
        final ver = e['version'] as String?;
        if (pkg != null && ver != null) map[pkg] = ver;
        if (pkg != null) {
          unstableMap[pkg] = e['unstable'] == 'true' || e['unstable'] == true;
        }
      }
      _remoteVersionsCache = map;
      _remoteUnstableCache = unstableMap;
      _remoteVersionsFetchedAt = DateTime.now();
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
    final repoUrl = PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl);
    final bust = DateTime.now().millisecondsSinceEpoch;
    final url =
        cacheBust ? '$repoUrl/index.json?t=$bust' : '$repoUrl/index.json';
    final res = await dio.get<String>(
      url,
      options: Options(receiveTimeout: const Duration(seconds: 20)),
    );
    final decoded = await compute(jsonDecode, res.data!);
    final list = decoded is Map ? (decoded['extensions'] ?? []) : decoded;
    final normalized = List<dynamic>.from(list);
    _rememberOfficialCatalogEntries(normalized);
    _repoIndexCache = normalized;
    _repoIndexFetchedAt = DateTime.now();
    return normalized;
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
  static Future<bool> hasExtensionUpdate(String package) async {
    final installed = runtimes[package]?.extension.version;
    if (installed == null) return false;
    final remote = await _fetchRemoteVersions();
    if (_remoteUnstableCache?[package] == true) return true;
    final remoteVersion = remote[package];
    return remoteVersion != null && remoteVersion != installed;
  }

  // Igual que hasExtensionUpdate pero devuelve SOLO el motivo "inestable"
  // (no versión) — usado para el badge naranja "Inestable" en ExtensionTile,
  // separado del badge rojo genérico de "actualización requerida". Comparte
  // el mismo caché/TTL, no pega de nuevo al índice.
  static Future<bool> isRemoteUnstable(String package) async {
    await _fetchRemoteVersions();
    return _remoteUnstableCache?[package] == true;
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
    if (Get.isRegistered<HomePageController>()) {
      Get.find<HomePageController>().callRefresh();
    }
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
