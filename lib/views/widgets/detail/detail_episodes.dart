import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/views/widgets/detail/detail_continue_play.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/detail/detail_card_tile.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class DetailEpisodes extends StatefulWidget {
  const DetailEpisodes({
    super.key,
    this.tag,
  });
  final String? tag;

  @override
  State<DetailEpisodes> createState() => _DetailEpisodesState();
}

class _DetailEpisodesState extends State<DetailEpisodes> {
  late DetailPageController c = Get.find<DetailPageController>(tag: widget.tag);
  List<fluent.ComboBoxItem<int>>? comboBoxItems;
  List<DropdownMenuItem<int>>? dropdownItems;
  late List<ExtensionEpisodeGroup> episodes = [];
  late String listMode = PrismHubStorage.getSetting(SettingKey.listMode);
  bool isRevered = false;

  static final _numberPattern = RegExp(r'\d+(?:\.\d+)?');

  // Nombres cortos (ej. "Capítulo 8.5") nunca se truncan, no hace falta
  // tocarlos. Los largos (título completo de la serie + número) sí se
  // recortan con ellipsis en espacios angostos, y el número queda tapado.
  // Antes se anteponía la POSICIÓN en la lista (index+1) como si fuera el
  // número — rompe apenas hay un especial/capítulo no secuencial (ej.
  // "Capítulo 8.5" en la posición 9 mostraba "9." como si ese fuera el
  // número real). Ahora se extrae el número DE VERDAD desde el propio
  // nombre — si no hay ninguno, se deja el nombre tal cual (se acepta el
  // recorte antes que inventar un dato).
  String _episodeLabel(String name) {
    if (name.length <= 20) return name;
    final matches = _numberPattern.allMatches(name).toList();
    if (matches.isEmpty) return name;
    final number = matches.last.group(0)!;
    if (name.trimLeft().startsWith(number)) return name;
    return '$number. $name';
  }

