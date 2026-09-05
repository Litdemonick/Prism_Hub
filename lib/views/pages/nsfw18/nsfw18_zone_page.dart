import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/resume_history.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_lock_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_search_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_zone_page_tv.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/dialogs/import_dialog.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_hero_banner.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_section.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

// Card ancha estilo Crunchyroll: solo en escritorio (Windows/Linux). En
// Android se mantiene la vertical, que es la que entra bien en pantallas
// chicas tanto en vertical como en horizontal.
// La ancha va en las dos plataformas, igual que en la Biblioteca: es un marco
// 16:9 para una captura 16:9. Ver el comentario en library_page.dart.
const bool _wideCards = true;

// true en horizontal de celular, donde el alto útil es ~300-390 y cada bloque
// de aire vertical se nota muchísimo más que en vertical o en escritorio.
bool _tightTop(BuildContext context) =>
    Platform.isAndroid &&
    MediaQuery.orientationOf(context) == Orientation.landscape;

void _goBackFromZone(String? from) {
  if (Platform.isAndroid) {
    // Android llega acá con Get.to (push encima del shell principal) — un
    // pop simple ya vuelve exactamente a donde estaba, sin necesitar "from".
    Get.back();
  } else {
    // Desktop: router.go() REEMPLAZA todo el stack de rutas (no hay un
    // "anterior" que hacer pop) — sin esto, cancelar/decir "no entrar"
    // siempre mandaba a Home sin importar desde dónde se entró a la Zona
    // +18 (ej. desde Ajustes). "from" viaja como query param desde el
    // único lugar que navega acá (main_page.dart), con la ruta que estaba
    // activa justo antes de tocar "Zona +18" en el panel.
    router.go((from != null && from.isNotEmpty) ? from : '/');
  }
}

// Punto de entrada real de la Zona +18:
// 1. El switch de NSFW en Ajustes tiene que estar prendido — si no, ni
//    siquiera llega a pedir el PIN (ver _Nsfw18DisabledPage).
// 2. Confirmación "¿estás seguro?" — SIEMPRE, cada vez que se entra (no
//    solo la primera), independiente del PIN.
// 3. PIN (o configurarlo la primera vez) — SIEMPRE también, cada vez que se
//    entra. Antes se recordaba el desbloqueo mientras la app siguiera abierta;
//    se quitó a propósito (ver Nsfw18Zone), porque dejaba la zona accesible sin
//    PIN a quien agarrara el dispositivo después.
class Nsfw18ZoneGate extends StatefulWidget {
  const Nsfw18ZoneGate({super.key, this.from});
  // Desktop: ruta que estaba activa antes de entrar a la Zona +18 (ver
  // main_page.dart) — a dónde volver si se cancela/dice "no entrar".
  final String? from;

  @override
  State<Nsfw18ZoneGate> createState() => _Nsfw18ZoneGateState();
}

class _Nsfw18ZoneGateState extends State<Nsfw18ZoneGate> {
  // Arranca SIEMPRE bloqueado — el PIN se pide en cada entrada (ver el
  // comentario de la clase y Nsfw18Zone).
  bool _unlocked = false;
  bool _confirmed = false;
  bool _askedConfirm = false;

  bool get _nsfwEnabled =>
      PrismHubStorage.getSetting(SettingKey.enableNSFW) == true;

  @override
  void initState() {
    super.initState();
    if (_nsfwEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirmEnter());
    }
  }

  Future<void> _confirmEnter() async {
    if (_askedConfirm || !mounted) return;
    _askedConfirm = true;
    final result = await showPlatformDialog(
      context: context,
      title: 'nsfw18.confirm-enter-title'.i18n,
      content: Text('nsfw18.confirm-enter-content'.i18n),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('nsfw18.confirm-enter-yes'.i18n),
        ),
      ],
    );
    if (!mounted) return;
    if (result == true) {
      setState(() => _confirmed = true);
    } else {
      _goBackFromZone(widget.from);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_nsfwEnabled) {
      return const _Nsfw18DisabledPage();
    }
    if (!_confirmed) {
      return Scaffold(
          backgroundColor: HomeTheme.bg, body: const SizedBox.shrink());
    }
    if (!_unlocked) {
      return Nsfw18LockPage(
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }
    // TV: pantalla propia, sin nada del diseño de Android/escritorio — ver
    // el comentario largo de Nsfw18ZonePageTv.
    if (PlatformTv.esTelevisionSync) return const Nsfw18ZonePageTv();
    return const Nsfw18ZonePage();
  }
}

