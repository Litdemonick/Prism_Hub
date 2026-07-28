import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:prismhub/data/providers/anilist_provider.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/views/pages/extension/extension_page.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/pages/extension/extension_settings_page.dart';
import 'package:prismhub/views/pages/favorites_page.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/pages/home_page.dart';
import 'package:prismhub/views/pages/main_page.dart';
import 'package:prismhub/views/pages/search/extension_searcher_page.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/pages/settings/settings_page.dart';
import 'package:prismhub/views/pages/tracking/anilist_more_page.dart';
import 'package:prismhub/views/pages/tracking/anilist_tracking_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

BuildContext get currentContext {
  if (Platform.isAndroid) {
    return Get.context!;
  }
  return _shellNavigatorKey.currentContext ?? Get.context!;
}

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return DesktopMainPage(
          shellContext: _shellNavigatorKey.currentContext,
          state: state,
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => _animation(state, const HomePage()),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => _animation(
            state,
            HistoryPage(
              initialTab: int.tryParse(
                    state.uri.queryParameters['tab'] ?? '',
                  ) ??
                  0,
            ),
          ),
        ),
        GoRoute(
          path: '/favorites',
          pageBuilder: (context, state) => _animation(
            state,
            FavoritesPage(
              type: ExtensionType.values[int.parse(
                state.uri.queryParameters['type']!,
              )],
            ),
          ),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) => _animation(state, const SearchPage()),
        ),
        GoRoute(
          path: '/search_extension',
          pageBuilder: (context, state) => _animation(
            state,
            ExtensionSearcherPage(
              package: state.uri.queryParameters['package']!,
              keyWord: state.uri.queryParameters['keyWord'],
            ),
          ),
        ),
        GoRoute(
          path: '/extension',
          pageBuilder: (context, state) =>
              _animation(state, const ExtensionPage()),
        ),
        GoRoute(
          path: '/extension_settings',
          pageBuilder: (context, state) => _animation(
            state,
            ExtensionSettingsPage(
              package: state.uri.queryParameters['package']!,
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              _animation(state, const SettingsPage()),
        ),
        GoRoute(
          path: '/settings/anilist',
          pageBuilder: (context, state) =>
              _animation(state, const AniListTrackingPage()),
        ),
        GoRoute(
          path: '/settings/anilist_more',
          pageBuilder: (context, state) => _animation(
            state,
            AnilistMorePage(
              anilistType: AnilistType.values[int.parse(
                state.uri.queryParameters['type']!,
              )],
            ),
          ),
        ),
        GoRoute(
          path: '/extension_repo',
          pageBuilder: (context, state) =>
              _animation(state, const ExtensionRepoPage()),
        ),
        GoRoute(
          path: '/detail',
          pageBuilder: (context, state) {
            final url = state.uri.queryParameters['url']!;
            final package = state.uri.queryParameters['package']!;
            return _animation(
              state,
              DetailPage(
                key: ValueKey('$package|$url'),
                url: url,
                package: package,
                tag: '$package|$url',
              ),
            );
          },
        ),
      ],
    )
  ],
);

// FluentApp.router no es MaterialApp ni CupertinoApp — go_router solo sabe
// dar transición automática a esos dos tipos de app (ver
// go_router/src/builder.dart, _pageBuilderForAppType), así que con
// GoRoute.builder (lo que había acá antes) TODA la navegación de escritorio
// quedaba con NoTransitionPage: un corte seco sin ninguna animación,
// confirmado en vivo con el botón de detalle (se sentía brusco, no era un
// problema de frames). CustomTransitionPage con un fade+slide corto arregla
// esto para cualquier ruta que pase por acá.
Page<void> _animation(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      );
    },
  );
}
