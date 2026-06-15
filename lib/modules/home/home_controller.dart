import 'package:get/get.dart';
import 'package:logging/logging.dart';

import '../../data/models/media_item.dart';
import '../../data/services/extension/extension_loader.dart';
import '../../data/services/extension/extension_service.dart';

class HomeController extends GetxController {
  static final _log = Logger('HomeController');

  final sections     = <HomeSection>[].obs;
  final isLoading    = false.obs;
  final noConnection = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadLatest();
  }

  Future<void> loadLatest() async {
    isLoading.value    = true;
    noConnection.value = false;

    // Si Prism+ no está cargado aún, intentar instalarlo ahora
    if (!ExtensionService.hasAny) {
      await ExtensionLoader.autoInstallBuiltIn();
    }

    final runtimes = ExtensionService.allLoaded;
    if (runtimes.isEmpty) {
      noConnection.value = true;
      isLoading.value    = false;
      return;
    }

    // Carga en paralelo para mejor rendimiento
    final futures = runtimes.map((rt) async {
      try {
        final raw = await rt.latest(1);
        if (raw.isEmpty) return null;
        return HomeSection(
          extensionName: rt.extension.name,
          package:       rt.extension.package,
          items: raw
              .map(
                (m) => MediaItem.fromMap(
                  m,
                  package: rt.extension.package,
                  type:    rt.extension.type,
                ),
              )
              .toList(),
        );
      } catch (e) {
        _log.warning('Error en latest() de ${rt.extension.package}: $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    sections.value  = results.whereType<HomeSection>().toList();
    isLoading.value = false;
  }
}
