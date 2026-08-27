import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:prismhub/views/widgets/beta_notice.dart';
import 'package:prismhub/controllers/catalogo_extensiones_controller.dart';
import 'package:prismhub/controllers/zona_catalogo_controller.dart';
import 'package:prismhub/views/pages/extension/extension_page.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/home_page.dart';
import 'package:prismhub/views/pages/library_page.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/pages/settings/settings_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_search_page.dart';
import 'package:prismhub/views/pages/zonas/zona_catalogo_page.dart';
import 'package:prismhub/views/pages/zonas/zona_tv_page.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/modo_app.dart';
import 'package:prismhub/utils/platform_tv.dart';
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

  /// Si la ruta actual es esta (o una de sus subrutas) — para saber qué
  /// burbuja del riel marcar como seleccionada. Compara contra la ruta y no
  /// contra `c.selectedTab` a propósito: Repositorio y Ajustes navegan con
  /// `router.go` directo, sin pasar por `changeTab`, así que el número de
  /// pestaña se queda atrasado para esos dos — la ruta nunca miente.
  ///
  /// El corte con `/` es a propósito: sin él, `/extension_repo` "empieza
  /// con" `/extension` y las dos burbujas se hubieran marcado juntas.
  bool _enRuta(String ruta) {
    final path = widget.state.uri.path;
    if (ruta == '/') return path == '/';
    return path == ruta || path.startsWith('$ruta/');
  }

  /// El tamaño de cada burbuja del riel, según el alto REAL de la ventana.
  ///
  /// ── El bug real que esto corrige ─────────────────────────────────────
  ///
  /// Con las 9 burbujas a su tamaño fijo (42px + 6px de aire arriba/abajo =
  /// 54px cada una, ~486px en total) más el aire del encabezado, una
  /// ventana baja (poca altura, ej. una mitad de pantalla en un monitor
  /// normal) no alcanzaba a mostrarlas todas — y Fluent lo resuelve solo
  /// con SU PROPIO scroll vertical en el riel, un scrollbar angosto al lado
  /// de las burbujas. Se ve roto contra el resto del diseño. Pedido
  /// explícito: "quita el scroll... acomoda los botones adaptable".
  ///
  /// Se calcula cuánto entra de verdad y se achica el diámetro (nunca por
  /// debajo de 30, para que el ícono siga siendo tocable) antes de que
  /// Fluent tenga que recurrir a su scroll.
  ({double diametro, double espacioVertical}) _tamanoBurbujas(
      BuildContext context) {
    final altura = MediaQuery.sizeOf(context).height;
    // 9 burbujas: Inicio + 4 zonas + Biblioteca + Extensiones (items) más
    // Repositorio + Ajustes (footerItems) — la versión y el separador no
    // cuentan, son chicos y fijos.
    const cantidad = 9.0;
    // Barra de título (~50) + el header de 16 que se le agregó al riel +
    // un colchón para el separador y el aire del footer.
    const reservado = 110.0;
    final disponible = altura - reservado;
    final porItem = (disponible / cantidad).clamp(24.0, 54.0);
    // El piso baja bastante respecto de la primera versión (era 30/3): con
    // una ventana de verdad chica, Fluent recurre a SU PROPIO scroll interno
    // en el riel apenas la suma de las filas no entra en el alto que le
    // queda — y esa fila tiene un mínimo propio del paquete, no solo el
    // tamaño del ícono de adentro. Dejando que el ícono se achique más antes
    // de tocar ese piso, hay más margen para evitar el scroll de Fluent en
    // ventanas moderadamente bajas. En una MUY baja (una franja angosta de
    // verdad) puede que ese mínimo propio de Fluent siga ganando — eso no es
    // algo que se pueda seguir empujando solo desde el tamaño del ícono.
    final diametro = (porItem - 4).clamp(18.0, 42.0);
    final espacioVertical = ((porItem - diametro) / 2).clamp(1.0, 6.0);
    return (diametro: diametro, espacioVertical: espacioVertical);
  }

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

  /// Al VOLVER a una zona, no solo al abrirla la primera vez.
  ///
  /// ── Por qué acá y no en el `initState` de cada pantalla ─────────────────
  ///
  /// El WIDGET de cada zona (`ZonaCatalogoPage`) se rearma de cero en cada
  /// navegación —esta pantalla cuelga de una `ShellRoute` de go_router, y
  /// `widget.child` es su Navigator anidado: no hay ningún `IndexedStack`
  /// escondido que lo evite (se intentó una vez y rompió la navegación a la
  /// ficha, porque reemplazaba ese Navigator entero — revertido). Lo que SÍ
  /// sobrevive es el `ZonaCatalogoController` de cada zona, registrado por
  /// tag en GetX: el catálogo ya bajado no se pierde, solo se vuelve a
  /// dibujar la grilla con lo que el controller ya tiene en memoria.
  ///
  /// `widget.state` cambia en cada navegación — comparando la ruta vieja
  /// contra la nueva en `didUpdateWidget` se sabe exactamente cuándo el
  /// usuario ACABA de entrar a una pestaña, sin importar que su contenido
  /// ya estuviera armado de antes.
  ///
  /// Pedido explícito: Inicio se pone al día y resortea por dónde arranca
  /// el carrusel cada vez que se vuelve a entrar; las zonas de contenido
  /// se ponen al día por si alguna extensión publicó algo nuevo — ninguna
  /// de las dos cosas rompe lo que ya estaba en pantalla (el refresco
  /// reusa/actualiza filas existentes, nunca las tira a la basura de
  /// entrada).
  @override
  void didUpdateWidget(covariant DesktopMainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rutaVieja = oldWidget.state.uri.path;
    final rutaNueva = widget.state.uri.path;
    if (rutaVieja == rutaNueva) return;
    _alSalirDe(rutaVieja);
    _alVolverA(rutaNueva);
  }

  /// Libera lo acumulado por scroll de la zona que se deja — ver
  /// `ZonaCatalogoController.liberarMemoria`.
  void _alSalirDe(String ruta) {
    final zona = _zonaDeRuta(ruta);
    if (zona == null) return;
    if (!Get.isRegistered<ZonaCatalogoController>(tag: zona.name)) return;
    Get.find<ZonaCatalogoController>(tag: zona.name).liberarMemoria();
  }

  ZonaPrincipal? _zonaDeRuta(String ruta) => switch (ruta) {
        final r when r.startsWith('/peliculas') => ZonaPrincipal.peliculas,
        final r when r.startsWith('/series') => ZonaPrincipal.series,
        final r when r.startsWith('/anime') => ZonaPrincipal.anime,
        final r when r.startsWith('/mangas') => ZonaPrincipal.mangas,
        _ => null,
      };

  /// El `onTap` de cada destino del panel lateral (Inicio y las 4 zonas).
  ///
  /// `router.go(ruta)` a la ruta en la que ya se está es un no-op para
  /// go_router — sin transición, sin que `didUpdateWidget` se entere de
  /// nada. Pedido explícito: tocar el botón de una zona estando YA
  /// adentro tiene que refrescar y volver arriba al principio, no quedarse
  /// quieto como si no hubiera pasado nada.
  void _alTocarDestino(String ruta) {
    if (widget.state.uri.path == ruta) {
      if (ruta == '/') {
        _alVolverA(ruta);
        return;
      }
      final zona = _zonaDeRuta(ruta);
      if (zona != null &&
          Get.isRegistered<ZonaCatalogoController>(tag: zona.name)) {
        Get.find<ZonaCatalogoController>(tag: zona.name).alTocarDeNuevo();
      }
      return;
    }
    router.go(ruta);
  }

  void _alVolverA(String ruta) {
    if (ruta == '/') {
      if (!Get.isRegistered<CatalogoExtensionesController>()) return;
      // Solo el refresco de contenido — pedido explícito: el carrusel NO
      // se toca acá. Ya tiene su propio criterio de rotación/random
      // (_arranque, una vez por apertura de la app) que sigue andando
      // solo; intentar resortearlo también al re-entrar dio varios bugs
      // seguidos (saltos raros, posiciones a mitad de camino) sin poder
      // verlo en pantalla para depurarlo bien. Mejor uno solo, que ya
      // funciona, que dos peleándose.
      unawaited(Get.find<CatalogoExtensionesController>().refrescarTodo());
      return;
    }
    final zona = _zonaDeRuta(ruta);
    if (zona == null) return;
    if (!Get.isRegistered<ZonaCatalogoController>(tag: zona.name)) return;
    unawaited(Get.find<ZonaCatalogoController>(tag: zona.name).cargarInicial());
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
    if (ruta.startsWith('/peliculas')) return 'home.zona-peliculas'.i18n;
    if (ruta.startsWith('/series')) return 'home.zona-series'.i18n;
    if (ruta.startsWith('/anime')) return 'home.zona-anime'.i18n;
    if (ruta.startsWith('/mangas')) return 'home.zona-mangas'.i18n;
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
            // Con el color puesto, no heredado.
            //
            // Sin color caía en la tipografía de Fluent, que trae la suya según
            // SU tema. Con el modo claro quedaba blanco sobre la barra clara.
            Text(
              'PrismHub',
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                color: HomeTheme.textPrimary,
              ),
            ),
            // El nombre de la app se queda: es lo que identifica la ventana en
            // la barra de tareas y en la captura. La zona va al lado, más
            // liviana, para que se lea como «dónde estoy» y no como otro
            // título compitiendo con el primero.
            if (zona.isNotEmpty) ...[
              const SizedBox(width: 10),
              // Los dos con la paleta del modo, no con blanco a mano: en claro
              // el separador desaparecía y la zona quedaba ilegible.
              Container(
                width: 1,
                height: 16,
                color: HomeTheme.border,
              ),
              const SizedBox(width: 10),
              Text(
                zona,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: HomeTheme.textMuted,
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
    final burbujas = _tamanoBurbujas(context);
    return fluent.NavigationView(
      appBar: fluent.NavigationAppBar(
        leading: () {
          return fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.back, size: 12.0),
            onPressed: () {
              // `router.canPop()` mira el navigator RAÍZ sin importar desde
              // dónde se llame — reportado en vivo con el log completo:
              // `Null check operator used on a null value` dentro de
              // go_router (`_NavigatorStateIterator.moveNext`), porque el
              // navigator anidado de esta ShellRoute no es el que ese
              // método asume. `context.canPop()` resuelve el GoRouter más
              // cercano A ESTE contexto —el mismo que usa `context.pop()`
              // dos líneas más abajo—, así que los dos quedan consultando
              // al mismo navigator.
              if (context.canPop()) {
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
              // Único punto para buscar en escritorio desde que la Fase 6c
              // sacó "Buscar" del panel lateral (era una zona más, con su
              // propia entrada fija) — reportado en vivo: sin esto no había
              // NINGÚN camino visible a SearchPage en Windows. Se pone acá,
              // en la barra superior, en vez de depender de un botón dentro
              // de cada zona: es el único lugar que se ve sea cual sea la
              // pantalla en la que se esté parado.
              //
              // Y DETECTA sola la Zona +18: antes esta misma barra convivía
              // con OTRO botón de buscar, propio de esa zona
              // (nsfw18_zone_page.dart), y las dos lupas juntas en pantalla
              // se veían como dos caminos distintos a lo mismo — pedido
              // explícito de que sea una sola, la de siempre, que cambie de
              // destino sola según dónde se esté parado. `_enRuta` es el
              // mismo chequeo que ya usa cada `_Burbuja` del panel para
              // saber si está seleccionada.
              fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.search, size: 16.0),
                onPressed: () => _enRuta('/adult-zone')
                    ? openNsfw18Search(context, yaAutorizado: true)
                    : router.go('/search'),
              ),
              const SizedBox(width: 4),
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
        // Pedido explícito: sin el botón de arriba para plegar/desplegar el
        // riel — acá el riel siempre va en `compact` (ver `displayMode` más
        // abajo), así que ese botón no tenía ningún estado al que llevar.
        toggleable: false,
        // Pedido explícito: iconos grandes en el panel lateral. Fluent
        // calcula el ancho de cada ícono del riel a partir de este
        // `compactWidth` (por defecto 50), así que hace falta agrandar el
        // riel entero para que el ícono más grande (24, ver cada PaneItem
        // abajo) tenga dónde entrar sin desbordar la fila — mismo desborde
        // que ya se reportó una vez con el tamaño por defecto de Fluent.
        size: const fluent.NavigationPaneSize(
          openMaxWidth: 230,
          compactWidth: 64,
        ),
        // Sin el botón de arriba, el riel arrancaba pegado al borde de la
        // barra de título — un aire chico antes del primer ícono para que
        // no quede a tope, pedido explícito.
        header: const SizedBox(height: 16),
        // Pedido explícito: nada de la marca rectangular que dibuja Fluent
        // solo (`StickyNavigationIndicator`, el valor por defecto) — la
        // burbuja de cada ítem (ver `_Burbuja` abajo) ya es su propio
        // indicador, circular. Con los dos a la vez se veían dos marcas
        // distintas compitiendo por decir "estás acá".
        indicator: null,
        selected: c.selectedTab.value,
        onChanged: c.changeTab,
        displayMode: fluent.PaneDisplayMode.compact,
        footerItems: [
          fluent.PaneItemSeparator(),
          // La entrada a la Zona +18 se sacó de acá: un ícono de advertencia
          // rojo siempre visible en el panel lateral es lo contrario de
          // discreto — cualquiera que mire la pantalla de reojo lo ve. Ahora
          // vive dentro de Ajustes, junto al switch de NSFW (ver
          // settings_page.dart), igual que ya estaba en Android.
          fluent.PaneItem(
            tileColor: const fluent.WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor:
                const fluent.WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: fluent.FluentIcons.repo,
              seleccionado: _enRuta('/extension_repo'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('common.extension-repo'.i18n),
            body: const ExtensionPage(),
            onTap: () {
              router.go('/extension_repo');
            },
          ),
          fluent.PaneItem(
            tileColor: const fluent.WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor:
                const fluent.WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: fluent.FluentIcons.settings,
              seleccionado: _enRuta('/settings'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('common.settings'.i18n),
            body: const SettingsPage(),
            onTap: () {
              router.go('/settings');
            },
          ),
          // La versión, al pie de todo. Ver DistintivoDeVersion.
          //
          // Con el riel plegado —que es como arranca— no entra una pastilla con
          // texto, así que ahí no se dibuja: quedaría cortada contra el borde.
          // Al abrirlo aparece.
          fluent.PaneItemWidgetAdapter(
            child: Builder(
              builder: (context) {
                final abierto = fluent.NavigationView.of(context).displayMode ==
                    fluent.PaneDisplayMode.open;
                if (!abierto) return const SizedBox.shrink();
                return const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DistintivoDeVersion(),
                  ),
                );
              },
            ),
          ),
        ],
        items: [
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: fluent.FluentIcons.home,
              seleccionado: _enRuta('/'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('common.home'.i18n),
            body: const HomePage(),
            onTap: () => _alTocarDestino('/'),
          ),
          // TV/streaming en vivo: mismo lugar y mismo criterio que ya tiene
          // Android TV (`_CategoriaTV.tv`) — todavía no hay ninguna extensión
          // que declare este tipo de contenido, así que queda vacía a
          // propósito hasta que aparezca una (ver `ZonaTvPage`).
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: Icons.live_tv_rounded,
              seleccionado: _enRuta('/tv'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('home.tv-canales'.i18n),
            body: const ZonaTvPage(),
            onTap: () => _alTocarDestino('/tv'),
          ),
          // Mismos íconos que ya usa Android (`destinations`, más abajo) y
          // Android TV (`_CategoriaTV`, home_page_tv.dart) para estas
          // cuatro — pedido explícito, en vez de los de Fluent que traía
          // antes.
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: Icons.movie_rounded,
              seleccionado: _enRuta('/peliculas'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('home.zona-peliculas'.i18n),
            body: const ZonaCatalogoPage(zona: ZonaPrincipal.peliculas),
            onTap: () => _alTocarDestino('/peliculas'),
          ),
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: Icons.tv_rounded,
              seleccionado: _enRuta('/series'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('home.zona-series'.i18n),
            body: const ZonaCatalogoPage(zona: ZonaPrincipal.series),
            onTap: () => _alTocarDestino('/series'),
          ),
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: Icons.animation_rounded,
              seleccionado: _enRuta('/anime'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('home.zona-anime'.i18n),
            body: const ZonaCatalogoPage(zona: ZonaPrincipal.anime),
            onTap: () => _alTocarDestino('/anime'),
          ),
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: Icons.auto_stories_rounded,
              seleccionado: _enRuta('/mangas'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('home.zona-mangas'.i18n),
            body: const ZonaCatalogoPage(zona: ZonaPrincipal.mangas),
            onTap: () => _alTocarDestino('/mangas'),
          ),
          // Biblioteca: lo que el usuario YA tiene (Continuar viendo,
          // Favoritos). Es el Home de antes, movido tal cual sin rediseñar —
          // ver library_page.dart.
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: fluent.FluentIcons.library,
              seleccionado: _enRuta('/biblioteca'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
            title: Text('common.library'.i18n),
            body: const LibraryPage(),
            onTap: () {
              router.go('/biblioteca');
            },
          ),
          fluent.PaneItem(
            tileColor: const WidgetStatePropertyAll(Colors.transparent),
            selectedTileColor: const WidgetStatePropertyAll(Colors.transparent),
            icon: _Burbuja(
              icono: fluent.FluentIcons.add_in,
              seleccionado: _enRuta('/extension'),
              diametro: burbujas.diametro,
              espacioVertical: burbujas.espacioVertical,
            ),
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

/// El ícono de cada destino del riel: una burbuja circular translúcida,
/// estilo acrílico — pedido explícito ("como burbuja", con una captura de
/// referencia de íconos redondos flotantes en vez del cuadrado con esquinas
/// que dibuja Fluent por defecto.
///
/// Reemplaza del todo el indicador propio de Fluent (`tileColor`/
/// `selectedTileColor` van transparentes en cada `PaneItem`, y
/// `NavigationPane.indicator` va en `null`, ver más arriba) — con los dos
/// indicadores a la vez se leían como dos marcas distintas.
///
/// Sin animación de tamaño/posición al pasar el mouse o seleccionar, mismo
/// criterio que ya se usa en `BotonesVentana`: el color cambia al instante,
/// nada se mueve ni escala.
class _Burbuja extends StatefulWidget {
  const _Burbuja({
    required this.icono,
    required this.seleccionado,
    this.diametro = 42,
    this.espacioVertical = 6,
  });

  final IconData icono;
  final bool seleccionado;

  /// El tamaño del círculo y el aire arriba/abajo — pedido explícito:
  /// "quita el scroll cuando la ventana es chica, acomoda los botones
  /// adaptable". Sin esto, una ventana baja (poca altura) desbordaba el
  /// riel entero y Fluent lo resolvía con SU PROPIO scroll vertical — un
  /// scrollbar angosto al lado de las burbujas, que se veía roto contra el
  /// resto del diseño. `_DesktopMainPageState._tamanoBurbujas` calcula estos
  /// dos números según el alto real de la ventana para que las 9 burbujas
  /// entren siempre sin scroll, achicándose si hace falta.
  final double diametro;
  final double espacioVertical;

  @override
  State<_Burbuja> createState() => _BurbujaState();
}

class _BurbujaState extends State<_Burbuja> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final acento = HomeTheme.accentPink;
    final colorRelleno = widget.seleccionado
        ? acento.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: _hover ? 0.10 : 0.05);
    final borde = widget.seleccionado
        ? acento.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: _hover ? 0.22 : 0.12);
    // El aire vertical de sobra es lo que separa las burbujas entre sí: el
    // riel de Fluent no tiene una propiedad de "espaciado entre ítems", pero
    // sí deja crecer la fila más allá de su alto mínimo si el contenido pide
    // más — pedido explícito ("da espacio"), sin tocar el ancho del riel.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.espacioVertical),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          width: widget.diametro,
          height: widget.diametro,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorRelleno,
            border: Border.all(color: borde, width: 1.2),
            boxShadow: widget.seleccionado
                ? [
                    BoxShadow(
                      color: acento.withValues(alpha: 0.28),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icono,
            // El ícono escala con el círculo — sin esto, achicar la burbuja
            // en una ventana baja dejaba el ícono grande de siempre casi
            // tocando el borde.
            size: widget.diametro * 0.45,
            color: widget.seleccionado ? acento : HomeTheme.textPrimary,
          ),
        ),
      ),
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
    _devolverElFoco(previousRoute);
  }

  /// Le devuelve el foco a la pantalla que queda a la vista.
  ///
  /// ── Por qué hace falta ────────────────────────────────────────────────
  ///
  /// Al cerrar una pantalla, el widget que tenía el foco se va con ella y el
  /// foco queda en el aire. Con dedo o mouse no se nota —el próximo toque lo
  /// arregla— pero con un control remoto es fatal: sin nada enfocado, las
  /// flechas no tienen desde dónde moverse y la app queda congelada.
  ///
  /// Pasaba al volver de Extensiones, Favoritos o Ajustes con el botón de
  /// atrás del mando.
  void _devolverElFoco(Route<dynamic>? destino) {
    if (!PlatformTv.esTelevisionSync) return;
    final contexto = destino?.navigator?.context;
    if (contexto == null) return;
    // Después del cuadro: durante el pop el árbol todavía se está
    // desarmando, y pedir foco ahí no llega a ningún lado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!contexto.mounted) return;
      final ambito = FocusScope.of(contexto);
      // `focusedChild` es lo que esa pantalla tenía enfocado antes de que le
      // abrieran algo encima: devolvérselo deja al usuario donde estaba, no
      // en el primer elemento de la lista.
      //
      // Ojo con el caso que rompía todo (medido en vivo): ese "hijo
      // enfocado" puede ser OTRO ÁMBITO, no un widget. Devolverle el foco a
      // un ámbito deja al mando sin destino —las flechas no tienen desde
      // dónde salir— y la app queda congelada hasta cerrarla. Por eso solo
      // vale si es un nodo de verdad.
      final anterior = ambito.focusedChild;
      if (anterior != null &&
          anterior is! FocusScopeNode &&
          anterior.context != null &&
          anterior.canRequestFocus) {
        anterior.requestFocus();
        return;
      }
      ambito.nextFocus();
    });
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

  /// Las cinco zonas, ya armadas.
  ///
  /// ── Por qué NO es `const`, que es como estaba ──────────────────────────
  ///
  /// Era `final pages = const [HomePage(), ...]`: widgets const guardados en un
  /// campo, o sea SIEMPRE los mismos cinco objetos. Y cuando el widget nuevo es
  /// el MISMO objeto que el viejo, Flutter no actualiza el elemento ni baja al
  /// subárbol — se lo saltea entero (`updateChild` en framework.dart:
  /// `if (hasSameSuperclass && child.widget == newWidget)`).
  ///
  /// Con eso, cambiar de claro a oscuro no llegaba a ninguna de las cinco
  /// pestañas: la raíz se rehacía, esta pantalla se rehacía, y acá se cortaba
  /// el camino. Es el mismo bug que ya se había arreglado un piso más arriba
  /// con el `const AndroidMainPage()` de main.dart, escondido un nivel abajo.
  ///
  /// ── Y por qué se guardan igual, en vez de armarlas en cada dibujado ────
  ///
  /// Porque esta pantalla se rehace bastante seguido —al cambiar de pestaña, al
  /// abrir los tres puntos, al entrar y salir de una ficha—, y con instancias
  /// nuevas cada vez las CINCO zonas volverían a construirse en cada uno de
  /// esos toques, no solo la que se ve. Guardándolas se conserva el atajo de
  /// Flutter para todo eso, que es lo que había antes.
  ///
  /// Se rehacen en un solo caso: cuando cambia el modo de color. Ver
  /// [_pilaDePaginas].
  List<Widget> _zonas = _crearZonas();

  /// El modo con el que se armaron las zonas que hay guardadas.
  bool _modoDeLasZonas = ModoDeColor.claro;

  /// Sin un solo `const` acá, y no es un descuido: un widget const está
  /// canonizado, o sea que `const HomePage()` devuelve SIEMPRE el mismo objeto
  /// y rehacer la lista no cambiaría nada. Es justamente lo que hay que evitar.
  ///
  /// De ahí los `ignore`: el analizador ve constructores que podrían ser
  /// const y avisa, sin saber que acá eso rompe la función.
  ///
  /// Buscar ya no tiene zona propia acá — ver `home_hero_banner.dart`/
  /// `home_page_tv.dart`, que ahora la empujan como pantalla suelta
  /// (`Get.to`), igual que Historial o el Repositorio.
  ///
  /// El orden tiene que ser el MISMO que `MainController.tabHome`/
  /// `tabPeliculas`/etc. y que `destinations`, más abajo — ver el
  /// comentario de `main_controller.dart`.
  static List<Widget> _crearZonas() => [
        // ignore: prefer_const_constructors
        HomePage(),
        const ZonaCatalogoPage(zona: ZonaPrincipal.peliculas),
        const ZonaCatalogoPage(zona: ZonaPrincipal.series),
        const ZonaCatalogoPage(zona: ZonaPrincipal.anime),
        const ZonaCatalogoPage(zona: ZonaPrincipal.mangas),
        // ignore: prefer_const_constructors
        LibraryPage(),
        // ignore: prefer_const_constructors
        ExtensionPage(),
        // ignore: prefer_const_constructors
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
      // Mismos íconos que ya eligió Android TV para estas tres categorías
      // (`_CategoriaTV`, home_page_tv.dart) — reconocimiento cruzado entre
      // plataformas.
      _Destination(
          Icons.movie_outlined, Icons.movie, 'home.zona-peliculas'.i18n),
      _Destination(
          Icons.tv_outlined, Icons.tv_rounded, 'home.zona-series'.i18n),
      _Destination(Icons.animation_outlined, Icons.animation_rounded,
          'home.zona-anime'.i18n),
      _Destination(Icons.auto_stories_outlined, Icons.auto_stories_rounded,
          'home.zona-mangas'.i18n),
      // Biblioteca: lo que el usuario YA tiene (Continuar viendo, Favoritos).
      // Es el Home de antes, movido tal cual — ver library_page.dart.
      _Destination(Icons.video_library_outlined, Icons.video_library,
          'common.library'.i18n),
      _Destination(
          Icons.extension_outlined, Icons.extension, 'common.extension'.i18n),
      _Destination(
          Icons.settings_outlined, Icons.settings, 'common.settings'.i18n),
    ];
    return Obx(
      // ── El botón de atrás del sistema ──────────────────────────────────
      //
      // Las zonas NO son rutas: viven en un IndexedStack dentro de este mismo
      // Scaffold. Así que para Android no hay nada apilado que desapilar, y su
      // botón de atrás cerraba el app de una — incluso estando en Ajustes,
      // adonde se entra a propósito desde otra zona.
      //
      // Con esto el atrás hace lo que uno espera: desde Ajustes vuelve a la
      // zona de la que se vino (la misma que ofrece la flecha de su cabecera),
      // desde cualquier otra vuelve a Inicio, y recién estando en Inicio sale.
      // O sea que salir del app pasa a ser una decisión y no un accidente.
      () => PopScope(
        canPop: c.selectedTab.value == MainController.tabHome,
        onPopInvokedWithResult: (salio, _) {
          if (salio) return;
          if (c.selectedTab.value == MainController.tabAjustes) {
            c.changeTab(c.tabAnterior);
            return;
          }
          c.changeTab(MainController.tabHome);
        },
        child: Scaffold(
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
                  // TV primero: sin riel ni barra flotante — son diseño de
                  // teléfono/tablet, pensados para dedo y pulgar. En TV la
                  // navegación entre secciones va por la barra propia de
                  // `HomeTV` (Buscar/Favoritos/Historial/Ajustes) y por
                  // Ajustes; acá no hay nada que dibujar aparte del contenido.
                  child: PlatformTv.esTelevisionSync
                      ? _buildPages()
                      : _apaisado(context)
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
                                // ── Al esconderse tiene que SOLTAR el ancho ───────
                                //
                                // Antes era un AnimatedSlide, que corre el riel hacia
                                // afuera pero le deja el lugar reservado: en el Row
                                // seguía ocupando su columna. O sea que en Ajustes
                                // —la única zona donde la barra se esconde— quedaba
                                // una franja vacía a la izquierda y todo el contenido
                                // aparecía corrido a la derecha. Reportado en vivo.
                                //
                                // De pie no pasaba porque ahí la barra FLOTA encima
                                // del contenido: correrla ya libera la pantalla.
                                //
                                // Con AnimatedSize el ancho se va con ella, así que
                                // Ajustes usa la pantalla entera, y el encogerse se
                                // ve como que la barra se retira.
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  child: _barraEscondida
                                      ? const SizedBox.shrink()
                                      : _barraVertical(destinations),
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
            // Solo de pie: acostado no hay botón de tres puntos que lo abra
            // (sus opciones van directas en el riel), y si quedó abierto al
            // girar, no puede seguir puesto sobre la pantalla nueva.
            if (_masAbierto && !_apaisado(context)) _capaDeMas(),
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
          bottomNavigationBar: (PlatformTv.esTelevisionSync ||
                  _apaisado(context))
              ? null
              : AnimatedSlide(
                  offset: _barraEscondida ? const Offset(0, 1.6) : Offset.zero,
                  // ── Sin animación cuando la causa es una ruta ────────────
                  //
                  // La barra se esconde por dos motivos distintos y no son
                  // iguales. En Ajustes se esconde EN SU SITIO, con la pantalla
                  // quieta detrás: ahí la animación es lo que explica que se
                  // retiró, y se queda.
                  //
                  // Pero cuando se abre una pantalla encima —el reproductor, el
                  // lector, una ficha— la barra ni se ve: la tapa la propia
                  // ruta. Animarla no aporta nada y encima se nota justo en el
                  // peor momento, al cerrar: la ruta se va hacia un lado y la
                  // barra sube desde abajo por su cuenta, dos movimientos a la
                  // vez para una sola acción. Eso es lo que se sentía raro.
                  //
                  // Ahí va instantánea: cuando la ruta termina de irse, la
                  // barra ya está en su lugar.
                  duration: _sinAnimarLaBarra
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: _barraFlotante(destinations),
                ),
        ),
      ),
    );
  }

  /// ── Cuántos íconos entran en la barra ────────────────────────────────
  ///
  /// Seis: Inicio, Películas, Series, Anime, Mangas y Biblioteca — las
  /// zonas de primer nivel. Extensiones y Ajustes se van a los tres puntos
  /// junto con los atajos que antes no estaban en ningún lado: son a las
  /// que menos se entra de las ocho, y Ajustes ya tiene su atajo arriba en
  /// el Home.
  ///
  /// Riesgo a medir, no a asumir resuelto: la pastilla flotante está
  /// calibrada a ojo para 4 íconos en un ancho de teléfono típico. Con 6
  /// puede quedar apretada en un `compacto` angosto de verdad — falta
  /// probarlo en un ancho real.
  static const _enLaBarra = 6;

  /// Cuántos van arriba del todo en el riel acostado — las mismas seis que
  /// la barra de abajo, por la misma razón: son las zonas de primer nivel.
  /// Extensiones/Ajustes bajan con el resto acostado igual (ver
  /// `_barraVertical`).
  static const _enElRiel = 6;

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
  /// La pastilla estaba calibrada a ojo para 4 íconos de 46px — con las 6
  /// zonas de primer nivel que tiene ahora (Inicio+4 zonas+Biblioteca), un
  /// teléfono angosto de verdad no tenía ancho para seis círculos de ese
  /// tamaño más el botón redondo del extremo: desbordaba. Reportado en vivo
  /// con overflow.
  ///
  /// Ver el comentario largo en `_barraVertical`: acá también se probó
  /// calcular el tamaño a mano (restando márgenes/botón/relleno) y por las
  /// mismas dudas de redondeo se prefiere `FittedBox` — la pastilla se
  /// dibuja a su tamaño natural y se achica ENTERA si no entra, nunca
  /// desborda porque nunca ocupa más de lo que el padre le da.

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
              // FittedBox: la pastilla se dibuja a su tamaño natural (46px
              // por ícono) y se achica ENTERA si no entra en el ancho que
              // le tocó — ver el comentario largo más arriba.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: DecoratedBox(
                  // Traslúcida acá, no la pastilla opaca de siempre —
                  // pedido explícito: "que las cosas se vean atrás de
                  // ella, en vertical" (de pie, esta barra). Baja el alfa
                  // en vez de agregar desenfoque real (`BackdropFilter`):
                  // el de abajo hay que recalcularlo en cada cuadro
                  // mientras se hace scroll, justo encima de la grilla de
                  // portadas que más se mueve — ya se había probado y
                  // descartado por eso (ver el comentario de `_pastilla`).
                  // Bajar la opacidad no cuesta nada por cuadro y ya deja
                  // adivinarse lo que pasa por detrás.
                  decoration: _pastillaFlotante,
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
  ///
  /// ── Dos intentos de calcular el tamaño a mano, los dos se quedaron
  /// cortos ─────────────────────────────────────────────────────────────
  ///
  /// Primero se restó a mano "lo que ya ocupan los márgenes y el relleno"
  /// (`MediaQuery.sizeOf(context).height` menos una constante `reservado`).
  /// Seguía desbordando 2px en vivo. Después se cambió por el alto REAL
  /// que un `LayoutBuilder` le daba a la pastilla en ese punto exacto del
  /// árbol — en teoría no podía desincronizarse nunca, y sin embargo el
  /// mismo desborde de 2px volvió a aparecer, calcado, en un build limpio.
  /// Sin poder reproducir el dispositivo real para depurarlo más a fondo,
  /// la conclusión es que CUALQUIER cálculo a mano puede quedarse corto
  /// por una diferencia de redondeo que no se ve leyendo el código.
  ///
  /// Ver `FittedBox` más abajo: la solución final no calcula nada.
  Widget _barraVertical(List<_Destination> destinos) {
    // ── Los CUATRO lados, no solo la izquierda ────────────────────────────
    //
    // Antes solo se restaba `costados.left`, con la idea de que "la
    // izquierda cubre los dos casos: da 0 cuando el corte de la cámara
    // quedó del otro lado". Eso es falso a medias: cuando el teléfono gira
    // para el otro sentido, el corte pasa a la DERECHA, y `right` acá
    // seguía siendo un 12 fijo que no restaba nada del inset real — el
    // riel quedaba dibujado debajo de la cámara/la franja de notificaciones
    // de ese lado. Reportado en vivo con captura: "toca la zona de
    // notificaciones", "no tiene safe area". Con los cuatro lados de
    // `viewPadding` (0 en el que no tenga nada que evitar) el riel se
    // corre del inset real sea cual sea el sentido en que quedó girado.
    final costados = MediaQuery.viewPaddingOf(context);
    return Padding(
      // Aire parejo además de lo que se lleve la barra del sistema. Con 10
      // a la izquierda y 14 a la derecha los íconos quedaban corridos
      // contra el borde en vez de centrados en su franja.
      padding: EdgeInsets.fromLTRB(
        costados.left + 12,
        costados.top + 6,
        costados.right + 12,
        costados.bottom + 6,
      ),
      // ── Centrado a lo alto, explícito ─────────────────────────────────────
      //
      // Antes solo estaba el mainAxisAlignment de la columna, que centra
      // DENTRO del alto que le den. Y el alto que le daban no era el de la
      // pantalla: la barra del sistema de arriba lo corría, así que el riel
      // quedaba más cerca del borde superior que del inferior.
      //
      // Con el Center la columna se mide contra la franja entera y queda a
      // media altura de verdad, esté el aparato girado para donde esté.
      child: Center(
        // ── El riel también va en su pastilla oscura ──────────────────────
        //
        // Acostado los iconos iban sueltos sobre la página, sin nada detrás.
        // Con la app en oscuro eso pasaba porque son blancos sobre un fondo
        // oscuro; en modo claro quedaban blancos sobre casi blanco y el riel
        // desaparecía entero.
        //
        // Con la misma pastilla que la barra de abajo se resuelve y además
        // quedan iguales: acostado y de pie son la misma barra, solo que
        // girada, y no había motivo para que se vieran distintas.
        //
        // (Se probó sacarla del todo para que el contenido se viera detrás
        // — pedido mal entendido de mi parte: el pedido real era para la
        // barra de ABAJO, "en horizontal no" tocar esta. Revertido.)
        //
        // ── FittedBox, no un cálculo de tamaño a mano ─────────────────────
        //
        // Dos intentos anteriores calculaban el diámetro del ícono a mano
        // (primero con `MediaQuery.sizeOf(context).height` menos una
        // constante "reservado", después con el alto real de un
        // `LayoutBuilder`) y los DOS siguieron desbordando 2px en vivo —
        // cualquier número que se le reste a mano puede quedarse corto por
        // un pixel de diferencia entre lo que el código asume y lo que el
        // layout real de ESE teléfono puntual necesita.
        //
        // `FittedBox` no calcula nada: dibuja la pastilla a su tamaño
        // NATURAL (los íconos a 46, como en el resto de la app) y la achica
        // como una sola unidad si no entra en el alto disponible —
        // `BoxFit.scaleDown` nunca la agranda, solo la achica cuando hace
        // falta. Matemáticamente no puede desbordar: por definición nunca
        // ocupa más de lo que el padre le da.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: _pastilla,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _enElRiel; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _IconoDeBarra(
                      destino: destinos[i],
                      elegido: c.selectedTab.value == i,
                      onTap: () => _irAZona(i),
                    ),
                  ),
                // ── Acostado, el riel es SOLO esas tres ─────────────────────────
                //
                // Ni los tres puntos ni las opciones que salían de ellos. El riel
                // acostado es una columna angosta contra el borde: cuantos más
                // íconos tiene, menos se distingue a qué zona se va, y el
                // desplegable encima quedaba peor todavía —se dibujaba sobre el
                // propio riel y empujaba los botones hacia arriba—.
                //
                // Lo que queda afuera sigue teniendo por dónde: Ajustes por su
                // atajo del Home, Historial y Favoritos desde Biblioteca (sus «ver
                // más» abren esas mismas pestañas), y Extensiones desde el aviso de
                // «no tenés extensiones activas» y desde el Repositorio.
                //
                // De pie no cambia nada: barra abajo con cuatro y el resto en los
                // tres puntos, que ahí sí hacen falta porque el ancho es el que es.
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Las que no entran en la barra de abajo: Extensiones, Ajustes,
  /// Historial y Favoritos.
  ///
  /// En un solo lugar porque las usan los dos caminos: de pie salen del
  /// desplegable de los tres puntos, y acostado van directas en el riel.
  ///
  /// Extensiones se sumó acá al pasar la barra a seis zonas de contenido
  /// (Inicio+4 zonas+Biblioteca) — antes entraba en la barra misma.
  ///
  /// Buscar, primero de la lista — pedido explícito. Antes el único camino
  /// era el ícono de lupa del banner de Inicio: si no se estaba parado ahí
  /// (en una zona, en Biblioteca), no había forma de llegar al buscador
  /// general sin volver antes a Inicio.
  List<(IconData, String, VoidCallback)> _extras() => [
        (
          Icons.search_rounded,
          'common.search'.i18n,
          () => Get.to(() => const SearchPage()),
        ),
        // TV/streaming en vivo — pedido explícito de dejarla puesta, pero
        // SIN sumarle un ícono más al bottom-nav (ya viene justo de
        // espacio, ver `_barraFlotante`/`_barraVertical`): vive acá, no en
        // la barra, mientras no haya ninguna extensión real para mostrar.
        (
          Icons.live_tv_rounded,
          'home.tv-canales'.i18n,
          () => Get.to(() => const ZonaTvPage()),
        ),
        (
          Icons.extension_outlined,
          'common.extension'.i18n,
          () => _irAZona(MainController.tabExtensiones),
        ),
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
          // Su propia zona, no una pestaña del Historial: entrar a Favoritos
          // y que la pantalla dijera «Historial» arriba no tenía defensa.
          () => Get.to(() => const HistoryPage(soloFavoritos: true)),
        ),
      ];

  /// El fondo de la pastilla, igual acostado que de pie.
  /// El fondo de la pastilla de navegación.
  ///
  /// ── Oscura SIEMPRE, también en modo claro ───────────────────────────────
  ///
  /// Se probó clara —la superficie de tarjeta con su borde— y no funciona: la
  /// barra flota ENCIMA del contenido, y el contenido son portadas de
  /// cualquier color. Clara sobre una portada clara desaparece, y los iconos
  /// oscuros de adentro con ella.
  ///
  /// Oscura con los iconos en blanco se lee sobre cualquier cosa, en los dos
  /// modos, que es lo único que se le pide a una barra que flota. Es lo que
  /// hacen las barras flotantes de cualquier app, tengan el tema que tengan.
  ///
  /// Casi opaca y no con desenfoque: el desenfoque hay que recalcularlo en cada
  /// cuadro mientras uno se desplaza, y encima de una lista de portadas es
  /// justo donde no sobran milisegundos.
  static BoxDecoration get _pastilla => BoxDecoration(
        color: const Color(0xF20E0E14),
        borderRadius: BorderRadius.circular(34),
        // El aro la despega del contenido: sin él, sobre una zona oscura se
        // funde con el fondo y los iconos vuelven a verse sueltos.
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      );

  /// La misma pastilla, más traslúcida — solo para la barra flotante de
  /// ABAJO (de pie). Pedido explícito: que se adivine el contenido detrás
  /// de ella al hacer scroll. Alfa más bajo (0xB3 ≈ 70%, contra el 0xF2
  /// ≈ 95% de la de siempre) en vez de un desenfoque real: un
  /// `BackdropFilter` se recalcula en cada cuadro mientras se desplaza la
  /// grilla de portadas que tiene justo detrás, y eso ya se probó y se
  /// descartó por costoso (ver el comentario de `_pastilla`) — bajar el
  /// alfa no cuesta nada por cuadro y ya deja notarse lo que hay atrás.
  static BoxDecoration get _pastillaFlotante => BoxDecoration(
        color: const Color(0xB30E0E14),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
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

  /// Una opción del desplegable.
  ///
  /// Escalonadas: salen una atrás de otra, así se lee el recorrido en vez de
  /// aparecer las tres de golpe.
  Widget _opcion(List<(IconData, String, VoidCallback)> opciones, int i) {
    return _OpcionFlotante(
      icono: opciones[i].$1,
      texto: opciones[i].$2,
      demora: Duration(milliseconds: 60 * (opciones.length - i)),
      iconoPrimero: false,
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

  /// Si había una pantalla encima la última vez que se dibujó.
  ///
  /// Se guarda para saber POR QUÉ cambió la barra: si lo que cambió fue esto,
  /// la causa es una ruta que se abrió o se cerró y la animación sobra. Ver el
  /// comentario del AnimatedSlide.
  bool _habiaPantallaEncima = false;

  /// Si este cambio de la barra viene de una ruta y no de cambiar de zona.
  ///
  /// Se lee en `build` y actualiza el recuerdo de paso. No es un `setState`
  /// escondido: es un campo suelto que solo se usa para elegir la duración de
  /// la animación en este mismo dibujado.
  bool get _sinAnimarLaBarra {
    final ahora = ObservadorDePila.hayPantallaEncima.value;
    final porRuta = ahora != _habiaPantallaEncima;
    _habiaPantallaEncima = ahora;
    // Con una pantalla encima tampoco se anima: no se ve, está tapada.
    return porRuta || ahora;
  }

  /// Los botones que salen de los tres puntos.
  ///
  /// Flotando sobre el contenido y no en una hoja que sube desde abajo: la
  /// hoja tapa media pantalla y se lee como «entré a otro lado», cuando lo
  /// único que pasó es que la barra mostró lo que tenía guardado. Saliendo
  /// desde el propio botón, se ve de dónde vienen y a qué vuelven.
  Widget _capaDeMas() {
    final bordes = MediaQuery.viewPaddingOf(context);
    final opciones = _extras();

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
          // Solo de pie: acostado no hay botón que abra esto (ver
          // _barraVertical), así que no hace falta la variante horizontal —
          // la había, y era código que no se ejecutaba nunca.
          Positioned(
            right: 18,
            bottom: (bordes.bottom > 0 ? bordes.bottom * 0.55 + 14 : 20) + 66,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < opciones.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _opcion(opciones, i),
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
    // ── Las zonas se rehacen SOLO al cambiar el modo ─────────────────────
    //
    // Objetos nuevos es lo único que obliga a Flutter a bajar al subárbol de
    // cada pestaña (ver [_zonas]). Fuera de eso se reusan los de antes, así que
    // cambiar de pestaña sigue costando lo mismo que costaba.
    //
    // Es un campo suelto que se toca durante el dibujado, como
    // `_habiaPantallaEncima` acá abajo: no dispara ningún redibujado por su
    // cuenta —el del cambio de modo ya viene bajando desde la raíz— así que no
    // es un setState escondido.
    if (_modoDeLasZonas != ModoDeColor.claro) {
      _modoDeLasZonas = ModoDeColor.claro;
      _zonas = _crearZonas();
    }
    final zonas = _zonas;
    return IndexedStack(
      index: c.selectedTab.value,
      children: [
        for (var i = 0; i < zonas.length; i++)
          RepaintBoundary(
            // ── Sin un FocusScope por zona ──────────────────────────────
            //
            // Se probó darle a cada zona su propio ámbito (para que
            // recordara en qué tarjeta estabas al volver) y salió mucho
            // peor: al volver de Extensiones el foco quedaba en un ámbito
            // apagado y la app se congelaba del todo — había que cerrarla.
            //
            // Que el foco vuelva donde estaba se resuelve en el observador
            // de navegación (ver _devolverElFoco), que es donde de verdad se
            // sabe que una pantalla se cerró.
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
              child: zonas[i],
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

  // El lado del botón — 46 siempre. Que la pastilla entera entre en la
  // pantalla (aunque tenga 6 destinos) ya no es cosa de este número: lo
  // resuelve el `FittedBox` que envuelve la pastilla en
  // `_barraFlotante`/`_barraVertical`, achicando el conjunto entero si
  // hace falta en vez de calcular un tamaño por ícono a mano.
  static const _tamano = 46.0;

  @override
  Widget build(BuildContext context) {
    final acento = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: elegido,
      label: destino.label,
      child: InkResponse(
        onTap: onTap,
        radius: _tamano * 0.57,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: _tamano,
          height: _tamano,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: elegido ? acento.withValues(alpha: 0.3) : Colors.transparent,
          ),
          child: Icon(
            elegido ? destino.selectedIcon : destino.icon,
            // Sigue al botón, para que la proporción sea la misma en los dos.
            size: _tamano * 0.5,
            // La pastilla es oscura en los dos modos (ver _pastilla), así
            // que sus iconos van en blanco siempre. Con el color del tema se
            // volvían casi negros en claro: iconos negros sobre negro.
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
          // Mismo caso: fondo oscuro fijo, icono blanco fijo.
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
          // La etiqueta va sobre una pastilla oscura: blanca siempre. Con el
          // color del tema quedaba negra sobre negro y las tres opciones
          // —Ajustes, Historial, Favoritos— se veían como cajas vacías.
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

/// La versión instalada, en una pastilla chica que dice «beta».
///
/// ── Por qué a la vista y no escondida en Ajustes ────────────────────────
///
/// Porque el app todavía es beta y se publica seguido: saber qué versión se
/// está usando es lo primero que hace falta para reportar algo, y hasta ahora
/// había que ir a buscarla adentro de Ajustes.
///
/// Va ABAJO y chica a propósito: es un dato de referencia, no algo que haya que
/// leer todo el tiempo. Arriba, al lado del nombre, competía con el título.
///
/// La misma pieza en las dos plataformas: en escritorio al pie del riel, en el
/// teléfono al pie de Ajustes.
///
/// En compilaciones de prueba suma su distintivo (`dev`, `debug`), que ya
/// resuelve [ModoApp.versionConModo] — así se distingue la copia instalada de
/// la de pruebas, que conviven en el mismo equipo.
class DistintivoDeVersion extends StatelessWidget {
  const DistintivoDeVersion({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        // Apenas teñida con el acento: se lee como una etiqueta y no como un
        // botón. Un relleno macizo acá abajo llamaría más la atención que el
        // contenido.
        color: HomeTheme.accentPink.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.32)),
      ),
      child: Text(
        // La versión sale del paquete instalado, no de una constante escrita a
        // mano: así no se puede desincronizar de lo que el usuario tiene.
        'beta · ${ModoApp.versionConModo(packageInfo.version)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: HomeTheme.accentPink,
        ),
      ),
    );
  }
}
