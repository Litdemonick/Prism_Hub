import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:prismhub/views/pages/extension/extension_page.dart';
import 'package:prismhub/views/pages/home_page.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/pages/settings/settings_page.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:window_manager/window_manager.dart';

// Banner único de "sin conexión", visible en toda la app (cualquier pestaña)
// en vez de que cada pantalla se entere sola cuando una petición falla —
// antes eso era inconsistente: algunas pantallas mostraban su propio mensaje
// tarde (recién al fallar una petición) y otras (ej. Home) tragaban el error
// en silencio, así que sin wifi la app no avisaba nada ahí.
Widget _noConnectionBanner() {
  return Obx(() {
    if (ConnectivityUtils.isOnline.value) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'common.no-internet'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  });
}

class DesktopMainPage extends StatefulWidget {
  const DesktopMainPage({
    super.key,
    required this.child,
    required this.shellContext,
    required this.state,
  });

  final Widget child;
  final BuildContext? shellContext;
  final GoRouterState state;

  @override
  State<DesktopMainPage> createState() => _DesktopMainPageState();
}

class _DesktopMainPageState extends State<DesktopMainPage> with WindowListener {
  late MainController c;

  @override
  void initState() {
    c = Get.put(MainController());
    if (PrismHubStorage.getSetting(SettingKey.autoCheckUpdate)) {
      ApplicationUtils.checkForcedUpdate(context);
    }
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Widget _title() {
    return const DragToMoveArea(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          'PrismHub',
          style: TextStyle(
            fontSize: 20.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return fluent.NavigationView(
      appBar: fluent.NavigationAppBar(
        leading: () {
          return fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.back, size: 12.0),
            onPressed: () {
              if (router.canPop()) {
                context.pop();
                setState(() {});
              }
            },
          );
        }(),
        title: _title(),
        actions: Obx(
          () => Row(
            children: [
              const Spacer(),
              ...c.actions,
              SizedBox(
                width: 138,
                height: 50,
                child: WindowCaption(
                  backgroundColor: Colors.transparent,
                  brightness: fluent.FluentTheme.of(context).brightness,
                ),
              )
            ],
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      paneBodyBuilder: (item, body) {
        return Column(
          children: [
            _noConnectionBanner(),
            Expanded(child: widget.child),
          ],
        );
      },
      pane: fluent.NavigationPane(
        // 200 cortaba "Repositorio de extensiones" (el ítem más largo del
        // panel) contra el borde.
        size: const fluent.NavigationPaneSize(openMaxWidth: 230),
        selected: c.selectedTab.value,
        onChanged: c.changeTab,
        displayMode: fluent.PaneDisplayMode.compact,
        footerItems: [
          fluent.PaneItemSeparator(),
          fluent.PaneItem(
            icon: const Icon(fluent.FluentIcons.repo),
            title: Text('common.extension-repo'.i18n),
            body: const ExtensionPage(),
            onTap: () {
              router.go('/extension_repo');
            },
          ),
          fluent.PaneItem(
            icon: const Icon(fluent.FluentIcons.settings),
            title: Text('common.settings'.i18n),
            body: const SettingsPage(),
            onTap: () {
              router.go('/settings');
            },
          ),
        ],
        items: [
          fluent.PaneItem(
            icon: const Icon(fluent.FluentIcons.home),
            title: Text('common.home'.i18n),
            body: const HomePage(),
            onTap: () {
              router.go('/');
            },
          ),
          fluent.PaneItem(
            icon: const Icon(fluent.FluentIcons.search),
            title: Text('common.search'.i18n),
            body: const SearchPage(),
            onTap: () {
              router.go('/search');
            },
          ),
          fluent.PaneItem(
            icon: const Icon(fluent.FluentIcons.add_in),
            title: Text('common.extension'.i18n),
            body: const ExtensionPage(),
            onTap: () {
              router.go('/extension');
            },
          ),
        ],
      ),
    );
  }

  @override
  void onWindowResize() {
    WindowManager.instance.getSize().then((value) {
      PrismHubStorage.setSetting(
        SettingKey.windowSize,
        "${value.width},${value.height}",
      );
    });
  }

  @override
  void onWindowMove() {
    WindowManager.instance.getPosition().then((value) {
      PrismHubStorage.setSetting(
        SettingKey.windowPosition,
        "${value.dx},${value.dy}",
      );
    });
  }
}

class AndroidMainPage extends fluent.StatefulWidget {
  const AndroidMainPage({super.key});

  @override
  fluent.State<AndroidMainPage> createState() => _AndroidMainPageState();
}

class _AndroidMainPageState extends fluent.State<AndroidMainPage> {
  late MainController c;

  final pages = const [
    HomePage(),
    SearchPage(),
    ExtensionPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    c = Get.put(MainController());
    if (PrismHubStorage.getSetting(SettingKey.autoCheckUpdate)) {
      ApplicationUtils.checkForcedUpdate(context);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    List<_Destination> destinations = <_Destination>[
      _Destination(Icons.home_outlined, Icons.home, 'common.home'.i18n),
      _Destination(Icons.search_outlined, Icons.search, 'common.search'.i18n),
      _Destination(
          Icons.extension_outlined, Icons.extension, 'common.extension'.i18n),
      _Destination(
          Icons.settings_outlined, Icons.settings, 'common.settings'.i18n),
    ];
    return Obx(
      () => Scaffold(
        // Las 4 pestañas viven DENTRO de este Scaffold, así que poner
        // resizeToAvoidBottomInset:false solo en el Scaffold interno de
        // Búsqueda no alcanzaba: el de afuera seguía encogiéndose con el
        // teclado y el overflow persistía (confirmado en vivo). Los campos
        // de texto de estas pestañas están arriba (en la AppBar), así que
        // el teclado puede superponerse sin tapar nada importante.
        resizeToAvoidBottomInset: false,
        // IndexedStack en vez de pages[index]: con pages[index], cambiar de
        // pestaña sacaba el widget de la anterior del árbol y montaba uno
        // nuevo de cero (initState, animaciones, scroll, todo desde cero)
        // en cada toque — se sentía pesado/trabado. IndexedStack monta las
        // 4 páginas una sola vez y solo oculta las que no están activas; los
        // controllers GetX de cada una ya se reusaban entre pestañas (ver
        // comentario en home_page.dart), así que esto no agrega trabajo de
        // fondo nuevo, solo evita el remount constante.
        body: Column(
          children: [
            SafeArea(bottom: false, child: _noConnectionBanner()),
            Expanded(
              child: LayoutUtils.isTablet
                  ? Row(
                      children: [
                        NavigationRail(
                          groupAlignment: 0,
                          labelType: NavigationRailLabelType.all,
                          destinations: destinations
                              .map((e) => NavigationRailDestination(
                                    icon: Icon(e.icon),
                                    selectedIcon: Icon(e.selectedIcon),
                                    label: Text(e.label),
                                  ))
                              .toList(),
                          selectedIndex: c.selectedTab.value,
                          onDestinationSelected: c.changeTab,
                        ),
                        Expanded(
                          child: _buildPages(),
                        ),
                      ],
                    )
                  : _buildPages(),
            ),
          ],
        ),
        bottomNavigationBar: LayoutUtils.isTablet
            ? null
            : NavigationBar(
                destinations: destinations
                    .map((e) => NavigationDestination(
                          icon: Icon(e.icon),
                          selectedIcon: Icon(e.selectedIcon),
                          label: e.label,
                        ))
                    .toList(),
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                selectedIndex: c.selectedTab.value,
                onDestinationSelected: c.changeTab,
              ),
      ),
    );
  }

  // IndexedStack mantiene las 4 páginas montadas (ver comentario de arriba)
  // pero NO pausa sus animaciones solo por no ser la visible — a diferencia
  // de Offstage, IndexedStack no toca TickerMode, así que cada AnimationController
  // en las pestañas ocultas (el fondo animado AnimatedBackgroundGlow de
  // Home/Buscar/Extensiones/Ajustes hace un blur pesado en bucle infinito)
  // seguía corriendo para siempre en segundo plano. Con las 4 pestañas
  // visitadas, eso son 4 blurs pesados compitiendo por el mismo frame budget
  // TODO el tiempo — de ahí que cualquier botón/animación en cualquier lado
  // se sintiera con tirones, y que un hot restart "arreglara" todo
  // temporalmente (mata los 4) hasta que se volvían a acumular navegando.
  // TickerMode(enabled: false) en las no-activas pausa sus tickers sin
  // desmontarlas — se retoma solo la animación de la pestaña visible.
  Widget _buildPages() {
    return IndexedStack(
      index: c.selectedTab.value,
      children: [
        for (var i = 0; i < pages.length; i++)
          TickerMode(
            enabled: i == c.selectedTab.value,
            child: pages[i],
          ),
      ],
    );
  }
}

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);
  final IconData selectedIcon;
  final IconData icon;
  final String label;
}
