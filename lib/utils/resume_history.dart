import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/views/pages/watch/watch_page.dart';
import 'package:prismhub/views/widgets/deferred_route_content.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/progress.dart';

// Tapping a "Continuar" card should feel instant. The expensive part
// (loading/parsing cached detail, or fetching it if cache is missing) now
// happens inside a tiny loading route, after navigation has already started.
Future<void> resumeHistoryItem(BuildContext context, History history) async {
  final runtime = ExtensionUtils.runtimes[history.package];
  final disabled =
      runtime != null && !ExtensionUtils.isEnabled(history.package);
  if (runtime == null || disabled) {
    showPlatformSnackbar(
      context: context,
      content: FlutterI18n.translate(
        context,
        disabled ? 'common.extension-disabled' : 'common.extension-missing',
        translationParams: {'package': ExtensionUtils.nombreDe(history.package)},
      ),
      severity: fluent.InfoBarSeverity.error,
    );
    return;
  }

  // Antes de resolver el destino (que ya llama a la extensión vía
  // runtime.detail más abajo si no hay caché), se chequea si hace falta
  // actualizar — "Continuar" no pasaba por Instaladas/ExtensionSearcherPage,
  // así que este aviso nunca corría acá.
  if (await ExtensionUtils.blockedByPendingUpdate(context, history.package)) {
    return;
  }
  if (!context.mounted) return;

  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final cachedTarget = _resumeTargetCache[_resumeKey(history, runtime)];
  if (isDesktop && cachedTarget != null) {
    Navigator.of(context, rootNavigator: true).push(
      _resumeWatchRoute(history, cachedTarget),
    );
    return;
  }

  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      transitionDuration:
          isDesktop ? Duration.zero : const Duration(milliseconds: 120),
      reverseTransitionDuration:
          isDesktop ? Duration.zero : const Duration(milliseconds: 120),
      pageBuilder: (_, animation, __) {
        final page = _ResumeHistoryLoaderPage(
          history: history,
          runtime: runtime,
        );
        if (isDesktop) return page;
        return FadeTransition(opacity: animation, child: page);
      },
    ),
  );
}

class _ResumeTarget {
  const _ResumeTarget({
    required this.detail,
    required this.playList,
    required this.resolvedType,
    required this.anilistId,
  });

  final ExtensionDetail detail;
  final List<ExtensionEpisode> playList;
  final ExtensionType resolvedType;
  final String anilistId;
}

final Map<String, _ResumeTarget> _resumeTargetCache = {};
final Map<String, Future<_ResumeTarget?>> _resumeTargetInFlight = {};

Future<void> prewarmResumeHistoryTargets(
  Iterable<History> histories, {
  int max = 40,
}) async {
  var count = 0;
  for (final history in histories) {
    if (count >= max) return;
    final runtime = ExtensionUtils.runtimes[history.package];
    if (runtime == null || !ExtensionUtils.isEnabled(history.package)) {
      continue;
    }
    count++;
    await _loadCachedResumeTarget(history, runtime);
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 24));
  }
}

String _resumeKey(History h, ExtensionService runtime) {
  return [
    h.package,
    runtime.extension.version,
    h.url,
    h.episodeGroupId,
    h.episodeId,
  ].join('|');
}

Map<String, dynamic> _decodeDetailJson(String source) {
  return Map<String, dynamic>.from(jsonDecode(source));
}

Future<Map<String, dynamic>> _decodeCachedDetail(String source) async {
  if (source.length < 4096) {
    return _decodeDetailJson(source);
  }
  return compute(_decodeDetailJson, source);
}

Future<_ResumeTarget?> _loadResumeTarget(
  History history,
  ExtensionService runtime,
) {
  final key = _resumeKey(history, runtime);
  final cachedTarget = _resumeTargetCache[key];
  if (cachedTarget != null) return Future.value(cachedTarget);

  final inFlight = _resumeTargetInFlight[key];
  if (inFlight != null) return inFlight;

  final future = _doLoadResumeTarget(history, runtime).then((target) {
    if (target != null) _resumeTargetCache[key] = target;
    return target;
  });
  _resumeTargetInFlight[key] = future;
  return future.whenComplete(() => _resumeTargetInFlight.remove(key));
}

