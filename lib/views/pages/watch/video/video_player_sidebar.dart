import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/utils/color.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/list_title.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/watch/playlist.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/watch/tutorial_reproductor.dart';
import 'package:prismhub/views/widgets/messenger.dart';

enum SidebarTab {
  episodes,
  qualitys,
  torrentFiles,
  tracks,
  servers,
  settings,
}

_sidebarTabToString(SidebarTab tab) {
  return "video.sidebar.tab.${tab.name}".i18n;
}

class VideoPlayerSidebar extends StatefulWidget {
  const VideoPlayerSidebar({
    super.key,
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  State<VideoPlayerSidebar> createState() => _VideoPlayerSidebarState();
}

class _VideoPlayerSidebarState extends State<VideoPlayerSidebar> {
  late final _c = widget.controller;

  late final Map<SidebarTab, Widget> _tabs = {
    SidebarTab.episodes: PlayList(
      title: _c.title,
      list: _c.playList.map((e) => e.name).toList(),
      selectIndex: _c.index.value,
      onChange: (value) {
        // Bloqueado mientras carga — sin esto se podía elegir otro capítulo
        // encima de uno que todavía estaba resolviendo.
        if (_c.isGettingWatchData.value) return;
        _c.index.value = value;
        _c.showSidebar.value = false;
      },
    ),
  };

  // Cada botón del footer (episodios/servidor/calidad/pistas/ajustes) abre
  // SOLO su propia lista acá — a pedido explícito, ya no comparten una tira
  // de pestañas donde servidor/episodios quedaban mezclados con pistas y
  // ajustes. reactivo a initSidebarTab: si el panel ya está abierto y se
  // toca OTRO botón del footer, cambia el contenido en vez de solo cerrar
  // (ver VideoPlayerController.toggleSideBar).
  Widget _buildAndroid(BuildContext context) {
    return Container(
      color: ThemeData.dark().colorScheme.surface,
      child: Obx(() {
        final tab = _c.initSidebarTab.value;
        final content = _tabs[tab];
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      // El panel de "servidores" tambien es el que abre el
                      // boton de calidad cuando la extension entrega una url
                      // por resolucion (Eporner). Ahi lo que se lista son
                      // calidades, asi que titularlo "Servidores disponibles"
                      // era mentir sobre lo que se esta eligiendo.
                      tab == SidebarTab.servers && !_c.servidoresSonAparte
                          ? _sidebarTabToString(SidebarTab.qualitys)
                          : _sidebarTabToString(tab),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _c.showSidebar.value = false,
                ),
              ],
            ),
            Expanded(child: content ?? const SizedBox.shrink()),
          ],
        );
      }),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return fluent.FluentTheme(
      data: fluent.FluentThemeData(
        brightness: Brightness.dark,
      ),
      child: Container(
        color: fluent.FluentThemeData.dark().micaBackgroundColor,
        child: ListView(
          padding: const EdgeInsets.all(10),
          children: [
            Row(
              children: [
                Text(
                  "common.settings".i18n,
                  style: fluent.FluentThemeData.dark().typography.bodyLarge,
                ),
                const Spacer(),
                fluent.IconButton(
                  onPressed: () {
                    _c.showSidebar.value = false;
                  },
                  icon: const Icon(fluent.FluentIcons.chrome_close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _tabs[SidebarTab.settings]!
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_c.torrentMediaFileList.isNotEmpty) {
      _tabs.addAll(
        {
          SidebarTab.torrentFiles: _TorrentFiles(
            controller: _c,
          ),
        },
      );
    }

    if (_c.qualityMap.isNotEmpty) {
      _tabs.addAll(
        {
          SidebarTab.qualitys: _QualitySelector(
            controller: _c,
          ),
        },
      );
    }

    if (_c.availableServers.isNotEmpty) {
      _tabs.addAll(
        {
          SidebarTab.servers: _ServerSelector(
            controller: _c,
          ),
        },
      );
    }

    _tabs.addAll(
      {
        SidebarTab.tracks: _TrackSelector(
          controller: _c,
        ),
        SidebarTab.settings: _SideBarSettings(
          controller: _c,
        ),
      },
    );
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}

class _SideBarSettings extends StatefulWidget {
  const _SideBarSettings({
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  State<_SideBarSettings> createState() => _SideBarSettingsState();
}

class _SideBarSettingsState extends State<_SideBarSettings> {
  late final _c = widget.controller;

  /// Deja el tutorial listo para salir la proxima vez que se abra un video.
  ///
  /// No se muestra ACA mismo a proposito. Este panel vive DENTRO del
  /// reproductor: abrirlo encima taparia el video con un tutorial que explica
  /// gestos sobre una pantalla que en ese momento esta ocupada por el propio
  /// panel. Ademas el primer paso es "toca el centro para pausar", y con el
  /// panel abierto ese toque no hace lo que dice.
  ///
  /// Marcandolo para la proxima, el tutorial sale sobre un video recien
  /// abierto, que es donde los gestos se pueden probar de verdad mientras se
  /// leen. Y sale UNA sola vez, como la primera: al cerrarlo se vuelve a
  /// marcar como visto.
  Future<void> _volverAVerTutorial(BuildContext context) async {
    await TutorialReproductor.reiniciar();
    if (!context.mounted) return;
    _c.showSidebar.value = false;
    showPlatformSnackbar(
      context: context,
      content: 'video.tutorial.will-show'.i18n,
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ver VideoPlayerController.vrUnaPantalla. Mismo interruptor que en el
        // telefono: un VR sin gafas se ve igual de mal en las dos pantallas.
        fluent.Card(
          child: Obx(
            () => Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('video.sidebar.vr-single'.i18n),
                      const SizedBox(height: 2),
                      Text(
                        'video.sidebar.vr-single-hint'.i18n,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                fluent.ToggleSwitch(
                  checked: _c.vrUnaPantalla.value,
                  onChanged: (_) => _c.alternarVrUnaPantalla(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        fluent.Card(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('video.tutorial.show-again'.i18n),
                    const SizedBox(height: 2),
                    Text(
                      'video.tutorial.show-again-hint'.i18n,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              fluent.Button(
                onPressed: () => _volverAVerTutorial(context),
                child: Text('video.tutorial.show-again-action'.i18n),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        fluent.Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('video.sidebar.subtitle.title'.i18n),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('video.sidebar.subtitle.font-size'.i18n),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Obx(
                      () => fluent.Slider(
                        value: _c.subtitleFontSize.value,
                        onChanged: (value) {
                          _c.subtitleFontSize.value = value;
                        },
                        min: 20,
                        max: 80,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Obx(
                    () => Text(
                      _c.subtitleFontSize.value.toStringAsFixed(0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('video.sidebar.subtitle.font-color'.i18n),
                  const SizedBox(width: 10),
                  fluent.SplitButton(
                    flyout: fluent.FlyoutContent(
                      constraints: const BoxConstraints(maxWidth: 200.0),
                      child: Obx(
                        () => Wrap(
                          runSpacing: 10.0,
                          spacing: 8.0,
                          children: [
                            ...ColorUtils.baseColors.map((color) {
                              return fluent.Button(
                                autofocus: _c.subtitleFontColor.value == color,
                                style: fluent.ButtonStyle(
                                  padding: WidgetStateProperty.all(
                                    const EdgeInsets.all(4.0),
                                  ),
                                ),
                                onPressed: () {
                                  _c.subtitleFontColor.value = color;
                                  Navigator.of(context).pop(color);
                                },
                                child: Container(
                                  height: 32,
                                  width: 32,
                                  color: color,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    child: Obx(
                      () => Container(
                        decoration: BoxDecoration(
                          color: _c.subtitleFontColor.value,
                          borderRadius:
                              const BorderRadiusDirectional.horizontal(
                            start: Radius.circular(4.0),
                          ),
                        ),
                        height: 32,
                        width: 36,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('video.sidebar.subtitle.background-color'.i18n),
                  const SizedBox(width: 10),
                  fluent.SplitButton(
                    flyout: fluent.FlyoutContent(
                      constraints: const BoxConstraints(maxWidth: 200.0),
                      child: Obx(
                        () => Wrap(
                          runSpacing: 10.0,
                          spacing: 8.0,
                          children: [
                            ...ColorUtils.baseColors.map((color) {
                              return fluent.Button(
                                autofocus:
                                    _c.subtitleBackgroundColor.value == color,
                                style: fluent.ButtonStyle(
                                  padding: WidgetStateProperty.all(
                                    const EdgeInsets.all(4.0),
                                  ),
                                ),
                                onPressed: () {
                                  _c.subtitleBackgroundColor.value = color;
                                  Navigator.of(context).pop(color);
                                },
                                child: Container(
                                  height: 32,
                                  width: 32,
                                  color: color,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    child: Obx(
                      () => Container(
                        decoration: BoxDecoration(
                          color: _c.subtitleBackgroundColor.value,
                          borderRadius:
                              const BorderRadiusDirectional.horizontal(
                            start: Radius.circular(4.0),
                          ),
                        ),
                        height: 32,
                        width: 36,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('video.sidebar.subtitle.background-opacity'.i18n),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Obx(
                      () => fluent.Slider(
                        value: _c.subtitleBackgroundOpacity.value,
                        onChanged: (value) {
                          _c.subtitleBackgroundOpacity.value = value;
                        },
                        min: 0,
                        max: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Obx(
                    () => Text(
                      _c.subtitleBackgroundOpacity.value.toStringAsFixed(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // textAlign
              Row(
                children: [
                  Text('video.sidebar.subtitle.text-align'.i18n),
                  const SizedBox(width: 10),
                  fluent.SplitButton(
                    flyout: fluent.FlyoutContent(
                      constraints: const BoxConstraints(maxWidth: 200.0),
                      child: Obx(
                        () => Wrap(
                          runSpacing: 10.0,
                          spacing: 8.0,
                          children: [
                            fluent.Button(
                              autofocus: _c.subtitleTextAlign.value ==
                                  TextAlign.justify,
                              style: fluent.ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.all(4.0),
                                ),
                              ),
                              onPressed: () {
                                _c.subtitleTextAlign.value = TextAlign.justify;
                                Navigator.of(context).pop(TextAlign.justify);
                              },
                              child: Container(
                                height: 32,
                                width: 32,
                                color: Colors.transparent,
                                child: const Icon(
                                  Icons.format_align_justify,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            fluent.Button(
                              autofocus:
                                  _c.subtitleTextAlign.value == TextAlign.left,
                              style: fluent.ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.all(4.0),
                                ),
                              ),
                              onPressed: () {
                                _c.subtitleTextAlign.value = TextAlign.left;
                                Navigator.of(context).pop(TextAlign.left);
                              },
                              child: Container(
                                height: 32,
                                width: 32,
                                color: Colors.transparent,
                                child: const Icon(
                                  Icons.format_align_left,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            fluent.Button(
                              autofocus:
                                  _c.subtitleTextAlign.value == TextAlign.right,
                              style: fluent.ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.all(4.0),
                                ),
                              ),
                              onPressed: () {
                                _c.subtitleTextAlign.value = TextAlign.right;
                                Navigator.of(context).pop(TextAlign.right);
                              },
                              child: Container(
                                height: 32,
                                width: 32,
                                color: Colors.transparent,
                                child: const Icon(
                                  Icons.format_align_right,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            fluent.Button(
                              autofocus: _c.subtitleTextAlign.value ==
                                  TextAlign.center,
                              style: fluent.ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.all(4.0),
                                ),
                              ),
                              onPressed: () {
                                _c.subtitleTextAlign.value = TextAlign.center;
                                Navigator.of(context).pop(TextAlign.center);
                              },
                              child: Container(
                                height: 32,
                                width: 32,
                                color: Colors.transparent,
                                child: const Icon(
                                  Icons.format_align_center,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Obx(
                      () => SizedBox(
                        height: 32,
                        width: 36,
                        child: Icon(
                          _c.subtitleTextAlign.value == TextAlign.justify
                              ? Icons.format_align_justify
                              : _c.subtitleTextAlign.value == TextAlign.left
                                  ? Icons.format_align_left
                                  : _c.subtitleTextAlign.value ==
                                          TextAlign.right
                                      ? Icons.format_align_right
                                      : Icons.format_align_center,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('video.sidebar.subtitle.font-weight'.i18n),
              const SizedBox(height: 10),
              Obx(
                () => Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    fluent.ToggleButton(
                      checked: _c.subtitleFontWeight.value == FontWeight.normal,
                      onChanged: (value) {
                        _c.subtitleFontWeight.value = FontWeight.normal;
                      },
                      child: Text(
                        'video.sidebar.subtitle.font-weight-normal'.i18n,
                      ),
                    ),
                    fluent.ToggleButton(
                      checked: _c.subtitleFontWeight.value == FontWeight.bold,
                      onChanged: (value) {
                        _c.subtitleFontWeight.value = FontWeight.bold;
                      },
                      child: Text(
                        'video.sidebar.subtitle.font-weight-bold'.i18n,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        fluent.Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('video.sidebar.play-mode.title'.i18n),
              const SizedBox(
                height: 10,
                width: double.infinity,
              ),
              Obx(
                () => Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    fluent.ToggleButton(
                      checked: _c.playMode.value == PlaylistMode.loop,
                      onChanged: (value) {
                        _c.playMode.value = PlaylistMode.loop;
                      },
                      child: Text('video.sidebar.play-mode.loop'.i18n),
                    ),
                    fluent.ToggleButton(
                      checked: _c.playMode.value == PlaylistMode.single,
                      onChanged: (value) {
                        _c.playMode.value = PlaylistMode.single;
                      },
                      child: Text('video.sidebar.play-mode.single'.i18n),
                    ),
                    fluent.ToggleButton(
                      checked: _c.playMode.value == PlaylistMode.none,
                      onChanged: (value) {
                        _c.playMode.value = PlaylistMode.none;
                      },
                      child: Text('video.sidebar.play-mode.auto-next'.i18n),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      children: [
        // Ver VideoPlayerController.vrUnaPantalla. Va primero porque cuando
        // hace falta, hace falta ANTES de poder mirar nada.
        Obx(
          () => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _c.vrUnaPantalla.value,
            onChanged: (_) => _c.alternarVrUnaPantalla(),
            title: Text('video.sidebar.vr-single'.i18n),
            subtitle: Text(
              'video.sidebar.vr-single-hint'.i18n,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.school_outlined),
          title: Text('video.tutorial.show-again'.i18n),
          subtitle: Text(
            'video.tutorial.show-again-hint'.i18n,
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => _volverAVerTutorial(context),
        ),
        const Divider(),
        Text(
          'video.sidebar.subtitle.title'.i18n,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 20),
        Text('video.sidebar.subtitle.font-size'.i18n),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Obx(
                () => SliderTheme(
                  data: SliderThemeData(
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _c.subtitleFontSize.value,
                    onChanged: (value) {
                      _c.subtitleFontSize.value = value;
                    },
                    min: 20,
                    max: 80,
                  ),
                ),
              ),
            ),
            Obx(
              () => Text(
                _c.subtitleFontSize.value.toStringAsFixed(0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('video.sidebar.subtitle.font-color'.i18n),
        const SizedBox(height: 10),
        Obx(
          () {
            final selectColor = _c.subtitleFontColor.value;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final color in ColorUtils.baseColors) ...[
                    GestureDetector(
                      onTap: () {
                        _c.subtitleFontColor.value = color;
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: selectColor == color
                              ? Border.all(
                                  color: Colors.grey,
                                  width: 2,
                                )
                              : null,
                          color: color,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                        ),
                        height: 32,
                        width: 32,
                      ),
                    ),
                    const SizedBox(width: 10)
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Text('video.sidebar.subtitle.background-color'.i18n),
        const SizedBox(height: 10),
        Obx(
          () {
            final selectColor = _c.subtitleBackgroundColor.value;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final color in ColorUtils.baseColors) ...[
                    GestureDetector(
                      onTap: () {
                        _c.subtitleBackgroundColor.value = color;
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: selectColor == color
                              ? Border.all(
                                  color: Colors.grey,
                                  width: 2,
                                )
                              : null,
                          color: color,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                        ),
                        height: 32,
                        width: 32,
                      ),
                    ),
                    const SizedBox(width: 10)
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'video.sidebar.subtitle.background-opacity'.i18n,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Obx(
                () => SliderTheme(
                  data: SliderThemeData(
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _c.subtitleBackgroundOpacity.value,
                    onChanged: (value) {
                      _c.subtitleBackgroundOpacity.value = value;
                    },
                    min: 0,
                    max: 1,
                  ),
                ),
              ),
            ),
            Obx(
              () => Text(
                _c.subtitleBackgroundOpacity.value.toStringAsFixed(2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // textAlign
        Text('video.sidebar.subtitle.text-align'.i18n),
        const SizedBox(height: 10),

        Obx(
          () => Wrap(
            children: [
              for (final align in TextAlign.values) ...[
                GestureDetector(
                  onTap: () {
                    _c.subtitleTextAlign.value = align;
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: _c.subtitleTextAlign.value == align
                          ? Border.all(
                              color: Colors.grey,
                              width: 2,
                            )
                          : null,
                      color: Colors.transparent,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(5),
                      ),
                    ),
                    height: 32,
                    width: 32,
                    child: Icon(
                      align == TextAlign.justify
                          ? Icons.format_align_justify
                          : align == TextAlign.left
                              ? Icons.format_align_left
                              : align == TextAlign.right
                                  ? Icons.format_align_right
                                  : Icons.format_align_center,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10)
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'video.sidebar.subtitle.font-weight'.i18n,
        ),
        const SizedBox(height: 10),
        Obx(
          () => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: FontWeight.normal,
                  label: Text(
                    'video.sidebar.subtitle.font-weight-normal'.i18n,
                  ),
                ),
                ButtonSegment(
                  value: FontWeight.bold,
                  label: Text(
                    'video.sidebar.subtitle.font-weight-bold'.i18n,
                  ),
                ),
              ],
              selected: <FontWeight>{_c.subtitleFontWeight.value},
              onSelectionChanged: (value) {
                _c.subtitleFontWeight.value = value.first;
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'video.sidebar.play-mode.title'.i18n,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 10),
        Obx(
          () => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: PlaylistMode.loop,
                  label: Text(
                    'video.sidebar.play-mode.loop'.i18n,
                  ),
                ),
                ButtonSegment(
                  value: PlaylistMode.single,
                  label: Text(
                    'video.sidebar.play-mode.single'.i18n,
                  ),
                ),
                ButtonSegment(
                  value: PlaylistMode.none,
                  label: Text(
                    'video.sidebar.play-mode.auto-next'.i18n,
                  ),
                ),
              ],
              selected: <PlaylistMode>{_c.playMode.value},
              onSelectionChanged: (value) {
                _c.playMode.value = value.first;
              },
            ),
          ),
        ),
      ],
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

/// Una fila de una lista donde se elige algo: calidad o servidor.
///
/// Existe para que las dos se marquen IGUAL. Estaban escritas por separado y
/// cada una marcaba lo elegido a su manera —o no lo marcaba—, así que en el
/// panel de calidad no se sabía cuál estaba puesta.
///
/// El activo lleva tres señales y no una: fondo propio, el texto en el color
/// del app y una tilde. Sobre el fondo oscuro del reproductor, un solo matiz de
/// color no se distingue.
class _FilaSeleccionable extends StatelessWidget {
  const _FilaSeleccionable({
    required this.texto,
    required this.activo,
    required this.onTap,
  });

  final String texto;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: activo
            ? HomeTheme.accentPink.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: activo
                  ? HomeTheme.accentPink
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          title: Text(
            texto,
            style: TextStyle(
              color: activo ? HomeTheme.accentPink : HomeTheme.textPrimary,
              fontWeight: activo ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          trailing: activo
              ? const Icon(Icons.check_rounded,
                  size: 18, color: HomeTheme.accentPink)
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Lo que se ve cuando una lista del panel no tiene nada.
///
/// Antes quedaba un rectangulo negro sin una palabra, que no distingue "no hay"
/// de "se rompio algo". Es el mismo caso en calidad y en servidores.
class _PanelVacio extends StatelessWidget {
  const _PanelVacio({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_clear_outlined,
                size: 34, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: HomeTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualitySelector extends StatefulWidget {
  const _QualitySelector({
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  State<_QualitySelector> createState() => _QualitySelectorState();
}

class _QualitySelectorState extends State<_QualitySelector> {
  late final _c = widget.controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => _c.qualityMap.isEmpty
          ? _PanelVacio(texto: 'video.no-qualities'.i18n)
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              children: [
                for (final quality in _c.qualityMap.entries)
                  _FilaSeleccionable(
                    texto: quality.key,
                    // currentQuality guarda la resolucion que se esta viendo, con el
                    // mismo nombre que usa el menu (ver etiquetaCalidad), asi que
                    // alcanza con compararlas.
                    activo: quality.key == _c.currentQuality.value,
                    onTap: () {
                      _c.switchQuality(quality.value);
                      _c.showSidebar.value = false;
                    },
                  ),
              ],
            ),
    );
  }
}

// Lista de servidores dentro del sidebar (celular) — a pedido explícito,
// ya no queda una tira de pestañas siempre visible tapando el video; ahora
// se abre bajo demanda con el mismo mecanismo que calidad/pistas/episodios.
class _ServerSelector extends StatelessWidget {
  const _ServerSelector({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = controller.currentServerName.value;
      if (controller.availableServers.isEmpty) {
        return _PanelVacio(texto: 'video.no-servers'.i18n);
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        children: [
          for (final entry in controller.availableServers.entries)
            // El activo se marcaba solo con `selected`, que se apoya en el
            // color de selección del tema: sobre el fondo oscuro del
            // reproductor la diferencia era casi invisible y no se sabía cuál
            // estaba puesto. Ahora lleva su propio fondo, el texto en el color
            // del app y una tilde a la derecha — tres señales en vez de un
            // matiz. Este selector es el mismo en el teléfono y en escritorio,
            // así que se ve igual en los dos.
            _FilaSeleccionable(
              texto: entry.key,
              activo: entry.key == current,
              onTap: () {
                controller.selectServer(entry.key);
                controller.showSidebar.value = false;
              },
            ),
        ],
      );
    });
  }
}

class _TrackSelector extends StatelessWidget {
  const _TrackSelector({
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        ListTitle(
          title: 'video.subtitle'.i18n,
        ),
        ListTile(
          selected:
              SubtitleTrack.no() == controller.player.state.track.subtitle,
          title: Text('common.off'.i18n),
          onTap: () {
            controller.setSubtitleTrack(
              SubtitleTrack.no(),
            );
            controller.showSidebar.value = false;
          },
        ),
        ListTile(
          title: Text('video.subtitle-file'.i18n),
          onTap: () {
            controller.addSubtitleFile();
            controller.showSidebar.value = false;
          },
        ),
        // 来自扩展的字幕
        for (final subtitle in controller.subtitles)
          ListTile(
            selected: subtitle == controller.player.state.track.subtitle,
            title: Text(subtitle.title ?? ''),
            subtitle: Text(subtitle.language ?? ''),
            onTap: () {
              controller.setSubtitleTrack(
                subtitle,
              );
              controller.showSidebar.value = false;
            },
          ),
        // 来自视频本身的字幕
        for (final subtitle in controller.player.state.tracks.subtitle)
          if (subtitle != SubtitleTrack.no() &&
              (subtitle.language != null || subtitle.title != null))
            ListTile(
              selected: subtitle == controller.player.state.track.subtitle,
              title: Text(subtitle.title ?? ''),
              subtitle: Text(subtitle.language ?? ''),
              onTap: () {
                controller.setSubtitleTrack(
                  subtitle,
                );
                controller.showSidebar.value = false;
              },
            ),
        const SizedBox(height: 10),
        ListTitle(
          title: 'video.audio'.i18n,
        ),
        const SizedBox(height: 5),
        for (final audio in controller.player.state.tracks.audio)
          if (audio.language != null || audio.title != null)
            ListTile(
              selected: audio == controller.player.state.track.audio,
              title: Text(audio.title ?? ''),
              subtitle: Text(audio.language ?? ''),
              onTap: () {
                controller.player.setAudioTrack(
                  audio,
                );
                controller.showSidebar.value = false;
              },
            ),
      ],
    );
  }
}

class _TorrentFiles extends StatelessWidget {
  const _TorrentFiles({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final file in controller.torrentMediaFileList)
          ListTile(
            selected: controller.currentTorrentFile.value == file,
            title: Text(
              file,
              style: const TextStyle(
                fontSize: 13,
              ),
            ),
            onTap: () {
              controller.playTorrentFile(file);
              controller.showSidebar.value = false;
            },
          ),
      ],
    );
  }
}
