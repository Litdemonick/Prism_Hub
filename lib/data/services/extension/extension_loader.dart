import 'dart:io';

import 'package:isar/isar.dart';
import 'package:logging/logging.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/database_service.dart';
import '../../models/extension_model.dart';
import '../../providers/extension_repo_provider.dart';
import 'extension_installer.dart';
import 'extension_service.dart';

abstract final class ExtensionLoader {
  static final _log = Logger('ExtensionLoader');

  static Future<void> loadAll() async {
    final installed = await DatabaseService.db.extensionModels
        .filter()
        .isInstalledEqualTo(true)
        .findAll();

    _log.info('Extensiones en DB: ${installed.length}');

    for (final ext in installed) {
      if (ext.localScriptPath == null) continue;
      final file = File(ext.localScriptPath!);
      if (!await file.exists()) {
        _log.warning('Bundle no encontrado: ${ext.package}');
        continue;
      }
      try {
        final script = await file.readAsString();
        ExtensionService.load(ext, script);
      } catch (e, st) {
        _log.severe('Error cargando ${ext.package}', e, st);
      }
    }

    // Siempre verificar el catálogo remoto e instalar extensiones faltantes.
    // El installer omite paquetes ya presentes en DB para no re-descargar.
    await autoInstallBuiltIn();
  }

  /// Descarga e instala todas las extensiones de los repos integrados.
  /// Se puede llamar externamente para reintentar si falló la conexión.
  static Future<void> autoInstallBuiltIn() async {
    _log.info('Auto-instalando desde repositorios integrados...');
    final provider = ExtensionRepoProvider();
    final installer = ExtensionInstaller();

    for (final repoUrl in AppConfig.builtInRepos) {
      try {
        final index = await provider.fetchIndex(repoUrl);
        _log.info('${index.extensions.length} extensiones en $repoUrl');
        for (final dto in index.extensions) {
          try {
            await installer.install(dto);
            _log.info('Instalada: ${dto.package} v${dto.version}');
          } catch (e) {
            _log.warning('Error instalando ${dto.package}: $e');
          }
        }
      } catch (e) {
        _log.warning('No se pudo conectar con $repoUrl: $e');
      }
    }
  }
}
