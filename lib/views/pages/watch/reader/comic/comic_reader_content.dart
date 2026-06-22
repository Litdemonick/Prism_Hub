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
  }

  late final _c = Get.find<ComicController>(tag: widget.tag);

  final List<int> _pointer = [];

  _buildPlaceholder(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: Center(
          child: ProgressRing(),
        ),
      ),
    );
  }

  Widget _buildModeBtn(IconData icon, String label, MangaReadMode mode) {
    final active = _c.readType.value == mode;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: () => _c.readType.value = mode,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withAlpha(60)
                : Colors.black.withAlpha(120),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            color: active ? Colors.white : Colors.white54,
            size: 18,
          ),
        ),
      ),
    );
  }

  _buildDisplay(Widget child) {
    return Stack(
      children: [
        child,
        // Page / position counter
        Positioned(
          bottom: 0,
          child: Container(
            color: Colors.black.withAlpha(200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: Obx(
              () => Text(
                "${_c.currentPage.value + 1}/${_c.watchData.value?.urls.length ?? 0}",
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ),
        // Quick mode-toggle buttons — hidden while control panel is visible
        // to avoid overlapping the Siguiente/Anterior chapter buttons.
        Positioned(
          bottom: 2,
          right: 8,
          child: Obx(() {
            if (_c.isShowControlPanel.value) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeBtn(
                    Icons.view_day, 'Cascada', MangaReadMode.webTonn),
                const SizedBox(width: 4),
                _buildModeBtn(
                    Icons.menu_book, 'Páginas', MangaReadMode.standard),
              ],
            );
          }),
        ),
      ],
    );
  }

  _buildContent() {
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
          builder: ((context, constraints) {
            final maxWidth = constraints.maxWidth;
            return Obx(() {
              if (_c.error.value.isNotEmpty) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_c.error.value),
                    PlatformButton(
                      child: Text('common.retry'.i18n),
                      onPressed: () {
                        _c.getContent();
                      },
                    )
                  ],
                );
              }

              if (_c.watchData.value == null) {
                return const Center(child: ProgressRing());
              }

              final viewPadding =
                  maxWidth > 800 ? ((maxWidth - 800) / 2) : 0.0;
              final images = _c.watchData.value!.urls;
              final readerType = _c.readType.value;
              final cuurentPage = _c.currentPage.value;

              // ── Cascade (webtoon) mode ─────────────────────────────────────
              if (readerType == MangaReadMode.webTonn) {
                final width = MediaQuery.of(context).size.width;
                final height = MediaQuery.of(context).size.height;
                return SizedBox(
                  width: width,
                  height: height,
                  child: Listener(
                    onPointerDown: (event) {
                      _pointer.add(event.pointer);
                      if (_pointer.length == 2) {
                        _c.isZoom.value = true;
                      }
                    },
                    onPointerUp: (event) {
                      _pointer.remove(event.pointer);
                      if (_pointer.length == 1) {
                        _c.isZoom.value = false;
                      }
                    },
                    child: InteractiveViewer(
                      scaleEnabled: _c.isZoom.value,
                      child: ScrollablePositionedList.builder(
                        physics: _c.isZoom.value
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        padding: EdgeInsets.symmetric(
                          horizontal: viewPadding,
                        ),
                        initialScrollIndex: cuurentPage,
                        itemScrollController: _c.itemScrollController,
                        itemPositionsListener: _c.itemPositionsListener,
                        scrollOffsetController: _c.scrollOffsetController,
                        itemBuilder: (context, index) {
                          final url = images[index];
                          return CacheNetWorkImagePic(
                            url,
                            fit: BoxFit.fitWidth,
                            placeholder: _buildPlaceholder(context),
                            headers: _c.watchData.value?.headers,
                          );
                        },
                        itemCount: images.length,
                      ),
                    ),
                  ),
                );
              }

              // ── Page-by-page mode (standard / rightToLeft) ─────────────────
              // On desktop: images use ExtendedImageMode.none so the scroll
              // wheel is NOT consumed by ExtendedImage for zoom. A Listener
              // wrapping the page view claims scroll events and converts them
              // to page navigation. Pinch-to-zoom is kept on Android via
              // ExtendedImageMode.gesture.
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
                  itemBuilder: (BuildContext context, int index) {
                    final url = images[index];
                    return Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: viewPadding,
                      ),
                      child: CacheNetWorkImagePic(
                        url,
                        mode: isDesktop
                            ? ExtendedImageMode.none
                            : ExtendedImageMode.gesture,
                        key: ValueKey(url),
                        fit: BoxFit.contain,
                        placeholder: _buildPlaceholder(context),
                        headers: _c.watchData.value?.headers,
                      ),
                    );
                  },
                ),
              );
            });
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: (context) {
        return Scaffold(
            body: SafeArea(
          child: _buildDisplay(
            _buildContent(),
          ),
        ));
      },
      desktopBuilder: (context) => _buildDisplay(
        _buildContent(),
      ),
    );
  }
}
