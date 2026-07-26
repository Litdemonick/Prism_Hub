import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/views/pages/watch/watch_page.dart';
import 'package:prismhub/views/widgets/messenger.dart';

// Tapping a "Continuar" card used to always open the detail page (cover +
// chapter grid) even though the whole point was to jump back into a chapter
// already in progress. This resumes straight into the reader/player
// instead — using the locally-cached detail (Isar, same one the detail page
// itself persists) when available so it's instant, and only falling back to
// a fresh network fetch (or, if that fails, the detail page) when there's
// no cache yet.
Future<void> resumeHistoryItem(BuildContext context, History history) async {
  final runtime = ExtensionUtils.runtimes[history.package];
  // Deshabilitada (con el toggle apagado) se bloquea igual que no instalada
  // — antes esto solo miraba si el runtime existía, así que "Continuar
  // viendo" abría igual el reproductor de una extensión desactivada.
  final disabled = runtime != null && !ExtensionUtils.isEnabled(history.package);
  if (runtime == null || disabled) {
    showPlatformSnackbar(
      context: context,
      content: FlutterI18n.translate(
        context,
        disabled ? 'common.extension-disabled' : 'common.extension-missing',
        translationParams: {'package': history.package},
      ),
      severity: fluent.InfoBarSeverity.error,
    );
    return;
  }

  ExtensionDetail? detail;
  String anilistId = '';

  final cached = await DatabaseService.getPrismHubDetail(
    history.package,
    history.url,
  );
  if (cached != null) {
    try {
      detail = ExtensionDetail.fromJson(
        Map<String, dynamic>.from(jsonDecode(cached.data)),
      );
      anilistId = cached.aniListID ?? '';
    } catch (_) {
      detail = null;
    }
  }

  if (detail == null) {
    try {
      detail = await runtime.detail(history.url);
    } catch (_) {
      _openDetailPageFallback(history);
      return;
    }
  }

  final groups = detail.episodes;
  if (groups == null || history.episodeGroupId >= groups.length) {
    _openDetailPageFallback(history);
    return;
  }

  if (!context.mounted) return;
  final resolvedType = ExtensionUtils.resolveType(runtime.extension, detail);
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.ease)),
          child: WatchPage(
            cover: detail!.cover,
            playList: groups[history.episodeGroupId].urls,
            package: history.package,
            playerIndex: history.episodeId,
            title: history.title,
            episodeGroupId: history.episodeGroupId,
            detailUrl: history.url,
            anilistID: anilistId,
            typeOverride: resolvedType,
          ),
        );
      },
    ),
  );
}

void _openDetailPageFallback(History history) {
  if (Platform.isAndroid) {
    Get.to(DetailPage(
      key: ValueKey('${history.package}|${history.url}'),
      url: history.url,
      package: history.package,
      tag: '${history.package}|${history.url}',
    ));
    return;
  }
  router.push(
    Uri(
      path: '/detail',
      queryParameters: {'url': history.url, 'package': history.package},
    ).toString(),
  );
}
