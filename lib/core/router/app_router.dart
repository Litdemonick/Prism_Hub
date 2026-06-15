import 'package:go_router/go_router.dart';

import '../../modules/detail/detail_page.dart';
import '../../modules/home/home_page.dart';
import '../../modules/player/player_page.dart';
import '../../modules/player/watch_args.dart';
import '../../modules/reader/reader_page.dart';
import '../../modules/search/search_page.dart';
import '../../modules/settings/settings_page.dart';
import '../../shared/widgets/app_shell.dart';

abstract final class AppRoutes {
  static const home     = '/';
  static const search   = '/search';
  static const settings = '/settings';
  static const detail   = '/detail';
  static const player   = '/player';
  static const reader   = '/reader';
}

abstract final class AppRouter {
  static final config = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.home,     builder: (ctx, _) => const HomePage()),
          GoRoute(path: AppRoutes.search,   builder: (ctx, _) => const SearchPage()),
          GoRoute(path: AppRoutes.settings, builder: (ctx, _) => const SettingsPage()),
        ],
      ),
      // Pantalla completa — fuera del ShellRoute (sin NavigationRail)
      GoRoute(
        path: AppRoutes.detail,
        builder: (ctx, st) => DetailPage(args: st.extra! as DetailArgs),
      ),
      GoRoute(
        path: AppRoutes.player,
        builder: (ctx, st) => PlayerPage(args: st.extra! as WatchArgs),
      ),
      GoRoute(
        path: AppRoutes.reader,
        builder: (ctx, st) => ReaderPage(args: st.extra! as WatchArgs),
      ),
    ],
  );
}
