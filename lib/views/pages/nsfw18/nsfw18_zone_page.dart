import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/favorite.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/resume_history.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_lock_page.dart';
import 'package:prismhub/views/widgets/button.dart';
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
final bool _wideCards = !Platform.isAndroid;

// true en horizontal de celular, donde el alto útil es ~300-390 y cada bloque
// de aire vertical se nota muchísimo más que en vertical o en escritorio.
bool _tightTop(BuildContext context) =>
    Platform.isAndroid &&
    MediaQuery.of(context).orientation == Orientation.landscape;

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
      return const Scaffold(
          backgroundColor: HomeTheme.bg, body: SizedBox.shrink());
    }
    if (!_unlocked) {
      return Nsfw18LockPage(
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }
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
        iconTheme: const IconThemeData(color: HomeTheme.textPrimary),
        title: Text(
          'nsfw18.title'.i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
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
                const Icon(Icons.lock_outline,
                    color: HomeTheme.textMuted, size: 40),
                const SizedBox(height: 16),
                Text(
                  'nsfw18.disabled-title'.i18n,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomeTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'nsfw18.disabled-subtitle'.i18n,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: HomeTheme.textMuted, fontSize: 13),
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
                          Get.find<MainController>().changeTab(3);
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
  late final HomePageController c =
      Get.isRegistered<HomePageController>(tag: HomePageController.zoneTag)
          ? Get.find<HomePageController>(tag: HomePageController.zoneTag)
          : Get.put(
              HomePageController(nsfwOnly: true),
              tag: HomePageController.zoneTag,
            );

  void _openDetail(String url, String package) {
    ExtensionUtils.openExtensionDetail(context, package: package, url: url);
  }

  void _openHistoryTab(int tab) {
    if (Platform.isAndroid) {
      Get.to(HistoryPage(initialTab: tab, zone: true));
      return;
    }
    router.push(
      Uri(
        path: '/history',
        queryParameters: {'tab': tab.toString(), 'zone': '1'},
      ).toString(),
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
        accent: HomeTheme.accentRed,
        title: titulo,
        onClickMore: () => _openHistoryTab(1),
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
                accent: HomeTheme.accentRed,
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
        accent: HomeTheme.accentRed,
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
                accent: HomeTheme.accentRed,
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
        return Container(
          color: HomeTheme.bg,
          child: Stack(
            children: [
              const Positioned.fill(
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
                            Obx(() => HomeHeroBanner(
                                  background: c.heroBackground.value,
                                  gradient: HomeTheme.heroGradientRed,
                                  // Android: esta pantalla se llegó con Get.to
                                  // (empujada encima del shell principal), así
                                  // que hay que cambiar la pestaña Y cerrarla.
                                  //
                                  // La pestaña se cambia ANTES del pop, no
                                  // después: al revés había una carrera con la
                                  // animación del pop y el cambio no se
                                  // aplicaba — entrando desde Ajustes, tocar
                                  // "Explorar catálogo" devolvía a Ajustes en
                                  // vez de ir a Buscar (confirmado en vivo).
                                  // Poniéndola primero, cuando el pop revela
                                  // el shell ya está en Buscar y no hay carrera
                                  // posible.
                                  //
                                  // En desktop el default ya anda bien
                                  // (router.go reemplaza la ruta actual sea
                                  // cual sea, confirmado en vivo).
                                  onExploreCatalog: Platform.isAndroid
                                      ? () {
                                          // isRegistered y no try/catch: si
                                          // por lo que sea el controller no
                                          // está, el pop TIENE que pasar igual
                                          // — si no, se queda atrapado acá.
                                          // isRegistered y no try/catch: si
                                          // por lo que sea el controller no
                                          // está, el pop TIENE que pasar igual
                                          // — si no, se queda atrapado acá.
                                          if (Get.isRegistered<
                                              MainController>()) {
                                            Get.find<MainController>()
                                                .changeTab(1);
                                          }
                                          // until(isFirst) y no un back()
                                          // simple: un back() cierra UNA capa
                                          // y deja lo que haya abajo. Medido
                                          // en vivo con logs: la pestaña
                                          // quedaba correcta en Buscar y el
                                          // shell la dibujaba, pero el usuario
                                          // seguía viendo Ajustes — o sea que
                                          // había otra ruta apilada encima del
                                          // shell tapándolo. Volviendo hasta
                                          // la primera ruta se llega al shell
                                          // sí o sí, sin importar cuántas
                                          // capas haya quedado en el medio.
                                          Get.until((route) => route.isFirst);
                                        }
                                      : null,
                                )),
                            // El aire entre el hero y la primera fila se
                            // achica en horizontal de celular: ahí el alto
                            // total es ~300-390 y 32px de hueco eran una
                            // porción visible de la pantalla.
                            SizedBox(height: _tightTop(context) ? 14 : 32),
                            if (isEmpty)
                              SizedBox(
                                height:
                                    (outerConstraints.maxHeight - 32 - 32 - 220)
                                        .clamp(220.0, double.infinity),
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

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'nsfw18.title'.i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
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
    return _buildContent();
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
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
                  child: const Icon(
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
