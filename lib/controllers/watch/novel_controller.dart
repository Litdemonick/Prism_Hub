import 'package:flutter/scheduler.dart';
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

  // Capítulo nuevo: no se hace caso a las posiciones hasta que la lista del
  // capítulo nuevo esté montada (ver ComicController._ignorarPosiciones).
  bool _ignorarPosiciones = false;

  @override
  void onInit() {
    super.onInit();
    fontSize.value = PrismHubStorage.getSetting(SettingKey.novelFontSize);

    // Mismo blindaje que en ComicController — ver el comentario largo de allá.
    // Acá no se llegó a reportar, pero el patrón es idéntico (mismo paquete,
    // mismo listener compartido entre capítulos) así que se cubre igual.
    itemPositionsListener.itemPositions.addListener(() {
      if (_ignorarPosiciones) return;
      final posiciones = itemPositionsListener.itemPositions.value;
      if (posiciones.isEmpty) {
        return;
      }
      // `itemPositions` no viene ordenado: `.first` daba cualquiera de los
      // párrafos visibles, no el de arriba.
      var arriba = -1;
      for (final p in posiciones) {
        if (p.itemTrailingEdge <= 0) continue;
        if (arriba == -1 || p.index < arriba) arriba = p.index;
      }
      if (arriba < 0) return;
      // Los dos de más son el título y el subtítulo (ver el itemCount de
      // novel_reader_content).
      final total = (watchData.value?.content.length ?? 0) + 2;
      if (total > 2 && arriba > total - 1) return;
      positions.value = arriba;
    });
    addWorker(ever(
      fontSize,
      (callback) =>
          PrismHubStorage.setSetting(SettingKey.novelFontSize, callback),
    ));

    // 切换章节时重置页码
    addWorker(ever(index, (callback) {
      _ignorarPosiciones = true;
      positions.value = 0;
    }));

    // Se vuelve a escuchar un frame después de que llegó el capítulo nuevo.
    addWorker(ever(super.watchData, (data) {
      if (data == null) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _ignorarPosiciones = false;
      });
    }));

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
