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
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/window_caption_buttons.dart';
import 'package:window_manager/window_manager.dart';

// Banner único de "sin conexión", visible en toda la app (cualquier pestaña)
// en vez de que cada pantalla se entere sola cuando una petición falla —
// antes eso era inconsistente: algunas pantallas mostraban su propio mensaje
// tarde (recién al fallar una petición) y otras (ej. Home) tragaban el error
// en silencio, así que sin wifi la app no avisaba nada ahí.
Widget _noConnectionBanner() {
  // ── Sin barra naranja ───────────────────────────────────────────────────
  //
  // Cruzaba la pantalla entera, empujaba todo hacia abajo y tapaba el título
  // de la zona. Y no ayudaba: el usuario ya sabe que no tiene wifi, y lo que
  // necesita es entender que el app está esperando, no un cartel.
  //
  // Eso ahora lo dicen los bloques grises brillando en cada tarjeta: se ve
  // dónde va a aparecer el contenido y que está en camino. Y cuando una
  // extensión falla de verdad, su fila lo dice en una línea con su botón de
  // reintentar — ahí sí, donde pasó.
  //
  // Se deja la función y no se borran sus llamadas: si algún día vuelve a
  // hacer falta un aviso global, este es el lugar.
  return const SizedBox.shrink();
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

  /// En qué zona está parado el usuario, según la dirección actual.
  ///
  /// Sale del router y no de `selectedTab` a propósito: en escritorio se llega
  /// a una zona por el panel lateral **y también** por el botón de atrás, y en
  /// ese segundo caso la pestaña seleccionada se puede quedar atrasada. La
  /// dirección nunca miente.
  String _zona() {
    final ruta = widget.state.uri.path;
    if (ruta == '/') return 'common.home'.i18n;
    if (ruta.startsWith('/biblioteca')) return 'common.library'.i18n;
    if (ruta.startsWith('/search')) return 'common.search'.i18n;
    if (ruta.startsWith('/extension')) return 'common.extension'.i18n;
    if (ruta.startsWith('/settings')) return 'common.settings'.i18n;
    // Las demás —una ficha, el reproductor, el repositorio— no son zonas del
    // panel: ahí no se pone nada y queda solo el nombre de la app.
    return '';
  }

  Widget _title() {
    final zona = _zona();
    return DragToMoveArea(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PrismHub',
              style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
            ),
            // El nombre de la app se queda: es lo que identifica la ventana en
            // la barra de tareas y en la captura. La zona va al lado, más
            // liviana, para que se lea como «dónde estoy» y no como otro
            // título compitiendo con el primero.
            if (zona.isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 16,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              const SizedBox(width: 10),
              Text(
                zona,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ],
          ],
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

/// Si hay alguna pantalla apilada encima del Home.
///
/// ── Para qué ──────────────────────────────────────────────────────────────
///
/// Para que la barra flotante se vaya y vuelva **deslizándose**, en vez de
/// desaparecer de un cuadro al otro.
///
/// Cuando se abre una ficha o el reproductor, la pantalla nueva entra
/// corriéndose desde el costado y durante esa transición se sigue viendo la de
/// abajo. Si la barra simplemente deja de dibujarse, se ve parpadear. Bajándola
/// al mismo tiempo, la salida se lee como un movimiento solo.
///
/// ── Por qué solo las PageRoute ────────────────────────────────────────────
///
/// Porque un diálogo o una hoja de abajo también son rutas, y ahí la barra NO
/// se tiene que ir: el usuario sigue en la misma pantalla, solo que con algo
/// encima. Contarlas hacía que abrir los tres puntos escondiera la barra que
/// los acababa de mostrar.
class ObservadorDePila extends NavigatorObserver {
  /// Estático porque lo lee la barra, que vive en otra parte del árbol y no
  /// tiene forma de llegar hasta el observador que instaló GetMaterialApp.
  static final hayPantallaEncima = false.obs;

  int _profundidad = 0;

  void _contar(int delta) {
    _profundidad += delta;
    if (_profundidad < 0) _profundidad = 0;
    hayPantallaEncima.value = _profundidad > 0;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Sin `previousRoute` es la primera pantalla de todas: no hay nada debajo
    // que esconder.
    if (route is PageRoute && previousRoute != null) _contar(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) _contar(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) _contar(-1);
  }
}

class AndroidMainPage extends fluent.StatefulWidget {
  const AndroidMainPage({super.key});

  @override
  fluent.State<AndroidMainPage> createState() => _AndroidMainPageState();
}

class _AndroidMainPageState extends fluent.State<AndroidMainPage> {
  late MainController c;

  /// Si los tres puntos están desplegados.
  bool _masAbierto = false;

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
        // La capa de «más» va DENTRO del cuerpo y no en la barra: la barra
        // mide lo que mide, y hacerla crecer para meter los botones ahí le
        // cambiaría el relleno al cuerpo cada vez que se abre — o sea, todo
        // el contenido pegando un salto al desplegar.
        body: Stack(children: [
          Column(
            children: [
              // ── Sin SafeArea envolviéndolo ───────────────────────────
              //
              // Envuelto, reservaba la franja de la barra de estado SIEMPRE,
              // también con el aviso oculto. Y esa franja se pinta ACÁ AFUERA de
              // las páginas, así que quedaba negra plana mientras la zona de
              // abajo tenía su fondo con brillo: se veía como una barra rara
              // cruzando arriba de todo.
              //
              // Ahora el aviso se ocupa de su propio hueco cuando aparece, y
              // cada zona empieza en el borde de la pantalla y pinta su fondo
              // de arriba abajo. A cambio, cada una tiene que respetar la barra
              // de estado por su cuenta — las que llevan AppBar ya lo hacían
              // solas, y a las otras se les puso.
              _noConnectionBanner(),
              Expanded(
                child: _apaisado(context)
                    // ── Teléfono acostado: riel a la izquierda ─────────────
                    //
                    // Abajo no puede quedarse. En horizontal el alto es lo único
                    // que escasea —360 píxeles contra 800— y una barra abajo se
                    // lleva la franja donde justamente se ven las portadas. A la
                    // izquierda se come ancho, que es lo que sobra.
                    //
                    // Y va en un Row, no flotando encima: acostado el contenido
                    // usa el ancho entero, así que una barra superpuesta taparía
                    // la primera columna de tarjetas en vez de dejar ver algo por
                    // detrás. Con el Row, el contenido empieza DESPUÉS del riel y
                    // no se pisan nunca.
                    ? Row(
                        children: [
                          AnimatedSlide(
                            // Se va por donde entró: hacia afuera por el costado.
                            offset: _barraEscondida
                                ? const Offset(-1.6, 0)
                                : Offset.zero,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            child: _barraVertical(destinations),
                          ),
                          Expanded(
                            // El riel YA dejó pasar la franja de la barra del
                            // sistema. Sin sacarla de acá, el SafeArea de cada
                            // zona la vuelve a reservar y el contenido queda con
                            // el doble de margen a la izquierda.
                            child: MediaQuery.removePadding(
                              context: context,
                              removeLeft: true,
                              child: _buildPages(),
                            ),
                          ),
                        ],
                      )
                    : _buildPages(),
              ),
            ],
          ),
          if (_masAbierto) _capaDeMas(),
        ]),
        // El contenido pasa POR DEBAJO de la barra.
        //
        // Con `extendBody`, Flutter le suma el alto de la barra al relleno de
        // abajo del cuerpo, así que las páginas que usan SafeArea reservan ese
        // lugar solas y nada queda tapado — pero el fondo y las portadas sí se
        // ven correr por atrás, que es lo que hace que la barra se lea como
        // algo que flota y no como un zócalo pegado.
        extendBody: true,
        // AnimatedSlide y no un `if`: correrla no cambia cuánto mide, así
        // que el relleno que el Scaffold le pasa al cuerpo se queda igual y
        // el contenido no pega un salto cuando la barra se va.
        // Abajo y centrada SIEMPRE, también acostado.
        //
        // Se probó al costado en horizontal, para no gastar alto. No va: el
        // pulgar en horizontal cae abajo, no a la izquierda, y una barra
        // flotando a media altura de la pantalla no se lee como la barra de
        // navegación de nada. Queda pegada —con su aire— a la barra del
        // sistema, que es donde el usuario ya la busca.
        // ── La tablet usa la MISMA barra que el teléfono ─────────────────
        //
        // Antes le tocaba un NavigationRail de Material pegado a la
        // izquierda, con etiquetas debajo de cada ícono. Eso era de otro
        // diseño: sobre el fondo con brillo se veía como un panel de sistema
        // metido a la fuerza, y encima ocupaba una columna fija todo el
        // tiempo.
        //
        // Una tablet es una pantalla táctil grande, no un escritorio: le sirve
        // lo mismo que al teléfono, con más aire. El aire ya lo da `_margen`,
        // que en `amplio` y `enorme` deja 32 y 48 píxeles a los costados.
        bottomNavigationBar: _apaisado(context)
            ? null
            : AnimatedSlide(
                offset: _barraEscondida ? const Offset(0, 1.6) : Offset.zero,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: _barraFlotante(destinations),
              ),
      ),
    );
  }

  /// ── Cuántos íconos entran en la barra ────────────────────────────────
  ///
  /// Cuatro. El quinto, Ajustes, se va a los tres puntos junto con los atajos
  /// que antes no estaban en ningún lado.
  ///
  /// Ajustes es el que sale y no otro a propósito: es al que menos se entra de
  /// los cinco, y encima ya tiene su atajo arriba en el Home.
  static const _enLaBarra = 4;

  /// El aparato está acostado: la barra va al costado y no abajo.
  ///
  /// ── Se mira la ORIENTACIÓN, no el alto ──────────────────────────────────
  ///
  /// Antes esto era `alto < 500`, pensado para el teléfono acostado. Una
  /// tablet acostada tiene 800 píxeles de alto, así que nunca entraba: se
  /// quedaba con la barra abajo aunque estuviera igual de horizontal que el
  /// teléfono. Y la tablet vive acostada la mayor parte del tiempo.
  ///
  /// Con la orientación entran las dos, y sigue afuera lo que corresponde: una
  /// tablet DE PIE es alta y angosta, ahí la barra va abajo como en cualquier
  /// teléfono.
  ///
  /// El mínimo de ancho es para no mandar al costado una ventana angosta que
  /// por poco quedó más ancha que alta — ahí el riel se comería un tercio de
  /// la pantalla.
  static bool _apaisado(BuildContext context) {
    final t = MediaQuery.sizeOf(context);
    return t.width > t.height && t.width >= 600;
  }

  /// ── Por qué la barra SÍ lleva fondo ──────────────────────────────────────
  ///
  /// Se probó sin él y no funciona: encima de una grilla de portadas, cuatro
  /// íconos sueltos no se leen como un mando, se leen como cuatro manchas
  /// blancas. Y la marca del elegido —lo único que dice dónde estás— se pierde
  /// contra cualquier portada clara.
  ///
  /// La pastilla resuelve las dos cosas: agrupa los íconos en una sola pieza y
  /// les da un fondo parejo contra el que la marca siempre significa lo mismo.
  ///
  /// Lo que la mantiene FLOTANDO y no pegada como un zócalo es otra cosa: no
  /// llega a los bordes, está despegada de abajo, tiene esquinas redondas y el
  /// contenido le pasa por detrás (`extendBody`). Fondo y zócalo no son lo
  /// mismo.
  Widget _barraFlotante(List<_Destination> destinos) {
    // Lo que ocupa la barra del sistema —los tres botones, o la rayita de
    // gestos—. Sin esto la barra se apoya justo encima y en un teléfono con
    // gestos el deslizar de atrás se come el toque.
    final abajo = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding:
          EdgeInsets.fromLTRB(16, 0, 16, abajo > 0 ? abajo * 0.55 + 12 : 18),
      // El alto va EXPLÍCITO. Sin él, el Align de adentro se estira hasta el
      // máximo que le dan —que en un bottomNavigationBar es la pantalla
      // entera— y con `extendBody` ese alto se convierte en relleno del
      // cuerpo: la app quedaba en negro en vertical, y en horizontal no,
      // porque ahí la barra ni existía. Un Align sin alto propio LLENA.
      child: SizedBox(
        height: 62,
        // Centrada como UNA pieza: la pastilla y los tres puntos juntos.
        //
        // Antes la pastilla iba en un Expanded y se centraba en el hueco que
        // sobraba, o sea en el ancho MENOS el botón — y quedaba corrida a la
        // izquierda respecto del centro real de la pantalla.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: DecoratedBox(
                decoration: _pastilla,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    // Que no se estire: la pastilla mide lo que miden sus
                    // cuatro íconos y nada más.
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _enLaBarra; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 6),
                          child: _IconoDeBarra(
                            destino: destinos[i],
                            elegido: c.selectedTab.value == i,
                            onTap: () => _irAZona(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _botonDelExtremo(),
          ],
        ),
      ),
    );
  }

  /// La barra, de pie, para el teléfono acostado.
  ///
  /// ── Sin pastilla, al revés que abajo ─────────────────────────────────────
  ///
  /// Abajo la pastilla hace falta: la barra cruza por encima de las portadas y
  /// sin un fondo parejo los íconos se pierden. Acá no cruza nada — el riel
  /// tiene su propia columna y el contenido empieza después—, así que un
  /// recuadro alrededor sería una caja dibujada sobre el vacío.
  ///
  /// Lo único que se marca es el elegido, con su círculo.
  Widget _barraVertical(List<_Destination> destinos) {
    // En horizontal la barra del sistema se mete por un COSTADO, y de qué lado
    // depende de hacia dónde giró el teléfono. `viewPadding.left` contesta las
    // dos: vale cero cuando quedó del otro lado.
    final costados = MediaQuery.viewPaddingOf(context);
    return Padding(
      // A la derecha va el aire que separa el riel del contenido. Sin él, la
      // primera columna de tarjetas arranca pegada a los íconos.
      padding: EdgeInsets.only(left: costados.left + 10, right: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _enLaBarra; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _IconoDeBarra(
                destino: destinos[i],
                elegido: c.selectedTab.value == i,
                onTap: () => _irAZona(i),
              ),
            ),
          const SizedBox(height: 14),
          _botonDelExtremo(tamano: _ladoDelExtremo),
        ],
      ),
    );
  }

  /// El fondo de la pastilla, igual acostado que de pie.
  static final _pastilla = BoxDecoration(
    // Casi opaca. Un desenfoque de fondo se vería mejor, pero hay que
    // recalcularlo en CADA cuadro mientras el usuario se desplaza, y encima de
    // una lista de portadas es justo donde no sobran milisegundos.
    color: const Color(0xF20E0E14),
    borderRadius: BorderRadius.circular(34),
    // El aro es lo que la despega del contenido: sin él, sobre una zona oscura
    // la pastilla se funde con el fondo y los íconos vuelven a verse sueltos.
    border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
    boxShadow: const [
      BoxShadow(color: Color(0x99000000), blurRadius: 20, offset: Offset(0, 8)),
    ],
  );

  /// Cambia de zona y cierra el desplegable.
  ///
  /// Los tres puntos se abren encima del contenido, así que si el usuario se
  /// va a otra zona con ellos abiertos —tocando una opción, o el ícono de
  /// Inicio que asoma por debajo del velo— la capa se quedaba puesta sobre la
  /// pantalla nueva. Toda salida de acá pasa por este método.
  void _irAZona(int i) {
    if (_masAbierto) setState(() => _masAbierto = false);
    c.changeTab(i);
  }

  /// El lado del botón de los tres puntos cuando la barra va acostada.
  ///
  /// Con nombre y no repetido a mano: de esta medida depende dónde arranca la
  /// fila de opciones, y si los dos números se separan, las opciones se meten
  /// encima del riel.
  static const double _ladoDelExtremo = 46;

  /// Una opción del desplegable.
  ///
  /// Escalonadas: salen una atrás de otra, así se lee el recorrido en vez de
  /// aparecer las tres de golpe. Acostado el icono va primero, porque la fila
  /// crece hacia la derecha y el icono es el que tiene que quedar del lado del
  /// botón que las abrió.
  Widget _opcion(
    List<(IconData, String, VoidCallback)> opciones,
    int i,
    bool apaisado,
  ) {
    return _OpcionFlotante(
      icono: opciones[i].$1,
      texto: opciones[i].$2,
      demora: Duration(milliseconds: 60 * (opciones.length - i)),
      iconoPrimero: apaisado,
      onTap: () {
        setState(() => _masAbierto = false);
        opciones[i].$3();
      },
    );
  }

  /// Los tres puntos, al extremo de la barra.
  Widget _botonDelExtremo({double tamano = 52}) {
    return _BotonRedondo(
      icono: Icons.more_horiz_rounded,
      tamano: tamano,
      onTap: () => setState(() => _masAbierto = !_masAbierto),
    );
  }

  /// Si la barra tiene que estar escondida ahora mismo.
  ///
  /// Dos motivos, y los dos son «acá estorba»:
  ///
  ///   · Hay una pantalla completa encima —una ficha, el reproductor,
  ///     Historial—. Ahí la barra ya no manda nada.
  ///   · Se está en Ajustes. Es una lista larga de opciones y la barra tapa
  ///     justo las últimas; además Ajustes no tiene botón propio en la barra,
  ///     así que no habría nada marcado. Su propia flecha se encarga de
  ///     volver (ver settings_page.dart).
  bool get _barraEscondida =>
      ObservadorDePila.hayPantallaEncima.value ||
      c.selectedTab.value == MainController.tabAjustes;

  /// Los botones que salen de los tres puntos.
  ///
  /// Flotando sobre el contenido y no en una hoja que sube desde abajo: la
  /// hoja tapa media pantalla y se lee como «entré a otro lado», cuando lo
  /// único que pasó es que la barra mostró lo que tenía guardado. Saliendo
  /// desde el propio botón, se ve de dónde vienen y a qué vuelven.
  Widget _capaDeMas() {
    final apaisado = _apaisado(context);
    final bordes = MediaQuery.viewPaddingOf(context);

    final opciones = <(IconData, String, VoidCallback)>[
      (
        Icons.settings_outlined,
        'common.settings'.i18n,
        () => _irAZona(MainController.tabAjustes),
      ),
      (
        Icons.history_rounded,
        'home.history'.i18n,
        () => Get.to(() => const HistoryPage()),
      ),
      (
        Icons.favorite_border_rounded,
        'home.favorite'.i18n,
        // La pestaña de favoritos de Historial. Mismo índice que usa
        // Biblioteca — si cambia allá, cambia acá.
        () => Get.to(() => const HistoryPage(initialTab: 3)),
      ),
    ];

    return Positioned.fill(
      child: Stack(
        children: [
          // Tocar afuera cierra. Y el velo no es decorativo: sin él, los
          // botones flotantes se pierden encima de una grilla de portadas.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _masAbierto = false),
            child: const ColoredBox(color: Color(0xB3000000)),
          ),
          Positioned(
            // ── Acostado salen HACIA LA DERECHA, no hacia arriba ───────────
            //
            // Antes esto era una columna anclada al mismo borde izquierdo que
            // el riel, así que las opciones se apilaban ENCIMA de los íconos
            // de la barra y subían por la pantalla. Reportado en vivo: «los
            // botones se desplazan arriba, era el botón en sí y no solo el
            // texto».
            //
            // Ahora es una FILA que arranca justo después del riel: las
            // opciones salen del botón hacia el costado libre, que es donde
            // hay lugar cuando el teléfono está acostado. De pie se queda como
            // estaba —columna que sube desde el botón, que ahí está abajo—.
            //
            // El desplazamiento horizontal es la red: con tres opciones entran
            // de sobra, pero si mañana son cinco no se salen de la pantalla.
            left: apaisado ? bordes.left + 10 + _ladoDelExtremo + 14 : null,
            right: apaisado ? null : 18,
            top: apaisado ? 0 : null,
            bottom: apaisado
                ? 0
                : (bordes.bottom > 0 ? bordes.bottom * 0.55 + 14 : 20) + 66,
            child: apaisado
                ? Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < opciones.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _opcion(opciones, i, apaisado),
                            ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < opciones.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _opcion(opciones, i, apaisado),
                        ),
                    ],
                  ),
          ),
        ],
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
    return _TransicionDeZona(
      indice: c.selectedTab.value,
      child: _pilaDePaginas(),
    );
  }

  Widget _pilaDePaginas() {
    return IndexedStack(
      index: c.selectedTab.value,
      children: [
        for (var i = 0; i < pages.length; i++)
          RepaintBoundary(
            child: TickerMode(
              enabled: i == c.selectedTab.value,
              // ── Sin SafeArea de abajo tampoco ──────────────────────
              //
              // Hacía lo mismo que el de arriba pero al revés: reservaba el
              // alto de la barra flotante POR AFUERA de la página, así que
              // detrás de la barra quedaba una banda negra en vez del fondo de
              // la zona. Se veía como una sombra tapando.
              //
              // El lugar no se pierde: ahora cada zona se lo suma al relleno
              // de su propia lista (`MediaQuery.paddingOf(context).bottom`,
              // que con `extendBody` ya vale exactamente el alto de la barra).
              // Así el fondo llega hasta el borde y lo que se desplaza igual
              // termina por encima de la barra.
              child: pages[i],
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

/// Un botón de la barra flotante.
///
/// El elegido se marca con un círculo relleno detrás. Sobre la pastilla, que
/// es de un tono parejo, alcanza con eso: no hace falta que el círculo sea
/// opaco ni que el ícono cambie de color, y así la marca se ve como parte de
/// la barra y no como un botón distinto pegado encima.
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: elegido ? acento.withValues(alpha: 0.3) : Colors.transparent,
          ),
          child: Icon(
            elegido ? destino.selectedIcon : destino.icon,
            size: 23,
            color: elegido ? Colors.white : Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// El botón redondo del extremo de la barra.
///
/// Sólido siempre, esté o no en la zona activa: lo que hace no es cambiar de
/// pestaña, y sin una forma que lo distinga se leería como un quinto destino.
class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({
    required this.icono,
    required this.onTap,
    this.tamano = 52,
  });

  final IconData icono;
  final VoidCallback onTap;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.alphaBlend(
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.34),
        const Color(0xFF14141C),
      ),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      shadowColor: const Color(0xCC000000),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: tamano,
          height: tamano,
          child: Icon(icono, size: 25, color: Colors.white),
        ),
      ),
    );
  }
}