Future<_ResumeTarget?> _loadCachedResumeTarget(
  History history,
  ExtensionService runtime,
) async {
  final key = _resumeKey(history, runtime);
  final cachedTarget = _resumeTargetCache[key];
  if (cachedTarget != null) return cachedTarget;

  final cached = await DatabaseService.getPrismHubDetail(
    history.package,
    history.url,
  );
  if (cached == null) return null;

  try {
    final detail = ExtensionDetail.fromJson(
      await _decodeCachedDetail(cached.data),
    );
    final groups = detail.episodes;
    if (groups == null ||
        history.episodeGroupId < 0 ||
        history.episodeGroupId >= groups.length) {
      return null;
    }
    final playList = groups[history.episodeGroupId].urls;
    if (history.episodeId < 0 || history.episodeId >= playList.length) {
      return null;
    }
    final target = _ResumeTarget(
      detail: detail,
      playList: playList,
      resolvedType: ExtensionUtils.resolveType(runtime.extension, detail),
      anilistId: cached.aniListID ?? '',
    );
    _resumeTargetCache[key] = target;
    return target;
  } catch (_) {
    return null;
  }
}

Future<_ResumeTarget?> _doLoadResumeTarget(
  History history,
  ExtensionService runtime,
) async {
  ExtensionDetail? detail;
  String anilistId = '';

  final cached = await DatabaseService.getPrismHubDetail(
    history.package,
    history.url,
  );
  if (cached != null) {
    try {
      detail = ExtensionDetail.fromJson(await _decodeCachedDetail(cached.data));
      anilistId = cached.aniListID ?? '';
    } catch (_) {
      detail = null;
    }
  }

  detail ??= await runtime.detail(history.url);

  final groups = detail.episodes;
  if (groups == null ||
      history.episodeGroupId < 0 ||
      history.episodeGroupId >= groups.length) {
    return null;
  }

  final playList = groups[history.episodeGroupId].urls;
  if (history.episodeId < 0 || history.episodeId >= playList.length) {
    return null;
  }

  return _ResumeTarget(
    detail: detail,
    playList: playList,
    resolvedType: ExtensionUtils.resolveType(runtime.extension, detail),
    anilistId: anilistId,
  );
}

class _ResumeHistoryLoaderPage extends StatefulWidget {
  const _ResumeHistoryLoaderPage({
    required this.history,
    required this.runtime,
  });

  final History history;
  final ExtensionService runtime;

  @override
  State<_ResumeHistoryLoaderPage> createState() =>
      _ResumeHistoryLoaderPageState();
}

class _ResumeHistoryLoaderPageState extends State<_ResumeHistoryLoaderPage> {
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    _ResumeTarget? target;
    try {
      target = await _loadResumeTarget(widget.history, widget.runtime);
    } catch (_) {
      target = null;
    }
    if (!mounted) return;

    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (!isDesktop) {
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
    }

    if (target == null) {
      Navigator.of(context, rootNavigator: true).pop();
      _openDetailPageFallback(context, widget.history);
      return;
    }

    Navigator.of(context, rootNavigator: true).pushReplacement(
      _resumeWatchRoute(widget.history, target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: const Center(child: ProgressRing()),
    );
  }
}

Route<void> _resumeWatchRoute(History history, _ResumeTarget target) {
  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  return PageRouteBuilder<void>(
    transitionDuration: isDesktop
        ? const Duration(milliseconds: 220)
        : const Duration(milliseconds: 320),
    reverseTransitionDuration: isDesktop
        ? const Duration(milliseconds: 220)
        : const Duration(milliseconds: 120),
    pageBuilder: (_, animation, __) {
      final page = _DeferredResumeWatchPage(
        history: history,
        target: target,
        pushAnimation: animation,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        ),
        child: page,
      );
    },
  );
}

void _openDetailPageFallback(BuildContext context, History history) {
  ExtensionUtils.openExtensionDetail(
    context,
    package: history.package,
    url: history.url,
  );
}

class _DeferredResumeWatchPage extends StatelessWidget {
  const _DeferredResumeWatchPage({
    required this.history,
    required this.target,
    required this.pushAnimation,
  });

  final History history;
  final _ResumeTarget target;
  final Animation<double> pushAnimation;

  @override
  Widget build(BuildContext context) {
    return DeferredRouteContent(
      pushAnimation: pushAnimation,
      placeholder: Scaffold(
        backgroundColor: HomeTheme.bg,
        body: const Center(child: ProgressRing()),
      ),
      builder: (context) => WatchPage(
        cover: target.detail.cover,
        playList: target.playList,
        package: history.package,
        playerIndex: history.episodeId,
        title: history.title,
        episodeGroupId: history.episodeGroupId,
        detailUrl: history.url,
        anilistID: target.anilistId,
        typeOverride: target.resolvedType,
        autoResume: true,
        // Sin esto, retomar "Continuar" de un título +18 volvía a guardar
        // el History con isNsfw=false (default) al primer touch, pisando
        // la marca +18 que ya tenía — se "salía" de la Zona +18 solo con
        // seguir mirando. history.isNsfw YA tiene la respuesta correcta,
        // no hace falta volver a preguntar nada acá.
        isNsfw: history.isNsfw,
      ),
    );
  }
}
