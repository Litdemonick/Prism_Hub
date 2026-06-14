import 'package:get/get.dart';
import 'package:logging/logging.dart';

import '../../data/models/watch_data.dart';
import '../../data/services/extension/extension_service.dart';

class ReaderController extends GetxController {
  static final _log = Logger('ReaderController');

  final pages = <String>[].obs;
  final currentPage = 0.obs;
  final isLoading = true.obs;
  final error = Rxn<String>();

  Future<void> load(String episodeUrl, String package) async {
    isLoading.value = true;
    error.value = null;

    final rt = ExtensionService.get(package);
    if (rt == null) {
      error.value = 'Extensión no disponible';
      isLoading.value = false;
      return;
    }

    try {
      final raw = await rt.watch(episodeUrl);
      final data = WatchData.fromMap(raw);
      pages.value = data.streams
          .map((s) => s.url)
          .where((u) => u.isNotEmpty)
          .toList();

      if (pages.isEmpty) {
        error.value = 'Sin páginas disponibles';
      }
    } catch (e, st) {
      _log.severe('Error cargando páginas', e, st);
      error.value = 'Error al cargar el capítulo';
    } finally {
      isLoading.value = false;
    }
  }
}
