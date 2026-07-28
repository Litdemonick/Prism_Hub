// ignore_for_file: use_build_context_synchronously
import 'dart:io';

import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

late PackageInfo packageInfo;
late AndroidDeviceInfo androidDeviceInfo;
late WindowsDeviceInfo windowsDeviceInfo;
late LinuxDeviceInfo linuxDeviceInfo;

class ApplicationUtils {
  static Future ensureInitialized() async {
    packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      androidDeviceInfo = await deviceInfo.androidInfo;
      return packageInfo;
    }
    if (Platform.isLinux) {
      linuxDeviceInfo = await deviceInfo.linuxInfo;
      return packageInfo;
    }
    if (Platform.isWindows) {
      windowsDeviceInfo = await deviceInfo.windowsInfo;
    }
    return packageInfo;
  }

  static String get _platformSuffix =>
      Platform.isWindows ? 'windows-x64.zip' : 'linux-x64.tar.gz';

  static bool get _windowsInstallLooksManaged {
    if (!Platform.isWindows) return false;
    final installDir = Directory(Platform.resolvedExecutable).parent;
    final lower = installDir.path.toLowerCase();
    final hasInnoUninstaller = installDir
        .listSync()
        .whereType<File>()
        .any((f) => f.uri.pathSegments.last.toLowerCase().startsWith('unins'));
    return hasInnoUninstaller || lower.contains(r'\program files');
  }

  static Map<String, dynamic>? _findAsset(dynamic assets, String tagName) {
    final expectedName = 'PrismHub-$tagName-$_platformSuffix';
    final expectedSetupName = 'PrismHub-setup-$tagName.exe';
    try {
      final list = assets as List;
      if (Platform.isWindows && _windowsInstallLooksManaged) {
        final setup = list.firstWhereOrNull(
          (a) => (a['name'] as String?) == expectedSetupName,
        );
        if (setup != null) return setup as Map<String, dynamic>;
      }
      final archive = list.firstWhere(
        (a) => (a['name'] as String) == expectedName,
      );
      return archive as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _findAndroidAsset(dynamic assets) {
    if (!Platform.isAndroid) return null;
    try {
      final list = (assets as List).cast<Map<String, dynamic>>();
      final supportedAbis = androidDeviceInfo.supportedAbis;
      for (final abi in supportedAbis) {
        final match = list.firstWhereOrNull((a) {
          final name = (a['name'] as String?)?.toLowerCase() ?? '';
          return name.endsWith('-$abi.apk');
        });
        if (match != null) return match;
      }
      return list.firstWhereOrNull((a) {
        final name = (a['name'] as String?)?.toLowerCase() ?? '';
        return name.endsWith('.apk');
      });
    } catch (_) {
      return null;
    }
  }

  // Chequeo obligatorio de versión: a diferencia de checkUpdate() (dialog
  // descartable, disparado manualmente o al inicio si autoCheckUpdate está
  // activado), esta variante bloquea el uso de la app con una página de
  // pantalla completa sin forma de cerrarla salvo actualizando. Solo tiene
  // sentido en Android/Windows/Linux — la Web siempre sirve la última
  // versión desplegada, no hay un "instalable" que forzar.
  static Future<void> checkForcedUpdate(BuildContext context) async {
    if (kIsWeb) return;
    try {
      const url =
          "https://api.github.com/repos/Litdemonick/Prism_Hub/releases/latest";
      final res = await dio.get(url);
      final tagName = res.data["tag_name"] as String;
      final remoteVersion = tagName.replaceFirst('v', '');
      if (packageInfo.version == remoteVersion) return;
      if (!context.mounted) return;

      final asset = Platform.isAndroid
          ? _findAndroidAsset(res.data['assets'])
          : _findAsset(res.data['assets'], tagName);

      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              _ForcedUpdatePage(
            remoteVersion: remoteVersion,
            changelog: (res.data['body'] as String?) ?? '',
            htmlUrl: res.data['html_url'] as String,
            asset: asset,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } catch (e) {
      // Silencioso: si no se puede chequear (sin internet, GitHub caído), no
      // hay que bloquear el uso de la app por un error de red — el gate solo
      // se muestra cuando SÍ se confirma una versión nueva.
      debugPrint('checkForcedUpdate error: $e');
    }
  }

  static checkUpdate(BuildContext context, {bool showSnackbar = false}) async {
    try {
      const url =
          "https://api.github.com/repos/Litdemonick/Prism_Hub/releases/latest";
      final res = await dio.get(url);
      final tagName = res.data["tag_name"] as String;
      final remoteVersion = tagName.replaceFirst('v', '');
      debugPrint('remoteVersion: $remoteVersion');
      if (packageInfo.version != remoteVersion) {
        if (Platform.isAndroid) {
          final asset = _findAndroidAsset(res.data['assets']);
          Get.to(
            Scaffold(
              appBar: AppBar(
                title: Text(
                  FlutterI18n.translate(
                    context,
                    'upgrade.new-version',
                    translationParams: {
                      'version': remoteVersion,
                    },
                  ),
                ),
              ),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(child: Markdown(data: res.data['body'])),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: PlatformFilledButton(
                        onPressed: () {
                          RouterUtils.pop();
                          launchUrl(
                            Uri.parse(
                              (asset?['browser_download_url'] as String?) ??
                                  res.data['html_url'] as String,
                            ),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: Text('upgrade.download'.i18n),
                      ),
                    )
                  ],
                ),
              ),
            ),
            transition: Transition.rightToLeftWithFade,
          );
          return;
        }

        final asset = _findAsset(res.data['assets'], tagName);

        showPlatformDialog(
          context: context,
          title: FlutterI18n.translate(
            context,
            'upgrade.new-version',
            translationParams: {
              'version': remoteVersion,
            },
          ),
          content: Markdown(
            shrinkWrap: true,
            data: res.data['body'],
          ),
          actions: [
            PlatformTextButton(
              onPressed: () {
                RouterUtils.pop();
              },
              child: Text('upgrade.not-now'.i18n),
            ),
            PlatformFilledButton(
              onPressed: () {
                RouterUtils.pop();
                if (asset != null) {
                  _downloadAndInstall(context, asset, remoteVersion);
                } else {
                  launchUrl(
                    Uri.parse(res.data['html_url']),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              child: Text(
                asset != null ? 'upgrade.download-install'.i18n : 'upgrade.download'.i18n,
              ),
            )
          ],
        );
      } else {
        if (!showSnackbar) {
          return;
        }
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.check-update'.i18n,
          content: "upgrade.no-update".i18n,
        );
      }
    } catch (e) {
      if (!showSnackbar) {
        return;
      }
      showPlatformSnackbar(
        context: context,
        title: 'upgrade.check-update'.i18n,
        content: 'upgrade.error'.i18n,
      );
    }
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    Map<String, dynamic> asset,
    String version,
  ) async {
    Get.dialog(
      const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Descargando actualización...'),
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );

    try {
      final url = asset['browser_download_url'] as String;
      final tempDir = Directory.systemTemp.createTempSync('PrismHub_update_');
      final downloadPath = '${tempDir.path}/${asset['name']}';

      // Descargar con progreso
      await dio.download(url, downloadPath, onReceiveProgress: (count, total) {
        debugPrint('Download progress: ${(count / total * 100).toStringAsFixed(2)}%');
      });

      final assetName = (asset['name'] as String).toLowerCase();

      // Android: descargar e instalar APK automáticamente
      if (Platform.isAndroid && assetName.endsWith('.apk')) {
        Get.back(); // Cerrar dialogo
        await _installAndroidApk(downloadPath);
        return;
      }

      // Windows: instalador .exe
      if (Platform.isWindows && assetName.endsWith('.exe')) {
        Get.back();
        await _runWindowsInstaller(downloadPath);
        return;
      }

      // Windows/Linux: descargar y reemplazar app
      final extractDir =
          Directory('${tempDir.path}${Platform.pathSeparator}app');
      extractDir.createSync();

      if (Platform.isLinux) {
        await Process.run('tar', [
          '-xzf',
          downloadPath,
          '-C',
          extractDir.path,
        ]);
      } else if (Platform.isWindows) {
        await Process.run('powershell', [
          'Expand-Archive',
          '-Path',
          downloadPath,
          '-DestinationPath',
          extractDir.path,
          '-Force',
        ]);
      }

      Get.back();

      final sourceDir = _findExtractedAppDir(extractDir);
      await _replaceAndRestart(sourceDir, tempDir);
    } catch (e) {
      Get.back();
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.install-failed'.i18n,
          content: e.toString(),
        );
      }
      debugPrint('Download/install error: $e');
    }
  }

  static Future<void> _installAndroidApk(String apkPath) async {
    try {
      final file = File(apkPath);
      if (!await file.exists()) {
        throw 'APK file not found: $apkPath';
      }

      // Usar android_intent_plus para instalar el APK
      const platform = MethodChannel('com.example.prismhub/update');
      await platform.invokeMethod('installApk', {'apkPath': apkPath});
    } catch (e) {
      debugPrint('Android APK install error: $e');
      // Fallback: abrir el APK con la aplicación predeterminada
      try {
        await launchUrl(Uri.file(apkPath), mode: LaunchMode.externalApplication);
      } catch (_) {
        rethrow;
      }
    }
  }

  static Directory _findExtractedAppDir(Directory extractDir) {
    final currentExeName =
        Platform.resolvedExecutable.split(Platform.pathSeparator).last;
    final targetExeName = currentExeName.toLowerCase();
    final exeFiles = extractDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    final matchingExe = exeFiles.firstWhereOrNull(
      (f) => f.uri.pathSegments.last.toLowerCase() == targetExeName,
    );
    if (matchingExe != null) return matchingExe.parent;

    final prismExe = exeFiles.firstWhereOrNull(
      (f) => f.uri.pathSegments.last.toLowerCase().contains('prismhub'),
    );
    if (prismExe != null) return prismExe.parent;

    if (Platform.isLinux) {
      final currentName =
          Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      final matchingFile = extractDir
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhereOrNull(
            (f) => f.uri.pathSegments.last.toLowerCase() ==
                currentName.toLowerCase(),
          );
      if (matchingFile != null) return matchingFile.parent;
    }

    return extractDir;
  }

  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  static bool _canWriteTo(Directory dir) {
    try {
      final probe = File(
        '${dir.path}${Platform.pathSeparator}.prismhub-update-write-test',
      );
      probe.writeAsStringSync('ok');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _runWindowsInstaller(String installerPath) async {
    final command =
        'Start-Process -FilePath ${_psQuote(installerPath)} -Verb RunAs';
    await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ]);
    exit(0);
  }

  static Future<void> _replaceAndRestart(
    Directory sourceDir,
    Directory tempDir,
  ) async {
    final currentExe = Platform.resolvedExecutable;
    final installDir = Directory(currentExe).parent;
    final exeName = currentExe.split(Platform.pathSeparator).last;

    if (Platform.isLinux) {
      try {
        // Copiar archivos con permisos
        await Process.run('cp', ['-r', '${sourceDir.path}/.', installDir.path]);
        // Asegurar que el ejecutable sea ejecutable
        await Process.run('chmod', ['+x', '${installDir.path}/$exeName']);
        // Iniciar la app actualizada en un nuevo proceso
        Process.start(
          '${installDir.path}/$exeName',
          [],
          mode: ProcessStartMode.detached,
        );
        // Dar tiempo para que el nuevo proceso inicie antes de salir
        await Future.delayed(const Duration(milliseconds: 500));
        exit(0);
      } catch (e) {
        debugPrint('Linux update failed: $e');
        rethrow;
      }
    } else if (Platform.isWindows) {
      final scriptPath = '${tempDir.path}\\update.ps1';
      final logPath =
          '${Directory.systemTemp.path}\\PrismHub-update-${DateTime.now().millisecondsSinceEpoch}.log';
      
      File(scriptPath).writeAsStringSync(
        r'''
param(
  [string]$SourceDir,
  [string]$InstallDir,
  [string]$ExeName,
  [string]$TempDir,
  [string]$LogPath,
  [int]$AppPid
)

$ErrorActionPreference = 'Continue'
$VerbosePreference = 'Continue'

function Log([string]$Message) {
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  $logMessage = "[$timestamp] $Message"
  Write-Host $logMessage
  Add-Content -LiteralPath $LogPath -Value $logMessage
}

Log "Update script started"
Log "Source: $SourceDir"
Log "Install: $InstallDir"
Log "App PID: $AppPid"

try {
  # Esperar a que la aplicación se cierre (máximo 30 segundos)
  Log "Waiting for PrismHub process $AppPid to exit..."
  try {
    $process = Get-Process -Id $AppPid -ErrorAction SilentlyContinue
    if ($process) {
      $process.WaitForExit(30000)
      Log "Process exited"
    } else {
      Log "Process not found, proceeding with update"
    }
  } catch {
    Log "Could not wait for process: $_"
  }
  
  # Crear directorio de instalación si no existe
  if (-not (Test-Path $InstallDir)) {
    Log "Creating install directory: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  }
  
  # Copiar archivos
  Log "Copying files from $SourceDir to $InstallDir"
  Get-ChildItem -Path $SourceDir -Recurse | 
    Copy-Item -Destination { 
      if ($_.PSIsContainer) {
        Join-Path $InstallDir $_.FullName.Substring($SourceDir.Length)
      } else {
        Join-Path $InstallDir $_.FullName.Substring($SourceDir.Length)
      }
    } -Force -ErrorAction Continue
  
  Log "Copy completed"
  
  # Iniciar la aplicación actualizada
  $exePath = Join-Path $InstallDir $ExeName
  Log "Starting $exePath"
  Start-Process -FilePath $exePath -PassThru
  Log "Application started"
  
} catch {
  Log "ERROR: $($_.Exception.Message)"
  Log "Attempting to start existing application..."
  try {
    Start-Process -FilePath (Join-Path $InstallDir $ExeName)
  } catch {
    Log "Failed to start application: $_"
  }
} finally {
  Log "Cleaning up temp directory..."
  try {
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    Log "Temp directory cleaned"
  } catch {
    Log "Could not clean temp: $_"
  }
  Log "Update script finished"
}
''',
      );
      
      final args = [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-SourceDir',
        sourceDir.path,
        '-InstallDir',
        installDir.path,
        '-ExeName',
        exeName,
        '-TempDir',
        tempDir.path,
        '-LogPath',
        logPath,
        '-AppPid',
        pid.toString(),
      ];
      
      try {
        if (_canWriteTo(installDir)) {
          // Permisos suficientes: ejecutar sin elevar
          Process.start('powershell', args, mode: ProcessStartMode.detached);
          debugPrint('Update script started with standard permissions');
        } else {
          // Sin permisos: elevar con RunAs
          final command = 'Start-Process -FilePath powershell '
              '-ArgumentList ${_psQuote(args.map(_psQuote).join(','))} '
              '-Verb RunAs -WindowStyle Hidden';
          Process.run('powershell', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            command,
          ]);
          debugPrint('Update script started with elevated permissions');
        }
        // Esperar un poco antes de salir para que PowerShell inicie
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        debugPrint('Failed to start update script: $e');
        rethrow;
      }
      
      exit(0);
    }
  }
}

