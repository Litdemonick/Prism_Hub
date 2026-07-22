import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/comic_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
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

  @override
  void dispose() {
    _androidPinchTransform.dispose();
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
        final dy = (e as PointerScrollEvent).scrollDelta.dy;
        final target =
            (_cascadeScrollOffset + dy).clamp(0.0, _cascadeScrollMax);
        if (target == _cascadeScrollOffset) return;
        final position = _cascadeScrollPosition;
        if (position != null) {
          position.jumpTo(target);
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

  _buildPlaceholder(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      width: width,
      height: height,
      child: const Center(child: ProgressRing()),
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
    late Color backgroundColor;
    if (Platform.isAndroid) {
      backgroundColor = Theme.of(context).colorScheme.surface;
    } else {
      backgroundColor = fluent.FluentTheme.of(context).micaBackgroundColor;
    }

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
        focusNode: FocusNode(),
        autofocus: true,
        onKeyEvent: _c.onKey,
        child: Container(
          color: backgroundColor,
          width: double.infinity,
          child: LayoutBuilder(
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

                final images = _c.watchData.value!.urls;
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
                    if (_cascadeScrollPosition == null && n.context != null) {
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
