# PrismHub — Session Context

## Last Release: v1.0.6
- Tag `v1.0.6` pushed to `main` (commit to be created)
- CI building: Linux, Windows, Android APKs
- Old releases v1.0.3, v1.0.4 deleted (tags + GitHub releases)

## Fixes Applied (already in main)

### Linux
- `release.yml`: Step copies `libquickjs_c_bridge_plugin.so` manually into Linux bundle after build (flutter_js 0.8.x bug: uses `flutter_qjs_bundled_libraries` instead of `flutter_js_bundled_libraries`, so the .so was never included)
- `application.dart:289-292`: `tempDir` → `downloadDir` fix (rename broke update path)
- App works on any Linux distro with proper GPU drivers (CachyOS, Arch, Ubuntu, Fedora, etc.)

### Windows
- `_downloadAndInstall`, `_replaceAndRestart` fixed in `application.dart`
- `_ForcedUpdatePage`: centered card, not full-screen overlay (window stays movable)
- PowerShell update script improved (permissions, timeout, logging)

### Android
- APK download uses `getTemporaryDirectory()` (app cache, covered by FileProvider), not `Directory.systemTemp`
- MethodChannel `installApk` in `MainActivity.kt`
- `REQUEST_INSTALL_PACKAGES` permission in `AndroidManifest.xml`
- FileProvider paths in `file_paths.xml`

### Asset naming (v1.0.5)
- APK names now `PrismHub-v1.0.5-android-arm64-v8a.apk` etc. (added `android-` prefix)
- Release body table updated to match

## Known Issues
- **Linux SIGSEGV in VirtualBox**: Crash at startup with `LIBGL_ALWAYS_SOFTWARE=1`, SIGSEGV in mpv/media_kit init. Cause: VirtualBox has no proper GPU driver — Mesa/EGL crash. **On real hardware it works fine.** If needed: force software rendering in Flutter runner C++ code, or wrap with `MPV_VO=x11` / `GALLIUM_DRIVER=softpipe` env vars.

## Update flow to test
1. v1.0.3 → v1.0.5 auto-update needs to be verified once v1.0.3 build is confirmed working
2. The v1.0.3 downloadable Linux bundle was built from commit `0e9346c` (which includes the tempDir fix)

## Git Branches
- `main` and `develop` both at commit `ac10d83` (v1.0.5)
- Local tags: none (old ones deleted, only remote tag `v1.0.5`)

---

## Debug Session — 2026-07-28 — Crash on Android & Linux (Windows OK)

### Symptom (confirmed 2026-07-28)
- **Windows**: downloaded build works fine
- **Android**: splash NUNCA se ve → crash ANTES de `runApp()` (Crash Point A)
- **Linux**: splash SÍ aparece ("sale y cargando") → luego crashea y se cierra → crash DURANTE `_init()` (Crash Point B o C)

### Crash Analysis — Startup Flow (main.dart)

```
main()
  ├── WidgetsFlutterBinding.ensureInitialized()
  ├── PrismHubDirectory.ensureInitialized()
  ├── PrismHubStorage.ensureInitialized()  ← Hive + Isar
  ├── [desktop] windowManager setup        ← only Linux/Windows
  ├── [Android] SystemUiOverlayStyle
  └── runApp(_AppRoot())                   ← NEVER reached if above throws
```

#### Crash Point A: BEFORE `runApp()` (no splash visible)
If `PrismHubStorage.ensureInitialized()` throws (Hive/Isar init fail, corrupted DB, schema mismatch, migration error), `runApp()` is never called. The Flutter engine starts but has no UI — app appears to "open and close."

Relevant code: `prismhub_storage.dart:17-46`
- `Hive.initFlutter(_path)` → `Hive.openBox("settings")`
- `Isar.open(...)` → `performMigrationIfNeeded()`
- Migration: `throw Exception('Unknown version: $currentVersion')`

