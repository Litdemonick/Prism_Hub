import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/comic_controller.dart';
import 'package:prismhub/utils/i18n.dart';
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

  // Desktop-only: double-click narrows the content column for an overview.
  // Narrowing/widening resizes every image (BoxFit.fitWidth recalculates
  // each item's height), which shifts the whole scroll extent — without
  // re-anchoring, the same pixel offset now points at a different page, so
  // the view appears to jump. Re-jump to the page you were on once the
  // resized layout has been painted.
  void _onCascadeDoubleTap() {
    final page = _c.currentPage.value;
    setState(() => _cascadeZoomed = !_cascadeZoomed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _c.itemScrollController.isAttached) {
        _c.itemScrollController.jumpTo(index: page);
      }
    });
  }

  // Custom track+thumb standing in for the native Scrollbar in cascade mode.
  // ScrollablePositionedList only learns each item's real pixel height once
  // it renders (lazy network images), so a PIXEL-based scrollbar drag maps
  // to a wildly wrong distance as that estimate keeps shifting underneath
  // it. Tracking by ITEM INDEX instead is always exact — itemCount never
  // changes — so a drag tracks the mouse 1:1 with no jump/lurch.
  static const _cascadeScrollbarWidth = 10.0;

  Widget _buildCascadeScrollbar(int itemCount) {
    if (itemCount <= 1) return const SizedBox.shrink();

    double thumbHeightFor(double trackHeight) =>
        (trackHeight / itemCount * 3).clamp(32.0, trackHeight);

    void jumpToLocalY(double trackHeight, double localY) {
      final thumbHeight = thumbHeightFor(trackHeight);
      final usableTrack = trackHeight - thumbHeight;
      final fraction = usableTrack <= 0
          ? 0.0
          : ((localY - thumbHeight / 2) / usableTrack).clamp(0.0, 1.0);
      final index = (fraction * (itemCount - 1)).round();
      if (_c.itemScrollController.isAttached) {
        _c.itemScrollController.jumpTo(index: index);
      }
    }

    return Positioned(
      right: 2,
      top: 0,
      bottom: 0,
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

      return Container(
        color: Colors.black.withAlpha(200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Text(
          '${page + 1}/$total',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      );
    });
  }

  // ── Full display overlay (wraps content) ─────────────────────────────────

  Widget _buildDisplay(Widget child) {
    final isAndroid = Platform.isAndroid;
    // On Android, overlays fade in/out with isShowControlPanel so reading is
    // immersive (scrolling hides them; single tap brings them back).
    Widget overlay(Widget w) {
      if (!isAndroid) return w;
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
    const backgroundColor = HomeTheme.bg;

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
        onKeyEvent: _c.onKey,
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
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final maxHeight = constraints.maxHeight;
                return Obx(() {
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
                              // Placeholder discreto (no el logo a pantalla
                              // completa que usa la cascada): en paginado ese
                              // logo ocupa toda la pantalla y se confunde con
                              // una página de verdad, dando la sensación de
                              // haber saltado varias.
                              placeholder: const Center(child: ProgressRing()),
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
                                  enabled: _c.currentPage.value > 0,
                                )),
                            Obx(() => _PageArrow(
                                  left: false,
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
                  final currentPage = _c.currentPage.value;

                  // Cascade: cap content at 900 px normally; narrow to ~55% when
                  // zoomed out so images shrink but still fill edge-to-edge (no box).
                  final normalWidth = maxWidth < 900.0 ? maxWidth : 900.0;
                  final effectiveWidth =
                      _cascadeZoomed ? normalWidth * 0.55 : normalWidth;
                  final cascadePadding = maxWidth > effectiveWidth
                      ? (maxWidth - effectiveWidth) / 2
                      : 0.0;

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
                      }
                      return false;
                    },
                    child: ScrollablePositionedList.builder(
                      physics: (_c.isZoom.value || _androidPinching)
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      padding: EdgeInsets.symmetric(horizontal: cascadePadding),
                      initialScrollIndex: currentPage,
                      itemScrollController: _c.itemScrollController,
                      itemPositionsListener: _c.itemPositionsListener,
                      scrollOffsetController: _c.scrollOffsetController,
                      itemBuilder: (context, index) {
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

                    // Space reserved on the right so the opaque border-absorber
                    // doesn't sit on top of (and swallow every click meant for)
                    // the custom scrollbar's own hit area.
                    const scrollbarStrip = _cascadeScrollbarWidth + 6;

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
                              onDoubleTap: _onCascadeDoubleTap,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(scrollbars: false),
                                child: scrollList,
                              ),
                            ),
                            if (cascadePadding > 0) ...[
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                width: cascadePadding,
                                child: borderAbsorber(),
                              ),
                              Positioned(
                                right: scrollbarStrip,
                                top: 0,
                                bottom: 0,
                                width: (cascadePadding - scrollbarStrip)
                                    .clamp(0.0, double.infinity),
                                child: borderAbsorber(),
                              ),
                            ],
                            _buildCascadeScrollbar(images.length),
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
      androidBuilder: (context) => Scaffold(
        body: SafeArea(child: _buildDisplay(_buildContent())),
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
  });

  final bool left;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Deshabilitada (primera/última página): no se dibuja nada, así no queda
    // una flecha sugiriendo que hay algo más.
    if (!enabled) return const SizedBox.shrink();
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
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
          width: 64,
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
  });

  final String url;
  final Map<String, String>? headers;
  final Widget placeholder;

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
  Widget _doubleTapZoomOverlay() {
    final inset = Platform.isAndroid ? 0.0 : 80.0;
    return Positioned(
      left: inset,
      right: inset,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _toggleZoomOut,
      ),
    );
  }

  void _toggleZoomOut() {
    setState(() {
      _zoomedOut = !_zoomedOut;
      // Página de manga: el "alejar" no aplica (ya entra entera), así que el
      // doble toque sirve para volver a 1x si se había acercado con pinza.
      if (_zoomed) {
        _zoomController.value = Matrix4.identity();
        _zoomed = false;
      }
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

    return Positioned(
      right: 2,
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
                        right: 0,
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
                      fit: BoxFit.contain,
                      placeholder: widget.placeholder,
                      fallback: const _PagedLoadError(),
                      headers: widget.headers,
                    ),
                  ),
                ),
              ),
              _doubleTapZoomOverlay(),
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
        final stripWidth = _zoomedOut ? fullWidth * 0.55 : fullWidth;
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
                    child: Center(
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
            _doubleTapZoomOverlay(),
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
                style:
                    const TextStyle(color: HomeTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}