// El switch de NSFW en Ajustes está apagado — no se deja ni pedir el PIN.
// Mismo criterio que activar una extensión nsfw (ExtensionTile): sin el
// switch prendido, no hay forma de entrar.
class _Nsfw18DisabledPage extends StatelessWidget {
  const _Nsfw18DisabledPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        iconTheme: IconThemeData(color: HomeTheme.textPrimary),
        title: Text(
          'nsfw18.title'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, color: HomeTheme.textMuted, size: 40),
                const SizedBox(height: 16),
                Text(
                  'nsfw18.disabled-title'.i18n,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HomeTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'nsfw18.disabled-subtitle'.i18n,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (Platform.isAndroid) {
                        // Antes solo hacía Get.back(): el botón dice "Ir a
                        // Ajustes" pero en Android dejaba al usuario donde
                        // estaba, sin llevarlo a ningún lado (reportado en
                        // vivo). La Zona +18 se llega empujada ENCIMA del
                        // shell principal (Get.to), así que hay que cambiar la
                        // pestaña Y cerrar esta pantalla.
                        //
                        // La pestaña PRIMERO y el pop después: al revés hay una
                        // carrera con la animación del pop y el cambio no se
                        // llega a aplicar (mismo caso que "Explorar catálogo",
                        // confirmado en vivo). El isRegistered es para que el
                        // pop pase igual si el controller no estuviera.
                        if (Get.isRegistered<MainController>()) {
                          Get.find<MainController>()
                              .changeTab(MainController.tabAjustes);
                        }
                        // Mismo criterio que "Explorar catálogo": hasta el
                        // shell, no una sola capa (ver el comentario ahí).
                        Get.until((route) => route.isFirst);
                      } else {
                        router.go('/settings');
                      }
                    },
                    child: Text('nsfw18.disabled-cta'.i18n),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Mismo layout que HomePage (hero + Continuar + Favoritos), con tema rojo
// en vez de rosa/violeta, y mostrando SOLO lo marcado +18 (ver
// HomePageController.nsfwOnly). Reusa los mismos widgets de Home en vez de
// duplicar el layout entero.
class Nsfw18ZonePage extends StatefulWidget {
  const Nsfw18ZonePage({super.key});

  @override
  State<Nsfw18ZonePage> createState() => _Nsfw18ZonePageState();
}

class _Nsfw18ZonePageState extends State<Nsfw18ZonePage> {
  // Destino del "Ver todo" de cada seccion, en el orden de pestanas de
  // HistoryPage: Todo, Video, Lectura, Fav. Video, Fav. Lectura. Antes todas
  // las secciones abrian la misma pestana, asi que tocar "Continuar leyendo"
  // caia en "Todo" y los dos bloques de Favoritos caian en "Fav. Video".
  static const _tabVideo = 1;
  static const _tabLectura = 2;
  static const _tabFavVideo = 3;
  static const _tabFavLectura = 4;

  late final HomePageController c =
      Get.isRegistered<HomePageController>(tag: HomePageController.zoneTag)
          ? Get.find<HomePageController>(tag: HomePageController.zoneTag)
          : Get.put(
              HomePageController(nsfwOnly: true),
              tag: HomePageController.zoneTag,
            );

  // cover/headers: la portada que la tarjeta ya está mostrando, para que la
  // ficha abra con imagen. Ver PortadaAdelantada.
  void _openDetail(String url, String package,
      {String? cover, Map<String, String>? headers}) {
    ExtensionUtils.openExtensionDetail(
      context,
      package: package,
      url: url,
      cover: cover,
      coverHeaders: headers,
    );
  }

