import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/favorite.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/utils/i18n.dart';
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
final bool _wideCards = !Platform.isAndroid;

// true en horizontal de celular, donde el alto útil es ~300-390 y cada bloque
// de aire vertical se nota muchísimo más que en vertical o en escritorio.
bool _tightTop(BuildContext context) =>
    Platform.isAndroid &&
    MediaQuery.of(context).orientation == Orientation.landscape;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late HomePageController c;

  // Índice de la pestaña "Favoritos" en HistoryPage — bajó de 4 a 3 al
  // fusionar las pestañas Manga+Novela en una sola ("Lectura").
  static const _favoritesTabIndex = 3;

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

  void _openDetail(String url, String package) {
    ExtensionUtils.openExtensionDetail(context, package: package, url: url);
  }

  void _openHistoryTab(int tab) {
    if (Platform.isAndroid) {
      Get.to(HistoryPage(initialTab: tab));
      return;
    }
    router.push(
      Uri(path: '/history', queryParameters: {'tab': tab.toString()})
          .toString(),
    );
  }

  bool _isRemoteCover(String? cover) {
    if (cover == null || cover.isEmpty) return false;
    final normalized = cover.toLowerCase();
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://');
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
    }) {
      return HomeSection(
        itemWidth: ancha ? HomeMediaCard.wideWidth : null,
        itemHeight: ancha ? HomeMediaCard.wideTotalHeight : null,
        itemCoverHeight: ancha ? HomeMediaCard.wideImageHeight : null,
        boxed: true,
        accent: HomeTheme.accentPink,
        title: titulo,
        onClickMore: () => _openHistoryTab(_favoritesTabIndex),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final f = items[index];
          // Obx por tarjeta: ver el mismo comentario en _continuarSecciones.
          return Obx(() => HomeMediaCard(
                horizontal: ancha,
                // El tipo lo dice el título de la sección.
                type: null,
                title: f.title,
                subtitle: 'home.favorite'.i18n,
                extensionName:
                    ExtensionUtils.runtimes[f.package]?.extension.name,
                cover: f.cover,
                headers: c.headersForPackage(f.package),
                onTap: () => _openDetail(f.url, f.package),
                onDelete: () => c.deleteFavorite(f),
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
          items: videos,
          ancha: _wideCards,
        ),
        const SizedBox(height: 32),
      ],
      if (lectura.isNotEmpty) ...[
        seccion(
          titulo: 'home.favorite-reading'.i18n,
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
    }) {
      return HomeSection(
        // La ancha usa su propio tamaño; la vertical deja los valores por
        // defecto, que ya se adaptan a cada plataforma y orientación.
        itemWidth: ancha ? HomeMediaCard.wideWidth : null,
        itemHeight: ancha ? HomeMediaCard.wideTotalHeight : null,
        itemCoverHeight: ancha ? HomeMediaCard.wideImageHeight : null,
        boxed: true,
        accent: HomeTheme.accentPink,
        title: titulo,
        onClickMore: () => _openHistoryTab(0),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final h = items[index];
          // Obx propio por tarjeta — ListView.builder arma cada ítem de forma
          // perezosa, FUERA del alcance del Obx que envuelve la página, así
          // que sin esto togglear "ocultar" no refrescaba la tarjeta.
          final isVideo = h.type == ExtensionType.bangumi;
          final remoteVideoCover = isVideo && _isRemoteCover(h.cover);
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
                cover: isVideo ? (remoteVideoCover ? h.cover : null) : h.cover,
                coverFile: isVideo && h.cover != null && !remoteVideoCover
                    ? File(h.cover!)
                    : null,
                headers: isVideo && !remoteVideoCover
                    ? null
                    : c.headersForPackage(h.package),
                newEpisodeLabel: h.newEpisodeLabel,
                onTap: () => resumeHistoryItem(context, h),
                // No borra: saca el ítem de Continuar marcándolo visto. El
                // borrado real vive en el Historial, que es donde uno
                // administra el archivo.
                onDelete: () => c.quitarDeContinuar(h),
                deleteLabel: 'home.remove-from-continue'.i18n,
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
          items: videos,
          // La card ancha es solo de escritorio; en celular no entra.
          ancha: _wideCards,
        ),
        const SizedBox(height: 32),
      ],
      if (lectura.isNotEmpty) ...[
        seccion(
          titulo: 'home.continue-reading'.i18n,
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
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                height:
                                    (outerConstraints.maxHeight - 32 - 32 - 220)
                                        .clamp(220.0, double.infinity),
                                child: const _HomeEmptyState(),
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
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          "common.home".i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      // Además del refresco automático (ver HomePageController), deslizar
      // para abajo lo fuerza al toque — sin esperar el timer.
      body: RefreshIndicator(
        onRefresh: () => c.onRefresh(),
        color: HomeTheme.accentPink,
        backgroundColor: HomeTheme.cardSurface,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildDesktopHome(BuildContext context) {
    return _buildContent();
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroidHome,
      desktopBuilder: _buildDesktopHome,
    );
  }
}

// Estado vacío cuando no hay ni Continuar viendo ni Favoritos — un área
// marcada (borde suave) con un ícono que pulsa despacio, en vez de dejar el
// home con un hueco sin nada debajo del banner.
class _HomeEmptyState extends StatefulWidget {
  const _HomeEmptyState();

  @override
  State<_HomeEmptyState> createState() => _HomeEmptyStateState();
}

class _HomeEmptyStateState extends State<_HomeEmptyState>
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
                  child: const Icon(
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
                    const TextStyle(color: HomeTheme.textMuted, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
