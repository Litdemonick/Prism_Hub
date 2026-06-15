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
        final currentPackages = index.extensions.map((e) => e.package).toSet();

        for (final dto in index.extensions) {
          try {
            // force: true → re-descarga siempre la versión más reciente del repo
            // oficial (es liviano: bundles de pocas KB). Garantiza que los
            // arreglos lleguen al dispositivo sin depender de la versión local
            // ni del caché. Junto al cache-buster, elimina las extensiones viejas.
            await installer.install(dto, force: true);
            _log.info('Instalada: ${dto.package} v${dto.version}');
          } catch (e) {
            _log.warning('Error instalando ${dto.package}: $e');
          }
        }

        // Limpiar extensiones "zombis": las que se instalaron desde el repo
        // oficial pero ya no están en el índice (se eliminaron de prism+).
        // Sin esto quedan en la DB spammeando errores de red al arrancar.
        await _removeStaleBuiltIns(repoUrl, currentPackages, installer);
      } catch (e) {
        _log.warning('No se pudo conectar con $repoUrl: $e');
      }
    }
  }

  /// Desinstala las extensiones que vinieron del repo oficial pero ya no figuran
  /// en su índice. No toca extensiones de repos agregados por el usuario.
  static Future<void> _removeStaleBuiltIns(
    String repoUrl,
    Set<String> currentPackages,
    ExtensionInstaller installer,
  ) async {
    final installed = await DatabaseService.db.extensionModels
        .filter()
        .isInstalledEqualTo(true)
        .findAll();

    for (final ext in installed) {
      final fromThisRepo = ext.repoUrl == repoUrl;
      if (fromThisRepo && !currentPackages.contains(ext.package)) {
        try {
          await installer.uninstall(ext);
          _log.info('Extensión zombi eliminada: ${ext.package}');
        } catch (e) {
          _log.warning('No se pudo eliminar ${ext.package}: $e');
        }
      }
    }
  }
}
