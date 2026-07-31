import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';

class FavoritesPage extends fluent.StatefulWidget {
  const FavoritesPage({super.key, required this.type});
  final ExtensionType type;

  @override
  fluent.State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends fluent.State<FavoritesPage> {
  // Una sola vez (no re-fetch por tecla) — el buscador de acá adentro solo
  // filtra localmente lo que ya se cargó, mismo criterio que HistoryPage.
  late final Future<List<Favorite>> _future =
      DatabaseService.getFavoritesByType(type: widget.type);
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Favorite> _filter(List<Favorite> data) {
    if (_query.trim().isEmpty) return data;
    return data.where((f) => SearchText.matchesQuery(f.title, _query)).toList();
  }

  // Buscador nuevo — antes esta pantalla no tenía ningún campo de texto.
  // Mismo patrón visual que HistoryPage (Material TextField en Android,
  // fluent.TextBox en desktop), con botón de limpiar en los dos.
  Widget _buildSearchBox() {
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
        suffix: _query.isEmpty
            ? null
            : fluent.IconButton(
                icon:
                    const Icon(fluent.FluentIcons.chrome_close, size: 9.0),
                onPressed: () => setState(() {
                  _searchController.clear();
                  _query = '';
                }),
              ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          FlutterI18n.translate(
            context,
            "home.favorite-all",
            translationParams: {
              "type": ExtensionUtils.typeToString(widget.type).toLowerCase(),
            },
          ),
        ),
      ),
      body: FutureBuilder(
        future: _future,
        builder: ((context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text("${snapshot.error}"),
            );
          }

          if (!snapshot.hasData) {
            return const SizedBox(
              height: 300,
              child: Center(
                child: ProgressRing(),
              ),
            );
          }
          final data = snapshot.data ?? [];
          final filtered = _filter(data);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _buildSearchBox(),
              ),
              Expanded(
                child: data.isEmpty
                    ? Center(child: Text("common.no-result".i18n))
                    : filtered.isEmpty
                        ? Center(child: Text("common.no-result".i18n))
                        : LayoutBuilder(
                            builder: (context, constraints) =>
                                GridView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: constraints.maxWidth ~/ 120,
                                childAspectRatio: 0.7,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ExtensionItemCard(
                                  title: item.title,
                                  url: item.url,
                                  package: item.package,
                                  cover: item.cover,
                                );
                              },
                            ),
                          ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  FlutterI18n.translate(
                    context,
                    "home.favorite-all",
                    translationParams: {
                      "type": ExtensionUtils.typeToString(widget.type)
                          .toLowerCase(),
                    },
                  ),
                  style: fluent.FluentTheme.of(context).typography.subtitle,
                ),
              ),
              const Spacer(),
              SizedBox(width: 220, child: _buildSearchBox()),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder(
              future: _future,
              builder: ((context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      snapshot.error.toString(),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final data = snapshot.data ?? [];
                final filtered = _filter(data);

                if (data.isEmpty || filtered.isEmpty) {
                  return Center(
                    child: Text("common.no-result".i18n),
                  );
                }

                return LayoutBuilder(
                  builder: ((context, constraints) => GridView.builder(
                        padding:
                            const EdgeInsets.only(right: 8, bottom: 8, top: 8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: constraints.maxWidth ~/ 160,
                          childAspectRatio: 0.6,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ExtensionItemCard(
                            title: item.title,
                            url: item.url,
                            package: item.package,
                            cover: item.cover,
                          );
                        },
                      )),
                );
              }),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