  /// Marca como visto lo que está en curso y avisa a dónde quedó — mismo
  /// criterio que en Biblioteca, ver el comentario largo allá.
  Future<void> _marcarVisto(BuildContext context, History h) async {
    final resultado = await c.marcarVistoYPasarAlSiguiente(h);
    if (!context.mounted) return;
    final String mensaje;
    if (resultado == null) {
      mensaje = 'home.mark-watched-fail'.i18n;
    } else if (resultado.isEmpty) {
      mensaje = 'home.mark-watched-done'.i18n;
    } else {
      mensaje = FlutterI18n.translate(
        context,
        'home.mark-watched-next',
        translationParams: {'ep': resultado},
      );
    }
    showPlatformSnackbar(context: context, content: mensaje);
  }

  void _openHistoryTab(int tab) {
    if (Platform.isAndroid) {
      // Las pestañas 3 y 4 son favoritos, y eso es SU zona, no una
      // pestaña del Historial. Ver HistoryPage.soloFavoritos.
      Get.to(HistoryPage(
        initialTab: tab,
        zone: true,
        soloFavoritos: tab >= 3,
      ));
      return;
    }
    router.push(
      Uri(
        path: '/history',
        queryParameters: {'tab': tab.toString(), 'zone': '1'},
      ).toString(),
    );
  }

  // "Continuar" partido en dos: los vídeos con la card ancha 16:9 (que es la
  // forma real de sus capturas) y la lectura con la card vertical, donde un
  // póster entra entero sin recortar ni dejar franjas. Mezclados en una sola
  // fila era imposible: la fila reserva UN alto y una forma, así que uno de
  // los dos tipos siempre quedaba mal.

  // Favoritos con el mismo criterio que "Continuar": vídeo en la card ancha
  // 16:9 y lectura en la vertical, cada uno con la forma que le corresponde.
  // Mezclados, la fila reserva un solo alto y una sola forma, así que uno de
  // los dos tipos siempre quedaba recortado o con franjas.
  List<Widget> _favoritosSecciones(BuildContext context) {
    final videos = c.favorites
        .where((f) => f.type == ExtensionType.bangumi)
        .toList(growable: false);
    final lectura = c.favorites
        .where((f) => f.type != ExtensionType.bangumi)
        .toList(growable: false);

    Widget seccion({
      required String titulo,
      required List<Favorite> items,
      required bool ancha,
      required int tab,
    }) {
      return HomeSection(
        itemWidth: ancha ? HomeMediaCard.anchoAncha : null,
        itemHeight: ancha ? HomeMediaCard.altoTotalAncha : null,
        itemCoverHeight: ancha ? HomeMediaCard.altoImagenAncha : null,
        // Sin caja alrededor de la sección.
        //
        // Era un panel apenas más claro que el fondo con su borde, y con dos o
        // tres secciones seguidas la pantalla quedaba llena de recuadros
        // anidados: el recuadro de la sección, adentro el de cada tarjeta, y
        // dentro de ese la portada. El título de la sección y el aire entre
        // una y otra ya alcanzan para separarlas, y sin la caja las portadas
        // ganan el ancho que se llevaba su relleno.
        boxed: false,
        accent: HomeTheme.accentRed,
        title: titulo,
        onClickMore: () => _openHistoryTab(tab),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final f = items[index];
          // Obx por tarjeta: ver el mismo comentario en _continuarSecciones.
          return Obx(() => HomeMediaCard(
                key: ValueKey('fav-${f.package}|${f.url}'),
                horizontal: ancha,
                // El tipo lo dice el título de la sección.
                type: null,
                title: f.title,
                subtitle: 'home.favorite'.i18n,
                extensionName:
                    ExtensionUtils.runtimes[f.package]?.extension.name,
                cover: f.cover,
                headers: c.headersForPackage(f.package),
                onTap: () => _openDetail(f.url, f.package,
                    cover: f.cover, headers: c.headersForPackage(f.package)),
                onDelete: () => c.deleteFavorite(f),
                onVerDetalle: () => _openDetail(f.url, f.package,
                    cover: f.cover, headers: c.headersForPackage(f.package)),
                hidden: HiddenCards.isHidden(f.package, f.url),
                onToggleHide: () => HiddenCards.toggle(f.package, f.url),
                accent: HomeTheme.accentRed,
              ));
        },
      );
    }

