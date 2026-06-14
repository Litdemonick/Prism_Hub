import 'package:get/get.dart';
import 'package:logging/logging.dart';

import '../../data/models/media_item.dart';
import '../../data/services/extension/extension_service.dart';

class HomeController extends GetxController {
  static final _log = Logger('HomeController');

  final sections = <HomeSection>[].obs;
  final isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadLatest();
  }

  Future<void> loadLatest() async {
    isLoading.value = true;

    final runtimes = ExtensionService.allLoaded;
    final result = <HomeSection>[];

    for (final rt in runtimes) {
      try {
        final raw = await rt.latest(1);
        if (raw.isNotEmpty) {
          result.add(
            HomeSection(
              extensionName: rt.extension.name,
              package: rt.extension.package,
              items: raw
                  .map(
                    (m) => MediaItem.fromMap(
                      m,
                      package: rt.extension.package,
                      type: rt.extension.type,
                    ),
                  )
                  .toList(),
            ),
          );
        }
      } catch (e) {
        _log.warning('Error en latest() de ${rt.extension.package}: $e');
      }
    }

    sections.value = result;
    isLoading.value = false;
  }
}
