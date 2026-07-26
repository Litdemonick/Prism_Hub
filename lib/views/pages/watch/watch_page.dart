import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/pages/watch/reader/comic/comic_reader.dart';
import 'package:prismhub/views/pages/watch/reader/novel/novel_reader.dart';
import 'package:prismhub/views/pages/watch/video/video_player.dart';
import 'package:prismhub/utils/extension.dart';

class WatchPage extends StatelessWidget {
  const WatchPage({
    super.key,
    required this.playList,
    required this.package,
    required this.title,
    required this.playerIndex,
    required this.episodeGroupId,
    required this.detailUrl,
    required this.anilistID,
    this.cover,
    this.typeOverride,
    this.cameFromDetail = false,
  });
  final List<ExtensionEpisode> playList;
  final int playerIndex;
  final String title;
  final String package;
  final String detailUrl;
  final int episodeGroupId;
  final String? cover;
  final String anilistID;
  // Extensiones normales no lo necesitan (se cae a runtime.extension.type,
  // igual que siempre) — solo hace falta para una extensión "mixed" (ver
  // ExtensionUtils.resolveType), donde el tipo fijo de la extensión no
  // alcanza para decidir lector-vs-reproductor: el llamador (detail_controller,
  // resumeHistoryItem) ya resolvió el tipo real de ESTE título puntual.
  final ExtensionType? typeOverride;
  // Solo el lector (Comic/Novel) lo usa — ver ReaderController.cameFromDetail.
  final bool cameFromDetail;

  @override
  Widget build(BuildContext context) {
    final installed = ExtensionUtils.runtimes[package];
    // Última barrera antes de reproducir/leer — sin esto, entrar acá con una
    // extensión desinstalada tiraba un null-check crash, y con una
    // deshabilitada (sigue instalada, `runtimes` no distingue) reproducía
    // igual pese al toggle apagado. Cubre CUALQUIER camino que llegue a esta
    // página (detalle, "Continuar viendo", deep link futuro), no solo los ya
    // revisados a mano.
    if (installed == null || !ExtensionUtils.isEnabled(package)) {
      final message = Text(
        FlutterI18n.translate(
          context,
          installed == null
              ? 'common.extension-missing'
              : 'common.extension-disabled',
          translationParams: {'package': package},
        ),
      );
      return Scaffold(body: Center(child: message));
    }
    final runtime = installed;
    switch (typeOverride ?? runtime.extension.type) {
      case ExtensionType.bangumi:
        return VideoPlayer(
          title: title,
          playList: playList,
          runtime: runtime,
          playerIndex: playerIndex,
          // 用来存储历史记录了
          episodeGroupId: episodeGroupId,
          detailUrl: detailUrl,
          anilistID: anilistID,
        );
      case ExtensionType.manga:
        return ComicReader(
          title: title,
          playList: playList,
          detailUrl: detailUrl,
          playerIndex: playerIndex,
          episodeGroupId: episodeGroupId,
          runtime: runtime,
          cover: cover,
          anilistID: anilistID,
          cameFromDetail: cameFromDetail,
        );
      default:
        return NovelReader(
          playList: playList,
          runtime: runtime,
          episodeGroupId: episodeGroupId,
          playerIndex: playerIndex,
          title: title,
          detailUrl: detailUrl,
          cover: cover,
          anilistID: anilistID,
          cameFromDetail: cameFromDetail,
        );
    }
  }
}
