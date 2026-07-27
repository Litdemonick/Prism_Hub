import 'package:easy_refresh/easy_refresh.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_repo_controller.dart';
import 'package:prismhub/views/widgets/extension/extension_card.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';
import 'package:prismhub/views/widgets/search_appbar.dart';

class ExtensionRepoPage extends StatefulWidget {
  const ExtensionRepoPage({super.key});

  @override
  State<ExtensionRepoPage> createState() => _ExtensionRepoPageState();
}

class _ExtensionRepoPageState extends State<ExtensionRepoPage> {
  late ExtensionRepoPageController c;

  // Alias a ExtensionUtils.videoTypes/readingTypes (único lugar con esta
  // regla ahora — antes estaba duplicada acá Y en search_page.dart). Se
  // mantienen estos nombres locales porque el resto del archivo los usa
  // para pattern-matching por identidad de Set más abajo; al ser el MISMO
  // const canonicalizado que expone ExtensionUtils, la identidad se
  // conserva igual.
  static const _videoTypes = ExtensionUtils.videoTypes;
  static const _readingTypes = ExtensionUtils.readingTypes;

  @override
  void initState() {
    c = Get.put(ExtensionRepoPageController());
    super.initState();
  }

  // 筛选 dialog
  _filterDialog() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Obx(
                  () => SegmentedButton<Set<ExtensionType>?>(
                    segments: [
                      ButtonSegment(
                        value: null,
                        label: Text('common.show-all'.i18n),
                      ),
                      ButtonSegment(
                        value: _videoTypes,
                        label: Text('extension-type.video'.i18n),
                      ),
                      ButtonSegment(
                        value: _readingTypes,
                        label: Text('extension-type.reading'.i18n),
                      ),
                    ],
                    selected: <Set<ExtensionType>?>{c.searchType.value},
                    onSelectionChanged: (value) {
                      debugPrint(value.first.toString());
                      c.searchType.value = value.first;
                      Get.back();
                    },
                    showSelectedIcon: false,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _content() {
    if (c.isLoading.value) {
      return const Center(child: ProgressRing());
    }
    if (c.isError.value) {
      return Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('extension-repo.error'.i18n),
          const SizedBox(height: 8),
          fluent.Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'extension-repo.error-tips'.i18n,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 13),
          PlatformFilledButton(
            child: Text('common.retry'.i18n),
            onPressed: () {
              c.onRefresh();
            },
          )
        ],
      ));
    }

    final extensionCards = c.extensions
        .where((e) =>
            e['package'] != null &&
            e['name'] != null &&
            e['version'] != null &&
            e['lang'] != null)
        .map((e) {
      final type = ExtensionType.values.firstWhere(
        (element) => element.toString() == 'ExtensionType.${e['type']}',
        orElse: () => ExtensionType.bangumi,
      );
      return ExtensionCard(
          key: ValueKey(e['package']),
          name: e['name'] ?? '',
          icon: e['icon'],
          version: e['version'] ?? '',
          package: e['package'] ?? '',
          lang: e['lang'] ?? 'all',
          // El catálogo de prism+ trae la URL del bundle en `script`;
          // repos antiguos usaban `url`. Soportar ambos.
          url: e['script'] ?? e['url'],
          webSite: e['webSite'],
          license: e['license'],
          description: e['description'],
          // Firma Ed25519 de prism+ — la card verifica antes de instalar.
          signature: e['signature'],
          nsfw: e['nsfw'] == 'true' || e['nsfw'] == true,
          unstable: e['unstable'] == 'true' || e['unstable'] == true,
          type: type);
    }).toList();
    // 过滤
    if (c.search.value.isNotEmpty) {
      extensionCards.removeWhere((element) =>
          !element.name.toLowerCase().contains(c.search.value.toLowerCase()));
    }
    if (c.searchType.value != null) {
      extensionCards.removeWhere(
        (element) => !c.searchType.value!.contains(element.type),
      );
    }
    if (c.searchLang.value != 'all') {
      extensionCards.removeWhere(
        (element) => element.lang != c.searchLang.value,
      );
    }

    if (extensionCards.isEmpty) {
      return Center(child: Text('extension-repo.empty'.i18n));
    }

    // Instaladas primero, agrupadas aparte — antes quedaban mezcladas en
    // cualquier orden con las que ni siquiera están instaladas, obligando a
    // buscar entre todas para ver qué ya tenés.
    final installedCards = extensionCards
        .where((e) => ExtensionUtils.runtimes.containsKey(e.package))
        .toList();
    final availableCards = extensionCards
        .where((e) => !ExtensionUtils.runtimes.containsKey(e.package))
        .toList();
    final showSections = installedCards.isNotEmpty && availableCards.isNotEmpty;

    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        );

    return PlatformBuildWidget(
      androidBuilder: (context) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (showSections) sectionTitle('extension-repo.installed'.i18n),
          ...installedCards,
          if (showSections) sectionTitle('extension-repo.available'.i18n),
          ...availableCards,
        ],
      ),
      // Wrap centrado en vez de GridView.count con columnas fijas: con pocas
      // extensiones (ej. una sola en "Disponibles") el grid viejo las dejaba
      // pegadas arriba a la izquierda con todo el resto de la ventana vacío
      // — Wrap las centra como grupo, y sigue reflowando en varias filas sin
      // desbordar cuando se van agregando muchas más (no hace falta calcular
      // columnas a mano).
      desktopBuilder: (context) {
        Widget grid(List<Widget> cards) => Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final card in cards) SizedBox(width: 220, child: card),
              ],
            );
        // padding a la derecha: en desktop Flutter dibuja el scrollbar
        // pegado al borde del propio Scrollable — sin este margen quedaba
        // encima de la última columna de cards (confirmado en vivo). Abajo,
        // espacio para poder scrollear un poco más allá de la última fila
        // en vez de que quede justo pegada al borde inferior.
        const scrollPadding = EdgeInsets.only(right: 16, bottom: 24);
        if (!showSections) {
          return SingleChildScrollView(
            padding: scrollPadding,
            child: grid(installedCards + availableCards),
          );
        }
        return SingleChildScrollView(
          padding: scrollPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle('extension-repo.installed'.i18n),
              grid(installedCards),
              const SizedBox(height: 24),
              sectionTitle('extension-repo.available'.i18n),
              grid(availableCards),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: HomeTheme.bg,
        // Buscador en la AppBar (arriba): el teclado se superpone en vez de
        // encoger el body, si no en horizontal la lista se queda sin alto y
        // desborda.
        resizeToAvoidBottomInset: false,
        appBar: SearchAppBar(
          title: 'common.extension-repo'.i18n,
          textEditingController: TextEditingController(text: c.search.value),
          onSubmitted: (value) {
            c.search.value = value;
          },
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () {
                _filterDialog();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            EasyRefresh(
              onRefresh: c.onRefresh,
              header: const ClassicHeader(
                showText: false,
                showMessage: false,
              ),
              child: Obx(_content),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Column(
              children: [
                // Wrap en vez de Row+Spacer: en ventana angosta (PC modo
                // chiquito) el título + los 2 combos + el buscador de 200px no
                // entraban en una sola línea y tiraban un RenderFlex overflow
                // arriba de todo — confirmado en vivo. Wrap baja la barra de
                // controles a una segunda línea en vez de desbordar.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 12,
                  children: [
                    Text(
                      'common.extension-repo'.i18n,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Antes cada control (combo/buscador/refresh) quedaba como una
                    // caja plana suelta, sin relación visual con el resto de la
                    // app — agrupados en una sola superficie con el mismo estilo
                    // de las tarjetas de abajo, se lee como una sola barra en vez
                    // de piezas sueltas.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: HomeTheme.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HomeTheme.border),
                      ),
                      child: Row(
                        children: [
                          Obx(
                            () => fluent.ComboBox<String>(
                              items: [
                                fluent.ComboBoxItem(
                                    value: 'all',
                                    child: Text('common.show-all'.i18n)),
                                const fluent.ComboBoxItem(
                                    value: 'en', child: Text('English')),
                                const fluent.ComboBoxItem(
                                    value: 'es', child: Text('Español')),
                                const fluent.ComboBoxItem(
                                    value: 'zh', child: Text('中文')),
                                const fluent.ComboBoxItem(
                                    value: 'ja', child: Text('日本語')),
                                const fluent.ComboBoxItem(
                                    value: 'ko', child: Text('한국어')),
                                const fluent.ComboBoxItem(
                                    value: 'hi', child: Text('हिन्दी')),
                                const fluent.ComboBoxItem(
                                    value: 'ru', child: Text('Русский')),
                              ],
                              value: c.searchLang.value,
                              onChanged: (value) {
                                c.searchLang.value = value ?? 'all';
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Obx(
                            () => fluent.ComboBox<String>(
                              items: [
                                fluent.ComboBoxItem(
                                  value: "all",
                                  child: Text('common.show-all'.i18n),
                                ),
                                fluent.ComboBoxItem(
                                  value: "video",
                                  child: Text('extension-type.video'.i18n),
                                ),
                                fluent.ComboBoxItem(
                                  value: "reading",
                                  child: Text('extension-type.reading'.i18n),
                                ),
                              ],
                              value: switch (c.searchType.value) {
                                null => "all",
                                _videoTypes => "video",
                                _readingTypes => "reading",
                                _ => "all",
                              },
                              onChanged: (value) {
                                c.searchType.value = switch (value) {
                                  "video" => _videoTypes,
                                  "reading" => _readingTypes,
                                  _ => null,
                                };
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 200,
                            child: Obx(
                              () => fluent.TextBox(
                                controller:
                                    TextEditingController(text: c.search.value),
                                placeholder: 'common.search'.i18n,
                                onChanged: (value) {
                                  if (value.isEmpty) {
                                    c.onRefresh();
                                    c.search.value = '';
                                  }
                                },
                                onSubmitted: (value) {
                                  c.search.value = value;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          fluent.IconButton(
                            icon: const Icon(fluent.FluentIcons.refresh),
                            onPressed: () {
                              c.onRefresh();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Obx(_content),
                ),
              ],
            ),
          ),
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
