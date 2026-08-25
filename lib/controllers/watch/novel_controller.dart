import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/comportamiento_sistema_tv.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
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

  /// Leer sin la barra de estado ni la de navegación del teléfono, para que
  /// el texto use todo el alto — mismo botón y mismo comportamiento que en el
  /// lector de cómics (ver ComicController.llenarPantalla).
  ///
  /// Acá no recorta ni reescala nada: el texto ya usa todo el ancho y el
  /// tamaño lo maneja su propio deslizador. Lo único que hace es ganar el
  /// alto de las dos barras.
  ///
  /// Por sesión y no guardado por título, mismo criterio que en cómics.
  final llenarPantalla = false.obs;

  /// Barras del sistema según "llenar pantalla".
  ///
  /// `immersiveSticky` y NO `edgeToEdge`: con edgeToEdge el contenido llega a
  /// los bordes pero las dos barras SIGUEN VISIBLES encima — se reportó en
  /// vivo con captura en el lector de cómics, donde este mismo método ya está
  /// funcionando bien. Vuelven solas si se desliza desde el borde, sin sacar
  /// al lector del modo.
  /// Y el ESTILO después del modo: `setEnabledSystemUIMode` reinicia el color
  /// de los iconos del sistema a los de Android, que son claros. Sin volver a
  /// pedirlo, con el modo claro puesto quedaban blancos sobre una barra casi
  /// blanca y la de arriba se veía vacía. Misma trampa que en
  /// ComicController._actualizarPantallaCompletaAndroid.
  void _actualizarPantallaCompletaAndroid(bool activo) {
    if (activo) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      restaurarBarrasDelSistema();
    }
    ModoDeColor.aplicarBarrasDelSistema();
  }

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

    if (Platform.isAndroid) {
      addWorker(ever(llenarPantalla, _actualizarPantallaCompletaAndroid));
    }

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
    // Si se salió con "llenar pantalla" prendido, las barras quedaron
    // escondidas — sin esto la pantalla de atrás se quedaba sin hora ni
    // barra de navegación hasta reiniciar la app.
    if (Platform.isAndroid && llenarPantalla.value) {
      restaurarBarrasDelSistema();
      // Y el estilo, por lo mismo de arriba: sin esto se salía del lector con
      // los iconos del sistema en claro, invisibles con el modo claro puesto.
      ModoDeColor.aplicarBarrasDelSistema();
    }
    saveProgressNow();
    super.onClose();
  }
}