    return [
      if (videos.isNotEmpty) ...[
        seccion(
          titulo: 'home.favorite-video'.i18n,
          tab: _tabFavVideo,
          items: videos,
          ancha: _wideCards,
        ),
        const SizedBox(height: 32),
      ],
      if (lectura.isNotEmpty) ...[
        seccion(
          titulo: 'home.favorite-reading'.i18n,
          tab: _tabFavLectura,
          items: lectura,
          ancha: false,
        ),
        const SizedBox(height: 32),
      ],
    ];
  }

  List<Widget> _continuarSecciones(BuildContext context) {
    final videos = c.resents
        .where((h) => h.type == ExtensionType.bangumi)
        .toList(growable: false);
    final lectura = c.resents
        .where((h) => h.type != ExtensionType.bangumi)
        .toList(growable: false);

    Widget seccion({
      required String titulo,
      required List<History> items,
      required bool ancha,
      required int tab,
    }) {
      return HomeSection(
        // La ancha usa su propio tamaño; la vertical deja los valores por
        // defecto, que ya se adaptan a cada plataforma y orientación.
        itemWidth: ancha ? HomeMediaCard.anchoAncha : null,
        itemHeight: ancha ? HomeMediaCard.altoTotalAncha : null,
        itemCoverHeight: ancha ? HomeMediaCard.altoImagenAncha : null,
        // Sin caja alrededor de la sección.
        //
        // Era un panel apenas más claro que el fondo con su borde, y con dos o
        // tres secciones seguidas la pantalla quedaba llena de recuadros
        // anidados: el recuadro de la sección, adentro el de cada tarjeta, y
        // dentro de ese la portada. El título de la sección y el aire entre
        // una y otra ya alcanzan para separarlas, y sin la caja las portadas
        // ganan el ancho que se llevaba su relleno.
        boxed: false,
        accent: HomeTheme.accentRed,
        title: titulo,
        onClickMore: () => _openHistoryTab(tab),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final h = items[index];
          // Obx propio por tarjeta — ListView.builder arma cada ítem de forma
          // perezosa, FUERA del alcance del Obx que envuelve la página, así
          // que sin esto togglear "ocultar" no refrescaba la tarjeta.
          final isVideo = h.type == ExtensionType.bangumi;
          // Ver PortadaHistorial: el mismo campo `cover` puede traer una
          // captura local del frame o el poster de red.
          final portada = PortadaHistorial.de(h);
          return Obx(() => HomeMediaCard(
                horizontal: ancha,
                // El tipo ya lo dice el título de la sección: repetirlo en
                // cada tarjeta era ruido.
                type: null,
                title: h.title,
                subtitle: FlutterI18n.translate(
                  context,
                  isVideo ? 'home.watched-episode' : 'home.watched-chapter',
                  translationParams: {
                    'ep': ExtensionUtils.episodeNumberLabel(
                      h.episodeTitle,
                      h.episodeId,
                    ),
                  },
                ),
                extensionName:
                    ExtensionUtils.runtimes[h.package]?.extension.name,
                // El historial de VÍDEO guarda una captura LOCAL como portada
                // (no una URL de red) — tratarla como red siempre fallaba.
                cover: portada.url,
                coverFile: portada.archivo,
                headers: portada.necesitaHeaders
                    ? c.headersForPackage(h.package)
                    : null,
                newEpisodeLabel: h.newEpisodeLabel,
                onTap: () => resumeHistoryItem(context, h),
                // No borra: saca el ítem de Continuar marcándolo visto. El
                // borrado real vive en el Historial, que es donde uno
                // administra el archivo.
                onDelete: () => c.quitarDeContinuar(h),
                deleteLabel: 'home.remove-from-continue'.i18n,
                // Mismo criterio que en Biblioteca: dar por visto lo actual
                // y pasar al que sigue sin abrirlo.
                extraActionLabel: 'home.mark-watched'.i18n,
                extraActionIcon: Icons.done_all_rounded,
                onExtraAction: () => _marcarVisto(context, h),
                // Solo si la portada es de red: el historial de vídeo guarda
                // una captura en disco, y eso no se puede pedir por URL.
                onVerDetalle: () => _openDetail(h.url, h.package,
                    cover: portada.archivo == null ? portada.url : null,
                    headers: portada.necesitaHeaders
                        ? c.headersForPackage(h.package)
                        : null),
                hidden: HiddenCards.isHidden(h.package, h.url),
                onToggleHide: () => HiddenCards.toggle(h.package, h.url),
                accent: HomeTheme.accentRed,
              ));
        },
      );
    }

