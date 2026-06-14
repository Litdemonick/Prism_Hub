import 'package:get/get.dart';
import 'package:logging/logging.dart';

import '../../data/models/media_item.dart';
import '../../data/services/extension/extension_service.dart';

class DetailController extends GetxController {
  static final _log = Logger('DetailController');

  final detail = Rxn<MediaDetail>();
  final isLoading = false.obs;
  final error = Rxn<String>();

  Future<void> load(String url, String package) async {
    isLoading.value = true;
    error.value = null;

    final rt = ExtensionService.get(package);
    if (rt == null) {
      error.value = 'Extensión no disponible: $package';
      isLoading.value = false;
      return;
    }

    try {
      final data = await rt.detail(url);
      detail.value = MediaDetail.fromMap(
        data,
        package: package,
        url: url,
        type: rt.extension.type,
      );
    } catch (e) {
      _log.severe('Error en detail($url)', e);
      error.value = 'No se pudo cargar el contenido';
    } finally {
      isLoading.value = false;
    }
  }
}
