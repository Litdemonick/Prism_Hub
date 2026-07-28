import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class DetailContinuePlay extends StatefulWidget {
  const DetailContinuePlay({
    super.key,
    this.tag,
  });
  final String? tag;

  @override
  State<DetailContinuePlay> createState() => _DetailContinuePlayState();
}

class _DetailContinuePlayState extends State<DetailContinuePlay> {
  late DetailPageController c = Get.find<DetailPageController>(tag: widget.tag);

  bool _canContinue(History? history) {
    final episodes = c.detail?.episodes;
    if (history == null || history.episodeTitle.isEmpty) return false;
    if (episodes == null || episodes.isEmpty) return false;
    if (history.episodeGroupId < 0 ||
        history.episodeGroupId >= episodes.length) {
      return false;
    }
    final urls = episodes[history.episodeGroupId].urls;
    return history.episodeId >= 0 && history.episodeId < urls.length;
  }

  // episodeTitle a veces queda igual al título de la obra (sin número
  // propio) — el número real (extraído del título si lo trae, o la
  // posición como última opción) es lo que de verdad identifica en qué
  // episodio/capítulo vas.
  String _episodeLabel(History history) {
    final number = ExtensionUtils.episodeNumberLabel(
        history.episodeTitle, history.episodeId);
    return c.type == ExtensionType.bangumi
        ? FlutterI18n.translate(context, 'detail.episode-label',
            translationParams: {'ep': number})
        : FlutterI18n.translate(context, 'detail.chapter-label',
            translationParams: {'ep': number});
  }

  Widget _buildAndroid(BuildContext context) {
    return Obx(() {
      late String noEpisodesString;
      late String watchNowString;
      if (c.type == ExtensionType.bangumi) {
        noEpisodesString = 'video.no-episodes'.i18n;
        watchNowString = 'video.watch-now'.i18n;
      } else {
        noEpisodesString = 'reader.no-chapters'.i18n;
        watchNowString = 'reader.read-now'.i18n;
      }

      final noEpisodes = FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.play_arrow),
        label: Text(noEpisodesString),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.grey),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          minimumSize: WidgetStateProperty.all(
            const Size(double.infinity, 50),
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: Colors.white24, width: 1.5),
          ),
        ),
      );

      final history = c.history.value;
      final data = c.detail;
      if (c.isLoading.value) {
        return noEpisodes;
      }
      // 之前弄错了，所以需要判断标题是否为空
      if (_canContinue(history)) {
        final continueHistory = history!;
        return FilledButton.icon(
          onPressed: () {
            c.goWatch(
              context,
              data!.episodes![continueHistory.episodeGroupId].urls,
              continueHistory.episodeId,
              continueHistory.episodeGroupId,
              autoResume: true,
            );
          },
          icon: const Icon(Icons.play_arrow),
          label: Text(
            FlutterI18n.translate(
              context,
              'detail.continue-watching',
              translationParams: {
                'episode': _episodeLabel(continueHistory),
              },
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(
              const Size(double.infinity, 50),
            ),
            side: WidgetStateProperty.all(
              BorderSide(
                  color: HomeTheme.accentPink.withValues(alpha: 0.6),
                  width: 1.5),
            ),
          ),
        );
      }
      if (data!.episodes != null && data.episodes!.isNotEmpty) {
        return FilledButton.icon(
          onPressed: () {
            c.goWatch(
              context,
              data.episodes![0].urls,
              0,
              0,
            );
          },
          icon: const Icon(Icons.play_arrow),
          label: Text(watchNowString),
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(
              const Size(double.infinity, 50),
            ),
            side: WidgetStateProperty.all(
              BorderSide(
                  color: HomeTheme.accentPink.withValues(alpha: 0.6),
                  width: 1.5),
            ),
          ),
        );
      }
      return noEpisodes;
    });
  }

  Widget _buildDesktop(BuildContext context) {
    return Obx(() {
      final history = c.history.value;
      final data = c.detail!;
      if (_canContinue(history)) {
        final continueHistory = history!;
        return fluent.Button(
          style: fluent.ButtonStyle(
            backgroundColor:
                fluent.WidgetStateProperty.all(HomeTheme.accentPink),
            foregroundColor: fluent.WidgetStateProperty.all(HomeTheme.bg),
            shape: fluent.WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
          onPressed: () {
            c.goWatch(
              context,
              data.episodes![continueHistory.episodeGroupId].urls,
              continueHistory.episodeId,
              continueHistory.episodeGroupId,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(fluent.FluentIcons.play, size: 14),
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(
                    maxWidth: 150,
                  ),
                  child: Text(
                    FlutterI18n.translate(
                      context,
                      'detail.continue-watching',
                      translationParams: {
                        'episode': _episodeLabel(continueHistory),
                      },
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                )
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