  Widget _buildAndroidEpisodes(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // select 选择框
        if (episodes.isNotEmpty) ...[
          Container(
              margin: const EdgeInsets.only(left: 8, top: 5, right: 8),
              padding:
                  const EdgeInsets.only(left: 20, right: 20, top: 5, bottom: 5),
              decoration: BoxDecoration(
                // 背景颜色为 primaryContainer
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.all(
                  Radius.circular(10),
                ),
              ),
              child: DropdownButton<int>(
                // 内容为 primary 颜色
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
                isExpanded: true,
                underline: const SizedBox(),
                value: c.selectEpGroup.value,
                items: dropdownItems,
                onChanged: (value) {
                  setState(() {
                    c.selectEpGroup.value = value!;
                  });
                },
              )),
          Container(
            margin: const EdgeInsets.only(left: 16, top: 10),
            child: Row(children: [
              Text(
                FlutterI18n.translate(
                  context,
                  'detail.total-episodes',
                  translationParams: {
                    'total':
                        episodes[c.selectEpGroup.value].urls.length.toString(),
                  },
                ),
                style: const TextStyle(
                  fontSize: 18,
                ),
              ),
              Transform.flip(
                flipY: isRevered,
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      isRevered = !isRevered;
                    });
                  },
                  icon: const Icon(Icons.sort_rounded),
                ),
              )
            ]),
          )
        ],
        if (episodes.isEmpty || episodes[c.selectEpGroup.value].urls.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                c.type == ExtensionType.bangumi
                    ? 'video.no-episodes-yet'.i18n
                    : 'reader.no-chapters-yet'.i18n,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(0),
              itemCount: episodes.isEmpty
                  ? 0
                  : episodes[c.selectEpGroup.value].urls.length,
              itemBuilder: (context, index) {
                final total = episodes[c.selectEpGroup.value].urls.length;
                final name = isRevered
                    ? episodes[c.selectEpGroup.value]
                        .urls[total - 1 - index]
                        .name
                    : episodes[c.selectEpGroup.value].urls[index].name;
                return ListTile(
                  title: Text(
                    _episodeLabel(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    c.goWatch(
                      context,
                      episodes[c.selectEpGroup.value].urls,
                      isRevered
                          ? episodes[c.selectEpGroup.value].urls.length -
                              1 -
                              index
                          : index,
                      c.selectEpGroup.value,
                    );
                  },
                );
              },
            ),
          )
      ],
    );
  }

  fluent.ButtonStyle get _chipButtonStyle => fluent.ButtonStyle(
        backgroundColor: fluent.WidgetStateProperty.resolveWith((states) {
          if (states.isPressed || states.isHovered) {
            return HomeTheme.accentPink.withValues(alpha: 0.18);
          }
          return HomeTheme.cardSurface;
        }),
        foregroundColor: fluent.WidgetStateProperty.resolveWith((states) {
          if (states.isPressed || states.isHovered) {
            return HomeTheme.accentPink;
          }
          return HomeTheme.textPrimary;
        }),
        shape: fluent.WidgetStateProperty.resolveWith((states) {
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: states.isPressed || states.isHovered
                  ? HomeTheme.accentPink
                  : HomeTheme.border,
            ),
          );
        }),
      );

  Widget _buildDesktopEpisodes(BuildContext context) {
    late String episodesString;
    late String noEpisodesYetString;
    if (c.type == ExtensionType.bangumi) {
      episodesString = 'video.episodes'.i18n;
      noEpisodesYetString = 'video.no-episodes-yet'.i18n;
    } else {
      episodesString = 'reader.chapters'.i18n;
      noEpisodesYetString = 'reader.no-chapters-yet'.i18n;
    }
    final noEpisodes =
        episodes.isEmpty || episodes[c.selectEpGroup.value].urls.isEmpty;

    Widget cardTile(Widget child) {
      return DetailCardTile(
        title: episodesString,
        leading: Row(children: [
          fluent.IconButton(
            icon: Icon(
              listMode == "grid"
                  ? fluent.FluentIcons.view_list
                  : fluent.FluentIcons.grid_view_medium,
              color: HomeTheme.textPrimary,
            ),
            onPressed: () {
              setState(() {
                listMode == "grid" ? listMode = "list" : listMode = "grid";
                PrismHubStorage.setSetting(SettingKey.listMode, listMode);
              });
            },
          ),
          fluent.IconButton(
            icon: Icon(
              isRevered
                  ? fluent.FluentIcons.sort_lines_ascending
                  : fluent.FluentIcons.sort_lines,
              color: HomeTheme.textPrimary,
            ),
            onPressed: () {
              setState(() {
                isRevered = !isRevered;
                // PrismHubStorage.setSetting(SettingKey.listMode, listMode);
              });
            },
          )
        ]),
        trailing: Row(
          children: [
            DetailContinuePlay(tag: widget.tag),
            const SizedBox(width: 8),
            fluent.ComboBox<int>(
              items: comboBoxItems,
              value: c.selectEpGroup.value,
              onChanged: (value) {
                setState(() {
                  c.selectEpGroup.value = value!;
                });
              },
            )
          ],
        ),
        child: Container(
          constraints: const BoxConstraints(
            maxHeight: 500,
          ),
          child: child,
        ),
      );
    }

    if (noEpisodes) {
      // SizedBox con alto fijo y chico — antes esto pasaba por el mismo
      // Container(maxHeight: 500) que la grilla/lista con contenido real,
      // y Center se estiraba a ocupar las 500px igual, dejando un cartel
      // de una sola línea perdido en medio de un espacio enorme.
      return cardTile(
        SizedBox(
          height: 120,
          child: Center(
            child: Text(
              noEpisodesYetString,
              style: const TextStyle(color: HomeTheme.textMuted),
            ),
          ),
        ),
      );
    }

    if (listMode == "grid") {
      return cardTile(
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              reverse: isRevered,
              shrinkWrap: true,
              itemCount: episodes.isEmpty
                  ? 0
                  : episodes[c.selectEpGroup.value].urls.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (constraints.maxWidth ~/ 160).clamp(1, 20),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                // Antes 5 (celdas muy bajas/angostas) sin overflow en el
                // Text — nombres largos ("Capítulo 95.5", títulos con
                // texto) se cortaban a la mitad contra el borde del botón.
                // Con menos alto de celda + maxLines/overflow explícitos
                // en el Text de abajo, ahora se recortan prolijo (ellipsis)
                // en vez de tajarse.
                childAspectRatio: 3.4,
              ),
              itemBuilder: (context, index) {
                final name = episodes[c.selectEpGroup.value].urls[index].name;
                return fluent.Button(
                  style: _chipButtonStyle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: Text(
                        _episodeLabel(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  onPressed: () async {
                    c.goWatch(
                      context,
                      episodes[c.selectEpGroup.value].urls,
                      index,
                      c.selectEpGroup.value,
                    );
                  },
                );
              },
            );
          },
        ),
      );
    }

    return cardTile(
      ListView.builder(
        shrinkWrap: true,
        reverse: isRevered,
        padding: const EdgeInsets.all(0),
        itemCount:
            episodes.isEmpty ? 0 : episodes[c.selectEpGroup.value].urls.length,
        itemBuilder: (context, index) {
          final name = episodes[c.selectEpGroup.value].urls[index].name;
          return fluent.ListTile(
            title: Text(
              _episodeLabel(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
            onPressed: () {
              c.goWatch(
                context,
                episodes[c.selectEpGroup.value].urls,
                index,
                c.selectEpGroup.value,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      episodes = c.isLoading.value ? [] : c.detail!.episodes ?? [];
      dropdownItems = [
        for (var i = 0; i < episodes.length; i++)
          DropdownMenuItem<int>(
            value: i,
            child: Text(episodes[i].title),
          )
      ];
      comboBoxItems = [
        for (var i = 0; i < episodes.length; i++)
          fluent.ComboBoxItem<int>(
            value: i,
            child: Text(episodes[i].title),
          )
      ];
      return PlatformBuildWidget(
        androidBuilder: _buildAndroidEpisodes,
        desktopBuilder: _buildDesktopEpisodes,
      );
    });
  }
}
