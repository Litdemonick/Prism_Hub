import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/pages/detail_page.dart';
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
  const HistoryPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HomePageController _c = Get.find<HomePageController>();
  late int _tabIndex = widget.initialTab;
  final _searchController = TextEditingController();
  String _query = '';

  // "Lectura" agrupa manga+novela — de cara al usuario es una sola
  // categoría (ambos son texto para leer).
  static const _tabs = [
    'search.all',
    'extension-type.video',
    'extension-type.reading',
    'home.favorite',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Set<ExtensionType>? get _typeFilter {
    switch (_tabIndex) {
      case 1:
        return {ExtensionType.bangumi};
      case 2:
        return {ExtensionType.manga, ExtensionType.fikushon};
      default:
        return null;
    }
  }

  bool get _onFavoritesTab => _tabIndex == 3;

  List<History> _filteredHistory() {
    final type = _typeFilter;
    final q = _query.trim().toLowerCase();
    return _c.resents.where((h) {
      if (type != null && !type.contains(h.type)) return false;
      if (q.isNotEmpty && !h.title.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  List<Favorite> _filteredFavorites() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _c.favorites;
    return _c.favorites
        .where((f) => f.title.toLowerCase().contains(q))
        .toList();
  }

  void _openDetail(String url, String package) {
    if (Platform.isAndroid) {
      Get.to(DetailPage(
        key: ValueKey('$package|$url'),
        url: url,
        package: package,
        tag: '$package|$url',
      ));
      return;
    }
    router.push(
      Uri(
        path: '/detail',
        queryParameters: {'url': url, 'package': package},
      ).toString(),
    );
  }

  Future<void> _deleteHistory(History h) async {
    await DatabaseService.deleteHistoryByPackageAndUrl(h.package, h.url);
    await _c.refreshHistory();
    if (mounted) setState(() {});
  }

  Future<void> _deleteFavorite(Favorite f) async {
    await DatabaseService.deleteFavorite(f.package, f.url);
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
      await DatabaseService.deleteFavoritesByType(null);
    } else {
      final types = _typeFilter;
      if (types == null) {
        await DatabaseService.deleteHistoryByType(null);
      } else {
        // La pestaña "Lectura" agrupa manga+novela — hay que borrar cada
        // tipo por separado, deleteHistoryByType solo acepta uno a la vez.
        for (final t in types) {
          await DatabaseService.deleteHistoryByType(t);
        }
      }
    }
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  Widget _buildGrid() {
    final items = _onFavoritesTab
        ? _filteredFavorites().map((f) {
            return HomeMediaCard(
              key: ValueKey('fav-${f.package}-${f.url}'),
              title: f.title,
              subtitle: 'home.favorite'.i18n,
              type: f.type,
              cover: f.cover,
              headers: _c.headersForPackage(f.package),
              onTap: () => _openDetail(f.url, f.package),
              onDelete: () => _deleteFavorite(f),
              hidden: HiddenCards.isHidden(f.package, f.url),
              onToggleHide: () => HiddenCards.toggle(f.package, f.url),
            );
          }).toList()
        : _filteredHistory().map((h) {
            return HomeMediaCard(
              key: ValueKey('hist-${h.package}-${h.url}'),
              title: h.title,
              // episodeTitle a veces queda igual al título de la obra (sin
              // número propio) — pero cuando sí trae un número real (lo más
              // común), ese número es más confiable que la posición en la
              // lista (episodeId+1), que puede no coincidir con la
              // numeración real de la fuente (specials, offsets distintos).
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
              cover: h.type == ExtensionType.bangumi ? null : h.cover,
              coverFile: h.type == ExtensionType.bangumi && h.cover != null
                  ? File(h.cover!)
                  : null,
              headers: h.type == ExtensionType.bangumi
                  ? null
                  : _c.headersForPackage(h.package),
              onTap: () => _openDetail(h.url, h.package),
              onDelete: () => _deleteHistory(h),
              hidden: HiddenCards.isHidden(h.package, h.url),
              onToggleHide: () => HiddenCards.toggle(h.package, h.url),
            );
          }).toList();

    if (items.isEmpty) {
      final nothingAtAll = _c.resents.isEmpty && _c.favorites.isEmpty;
      // Expanded no sirve acá (el padre es un Column dentro de un scroll):
      // el ConstrainedBox de _buildBody ya fuerza el alto mínimo de
      // pantalla, así que basta con centrarse en el espacio sobrante.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: Text(
            nothingAtAll ? 'home.no-record'.i18n : 'common.no-result'.i18n,
            style: const TextStyle(color: HomeTheme.textMuted),
          ),
        ),
      );
    }

    // Sin scroll propio: ahora scrollea el contenedor de afuera junto con
    // las pestañas y el buscador (ver _buildBody) — en horizontal, con el
    // encabezado fijo al grid le quedaba tan poco alto que las tarjetas se
    // veían cortadas por abajo y no había forma de llegar a verlas enteras.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 20,
        children: items,
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: List.generate(_tabs.length, (index) {
          final selected = index == _tabIndex;
          return GestureDetector(
            onTap: () => setState(() => _tabIndex = index),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: selected
                      ? HomeTheme.accentPink.withValues(alpha: 0.18)
                      : HomeTheme.cardSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? HomeTheme.accentPink : HomeTheme.border,
                  ),
                ),
                child: Text(
                  _tabs[index].i18n,
                  style: TextStyle(
                    color:
                        selected ? HomeTheme.accentPink : HomeTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
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
              const Positioned.fill(child: AnimatedBackgroundGlow()),
              // Todo (pestañas + buscador + tarjetas) en UN solo scroll: con
              // el encabezado fijo y el grid en un Expanded, en horizontal al
              // grid le quedaban ~150px y las tarjetas se cortaban sin poder
              // llegar a verlas enteras. Así el encabezado se desplaza y las
              // tarjetas usan toda la pantalla.
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  // minHeight = alto visible: sin esto el contenido solo mide
                  // lo que ocupa (ej. el estado vacío "Sin resultados"), y el
                  // fondo con el glow quedaba cortado a media pantalla en vez
                  // de llegar hasta abajo.
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        _buildTabs(),
                        _buildSearchAndActions(),
                        _buildGrid(),
                      ],
                    ),
                  ),
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
          'home.history'.i18n,
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
                'home.history'.i18n,
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
