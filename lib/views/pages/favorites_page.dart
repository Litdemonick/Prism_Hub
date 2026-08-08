import 'dart:io';
import 'dart:math' as math;
import 'package:get/get.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/franja_de_zona.dart';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class FavoritesPage extends fluent.StatefulWidget {
  const FavoritesPage({super.key, required this.type});
  final ExtensionType type;

  @override
  fluent.State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends fluent.State<FavoritesPage> {
  // ── La lista se relee, no se pide una sola vez ─────────────────────────
  //
  // Era un Future creado en el estado, o sea una lectura y nada más. Alcanzaba
  // mientras la pantalla solo mostraba: ahora desde acá se puede quitar de
  // favoritos y ocultar una tarjeta, y con el Future clavado la tarjeta que
  // acababas de quitar seguía ahí hasta salir y volver a entrar.
  List<Favorite>? _datos;

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _leer();
  }

  Future<void> _leer() async {
    final datos = await DatabaseService.getFavoritesByType(type: widget.type);
    if (!mounted) return;
    setState(() => _datos = datos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _quitar(Favorite f) async {
    await DatabaseService.deleteFavorite(f.package, f.url);
    await _leer();
  }

  void _abrir(Favorite f) {
    ExtensionUtils.openExtensionDetail(
      context,
      package: f.package,
      url: f.url,
      cover: f.cover,
    );
  }

  Map<String, String>? _cabeceras(String package) {
    final sitio = ExtensionUtils.runtimes[package]?.extension.webSite;
    if (sitio == null || sitio.isEmpty) return null;
    return {'Referer': sitio};
  }

  /// Una tarjeta de favorito, la misma que usan el Inicio y el Historial.
  ///
  /// Antes acá iba una tarjeta chica y distinta, sin menú de tres puntos: no se
  /// podía quitar de favoritos, ni ocultar, ni abrir la ficha desde el menú, y
  /// se veía más chica que la misma obra en cualquier otra pantalla.
  Widget _tarjeta(Favorite f, double ancho) {
    return HomeMediaCard(
      key: ValueKey('fav-${f.package}-${f.url}'),
      ancho: ancho,
      title: f.title,
      subtitle: 'home.favorite'.i18n,
      type: f.type,
      cover: f.cover,
      headers: _cabeceras(f.package),
      onTap: () => _abrir(f),
      onVerDetalle: () => _abrir(f),
      onDelete: () => _quitar(f),
      esFavorito: true,
      onAlternarFavorito: () => _quitar(f),
      hidden: HiddenCards.isHidden(f.package, f.url),
      onToggleHide: () => HiddenCards.toggle(f.package, f.url),
    );
  }

  /// La grilla, con las tarjetas llenando su celda.
  ///
  /// Misma cuenta que el Historial: se cuentan las columnas que entran, se
  /// reparte el ancho disponible y ese es el que recibe la tarjeta. Con el
  /// ancho fijo de antes quedaba aire a los costados de cada una y las
  /// portadas se veían chicas sin motivo.
  /// La misma grilla, pero como sliver: en Android va dentro de un
  /// CustomScrollView junto con la franja del título.
  Widget _grillaSliver(List<Favorite> lista) {
    final anchoTarjeta = Platform.isAndroid
        ? HomeMediaCard.androidWidth
        : HomeMediaCard.desktopWidth;
    final altoTarjeta = (Platform.isAndroid
            ? HomeMediaCard.androidHeight
            : HomeMediaCard.desktopHeight) +
        70;
    return SliverLayoutBuilder(builder: (context, cons) {
      const margen = 16.0;
      const entre = 16.0;
      final disponible = cons.crossAxisExtent - margen * 2;
      final columnas =
          math.max(1, ((disponible + entre) / (anchoTarjeta + entre)).floor());
      final ancho = (disponible - entre * (columnas - 1)) / columnas;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(
          margen,
          0,
          margen,
          MediaQuery.paddingOf(context).bottom + margen,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            mainAxisExtent: ancho * (altoTarjeta / anchoTarjeta),
            crossAxisSpacing: entre,
            mainAxisSpacing: 20,
          ),
          delegate: SliverChildBuilderDelegate(
            // Obx: el conjunto de tarjetas ocultas es reactivo, y sin esto
            // ocultarla no repintaba nada hasta salir y volver.
            (context, i) => Obx(() => _tarjeta(lista[i], ancho)),
            childCount: lista.length,
          ),
        ),
      );
    });
  }

  Widget _grilla(List<Favorite> lista, [double arriba = 0]) {
    final anchoTarjeta = Platform.isAndroid
        ? HomeMediaCard.androidWidth
        : HomeMediaCard.desktopWidth;
    final altoTarjeta = (Platform.isAndroid
            ? HomeMediaCard.androidHeight
            : HomeMediaCard.desktopHeight) +
        70;
    return LayoutBuilder(builder: (context, cons) {
      const margen = 16.0;
      const entre = 16.0;
      final disponible = cons.maxWidth - margen * 2;
      final columnas =
          math.max(1, ((disponible + entre) / (anchoTarjeta + entre)).floor());
      final ancho = (disponible - entre * (columnas - 1)) / columnas;
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(margen, arriba, margen, margen),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnas,
          mainAxisExtent: ancho * (altoTarjeta / anchoTarjeta),
          crossAxisSpacing: entre,
          mainAxisSpacing: 20,
        ),
        itemCount: lista.length,
        // Obx: el conjunto de tarjetas ocultas es reactivo, y sin esto
        // ocultarla no repintaba nada hasta salir y volver.
        itemBuilder: (context, i) => Obx(() => _tarjeta(lista[i], ancho)),
      );
    });
  }

  /// Los bloques que brillan, con la misma forma que la grilla de arriba.
  Widget _esperando([double arriba = 0]) {
    final anchoTarjeta = Platform.isAndroid
        ? HomeMediaCard.androidWidth
        : HomeMediaCard.desktopWidth;
    final altoTarjeta = (Platform.isAndroid
            ? HomeMediaCard.androidHeight
            : HomeMediaCard.desktopHeight) +
        70;
    return LayoutBuilder(builder: (context, cons) {
      final columnas = math.max(
          1, ((cons.maxWidth - 32 + 16) / (anchoTarjeta + 16)).floor());
      return EsqueletoDeGrilla(
        columnas: columnas,
        proporcion: anchoTarjeta / altoTarjeta,
        padding: EdgeInsets.fromLTRB(16, arriba, 16, 16),
      );
    });
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

  Widget _buildAndroid(BuildContext context) {
    final titulo = FlutterI18n.translate(
      context,
      "home.favorite-all",
      translationParams: {
        "type": ExtensionUtils.typeToString(widget.type).toLowerCase(),
      },
    );
    final datos = _datos;
    final filtrados = datos == null ? const <Favorite>[] : _filter(datos);

    return Scaffold(
      backgroundColor: HomeTheme.bg,
      // Sin AppBar: la franja fina, igual que el Historial, Buscar y
      // Extensiones. Y el buscador vive DENTRO de ella, así que se va la fila
      // que ocupaba debajo del título.
      // La franja va DENTRO del desplazamiento, como primer trozo: se va con
      // las tarjetas al bajar y vuelve al subir, igual que el nombre de la app
      // en el Inicio. Ver la nota en franja_de_zona.dart.
      body: RefreshIndicator(
        onRefresh: _leer,
        color: HomeTheme.accentPink,
        backgroundColor: HomeTheme.cardSurface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: FranjaDeZona(
                titulo: titulo,
                ayuda: 'common.search'.i18n,
                controlador: _searchController,
                alEscribir: (v) => setState(() => _query = v),
                alEnviar: (v) => setState(() => _query = v),
                // Se abre encima del shell, así que necesita su propia salida.
                alVolver: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
            if (datos == null)
              // Bloques mientras se lee la base. Vacío por «todavía no
              // pregunté» se ve igual que vacío por «no hay nada», y sin
              // distinguirlos salía «no hay resultados» con la lista llena.
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height,
                  child: _esperando(),
                ),
              )
            else if (filtrados.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 260,
                  child: Center(
                    child: Text(
                      "common.no-result".i18n,
                      style: const TextStyle(color: HomeTheme.textMuted),
                    ),
                  ),
                ),
              )
            else
              _grillaSliver(filtrados),
          ],
        ),
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
            child: Builder(builder: (context) {
              final datos = _datos;
              // Bloques mientras se lee la base, igual que en Android: vacío
              // por «todavía no pregunté» se ve igual que vacío por «no hay
              // nada», y sin distinguirlos salía «no hay resultados» con la
              // lista llena.
              if (datos == null) return _esperando();
              final filtrados = _filter(datos);
              if (filtrados.isEmpty) {
                return Center(
                  child: Text(
                    "common.no-result".i18n,
                    style: const TextStyle(color: HomeTheme.textMuted),
                  ),
                );
              }
              return _grilla(filtrados);
            }),
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
