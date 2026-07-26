import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/watch/novel_controller.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/views/pages/watch/reader/novel/novel_reader_content.dart';
import 'package:prismhub/views/pages/watch/reader/novel/novel_reader_settings.dart';
import 'package:prismhub/views/widgets/watch/reader_view.dart';
import 'package:prismhub/data/services/extension_service.dart';

class NovelReader extends StatefulWidget {
  const NovelReader({
    super.key,
    required this.playList,
    required this.runtime,
    required this.episodeGroupId,
    required this.playerIndex,
    required this.title,
    required this.detailUrl,
    required this.anilistID,
    this.cover,
    this.cameFromDetail = false,
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

  @override
  State<NovelReader> createState() => _NovelReaderState();
}

class _NovelReaderState extends State<NovelReader> {
  late final String _tag = ReaderController.buildTag(
      widget.title, widget.detailUrl, widget.episodeGroupId);

  @override
  void initState() {
    Get.put(
      NovelController(
        title: widget.title,
        playList: widget.playList,
        detailUrl: widget.detailUrl,
        playIndex: widget.playerIndex,
        episodeGroupId: widget.episodeGroupId,
        runtime: widget.runtime,
        cover: widget.cover,
        anilistID: widget.anilistID,
        cameFromDetail: widget.cameFromDetail,
      ),
      tag: _tag,
    );
    super.initState();
  }

  @override
  void dispose() {
    Get.delete<NovelController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderView<NovelController>(
      _tag,
      content: NovelReaderContent(_tag),
      buildSettings: (context) => NovelReaderSettings(_tag),
    );
  }
}
