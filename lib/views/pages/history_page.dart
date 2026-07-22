import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/views/widgets/history/history_item_card.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

// "Ver todo" destination for Home's Continuar section — one place with
// every history/favorite item, filterable by tab, searchable by title, and
// deletable one-by-one (visible trash icon) or all at once (no right-click
// needed for either).
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late final _c = Get.find<HomePageController>();
  late final TabController _tabController = TabController(
    length: 5,
    vsync: this,
    initialIndex: widget.initialTab,
  )..addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  ExtensionType? get _typeFilter {
    switch (_tabController.index) {
      case 1:
        return ExtensionType.bangumi;
      case 2:
        return ExtensionType.manga;
      case 3:
        return ExtensionType.fikushon;
      default:
        return null;
    }
  }

  bool get _onFavoritesTab => _tabController.index == 4;

  List<History> _filteredHistory() {
    final type = _typeFilter;
    final q = _query.trim().toLowerCase();
    return _c.resents.where((h) {
      if (type != null && h.type != type) return false;
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
      Get.to(DetailPage(url: url, package: package));
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
        content: Text('home.clear-history-confirm'.i18n),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.i18n),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.delete-all'.i18n),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_onFavoritesTab) {
      await DatabaseService.deleteFavoritesByType(null);
    } else {
      await DatabaseService.deleteHistoryByType(_typeFilter);
    }
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  Widget _buildGrid() {
    final items = _onFavoritesTab
        ? _filteredFavorites().map((f) {
            return HistoryItemCard(
              key: ValueKey('fav-${f.package}-${f.url}'),
              title: f.title,
              cover: f.cover,
              onTap: () => _openDetail(f.url, f.package),
              onDelete: () => _deleteFavorite(f),
            );
          }).toList()
        : _filteredHistory().map((h) {
            return HistoryItemCard(
              key: ValueKey('hist-${h.package}-${h.url}'),
              title: h.title,
              cover: h.cover,
              isLocalCover: h.type == ExtensionType.bangumi,
              subtitle: FlutterI18n.translate(
                context,
                'home.watched',
                translationParams: {'ep': h.episodeTitle},
              ),
              onTap: () => _openDetail(h.url, h.package),
              onDelete: () => _deleteHistory(h),
            );
          }).toList();

    if (items.isEmpty) {
      final nothingAtAll = _c.resents.isEmpty && _c.favorites.isEmpty;
      return Center(
        child: Text(nothingAtAll ? 'home.no-record'.i18n : 'common.no-result'.i18n),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (constraints.maxWidth ~/ 160).clamp(2, 20),
          childAspectRatio: 0.62,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => items[index],
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabs: [
        Tab(text: 'search.all'.i18n),
        Tab(text: 'extension-type.video'.i18n),
        Tab(text: 'extension-type.comic'.i18n),
        Tab(text: 'extension-type.novel'.i18n),
        Tab(text: 'home.favorite'.i18n),
      ],
    );
  }

  Widget _buildSearchBox() {
    if (Platform.isAndroid) {
      return TextField(
        controller: _searchController,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: 'common.search'.i18n,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => setState(() => _query = value),
      );
    }
    // Desktop runs on fluent_ui, not Material — there's no Material ancestor
    // for a plain TextField to find, so it must be a fluent.TextBox here.
    return fluent.TextBox(
      controller: _searchController,
      placeholder: 'common.search'.i18n,
      prefix: const Padding(
        padding: EdgeInsets.only(left: 8),
        child: Icon(fluent.FluentIcons.search, size: 16),
      ),
      onChanged: (value) => setState(() => _query = value),
    );
  }

  Widget _buildSearchAndActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildSearchBox()),
          const SizedBox(width: 8),
          if (Platform.isAndroid)
            TextButton(
              onPressed: _confirmClearAll,
              child: Text('common.delete-all'.i18n),
            )
          else
            fluent.Button(
              onPressed: _confirmClearAll,
              child: Text('common.delete-all'.i18n),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Obx(
      () => Column(
        children: [
          _buildTabs(),
          _buildSearchAndActions(),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('home.history'.i18n)),
      body: _buildBody(),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'home.history'.i18n,
              style: fluent.FluentTheme.of(context).typography.subtitle,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
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