// Página de pantalla completa sin forma de descartarla (PopScope con
// canPop:false, sin AppBar/botón atrás) — se muestra solo cuando
// checkForcedUpdate() confirmó una versión más nueva. En Windows/Linux con
// asset disponible, "Actualizar ahora" descarga+instala+reinicia el proceso
// solo (nunca vuelve a esta página). En Android (y Desktop sin asset
// coincidente) abre la página de GitHub en el navegador y agrega un botón
// "Ya actualicé": vuelve a consultar PackageInfo.fromPlatform() (lee el
// paquete instalado en el SO, no el proceso en memoria) para detectar si la
// actualización ya se instaló y, en ese caso, recién ahí cierra el gate.
class _ForcedUpdatePage extends StatefulWidget {
  const _ForcedUpdatePage({
    required this.remoteVersion,
    required this.changelog,
    required this.htmlUrl,
    required this.asset,
  });

  final String remoteVersion;
  final String changelog;
  final String htmlUrl;
  final Map<String, dynamic>? asset;

  @override
  State<_ForcedUpdatePage> createState() => _ForcedUpdatePageState();
}

class _ForcedUpdatePageState extends State<_ForcedUpdatePage> {
  bool _checking = false;

  bool get _needsManualRetry => Platform.isAndroid || widget.asset == null;

