import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/providers/anilist_provider.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:prismhub/utils/log.dart';
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
    super.cameFromDetail,
    super.isNsfw,
  });

  // Modo de lectura. webTonn = cascada vertical continua (por defecto, es lo
  // natural para manhwa/webtoon); standard y rightToLeft = página a página
  // horizontal, como un manga tradicional (rightToLeft invierte el sentido,
  // que es como se leen los manga japoneses). Se guarda POR TÍTULO en la
  // base (ver DatabaseService.setMangaReaderType), así cada obra recuerda
  // cómo la venís leyendo.
  final readType = MangaReadMode.webTonn.obs;

  bool get isPaged => readType.value != MangaReadMode.webTonn;

  /// Llenar la pantalla con la página, recortando lo que sobre en vez de
  /// dejarla entera con franjas — mismo concepto que
  /// VideoPlayerController.llenarPantalla, para el lector.
  ///
  /// Solo cambia algo en modo paginado (manga/manhwa página a página): en
  /// la cascada las imágenes ya llenan el ancho por diseño (BoxFit.fitWidth,
  /// ver ComicReaderContent), así que no hay franjas que recortar ahí.
  ///
  /// Por sesión y no guardado por título, mismo criterio que el video: es
  /// una decisión de "esta página puntual", no una preferencia permanente.
  final llenarPantalla = false.obs;

  // UNO solo para toda la vida del lector. Antes se recreaba en cada cambio
  // de modo/capítulo para poder fijar initialPage, y eso traía un bug feo:
  // el controller nuevo se creaba FUERA del ciclo de construcción, así que
  // el PageView podía seguir usando el viejo y el nuevo quedaba sin
  // conectar — al tocar las flechas saltaba "PageController is not attached
  // to a PageView" y no cambiaba de página (confirmado en vivo). Se
  // reposiciona con jumpToPage, que no necesita recrear nada.
  final pageController = PageController();

  Future<void> setReadMode(MangaReadMode mode) async {
    if (mode == readType.value) return;
    readType.value = mode;
    _animatingTo = null;
    await DatabaseService.setMangaReaderType(detailUrl, mode);
    // En ambos sentidos hay que reposicionar DESPUÉS de que el widget nuevo
    // (PageView o lista de cascada) se haya montado — antes de eso ninguno
    // de los dos controllers está conectado todavía.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isPaged) {
        _gotoPage(currentPage.value);
      } else {
        _jumpPage(currentPage.value);
      }
    });
  }

  // Reposiciona el PageView sin animación. Silencioso si todavía no está
  // montado — el llamador siempre lo hace tras un frame, pero cambiar de
  // capítulo puede dejar un instante sin PageView vivo.
  void _gotoPage(int page) {
    _animatingTo = null;
    if (!pageController.hasClients) return;
    try {
      pageController.jumpToPage(page);
    } catch (e) {
      logger.warning('ComicController._gotoPage($page) falló: $e');
    }
  }

  final currentScale = 1.0.obs;
  // 当前页码
  final currentPage = 0.obs;

  // ── Dónde se pega la franja cuando sobra ancho ──────────────────────────
  //
  // 'izquierda' · 'centro' (de fábrica) · 'derecha'. Aplica a los dos sitios
  // donde la franja no llena la pantalla: la cascada y la tira de manhwa
  // dentro del modo paginado. Se guarda global (ver SettingKey.mangaStripAlign).
  static const alineacionIzquierda = 'izquierda';
  static const alineacionCentro = 'centro';
  static const alineacionDerecha = 'derecha';

  final stripAlign = alineacionCentro.obs;

  Future<void> setStripAlign(String valor) async {
    if (valor == stripAlign.value) return;
    stripAlign.value = valor;
    await PrismHubStorage.setSetting(SettingKey.mangaStripAlign, valor);
  }

  final itemPositionsListener = ItemPositionsListener.create();
  final itemScrollController = ItemScrollController();
  final scrollOffsetController = ScrollOffsetController();

  // 是否已经恢复上次阅读
  final isRecover = false.obs;

  // 是否按下 ctrl

  final isZoom = false.obs;

  @override
  // En cascada no (ahí el clic solo muestra/oculta el panel). En paginado sí:
  // la capa de toque de ReaderView está POR ENCIMA del contenido, así que es
  // la única que puede recibir el clic de forma confiable — cuando las
  // flechas intentaban manejarlo ellas mismas, el clic caía en esa capa de
  // arriba y abría el panel de opciones en vez de pasar de página
  // (confirmado en vivo en modo derecha→izquierda). Las flechas quedan como
  // indicador visual (ver _PageArrow, va dentro de un IgnorePointer) y el
  // clic lo maneja solo ReaderView, así nunca se cuenta dos veces.
  bool get clickPagingEnabled => isPaged;

  // Capítulo nuevo: se deja de hacer caso a lo que avise la lista hasta que la
  // del capítulo NUEVO esté montada.
  //
  // Por qué hace falta (reportado en vivo: "al cambiar de capítulo y hacer
  // scroll rápido hacia abajo, salta y se va hasta abajo del manhwa"):
  //
  //   1. Venías leyendo la página 40 → currentPage = 40.
  //   2. Cambiás de capítulo: acá abajo se pone currentPage = 0 y getContent()
  //      vacía watchData, así que la lista del capítulo viejo se destruye.
  //   3. Al desarmarse todavía dispara posiciones con los índices VIEJOS, y
  //      este listener volvía a escribir currentPage = 40.
  //   4. Llega el capítulo nuevo y la lista se arma con initialScrollIndex 40.
  //      Si el capítulo nuevo es más corto, scrollable_positioned_list clampea
  //      al último ítem — y el capítulo abre AL FONDO.
  //
  // Scrollear rápido lo hace mucho más probable porque deja más avisos de
  // posición encolados justo cuando se cambia de capítulo.
  bool _ignorarPosiciones = false;

  @override
  void onInit() {
    itemPositionsListener.itemPositions.addListener(() {
      if (_ignorarPosiciones) return;
      final posiciones = itemPositionsListener.itemPositions.value;
      if (posiciones.isEmpty) {
        return;
      }
      // `itemPositions` NO viene ordenado — lo dice el propio paquete. Con
      // `.first` salía cualquiera de las páginas visibles, no la de arriba, y
      // en cascada hay varias a la vez (minCacheExtent 3000). De ahí que el
      // contador de página y el pulgar de la barra saltaran solos.
      var arriba = -1;
      for (final p in posiciones) {
        // Ya pasó del todo por arriba del borde: no es la que se está leyendo.
        if (p.itemTrailingEdge <= 0) continue;
        if (arriba == -1 || p.index < arriba) arriba = p.index;
      }
      if (arriba < 0) return;
      // Sobrante de un capítulo más largo: no puede quedar apuntando fuera.
      final total = watchData.value?.urls.length ?? 0;
      if (total > 0 && arriba > total - 1) return;
      currentPage.value = arriba;
    });

    // Modo guardado de ESTE título (si nunca se eligió, queda webtoon).
    DatabaseService.getMnagaReaderType(detailUrl, MangaReadMode.webTonn)
        .then((mode) {
      readType.value = mode;
    });

    // Alineación guardada. Si el ajuste viniera vacío o con algo que no
    // reconocemos, queda centrado — que es como venía siendo siempre.
    final alineacionGuardada =
        PrismHubStorage.getSetting(SettingKey.mangaStripAlign);
    if (alineacionGuardada == alineacionIzquierda ||
        alineacionGuardada == alineacionDerecha) {
      stripAlign.value = alineacionGuardada as String;
    }

    // 如果切换章节，重置当前页码
    addWorker(ever(super.index, (callback) {
      _ignorarPosiciones = true;
      currentPage.value = 0;
      // Capítulo nuevo: volver a la primera página, después de que el
      // PageView del capítulo nuevo esté montado.
      if (isPaged) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _gotoPage(0));
      }
    }));

    // Se vuelve a escuchar recién cuando el capítulo nuevo ya tiene con qué
    // montarse, y un frame después: para entonces la lista vieja ya no existe
    // y lo que avise la posición es de la lista nueva. Va ANTES del worker de
    // recuperación de progreso a propósito — ése escribe currentPage a mano,
    // no por este listener, así que no lo pisa.
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
      currentPage.value = int.tryParse(history.progress) ?? 0;
      // Modo paginado: mismo criterio que la cascada — saltar recién después
      // del frame en que el PageView ya montó, si no el controller todavía
      // no está conectado.
      if (isPaged) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _gotoPage(currentPage.value);
        });
        return;
      }
      // Confirmado en vivo (intermitente — "a veces"): llamar jumpTo acá
      // directo carrereaba con el propio primer build de
      // ScrollablePositionedList (el Obx de comic_reader_content recién
      // está montando la lista para ESTE mismo watchData) — a veces el
      // controller ya figuraba "isAttached" pero el estado interno del
      // paquete todavía no estaba listo para recibir jumpTo, y volaba la
      // assertion '_scrollableListState == null' (scrollable_positioned_list
      // no tolera un jumpTo mientras el attach/attach anterior sigue en
      // curso). Postergarlo a después del frame en que la lista ya montó
      // le da tiempo real a asentarse antes de tocarlo.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _jumpPage(currentPage.value);
      });
    }));
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
    if (!itemScrollController.isAttached) return;
    try {
      itemScrollController.jumpTo(index: page);
    } catch (e) {
      // Red de seguridad: si igual se pierde la carrera contra el propio
      // attach de la lista, que se quede en la página 0 en vez de tirar
      // abajo todo el lector.
      logger.warning('ComicController._jumpPage($page) falló: $e');
    }
  }

  // Página a la que se está animando ahora mismo en modo paginado. Sin esto,
  // varios disparos seguidos del mismo clic (la capa de toque de ReaderView
  // puede emitir más de un evento, y el teclado repite al mantener apretado)
  // se acumulaban: cada uno leía currentPage YA actualizado por la animación
  // anterior y sumaba otra página encima — de ahí el salto de 6-7 páginas de
  // un solo clic, confirmado en vivo. Con esto, cada avance parte del último
  // destino pedido y se ignora lo que llegue mientras la animación corre.
  int? _animatingTo;

  void _animateToPage(int target) {
    final controller = pageController;
    // hasClients: animateToPage tira una assertion si el PageView todavía no
    // montó (o ya se fue) — pasaba al tocar las flechas justo en ese
    // instante. Salir en silencio es correcto: no hay nada que animar.
    if (!controller.hasClients) return;
    // Ya se está yendo a esa misma página: no reencolar otra animación.
    if (_animatingTo == target) return;
    _animatingTo = target;
    controller
        .animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    )
        .whenComplete(() {
      // Solo limpiar si sigue siendo ESTE destino — si mientras tanto se
      // pidió otro, ese es el que manda.
      if (_animatingTo == target) _animatingTo = null;
    });
  }

  // 下一页
  @override
  void nextPage() {
    final count = watchData.value?.urls.length ?? 0;
    if (isPaged) {
      // Base = destino en curso (si hay) en vez de la página actual: así dos
      // clics rápidos avanzan 1 y 2, no 1 y 1.
      final base = _animatingTo ?? currentPage.value;
      final target = base + 1;
      if (target >= count) return;
      _animateToPage(target);
      return;
    }
    final next = currentPage.value + 1;
    if (next >= count) return;
    if (itemScrollController.isAttached) {
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
    if (isPaged) {
      // Misma protección que nextPage (ver _animatingTo).
      final base = _animatingTo ?? currentPage.value;
      final target = base - 1;
      if (target < 0) return;
      _animateToPage(target);
      return;
    }
    final prev = (currentPage.value - 1).clamp(0, 9999);
    if (itemScrollController.isAttached) {
      itemScrollController.scrollTo(
        index: prev,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
  }

  // Mismo guardado que hacía onClose, ahora en un método propio para que el
  // ciclo de vida (pantalla apagada / app en segundo plano) pueda volcarlo
  // sin esperar a que se cierre el lector — ver ReaderController.
  @override
  void saveProgressNow() {
    final data = super.watchData.value;
    if (data == null) return;
    super.addHistory(
      currentPage.value.toString(),
      data.urls.length.toString(),
    );
  }

  @override
  void onClose() {
    pageController.dispose();
    saveProgressNow();
    if (PrismHubStorage.getSetting(SettingKey.autoTracking) == true &&
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