/// Una de las opciones que salen de los tres puntos: su etiqueta y su botón.
class _OpcionFlotante extends StatelessWidget {
  const _OpcionFlotante({
    required this.icono,
    required this.texto,
    required this.onTap,
    required this.demora,
    required this.iconoPrimero,
  });

  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final Duration demora;

  /// Acostado la barra está a la izquierda, así que el botón va primero y la
  /// etiqueta sale hacia adentro de la pantalla. Al revés, la etiqueta se
  /// saldría por el borde.
  final bool iconoPrimero;

  @override
  Widget build(BuildContext context) {
    final etiqueta = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xF01A1A24),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 12),
        ],
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final boton = _BotonRedondo(icono: icono, onTap: onTap, tamano: 48);

    final fila = Row(
      mainAxisSize: MainAxisSize.min,
      children: iconoPrimero
          ? [boton, const SizedBox(width: 12), etiqueta]
          : [etiqueta, const SizedBox(width: 12), boton],
    );

    // TweenAnimationBuilder y no un controlador: esto se monta cuando se abre
    // y se desmonta cuando se cierra, así que alcanza con una animación que
    // corre una sola vez al aparecer. La demora distinta por opción es la que
    // las hace salir en fila.
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200) + demora,
        curve: Curves.easeOutBack,
        builder: (context, t, hijo) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: hijo,
          ),
        ),
        child: fila,
      ),
    );
  }
}