#### Crash Point B: `_AppRootState._init()` (splash visible but frozen)
```dart
_init()  // main.dart:160
  ├── PrismLog.ensureInitialized()
  ├── await ApplicationUtils.ensureInitialized()  ← PackageInfo + DeviceInfo
  ├── await ConnectivityUtils.ensureInitialized()
  ├── await PrismRequest.ensureInitialized()
  ├── await ExtensionUtils.ensureInitialized()
  ├── MediaKit.ensureInitialized()
  └── setState(() => _ready = true)               ← NEVER reached if above throws
```
If any step throws async, `_ready` stays false → splash forever. Error goes to zone handler (logs via `logger.severe`).

#### Crash Point C: Native crash (app process killed)
If a native library fails to load (SIGSEGV, UnsatisfiedLinkError), the process terminates regardless of Dart error handling.

### Platform-Specific Findings

#### 1. `JsBridge` NOT initialized on Android (only Linux)
- **File**: `extension_service.dart:272-300`
- `if (Platform.isLinux)` guard — `JsBridge` + all `handleDartBridge(...)` handlers only set up for Linux
- Android extensions that rely on `DartBridge.sendMessage` will fail silently or crash
- The JS eval strings are different per platform (Linux uses `DartBridge`, Android uses `sendMessage`/`stringify`)
- **Not a startup crash** but breaks extension runtime on Android

#### 2. `FlutterWindowsWebview` called on Linux
- **File**: `tracking_page_controller.dart:3,54`
- Top-level import: `import 'package:flutter_windows_webview/flutter_windows_webview.dart';`
- Runtime usage: `final webview = FlutterWindowsWebview();` — falls through on Linux because `!Platform.isAndroid` (line 47) is true
- **Crash on Linux** when logging into AniList

#### 3. `MediaKit.ensureInitialized()` — sync throw not caught
- **File**: `main.dart:171` in `_AppRootState._init()`
- `media_kit` v1.2.6 `ensureInitialized()` calls `nativeEnsureInitialized()` on ALL platforms
- If native libs missing (`libmpv.so` on Linux, `libmedia_kit_native_player.so` on Android) → throws synchronously
- No try-catch in `_init()` → Future rejects → zone catches → splash stays forever
- On Linux with missing/corrupt GPU drivers: native SIGSEGV kills process (documented in Known Issues for VirtualBox)

#### 4. `DeviceInfoPlugin` platform-specific calls
- **File**: `application.dart:29-44`
- `deviceInfo.androidInfo` / `deviceInfo.linuxInfo` / `deviceInfo.windowsInfo`
- If platform plugin not linked correctly → `MissingPluginException` → async error → splash forever
- Top-level `late` vars (`androidDeviceInfo`, `linuxDeviceInfo`, `windowsDeviceInfo`) crash with `LateInitializationError` if accessed on wrong platform — currently guarded correctly

#### 5. `flutter_windows_webview` git dependency
- **pubspec.yaml:49-52**: Git dep from `https://github.com/MiaoMint/flutter_windows_webview`
- Imported at top level in `tracking_page_controller.dart`
- Dart code resolves on all platforms, but native plugin only works on Windows
- Not a startup issue but could cause compile-time or load-time errors on Linux/Android

#### 6. `Process.run` calls on Linux (not startup but crash-prone)
- **bt_server.dart:52**: `Process.run('uname', ['-m'])` — fails on Linux without `uname`
- **bt_server.dart:94**: `Process.run('chmod', ...)` — fails in restricted filesystems
- **application.dart:322**: `Process.run('tar', ...)` — update flow fails without `tar`
- **application.dart:454**: `Process.run('cp', ...)` — update flow fails

### Dependencies — Versions Installed (pubspec.lock)
| Package | Required | Installed |
|---------|----------|-----------|
| media_kit | ^1.1.10+1 | 1.2.6 |
| media_kit_libs_video | ^1.0.4 | 1.0.7 |
| media_kit_libs_linux | transitive | 1.2.1 |
| media_kit_libs_android_video | transitive | 1.3.8 |
| media_kit_libs_windows_video | transitive | 1.0.11 |
| flutter_js | ^0.8.0 | 0.8.7 |
| hive | ^2.2.3 | (latest compatible) |
| isar | ^3.1.0+1 | (latest compatible) |
| device_info_plus | ^9.0.3 | (latest compatible) |

### MediaKit Native Library Loading (media_kit v1.2.6)

