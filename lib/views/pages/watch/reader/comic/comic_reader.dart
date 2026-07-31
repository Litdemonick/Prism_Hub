import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/pages/watch/reader/comic/comic_reader_content.dart';
import 'package:prismhub/views/pages/watch/reader/comic/comic_reader_settings.dart';
import 'package:prismhub/controllers/watch/comic_controller.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart' as prism_progress;
// import 'package:prismhub/views/pages/watch/reader/comic/comic_zoom.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/views/widgets/watch/reader_view.dart';

class ComicReader extends StatefulWidget {
  const ComicReader({
    super.key,
    required this.title,
    required this.playList,
    required this.detailUrl,
    required this.playerIndex,
    required this.episodeGroupId,
    required this.runtime,
    required this.anilistID,
    this.cover,
    this.cameFromDetail = false,
    this.isNsfw = false,
  });

  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playerIndex;
  final int episodeGroupId;
  final ExtensionService runtime;
  final String? cover;
  final String anilistID;
  final bool cameFromDetail;
  final bool isNsfw;

  @override
  State<ComicReader> createState() => _ComicReaderState();
}

class _ComicReaderState extends State<ComicReader> {
  late final String _tag = ReaderController.buildTag(
      widget.title, widget.detailUrl, widget.episodeGroupId);
  bool _ready = false;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Get.put(
        ComicController(
          title: widget.title,
          playList: widget.playList,
          detailUrl: widget.detailUrl,
          playIndex: widget.playerIndex,
          episodeGroupId: widget.episodeGroupId,
          runtime: widget.runtime,
          cover: widget.cover,
          anilistID: widget.anilistID,
          cameFromDetail: widget.cameFromDetail,
          isNsfw: widget.isNsfw,
        ),
        tag: _tag,
      );
      _registered = true;
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    if (_registered) {
      Get.delete<ComicController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const material.ColoredBox(
        color: material.Colors.black,
        child: material.Center(child: prism_progress.ProgressRing()),
      );
    }

    return ReaderView<ComicController>(
      _tag,
      content: PlatformWidget(
          androidWidget: ComicReaderContent(_tag),
          // DragToMoveArea removed: double-clicking buttons was triggering
          // window maximize/restore via the drag-to-move hook.
          desktopWidget: ComicReaderContent(_tag)),
      // Selector de modo de lectura (cascada / página a página, izq→der o
      // der→izq). Vuelve a haber algo que configurar, así que el botón del
      // engranaje se muestra de nuevo.
      buildSettings: (context) => ComicReaderSettings(_tag),
      // Comic reader handles its own page/chapter navigation in the content
      // overlay, so we suppress the generic chapter-navigation footer.
      buildFooter: (_) => const SizedBox.shrink(),
    );
  }
}
