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
    sections.value     = [];

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

    // Cada extensión carga independientemente: la UI muestra cada sección
    // en cuanto llega sin esperar a las que fallen o tarden más.
    var remaining = runtimes.length;

    void onDone() {
      remaining--;
      if (remaining <= 0) {
        if (sections.isEmpty) noConnection.value = true;
        isLoading.value = false;
      }
    }

    for (final rt in runtimes) {
      rt.latest(1).then((raw) {
        if (raw.isNotEmpty) {
          sections.add(HomeSection(
            extensionName: rt.extension.name,
            package:       rt.extension.package,
            items: raw
                .map((m) => MediaItem.fromMap(
                      m,
                      package: rt.extension.package,
                      type:    rt.extension.type,
                    ))
                .toList(),
          ));
        }
        onDone();
      }).catchError((Object e) {
        _log.warning('Error en latest() de ${rt.extension.package}: $e');
        onDone();
      });
    }
  }
}
