import 'package:get/get.dart';
import 'package:logging/logging.dart';

import '../../data/models/media_item.dart';
import '../../data/services/extension/extension_service.dart';

class ContentSearchController extends GetxController {
  static final _log = Logger('SearchController');

  final results = <MediaItem>[].obs;
  final isSearching = false.obs;
  final lastQuery = ''.obs;
  final selectedPackage = Rxn<String>(); // null = todas las extensiones

  Future<void> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) {
      results.clear();
      lastQuery.value = '';
      return;
    }

    lastQuery.value = q;
    isSearching.value = true;
    results.clear();

    final runtimes = selectedPackage.value != null
        ? [
            ExtensionService.get(selectedPackage.value!),
          ].whereType<ExtensionRuntime>().toList()
        : ExtensionService.allLoaded;

    final batches = await Future.wait(
      runtimes.map((rt) async {
        try {
          final raw = await rt.search(q, 1);
          return raw
              .map(
                (m) => MediaItem.fromMap(
                  m,
                  package: rt.extension.package,
                  type: rt.extension.type,
                ),
              )
              .toList();
        } catch (e) {
          _log.warning('Error buscando en ${rt.extension.package}: $e');
          return <MediaItem>[];
        }
      }),
    );

    results.value = batches.expand((b) => b).toList();
    isSearching.value = false;
  }

  void selectExtension(String? package) {
    selectedPackage.value = package;
    if (lastQuery.isNotEmpty) search(lastQuery.value);
  }
}
