import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:prismhub/views/widgets/beta_notice.dart';
import 'package:prismhub/views/pages/extension/extension_page.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/home_page.dart';
import 'package:prismhub/views/pages/library_page.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_zone_page.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/pages/settings/settings_page.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/window_caption_buttons.dart';
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
    super.initState();
    c = Get.put(MainController());
    // Aviso de beta, una sola vez. Va en un post-frame porque acá el árbol
    // todavía se está montando y el diálogo necesita un Navigator listo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showBetaNoticeIfNeeded(context);
    });
    if (PrismHubStorage.getSetting(SettingKey.autoCheckUpdate) == true) {
      ApplicationUtils.scheduleForcedUpdateCheck(context);
      // Y se sigue mirando cada tanto: si el release termina de publicarse con
      // la app ya abierta, el aviso llega igual, sin tener que reiniciarla.
      ApplicationUtils.iniciarChequeoPeriodico(context);
    }
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    ApplicationUtils.detenerChequeoPeriodico();
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
                // Ver BotonesVentana: el maximizar del WindowCaption del
                // paquete dejaba de responder despues de achicar la ventana.
                child: BotonesVentana(
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
        size: const fluent.NavigationPaneSize(openMaxWidth: 230),
        selected: c.selectedTab.value,
        onChanged: c.changeTab,
        displayMode: fluent.PaneDisplayMode.compact,
        footerItems: [
          fluent.PaneItemSeparator(),
          fluent.PaneItem(
            icon: const Icon(fluent.FluentIcons.warning,
                color: Color(0xFFE5484D)),
            title: Text('nsfw18.menu-label'.i18n),
            body: const Nsfw18ZoneGate(),
            onTap: () {
              // Se manda la ruta actual (antes de entrar) como "from" — así,
              // si se cancela/dice "no entrar" en la Zona +18, se vuelve
              // ahí en vez de siempre a Home (ver Nsfw18ZoneGate/router.go
              // reemplaza todo el stack, no hay "atrás" al que hacer pop).
              // Si ya se estaba en /adult-zone (re-tocar el mismo item), no
              // se manda from — evita un bucle donde cancelar reabre la
              // misma Zona +18 y vuelve a preguntar.
              final current = widget.state.uri.toString();
              final from = current == '/adult-zone' ? null : current;
              router.go(
                Uri(
                  path: '/adult-zone',
                  queryParameters: from == null ? null : {'from': from},
                ).toString(),
              );
            },
          ),
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
          // Biblioteca: lo que el usuario YA tiene (Continuar viendo,
          // Favoritos). Es el Home de antes, movido tal cual sin rediseñar —
          // ver library_page.dart.
          fluent.PaneItem(
            icon: const Icon(fluent.FluentIcons.library),
            title: Text('common.library'.i18n),
            body: const LibraryPage(),
            onTap: () {
              router.go('/biblioteca');
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

  /// La ventana se está cerrando: se calla el audio antes que nada.
  ///
  /// En escritorio, cerrar la ventana no siempre entrega
  /// `AppLifecycleState.detached` a tiempo — y ahí aparecía lo que se reportó:
  /// la app se cerraba y el vídeo se seguía escuchando, porque mpv nunca
  /// recibió la orden de parar.
  ///
  /// Este evento sí llega, y llega temprano. Manda las órdenes y no espera a
  /// nadie: el proceso se está yendo y bloquear el cierre para esperar una
  /// respuesta sería cambiar un problema por otro peor.
  @override
  void onWindowClose() {
    VideoPlayerController.apagarTodoYa();
  }

  @override
  void onWindowResize() {
    _saveWindowSize();
  }

  Future<void> _saveWindowSize() async {
    if (await WindowManager.instance.isFullScreen()) return;
    if (await WindowManager.instance.isMaximized()) return;
    final value = await WindowManager.instance.getSize();
    if (value.width < 900 || value.height < 600) return;
    await PrismHubStorage.setSetting(
      SettingKey.windowSize,
      "${value.width},${value.height}",
    );
  }

  @override
  void onWindowMove() {
    _saveWindowPosition();
  }

  Future<void> _saveWindowPosition() async {
    if (await WindowManager.instance.isFullScreen()) return;
    if (await WindowManager.instance.isMaximized()) return;
    final value = await WindowManager.instance.getPosition();
    await PrismHubStorage.setSetting(
      SettingKey.windowPosition,
      "${value.dx},${value.dy}",
    );
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
    LibraryPage(),
    SearchPage(),
    ExtensionPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    c = Get.put(MainController());
    // Aviso de beta, una sola vez. Va en un post-frame porque acá el árbol
    // todavía se está montando y el diálogo necesita un Navigator listo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showBetaNoticeIfNeeded(context);
    });
    if (PrismHubStorage.getSetting(SettingKey.autoCheckUpdate) == true) {
      ApplicationUtils.scheduleForcedUpdateCheck(context);
      // Y se sigue mirando cada tanto: si el release termina de publicarse con
      // la app ya abierta, el aviso llega igual, sin tener que reiniciarla.
      ApplicationUtils.iniciarChequeoPeriodico(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<_Destination> destinations = <_Destination>[
      _Destination(Icons.home_outlined, Icons.home, 'common.home'.i18n),
      // Biblioteca: lo que el usuario YA tiene (Continuar viendo, Favoritos).
      // Es el Home de antes, movido tal cual — ver library_page.dart.
      _Destination(Icons.video_library_outlined, Icons.video_library,
          'common.library'.i18n),
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
        // comentario en library_page.dart), así que esto no agrega trabajo de
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
        // El contenido pasa POR DEBAJO de la barra.
        //
        // Con `extendBody`, Flutter le suma el alto de la barra al relleno de
        // abajo del cuerpo, así que las páginas que usan SafeArea reservan ese
        // lugar solas y nada queda tapado — pero el fondo y las portadas sí se
        // ven correr por atrás, que es lo que hace que la barra se lea como
        // algo que flota y no como un zócalo pegado.
        extendBody: true,
        bottomNavigationBar:
            LayoutUtils.isTablet ? null : _barraFlotante(destinations),
      ),
    );
  }

  /// ── Cuántos íconos entran en la barra ────────────────────────────────
  ///
  /// Cuatro. Con los cinco destinos metidos a la fuerza en una barra flotante
  /// —que es más angosta que el ancho de pantalla— los íconos quedan pegados y
  /// se le erra al tocar. El quinto, Ajustes, se va a los tres puntos junto
  /// con los atajos que antes no estaban en ningún lado.
  ///
  /// Ajustes es el que sale y no otro a propósito: es al que menos se entra de
  /// los cinco, y encima ya tiene su atajo arriba en el Home.
  static const _enLaBarra = 4;

  Widget _barraFlotante(List<_Destination> destinos) {
    // Lo que ocupa la barra del sistema —los tres botones, o la rayita de
    // gestos—. Sin esto la barra flotante se apoya justo encima y en un
    // teléfono con gestos el deslizar de atrás se come el toque.
    final abajo = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, abajo > 0 ? abajo * 0.35 + 8 : 12),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Casi opaca a propósito. Un desenfoque de fondo se vería
                // mejor, pero hay que recalcularlo en CADA cuadro mientras el
                // usuario se desplaza, y encima de una lista de portadas eso
                // es justo donde no sobran milisegundos.
                color: const Color(0xF014141C),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < _enLaBarra; i++)
                      _IconoDeBarra(
                        destino: destinos[i],
                        elegido: c.selectedTab.value == i,
                        onTap: () => c.changeTab(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _BotonDeMas(onTap: _abrirMasOpciones),
        ],
      ),
    );
  }

  /// Lo que no entró en la barra, en una hoja que sube desde abajo.
  void _abrirMasOpciones() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14141C),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (hoja) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OpcionDeHoja(
              icono: Icons.settings_outlined,
              texto: 'common.settings'.i18n,
              onTap: () {
                Navigator.pop(hoja);
                c.changeTab(MainController.tabAjustes);
              },
            ),
            _OpcionDeHoja(
              icono: Icons.history_rounded,
              texto: 'common.history'.i18n,
              onTap: () {
                Navigator.pop(hoja);
                Get.to(() => const HistoryPage());
              },
            ),
            _OpcionDeHoja(
              icono: Icons.favorite_border_rounded,
              texto: 'common.favorite'.i18n,
              onTap: () {
                Navigator.pop(hoja);
                // La pestaña de favoritos de Historial. Mismo índice que usa
                // Biblioteca — si cambia allá, cambia acá.
                Get.to(() => const HistoryPage(initialTab: 3));
              },
            ),
            const SizedBox(height: 8),
          ],
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
          RepaintBoundary(
            child: TickerMode(
              enabled: i == c.selectedTab.value,
              // Todas menos Home terminan ARRIBA de la barra flotante.
              //
              // Con `extendBody` el cuerpo llega hasta el borde de abajo, y
              // Flutter le suma el alto de la barra al relleno del MediaQuery.
              // Este SafeArea es el que lo consume: sin él, la paginación de
              // Extensiones y el final de Ajustes quedaban tapados por la
              // barra, que es justo lo que no puede pasar.
              //
              // Home no lo lleva: ahí el punto ES que las portadas se vean
              // correr por debajo, y su ListView ya reserva el lugar solo.
              child: i == MainController.tabHome
                  ? pages[i]
                  : SafeArea(
                      top: false,
                      left: false,
                      right: false,
                      child: pages[i],
                    ),
            ),
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

/// Un ícono de la barra flotante.
///
/// El elegido se marca con un círculo relleno y no solo con color: sobre un
/// fondo oscuro, dos tonos de gris no se distinguen de un vistazo, y menos con
/// portadas de colores corriendo por detrás.
class _IconoDeBarra extends StatelessWidget {
  const _IconoDeBarra({
    required this.destino,
    required this.elegido,
    required this.onTap,
  });

  final _Destination destino;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final acento = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: elegido,
      label: destino.label,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            // Círculo entero, no una pastilla: al lado del botón redondo de
            // los tres puntos, una marca ovalada se veía como otra cosa.
            shape: BoxShape.circle,
            gradient: elegido
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      acento.withValues(alpha: 0.42),
                      acento.withValues(alpha: 0.18),
                    ],
                  )
                : null,
            // El aro es lo que la despega del fondo de la barra. Sin él, sobre
            // un relleno translúcido, la marca se veía como una mancha.
            border: elegido
                ? Border.all(color: acento.withValues(alpha: 0.55), width: 1.2)
                : null,
            boxShadow: elegido
                ? [
                    BoxShadow(
                      color: acento.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            scale: elegido ? 1.08 : 1.0,
            child: Icon(
              elegido ? destino.selectedIcon : destino.icon,
              size: 23,
              color: elegido ? Colors.white : Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

/// Los tres puntos, afuera de la barra.
///
/// Aparte y no como un ícono más: lo que hace no es cambiar de pestaña, y
/// mezclarlo con los otros cuatro haría que se lea como una quinta pestaña.
class _BotonDeMas extends StatelessWidget {
  const _BotonDeMas({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final acento = Theme.of(context).colorScheme.primary;
    return Material(
      color: acento.withValues(alpha: 0.22),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(Icons.more_horiz_rounded, size: 26, color: acento),
        ),
      ),
    );
  }
}

class _OpcionDeHoja extends StatelessWidget {
  const _OpcionDeHoja({
    required this.icono,
    required this.texto,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icono, color: Colors.white70),
      title: Text(texto, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}
