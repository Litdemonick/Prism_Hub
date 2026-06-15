import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../../../core/db/database_service.dart';
import '../../../core/utils/app_directory.dart';
import '../../models/extension_dto.dart';
import '../../models/extension_model.dart';
import 'extension_service.dart';

class ExtensionInstaller {
  ExtensionInstaller()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final Dio _dio;
  static final _log = Logger('ExtensionInstaller');

  Future<void> install(ExtensionDto dto, {bool force = false}) async {
    // Omitir si ya está instalada con la misma versión. Si la versión del índice
    // remoto es diferente, reinstalar automáticamente (sin force explícito).
    if (!force) {
      final existing = await DatabaseService.db.extensionModels.getByPackage(
        dto.package,
      );
      if (existing != null && existing.isInstalled) {
        if (existing.version == dto.version) {
          _log.fine('${dto.package} v${dto.version} ya instalada, omitiendo');
          return;
        }
        _log.info(
          '${dto.package}: versión local=${existing.version} '
          '→ remota=${dto.version}, actualizando',
        );
      }
    }

    _log.info('Instalando ${dto.package} v${dto.version}');

    final scriptPath = AppDirectory.extensionScript(dto.package);

    // Descarga el bundle compilado (.js). Cache-buster + no-cache para que la
    // CDN de GitHub no devuelva una versión vieja del script tras una actualización.
    final sep = dto.scriptUrl.contains('?') ? '&' : '?';
    final scriptUrl =
        '${dto.scriptUrl}${sep}_=${DateTime.now().millisecondsSinceEpoch}';
    await _dio.download(
      scriptUrl,
      scriptPath,
      options: Options(
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      ),
    );

    final script = await File(scriptPath).readAsString();

    final model = ExtensionModel()
      ..package = dto.package
      ..name = dto.name
      ..version = dto.version
      ..author = dto.author
      ..type = dto.type
      ..scriptUrl = dto.scriptUrl
      ..iconUrl = dto.iconUrl
      ..repoUrl = dto.repoUrl
      ..localScriptPath = scriptPath
      ..isInstalled = true
      ..installedAt = DateTime.now();

    final db = DatabaseService.db;
    await db.writeTxn(() async {
      final existing = await db.extensionModels.getByPackage(dto.package);
      if (existing != null) await db.extensionModels.delete(existing.id);
      await db.extensionModels.put(model);
    });

    // Carga el runtime inmediatamente (sin reiniciar la app)
    ExtensionService.load(model, script);
    _log.info('${dto.package} instalada');
  }

  Future<void> uninstall(ExtensionModel ext) async {
    _log.info('Desinstalando ${ext.package}');

    ExtensionService.unload(ext.package);

    if (ext.localScriptPath != null) {
      final file = File(ext.localScriptPath!);
      if (await file.exists()) await file.delete();
    }

    await DatabaseService.db.writeTxn(() async {
      await DatabaseService.db.extensionModels.delete(ext.id);
    });

    _log.info('${ext.package} desinstalada');
  }

  Future<void> update(ExtensionDto dto) async {
    _log.info('Actualizando ${dto.package} a v${dto.version}');
    // Desinstalar la versión antigua del runtime (el archivo se sobreescribirá)
    ExtensionService.unload(dto.package);
    await install(dto);
  }
}