/// El cambio de zona, con movimiento.
///
/// ── Por qué así y no con un PageView ─────────────────────────────────────
///
/// Porque las cinco pestañas viven en un IndexedStack para no montarse de cero
/// cada vez —ver el comentario largo en `_buildPages`— y un PageView tira lo
/// que no se ve. Cambiar a PageView por la animación habría devuelto el
/// remount que ese IndexedStack vino a sacar: scroll perdido, listas
/// recargando, todo de nuevo en cada toque.
///
/// Entonces la animación va POR AFUERA de la pila: cuando cambia la pestaña, lo
/// que ya está montado entra corriéndose y apareciendo. Cuesta un Transform y
/// un Opacity durante 220 ms, y no toca el estado de ninguna página.
///
/// ── Por qué el lado importa ──────────────────────────────────────────────
///
/// Porque la barra de abajo es una fila: si voy de Buscar a Extensiones —de
/// izquierda a derecha— y la pantalla entra desde la izquierda, el movimiento
/// contradice al dedo. Entrando desde el lado correcto, la app se siente como
/// una tira que se corre, que es lo que la barra ya está sugiriendo.
class _TransicionDeZona extends StatefulWidget {
  const _TransicionDeZona({required this.indice, required this.child});

  final int indice;
  final Widget child;