    return [
      if (videos.isNotEmpty) ...[
        seccion(
          titulo: 'home.continue-video'.i18n,
          tab: _tabVideo,
          items: videos,
          // La card ancha es solo de escritorio; en celular no entra.
          ancha: _wideCards,
        ),
        const SizedBox(height: 32),
      ],
      if (lectura.isNotEmpty) ...[
        seccion(
          titulo: 'home.continue-reading'.i18n,
          tab: _tabLectura,
          items: lectura,
          // Lectura SIEMPRE vertical: es la forma de un póster.
          ancha: false,
        ),
        const SizedBox(height: 32),
      ],
    ];
  }

  /// [conCabecera] agrega arriba el título de la zona con sus dos atajos.
  ///
  /// Solo en escritorio. En el teléfono eso ya lo pone la barra del Scaffold
  /// (ver `_buildAndroid`), y ponerlo dos veces daría el título repetido.
  Widget _buildContent({bool conCabecera = false}) {
    return Obx(
      () {
        final isEmpty = c.resents.isEmpty && c.favorites.isEmpty;
        return Container(
          color: HomeTheme.bg,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBackgroundGlow(accent: HomeTheme.accentRed),
              ),
              LayoutBuilder(
                builder: (context, outerConstraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: outerConstraints.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── La cabecera, igual que en Biblioteca ────────
                            //
                            // En escritorio esta zona no tenía título y sus dos
                            // atajos flotaban en una pastilla ENCIMA del
                            // contenido, pegados al borde. Al lado de
                            // Biblioteca —que tiene su título con los iconos
                            // alineados y el banner dentro de su caja— se veía
                            // como otra pantalla, hecha por otro.
                            //
                            // Misma estructura que allá: título a la izquierda,
                            // atajos a la derecha, y debajo el banner.
                            if (conCabecera) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'nsfw18.title'.i18n,
                                        style: HomeTheme.tituloDeZona(),
                                      ),
                                    ),
                                    // El buscador de esta zona ya NO tiene
                                    // un botón propio acá — pedido explícito:
                                    // con la lupa de la barra superior de
                                    // Fluent (main_page.dart) detectando sola
                                    // que se está en '/adult-zone' y abriendo
                                    // openNsfw18Search en vez de la búsqueda
                                    // general, tener las dos lupas a la vez
                                    // en pantalla era mostrar dos caminos
                                    // distintos a lo mismo.
                                    if (!PlatformTv.esTelevisionSync)
                                      IconButton(
                                        tooltip: 'import.title'.i18n,
                                        onPressed: () async {
                                          await showImportDialog(context);
                                          c.onRefresh();
                                        },
                                        icon: Icon(
                                          Icons.playlist_add_rounded,
                                          color: HomeTheme.textPrimary,
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: 'home.favorite'.i18n,
                                      onPressed: _favoritos,
                                      icon: Icon(
                                        Icons.favorite_border_rounded,
                                        color: HomeTheme.textPrimary,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'home.history'.i18n,
                                      onPressed: () => _openHistoryTab(0),
                                      icon: Icon(
                                        Icons.history_rounded,
                                        color: HomeTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Obx(() => HomeHeroBanner(
                                  background: c.heroBackground.value,
                                  gradient: HomeTheme.heroGradientRed,
                                  // "Explorar" muestra el CATÁLOGO +18
                                  // completo en cards, como las demás zonas
                                  // — no el buscador (ese es para escribir
                                  // algo puntual, y tiene su propia entrada).
                                  // Ver el comentario largo en
                                  // openNsfw18Catalog.
                                  //
                                  // Se apila ENCIMA de esta pantalla, así que
                                  // volver atrás cae siempre en el home +18,
                                  // sin importar desde dónde se haya entrado.
                                  onExploreCatalog: () =>
                                      openNsfw18Catalog(context),
                                )),
                            // El aire entre el hero y la primera fila se
                            // achica en horizontal de celular: ahí el alto
                            // total es ~300-390 y 32px de hueco eran una
                            // porción visible de la pantalla.
                            SizedBox(height: _tightTop(context) ? 14 : 32),
                            if (isEmpty)
                              SizedBox(
                                // El piso tiene que ser AL MENOS el
                                // `minHeight: 320` que `_Nsfw18EmptyState`
                                // ya se pide a sí misma — mismo bug y mismo
                                // arreglo que en `library_page.dart`
                                // (`_BibliotecaVacia`), reportado en vivo
                                // acá también con captura ("BOTTOM
                                // OVERFLOWED BY 28 PIXELS" en tablet
                                // acostada).
                                height:
                                    (outerConstraints.maxHeight - 32 - 32 - 220)
                                        .clamp(320.0, double.infinity),
                                child: const _Nsfw18EmptyState(),
                              ),
                            ..._continuarSecciones(context),
                            ..._favoritosSecciones(context),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Los favoritos DE ESTA ZONA.
  ///
  /// Con `zone: true`, que es lo que hace que mire la otra instancia del
  /// controlador. Sin eso se abrían los favoritos normales, o sea que lo
  /// guardado acá no tenía dónde verse junto y aparecía mezclado del otro lado.
  void _favoritos() {
    if (Platform.isAndroid) {
      Get.to(const HistoryPage(soloFavoritos: true, zone: true));
      return;
    }
    router.push(
      Uri(path: '/history', queryParameters: {'tab': '5', 'zone': '1'})
          .toString(),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'nsfw18.title'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
        actions: [
          // En Android no hay ninguna lupa general que llegue hasta acá
          // (esta pantalla se empuja ENCIMA del shell, así que ni el menú
          // de los "..." ni el buscador del Inicio son alcanzables desde
          // adentro) — a diferencia de PC, donde la barra superior de
          // Fluent SÍ llega a todos lados y ya detecta sola esta zona (ver
          // main_page.dart). Sin esta, no había ningún camino a buscar algo
          // puntual desde adentro — reportado en vivo: "no veo el search
          // adentro de la zona +18".
          if (!PlatformTv.esTelevisionSync)
            IconButton(
              tooltip: 'import.title'.i18n,
              onPressed: () async {
                await showImportDialog(context);
                c.onRefresh();
              },
              icon: Icon(Icons.playlist_add_rounded,
                  color: HomeTheme.textPrimary),
            ),
          IconButton(
            tooltip: 'nsfw18.search-zone-title'.i18n,
            onPressed: () => openNsfw18Search(context, yaAutorizado: true),
            icon: Icon(Icons.search_rounded, color: HomeTheme.textPrimary),
          ),
          IconButton(
            tooltip: 'home.favorite'.i18n,
            onPressed: _favoritos,
            icon: Icon(Icons.favorite_border_rounded,
                color: HomeTheme.textPrimary),
          ),
          // Y el historial DE ESTA ZONA al lado, con el mismo criterio.
          IconButton(
            tooltip: 'home.history'.i18n,
            onPressed: () => _openHistoryTab(0),
            icon: Icon(Icons.history_rounded, color: HomeTheme.textPrimary),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => c.onRefresh(),
        color: HomeTheme.accentRed,
        backgroundColor: HomeTheme.cardSurface,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    // ── Los atajos también en escritorio ──────────────────────────────────
    //
    // En Android van en la barra de arriba de esta zona; acá no había barra, y
    // los favoritos y el historial DE ESTA ZONA se quedaron sin puerta: había
    // que abrir los de la zona normal y no estaban ahí, porque cada una guarda
    // los suyos.
    //
    // Flotan arriba a la derecha, sobre el contenido, en vez de meter una barra
    // entera por dos botones.
    // Sin la pastilla flotante: los dos atajos pasaron a la cabecera, alineados
    // con el título, como en Biblioteca. Ver `_buildContent(conCabecera: true)`.
    return _buildContent(conCabecera: true);
  }

  /// La Zona +18 en televisor.
  ///
  /// ── Por qué no sirve la de Android ──────────────────────────────────────
  ///
  /// La de Android usa una `AppBar` con tres botones de icono. Con un mando eso
  /// es un problema doble: son blancos chicos pensados para el dedo, y ninguno
  /// lleva el marco de foco de la app —son `IconButton` de Material— así que al
  /// llegar arriba con el mando no se ve dónde se está parado.
  ///
  /// Acá la cabecera es una fila de botones grandes con su nombre escrito al
  /// lado del icono: desde el sillón se lee qué hace cada uno sin adivinar por
  /// el dibujo, y cada uno se enfoca con el mismo marco rojo que usa el resto
  /// de esta zona.
  ///
  /// Y sin `AppBar`: dibuja su propia superficie con elevación, y sobre el
  /// fondo de la zona eso se ve como una franja despareja cruzando la pantalla.
  Widget _buildTv(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Padding(
          // El mismo margen que el resto del televisor: entero a los costados
          // y un tercio arriba y abajo, para no regalar el alto de una fila.
          padding: HomeTheme.margenTv(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'nsfw18.title'.i18n,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: HomeTheme.textPrimary,
                      ),
                    ),
                  ),
                  _BotonTvZona(
                    icono: Icons.search_rounded,
                    texto: 'nsfw18.search-zone-title'.i18n,
                    onTap: () => openNsfw18Search(context, yaAutorizado: true),
                  ),
                  const SizedBox(width: 12),
                  _BotonTvZona(
                    icono: Icons.favorite_border_rounded,
                    texto: 'home.favorite'.i18n,
                    onTap: _favoritos,
                  ),
                  const SizedBox(width: 12),
                  _BotonTvZona(
                    icono: Icons.history_rounded,
                    texto: 'home.history'.i18n,
                    onTap: () => _openHistoryTab(0),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformTv.esTelevisionSync) return _buildTv(context);
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}

/// Un botón de la cabecera de la Zona en televisor: icono + nombre.
///
/// Con el nombre escrito y no solo el dibujo: desde tres metros, tres iconos
/// seguidos son tres manchas: hay que acercarse para saber cuál es cuál. Y con
/// el marco de foco de la app, que es lo que le faltaba a los `IconButton`.
class _BotonTvZona extends StatelessWidget {
  const _BotonTvZona({
    required this.icono,
    required this.texto,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      borderRadius: 999,
      accent: HomeTheme.accentRed,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HomeTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 22, color: HomeTheme.textPrimary),
            const SizedBox(width: 10),
            Text(
              texto,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: HomeTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _abrirHistorialZona(BuildContext context) {
  // zone: true — el Historial de la Zona +18, no el general.
  if (Platform.isAndroid) {
    Get.to(() => const HistoryPage(zone: true));
    return;
  }
  // La ruta es '/history' con zone=1, la MISMA que usa _openHistoryTab: no
  // existe ninguna '/nsfw18/...' declarada en el router. Escrita así, go_router
  // no encontraba la ruta y mostraba "Page Not Found" en vez del Historial.
  router.push(
    Uri(path: '/history', queryParameters: {'zone': '1'}).toString(),
  );
}

/// Botón al Historial cuando la zona está vacía. Ver el mismo widget en
/// library_page.dart: se repite acá porque los dos son privados de su archivo y
/// compartirlo obligaría a exponerlo solo por esto.
class _VerHistorialBoton extends StatelessWidget {
  const _VerHistorialBoton({required this.accent, required this.onTap});
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 17, color: accent),
              const SizedBox(width: 8),
              Text(
                'home.see-history'.i18n,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Nsfw18EmptyState extends StatefulWidget {
  const _Nsfw18EmptyState();

  @override
  State<_Nsfw18EmptyState> createState() => _Nsfw18EmptyStateState();
}

class _Nsfw18EmptyStateState extends State<_Nsfw18EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);
  late final Animation<double> _pulse = Tween<double>(begin: 0.5, end: 1.0)
      .animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 12),
          child: child,
        ),
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 320),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HomeTheme.textMuted.withValues(alpha: 0.3)),
          color: HomeTheme.cardSurface.withValues(alpha: 0.4),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _pulse,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: HomeTheme.accentRed.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    color: HomeTheme.accentRed,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'nsfw18.no-record'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(color: HomeTheme.textMuted, fontSize: 13.5),
              ),
              const SizedBox(height: 18),
              // Mismo botón que el Home normal, con el acento de esta zona y
              // llevando al Historial +18, no al general.
              _VerHistorialBoton(
                accent: HomeTheme.accentRed,
                onTap: () => _abrirHistorialZona(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
