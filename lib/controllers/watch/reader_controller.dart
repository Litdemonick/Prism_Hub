import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/alivio_de_memoria.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/watch_state.dart';

class ReaderController<T> extends GetxController with WidgetsBindingObserver {
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
  // Zona +18: viene de DetailPageController.isNsfw (extensión 100% nsfw, o
  // extensión mixta con la opción "adultos" del filtro seleccionada al
  // buscar). Se copia al History guardado en addHistory() para que ese
  // ítem puntual quede fuera del Continuar normal y solo se vea acá.
  final bool isNsfw;

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
    this.isNsfw = false,
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
  DateTime? _lastControlPanelReset;
  final List<Worker> _workers = [];

  @override
  void onInit() {
    // Antes que nada: mismo camino que ya usa el reproductor de vídeo al
    // entrar (ver VideoPlayerController.onInit) — soltar lo que no se está
    // usando (motores de extensión ociosos, y en un aparato flojo también
    // la caché de portadas) para dejarle la memoria y la CPU al lector, que
    // está por bajar y decodificar página tras página. No hace nada en un
    // aparato con memoria de sobra más que soltar motores ociosos, que no
    // cuesta nada.
    AlivioDeMemoria.soltarAntesDeReproducir();
    WidgetsBinding.instance.addObserver(this);
    getContent();
    addWorker(ever(index, (callback) => getContent()));
    super.onInit();
  }

  // Guardar el progreso SOLO en onClose no alcanzaba: si el usuario apaga la
  // pantalla leyendo y Android mata el proceso en segundo plano, onClose no
  // llega a correr nunca y se pierde por dónde iba. Acá se vuelca apenas la
  // app pasa a segundo plano, que es el último momento garantizado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      saveProgressNow();
    }
  }

  // Cada lector sabe cómo se mide su progreso (página vs. posición de scroll).
  // Vacío acá: los que no lo implementen simplemente no vuelcan nada.
  void saveProgressNow() {}

  void addWorker(Worker worker) {
    _workers.add(worker);
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

  /// La extensión dejó de estar disponible y no hay con qué seguir leyendo.
  ///
  /// Aparte de [error]: ese es "no se pudo cargar, probá de nuevo", y acá
  /// reintentar no sirve de nada. La pantalla lo muestra con un botón de salir
  /// en vez del de reintentar.
  final extensionCaida = RxnString();

  getContent() async {
    // Se comprueba ANTES de pedir nada.
    //
    // Una extensión puede caerse en medio de la lectura: el usuario la
    // desactiva o la borra desde otra pantalla, o el catálogo la marca
    // inestable. Y el chequeo del catálogo tarda en enterarse, así que la app
    // no puede esperar a que alguien más lo detecte. Antes esto salía como un
    // error de carga cualquiera y el lector ofrecía "reintentar" contra algo
    // que ya no existe.
    final motivo =
        ExtensionUtils.motivoNoDisponible(runtime.extension.package);
    if (motivo != null) {
      extensionCaida.value = motivo;
      error.value = motivo.i18n;
      watchData.value = null;
      return;
    }
    try {
      error.value = '';
      extensionCaida.value = null;
      watchData.value = null;
      watchData.value =
          await runtime.watch(cuurentPlayUrl, typeHint: _typeHint) as T;
    } catch (e) {
      // Puede haberse caído JUSTO ahora: se vuelve a mirar antes de echarle la
      // culpa a la red.
      final ahora =
          ExtensionUtils.motivoNoDisponible(runtime.extension.package);
      if (ahora != null) {
        extensionCaida.value = ahora;
        error.value = ahora.i18n;
        return;
      }
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
    final now = DateTime.now();
    if (isShowControlPanel.value &&
        _lastControlPanelReset != null &&
        now.difference(_lastControlPanelReset!) <
            const Duration(milliseconds: 250)) {
      return;
    }
    _lastControlPanelReset = now;
    if (!isShowControlPanel.value) {
      isShowControlPanel.value = true;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      isShowControlPanel.value = false;
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    // showControlPanel() se dispara con solo mover el mouse cerca de los
    // bordes (ver reader_view.dart, onHover) — pasa en casi cualquier
    // sesión de lectura. Sin cancelar acá, si el usuario sale del lector
    // dentro de los 3s siguientes el Timer sigue vivo y dispara después del
    // dispose, escribiendo sobre un Rx de un controller ya cerrado.
    _timer?.cancel();
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
    super.onClose();
  }

  addHistory(String progress, String totalProgress) async {
    // try/catch obligatorio: esto se llama desde onClose y desde el callback
    // de ciclo de vida, o sea desde lugares donde nadie está esperando el
    // Future. Una excepción ahí sería un error asíncrono sin dueño — se ve
    // como que la app "se rompió de la nada" y encima sin mensaje.
    try {
      await _putHistory(progress, totalProgress);
    } catch (e, st) {
      logger.severe('No se pudo guardar el progreso de lectura', e, st);
    }
  }

  Future<void> _putHistory(String progress, String totalProgress) async {
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
        ..cover = cover
        ..isNsfw = isNsfw
        // Al día solo si es el último capítulo Y además lo terminó. Se calcula
        // acá porque es el único momento en que se tiene la lista completa, la
        // posición del usuario y su progreso dentro del capítulo a la vez.
        ..watchState = calcularWatchStateDesdeTexto(
          index: index.value,
          total: playList.length,
          progreso: progress,
          progresoTotal: totalProgress,
        )
        // Referencia para detectar novedades más adelante: cuántos capítulos
        // había cuando el usuario estuvo al día.
        ..knownEpisodeCount = playList.length
        // Abrió el capítulo, así que la novedad ya no es novedad.
        ..newEpisodeLabel = null,
    );
    await HomePageController.refreshAll();
  }
}
