import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/views/pages/search/extension_searcher_page.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/refresh_button.dart';
import 'package:prismhub/views/widgets/search/search_all_extension.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/search_appbar.dart';

// Mismo lenguaje visual que Home/Historial (HomeTheme: fondo oscuro, chips
// redondeados en vez de tabs/toggle buttons por defecto, caja de búsqueda
// oscura). HorizontalList/ExtensionItemCard/SearchAllTile NO se tocan acá —
// son compartidos con otras páginas (ver comentario histórico en
// home_section.dart), esto solo restila el marco propio de esta página.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late SearchPageController c;
  final _searchController = TextEditingController();

  // "Lectura" agrupa manga+novela — de cara al usuario es una sola
  // categoría (ambos son texto para leer), aunque internamente sigan
  // siendo tipos distintos (el lector usa una UI distinta para cada uno).
  // videoTypes/readingTypes viven en ExtensionUtils (único lugar) — antes
  // este mismo set estaba duplicado acá y en extension_repo_page.dart.
  static const _types = <Set<ExtensionType>?>[
    null,
    ExtensionUtils.videoTypes,
    ExtensionUtils.readingTypes,
  ];
  static const _typeLabels = [
    'search.all',
    'extension-type.video',
    'extension-type.reading'
  ];

  @override
  void initState() {
    // Reusa el controller si ya existe (mismo patrón que HomePageController)
    // — antes Get.put() creaba uno NUEVO cada vez que se reentraba a esta
    // pestaña, tirando a la basura todos los resultados ya cargados: volver
    // a Buscar (o, en Android, cambiar de pestaña y volver) hacía que TODAS
    // las extensiones parpadearan de nuevo a "cargando" sin importar los
    // fixes de getRuntime()/getResult() — esos solo evitan el parpadeo
    // DENTRO de la misma instancia del controller, no entre instancias.
    c = Get.isRegistered<SearchPageController>()
        ? Get.find<SearchPageController>()
        : Get.put(SearchPageController());
    c.isPageOpen = true;
    if (c.needRefresh) {
      c.getRuntime();
    }
    _searchController.text = c.search.value;
    super.initState();
  }

  @override
  void dispose() {
    c.isPageOpen = false;
    _searchController.dispose();
    super.dispose();
  }

  Widget _chip(int index) {
    return Obx(() {
      final type = _types[index];
      final selected = c.cuurentExtensionType.value == type;
      return GestureDetector(
        onTap: () => c.getRuntime(types: type),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
              _typeLabels[index].i18n,
              style: TextStyle(
                color: selected ? HomeTheme.accentPink : HomeTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    });
  }

  // Versión Android: ancho completo, centrada, se puede envolver a una
  // segunda línea (no hay nada más en esa fila).
  Widget _buildTypeChips() {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: List.generate(_types.length, _chip),
      ),
    );
  }

  // Versión Desktop: en una sola línea siempre, con scroll horizontal en vez
  // de envolver — así nunca "salta" de tamaño ni empuja al buscador (que
  // queda fijo a la derecha en la misma fila).
  Widget _buildTypeChipsScrollable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _types.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _chip(i),
          ],
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Obx(() {
      // Altura reservada SIEMPRE (barra 3px + padding 8px), incluso oculta
      // (antes SizedBox.shrink, altura 0) — sin esto, al tocar un chip de
      // tipo la lista se reinicia, la barra aparece de golpe y empuja los
      // chips/resultados hacia abajo; al terminar de cargar desaparece y
      // todo "rebota" de nuevo a su posición original. Con la altura fija,
      // solo cambia la opacidad, nunca el layout de abajo.
      final total = c.searchResultList.length;
      final loading = c.finishCount != total;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 3,
          child: Opacity(
            opacity: loading ? 1 : 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: total == 0 ? null : c.finishCount / total,
                minHeight: 3,
                backgroundColor: HomeTheme.border,
                valueColor: const AlwaysStoppedAnimation(HomeTheme.accentPink),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildResults(void Function(int) onClickMore) {
    return Obx(() {
      // ignore: invalid_use_of_protected_member
      final list = c.searchResultList.value;
      // Antes tenía un ValueKey(search + tipo) — cambiar de chip o
      // escribir/borrar en el buscador generaba una key distinta, y eso
      // fuerza a Flutter a DESTRUIR y RECONSTRUIR desde cero todo el árbol
      // de SearchAllExtSearch (cada SearchAllTile, su HorizontalList con su
      // propio ScrollController, cada imagen). SearchAllExtSearch no tiene
      // ningún estado propio que dependa de esa key (todo sale de
      // runtimeList) — clickear los chips varias veces seguido apilaba
      // reconstrucciones completas más rápido de lo que el hilo de UI podía
      // procesarlas, sintiéndose como tirones/traba. Sin key, Flutter solo
      // actualiza las props del mismo widget en vez de recrearlo entero.
      return SearchAllExtSearch(
        kw: c.search.value,
        runtimeList: list,
        onClickMore: onClickMore,
      );
    });
  }

  Widget _buildAndroidSearch(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      // El teclado se superpone en vez de encoger el body: el campo de
      // búsqueda vive en la AppBar (arriba), así que sigue visible igual, y
      // sin esto en horizontal el body se achicaba tanto que las partes
      // fijas (progreso + chips) ya no entraban y desbordaban.
      resizeToAvoidBottomInset: false,
      appBar: SearchAppBar(
        textEditingController: _searchController,
        onChanged: (value) {
          if (value.isEmpty) c.search.value = '';
        },
        onSubmitted: (value) => c.search.value = value,
        hintText: "search.hint-text".i18n,
        title: "common.search".i18n,
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            c.getRuntime(types: c.cuurentExtensionType.value),
        color: HomeTheme.accentPink,
        backgroundColor: HomeTheme.cardSurface,
        child: Container(
          color: HomeTheme.bg,
          child: Stack(
            children: [
              const Positioned.fill(child: AnimatedBackgroundGlow()),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProgress(),
                        _buildTypeChips(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _buildResults((index) {
                      Get.to(ExtensionSearcherPage(
                        package: c.getPackgeByIndex(index),
                        keyWord: c.search.value,
                      ));
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSearch(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'common.search'.i18n,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: HomeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildProgress(),
                    // Fila fija en una sola línea: buscador siempre pegado
                    // a la derecha como en el diseño original. Los chips ya
                    // no usan Wrap (eso hacía que "Lectura" se cortara a una
                    // segunda línea suelta al elegir "Vídeo") — ahora
                    // scrollean horizontal si no entran, nunca cambian de
                    // alto ni empujan al resto. Un VerticalDivider separa
                    // visualmente el grupo de filtros del de acciones.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _buildTypeChipsScrollable()),
                        const SizedBox(width: 16),
                        const SizedBox(
                          height: 32,
                          child: VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: HomeTheme.border,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          height: 40,
                          child: RefreshButton(
                            onTap: () async => c.getRuntime(
                                types: c.cuurentExtensionType.value),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 300,
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: HomeTheme.cardSurface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: HomeTheme.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search,
                                  size: 18, color: HomeTheme.textMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: fluent.TextBox(
                                  controller: _searchController,
                                  placeholder: "search.hint-text".i18n,
                                  decoration: const WidgetStatePropertyAll(
                                      BoxDecoration()),
                                  style: const TextStyle(
                                      color: HomeTheme.textPrimary,
                                      fontSize: 14),
                                  placeholderStyle: const TextStyle(
                                      color: HomeTheme.textMuted),
                                  onChanged: (value) {
                                    if (value.isEmpty) c.search.value = '';
                                  },
                                  onSubmitted: (value) =>
                                      c.search.value = value,
                                  suffix: fluent.IconButton(
                                    icon: const Icon(
                                        fluent.FluentIcons.chrome_close,
                                        size: 9.0),
                                    onPressed: () {
                                      _searchController.clear();
                                      c.search.value = '';
                                    },
                                  ),
                                  suffixMode:
                                      fluent.OverlayVisibilityMode.editing,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildResults((index) {
                  router.push(Uri(
                    path: "/search_extension",
                    queryParameters: {
                      "package": c.getPackgeByIndex(index),
                      "keyWord": c.search.value,
                    },
                  ).toString());
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroidSearch,
      desktopBuilder: _buildDesktopSearch,
    );
  }
}
