import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/extension_model.dart';
import '../../data/models/watch_data.dart';
import '../player/watch_args.dart';
import 'reader_controller.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.args});
  final WatchArgs args;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final ReaderController _c;
  bool _verticalScroll = true; // manga: scroll vertical por defecto

  bool get _isMangaType => switch (widget.args.type) {
    ExtensionType.manga || ExtensionType.comic => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _verticalScroll = _isMangaType;
    _c = Get.put(ReaderController(), tag: widget.args.episodeUrl);
    _c.load(widget.args.episodeUrl, widget.args.package);
  }

  @override
  void dispose() {
    Get.delete<ReaderController>(tag: widget.args.episodeUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.args.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            Obx(() {
              final total = _c.pages.length;
              if (total == 0) return const SizedBox.shrink();
              return Text(
                _verticalScroll
                    ? '$total páginas'
                    : '${_c.currentPage.value + 1} / $total',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              );
            }),
          ],
        ),
        actions: [
          // Toggle modo lectura
          Obx(() {
            if (_c.pages.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: Icon(
                _verticalScroll
                    ? Icons.view_day_outlined
                    : Icons.swipe_outlined,
                color: Colors.white,
              ),
              tooltip: _verticalScroll ? 'Modo horizontal' : 'Modo vertical',
              onPressed: () => setState(() => _verticalScroll = !_verticalScroll),
            );
          }),
        ],
      ),
      body: Obx(() {
        if (_c.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (_c.error.value != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  _c.error.value!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (_c.pages.isEmpty) {
          return const Center(
            child: Text(
              'Sin páginas disponibles',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return _verticalScroll
            ? _VerticalReader(pages: _c.pages.toList())
            : _HorizontalReader(
                pages: _c.pages.toList(),
                currentPage: _c.currentPage,
              );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo scroll vertical (manga)
// ---------------------------------------------------------------------------

class _VerticalReader extends StatelessWidget {
  const _VerticalReader({required this.pages});
  final List<WatchStream> pages;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: pages.length,
      itemBuilder: (_, i) => CachedNetworkImage(
        imageUrl: pages[i].url,
        httpHeaders: pages[i].headers,
        fit: BoxFit.fitWidth,
        width: double.infinity,
        placeholder: (ctx, url) => const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator(color: Colors.white54)),
        ),
        errorWidget: (ctx, url, err) => const SizedBox(
          height: 200,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white30,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo horizontal (página a página)
// ---------------------------------------------------------------------------

class _HorizontalReader extends StatefulWidget {
  const _HorizontalReader({required this.pages, required this.currentPage});
  final List<WatchStream> pages;
  final RxInt currentPage;

  @override
  State<_HorizontalReader> createState() => _HorizontalReaderState();
}

class _HorizontalReaderState extends State<_HorizontalReader> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.currentPage.value);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      itemCount: widget.pages.length,
      onPageChanged: (i) => widget.currentPage.value = i,
      itemBuilder: (_, i) => InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: CachedNetworkImage(
          imageUrl: widget.pages[i].url,
          httpHeaders: widget.pages[i].headers,
          fit: BoxFit.contain,
          placeholder: (ctx, url) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (ctx, url, err) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
