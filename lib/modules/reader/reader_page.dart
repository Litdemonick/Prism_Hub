import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _c = Get.put(ReaderController(), tag: widget.args.episodeUrl);
    _c.load(widget.args.episodeUrl, widget.args.package);
  }

  @override
  void dispose() {
    _pageController.dispose();
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
                '${_c.currentPage.value + 1} / $total',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              );
            }),
          ],
        ),
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
                  Icons.error_outline,
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

        return PageView.builder(
          controller: _pageController,
          itemCount: _c.pages.length,
          onPageChanged: (i) => _c.currentPage.value = i,
          itemBuilder: (_, i) => _ImagePage(url: _c.pages[i]),
        );
      }),
    );
  }
}

class _ImagePage extends StatelessWidget {
  const _ImagePage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: CachedNetworkImage(
        imageUrl: url,
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
    );
  }
}
