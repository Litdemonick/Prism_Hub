import 'package:go_router/go_router.dart';

import '../../modules/detail/detail_page.dart';
import '../../modules/extensions/extensions_page.dart';
import '../../modules/home/home_page.dart';
import '../../modules/search/search_page.dart';
import '../../modules/settings/settings_page.dart';
import '../../shared/widgets/app_shell.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const search = '/search';
  static const detail = '/detail';
  static const player = '/player';
  static const reader = '/reader';
  static const extensions = '/extensions';
  static const settings = '/settings';
}

abstract final class AppRouter {
  static final config = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.home, builder: (ctx, st) => const HomePage()),
          GoRoute(
            path: AppRoutes.search,
            builder: (ctx, st) => const SearchPage(),
          ),
          GoRoute(
            path: AppRoutes.extensions,
            builder: (ctx, st) => const ExtensionsPage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (ctx, st) => const SettingsPage(),
          ),
        ],
      ),
      // Detail está fuera del ShellRoute para ocupar pantalla completa
      GoRoute(
        path: AppRoutes.detail,
        builder: (ctx, st) => DetailPage(args: st.extra! as DetailArgs),
      ),
    ],
  );
}
