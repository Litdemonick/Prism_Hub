import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/comic_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/watch/aviso_extension_caida.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ComicReaderContent extends StatefulWidget {
  const ComicReaderContent(this.tag, {super.key});
  final String tag;

  @override
  State<ComicReaderContent> createState() => _ComicReaderContentState();
}

class _ComicReaderContentState extends State<ComicReaderContent> {
  @override
  void initState() {
    super.initState();
    // Defer to post-frame: setting an Rx value during initState (which runs
    // inside the parent Obx's build phase) triggers markNeedsBuild on an
    // already-building widget, causing a Flutter assertion error.
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.isShowControlPanel.value = true;
      });
    }
  }

  // Antes se creaba un FocusNode() nuevo en cada build (el zoom/pinch en
  // Android dispara setState seguido) sin disponerlo nunca — leak de
  // FocusNode acumulándose en cada interacción durante una sesión de
  // lectura larga. Uno solo, creado acá y liberado en dispose().
  final _keyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _cascadeScrollPosition = null;
    _androidPinchTransform.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  late final _c = Get.find<ComicController>(tag: widget.tag);

  // Precarga hacia adelante: además de agrandar el cache extent de la lista
  // (que adelanta el BUILD), se mete en el caché de imágenes las próximas
  // páginas aunque estén lejos de construirse. Así el lector se siente fluido
  // en vez de mostrar el placeholder en cada página nueva.
  //
  // Se usa el MISMO ExtendedNetworkImageProvider con cache:true que usa
  // CacheNetWorkImagePic para dibujar (ver _resolveAspect), así la precarga y
  // el dibujado comparten entrada de caché y nunca hay una segunda descarga
  // del mismo archivo.
  static const _precacheAhead = 4;
  int _lastPrecachedFrom = -1;
  final Set<String> _precached = {};

  void _precacheAround(List<String> images, int index) {
    if (images.isEmpty) return;
    // Una sola vez por página: itemPositions dispara muy seguido mientras se
    // scrollea y no hace falta reintentar lo ya pedido.
    if (_lastPrecachedFrom == index) return;
    _lastPrecachedFrom = index;
    final headers = _c.watchData.value?.headers;
    final end = (index + _precacheAhead).clamp(0, images.length - 1);
    for (var i = index; i <= end; i++) {
      final url = images[i];
      if (!_precached.add(url)) continue;
      // Best-effort: un fallo acá no debe romper la lectura — la imagen se
      // vuelve a pedir cuando la lista la construya de verdad.
      //
      // El listener se SACA al resolver (igual que hace precacheImage de
      // Flutter): dejarlo puesto mantendría vivo el ImageStream de cada
      // página precargada para toda la sesión, que en un capítulo largo es
      // una fuga de memoria seria.
      final stream =
          ExtendedNetworkImageProvider(url, headers: headers, cache: true)
              .resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, __) => stream.removeListener(listener),
        onError: (_, __) {
          stream.removeListener(listener);
          // Se saca del set así un reintento posterior puede volver a pedirla.
          _precached.remove(url);
        },
      );
      stream.addListener(listener);
    }
  }

  // Tracked by NotificationListener so border wheel-forwarding knows
  // the current absolute pixel offset without needing a ScrollController.
  double _cascadeScrollOffset = 0;
  double _cascadeScrollMax = double.maxFinite;

  // Captured from a ScrollNotification's context (see scrollList below) so
  // border-forwarded wheel scroll can call jumpTo() directly — a true
  // synchronous position set, with no animation machinery involved at all.
  // ScrollOffsetController only
  // exposes an animate-based API; even at a 1ms duration that still runs
  // through a Ticker-driven DrivenScrollActivity, which costs at least one
  // frame and gets restarted by every new event during a fast, rapid-fire
  // scroll — visibly lagging behind the instant, un-animated jumpTo the
  // native Scrollable itself uses when the mouse is over the content.
  ScrollPosition? _cascadeScrollPosition;
  // Identidad del capítulo actualmente mostrado — cuando cambia (nuevo
  // objeto watchData al pasar de capítulo), ScrollablePositionedList arma un
  // Scrollable interno nuevo y _cascadeScrollPosition queda apuntando al
  // viejo. Se limpia acá mismo así el próximo intento de scroll desde
  // afuera usa el fallback animado (ver _forwardBorderWheelScroll) en vez de
  // quedarse pegado a una referencia vieja hasta que llegue una notificación
  // de scroll real que la refresque sola.
  Object? _lastWatchData;
  // Último modo de lectura visto — ver el chequeo en _buildContent: cambiar
  // de modo también invalida el Scrollable de la cascada.
  MangaReadMode? _lastReadType;

  // Android-only: controls pinch-to-zoom scale in the cascade InteractiveViewer.
  final _androidPinchTransform = TransformationController();
  // Android-only: raw pointer count so the inner list's scroll physics can
  // be disabled the instant a 2nd finger touches down. Without this, the
  // vertical drag recognizer races the pinch-scale gesture and both move the
  // content at once, making zoom appear to jump to a different reading
  // position. Uses plain setState (not GetX Rx) so it applies immediately,
  // before the gesture arena resolves — a reactive round-trip here would
  // reintroduce the "missed gesture start" issue this screen already had.
  final Set<int> _androidPointers = {};
  bool get _androidPinching => _androidPointers.length >= 2;

  void _onAndroidPointerDown(PointerDownEvent event) {
    setState(() => _androidPointers.add(event.pointer));
  }

  void _onAndroidPointerUp(PointerEvent event) {
    if (_androidPointers.remove(event.pointer)) setState(() {});
  }

  // Padding-based zoom: narrows the content column so images appear smaller
  // but still fill top-to-bottom with no centering box. Toggled by double-tap.
  bool _cascadeZoomed = false;

  /// Cuánto se angosta la columna al alejar. Con nombre porque la cuenta que
  /// mantiene el punto tocado en su lugar (ver _onCascadeDoubleTap) necesita
  /// EXACTAMENTE el mismo número que el ancho de la columna: las imágenes van
  /// con BoxFit.fitWidth, así que su alto escala igual que su ancho, y de ahí
  /// sale el factor con el que se corrige la posición.
  static const _factorAlejado = 0.55;

  /// Dónde cayó el último doble toque, como fracción del alto de la vista
  /// (0 = arriba del todo, 1 = abajo del todo).
  ///
  /// Se guarda en `onDoubleTapDown`, que siempre llega antes que
  /// `onDoubleTap`. Arranca en el centro por si el zoom se dispara por algún
  /// camino que no sea un toque.
  double _fraccionDelDobleToque = 0.5;

  void _registrarDobleToque(double dy, double altoDeLaVista) {
    if (altoDeLaVista <= 0) return;
    _fraccionDelDobleToque = (dy / altoDeLaVista).clamp(0.0, 1.0);
  }

  // Desktop-only: double-click narrows the content column for an overview.
  // Narrowing/widening resizes every image (BoxFit.fitWidth recalculates
  // each item's height), which shifts the whole scroll extent — without
  // re-anchoring, the same pixel offset now points at a different page, so
  // the view appears to jump. Re-jump to the page you were on once the
  // resized layout has been painted.
  void _onCascadeDoubleTap() {
    // Android: si quedó pellizcado o corrido, el doble toque PRIMERO endereza
    // —vuelve a 1x y centrado— y no hace nada más. El siguiente doble toque
    // ya alterna el alejado de siempre.
    //
    // Antes no había forma de enderezarlo: el pellizco de la cascada usa este
    // TransformationController y nadie lo devolvía nunca a la identidad, así
    // que una vez movido el manhwa quedaba corrido hasta salir del capítulo
    // (reportado en vivo: "a veces el usuario lo mueve y no queda centrado").
    if (Platform.isAndroid &&
        _androidPinchTransform.value != Matrix4.identity()) {
      // Mismo remedio que más abajo (alignment de itemLeadingEdge), pero
      // acá es una red de seguridad y no la cura completa: el pellizco es
      // un transform VISUAL (InteractiveViewer, panEnabled:false) que no
      // mueve el scroll de la lista de abajo, así que en teoría enderezar
      // no debería moverla. Pero se puede seguir scrolleando mientras se
      // está pellizcado, y ahí sí el scroll de la lista cambió de verdad
      // — este jumpTo lo vuelve a poner en la MISMA página y fracción de
      // justo antes de enderezar, en vez de dejarlo donde sea que haya
      // quedado el scroll subyacente.
      final page = _c.currentPage.value;
      double alignment = 0;
      for (final p in _c.itemPositionsListener.itemPositions.value) {
        if (p.index == page) {
          alignment = p.itemLeadingEdge;
          break;
        }
      }
      setState(() => _androidPinchTransform.value = Matrix4.identity());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _c.itemScrollController.isAttached) {
          _c.itemScrollController.jumpTo(index: page, alignment: alignment);
        }
      });
      return;
    }

    // ── El punto que se tocó se queda donde está ──────────────────────────
    //
    // Antes esto anclaba el BORDE DE ARRIBA de la página actual: se
    // conservaba la página y cuánto de ella ya se había pasado, pero al
    // cambiar el ancho la página entera cambia de alto, así que lo que
    // estabas mirando se corría igual — se veía "lo mismo pero movido", no
    // "lo mismo más cerca o más lejos". A pedido explícito ahora el ancla es
    // el punto exacto donde cayó el doble toque.
    //
    // La cuenta, todo en fracciones del alto de la vista (que es la unidad
    // en la que vienen itemLeadingEdge/itemTrailingEdge y la que espera
    // jumpTo como alignment):
    //
    //   t  = dónde se tocó
    //   L0 = borde de arriba de la página tocada, ahora
    //   h0 = alto de esa página, ahora
    //   f  = cuánto se agranda/achica la columna
    //
    // El punto tocado está a (t - L0) de arriba de la página, o sea a la
    // altura (t - L0) / h0 de ella. Después del cambio esa misma altura de
    // la página mide (t - L0) * f, porque el alto escala igual que el ancho
    // (BoxFit.fitWidth). Para que ese punto siga cayendo en t, el borde de
    // arriba tiene que quedar en:
    //
    //   L1 = t - (t - L0) * f
    //
    // Se lee ANTES de tocar el zoom: después de setState las posiciones
    // viejas ya no valen.
    final t = _fraccionDelDobleToque;
    // Alejando la columna se angosta (f = 0.55); acercando vuelve a lo ancho
    // (f = 1 / 0.55). El estado todavía no cambió, así que _cascadeZoomed es
    // el de ANTES del toque.
    final f = _cascadeZoomed ? 1 / _factorAlejado : _factorAlejado;

    // La página que está debajo del dedo, no la que el contador marca como
    // "actual": son distintas si se tocó arriba o abajo de la pantalla, y la
    // que importa acá es la que se está mirando en ese punto.
    var page = _c.currentPage.value;
    double leadingEdge = 0;
    for (final p in _c.itemPositionsListener.itemPositions.value) {
      if (t >= p.itemLeadingEdge && t < p.itemTrailingEdge) {
        page = p.index;
        leadingEdge = p.itemLeadingEdge;
        break;
      }
      // Respaldo por si el toque cae en un hueco entre páginas (un borde
      // justo, o una imagen que todavía no midió): la página del contador,
      // con su borde real.
      if (p.index == page) leadingEdge = p.itemLeadingEdge;
    }
    final alignment = t - (t - leadingEdge) * f;

    setState(() => _cascadeZoomed = !_cascadeZoomed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _c.itemScrollController.isAttached) {
        _c.itemScrollController.jumpTo(index: page, alignment: alignment);
      }
    });
  }

  // Custom track+thumb standing in for the native Scrollbar in cascade mode.
  // ScrollablePositionedList only learns each item's real pixel height once
  // it renders (lazy network images), so a PIXEL-based scrollbar drag maps
  // to a wildly wrong distance as that estimate keeps shifting underneath
  // it. Tracking by ITEM INDEX instead is always exact — itemCount never
  // changes — so a drag tracks the mouse 1:1 with no jump/lurch.
  // Más ancha que la de antes (10px): a pedido explícito, era finita y difícil
  // de agarrar con el mouse en escritorio.
  static const _cascadeScrollbarWidth = 16.0;

  // Arriba se recorta lo que mide el panel de control superior
  // (control_panel_header: 40px en escritorio), que se dibuja ENCIMA de la
  // barra: sin esto el extremo de arriba del riel quedaba tapado y no se podía
  // ni ver ni agarrar (reportado en vivo).
  //
  // Abajo NO se recorta el footer (80px). Se probó y el riel quedaba cortado
  // TODO el tiempo, sin llegar al fondo, aunque el footer solo aparece cuando
  // se abren las opciones — a pedido explícito, el riel llega hasta abajo así
  // se puede arrastrar hasta el final del capítulo. Los 8px son solo aire para
  // que el thumb no toque el borde de la ventana.
  //
  // El recorte de arriba es FIJO, no atado a si el panel está visible: si el
  // riel cambiara de alto al mostrar/ocultar los paneles, el thumb —cuya
  // posición se calcula sobre el alto del riel— saltaría de lugar en cada
  // toggle.
  static const _cascadeScrollbarTopInset = 40.0;
  static const _cascadeScrollbarBottomInset = 8.0;

  /// [aLaIzquierda] pone la barra en el borde izquierdo en vez del derecho.
  ///
  /// Va al hueco que deja la franja, del lado contrario a donde esté pegada.
  /// Con la franja a la derecha la barra tocaba el manga: quedaba encima del
  /// contenido y encima se agarraba mal, porque el propio manga está debajo.
  /// Centrada o pegada a la izquierda el hueco cae a la derecha, así que la
  /// barra se queda donde estuvo siempre.
  Widget _buildCascadeScrollbar(int itemCount, {required bool aLaIzquierda}) {
    if (itemCount <= 1) return const SizedBox.shrink();

    double thumbHeightFor(double trackHeight) =>
        (trackHeight / itemCount * 3).clamp(32.0, trackHeight);

    void jumpToLocalY(double trackHeight, double localY) {
      final thumbHeight = thumbHeightFor(trackHeight);
      final usableTrack = trackHeight - thumbHeight;
      final fraction = usableTrack <= 0
          ? 0.0
          : ((localY - thumbHeight / 2) / usableTrack).clamp(0.0, 1.0);
      // Al fondo del riel: se salta al final REAL en píxeles, no al índice de
      // la última página. Saltar por índice deja el scroll al COMIENZO de esa
      // última imagen, así que su parte de abajo quedaba inalcanzable
      // arrastrando la barra — reportado en vivo ("no llega para ver todo el
      // contenido"). Se usa el mismo ScrollPosition que la rueda del mouse; si
      // todavía no está disponible se cae al salto por índice de siempre.
      if (fraction >= 0.999) {
        final position = _cascadeScrollPosition;
        if (position != null) {
          try {
            position.jumpTo(position.maxScrollExtent);
            return;
          } catch (_) {
            // ScrollPosition ya disposed — sigue por el camino de abajo.
          }
        }
      }
      final index = (fraction * (itemCount - 1)).round();
      if (_c.itemScrollController.isAttached) {
        _c.itemScrollController.jumpTo(index: index);
      }
    }

    return Positioned(
      left: aLaIzquierda ? 2 : null,
      right: aLaIzquierda ? null : 2,
      top: _cascadeScrollbarTopInset,
      bottom: _cascadeScrollbarBottomInset,
      width: _cascadeScrollbarWidth,
      child: LayoutBuilder(
        builder: (context, box) {
          final trackHeight = box.maxHeight;
          final thumbHeight = thumbHeightFor(trackHeight);
          return Obx(() {
            final page = _c.currentPage.value;
            final usableTrack = trackHeight - thumbHeight;
            final top =
                usableTrack <= 0 ? 0.0 : usableTrack * (page / (itemCount - 1));
            return Listener(
              // GestureDetector has no onPointerSignal of its own — without
              // this, hovering the visible scrollbar strip itself (a natural
              // spot to aim for when scrolling "from outside" the manga)
              // silently ate the wheel instead of forwarding it.
              onPointerSignal: _forwardBorderWheelScroll,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) =>
                    jumpToLocalY(trackHeight, d.localPosition.dy),
                onVerticalDragUpdate: (d) =>
                    jumpToLocalY(trackHeight, d.localPosition.dy),
                onTapDown: (d) => jumpToLocalY(trackHeight, d.localPosition.dy),
                child: Stack(
                  children: [
                    Positioned(
                      top: top,
                      width: _cascadeScrollbarWidth,
                      height: thumbHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(140),
                          borderRadius:
                              BorderRadius.circular(_cascadeScrollbarWidth / 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          });
        },
      ),
    );
  }

  // Called by opaque Listeners on the gray Mica border areas.
  // Forwards wheel (PointerScrollEvent) to the scroll position so the mouse
  // wheel still works even though the border absorbs click events.
  //
  // Uses ScrollPosition.jumpTo directly (via _cascadeScrollPosition) instead
  // of ScrollOffsetController.animateScroll: animateScroll only offers an
  // ANIMATED transition (ScrollController.animateTo), which — even at the
  // smallest safe duration — runs through a Ticker-driven DrivenScrollActivity
  // that takes at least one frame and gets restarted by every new event
  // during a fast, rapid-fire scroll. That per-event overhead is invisible
  // for a single tick but compounds under rapid scrolling, visibly lagging
  // behind the instant, un-animated jump the native Scrollable itself uses
  // when the mouse is directly over the content. jumpTo is synchronous, so
  // it matches that native feel exactly regardless of how fast events arrive.
  //
  // (DrivenScrollActivity's constructor also asserts `duration > Duration.zero`
  // — animateScroll with a literal zero duration throws that assertion on
  // every call. jumpTo has no such restriction.)
  // Flechas del teclado. En modo cascada NO se delega al controller: ahí
  // `onKey` llamaba a nextPage/previousPage, que hacen un scrollTo por ÍNDICE
  // con animación de 300ms y sin ninguna protección contra repetición. Al
  // mantener la flecha, cada KeyRepeatEvent (unos 30 por segundo) arrancaba un
  // scroll nuevo hacia currentPage+1, y como currentPage se va actualizando
  // mientras anima, los destinos se encadenaban y la lectura se iba
  // volando (reportado en vivo: "las flechitas se va super rápido").
  //
  // Acá se scrollea por PÍXELES con el mismo jumpTo que usa la rueda del
  // mouse (ver _forwardBorderWheelScroll): mantener la flecha simplemente
  // suma pasos chicos, que es el comportamiento normal de cualquier lector.
  // El modo paginado sigue yendo por el controller, donde una flecha = una
  // página es lo correcto y ya está protegido por _animatingTo.
  static const _keyScrollStep = 48.0;
  static const _keyPageStepFactor = 0.9;

  void _onKeyEvent(KeyEvent event) {
    // Escape cierra el lector, como el botón de atrás. Va PRIMERO y para
    // cualquier modo (paginado o cascada): es lo que espera cualquiera al
    // estar leyendo a pantalla completa. Usa el mismo RouterUtils.closeReader
    // que el botón, así no hay dos formas distintas de salir que se puedan
    // desincronizar.
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      RouterUtils.closeReader(context);
      return;
    }
    // El controller mantiene el estado de zoom (Ctrl) y el modo paginado.
    if (_c.isPaged || Platform.isAndroid) {
      _c.onKey(event);
      return;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      _c.onKey(event);
      return;
    }
    final key = event.logicalKey;
    final viewport = _cascadeScrollPosition?.viewportDimension ?? 0;
    double? delta;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      delta = _keyScrollStep;
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      delta = -_keyScrollStep;
    } else if (key == LogicalKeyboardKey.pageDown) {
      delta = viewport * _keyPageStepFactor;
    } else if (key == LogicalKeyboardKey.pageUp) {
      delta = -viewport * _keyPageStepFactor;
    }
    if (delta == null || delta == 0) {
      _c.onKey(event);
      return;
    }
    _scrollCascadeBy(delta);
  }

  // Mismo camino que la rueda del mouse: jumpTo directo sobre el
  // ScrollPosition real (instantáneo, sin máquina de animación que se
  // reinicie con cada evento), con el fallback animado para la ventanita
  // inicial en la que todavía no llegó ninguna notificación de scroll.
  void _scrollCascadeBy(double dy) {
    final target = (_cascadeScrollOffset + dy).clamp(0.0, _cascadeScrollMax);
    if (target == _cascadeScrollOffset) return;
    final position = _cascadeScrollPosition;
    if (position != null) {
      try {
        position.jumpTo(target);
      } catch (_) {
        // ScrollPosition ya disposed (se salió del lector en el medio).
      }
      return;
    }
    _c.scrollOffsetController.animateScroll(
      offset: target - _cascadeScrollOffset,
      duration: const Duration(milliseconds: 1),
      curve: Curves.linear,
    );
  }

  void _forwardBorderWheelScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        // El resolver ejecuta este callback en un paso posterior del mismo
        // evento de puntero (no un microtask) — pero si justo en el medio
        // se cerró/navegó fuera del lector, el widget (o el Scrollable
        // dueño de _cascadeScrollPosition) ya se dispuso y usar el
        // ScrollPosition tira "used after being disposed". mounted cubre el
        // caso común; el try/catch es la red para cuando lo que se disposed
        // es el Scrollable anidado y no este widget.
        if (!mounted) return;
        final dy = (e as PointerScrollEvent).scrollDelta.dy;
        final target =
            (_cascadeScrollOffset + dy).clamp(0.0, _cascadeScrollMax);
        if (target == _cascadeScrollOffset) return;
        final position = _cascadeScrollPosition;
        if (position != null) {
          try {
            position.jumpTo(target);
          } catch (_) {
            // Ver comentario de arriba — ScrollPosition ya disposed.
          }
          return;
        }
        // Fallback for the brief window before a scroll notification has
        // ever fired (so _cascadeScrollPosition is still null) — animated,
        // so a touch slower than jumpTo, but never a silent no-op.
        _c.scrollOffsetController.animateScroll(
          offset: target - _cascadeScrollOffset,
          duration: const Duration(milliseconds: 1),
          curve: Curves.linear,
        );
      });
    }
  }

  // Shown per-page while its image is still loading — scrolling fast
  // through not-yet-loaded pages used to hit a blank box; the dimmed
  // branded art fills that space instead of leaving it empty.
  Widget _buildPlaceholder(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.5,
            child:
                Image.asset('assets/carddefaultoffline.png', fit: BoxFit.cover),
          ),
          const Center(child: ProgressRing()),
        ],
      ),
    );
  }

  // ── Bottom bar: position counter ─────────────────────────────────────────

  Widget _buildBottomBar() {
    return Obx(() {
      final total = _c.watchData.value?.urls.length ?? 0;
      final page = _c.currentPage.value;

      // Antes era un rectángulo de esquinas vivas pegado al vértice de abajo
      // a la izquierda: tocaba los dos bordes de la pantalla y parecía más un
      // recorte mal cortado que una etiqueta (reportado en vivo con captura).
      // Ahora flota, separado de los bordes y con las puntas redondeadas,
      // como el resto de las etiquetas de la app.
      return Container(
        margin: const EdgeInsets.only(left: 12, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(200),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${page + 1}/$total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    });
  }

  // ── Full display overlay (wraps content) ─────────────────────────────────

  Widget _buildDisplay(Widget child) {
    // Los dos overlays se desvanecen con isShowControlPanel, igual que el
    // encabezado y el pie: lectura sin nada encima.
    //
    //   ANDROID   el panel va y viene con un toque, y scrollear lo esconde.
    //   WINDOWS   lo levanta pasar el mouse por los 60px de arriba o de abajo
    //             (ver reader_view) y se esconde solo a los 3 segundos.
    //
    // Antes el contador de páginas era la única cosa que en escritorio se
    // quedaba fija en pantalla mientras todo lo demás desaparecía.
    Widget overlay(Widget w) {
      return Obx(() {
        final visible = _c.isShowControlPanel.value;
        return AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(ignoring: !visible, child: w),
        );
      });
    }

    return Stack(
      children: [
        child,
        // Bottom-left: page counter + page navigation (page mode)
        Positioned(
          bottom: 0,
          left: 0,
          child: overlay(_buildBottomBar()),
        ),
      ],
    );
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _buildContent() {
    // Mismo negro que Home/Historial/Buscar (antes: colorScheme.surface /
    // micaBackgroundColor, un gris bastante más claro que no hacía juego
    // con el brillo animado de abajo, pensado para ese tono específico).
    // ── La zona de lectura también sigue al modo ────────────────────────
    //
    // Estaba clavada en el negro de la app, con el criterio de que una página
    // se mira sobre oscuro. Pero una página de manga o de manhwa es en su
    // mayoría BLANCA, así que sobre negro lo que queda es un marco oscuro
    // rodeando una franja clara — y con el modo claro puesto encima, la barra
    // de arriba quedaba blanca y el resto negro, que es lo peor de los dos.
    //
    // Siguiendo al modo, en claro la página se funde con el fondo y en oscuro
    // queda exactamente como estaba.
    final backgroundColor = HomeTheme.bg;

    // Outermost catch-all for wheel scroll in cascade mode: wraps literally
    // everything this widget returns, so it's guaranteed shallower than the
    // real Scrollable (which still wins first when the mouse is over actual
    // content — see PointerSignalResolver, deepest registrant wins) AND
    // shallower than every border/scrollbar Listener below. If any of those
    // narrower, more specific spots still had a gap in their coverage, this
    // is the last-resort net that can't have the same gap.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (event) {
        if (!Platform.isAndroid && _c.readType.value == MangaReadMode.webTonn) {
          _forwardBorderWheelScroll(event);
        }
      },
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Container(
          color: backgroundColor,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            // Igual que Home/Historial/Buscar: se ve en los márgenes
            // laterales que quedan cuando la página de manga (ancho tope
            // 900px, más abajo) no llena una ventana de escritorio ancha —
            // las páginas en sí son opacas y lo tapan sin distraer de la
            // lectura. (El crash de scrollable_positioned_list que parecía
            // venir de este Stack en realidad era una carrera aparte en
            // ComicController._jumpPage, ya arreglada — este Stack nunca
            // fue la causa real.)
            Positioned.fill(child: AnimatedBackgroundGlow()),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final maxHeight = constraints.maxHeight;
                return Obx(() {
                  // La extensión se cayó: no hay con qué reintentar.
                  //
                  // Va antes del error general, que ofrece "reintentar": los
                  // capítulos salen de la misma extensión que ya no está, así
                  // que ese botón mandaría al usuario a dar vueltas. Acá lo
                  // único útil es salir.
                  final caida = _c.extensionCaida.value;
                  if (caida != null) {
                    return AvisoExtensionCaida(
                      motivo: caida.i18n,
                      onSalir: () => RouterUtils.closeReader(context),
                    );
                  }
                  if (_c.error.value.isNotEmpty) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_c.error.value),
                        PlatformButton(
                          onPressed: _c.getContent,
                          child: Text('common.retry'.i18n),
                        ),
                      ],
                    );
                  }

                  if (_c.watchData.value == null) {
                    return const Center(child: ProgressRing());
                  }

                  // Cambio de capítulo (watchData es un objeto nuevo): el
                  // Scrollable interno viejo de ScrollablePositionedList queda
                  // atrás con él — limpiar acá para que el próximo scroll
                  // desde afuera del manga use el fallback animado en vez de
                  // una referencia vieja que ya no sirve (ver _cascadeScrollPosition).
                  if (!identical(_lastWatchData, _c.watchData.value)) {
                    _lastWatchData = _c.watchData.value;
                    _cascadeScrollPosition = null;
                    // Capítulo nuevo = otras URLs: se limpia el registro de
                    // precargadas para que no crezca sin límite a lo largo de
                    // una sesión de lectura larga.
                    _precached.clear();
                    _lastPrecachedFrom = -1;
                  }

                  // Lo MISMO al cambiar de modo: pasar a paginado destruye la
                  // ScrollablePositionedList entera, y al volver a cascada se
                  // arma una nueva con otro Scrollable interno. Sin limpiar
                  // acá, _cascadeScrollPosition seguía apuntando al viejo (ya
                  // disposed) y el scroll desde afuera del manga dejaba de
                  // funcionar hasta reabrir el capítulo — confirmado en vivo:
                  // "deja de andar cuando cambio a paginación y vuelvo a
                  // cascada".
                  if (_lastReadType != _c.readType.value) {
                    _lastReadType = _c.readType.value;
                    _cascadeScrollPosition = null;
                    _cascadeScrollOffset = 0;
                    _cascadeScrollMax = double.maxFinite;
                  }

                  final images = _c.watchData.value!.urls;

                  // Dónde está pegada la franja. Lo usan los dos modos, así
                  // que se lee una sola vez acá arriba.
                  final alineacion = _c.stripAlign.value;

                  // OJO: currentPage NO se lee acá. Este Obx envuelve todo el
                  // contenido, y onPageChanged actualiza currentPage MIENTRAS
                  // corre la animación de cambio de página — leerlo acá hacía
                  // que el PageView entero se reconstruyera a mitad del
                  // deslizamiento, y esa reconstrucción es lo que se veía
                  // como si pasaran varias páginas de golpe (confirmado en
                  // vivo, insistía aun después de cachear las proporciones).
                  // En el modo paginado lo leen solo las flechas, cada una en
                  // su propio Obx. La cascada sí lo necesita y lo lee abajo.

                  // Modo página a página (standard / rightToLeft): un PageView
                  // horizontal en vez de la cascada vertical. Se devuelve acá,
                  // antes de armar toda la maquinaria de la cascada (bordes,
                  // rueda, scrollbar propia, zoom por padding) — nada de eso
                  // aplica a un lector paginado, y mezclarlos era justo el
                  // riesgo de romper la cascada, que funciona bien.
                  if (_c.isPaged) {
                    // ── Dónde se dibujan las flechas ────────────────────────
                    //
                    // La izquierda SIEMPRE es "anterior" y la derecha
                    // "siguiente" (ver _PageArrow): lo único que cambia acá es
                    // en qué parte de la pantalla se dibujan, no cuál hace qué.
                    //
                    // Con la franja centrada quedan en los dos bordes, como
                    // siempre. Pegada a un costado, las dos se van juntas al
                    // hueco del otro lado y quedan centradas ahí — si no, la
                    // del lado de la franja se dibujaba ENCIMA del manga.
                    //
                    // El ancho se calcula con la franja sin alejar: el alejado
                    // es por página y acá todavía no se sabe. Si el hueco no da
                    // para las dos flechas, se quedan en los bordes.
                    final anchoFranja = maxWidth < 900.0 ? maxWidth : 900.0;
                    final huecoPaginado = maxWidth - anchoFranja;
                    final cabenLasDos = huecoPaginado >= _PageArrow.ancho * 2;
                    final enUnCostado =
                        alineacion != ComicController.alineacionCentro;

                    double? izqDe(bool esAnterior) {
                      if (!enUnCostado || !cabenLasDos) {
                        return esAnterior ? 0.0 : null;
                      }
                      // Centro del hueco: a la derecha de la franja si está
                      // pegada a la izquierda, y al revés.
                      final centroHueco =
                          alineacion == ComicController.alineacionIzquierda
                              ? maxWidth - huecoPaginado / 2
                              : huecoPaginado / 2;
                      return esAnterior
                          ? centroHueco - _PageArrow.ancho
                          : centroHueco;
                    }

                    return Listener(
                      // Mismo mecanismo que usa la cascada en Android: contar
                      // dedos para saber cuándo hay un pellizco en curso. Sin
                      // esto, el gesto de zoom y el de pasar de página se
                      // peleaban y ganaba el del PageView — por eso en
                      // celular el pellizco no hacía nada en modo paginado.
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onAndroidPointerDown,
                      onPointerUp: _onAndroidPointerUp,
                      onPointerCancel: _onAndroidPointerUp,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _c.pageController,
                            // rightToLeft: se invierte el sentido del
                            // deslizamiento, como se lee un manga japonés. El
                            // índice NO se invierte: la página 0 sigue siendo
                            // la primera.
                            reverse:
                                _c.readType.value == MangaReadMode.rightToLeft,
                            // Celular: el deslizamiento con el dedo es la forma
                            // natural de pasar de página, así que se deja la
                            // física normal y NO hacen falta flechas encima
                            // del manga.
                            //
                            // Escritorio: física bloqueada a propósito, porque
                            // ahí el mismo gesto llega como rueda del mouse y
                            // pasaba de página sola al querer bajar dentro de
                            // una página alta (confirmado en vivo). Se pasa de
                            // página con las flechas o el teclado.
                            // Con un pellizco en curso también se bloquea: si
                            // no, el segundo dedo arrastraba la página al mismo
                            // tiempo que hacía zoom.
                            physics: (Platform.isAndroid && !_androidPinching)
                                ? null
                                : const NeverScrollableScrollPhysics(),
                            // Mantiene viva la página de cada lado, así ya está
                            // descargada y decodificada ANTES de llegar a ella.
                            // Sin esto, al pasar de página se veía el logo de
                            // respaldo un instante mientras cargaba — parecía
                            // que pasaban varias páginas de golpe cuando en
                            // realidad era el placeholder de la siguiente.
                            allowImplicitScrolling: true,
                            onPageChanged: (i) => _c.currentPage.value = i,
                            itemCount: images.length,
                            itemBuilder: (context, index) => _PagedPage(
                              // Clave por índice+url: sin esto el PageView
                              // podía reciclar el State de una página en
                              // otra (mismo slot) y el zoom/achicado
                              // quedaba pegado de la página anterior.
                              key: ValueKey('$index-${images[index]}'),
                              url: images[index],
                              headers: _c.watchData.value?.headers,
                              // Solo cambia el reparto horizontal: la parte
                              // vertical queda en `center`, igual que el
                              // Center que había antes acá.
                              stripAlign: switch (_c.stripAlign.value) {
                                ComicController.alineacionIzquierda =>
                                  Alignment.centerLeft,
                                ComicController.alineacionDerecha =>
                                  Alignment.centerRight,
                                _ => Alignment.center,
                              },
                              // Placeholder discreto (no el logo a pantalla
                              // completa que usa la cascada): en paginado ese
                              // logo ocupa toda la pantalla y se confunde con
                              // una página de verdad, dando la sensación de
                              // haber saltado varias.
                              placeholder: const Center(child: ProgressRing()),
                              llenarPantalla: _c.llenarPantalla.value,
                            ),
                          ),
                          // Solo escritorio (ver arriba): en celular se desliza
                          // y las flechas solo taparían el manga.
                          // Obx propio por flecha: así el cambio de página
                          // solo reconstruye la flecha, no el PageView entero
                          // (ver comentario de currentPage más arriba).
                          if (!Platform.isAndroid) ...[
                            Obx(() => _PageArrow(
                                  left: true,
                                  desdeIzquierda: izqDe(true),
                                  enabled: _c.currentPage.value > 0,
                                )),
                            Obx(() => _PageArrow(
                                  left: false,
                                  desdeIzquierda: izqDe(false),
                                  enabled:
                                      _c.currentPage.value < images.length - 1,
                                )),
                          ],
                        ],
                      ),
                    );
                  }

                  // La cascada sí necesita la página actual (initialScrollIndex)
                  // y acá leerla no molesta: no hay una animación de PageView
                  // que se pueda cortar por el rebuild.
                  //
                  // Acotado al capítulo que se está mostrando: si quedara
                  // apuntando a una página que este capítulo no tiene,
                  // scrollable_positioned_list ancla la lista al ÚLTIMO ítem
                  // (ver su didUpdateWidget) y el capítulo abre al fondo. Es la
                  // segunda red: la primera está en ComicController, donde se
                  // deja de escuchar posiciones mientras se cambia de capítulo.
                  final ultimaPagina = images.isEmpty ? 0 : images.length - 1;
                  final currentPage =
                      _c.currentPage.value.clamp(0, ultimaPagina);

                  // Cascade: cap content at 900 px normally; narrow to ~55% when
                  // zoomed out so images shrink but still fill edge-to-edge (no box).
                  //
                  // Con "llenar pantalla" (ComicController.llenarPantalla) el
                  // tope de 900 se saca: en un teléfono maxWidth casi nunca
                  // llega a 900, así que ahí esto no cambiaba nada — donde SÍ
                  // se nota es en escritorio con la ventana ancha, que
                  // quedaba con márgenes a los costados aunque se pidiera
                  // llenar la pantalla.
                  final normalWidth = _c.llenarPantalla.value
                      ? maxWidth
                      : (maxWidth < 900.0 ? maxWidth : 900.0);
                  final effectiveWidth = _cascadeZoomed
                      ? normalWidth * _factorAlejado
                      : normalWidth;
                  // El ancho que sobra se reparte según la alineación elegida:
                  // todo a la derecha (franja pegada a la izquierda), todo a la
                  // izquierda (franja pegada a la derecha), o mitad y mitad
                  // (centrada, que es como venía siendo y sigue siendo el
                  // default). Ver ComicController.stripAlign.
                  final sobraDeAncho = maxWidth > effectiveWidth
                      ? maxWidth - effectiveWidth
                      : 0.0;
                  final margenIzq = switch (alineacion) {
                    ComicController.alineacionIzquierda => 0.0,
                    ComicController.alineacionDerecha => sobraDeAncho,
                    _ => sobraDeAncho / 2,
                  };
                  final margenDer = sobraDeAncho - margenIzq;

                  // Use the LayoutBuilder's own constraints, not MediaQuery's
                  // full window size — they can differ (e.g. a custom title
                  // bar takes space MediaQuery still counts), and sizing this
                  // area larger than what its parent actually allotted put
                  // part of the border hit-area outside the real, hit-testable
                  // region: wheel scroll silently did nothing there.
                  final sw = maxWidth;
                  final sh = maxHeight;

                  final scrollList = NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      // n.context is guaranteed to be inside the list's real
                      // internal Scrollable, since that's what dispatched this
                      // notification — unlike itemBuilder's context, which
                      // this package builds outside any Scrollable ancestor
                      // (Scrollable.of from there throws). maybeOf just in
                      // case, so a lookup miss no-ops instead of crashing.
                      //
                      // SIEMPRE se refresca (antes solo la primera vez, cuando
                      // era null) — al cambiar de capítulo, ScrollablePositionedList
                      // arma un Scrollable interno NUEVO, y con el guard viejo
                      // _cascadeScrollPosition se quedaba apuntando para
                      // siempre al de un capítulo anterior (posiblemente ya
                      // disposed): el scroll desde afuera del manga funcionaba
                      // solo en el primer capítulo y dejaba de responder en
                      // cuanto se cambiaba de capítulo.
                      if (n.context != null) {
                        _cascadeScrollPosition =
                            Scrollable.maybeOf(n.context!)?.position;
                      }
                      if (Platform.isAndroid) {
                        if (n is ScrollStartNotification) {
                          _c.isShowControlPanel.value = false;
                        }
                      }
                      if (n is ScrollUpdateNotification) {
                        _cascadeScrollOffset = n.metrics.pixels;
                        _cascadeScrollMax = n.metrics.maxScrollExtent;
                        // Va pidiendo las próximas páginas mientras se lee, no
                        // solo al abrir el capítulo.
                        _precacheAround(images, _c.currentPage.value);
                      }
                      return false;
                    },
                    child: ScrollablePositionedList.builder(
                      physics: (_c.isZoom.value || _androidPinching)
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      padding:
                          EdgeInsets.only(left: margenIzq, right: margenDer),
                      initialScrollIndex: currentPage,
                      itemScrollController: _c.itemScrollController,
                      itemPositionsListener: _c.itemPositionsListener,
                      scrollOffsetController: _c.scrollOffsetController,
                      // Sin esto la lista solo construía lo que está por
                      // entrar en pantalla, así que cada imagen recién
                      // empezaba a bajar cuando ya casi se veía: leyendo se
                      // topaba con el placeholder una página tras otra
                      // (reportado en vivo, peor en las extensiones con
                      // imágenes grandes o servidor lento). Con un cache
                      // extent grande la lista construye bastante más
                      // adelante, así que la descarga arranca mucho antes de
                      // que llegues. Va acompañado del precache de más abajo:
                      // esto adelanta el BUILD, y el precache adelanta la
                      // DESCARGA incluso más lejos.
                      minCacheExtent: 3000,
                      itemBuilder: (context, index) {
                        // Al construir una página se piden también las que
                        // vienen: cubre el arranque del capítulo, cuando
                        // todavía no hubo ningún scroll que lo dispare.
                        _precacheAround(images, index);
                        final url = images[index];
                        return CacheNetWorkImagePic(
                          url,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          placeholder: _buildPlaceholder(context),
                          headers: _c.watchData.value?.headers,
                        );
                      },
                      itemCount: images.length,
                    ),
                  );

                  // Desktop: opaque Listeners on Mica borders prevent phantom
                  // scroll on click. Double-click narrows the content column
                  // (padding-based zoom) so images stay edge-to-edge, top-to-bottom.
                  //
                  // Scrollbar disabled: ScrollablePositionedList only learns
                  // each item's real height once it has actually rendered (the
                  // images load lazily over the network), so its maxScrollExtent
                  // is a constantly-shifting estimate. Dragging a native
                  // proportional scrollbar against that estimate is inherently
                  // unstable — it jumps instead of tracking the drag smoothly.
                  // Position feedback is still available via the page counter.
                  if (!Platform.isAndroid) {
                    Widget borderAbsorber() => Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerSignal: _forwardBorderWheelScroll,
                        );

                    // Franja reservada para que el absorbedor opaco no se monte
                    // encima del área de agarre de la barra (y se coma todos
                    // los clics que iban para ella).
                    const scrollbarStrip = _cascadeScrollbarWidth + 6;

                    // La barra vive en el hueco que deja la franja, del lado
                    // contrario a donde esté pegada. Solo se muda cuando la
                    // franja va pegada a la DERECHA: ahí el hueco es el de la
                    // izquierda, y dejarla a la derecha la ponía encima del
                    // manga. Centrada o a la izquierda no cambia nada.
                    final barraALaIzquierda =
                        alineacion == ComicController.alineacionDerecha;
                    // Y la reserva acompaña a la barra, no al borde derecho.
                    final reservaIzq = barraALaIzquierda ? scrollbarStrip : 0.0;
                    final reservaDer = barraALaIzquierda ? 0.0 : scrollbarStrip;

                    return Listener(
                      // Outer catch-all: forwards wheel scroll for any point in
                      // this whole area that the native Scrollable doesn't
                      // already claim (it always wins first — see
                      // PointerSignalResolver, deepest registrant wins). This is
                      // a safety net on top of the border Positioneds below, so
                      // no gap in that geometry can silently eat the wheel.
                      behavior: HitTestBehavior.translucent,
                      onPointerSignal: _forwardBorderWheelScroll,
                      child: SizedBox(
                        width: sw,
                        height: sh,
                        child: Stack(
                          children: [
                            GestureDetector(
                              // onDoubleTapDown llega siempre antes que
                              // onDoubleTap: es de donde sale el punto que
                              // el zoom tiene que dejar quieto.
                              onDoubleTapDown: (d) => _registrarDobleToque(
                                d.localPosition.dy,
                                sh,
                              ),
                              onDoubleTap: _onCascadeDoubleTap,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(scrollbars: false),
                                child: scrollList,
                              ),
                            ),
                            // Cada absorbedor cubre SU margen real, no la mitad
                            // del sobrante: con la franja pegada a un costado
                            // los dos márgenes son distintos, y uno del tamaño
                            // equivocado se montaría encima del manga y se
                            // comería los clics de esa zona.
                            if (margenIzq > reservaIzq)
                              Positioned(
                                left: reservaIzq,
                                top: 0,
                                bottom: 0,
                                width: margenIzq - reservaIzq,
                                child: borderAbsorber(),
                              ),
                            if (margenDer > reservaDer)
                              Positioned(
                                right: reservaDer,
                                top: 0,
                                bottom: 0,
                                width: margenDer - reservaDer,
                                child: borderAbsorber(),
                              ),
                            _buildCascadeScrollbar(
                              images.length,
                              aLaIzquierda: barraALaIzquierda,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Android: scaleEnabled always true so pinch-to-zoom never
                  // misses the gesture start (no mid-gesture Obx rebuild).
                  // panEnabled: false lets the list handle vertical scroll;
                  // InteractiveViewer only claims 2-finger scale gestures.
                  return SizedBox(
                    width: sw,
                    height: sh,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onAndroidPointerDown,
                      onPointerUp: _onAndroidPointerUp,
                      onPointerCancel: _onAndroidPointerUp,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // Mismo registro que en escritorio — ver el otro
                        // GestureDetector de esta misma cascada.
                        onDoubleTapDown: (d) => _registrarDobleToque(
                          d.localPosition.dy,
                          sh,
                        ),
                        onDoubleTap: _onCascadeDoubleTap,
                        onTap: () {
                          _c.isShowControlPanel.value =
                              !_c.isShowControlPanel.value;
                        },
                        child: InteractiveViewer(
                          transformationController: _androidPinchTransform,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          minScale: 1.0,
                          maxScale: 4.0,
                          scaleEnabled: true,
                          panEnabled: false,
                          child: scrollList,
                        ),
                      ),
                    ),
                  );
                });
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      // "Llenar pantalla" también saca el SafeArea de arriba y de abajo acá
      // adentro (ver el worker en ComicController que pone edgeToEdge), para
      // que la página dibuje hasta la cámara y hasta donde está la barra de
      // navegación — el header de ReaderView es un widget aparte, flotando
      // por encima, y se queda con su propio SafeArea de siempre.
      androidBuilder: (context) => Scaffold(
        body: Obx(
          () => SafeArea(
            top: !_c.llenarPantalla.value,
            bottom: !_c.llenarPantalla.value,
            child: _buildDisplay(_buildContent()),
          ),
        ),
      ),
      desktopBuilder: (context) => _buildDisplay(_buildContent()),
    );
  }
}

