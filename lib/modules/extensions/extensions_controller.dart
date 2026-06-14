import 'package:get/get.dart';
import 'package:isar/isar.dart';
import 'package:logging/logging.dart';

import '../../core/db/database_service.dart';
import '../../core/utils/app_storage.dart';
import '../../data/models/extension_dto.dart';
import '../../data/models/extension_model.dart';
import '../../data/providers/extension_repo_provider.dart';
import '../../data/services/extension/extension_installer.dart';

class ExtensionsController extends GetxController {
  final _installer = ExtensionInstaller();
  final _repoProvider = ExtensionRepoProvider();
  static final _log = Logger('ExtensionsController');

  final installed = <ExtensionModel>[].obs;
  final available = <ExtensionDto>[].obs;
  final repos = <String>[].obs;

  final isLoadingInstalled = false.obs;
  final isLoadingAvailable = false.obs;

  // Packages en proceso (install/uninstall/update)
  final busyPackages = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    repos.value = AppStorage.getStringList(StorageKey.extensionRepos);
    _loadInstalled();
    fetchAvailable();
  }

  // ---------------------------------------------------------------------------
  // Carga

  Future<void> _loadInstalled() async {
    isLoadingInstalled.value = true;
    try {
      installed.value = await DatabaseService.db.extensionModels
          .filter()
          .isInstalledEqualTo(true)
          .findAll();
    } finally {
      isLoadingInstalled.value = false;
    }
  }

  Future<void> fetchAvailable() async {
    if (repos.isEmpty) {
      available.clear();
      return;
    }
    isLoadingAvailable.value = true;
    final all = <ExtensionDto>[];
    for (final url in repos) {
      try {
        final index = await _repoProvider.fetchIndex(url);
        all.addAll(index.extensions);
      } catch (e) {
        _log.warning('Error al obtener repo $url: $e');
        Get.snackbar('Error de red', 'No se pudo acceder a:\n$url');
      }
    }
    available.value = all;
    isLoadingAvailable.value = false;
  }

  // ---------------------------------------------------------------------------
  // Acciones

  Future<void> install(ExtensionDto dto) async {
    busyPackages.add(dto.package);
    try {
      await _installer.install(dto);
      await _loadInstalled();
      Get.snackbar('Instalada', '${dto.name} instalada correctamente');
    } catch (e) {
      _log.severe('Error instalando ${dto.package}', e);
      Get.snackbar('Error', 'No se pudo instalar ${dto.name}');
    } finally {
      busyPackages.remove(dto.package);
    }
  }

  Future<void> uninstall(ExtensionModel ext) async {
    busyPackages.add(ext.package);
    try {
      await _installer.uninstall(ext);
      await _loadInstalled();
      Get.snackbar('Desinstalada', '${ext.name} eliminada');
    } catch (e) {
      _log.severe('Error desinstalando ${ext.package}', e);
      Get.snackbar('Error', 'No se pudo desinstalar ${ext.name}');
    } finally {
      busyPackages.remove(ext.package);
    }
  }

  Future<void> updateExtension(ExtensionDto dto) async {
    busyPackages.add(dto.package);
    try {
      await _installer.update(dto);
      await _loadInstalled();
      Get.snackbar('Actualizada', '${dto.name} actualizada a v${dto.version}');
    } catch (e) {
      _log.severe('Error actualizando ${dto.package}', e);
      Get.snackbar('Error', 'No se pudo actualizar ${dto.name}');
    } finally {
      busyPackages.remove(dto.package);
    }
  }

  // ---------------------------------------------------------------------------
  // Repos

  Future<void> addRepo(String url) async {
    final clean = url.trim();
    if (clean.isEmpty || repos.contains(clean)) return;
    repos.add(clean);
    await AppStorage.setStringList(StorageKey.extensionRepos, repos.toList());
    await fetchAvailable();
  }

  Future<void> removeRepo(String url) async {
    repos.remove(url);
    await AppStorage.setStringList(StorageKey.extensionRepos, repos.toList());
    available.removeWhere((e) => e.repoUrl == url);
  }

  // ---------------------------------------------------------------------------
  // Helpers para la UI

  bool isInstalled(String package) =>
      installed.any((e) => e.package == package);

  bool isBusy(String package) => busyPackages.contains(package);

  bool hasUpdate(ExtensionDto dto) {
    final ext = installed.firstWhereOrNull((e) => e.package == dto.package);
    return ext != null && ext.version != dto.version;
  }

  ExtensionModel? installedModel(String package) =>
      installed.firstWhereOrNull((e) => e.package == package);
}