  @override
  State<_TransicionDeZona> createState() => _TransicionDeZonaState();
}

class _TransicionDeZonaState extends State<_TransicionDeZona>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    // Arranca terminada: al abrir la app la primera pestaña ya tiene que estar
    // puesta, sin una animación de entrada que nadie pidió.
    value: 1,
  );

  /// Hacia dónde entra: 1 si se fue a una pestaña de más a la derecha.
  double _lado = 1;

  @override
  void didUpdateWidget(_TransicionDeZona viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.indice == widget.indice) return;
    _lado = widget.indice > viejo.indice ? 1 : -1;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      // El hijo se pasa aparte para que la pila NO se reconstruya en cada
      // cuadro de la animación: solo se recalculan el corrimiento y la
      // opacidad, que es barato.
      child: widget.child,
      builder: (context, hijo) {
        final t = Curves.easeOutCubic.transform(_c.value);
        // ── Solo corrimiento, sin desvanecido ────────────────────────────
        //
        // El Opacity que había acá envolvía la pila ENTERA de pestañas, y eso
        // obliga a Flutter a dibujar todo en una capa aparte para después
        // aplicarle la transparencia. Con Impeller además saltaba una queja en
        // cada cambio de zona:
        //
        //   Contents::SetInheritedOpacity should never be called when
        //   Contents::CanAcceptOpacity returns false
        //
        // El corrimiento solo ya se lee igual de bien y no cuesta ninguna capa
        // de más: es una transformación, no un redibujado.
        return Transform.translate(
          // Corto a propósito. Un desplazamiento largo se siente lento aunque
          // dure lo mismo, y acá se cambia de pestaña todo el tiempo.
          offset: Offset(_lado * 34 * (1 - t), 0),
          child: hijo,
        );
      },
    );
  }
}
