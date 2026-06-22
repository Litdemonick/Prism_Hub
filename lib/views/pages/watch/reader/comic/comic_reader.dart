import 'package:fluent_ui/fluent_ui.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/pages/watch/reader/comic/comic_reader_content.dart';
import 'package:prismhub/views/pages/watch/reader/comic/comic_reader_settings.dart';
import 'package:prismhub/controllers/watch/comic_controller.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
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
  });

  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playerIndex;
  final int episodeGroupId;
  final ExtensionService runtime;
  final String? cover;
  final String anilistID;

  @override
  State<ComicReader> createState() => _ComicReaderState();
}

class _ComicReaderState extends State<ComicReader> {
  @override
  void initState() {
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
      ),
      tag: widget.title,
    );
    super.initState();
  }

  @override
  void dispose() {
    Get.delete<ComicController>(tag: widget.title);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderView<ComicController>(
      widget.title,
      content: PlatformWidget(
          androidWidget: ComicReaderContent(widget.title),
          // DragToMoveArea removed: double-clicking buttons was triggering
          // window maximize/restore via the drag-to-move hook.
          desktopWidget: ComicReaderContent(widget.title)),
      buildSettings: (context) => ComicReaderSettings(widget.title),
      // Comic reader handles its own page/chapter navigation in the content
      // overlay, so we suppress the generic chapter-navigation footer.
      buildFooter: (_) => const SizedBox.shrink(),
    );
  }
}
