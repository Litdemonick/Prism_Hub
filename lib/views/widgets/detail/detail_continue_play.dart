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
    this.comoFab = false,
  });
  final String? tag;

  /// Dibujarse como botón flotante en vez de como botón de una fila.
  ///
  /// En la ficha de Android la acción principal se fue de la cabecera al botón
  /// flotante: ahí no se lleva alto de la cabecera —que en un teléfono en
  /// vertical es lo que escasea— y, sobre todo, no desaparece al hacer scroll.
  /// Antes se plegaba con la cabecera justo cuando uno estaba mirando la lista
  /// y quería darle a leer.
  final bool comoFab;

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
          foregroundColor: WidgetStateProperty.all(HomeTheme.contraste),
          minimumSize: WidgetStateProperty.all(
            const Size(double.infinity, 42),
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: Colors.white24, width: 1.5),
          ),
        ),
      );

      final history = c.history.value;
      final data = c.detail;

      if (widget.comoFab) {
        // Se arma una sola vez la etiqueta y la acción, y después se dibuja:
        // las tres ramas de abajo repiten el mismo botón con otro texto, y
        // acá con el flotante ese enredo no hace falta.
        String etiqueta = watchNowString;
        VoidCallback? accion;
        if (!c.isLoading.value) {
          if (_canContinue(history)) {
            final h = history!;
            etiqueta = FlutterI18n.translate(
              context,
              'detail.continue-watching',
              translationParams: {'episode': _episodeLabel(h)},
            );
            accion = () => c.goWatch(
                  context,
                  data!.episodes![h.episodeGroupId].urls,
                  h.episodeId,
                  h.episodeGroupId,
                  autoResume: true,
                );
          } else if (data?.episodes != null && data!.episodes!.isNotEmpty) {
            accion = () => c.goWatch(context, data.episodes![0].urls, 0, 0);
          }
        }
        // Sin nada que abrir no se dibuja nada. Un botón flotante apagado
        // ocupa la esquina y no hace nada; que no hay capítulos ya lo dice la
        // lista, que es donde uno lo va a buscar.
        if (accion == null) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          onPressed: accion,
          backgroundColor: HomeTheme.accentPink,
          foregroundColor: HomeTheme.bg,
          icon: const Icon(Icons.play_arrow_rounded),
          label: ConstrainedBox(
            // Tope al ancho: "Continuar Capítulo 128" en un teléfono angosto
            // dejaba el botón cruzando la pantalla de lado a lado.
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      }

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
              const Size(double.infinity, 42),
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
              const Size(double.infinity, 42),
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
