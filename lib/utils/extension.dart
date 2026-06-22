import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
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
    'io.prismhub.jkanime',    // anime ES — múltiples servidores confiables
    'io.prismhub.manhwaweb',  // manhwa/manga ES — ManhwaWeb
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
      final repoUrl = PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl);
      // Cache-bust: GitHub raw caches index.json/dist for minutes, which would
      // hide a freshly pushed extension/resolver fix.
      final bust = DateTime.now().millisecondsSinceEpoch;
      final res = await dio.get<String>('$repoUrl/index.json?t=$bust');
      final decoded = jsonDecode(res.data!);
      final List list =
          decoded is Map ? (decoded['extensions'] ?? []) : decoded;
      for (final e in list) {
        final pkg = e['package']?.toString();
        final scriptUrl = (e['script'] ?? e['url'])?.toString();
        if (pkg == null || scriptUrl == null) continue;
        // Registrar TODA extensión del catálogo oficial (no solo las default)
        // para bloquear sideloads que las dupliquen.
        officialPackages.add(pkg);
        final officialName = e['name']?.toString().toLowerCase().trim();
        if (officialName != null && officialName.isNotEmpty) {
          officialNames.add(officialName);
        }
        // Solo los 3 paquetes por defecto se auto-instalan en primer launch.
        // Los demás nativos están disponibles en el catálogo del repo.
        if (!defaultPackages.contains(pkg)) continue;

        final dest = File(path.join(extensionsDir, '$pkg.js'));
        final exists = dest.existsSync();
        // Los 3 defaults se garantizan siempre presentes: si falta uno (p.ej.
        // cambió el set de defaults tras el primer arranque), se instala. Así el
        // equipo siempre tiene exactamente las 3 oficiales por defecto.
        // Already installed: only re-download when the repo version is different.
        if (exists) {
          final repoVersion = e['version']?.toString().replaceFirst('v', '');
          final localVersion = _scriptVersion(dest.readAsStringSync());
          if (repoVersion == null || repoVersion == localVersion) continue;
        }
        final sep = scriptUrl.contains('?') ? '&' : '?';
        final js = await dio.get<String>('$scriptUrl${sep}t=$bust');
        if (js.data != null && js.data!.isNotEmpty) {
          // Seguridad: los defaults son oficiales y DEBEN traer firma válida de
          // prism+. Si falta o no valida, es manipulación → no se instala.
          final signature = e['signature']?.toString();
          if (!ExtensionSignature.isOfficial(js.data!, signature)) {
            debugPrint(
                'Firma inválida o ausente para $pkg — no se instala (posible manipulación).');
            continue;
          }
          dest.writeAsStringSync(js.data!);
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
        for (final f in Directory(extensionsDir).listSync()) {
          if (path.extension(f.path) != '.js') continue;
          final pkg = path.basenameWithoutExtension(f.path);
          if (pkg.startsWith('io.prismhub.') &&
              !officialPackages.contains(pkg) &&
              !nativePackages.contains(pkg)) {
            try {
              File(f.path).deleteSync();
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
    _purgeRemovedPackages();
    await _installDefaultsFromRepo();
    await _loadExtensions();
    // Limpia el Hive disabled-list de entradas muertas (paquetes sin JS).
    _cleanStaleDisabledList();
    // 监听目录变化
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
            // Skip if this package is already being installed (e.g. by install())
            if (_loading.contains(package)) break;
            runtimes.remove(package);
            extensionErrorMap.remove(event.path);
            await installByPath(event.path);
            _safeReloadPage();
            break;
        }
      }
    });
  }

  static _loadExtensions() async {
    final extensionsList = Directory(extensionsDir).listSync();
    // Carga en paralelo: con 3-10 extensiones instaladas ahorra ~0.5-2 s
    // en el arranque del app versus la carga secuencial original.
    await Future.wait(extensionsList.map((e) => installByPath(e.path)));
    _reloadPage();
  }

  static uninstall(String package) async {
    final file = File(path.join(extensionsDir, '$package.js'));
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  // Borra sin necesidad de red los .js de paquetes retirados del catálogo.
  static void _purgeRemovedPackages() {
    for (final pkg in _removedPackages) {
      try {
        final f = File(path.join(extensionsDir, '$pkg.js'));
        if (f.existsSync()) {
          f.deleteSync();
          debugPrint('Paquete retirado eliminado del dispositivo: $pkg');
        }
      } catch (_) {}
    }
  }

  // Elimina del Hive disabled-list los package IDs que ya no tienen JS en disco,
  // evitando datos muertos que confundan el estado de la UI.
  static void _cleanStaleDisabledList() {
    final raw = PrismHubStorage.getSetting(SettingKey.disabledExtensions);
    if (raw == null) return;
    final List<String> list =
        raw is List ? List<String>.from(raw) : <String>[];
    final existingPkgs = Directory(extensionsDir)
        .listSync()
        .where((e) => path.extension(e.path) == '.js')
        .map((e) => path.basenameWithoutExtension(e.path))
        .toSet();
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
    if (pkg.isEmpty || !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(pkg)) {
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
    File(savePath).writeAsStringSync(script);
    try {
      runtimes[pkg] = await ExtensionService().initRuntime(ext);
    } catch (e) {
      // Init failed — remove the bad runtime and file so it doesn't persist
      // and break loading on the next launch.
      runtimes.remove(pkg);
      try {
        File(savePath).deleteSync();
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
  }

  static String typeToString(ExtensionType type) {
    switch (type) {
      case ExtensionType.bangumi:
        return 'extension-type.video'.i18n;
      case ExtensionType.fikushon:
        return 'extension-type.novel'.i18n;
      case ExtensionType.manga:
        return 'extension-type.comic'.i18n;
    }
  }

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
