import 'dart:async';

import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/error.dart';

class ReaderController<T> extends GetxController {
  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playIndex;
  final int episodeGroupId;
  final ExtensionService runtime;
  final String? cover;
  final String anilistID;
  // True cuando el lector se abrió desde la página de detalle (goWatch) —
  // en ese caso ya hay un DetailPage de este mismo título debajo en la
  // pila de navegación, y el botón "Ver detalle" (control_panel_header.dart)
  // solo necesita cerrar el lector para revelarlo, no abrir uno nuevo.
  // False cuando se entra por otro lado que NO deja un detalle debajo (ej.
  // "Continuar viendo" desde Home/Historial, ver resume_history.dart) —
  // ahí sí hace falta abrir un detalle nuevo, o "Ver detalle" no llevaría
  // a ningún lado.
  final bool cameFromDetail;

  ReaderController({
    required this.title,
    required this.playList,
    required this.detailUrl,
    required this.playIndex,
    required this.episodeGroupId,
    required this.runtime,
    required this.anilistID,
    this.cover,
    this.cameFromDetail = false,
  });

  // Tag único para Get.put/Get.find/Get.delete — antes se usaba solo
  // `title` (ver VideoPlayerController, mismo bug ya corregido ahí): si dos
  // capítulos del mismo título se abren en sucesión rápida, el segundo
  // Get.put(tag: title) pisa el registro del primero en el contenedor de
  // GetX, y cuando el widget VIEJO recién dispone (dispose puede llegar
  // tarde por la transición/animación) borra el controller del NUEVO lector
  // en vez del propio. El lector que quedó en pantalla se queda sin
  // controller registrado — de ahí lecturas/tirones raros al entrar y
  // volver a entrar seguido.
  static String buildTag(String title, String detailUrl, int episodeGroupId) {
    return '$title|$detailUrl|$episodeGroupId';
  }

  late Rx<T?> watchData = Rx(null);
  final error = ''.obs;
  final isShowControlPanel = false.obs;
  late final index = playIndex.obs;
  get cuurentPlayUrl => playList[index.value].url;
  Timer? _timer;

  @override
  void onInit() {
    getContent();
    ever(index, (callback) => getContent());
    super.onInit();
  }

  // Solo hace falta para una extensión "mixed" (ExtensionService.watch()
  // no puede adivinar manga-vs-fikushon desde su tipo fijo ahí) — este
  // reader SOLO se instancia para lectura, nunca para video, así que T ya
  // deja saber cuál de los dos es sin que el llamador tenga que pasarlo.
  ExtensionType? get _typeHint {
    if (T == ExtensionMangaWatch) return ExtensionType.manga;
    if (T == ExtensionFikushonWatch) return ExtensionType.fikushon;
    return null;
  }

  getContent() async {
    try {
      error.value = '';
      watchData.value = null;
      watchData.value =
          await runtime.watch(cuurentPlayUrl, typeHint: _typeHint) as T;
    } catch (e) {
      error.value = friendlyError(e);
    }
  }

  void previousPage() {}

  void nextPage() {}

  // Whether clicking the left/right thirds of the screen should page
  // forward/back (see ReaderView's tap-zone overlay). Readers with a
  // continuous-scroll mode (e.g. comic's webtoon/cascade) should disable
  // this — there's no discrete "page" to jump to on click there, and the
  // overlay firing on top of the content's own gestures causes erratic jumps.
  bool get clickPagingEnabled => true;

  showControlPanel() {
    isShowControlPanel.value = true;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      isShowControlPanel.value = false;
    });
  }

  @override
  void onClose() {
    // showControlPanel() se dispara con solo mover el mouse cerca de los
    // bordes (ver reader_view.dart, onHover) — pasa en casi cualquier
    // sesión de lectura. Sin cancelar acá, si el usuario sale del lector
    // dentro de los 3s siguientes el Timer sigue vivo y dispara después del
    // dispose, escribiendo sobre un Rx de un controller ya cerrado.
    _timer?.cancel();
    super.onClose();
  }

  addHistory(String progress, String totalProgress) async {
    await DatabaseService.putHistory(
      History()
        ..url = detailUrl
        ..episodeId = index.value
        // _typeHint ya resuelve manga-vs-fikushon por T (ver getContent()) —
        // sin esto, una extensión "mixed" guardaría el literal "mixed" en el
        // historial, que ExtensionTypeBadge/typeToString no saben mostrar.
        ..type = _typeHint ?? runtime.extension.type
        ..episodeGroupId = episodeGroupId
        ..package = runtime.extension.package
        ..episodeTitle = playList[index.value].name
        ..title = title
        ..progress = progress
        ..totalProgress = totalProgress
        ..cover = cover,
    );
    await Get.find<HomePageController>().onRefresh();
  }
}
