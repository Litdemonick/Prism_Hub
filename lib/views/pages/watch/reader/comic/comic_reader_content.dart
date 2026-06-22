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
import 'package:extended_image/extended_image.dart';

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

  late final _c = Get.find<ComicController>(tag: widget.tag);

  final List<int> _pointer = [];

  _buildPlaceholder(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      width: width,
      height: height,
      child: const Center(child: ProgressRing()),
    );
  }

  // ── Small icon button used for mode and chapter toggles ──────────────────

  Widget _buildIconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final isAndroid = Platform.isAndroid;
    // Android: 48×48 dp minimum tap target per Material guidelines.
    final iconSize = isAndroid ? 22.0 : 18.0;
    final padding = isAndroid ? 13.0 : 6.0;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withAlpha(60)
                : Colors.black.withAlpha(120),
            borderRadius: BorderRadius.circular(isAndroid ? 8 : 4),
          ),
          child: Icon(
            icon,
            color: active ? Colors.white : Colors.white54,
            size: iconSize,
          ),
        ),
      ),
    );
  }

  // ── Top overlay: chapter nav (left) + mode toggle (right) ────────────────
  // Positioned just below the 40 px header so it never conflicts with it.

  Widget _buildTopOverlay() {
    return Obx(() {
      final readerType = _c.readType.value;
      final hasPrev = _c.index.value > 0;
      final hasNext = _c.index.value < _c.playList.length - 1;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ← previous chapter
          if (hasPrev)
            _buildIconBtn(
              icon: Icons.skip_previous,
              tooltip: 'Capítulo anterior',
              onTap: () => _c.index.value--,
            ),
          if (hasPrev) const SizedBox(width: 4),
          // → next chapter
          if (hasNext)
            _buildIconBtn(
              icon: Icons.skip_next,
              tooltip: 'Capítulo siguiente',
              onTap: () => _c.index.value++,
            ),
          if (hasNext) const SizedBox(width: 8),
          // Cascade / Pages mode toggles
          _buildIconBtn(
            icon: Icons.view_day,
            tooltip: 'Cascada',
            onTap: () => _c.readType.value = MangaReadMode.webTonn,
            active: readerType == MangaReadMode.webTonn,
          ),
          const SizedBox(width: 4),
          _buildIconBtn(
            icon: Icons.menu_book,
            tooltip: 'Páginas',
            onTap: () => _c.readType.value = MangaReadMode.standard,
            active: readerType == MangaReadMode.standard,
          ),
        ],
      );
    });
  }

  // ── Bottom bar: counter + page nav (page mode) or just counter (cascade) ─

  Widget _buildBottomBar() {
    return Obx(() {
      final readerType = _c.readType.value;
      final total = _c.watchData.value?.urls.length ?? 0;
      final page = _c.currentPage.value;

      final counter = Text(
        '${page + 1}/$total',
        style: const TextStyle(color: Colors.white, fontSize: 15),
      );

      if (readerType == MangaReadMode.webTonn) {
        // Cascade: just the position counter
        return Container(
          color: Colors.black.withAlpha(200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: counter,
        );
      }

      // Page mode: prev-page | counter | next-page
      return Container(
        color: Colors.black.withAlpha(200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (page > 0)
              _buildNavBtn(
                label: 'common.previous'.i18n,
                onTap: _c.previousPage,
              ),
            if (page > 0) const SizedBox(width: 8),
            counter,
            if (total > 0 && page < total - 1) const SizedBox(width: 8),
            if (total > 0 && page < total - 1)
              _buildNavBtn(
                label: 'common.next'.i18n,
                onTap: _c.nextPage,
              ),
          ],
        ),
      );
    });
  }

  Widget _buildNavBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
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
        // Top-right: chapter nav + mode toggles
        Positioned(
          top: isAndroid ? 12 : 48,
          right: 8,
          child: overlay(_buildTopOverlay()),
        ),
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

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: _c.onKey,
      child: Container(
        color: backgroundColor,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
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
              final readerType = _c.readType.value;
              final currentPage = _c.currentPage.value;

              // Cascade: cap content at 900 px so Mica background shows on sides.
              final cascadePadding =
                  maxWidth > 900 ? (maxWidth - 900) / 2 : 0.0;

              // ── Cascade (webtoon) mode ───────────────────────────────────
              // SizedBox with screen dimensions gives ScrollablePositionedList
              // a bounded width. Images receive width:infinity so they fill
              // the available area (constrained by the list to maxWidth).
              if (readerType == MangaReadMode.webTonn) {
                final sw = MediaQuery.of(context).size.width;
                final sh = MediaQuery.of(context).size.height;
                return SizedBox(
                  width: sw,
                  height: sh,
                  child: Listener(
                    onPointerDown: (event) {
                      _pointer.add(event.pointer);
                      if (_pointer.length == 2) _c.isZoom.value = true;
                    },
                    onPointerUp: (event) {
                      _pointer.remove(event.pointer);
                      if (_pointer.length == 1) _c.isZoom.value = false;
                    },
                    child: InteractiveViewer(
                      scaleEnabled: _c.isZoom.value,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          // Auto-hide UI during scroll on Android for
                          // immersive reading; it comes back on single tap.
                          if (Platform.isAndroid) {
                            if (n is ScrollStartNotification) {
                              _c.isShowControlPanel.value = false;
                            }
                          }
                          return false;
                        },
                        child: ScrollablePositionedList.builder(
                          physics: _c.isZoom.value
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          padding: EdgeInsets.symmetric(
                              horizontal: cascadePadding),
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
                      ),
                    ),
                  ),
                );
              }

              // ── Page-by-page mode (standard / rightToLeft) ───────────────
              final isDesktop = !Platform.isAndroid;

              return Listener(
                onPointerSignal: isDesktop
                    ? (event) {
                        if (event is PointerScrollEvent) {
                          GestureBinding.instance.pointerSignalResolver
                              .register(event, (event) {
                            final delta =
                                (event as PointerScrollEvent).scrollDelta;
                            if (delta.dy > 0) {
                              _c.nextPage();
                            } else if (delta.dy < 0) {
                              _c.previousPage();
                            }
                          });
                        }
                      }
                    : null,
                child: ExtendedImageGesturePageView.builder(
                  itemCount: images.length,
                  reverse: readerType == MangaReadMode.rightToLeft,
                  onPageChanged: (index) {
                    _c.currentPage.value = index;
                  },
                  scrollDirection: Axis.horizontal,
                  controller: _c.pageController.value,
                  itemBuilder: (context, index) {
                    final url = images[index];
                    // width/height infinity fill the PageView cell (sw×sh).
                    // BoxFit.contain scales the portrait image to the screen
                    // height; the Mica background is naturally visible on the
                    // sides as letterbox — no explicit padding needed.
                    return CacheNetWorkImagePic(
                      url,
                      width: double.infinity,
                      height: double.infinity,
                      mode: isDesktop
                          ? ExtendedImageMode.none
                          : ExtendedImageMode.gesture,
                      key: ValueKey(url),
                      fit: BoxFit.contain,
                      placeholder: _buildPlaceholder(context),
                      headers: _c.watchData.value?.headers,
                    );
                  },
                ),
              );
            });
          },
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
