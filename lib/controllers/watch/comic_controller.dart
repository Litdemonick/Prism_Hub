import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/providers/anilist_provider.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

class ComicController extends ReaderController<ExtensionMangaWatch> {
  ComicController({
    required super.title,
    required super.playList,
    required super.detailUrl,
    required super.playIndex,
    required super.episodeGroupId,
    required super.runtime,
    required super.cover,
    required super.anilistID,
  });

  // Only the webtoon/cascade reader mode is supported — page-by-page
  // (standard / rightToLeft) was removed.
  final readType = MangaReadMode.webTonn.obs;

  final currentScale = 1.0.obs;
  // 当前页码
  final currentPage = 0.obs;

  final itemPositionsListener = ItemPositionsListener.create();
  final itemScrollController = ItemScrollController();
  final scrollOffsetController = ScrollOffsetController();

  // 是否已经恢复上次阅读
  final isRecover = false.obs;

  // 是否按下 ctrl

  final isZoom = false.obs;

  @override
  bool get clickPagingEnabled => false;

  @override
  void onInit() {
    itemPositionsListener.itemPositions.addListener(() {
      if (itemPositionsListener.itemPositions.value.isEmpty) {
        return;
      }
      final pos = itemPositionsListener.itemPositions.value.first;
      currentPage.value = pos.index;
    });

    // 如果切换章节，重置当前页码
    ever(super.index, (callback) => currentPage.value = 0);
    ever(super.watchData, (callback) async {
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
      currentPage.value = int.parse(history.progress);
      _jumpPage(currentPage.value);
    });
    super.onInit();
  }

  onKey(KeyEvent event) {
    // 按下 ctrl
    isZoom.value = HardwareKeyboard.instance.isControlPressed;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    // 上下左右都在同一条竖向滚动上翻页
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return previousPage();
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return nextPage();
    }
  }

  _jumpPage(int page) {
    if (itemScrollController.isAttached) {
      itemScrollController.jumpTo(index: page);
    }
  }

  // 下一页
  @override
  void nextPage() {
    final next = currentPage.value + 1;
    final count = watchData.value?.urls.length ?? 0;
    if (next < count && itemScrollController.isAttached) {
      itemScrollController.scrollTo(
        index: next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
  }

  // 上一页
  @override
  void previousPage() {
    final prev = (currentPage.value - 1).clamp(0, 9999);
    if (itemScrollController.isAttached) {
      itemScrollController.scrollTo(
        index: prev,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
  }

  @override
  void onClose() {
    if (super.watchData.value != null) {
      // 获取所有页数量
      final pages = super.watchData.value!.urls.length;
      super.addHistory(
        currentPage.value.toString(),
        pages.toString(),
      );
    }
    if (PrismHubStorage.getSetting(SettingKey.autoTracking) &&
        anilistID != "") {
      AniListProvider.editList(
        status: AnilistMediaListStatus.current,
        progress: playIndex + 1,
        mediaId: anilistID,
      );
    }
    super.onClose();
  }
}
