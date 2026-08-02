import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

// "Ver todo" destination for Home's Continuar section — one place with
// every history/favorite item, filterable by tab, searchable by title, and
// deletable one-by-one (visible trash icon) or all at once (no right-click
// needed for either). Mismo estilo visual que Home (HomeTheme + HomeMediaCard)
// para que se sienta parte de la misma app, no una pantalla aparte.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.initialTab = 0, this.zone = false});
  final int initialTab;
  // true: instancia de la Zona +18 (HomePageController.zoneTag, tema rojo).
  // Es la misma pantalla, apuntando a la OTRA instancia del controller.
  final bool zone;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HomePageController _c = Get.find<HomePageController>(
    tag: widget.zone ? HomePageController.zoneTag : null,
  );
  late final Color _accent =
      widget.zone ? HomeTheme.accentRed : HomeTheme.accentPink;
  late int _tabIndex = widget.initialTab;
  final _searchController = TextEditingController();
  String _query = '';

  // "Lectura" agrupa manga+novela — de cara al usuario es una sola
  // categoría (ambos son texto para leer).
  // Favoritos se parte en dos por el mismo motivo que se partió "Continuar"
  // en el Home: vídeo y lectura no comparten forma de tarjeta, y mezclados
  // uno de los dos siempre queda mal.
  static const _tabs = [
    'search.all',
    'extension-type.video',
    'extension-type.reading',
    'history.favorites-video',
    'history.favorites-reading',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _video = {ExtensionType.bangumi};
  static const _lectura = {ExtensionType.manga, ExtensionType.fikushon};

  Set<ExtensionType>? get _typeFilter {
    switch (_tabIndex) {
      case 1:
      case 3:
        return _video;
      case 2:
      case 4:
        return _lectura;
      default:
        return null;
    }
  }

  bool get _onFavoritesTab => _tabIndex >= 3;

  /// La pestaña actual muestra vídeo (tarjeta ancha) o lectura (vertical).
  /// `null` en "Todo", donde conviven los dos.
  bool? get _tabEsVideo {
    if (_tabIndex == 1 || _tabIndex == 3) return true;
    if (_tabIndex == 2 || _tabIndex == 4) return false;
    return null;
  }

  // ── Filtros de estado y orden ─────────────────────────────────────────────
  _EstadoFiltro _estado = _EstadoFiltro.todos;
  _Orden _orden = _Orden.recientes;

  List<History> _aplicarEstado(List<History> list) {
    switch (_estado) {
      case _EstadoFiltro.todos:
        return list;
      case _EstadoFiltro.pendiente:
        return list.where((h) => h.watchState == WatchState.pending).toList();
      case _EstadoFiltro.completado:
        return list.where((h) => h.watchState == WatchState.completed).toList();
      case _EstadoFiltro.finalizado:
        // Eje distinto de los dos anteriores: acá se pregunta por la OBRA, no
        // por el avance del usuario. Ver WatchState en history.dart.
        return list.where((h) => h.seriesFinished).toList();
    }
  }

  List<T> _aplicarOrden<T>(
    List<T> list,
    String Function(T) tituloDe,
    DateTime Function(T) fechaDe,
  ) {
    final copia = [...list];
    switch (_orden) {
      case _Orden.recientes:
        copia.sort((a, b) => fechaDe(b).compareTo(fechaDe(a)));
      case _Orden.antiguos:
        copia.sort((a, b) => fechaDe(a).compareTo(fechaDe(b)));
      case _Orden.az:
        copia.sort((a, b) =>
            tituloDe(a).toLowerCase().compareTo(tituloDe(b).toLowerCase()));
      case _Orden.za:
        copia.sort((a, b) =>
            tituloDe(b).toLowerCase().compareTo(tituloDe(a).toLowerCase()));
    }
    return copia;
  }

  List<History> _filteredHistory() {
    final type = _typeFilter;
    // allHistory y no resents: el Historial muestra TODO, incluido lo
    // completado. resents es la lista de "Continuar", que sí lo excluye.
    final base = _c.allHistory.where((h) {
      if (type != null && !type.contains(h.type)) return false;
      if (!SearchText.matchesQuery(h.title, _query)) return false;
      return true;
    }).toList();
    return _aplicarOrden(
      _aplicarEstado(base),
      (h) => h.title,
      (h) => h.date,
    );
  }

  List<Favorite> _filteredFavorites() {
    final type = _typeFilter;
    final base = _c.favorites.where((f) {
      if (type != null && !type.contains(f.type)) return false;
      if (!SearchText.matchesQuery(f.title, _query)) return false;
      return true;
    }).toList();
    // Los favoritos no llevan estado de avance (eso vive en el historial), así
    // que el filtro de estado no aplica — solo el orden.
    return _aplicarOrden(base, (f) => f.title, (f) => f.date);
  }

  /// Alterna entre "en curso" y "visto". No toca la fecha: mover un título
  /// entre estados no es haberlo visto de nuevo, y actualizarla lo mandaría al
  /// principio del Historial sin motivo.
  Future<void> _cambiarEstado(History h) async {
    h.watchState = h.watchState == WatchState.completed
        ? WatchState.pending
        : WatchState.completed;
    h.newEpisodeLabel = null;
    await DatabaseService.putHistoryRaw(h);
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  void _openDetail(String url, String package) {
    ExtensionUtils.openExtensionDetail(context, package: package, url: url);
  }

  // Si hay un DetailPageController vivo para este título (la página de
  // detalle sigue abierta en otra pestaña/ventana), le avisa que se olvide
  // la decisión de +18 que tenía guardada — sin esto, borrar acá no
  // afectaba esa instancia ya cargada, y volver a favoritear/mirar desde
  // ahí mismo NO volvía a preguntar (arrastraba la respuesta vieja).
  void _forgetNsfwDecisionIfOpen(String package, String url) {
    final tag = '$package|$url';
    if (Get.isRegistered<DetailPageController>(tag: tag)) {
      Get.find<DetailPageController>(tag: tag).forgetNsfwDecision();
    }
  }

  Future<void> _deleteHistory(History h) async {
    await DatabaseService.deleteHistoryByPackageAndUrl(h.package, h.url);
    _forgetNsfwDecisionIfOpen(h.package, h.url);
    await _c.refreshHistory();
    if (mounted) setState(() {});
  }

  Future<void> _deleteFavorite(Favorite f) async {
    await DatabaseService.deleteFavorite(f.package, f.url);
    _forgetNsfwDecisionIfOpen(f.package, f.url);
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HomeTheme.cardSurface,
        content: Text(
          'home.clear-history-confirm'.i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.i18n),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'common.delete-all'.i18n,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_onFavoritesTab) {
      for (final f in _c.favorites) {
        _forgetNsfwDecisionIfOpen(f.package, f.url);
      }
      // Solo la zona en la que estamos parados.
      //
      // Antes se borraba TODO sin mirar: desde el Historial +18, "borrar todo"
      // se llevaba puesto también lo del inicio normal, y al revés. La pantalla
      // ya sabía en qué zona estaba (widget.zone), pero el borrado no.
      await DatabaseService.deleteFavoritesByType(null, soloNsfw: widget.zone);
    } else {
      for (final h in _c.resents) {
        _forgetNsfwDecisionIfOpen(h.package, h.url);
      }
      final types = _typeFilter;
      if (types == null) {
        // Mismo motivo que arriba: solo la zona en la que estamos.
        await DatabaseService.deleteHistoryByType(null, soloNsfw: widget.zone);
      } else {
        // La pestaña "Lectura" agrupa manga+novela — hay que borrar cada
        // tipo por separado, deleteHistoryByType solo acepta uno a la vez.
        for (final t in types) {
          await DatabaseService.deleteHistoryByType(t, soloNsfw: widget.zone);
        }
      }
    }
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  Widget _buildGrid() {
    final favorites = _onFavoritesTab ? _filteredFavorites() : null;
    final history = _onFavoritesTab ? null : _filteredHistory();
    final itemCount = favorites?.length ?? history!.length;

    if (itemCount == 0) {
      final nothingAtAll = _c.resents.isEmpty && _c.favorites.isEmpty;
      return SliverPadding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        sliver: SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              nothingAtAll
                  ? (widget.zone
                      ? 'nsfw18.no-record'.i18n
                      : 'home.no-record'.i18n)
                  : 'common.no-result'.i18n,
              style: const TextStyle(color: HomeTheme.textMuted),
            ),
          ),
        ),
      );
    }

    final isAndroidLandscape = Platform.isAndroid &&
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Tarjeta ancha 16:9 solo cuando la pestaña muestra SOLO vídeo y hay ancho
    // para ella. En "Todo" conviven los dos tipos y la grilla reserva un único
    // alto y una única forma, así que ahí manda la vertical: es la que sirve
    // para ambos sin recortar. Es el mismo motivo por el que en el Home hubo
    // que partir "Continuar" en dos filas.
    final usarAncha = _tabEsVideo == true && !Platform.isAndroid;

    final cardWidth = usarAncha
        ? HomeMediaCard.wideWidth
        : isAndroidLandscape
            ? HomeMediaCard.androidLandscapeWidth
            : Platform.isAndroid
                ? HomeMediaCard.androidWidth
                : HomeMediaCard.desktopWidth;
    // La ancha ya trae su alto TOTAL (imagen + textos); la vertical solo el de
    // la portada, así que a esa hay que sumarle lo que va debajo.
    final cardExtent = usarAncha
        ? HomeMediaCard.wideTotalHeight + 18
        : (isAndroidLandscape
                ? HomeMediaCard.androidLandscapeHeight
                : Platform.isAndroid
                    ? HomeMediaCard.androidHeight
                    : HomeMediaCard.desktopHeight) +
            70;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: cardWidth + 16,
          mainAxisExtent: cardExtent,
          mainAxisSpacing: 20,
          crossAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final card = _onFavoritesTab
                ? _buildFavoriteCard(favorites![index], ancha: usarAncha)
                : _buildHistoryCard(history![index], ancha: usarAncha);
            return Align(
              alignment: Alignment.topCenter,
              child: card,
            );
          },
          childCount: itemCount,
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(Favorite f, {bool ancha = false}) {
    // Obx: igual que en home_page.dart — sin esto, togglear "ocultar" no
    // refrescaba la tarjeta acá (el RxSet de HiddenCards cambia, pero nada
    // en esta pantalla estaba suscripto a él) hasta reconstruir toda la
    // página (cambiar de pestaña y volver).
    return Obx(() => HomeMediaCard(
          horizontal: ancha,
          key: ValueKey('fav-${f.package}-${f.url}'),
          title: f.title,
          subtitle: 'home.favorite'.i18n,
          type: f.type,
          cover: f.cover,
          headers: _c.headersForPackage(f.package),
          onTap: () => _openDetail(f.url, f.package),
          onDelete: () => _deleteFavorite(f),
          onVerDetalle: () => _openDetail(f.url, f.package),
          hidden: HiddenCards.isHidden(f.package, f.url),
          onToggleHide: () => HiddenCards.toggle(f.package, f.url),
          accent: _accent,
        ));
  }

  Widget _buildHistoryCard(History h, {bool ancha = false}) {
    // La portada de vídeo puede ser una captura local O el póster de red (ver
    // PortadaHistorial). Antes acá se asumía siempre archivo local, así que un
    // ítem con póster de red hacía File("https://...") y la tarjeta quedaba
    // sin imagen — se notaba sobre todo en la Zona +18, y parecía que el botón
    // de mostrar/ocultar imagen se rompía.
    final portada = PortadaHistorial.de(h);
    // Obx: ver comentario en _buildFavoriteCard.
    return Obx(() => HomeMediaCard(
          horizontal: ancha,
          key: ValueKey('hist-${h.package}-${h.url}'),
          title: h.title,
          subtitle: FlutterI18n.translate(
            context,
            h.type == ExtensionType.bangumi
                ? 'home.watched-episode'
                : 'home.watched-chapter',
            translationParams: {
              'ep': ExtensionUtils.episodeNumberLabel(
                  h.episodeTitle, h.episodeId),
            },
          ),
          type: h.type,
          cover: portada.url,
          coverFile: portada.archivo,
          headers: portada.necesitaHeaders
              ? _c.headersForPackage(h.package)
              : null,
          onTap: () => _openDetail(h.url, h.package),
          onDelete: () => _deleteHistory(h),
          // Mover entre "en curso" y "visto" sin abrir el título. Hasta ahora
          // la única forma de devolver algo a Continuar era abrirlo y leer un
          // capítulo, y la única de sacarlo era quitarlo desde el Home.
          extraActionLabel: h.watchState == WatchState.completed
              ? 'history.back-to-continue'.i18n
              : 'history.mark-seen'.i18n,
          extraActionIcon: h.watchState == WatchState.completed
              ? Icons.replay_rounded
              : Icons.check_rounded,
          onExtraAction: () => _cambiarEstado(h),
          onVerDetalle: () => _openDetail(h.url, h.package),
          hidden: HiddenCards.isHidden(h.package, h.url),
          onToggleHide: () => HiddenCards.toggle(h.package, h.url),
          accent: _accent,
        ));
  }

  // Un solo chip para pestañas, estado y orden — antes el de pestañas estaba
  // escrito inline y copiarlo dos veces más era garantizar que se separaran.
  Widget _chip(String texto, bool seleccionado, VoidCallback onTap,
      {double fontSize = 13}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              horizontal: fontSize > 12 ? 16 : 12,
              vertical: fontSize > 12 ? 9 : 6),
          decoration: BoxDecoration(
            color: seleccionado
                ? _accent.withValues(alpha: 0.18)
                : HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: seleccionado ? _accent : HomeTheme.border,
            ),
          ),
          child: Text(
            texto,
            style: TextStyle(
              color: seleccionado ? _accent : HomeTheme.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        // Centrados en celular: las pestañas ocupan dos líneas en pantalla
        // angosta y alineadas a la izquierda la segunda quedaba colgando sola
        // en un costado. En escritorio entran en una línea y ahí el alineado a
        // la izquierda es lo correcto.
        alignment:
            Platform.isAndroid ? WrapAlignment.center : WrapAlignment.start,
        spacing: 10,
        runSpacing: 10,
        children: List.generate(
          _tabs.length,
          (index) => _chip(
            _tabs[index].i18n,
            index == _tabIndex,
            () => setState(() => _tabIndex = index),
          ),
        ),
      ),
    );
  }

  // Estado y orden en una sola fila. El estado se oculta en Favoritos: ahí no
  // hay avance del usuario que filtrar (eso vive en el historial), y dejar
  // chips que no hacen nada confunde más que ayudar.
  Widget _buildFiltrosYOrden() {
    final etiquetasEstado = {
      _EstadoFiltro.todos: 'history.state-all'.i18n,
      _EstadoFiltro.pendiente: 'history.state-pending'.i18n,
      _EstadoFiltro.completado: 'history.state-completed'.i18n,
      _EstadoFiltro.finalizado: 'history.state-finished'.i18n,
    };
    final etiquetasOrden = {
      _Orden.recientes: 'history.sort-recent'.i18n,
      _Orden.antiguos: 'history.sort-oldest'.i18n,
      _Orden.az: 'history.sort-az'.i18n,
      _Orden.za: 'history.sort-za'.i18n,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Wrap(
        alignment:
            Platform.isAndroid ? WrapAlignment.center : WrapAlignment.start,
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!_onFavoritesTab)
            for (final e in _EstadoFiltro.values)
              _chip(
                etiquetasEstado[e]!,
                _estado == e,
                () => setState(() => _estado = e),
                fontSize: 12,
              ),
          if (!_onFavoritesTab) const SizedBox(width: 12),
          Icon(Icons.sort, size: 16, color: HomeTheme.textMuted),
          for (final o in _Orden.values)
            _chip(
              etiquetasOrden[o]!,
              _orden == o,
              () => setState(() => _orden = o),
              fontSize: 12,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    // Desktop corre sobre fluent_ui, no Material — un TextField de Material
    // no encuentra el ancestro que necesita ahí (crashea con "No Material
    // widget found"). fluent.TextBox es el equivalente correcto para ese
    // árbol; Android sí tiene Material disponible (Scaffold en la raíz).
    if (Platform.isAndroid) {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HomeTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: HomeTheme.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style:
                    const TextStyle(color: HomeTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'common.search'.i18n,
                  hintStyle: const TextStyle(color: HomeTheme.textMuted),
                  // Solo visible con texto — antes no había forma de
                  // limpiar la búsqueda salvo borrar a mano.
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: HomeTheme.textMuted),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: fluent.TextBox(
        controller: _searchController,
        placeholder: 'common.search'.i18n,
        prefix: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(fluent.FluentIcons.search, size: 16),
        ),
        // Solo visible con texto — antes no había forma de limpiar la
        // búsqueda en desktop sin borrar a mano.
        suffix: _query.isEmpty
            ? null
            : fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.chrome_close, size: 9.0),
                onPressed: () => setState(() {
                  _searchController.clear();
                  _query = '';
                }),
              ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildSearchAndActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(child: _buildSearchBox()),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _confirmClearAll,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: HomeTheme.cardSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HomeTheme.border),
                ),
                child: Text(
                  'common.delete-all'.i18n,
                  style: const TextStyle(
                    color: HomeTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Obx(
      () {
        // Se leen ACÁ, síncrono, dentro del Obx. Las tarjetas se arman
        // dentro de un LayoutBuilder más abajo, y LayoutBuilder.builder
        // corre en la fase de LAYOUT, no de build — o sea que los Rx que
        // lee _buildGrid() ahí quedan FUERA de lo que Obx rastrea. Sin esta
        // lectura previa, Obx no encontraba ninguna variable observable en
        // su alcance y tiraba "improper use of a GetX has been detected"
        // (confirmado en vivo). Mismo motivo documentado en home_page.dart.
        // ignore: unused_local_variable
        final _ = _c.resents.length + _c.favorites.length;

        return Container(
          color: HomeTheme.bg,
          child: Stack(
            children: [
              Positioned.fill(child: AnimatedBackgroundGlow(accent: _accent)),
              // Todo (pestañas + buscador + tarjetas) en UN solo scroll: con
              // el encabezado fijo y el grid en un Expanded, en horizontal al
              // grid le quedaban ~150px y las tarjetas se cortaban sin poder
              // llegar a verlas enteras. Así el encabezado se desplaza y las
              // tarjetas usan toda la pantalla.
              Positioned.fill(
                child: CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(child: _buildTabs()),
                    SliverToBoxAdapter(child: _buildFiltrosYOrden()),
                    SliverToBoxAdapter(child: _buildSearchAndActions()),
                    _buildGrid(),
                  ],
                ),
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
      // El teclado se superpone en vez de encoger el body: en horizontal, al
      // enfocar el buscador quedaban ~100px de alto y las partes fijas
      // (pestañas + buscador) ya se los comían, así que al grid no le
      // quedaba nada y desbordaba (confirmado en vivo). El buscador está
      // ARRIBA, así que sigue visible con el teclado abierto.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          widget.zone ? 'nsfw18.title'.i18n : 'home.history'.i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.zone ? 'nsfw18.title'.i18n : 'home.history'.i18n,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: HomeTheme.textPrimary,
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No hacer early-return acá con un Center+Text suelto: eso saltea el
    // Scaffold/AppBar (sin Material ancestor, Flutter dibuja el texto con su
    // estilo de fallback feo — rojo con subrayado amarillo) y deja la página
    // sin botón para volver. El estado vacío se maneja dentro de _buildGrid,
    // que ya corre dentro del Scaffold normal.
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}

/// Filtro por estado del Historial. `finalizado` mira un eje distinto de los
/// otros dos: si la OBRA terminó, no si el usuario está al día.
enum _EstadoFiltro { todos, pendiente, completado, finalizado }

enum _Orden { recientes, antiguos, az, za }
