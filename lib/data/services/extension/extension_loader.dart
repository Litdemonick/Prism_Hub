import 'dart:io';

import 'package:isar/isar.dart';
import 'package:logging/logging.dart';

import '../../../core/db/database_service.dart';
import '../../models/extension_model.dart';
import 'extension_service.dart';

/// Carga al inicio todas las extensiones instaladas desde disco.
abstract final class ExtensionLoader {
  static final _log = Logger('ExtensionLoader');

  static Future<void> loadAll() async {
    final installed = await DatabaseService.db.extensionModels
        .filter()
        .isInstalledEqualTo(true)
        .findAll();

    _log.info('Cargando ${installed.length} extensiones instaladas');

    for (final ext in installed) {
      if (ext.localScriptPath == null) continue;
      final file = File(ext.localScriptPath!);
      if (!await file.exists()) {
        _log.warning(
          'Bundle no encontrado: ${ext.package} → ${ext.localScriptPath}',
        );
        continue;
      }
      try {
        final script = await file.readAsString();
        ExtensionService.load(ext, script);
      } catch (e, st) {
        _log.severe('Error cargando ${ext.package}', e, st);
      }
    }
  }
}
