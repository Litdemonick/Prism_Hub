import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/resume_history.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_hero_banner.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_section.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

// Card ancha estilo Crunchyroll: solo en escritorio (Windows/Linux). En
// Android se mantiene la vertical, que es la que entra bien en pantallas
// chicas tanto en vertical como en horizontal.
// ── La ancha va en las DOS plataformas ──────────────────────────────────
//
// Era solo de escritorio, y en Android «Continuar viendo» usaba la vertical:
// un marco de póster para una captura de vídeo. La captura es 16:9, así que
// entraba recortada por los costados —se perdía media escena— o con franjas.
// Justo lo que esta tarjeta vino a resolver.
//
// El tamaño del teléfono lo pone HomeMediaCard.anchoAncha, que ya distingue
// plataforma: los mismos 16:9, más chicos.
const bool _wideCards = true;

// true en horizontal de celular, donde el alto útil es ~300-390 y cada bloque
// de aire vertical se nota muchísimo más que en vertical o en escritorio.
bool _tightTop(BuildContext context) =>
    Platform.isAndroid &&
    MediaQuery.of(context).orientation == Orientation.landscape;

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late HomePageController c;

  // Índice de la pestaña "Favoritos" en HistoryPage — bajó de 4 a 3 al
  // fusionar las pestañas Manga+Novela en una sola ("Lectura").

  // Destino del "Ver todo" de cada seccion, en el orden de pestanas de
  // HistoryPage: Todo, Video, Lectura, Fav. Video, Fav. Lectura. Antes todas
  // las secciones abrian la misma pestana, asi que tocar "Continuar leyendo"
  // caia en "Todo" y los dos bloques de Favoritos caian en "Fav. Video".
  static const _tabVideo = 1;
  static const _tabLectura = 2;
  static const _tabFavVideo = 3;
  static const _tabFavLectura = 4;

  @override
  void initState() {
    // Reusa el controller si ya existe — en Android, cambiar de pestaña de
    // la barra inferior destruye y reconstruye HomePage entero (pages[i],
    // no un IndexedStack), así que Get.put() de nuevo creaba un controller
    // NUEVO cada vez que volvías a Home, tirando a la basura el hero ya
    // cargado y obligando a esperar de nuevo el fetch de red (por eso
    // parecía que hacía falta refrescar a mano para que apareciera algo).
    c = Get.isRegistered<HomePageController>()
        ? Get.find<HomePageController>()
        : Get.put(HomePageController());
    super.initState();
  }

  // cover/headers: la portada que la tarjeta ya está mostrando. Se pasa para
  // que la ficha abra con imagen en vez de con un hueco mientras la extensión
  // contesta. Ver PortadaAdelantada.
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

  /// Todos los favoritos, en su zona.
  void _favoritos() {
    if (Platform.isAndroid) {
      Get.to(const HistoryPage(soloFavoritos: true));
      return;
    }
    // En escritorio la navegación va por rutas, no por Get.to: usar Get.to acá
    // empuja una pantalla que el shell no dibuja.
    router.push(
      Uri(path: '/history', queryParameters: {'tab': '5'}).toString(),
    );
  }

  void _openHistoryTab(int tab) {
    if (Platform.isAndroid) {
      // Las pestañas 3 y 4 son favoritos, y eso es SU zona, no una
      // pestaña del Historial. Ver HistoryPage.soloFavoritos.
      Get.to(HistoryPage(initialTab: tab, soloFavoritos: tab >= 3));
      return;
    }
    router.push(
      Uri(path: '/history', queryParameters: {'tab': tab.toString()})
          .toString(),
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
        accent: HomeTheme.accentPink,
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
                accent: HomeTheme.accentPink,
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
        accent: HomeTheme.accentPink,
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
                // Solo si la portada es de red: el historial de vídeo guarda
                // una captura en disco, y eso no se puede volver a pedir por
                // URL desde la ficha.
                onVerDetalle: () => _openDetail(h.url, h.package,
                    cover: portada.archivo == null ? portada.url : null,
                    headers: portada.necesitaHeaders
                        ? c.headersForPackage(h.package)
                        : null),
                hidden: HiddenCards.isHidden(h.package, h.url),
                onToggleHide: () => HiddenCards.toggle(h.package, h.url),
                accent: HomeTheme.accentPink,
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

  Widget _buildContent() {
    return Obx(
      () {
        final isEmpty = c.resents.isEmpty && c.favorites.isEmpty;
        // OJO: heroBackground NO se lee acá a propósito. Antes sí, y como
        // este Obx envuelve TODO Home, la rotación del banner (cada 20s)
        // reconstruía el árbol entero — todas las secciones y tarjetas —
        // solo para cambiar una imagen de fondo. Ahora el banner tiene su
        // propio Obx (más abajo), así que la rotación solo lo reconstruye a
        // él. Este Obx queda atado únicamente a resents/favorites, que
        // cambian cuando el usuario hace algo, no en bucle.

        return Container(
          color: HomeTheme.bg,
          child: Stack(
            children: [
              const Positioned.fill(child: AnimatedBackgroundGlow()),
              LayoutBuilder(
                builder: (context, outerConstraints) {
                  return SingleChildScrollView(
                    // Lo que ocupa la barra flotante. Va acá adentro y no
                    // afuera de la página: afuera dejaba una banda negra
                    // detrás de la barra en vez del fondo de la zona.
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 8),
                    // Sin esto, RefreshIndicator (deslizar para actualizar en
                    // Android) no dispara cuando el contenido entra entero en la
                    // pantalla (ej. recién instalado, poco contenido) — el scroll
                    // "corto" no deja hacer overscroll para activarlo.
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      // Fuerza que el contenido ocupe AL MENOS toda la pantalla
                      // visible — así el estado vacío (altura calculada abajo)
                      // puede llegar hasta el fondo real sin dejar un hueco.
                      // OJO: nada de IntrinsicHeight acá — HomeHeroBanner usa
                      // LayoutBuilder, y ese widget NO soporta que le pidan
                      // dimensiones intrínsecas (tira una excepción de layout
                      // que puede cerrar el proceso entero en vez de solo
                      // mostrar el error en pantalla).
                      constraints:
                          BoxConstraints(minHeight: outerConstraints.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // El título, como primer elemento de la lista.
                            //
                            // Decía «Inicio», que era verdad cuando esta
                            // pantalla ERA el Home. Al partirse en dos quedó el
                            // título viejo pegado a la pantalla nueva, y en la
                            // barra de abajo el usuario tocaba «Biblioteca» y
                            // arriba le contestaba «Inicio».
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                0,
                                MediaQuery.paddingOf(context).top + 6,
                                0,
                                _tightTop(context) ? 4 : 10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "common.library".i18n,
                                      // Mismo estilo que el título de Inicio,
                                      // desde un solo lugar.
                                      style: HomeTheme.tituloDeZona(
                                        bajo: _tightTop(context),
                                      ),
                                    ),
                                  ),
                                  // Favoritos, alineado con el título.
                                  //
                                  // Acá y no escondido en otro lado: la
                                  // Biblioteca YA muestra los favoritos en
                                  // secciones, y este es el atajo a verlos
                                  // todos. Estaba detrás de los tres puntos de
                                  // la barra de abajo, que es donde nadie lo
                                  // busca.
                                  IconButton(
                                    tooltip: 'home.favorite'.i18n,
                                    onPressed: _favoritos,
                                    icon: Icon(
                                      Icons.favorite_border_rounded,
                                      color: HomeTheme.textPrimary,
                                    ),
                                  ),
                                  // Y el historial al lado: los dos son «lo
                                  // que ya viste o guardaste», que es de lo que
                                  // trata esta pantalla.
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
                            // Obx propio: aísla la rotación del banner (cada
                            // 20s) del resto de Home — ver comentario arriba.
                            Obx(() => HomeHeroBanner(
                                background: c.heroBackground.value)),
                            // El aire entre el hero y la primera fila se
                            // achica en horizontal de celular: ahí el alto
                            // total es ~300-390 y 32px de hueco eran una
                            // porción visible de la pantalla.
                            SizedBox(height: _tightTop(context) ? 14 : 32),
                            if (isEmpty)
                              SizedBox(
                                // 32 (padding vertical del Column) + 32 (gap
                                // arriba) + ~220 (alto mínimo del hero) — el
                                // resto de la pantalla, con un piso razonable.
                                //
                                // El piso tiene que ser AL MENOS el mismo
                                // `minHeight: 320` que `_BibliotecaVacia` ya
                                // se pide a sí misma (icono + texto + botón +
                                // su padding interno) — con 220 este SizedBox
                                // le daba una altura TIGHT más chica que la
                                // que pedía, y la apretaba: se veía "BOTTOM
                                // OVERFLOWED BY 28 PIXELS" en un teléfono/
                                // tablet acostado, donde el alto disponible
                                // es chico. Reportado en vivo con captura.
                                height:
                                    (outerConstraints.maxHeight - 32 - 32 - 220)
                                        .clamp(320.0, double.infinity),
                                child: const _BibliotecaVacia(),
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

  Widget _buildAndroidHome(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      // ── Sin AppBar ───────────────────────────────────────────────────────
      //
      // Una AppBar dibuja su propia superficie con elevación, y sobre el fondo
      // animado eso quedaba como una franja gris cruzando la pantalla — una
      // costura que no está en ninguna otra zona.
      //
      // El título no se pierde: pasa a ser texto suelto, igual que el
      // «PrismHub» del Home, y se desplaza con el contenido en vez de comerse
      // una franja fija para siempre.
      // El título ya no va acá afuera: entró al desplazamiento, como primer
      // elemento (ver _buildContent). Así se va con las tarjetas al bajar en
      // vez de comerse una franja fija para siempre — exactamente lo que hace
      // el nombre de la app en el Inicio.
      body: Column(
        children: [
          Expanded(
            // Además del refresco automático (ver HomePageController),
            // deslizar para abajo lo fuerza al toque — sin esperar el timer.
            child: RefreshIndicator(
              onRefresh: () => c.onRefresh(),
              color: HomeTheme.accentPink,
              backgroundColor: HomeTheme.cardSurface,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHome(BuildContext context) {
    return _buildContent();
  }

  /// Biblioteca en TV.
  ///
  /// Las secciones son las mismas (Continuar viendo/leyendo, Favoritos) y las
  /// tarjetas ya se enfocan solas en TV (ver HomeMediaCard). Lo que cambia es
  /// el marco: nada de Scaffold ni de "deslizar para actualizar" —no hay dedo
  /// que deslice, y ese gesto además peleaba con el subir del mando—.
  ///
  /// Sin fondo propio ni márgenes: en TV esta pantalla se dibuja DENTRO de la
  /// Home (es una zona más del sidebar, ver home_page_tv.dart), que ya pone el
  /// fondo, la barra de arriba y el margen de overscan. Repetirlos acá daba
  /// doble margen y un fondo encima del otro.
  ///
  /// Y tampoco reusa `_buildContent`: ese está armado para ocupar la pantalla
  /// ENTERA —el hueco del estado vacío se calcula restándole al alto total—
  /// y acá el alto disponible es menor (el sidebar y la barra de arriba ya se
  /// llevaron lo suyo). Con esa cuenta pensada para pantalla completa, el
  /// contenido se pasaba de largo: los 28 píxeles de desborde que se veían.
  Widget _buildTvHome(BuildContext context) {
    return Obx(() {
      // Sin título ni botones de Favoritos/Historial: en TV esos dos ya
      // están en la barra de arriba de la Home (esta pantalla vive dentro de
      // ella), y el nombre de la zona lo dice el sidebar. Repetirlos era
      // gastar la franja de arriba en algo que el usuario tiene enfrente.
      final vacia = c.resents.isEmpty && c.favorites.isEmpty;
      // El vacío de TV es propio: el de teléfono trae su recuadro con borde
      // y su botón de "Ver historial", y acá los dos sobran — el historial
      // ya está en la barra de arriba, y el recuadro dentro del panel se
      // leía como una caja flotando arriba en vez de un centro de pantalla.
      if (vacia) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 56,
                color: HomeTheme.textMuted,
              ),
              const SizedBox(height: 18),
              Text(
                'home.no-record'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(color: HomeTheme.textMuted, fontSize: 16),
              ),
            ],
          ),
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ..._continuarSecciones(context),
          ..._favoritosSecciones(context),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformTv.esTelevisionSync) return _buildTvHome(context);
    return PlatformBuildWidget(
      androidBuilder: _buildAndroidHome,
      desktopBuilder: _buildDesktopHome,
    );
  }
}

// Estado vacío cuando no hay ni Continuar viendo ni Favoritos — un área
// marcada (borde suave) con un ícono que pulsa despacio, en vez de dejar el
// home con un hueco sin nada debajo del banner.
// Navega al Historial desde el estado vacío. Ramificado por plataforma como
// el resto: en Android es una pestaña del shell, en escritorio una ruta.
void _abrirHistorial(BuildContext context) {
  if (Platform.isAndroid) {
    Get.to(() => const HistoryPage());
    return;
  }
  router.push('/history');
}

/// Botón discreto para llegar al Historial cuando el Inicio está vacío.
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

class _BibliotecaVacia extends StatefulWidget {
  const _BibliotecaVacia();

  @override
  State<_BibliotecaVacia> createState() => _BibliotecaVaciaState();
}

class _BibliotecaVaciaState extends State<_BibliotecaVacia>
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
                      color: HomeTheme.accentPink.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.movie_filter_outlined,
                    color: HomeTheme.accentPink,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'home.no-record'.i18n,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: HomeTheme.textMuted, fontSize: 13.5),
              ),
              const SizedBox(height: 18),
              // Botón al Historial: con los estados de seguimiento, terminar
              // todo deja el Home vacío aunque el Historial tenga contenido —
              // sin este acceso parecería que se perdió todo.
              _VerHistorialBoton(
                  accent: HomeTheme.accentPink,
                  onTap: () => _abrirHistorial(context)),
            ],
          ),
        ),
      ),
    );
  }
}