// Flecha lateral para pasar de página en modo paginado. Semánticamente la
// izquierda SIEMPRE es "anterior" y la derecha "siguiente", aunque en modo
// derecha→izquierda el deslizamiento vaya al revés — si no, el mismo botón
// haría cosas distintas según el modo y sería confuso.
class _PageArrow extends StatelessWidget {
  const _PageArrow({
    required this.left,
    required this.enabled,
    this.desdeIzquierda,
  });

  /// Cuánto mide de ancho. Lo necesita quien la coloca para repartir el hueco.
  static const ancho = 64.0;

  final bool left;
  final bool enabled;

  /// Posición exacta desde el borde izquierdo, cuando la franja está pegada a
  /// un costado y las dos flechas se van juntas al hueco del otro lado. En
  /// null vuelve a lo de siempre: cada una en su borde.
  final double? desdeIzquierda;

  @override
  Widget build(BuildContext context) {
    // Deshabilitada (primera/última página): no se dibuja nada, así no queda
    // una flecha sugiriendo que hay algo más.
    if (!enabled) return const SizedBox.shrink();
    final fijada = desdeIzquierda != null;
    return Positioned(
      left: fijada ? desdeIzquierda : (left ? 0 : null),
      right: fijada ? null : (left ? null : 0),
      top: 0,
      bottom: 0,
      // IgnorePointer a propósito: esto es SOLO el indicador visual de que
      // ese lado pasa de página. El clic lo maneja la capa de ReaderView,
      // que está por encima de todo este contenido — si además se manejara
      // acá, o el clic no llegaba (abría el panel de opciones) o se contaba
      // dos veces y saltaba varias páginas. Ambas cosas se confirmaron en
      // vivo. Una sola capa manejando el clic evita las dos.
      child: IgnorePointer(
        child: Container(
          width: ancho,
          alignment: Alignment.center,
          child: Opacity(
            opacity: 0.45,
            child: Icon(
              left ? Icons.chevron_left : Icons.chevron_right,
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// Una página en modo paginado. Resuelve el tamaño REAL de la imagen antes de
// decidir cómo mostrarla, porque los dos formatos que conviven acá necesitan
// cosas opuestas:
//
//  - Página de manga/cómic (proporción normal, más alta que ancha pero no
//    exagerado): entra entera en pantalla con contain. Es lo correcto y es
//    lo que ya se veía bien.
//  - Tira de manhwa/webtoon (larguísima y angosta): contain la reduce a un
//    hilo ilegible en el medio de la pantalla — confirmado en vivo. Para
//    esas se llena el ancho y se baja con la rueda DENTRO de la página, sin
//    cambiar de página.
//
// El umbral compara la proporción de la imagen contra la de la ventana: si
// la imagen es más del doble de "alta" que el espacio disponible, contain
// desperdiciaría más de la mitad del ancho y conviene el otro modo.
class _PagedPage extends StatefulWidget {
  const _PagedPage({
    super.key,
    required this.url,
    required this.headers,
    required this.placeholder,
    required this.stripAlign,
    required this.llenarPantalla,
  });

  final String url;
  final Map<String, String>? headers;
  final Widget placeholder;

  /// Dónde se pega la tira de manhwa cuando sobra ancho. Solo aplica a las
  /// páginas que resultan ser tira: una página de manga entra entera y no
  /// tiene sobrante que repartir.
  final Alignment stripAlign;

  /// Recortar la página para llenar la pantalla, en vez de mostrarla
  /// entera con franjas — ver ComicController.llenarPantalla.
  final bool llenarPantalla;

  @override
  State<_PagedPage> createState() => _PagedPageState();
}

class _PagedPageState extends State<_PagedPage> {
  // Proporciones ya medidas, por URL. Compartido entre todas las páginas y
  // sobreviviendo al reciclado del PageView: al volver a una página ya vista
  // se dibuja bien de una, sin pasar otra vez por el estado "midiendo".
  // Ese doble dibujado (primero ajustada al alto, después con la forma
  // definitiva) era lo que se veía como si pasaran varias páginas de golpe
  // al tocar las flechas — confirmado en vivo.
  static final Map<String, double> _aspectCache = {};

  // ancho/alto de la imagen real. null mientras no se resolvió.
  double? _aspect;
  ImageStreamListener? _listener;
  ImageStream? _stream;

  // Doble toque para alejar. En tira de manhwa angosta la columna (igual que
  // la cascada); en página de manga se maneja con el zoom del
  // InteractiveViewer.
  bool _zoomedOut = false;
  final _zoomController = TransformationController();
  bool _zoomed = false;

  /// Cuánto se angosta la tira al alejar. Con nombre por lo mismo que en la
  /// cascada: la cuenta que mantiene quieto el punto tocado necesita
  /// exactamente el mismo número que el ancho (ver _toggleZoomOut).
  static const _factorAlejadoTira = 0.55;

  // Zona de doble-toque para alejar/acercar. En desktop deja libres los 80px
  // de cada borde (misma franja que usa el clic de paginar en
  // reader_view.dart) — si el doble-toque cubriera todo el ancho, un clic en
  // la flecha entraba al MISMO gesture arena que este reconocedor de doble
  // toque (aunque sean widgets distintos, comparten el mismo puntero), y
  // Flutter tiene que esperar el timeout de doble-tap antes de resolver el
  // toque simple como tal — esa espera era la "mini pausa" al cambiar de
  // página con clic, reportada en vivo (con teclado, que no pasa por gesture
  // arena, ya andaba instantáneo). En Android no hay flechas clickeables
  // (el paginado ahí es por deslizamiento), así que cubre todo el ancho.
  Widget _doubleTapZoomOverlay({required bool esTira}) {
    final inset = Platform.isAndroid ? 0.0 : 80.0;
    return Positioned(
      left: inset,
      right: inset,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Dónde cayó el doble toque, que es el punto que el zoom tiene que
        // dejar quieto. Se le suma el `inset` porque esta capa arranca
        // corrida hacia adentro (ver arriba) y la cuenta necesita la
        // coordenada dentro de la página, no dentro de la capa.
        onDoubleTapDown: (d) => _puntoDelDobleToque = Offset(
          d.localPosition.dx + inset,
          d.localPosition.dy,
        ),
        onDoubleTap: () => _toggleZoomOut(esTira: esTira),
      ),
    );
  }

  /// Dónde cayó el último doble toque, en píxeles y dentro de la página.
  /// Arranca en cero por si el zoom se dispara por algún camino que no sea
  /// un toque; `onDoubleTapDown` siempre llega antes que `onDoubleTap`.
  Offset _puntoDelDobleToque = Offset.zero;

  /// Cuánto acerca el doble toque en una página de manga.
  static const _escalaDelAcercado = 2.5;

  void _toggleZoomOut({required bool esTira}) {
    // Cualquier cosa que no sea la identidad se deshace primero: vuelve a 1x
    // Y centrado. El chequeo de antes era `_zoomed`, que sale de comparar la
    // ESCALA contra 1.01 — si el usuario pellizcaba, arrastraba y volvía a
    // achicar hasta más o menos 1x, la escala ya no contaba como zoom pero
    // quedaba una traslación pegada: la página se veía corrida y no había
    // manera de enderezarla. Ahora sí.
    if (_zoomController.value != Matrix4.identity()) {
      setState(() {
        _zoomController.value = Matrix4.identity();
        _zoomed = false;
      });
      return;
    }

    // ── Página de manga: acercar en el punto tocado ───────────────────────
    //
    // Antes acá el doble toque daba vuelta `_zoomedOut`, que SOLO se usa
    // para el ancho de la tira — en una página de manga no se usa en ningún
    // lado, así que el doble toque no hacía absolutamente nada visible. Es
    // el "aún no anda" reportado.
    //
    // La matriz deja quieto el punto tocado: un punto p se dibuja en
    // (p - p·(e-1)·... ) — desarrollado, trasladar -p·(e-1) y después
    // escalar por e manda p a -p·(e-1) + e·p = p. O sea que lo que estabas
    // mirando queda donde estaba y el resto se agranda a su alrededor, que
    // es justo lo pedido: lo mismo, más cerca.
    if (!esTira) {
      final p = _puntoDelDobleToque;
      setState(() {
        _zoomController.value = Matrix4.identity()
          ..translateByDouble(
            -p.dx * (_escalaDelAcercado - 1),
            -p.dy * (_escalaDelAcercado - 1),
            0,
            1,
          )
          ..scaleByDouble(
            _escalaDelAcercado,
            _escalaDelAcercado,
            1,
            1,
          );
        // Habilita el arrastre para pasear por la página ya acercada (ver
        // panEnabled en el InteractiveViewer).
        _zoomed = true;
      });
      return;
    }

    // ── Tira de manhwa: se angosta la columna, anclando el punto tocado ───
    //
    // Mismo problema que tenía la cascada: cambiar el ancho cambia el alto
    // de toda la tira, así que sin corregir el scroll lo que estabas
    // mirando se iba a otro lado.
    //
    // Acá la cuenta es en píxeles porque es un ScrollController común: el
    // punto tocado está a (scroll + y) del principio de la tira; después
    // del cambio ese mismo punto está a (scroll + y)·f. Para que siga
    // cayendo en la misma altura y de la pantalla, el scroll tiene que
    // quedar en (scroll + y)·f - y.
    final y = _puntoDelDobleToque.dy;
    // `_zoomedOut` es todavía el estado de ANTES del toque: si estaba
    // alejado, este toque acerca (la columna se ensancha).
    final f = _zoomedOut ? 1 / _factorAlejadoTira : _factorAlejadoTira;
    final scroll = _stripScrollController.hasClients
        ? _stripScrollController.position.pixels
        : 0.0;
    final destino = (scroll + y) * f - y;

    setState(() => _zoomedOut = !_zoomedOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stripScrollController.hasClients) return;
      final posicion = _stripScrollController.position;
      posicion.jumpTo(destino.clamp(0.0, posicion.maxScrollExtent));
    });
  }

  void _syncZoomFlag() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  // Solo se usa para la tira de manhwa (la página de manga no tiene nada que
  // scrollear, ya entra entera).
  final _stripScrollController = ScrollController();
  static const _pagedScrollbarVisibleWidth = 10.0;
  static const _pagedScrollbarHitWidth = 18.0;
  bool _stripScrollbarReady = false;

  // Forwarding de la rueda: el zoom del InteractiveViewer va apagado en
  // desktop (`scaleEnabled: Platform.isAndroid`, ver más abajo) porque
  // reacciona a CUALQUIER rueda de forma directa e incondicional (confirmado
  // leyendo el código fuente de Flutter — no pasa por el
  // pointerSignalResolver, así que un Listener ancestro no alcanza para
  // frenarlo). Con eso apagado, acá solo queda reenviar el scroll a la tira;
  // el zoom queda a cargo únicamente del doble toque.
  void _handleWheelSignal(PointerSignalEvent event, {required bool isStrip}) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      if (!mounted) return;
      final scroll = e as PointerScrollEvent;
      if (scroll.scrollDelta.dy == 0) return;
      if (isStrip && _stripScrollController.hasClients) {
        final position = _stripScrollController.position;
        final target = (position.pixels + scroll.scrollDelta.dy)
            .clamp(0.0, position.maxScrollExtent);
        position.jumpTo(target);
      }
    });
  }

  void _scheduleStripScrollbarRefresh() {
    if (_stripScrollbarReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stripScrollController.hasClients) return;
      setState(() => _stripScrollbarReady = true);
    });
  }

  Widget _buildPagedStripScrollbar() {
    void jumpToLocalY(double trackHeight, double localY) {
      if (!_stripScrollController.hasClients) return;
      final position = _stripScrollController.position;
      if (position.maxScrollExtent <= 0) return;
      final thumbHeight = _thumbHeight(trackHeight, position);
      final usableTrack = trackHeight - thumbHeight;
      final fraction = usableTrack <= 0
          ? 0.0
          : ((localY - thumbHeight / 2) / usableTrack).clamp(0.0, 1.0);
      position.jumpTo(position.maxScrollExtent * fraction);
    }

    // Mismo criterio que en la cascada: la barra va al hueco, del lado
    // contrario a donde esté pegada la franja. Con la franja a la derecha,
    // dejarla acá la ponía justo encima del manga.
    final aLaIzquierda = widget.stripAlign == Alignment.centerRight;
    return Positioned(
      left: aLaIzquierda ? 2 : null,
      right: aLaIzquierda ? null : 2,
      top: 0,
      bottom: 0,
      width: _pagedScrollbarHitWidth,
      child: LayoutBuilder(
        builder: (context, box) {
          final trackHeight = box.maxHeight;
          return AnimatedBuilder(
            animation: _stripScrollController,
            builder: (context, _) {
              if (!_stripScrollController.hasClients) {
                return const SizedBox.shrink();
              }
              final position = _stripScrollController.position;
              if (position.maxScrollExtent <= 0) {
                return const SizedBox.shrink();
              }
              final thumbHeight = _thumbHeight(trackHeight, position);
              final usableTrack = trackHeight - thumbHeight;
              final top = usableTrack <= 0
                  ? 0.0
                  : usableTrack *
                      (position.pixels / position.maxScrollExtent)
                          .clamp(0.0, 1.0);
              return Listener(
                onPointerSignal: (event) =>
                    _handleWheelSignal(event, isStrip: true),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (d) =>
                      jumpToLocalY(trackHeight, d.localPosition.dy),
                  onVerticalDragUpdate: (d) =>
                      jumpToLocalY(trackHeight, d.localPosition.dy),
                  onTapDown: (d) =>
                      jumpToLocalY(trackHeight, d.localPosition.dy),
                  child: Stack(
                    children: [
                      Positioned(
                        top: top,
                        // El pulgar se arrima al borde exterior, que cambia
                        // con el lado en el que quedó la barra.
                        left: aLaIzquierda ? 0 : null,
                        right: aLaIzquierda ? null : 0,
                        width: _pagedScrollbarVisibleWidth,
                        height: thumbHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(140),
                            borderRadius: BorderRadius.circular(
                              _pagedScrollbarVisibleWidth / 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  double _thumbHeight(double trackHeight, ScrollPosition position) {
    final contentExtent = position.maxScrollExtent + position.viewportDimension;
    if (contentExtent <= 0) return trackHeight;
    return (trackHeight * position.viewportDimension / contentExtent)
        .clamp(32.0, trackHeight);
  }

  @override
  void initState() {
    super.initState();
    final cached = _aspectCache[widget.url];
    if (cached != null) {
      _aspect = cached;
      return;
    }
    _resolveAspect();
  }

  @override
  void didUpdateWidget(covariant _PagedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Red de seguridad: si el PageView llegara a reciclar este State para
    // otra página (mismo slot, url distinta) sin pasar por dispose/initState,
    // el zoom/achicado de la página anterior se veía en la nueva — página
    // corta y angosta con hueco negro abajo, o de entrada agrandada,
    // reportado en vivo. Cada página nueva arranca sin zoom aplicado.
    if (oldWidget.url != widget.url) {
      _zoomedOut = false;
      _zoomed = false;
      _stripScrollbarReady = false;
      _zoomController.value = Matrix4.identity();
      if (_stripScrollController.hasClients) {
        _stripScrollController.jumpTo(0);
      }
      final cached = _aspectCache[widget.url];
      if (cached != null) {
        _aspect = cached;
      } else {
        _aspect = null;
        _resolveAspect();
      }
    }
  }

  void _resolveAspect() {
    // Mismo provider con cache:true que usa CacheNetWorkImagePic para
    // dibujar, así medir no dispara una segunda descarga: el segundo pedido
    // sale del mismo caché.
    final provider = ExtendedNetworkImageProvider(
      widget.url,
      headers: widget.headers,
      cache: true,
    );
    _listener = ImageStreamListener((info, _) {
      final value = info.image.width / info.image.height;
      _aspectCache[widget.url] = value;
      if (!mounted) return;
      setState(() => _aspect = value);
    }, onError: (_, __) {
      // Si no se puede medir, se cae a contain (el comportamiento seguro).
      _aspectCache[widget.url] = 1;
      if (mounted) setState(() => _aspect = 1);
    });
    _stream = provider.resolve(ImageConfiguration.empty)
      ..addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _zoomController.dispose();
    _stripScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = _aspect;
        // Todavía midiendo: SOLO el indicador de carga, nunca la imagen con
        // una disposición provisoria. Antes acá se dibujaba ajustada al alto
        // y un instante después saltaba a su forma definitiva — ese cambio
        // de forma en medio del deslizamiento era justo lo que se veía como
        // "pasaron varias páginas". Mejor un instante de spinner que un
        // salto visual.
        if (aspect == null) return widget.placeholder;

        final viewAspect = constraints.maxWidth / constraints.maxHeight;
        final isTallStrip = aspect < viewAspect / 2;

        if (!isTallStrip) {
          // Manga/cómic: entra entera, sin scroll.
          return Stack(
            children: [
              Listener(
                onPointerSignal: (e) => _handleWheelSignal(e, isStrip: false),
                child: InteractiveViewer(
                  transformationController: _zoomController,
                  maxScale: 5,
                  // scaleEnabled false en desktop: InteractiveViewer reacciona
                  // a CUALQUIER rueda de mouse de forma directa e incondicional
                  // (no pasa por el pointerSignalResolver, así que envolverlo
                  // en un Listener no lo frena — confirmado leyendo el código
                  // fuente de Flutter) por eso zoomeaba igual con o sin Ctrl.
                  // Con scaleEnabled apagado, IV ignora la rueda por completo y
                  // el zoom queda 100% a cargo de _handleWheelSignal/
                  // _applyWheelZoom de acá arriba. En Android se deja
                  // encendido porque ahí sí hace falta para el pellizco real.
                  scaleEnabled: Platform.isAndroid,
                  // panEnabled solo con zoom aplicado: con la página entera a
                  // la vista, InteractiveViewer se quedaba igual con el gesto
                  // de arrastre y el PageView nunca lo recibía — por eso en
                  // celular "a veces no agarraba" el deslizamiento para
                  // cambiar de página (confirmado en vivo). Sin zoom no hay
                  // nada que desplazar, así que no perdemos nada dejándolo
                  // pasar.
                  panEnabled: _zoomed,
                  onInteractionEnd: (_) => _syncZoomFlag(),
                  child: SizedBox.expand(
                    child: CacheNetWorkImagePic(
                      widget.url,
                      width: double.infinity,
                      height: double.infinity,
                      // Llenar pantalla recorta lo que sobre en vez de
                      // dejar la página entera con franjas — ver
                      // ComicController.llenarPantalla.
                      fit:
                          widget.llenarPantalla ? BoxFit.cover : BoxFit.contain,
                      placeholder: widget.placeholder,
                      fallback: const _PagedLoadError(),
                      headers: widget.headers,
                    ),
                  ),
                ),
              ),
              _doubleTapZoomOverlay(esTira: false),
            ],
          );
        }

        // Tira de manhwa: llena el ancho (con un tope legible, igual que la
        // cascada) y se baja con la rueda dentro de la propia página.
        //
        // El scroll cubre TODO el ancho (no solo la tira): igual que en
        // cascada, la rueda tiene que funcionar apunte donde apunte el
        // mouse, también en los márgenes negros de los costados. El clic en
        // la franja de las flechas sigue paginando porque un toque y un
        // arrastre son gestos distintos — el toque no scrollea.
        final fullWidth =
            constraints.maxWidth < 900.0 ? constraints.maxWidth : 900.0;
        // Doble toque = alejar, mismo criterio que la cascada: se angosta la
        // columna al 55% para ver más de la tira de un vistazo.
        final stripWidth =
            _zoomedOut ? fullWidth * _factorAlejadoTira : fullWidth;
        // Algunas tiras, a este ancho, quedan más bajas que la pantalla
        // (panel corto clasificado igual como "tira" por su proporción) y
        // dejaban un hueco negro abajo — reportado en vivo con captura.
        // Relleno con la misma carta default que usa el error de carga, así
        // la página se ve completa hasta el fondo en vez de cortada.
        final imageHeight = stripWidth / aspect;
        final fillerHeight = imageHeight < constraints.maxHeight
            ? constraints.maxHeight - imageHeight
            : 0.0;
        // InteractiveViewer también acá: antes la tira de manhwa en modo
        // paginado era el único caso SIN zoom por pellizco (solo andaba en
        // cascada), reportado en vivo. panEnabled solo con zoom aplicado,
        // mismo motivo que en la página de manga: sin zoom no hay nada que
        // desplazar y así no le roba el gesto al scroll ni al PageView.
        if (!Platform.isAndroid) _scheduleStripScrollbarRefresh();
        return Stack(
          children: [
            Listener(
              onPointerSignal: (e) => _handleWheelSignal(e, isStrip: true),
              child: InteractiveViewer(
                transformationController: _zoomController,
                maxScale: 5,
                // Mismo motivo que en la página de manga: sin esto la rueda
                // zoomeaba siempre, tenga o no Ctrl apretado.
                scaleEnabled: Platform.isAndroid,
                panEnabled: _zoomed,
                onInteractionEnd: (_) => _syncZoomFlag(),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _stripScrollController,
                    child: Align(
                      alignment: widget.stripAlign,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: stripWidth,
                            child: CacheNetWorkImagePic(
                              widget.url,
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                              placeholder: widget.placeholder,
                              fallback: const _PagedLoadError(),
                              headers: widget.headers,
                            ),
                          ),
                          if (fillerHeight > 0)
                            SizedBox(
                              width: stripWidth,
                              height: fillerHeight,
                              // cover, no contain: con contain la carta (casi
                              // cuadrada) quedaba chiquita y centrada dejando
                              // franjas negras alrededor — un cuadradito feo
                              // suelto en medio del hueco, reportado en vivo.
                              // Con cover llena todo el ancho de la tira (la
                              // misma zona que ocupa el manga arriba), recorte
                              // mediante.
                              child: ClipRect(
                                child: Image.asset(
                                  'assets/carddefaultoffline.png',
                                  fit: BoxFit.cover,
                                  width: stripWidth,
                                  height: fillerHeight,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _doubleTapZoomOverlay(esTira: true),
            if (!Platform.isAndroid) _buildPagedStripScrollbar(),
          ],
        );
      },
    );
  }
}

// Respaldo cuando una página no carga, SOLO en modo paginado. La cascada usa
// el logo de la app a pantalla completa, que ahí funciona bien; en paginado
// esa misma imagen se estira a toda la ventana y se ve enorme (confirmado en
// vivo), además de parecer contenido real en vez de un error.
class _PagedLoadError extends StatelessWidget {
  const _PagedLoadError();

  @override
  Widget build(BuildContext context) {
    // Ocupa el lugar de la página que falló, con proporción de página real
    // (~0.7 ancho/alto) en vez de un tamaño fijo chico. Se calcula sobre el
    // espacio disponible, así queda bien tanto en la ventana de PC como en
    // la pantalla de un celular, sin estirarse a toda la ventana (que era el
    // problema original) ni quedar como una miniatura perdida en el medio.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : constraints.maxWidth;
        var height = maxH * 0.72;
        var width = height * 0.7;
        if (width > constraints.maxWidth * 0.85) {
          width = constraints.maxWidth * 0.85;
          height = width / 0.7;
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/carddefaultoffline.png',
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'reader.page-load-failed'.i18n,
                // Va sobre el fondo de la zona de lectura, que ahora sigue al
                // modo: si se quedaba en el gris claro, en modo claro no se
                // leía el aviso de que la página no cargó.
                style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}
