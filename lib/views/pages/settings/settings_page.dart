import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/providers/tmdb_provider.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/controllers/extension/extension_repo_controller.dart';
import 'package:prismhub/controllers/settings_controller.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_pin_settings_tile.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_zone_page.dart';
import 'package:prismhub/views/widgets/settings/settings_expander_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_input_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_radios_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_switch_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_numberbox_button.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/list_title.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tmdb_api/tmdb_api.dart';
import 'package:url_launcher/url_launcher.dart';

// El repo por defecto se guarda con "https://" adelante — mostrarlo/editarlo
// así en el campo de texto era frágil (había que dejar el prefijo intacto
// para no perder el esquema, y confirmar cada tecla — ver onChanged más
// abajo — disparaba un fetch de red con el valor a medio escribir, lo que se
// veía como el programa "bugueando"). Se muestra/edita solo la parte directa
// (dominio + ruta) y se reconstruye el esquema completo al guardar.
String _stripUrlScheme(String url) =>
    url.replaceFirst(RegExp(r'^https?://'), '');
String _withUrlScheme(String value) {
  final v = value.trim();
  if (v.isEmpty || v.startsWith('http://') || v.startsWith('https://')) {
    return v;
  }
  return 'https://$v';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsController c;

  @override
  void initState() {
    c = Get.put(SettingsController());
    super.initState();
  }

  List<Widget> _buildContent() {
    return [
      if (!Platform.isAndroid) ...[
        Text(
          'common.settings'.i18n,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: HomeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
      ],
      // 常规设置
      SettingsExpanderTile(
        icon: fluent.FluentIcons.developer_tools,
        androidIcon: Icons.construction,
        title: 'settings.general'.i18n,
        subTitle: 'settings.general-subtitle'.i18n,
        content: Column(
          children: [
            // TMDB KEY 设置
            SettingsIntpuTile(
              title: 'settings.tmdb-key'.i18n,
              buildSubtitle: () {
                if (!Platform.isAndroid) {
                  return 'settings.tmdb-key-subtitle'.i18n;
                }
                final key =
                    PrismHubStorage.getSetting(SettingKey.tmdbKey) as String;
                if (key.isEmpty) {
                  return 'common.unset'.i18n;
                }
                // 替换为*号
                return key.replaceAll(RegExp(r"."), '*');
              },
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.tmdbKey, value);
                TmdbApi.tmdb = TMDB(
                  ApiKeys(value, ''),
                  defaultLanguage:
                      PrismHubStorage.getSetting(SettingKey.language),
                );
              },
              buildText: () {
                return PrismHubStorage.getSetting(SettingKey.tmdbKey);
              },
            ),
            // 语言设置
            SettingsRadiosTile(
              title: 'settings.language'.i18n,
              itemNameValue: {
                'languages.en'.i18n: 'en',
                'languages.es'.i18n: 'es',
              },
              buildSubtitle: () => 'settings.language-subtitle'.i18n,
              applyValue: (value) {
                PrismHubStorage.setSetting(SettingKey.language, value);
                I18nUtils.changeLanguage(value);
              },
              buildGroupValue: () {
                // Validado, no crudo: si quedó guardado un idioma que ya no
                // existe, esto devuelve el de respaldo y el selector marca
                // algo, en vez de quedar sin ninguna opción elegida.
                return I18nUtils.currentLanguageCode;
              },
            ),
            // 启动检查更新
            SettingsSwitchTile(
              title: 'settings.auto-check-update'.i18n,
              buildSubtitle: () => 'settings.auto-check-update-subtitle'.i18n,
              buildValue: () =>
                  PrismHubStorage.getSetting(SettingKey.autoCheckUpdate),
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.autoCheckUpdate, value);
              },
            ),
            // NSFW
            SettingsSwitchTile(
              title: 'settings.nsfw'.i18n,
              buildSubtitle: () => "settings.nsfw-subtitle".i18n,
              buildValue: () {
                return PrismHubStorage.getSetting(SettingKey.enableNSFW);
              },
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.enableNSFW, value);
                // Seguridad NSFW: si el usuario apaga el ajuste, cualquier
                // extensión nsfw que haya quedado activada se desactiva sola
                // — sin esto, una extensión +18 seguía funcionando aunque el
                // ajuste que la habilitó ya no estuviera prendido.
                if (!value) {
                  for (final entry in ExtensionUtils.runtimes.entries) {
                    if (entry.value.extension.nsfw &&
                        ExtensionUtils.isEnabled(entry.key)) {
                      ExtensionUtils.setExtensionEnabled(entry.key, false);
                    }
                  }
                }
              },
            ),
            // Desktop ya tiene su propia entrada discreta en el panel de
            // navegación (footerItems, ver main_page.dart) — acá solo hace
            // falta en Android, que no tiene ese panel.
            if (Platform.isAndroid)
              SettingsTile(
                icon: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE5484D)),
                title: 'nsfw18.menu-label'.i18n,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Get.to(const Nsfw18ZoneGate()),
              ),
            const Nsfw18PinSettingsTile(),
          ],
        ),
      ),
      const SizedBox(height: 10),
      // 扩展仓库
      SettingsExpanderTile(
        icon: fluent.FluentIcons.repo,
        androidIcon: Icons.extension,
        title: 'settings.extension'.i18n,
        subTitle: 'settings.extension-subtitle'.i18n,
        content: Column(
          children: [
            SettingsIntpuTile(
              title: 'settings.repo-url'.i18n,
              buildSubtitle: () {
                if (!Platform.isAndroid) {
                  return 'settings.repo-url-subtitle'.i18n;
                }
                return _stripUrlScheme(
                    PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl));
              },
              onChanged: (value) {
                PrismHubStorage.setSetting(
                    SettingKey.prismhubRepoUrl, _withUrlScheme(value));
                Get.find<ExtensionRepoPageController>().onRefresh();
              },
              buildText: () {
                return _stripUrlScheme(
                    PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl));
              },
            ),
            const SizedBox(height: 8),
            // Solo informativo (no editable) — el repo por defecto es el
            // oficial de prism-plus; las extensiones que vienen firmadas
            // desde ahí se marcan como "PrismPlus" en el listado (ver
            // extension_card.dart).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'settings.repo-official-note'.i18n,
                style:
                    const TextStyle(fontSize: 12, color: HomeTheme.textMuted),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      const SizedBox(height: 10),
      // 视频播放器
      SettingsExpanderTile(
        icon: fluent.FluentIcons.play,
        androidIcon: Icons.play_arrow,
        title: 'settings.video-player'.i18n,
        subTitle: 'settings.video-player-subtitle'.i18n,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Servidor BT desactivado a pedido explícito — la entrada de
            // Ajustes se saca de la UI (el código de BTServerUtils sigue
            // existiendo, solo que ya no hay forma de instalarlo/arrancarlo
            // desde acá, y MainController tampoco lo arranca al abrir).
            // Reproductor externo bloqueado a pedido explícito: por ahora
            // toda la app (PC y celular) usa solo el reproductor
            // incorporado. Se deja la opción a la vista pero no editable —
            // el valor ya se fuerza a "built-in" al iniciar (ver
            // prismhub_storage.dart).
            SettingsRadiosTile(
              title: 'settings.external-player'.i18n,
              enabled: false,
              itemNameValue: {
                "settings.external-player-builtin".i18n: "built-in",
              },
              buildSubtitle: () =>
                  'settings.external-player-locked-subtitle'.i18n,
              applyValue: (value) {
                PrismHubStorage.setSetting(SettingKey.videoPlayer, value);
              },
              buildGroupValue: () {
                return PrismHubStorage.getSetting(SettingKey.videoPlayer);
              },
            ),
            const SizedBox(height: 10),
            if (!Platform.isAndroid) ...[
              Text("settings.skip-interval".i18n),
              const SizedBox(height: 2),
              Text(
                "settings.skip-interval-subtitle".i18n,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 15),
              Column(
                children: [
                  Row(children: [
                    Expanded(
                        child: SettingNumboxButton(
                      title: "key I",
                      button1text: "1s",
                      button2text: "0.1s",
                      onChanged: (value) {
                        PrismHubStorage.setSetting(
                            SettingKey.keyI, value ??= -10.0);
                      },
                      numberBoxvalue:
                          PrismHubStorage.getSetting(SettingKey.keyI) ?? -10.0,
                    )),
                    const SizedBox(width: 30),
                    Expanded(
                        child: SettingNumboxButton(
                      title: "key J",
                      button1text: "1s",
                      button2text: "0.1s",
                      onChanged: (value) {
                        PrismHubStorage.setSetting(
                            SettingKey.keyJ, value ??= 10.0);
                      },
                      numberBoxvalue:
                          PrismHubStorage.getSetting(SettingKey.keyJ) ?? 10.0,
                    ))
                  ]),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: SettingNumboxButton(
                        title: "arrow left",
                        icon: const Icon(fluent.FluentIcons.chevron_left_med),
                        button1text: "1s",
                        button2text: "0.1s",
                        numberBoxvalue:
                            PrismHubStorage.getSetting(SettingKey.arrowLeft) ??
                                10.0,
                        onChanged: (value) {
                          PrismHubStorage.setSetting(
                              SettingKey.arrowLeft, value ??= -2.0);
                        },
                      )),
                      const SizedBox(width: 30),
                      Expanded(
                          child: SettingNumboxButton(
                        title: "arrow right",
                        icon: const Icon(fluent.FluentIcons.chevron_right_med),
                        button1text: "1s",
                        button2text: "0.1s",
                        onChanged: (value) {
                          PrismHubStorage.setSetting(
                              SettingKey.arrowRight, value ??= 2);
                        },
                        numberBoxvalue:
                            PrismHubStorage.getSetting(SettingKey.arrowRight) ??
                                10.0,
                      ))
                    ],
                  )
                ],
              ),
            ]
          ],
        ),
      ),
      // Sección de sincronización (AniList) desactivada a pedido explícito
      // para esta release — se saca entera de la UI en vez de dejarla
      // visible pero rota. El código de tracking sigue intacto
      // (AniListTrackingPage, la ruta /settings/anilist, el
      // TrackingPageController), así que volver a mostrarla es solo
      // devolver este bloque.
      const SizedBox(height: 20),
      // 高级
      ListTitle(title: 'settings.advanced'.i18n),
      const SizedBox(height: 20),
      // 网络设置
      SettingsExpanderTile(
        content: Column(
          children: [
            // UA
            SettingsIntpuTile(
              title: 'settings.network-ua'.i18n,
              buildSubtitle: () {
                if (!Platform.isAndroid) {
                  return 'settings.network-ua-subtitle'.i18n;
                }
                return PrismHubStorage.getUASetting();
              },
              onChanged: (value) {
                PrismHubStorage.setUASetting(value);
              },
              buildText: () {
                return PrismHubStorage.getUASetting();
              },
            ),
            SettingsRadiosTile(
              title: 'settings.proxy-type'.i18n,
              itemNameValue: {
                'settings.proxy-type-direct'.i18n: 'DIRECT',
                'settings.proxy-type-socks5'.i18n: 'SOCKS5',
                'settings.proxy-type-socks4'.i18n: 'SOCKS4',
                'settings.proxy-type-http'.i18n: 'PROXY',
              },
              // Bloqueado: cambiar de "Directo" activa flutter_socks_proxy,
              // una reimplementación pura en Dart de HttpClient que enruta
              // TODAS las peticiones de la app por su parser (más lento) vía
              // HttpOverrides.global — confirmado como causa real de
              // lentitud general reportada en vivo. Se deja el valor
              // guardado a la vista (por si alguien lo configuró antes) pero
              // ya no editable.
              enabled: false,
              buildSubtitle: () => 'settings.proxy-type-locked-subtitle'.i18n,
              applyValue: (value) {
                PrismHubStorage.setSetting(SettingKey.proxyType, value);
                PrismRequest.refreshProxy();
              },
              buildGroupValue: () {
                return PrismHubStorage.getSetting(SettingKey.proxyType);
              },
            ),
            const SizedBox(height: 10),
            SettingsIntpuTile(
              title: 'settings.proxy'.i18n,
              enabled: false,
              buildSubtitle: () => 'settings.proxy-subtitle'.i18n,
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.proxy, value);
                PrismRequest.refreshProxy();
              },
              buildText: () {
                return PrismHubStorage.getSetting(SettingKey.proxy);
              },
            ),
          ],
        ),
        title: "settings.network".i18n,
        subTitle: "settings.network-subtitle".i18n,
        icon: fluent.FluentIcons.globe,
        androidIcon: Icons.network_wifi,
      ),
      const SizedBox(height: 10),
      // Debug
      SettingsExpanderTile(
        title: "settings.log".i18n,
        subTitle: 'settings.log-subtitle'.i18n,
        androidIcon: Icons.report,
        icon: fluent.FluentIcons.report_alert,
        content: Column(
          children: [
            SettingsSwitchTile(
              title: 'settings.save-log'.i18n,
              buildSubtitle: () => 'settings.save-log-subtitle'.i18n,
              buildValue: () {
                return PrismHubStorage.getSetting(SettingKey.saveLog);
              },
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.saveLog, value);
              },
            ),
            const SizedBox(height: 10),
            // 导出日志
            SettingsTile(
              title: 'settings.export-log'.i18n,
              buildSubtitle: () => 'settings.export-log-subtitle'.i18n,
              trailing: PlatformWidget(
                androidWidget: TextButton(
                  onPressed: () {
                    Share.shareXFiles([XFile(PrismLog.logFilePath)]);
                  },
                  child: Text('common.export'.i18n),
                ),
                desktopWidget: fluent.FilledButton(
                  onPressed: () async {
                    final path = await FilePicker.platform.saveFile(
                      type: FileType.custom,
                      allowedExtensions: ['log'],
                      fileName: 'PrismHub.log',
                    );
                    if (path != null) {
                      File(PrismLog.logFilePath).copy(path);
                    }
                  },
                  child: Text('common.export'.i18n),
                ),
              ),
            ),
          ],
        ),
      ),
      if (!Platform.isAndroid) ...[
        const SizedBox(height: 10),
        Obx(
          () {
            final value = c.extensionLogWindowId.value != -1;
            return SettingsSwitchTile(
              icon: const Icon(
                fluent.FluentIcons.bug,
                size: 24,
              ),
              title: 'settings.extension-log'.i18n,
              buildSubtitle: () => 'settings.extension-log-subtitle'.i18n,
              buildValue: () => value,
              onChanged: (value) {
                c.toggleExtensionLogWindow(value);
              },
              isCard: true,
            );
          },
        )
      ],
      // 关于
      const SizedBox(height: 20),
      ListTitle(title: 'settings.about'.i18n),
      const SizedBox(height: 20),
      SettingsTile(
        isCard: true,
        icon: const PlatformWidget(
          androidWidget: Icon(Icons.update),
          desktopWidget: Icon(fluent.FluentIcons.update_restore, size: 24),
        ),
        title: 'settings.upgrade'.i18n,
        buildSubtitle: () => FlutterI18n.translate(
          context,
          'settings.upgrade-subtitle',
          translationParams: {
            'version': packageInfo.version,
          },
        ),
        trailing: PlatformWidget(
          androidWidget: TextButton(
            onPressed: () {
              ApplicationUtils.checkUpdate(
                context,
                showSnackbar: true,
              );
            },
            child: Text('settings.upgrade-training'.i18n),
          ),
          desktopWidget: fluent.FilledButton(
            onPressed: () {
              ApplicationUtils.checkUpdate(
                context,
                showSnackbar: true,
              );
            },
            child: Text('settings.upgrade-training'.i18n),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SettingsExpanderTile(
        leading: const Image(
          image: AssetImage('assets/icon/logo.png'),
          width: 24,
          height: 24,
        ),
        title: "PrismHub",
        subTitle: "AGPL-3.0 License",
        open: true,
        noPage: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: HomeTheme.accentPink.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: HomeTheme.accentPink),
              ),
              child: const Text(
                "BETA",
                style: TextStyle(
                  color: HomeTheme.accentPink,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              'settings.about-description'.i18n,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
            const SizedBox(height: 20),
            Text(
              'settings.links'.i18n,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Wrap(
              children: [
                for (final link in c.links.entries)
                  fluent.Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          await launchUrl(
                            Uri.parse(link.value),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: Text(
                          link.key,
                          style: const TextStyle(
                            color: HomeTheme.accentPink,
                          ),
                        ),
                      ),
                    ),
                  )
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'settings.contributors'.i18n,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Wrap(
                children: [
                  if (c.contributors.isNotEmpty)
                    for (final contributor in c.contributors)
                      fluent.Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () async {
                              await launchUrl(
                                Uri.parse(contributor['html_url']),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: Text(
                              contributor['login'],
                              style: const TextStyle(
                                color: HomeTheme.accentPink,
                              ),
                            ),
                          ),
                        ),
                      )
                ],
              ),
            ),
          ],
        ),
      )
    ];
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'common.settings'.i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      body: Container(
        color: HomeTheme.bg,
        child: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: (context) => Container(
        color: HomeTheme.bg,
        child: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            ListView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              children: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }
}