`NativeLibrary.ensureInitialized()` en `native_library.dart:32-101`:
- Windows: busca `libmpv-2.dll`, `mpv-2.dll`, `mpv-1.dll` en %PATH%
- Linux: busca `libmpv.so`, `libmpv.so.2`, `libmpv.so.1` con `DynamicLibrary.open()`
- Android: busca `libmpv.so`

Si NO encuentra la lib, lanza `Exception("Cannot find libmpv...")` SINCRÓNICAMENTE.
Esto ocurre DENTRO de `MediaKit.ensureInitialized()` → dentro de `_init()` → dentro de `initState()` del splash.

**En Linux**: `DynamicLibrary.open("libmpv.so")` falla si mpv no está instalado en el sistema O si el bundle no incluye las libs correctas de `media_kit_libs_linux`. La excepción es síncrona → Future de `_init()` se rechaza → zone handler loggea → splash se queda para siempre. PERO si el crash es nativo (SIGSEGV de mpv al cargar), el proceso muere directamente.

**En Android**: igual pero busca `libmpv.so` en el APK (provisto por `media_kit_libs_android_video`). Si falta o es ABI incorrecto, `DynamicLibrary.open()` lanza excepción.

### Hipótesis principal para Android (no splash)

El crash es ANTES de `runApp()`. El único código que corre entre `WidgetsFlutterBinding.ensureInitialized()` y `runApp()` en Android es:

```dart
await PrismHubDirectory.ensureInitialized();   // main.dart:86
await PrismHubStorage.ensureInitialized();      // main.dart:87 — Hive + Isar
// (salta windowManager porque !Platform.isAndroid)
SystemChrome.setSystemUIOverlayStyle(style);    // main.dart:131
runApp(const _AppRoot());                       // main.dart:134
```

**Probable causa**: `PrismHubStorage.ensureInitialized()` lanza async → `runApp()` nunca se llama. Posibles motivos:
- Hive: `Hive.initFlutter()` falla (path inválido, permisos)
- Hive: `Hive.openBox("settings")` falla (box corrupto de instalación previa)
- Isar: `Isar.open()` falla (esquema incompatible con DB existente)
- Migración: `performMigrationIfNeeded()` → `throw Exception('Unknown version: $currentVersion')`

### Hipótesis principal para Linux (splash visible → crash)

El splash SÍ se ve → `runApp()` se ejecutó bien. El crash es DURANTE `_init()`:

1. `ApplicationUtils.ensureInitialized()` → `deviceInfo.linuxInfo` (MissingPluginException?)
2. `ExtensionUtils.ensureInitialized()` → `_installDefaultsFromRepo()` (HTTP) + `_loadExtensions()` (QuickJsRuntime2 nativo)
3. `MediaKit.ensureInitialized()` → `DynamicLibrary.open("libmpv.so")` (nativo, potencial SIGSEGV)

**Mayor sospechoso**: `MediaKit.ensureInitialized()` porque:
- Es síncrono → si falla, el Future de `_init()` se rechaza
- La lib nativa `libmpv.so` puede no estar en el bundle o ser incompatible
- En Linux con GPU problemática: SIGSEGV (confirmado en Known Issues para VirtualBox, pero puede pasar en hardware real con drivers defectuosos)

### Fixes aplicados en v1.0.6
1. **main.dart:86-94**: `PrismHubStorage.ensureInitialized()` envuelto en try-catch → si Hive/Isar falla, `runApp()` igual se ejecuta y el splash se muestra
2. **main.dart:160-174**: Todas las llamadas de `_init()` envueltas en try-catch individual (ApplicationUtils, ConnectivityUtils, PrismRequest, ExtensionUtils, MediaKit) → ninguna falla impide que el splash transicione a la app
3. **prismhub_storage.dart**: `settings` y `database` cambiados de `late final` a nullable → `getSetting` devuelve `null` si settings no se inicializó
4. **prismhub_storage.dart**: Isar init envuelto en try-catch separado → si Isar falla, la app arranca sin DB
5. **tracking_page_controller.dart**: `loginAniList()` usa InAppWebView en Linux como Android, `FlutterWindowsWebview` solo en Windows → no crashea en Linux
6. **main.dart:108**: Valor por defecto `"1280,720"` para windowSize si getSetting devuelve null