  Future<void> _retryCheck() async {
    setState(() => _checking = true);
    try {
      packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.version == widget.remoteVersion) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        return;
      }
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'upgrade.still-outdated'.i18n,
        );
      }
    } catch (_) {
      if (mounted) {
        showPlatformSnackbar(context: context, content: 'upgrade.error'.i18n);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _updateNow() {
    if (Platform.isAndroid) {
      // Android: descargar e instalar automáticamente
      if (widget.asset != null) {
        ApplicationUtils._downloadAndInstall(
          context,
          widget.asset!,
          widget.remoteVersion,
        );
      } else {
        // Fallback: abrir GitHub si no hay asset
        launchUrl(Uri.parse(widget.htmlUrl), mode: LaunchMode.externalApplication);
      }
    } else if (widget.asset != null) {
      // Windows/Linux: con asset disponible
      ApplicationUtils._downloadAndInstall(
        context,
        widget.asset!,
        widget.remoteVersion,
      );
    } else {
      // Sin asset: abrir GitHub
      launchUrl(Uri.parse(widget.htmlUrl), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withOpacity(0.5), // Fondo oscuro semi-transparente
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isMobile ? double.infinity : 600,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barra de título (solo en desktop)
                    if (!isMobile)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: HomeTheme.accentPink.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.system_update,
                                size: 24, color: HomeTheme.accentPink),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                FlutterI18n.translate(
                                  context,
                                  'upgrade.new-version',
                                  translationParams: {'version': widget.remoteVersion},
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: HomeTheme.accentPink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Contenido
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isMobile) ...[
                                const Icon(Icons.system_update,
                                    size: 48, color: HomeTheme.accentPink),
                                const SizedBox(height: 16),
                                Text(
                                  FlutterI18n.translate(
                                    context,
                                    'upgrade.new-version',
                                    translationParams: {'version': widget.remoteVersion},
                                  ),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: HomeTheme.textPrimary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'upgrade.forced-required'.i18n,
                                style: const TextStyle(color: HomeTheme.textPrimary),
                              ),
                              const SizedBox(height: 16),
                              Markdown(
                                data: widget.changelog,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Botones
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (_needsManualRetry) ...[
                            Expanded(
                              child: PlatformTextButton(
                                onPressed: _checking ? null : _retryCheck,
                                child: Text('upgrade.already-updated'.i18n),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: PlatformFilledButton(
                              onPressed: _checking ? null : _updateNow,
                              child: Text('upgrade.update-now'.i18n),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
