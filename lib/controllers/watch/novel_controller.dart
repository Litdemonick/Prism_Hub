import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class NovelController extends ReaderController<ExtensionFikushonWatch> {
  NovelController({
    required super.title,
    required super.playList,
    required super.detailUrl,
    required super.playIndex,
    required super.episodeGroupId,
    required super.runtime,
    required super.cover,
    required super.anilistID,
    super.cameFromDetail,
    super.isNsfw,
  });

  // 字体大小
  final fontSize = (18.0).obs;
  final itemPositionsListener = ItemPositionsListener.create();
  final isRecover = false.obs;
  final positions = 0.obs;

  @override
  void onInit() {
    super.onInit();
    fontSize.value = PrismHubStorage.getSetting(SettingKey.novelFontSize);

    itemPositionsListener.itemPositions.addListener(() {
      if (itemPositionsListener.itemPositions.value.isEmpty) {
        return;
      }
      final pos = itemPositionsListener.itemPositions.value.first;
      positions.value = pos.index;
    });
    addWorker(ever(
      fontSize,
      (callback) =>
          PrismHubStorage.setSetting(SettingKey.novelFontSize, callback),
    ));

    // 切换章节时重置页码
    addWorker(ever(index, (callback) => positions.value = 0));

    addWorker(ever(super.watchData, (callback) async {
      if (isRecover.value || callback == null) {
        return;
      }
      isRecover.value = true;
      // 获取上次阅读的页码
      final history = await DatabaseService.getHistoryByPackageAndUrl(
        super.runtime.extension.package,
        super.detailUrl,
      );
      if (history == null ||
          history.progress.isEmpty ||
          episodeGroupId != history.episodeGroupId ||
          history.episodeId != index.value) {
        return;
      }
      positions.value = int.tryParse(history.progress) ?? 0;
    }));
  }

  // Ver ReaderController.saveProgressNow: se vuelca también al pasar a
  // segundo plano, no solo al cerrar el lector.
  @override
  void saveProgressNow() {
    final data = super.watchData.value;
    if (data == null) return;
    super.addHistory(
      positions.value.toString(),
      data.content.length.toString(),
    );
  }

  @override
  void onClose() {
    saveProgressNow();
    super.onClose();
  }
}
