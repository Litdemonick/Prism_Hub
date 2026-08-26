import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:prismhub/data/providers/anilist_provider.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/views/pages/extension/extension_page.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/pages/extension/extension_settings_page.dart';
import 'package:prismhub/views/pages/favorites_page.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/pages/home_page.dart';
import 'package:prismhub/views/pages/library_page.dart';
import 'package:prismhub/views/pages/main_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_search_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_zone_page.dart';
import 'package:prismhub/views/pages/search/extension_searcher_page.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/pages/settings/bloqueador_page.dart';
import 'package:prismhub/views/pages/settings/registro_en_vivo_page.dart';
import 'package:prismhub/views/pages/settings/settings_page.dart';
import 'package:prismhub/views/pages/tracking/anilist_more_page.dart';
import 'package:prismhub/views/pages/tracking/anilist_tracking_page.dart';
import 'package:prismhub/views/pages/zonas/zona_catalogo_page.dart';

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
          path: '/peliculas',
          pageBuilder: (context, state) => _animation(
              state, const ZonaCatalogoPage(zona: ZonaPrincipal.peliculas)),
        ),
        GoRoute(
          path: '/series',
          pageBuilder: (context, state) => _animation(
              state, const ZonaCatalogoPage(zona: ZonaPrincipal.series)),
        ),
        GoRoute(
          path: '/anime',
          pageBuilder: (context, state) => _animation(
              state, const ZonaCatalogoPage(zona: ZonaPrincipal.anime)),
        ),
        GoRoute(
          path: '/mangas',
          pageBuilder: (context, state) => _animation(
              state, const ZonaCatalogoPage(zona: ZonaPrincipal.mangas)),
        ),
        // Biblioteca: lo que el usuario ya tiene. Es el Home de antes, movido
        // tal cual — ver library_page.dart.
        GoRoute(
          path: '/biblioteca',
          pageBuilder: (context, state) =>
              _animation(state, const LibraryPage()),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => _animation(
            state,
            () {
              final tab = int.tryParse(
                    state.uri.queryParameters['tab'] ?? '',
                  ) ??
                  0;
              return HistoryPage(
                initialTab: tab,
                zone: state.uri.queryParameters['zone'] == '1',
                // Las pestañas 3 y 4 son favoritos, y eso es su propia zona.
                soloFavoritos: tab >= 3,
              );
            }(),
          ),
        ),
        GoRoute(
          path: '/favorites',
          pageBuilder: (context, state) => _animation(
            state,
            FavoritesPage(
              type: _enumFromQuery(
                state.uri.queryParameters['type'],
                ExtensionType.values,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) =>
              _animation(state, const SearchPage()),
        ),
        // Zona +18 del buscador. En escritorio manda go_router (el navegador de
        // GetX no está activo acá, ver main.dart), así que necesita su propia
        // ruta — mismo criterio que /adult-zone y /detail. En Android no se usa:
        // ahí se empuja con Get.to (ver openNsfw18Search).
        GoRoute(
          path: '/adult-search',
          pageBuilder: (context, state) =>
              _animation(state, const Nsfw18SearchGate()),
        ),
        GoRoute(
          path: '/search_extension',
          pageBuilder: (context, state) => _animation(
            state,
            ExtensionSearcherPage(
              package: state.uri.queryParameters['package'] ?? '',
              keyWord: state.uri.queryParameters['keyWord'],
              // Si se llegó desde la Zona +18. Lo pone quien empuja la ruta
              // (ver search_page). Sin esto, en escritorio la extensión se
              // abría siempre como si viniera del buscador normal.
              soloAdulto: state.uri.queryParameters['soloAdulto'] == '1',
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
              package: state.uri.queryParameters['package'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              _animation(state, const SettingsPage()),
        ),
        // El visor del registro. En escritorio tiene que ser una ruta como
        // cualquier otra pantalla: acá manda go_router y el navegador de GetX
        // no está activo (ver main.dart). En Android no se usa — ahí se empuja
        // con Navigator desde la subpágina de Ajustes.
        GoRoute(
          path: '/settings/log',
          pageBuilder: (context, state) =>
              _animation(state, const RegistroEnVivoPage()),
        ),
        GoRoute(
          path: '/settings/bloqueador',
          pageBuilder: (context, state) =>
              _animation(state, const BloqueadorPage()),
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
              anilistType: _enumFromQuery(
                state.uri.queryParameters['type'],
                AnilistType.values,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/adult-zone',
          pageBuilder: (context, state) => _animation(
            state,
            Nsfw18ZoneGate(from: state.uri.queryParameters['from']),
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
            // Sin `!`: un parámetro ausente (una ruta mal armada o un enlace
            // externo) tiraba un error de null que se llevaba puesta la
            // pantalla entera. Con la cadena vacía, las páginas caen por su
            // camino normal de "extensión no encontrada", que ya existe y da
            // un mensaje claro.
            final url = state.uri.queryParameters['url'] ?? '';
            final package = state.uri.queryParameters['package'] ?? '';
            return _animation(
              state,
              DetailPage(
                key: ValueKey('$package|$url'),
                url: url,
                package: package,
                tag: '$package|$url',
                isAdultOption: state.uri.queryParameters['adult'] == '1',
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

// Los parámetros de una URL son texto arbitrario. Antes esto era
// `Values[int.parse(params['type']!)]`, o sea tres formas de reventar en una
// línea: `!` con el parámetro ausente, `int.parse` con algo que no es número,
// y el índice fuera de rango con un número cualquiera. Una ruta mal armada
// —o un enlace externo -- tumbaba la pantalla en vez de abrir algo razonable.
T _enumFromQuery<T>(String? raw, List<T> values) {
  final index = int.tryParse(raw ?? '') ?? 0;
  if (index < 0 || index >= values.length) return values.first;
  return values[index];
}
