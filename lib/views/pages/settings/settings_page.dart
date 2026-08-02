import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_age_dialog.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';
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
import 'package:prismhub/utils/router.dart';
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
// Deja SIEMPRE una URL usable. Borrar el campo guardaba una cadena vacía, y
// con eso el app armaba "/index.json" sin host: no cargaba ninguna extensión
// y en pantalla se veía como si no hubiera internet, sin ninguna pista de que
// el problema era este ajuste. Ante cualquier valor que no sirva se vuelve al
// repositorio oficial en vez de dejar el app sin catálogo.
// Pone los controles de a dos por fila solo si el ancho alcanza; si no, uno
// debajo del otro. Un umbral por ancho real y no por plataforma: un celular
// en horizontal sí tiene lugar para dos, y una ventana angosta en escritorio
// no.
Widget _parDeControles(BuildContext context, List<Widget> hijos) {
  final ancho = MediaQuery.sizeOf(context).width;
  if (ancho < 620) {
    return Column(
      children: [
        for (var i = 0; i < hijos.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          hijos[i],
        ],
      ],
    );
  }
  return Row(
    children: [
      for (var i = 0; i < hijos.length; i++) ...[
        if (i > 0) const SizedBox(width: 30),
        Expanded(child: hijos[i]),
      ],
    ],
  );
}

String _sanitizeRepoUrl(String value) {
  final withScheme = _withUrlScheme(value);
  if (withScheme.isEmpty) return PrismHubStorage.defaultRepoUrl;
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    return PrismHubStorage.defaultRepoUrl;
  }
  return withScheme;
}

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

  List<Widget> _buildSkipIntervalChildren() {
    return [
      Text("settings.skip-interval".i18n),
      const SizedBox(height: 2),
      Text(
        "settings.skip-interval-subtitle".i18n,
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 15),
      Column(
        children: [
          // Dos por fila SOLO si hay ancho. En un celular en vertical
          // cada control quedaba con ~150px y el número se partía en
          // cuatro líneas ("-", "1", "0", "s"). Se decide con el ancho
          // real disponible, así sirve igual en horizontal, donde sí
          // entran dos.
          _parDeControles(context, [
            SettingNumboxButton(
              title: "key I",
              button1text: "1s",
              button2text: "0.1s",
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.keyI, value ??= 10.0);
              },
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.keyI) ?? 10.0,
            ),
            SettingNumboxButton(
              title: "key J",
              button1text: "1s",
              button2text: "0.1s",
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.keyJ, value ??= -10.0);
              },
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.keyJ) ?? -10.0,
            ),
          ]),
          const SizedBox(height: 8),
          _parDeControles(context, [
            SettingNumboxButton(
              title: "arrow left",
              icon: const Icon(fluent.FluentIcons.chevron_left_med),
              button1text: "1s",
              button2text: "0.1s",
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.arrowLeft) ?? -2.0,
              onChanged: (value) {
                PrismHubStorage.setSetting(
                    SettingKey.arrowLeft, value ??= -2.0);
              },
            ),
            SettingNumboxButton(
              title: "arrow right",
              icon: const Icon(fluent.FluentIcons.chevron_right_med),
              button1text: "1s",
              button2text: "0.1s",
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.arrowRight, value ??= 2);
              },
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.arrowRight) ?? 2.0,
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: HomeTheme.accentPink,
              ),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text('settings.restore-defaults'.i18n),
              onPressed: () async {
                // Los mismos valores con los que arranca el app (ver
                // PrismHubStorage._initSettings): dejar la lista
                // duplicada acá sería pedir que se desincronicen, pero
                // no hay un punto único todavía — al menos quedan los
                // dos lugares señalados entre sí.
                await PrismHubStorage.setSetting(SettingKey.keyI, 10.0);
                await PrismHubStorage.setSetting(SettingKey.keyJ, -10.0);
                await PrismHubStorage.setSetting(SettingKey.arrowLeft, -2.0);
                await PrismHubStorage.setSetting(SettingKey.arrowRight, 2.0);
                if (!context.mounted) return;
                setState(() {});
                showPlatformSnackbar(
                  context: context,
                  content: 'settings.restore-defaults-done'.i18n,
                );
              },
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildSkipIntervalContent() {
    // En celular NO hay teclado: el unico atajo de salto es el doble toque a
    // izquierda o derecha, asi que mostrar "key I", "key J" y las flechas era
    // ofrecer cuatro ajustes de los que dos no hacen absolutamente nada. Se
    // muestran solo los dos que el doble toque usa de verdad, con nombres que
    // dicen que gesto configuran.
    if (Platform.isAndroid) return _buildSkipIntervalMobile();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildSkipIntervalChildren(),
    );
  }

  Widget _skipCard(String etiqueta, IconData icono, String key, double porDef) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        children: [
          Icon(icono, color: HomeTheme.accentPink, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              etiqueta,
              style:
                  const TextStyle(color: HomeTheme.textPrimary, fontSize: 14),
            ),
          ),
          _MobileStepper(settingKey: key, fallback: porDef),
        ],
      ),
    );
  }

  Widget _buildSkipIntervalMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // La explicacion va en su propia tarjeta, no como parrafo suelto.
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: HomeTheme.accentPink.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.touch_app,
                  color: HomeTheme.accentPink, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'settings.skip-interval-mobile-help'.i18n,
                  style: const TextStyle(
                      color: HomeTheme.textMuted, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        _skipCard('settings.skip-back'.i18n, Icons.fast_rewind,
            SettingKey.arrowLeft, -2.0),
        _skipCard('settings.skip-forward'.i18n, Icons.fast_forward,
            SettingKey.arrowRight, 2.0),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: HomeTheme.accentPink),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text('settings.restore-defaults'.i18n),
            onPressed: () async {
              await PrismHubStorage.setSetting(SettingKey.arrowLeft, -2.0);
              await PrismHubStorage.setSetting(SettingKey.arrowRight, 2.0);
              if (!context.mounted) return;
              setState(() {});
              showPlatformSnackbar(
                context: context,
                content: 'settings.restore-defaults-done'.i18n,
              );
            },
          ),
        ),
      ],
    );
  }

  // Navigator directo y NO Get.to: esta página se abre DESDE otra que ya se
  // empujó con Get.to (la subpágina de "Reproductor de vídeo" en Android), y
  // ahí el segundo Get.to no navegaba — mismo problema que ya habíamos visto
  // con la página del PIN de la zona +18, resuelto igual.
  void _openSkipIntervalPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: HomeTheme.bg,
          appBar: AppBar(
            backgroundColor: HomeTheme.bg,
            title: Text(
              'settings.skip-interval'.i18n,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              // StatefulBuilder propio: esta página vive fuera del árbol de
              // Ajustes, así que el setState de allá no la alcanza — sin esto
              // el botón de restablecer no refrescaba los números.
              builder: (context, _) => _buildSkipIntervalContent(),
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarAvisoLegal() {
    showPlatformDialog(
      context: context,
      title: 'settings.legal'.i18n,
      maxWidth: 520,
      content: Text(
        'settings.legal-body'.i18n,
        style: const TextStyle(
          color: HomeTheme.textMuted,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        Builder(
          builder: (ctx) => PlatformFilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.confirm'.i18n),
          ),
        ),
      ],
    );
  }

  // Fila con botón para un enlace del proyecto. Un solo lugar para las tres,
  // que sólo cambian en icono, textos y URL.
  Widget _enlaceTile({
    required IconData androidIcon,
    required IconData desktopIcon,
    required String titulo,
    required String subtitulo,
    required String url,
  }) {
    void abrir() => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
    return SettingsTile(
      isCard: true,
      icon: PlatformWidget(
        androidWidget: Icon(androidIcon),
        desktopWidget: Icon(desktopIcon, size: 24),
      ),
      title: titulo,
      buildSubtitle: () => subtitulo,
      trailing: PlatformWidget(
        androidWidget: TextButton(
          onPressed: abrir,
          child: Text('settings.open'.i18n),
        ),
        desktopWidget: fluent.FilledButton(
          onPressed: abrir,
          child: Text('settings.open'.i18n),
        ),
      ),
      onTap: abrir,
    );
  }

  void _abrirSugerencias() {
    launchUrl(
      Uri.parse('https://github.com/Litdemonick/Prism_Hub/issues'),
      mode: LaunchMode.externalApplication,
    );
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
        // En celular la entrada a la Zona +18 vive DENTRO de General (en
        // escritorio está en el panel lateral), así que el subtítulo lo dice
        // solo ahí — si no, mandaría a buscar algo que en PC no está acá.
        subTitle: Platform.isAndroid
            ? 'settings.general-subtitle-android'.i18n
            : 'settings.general-subtitle'.i18n,
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
              onChanged: (value) async {
                // Encender no necesita permiso de nadie.
                if (value) {
                  await PrismHubStorage.setSetting(
                      SettingKey.autoCheckUpdate, true);
                  // `mounted` del State (no context.mounted): esto vive
                  // dentro de _SettingsPageState, y es el chequeo que
                  // corresponde despues de un await.
                  if (mounted) {
                    ApplicationUtils.iniciarChequeoPeriodico(context);
                  }
                  return;
                }
                // Apagar sí: se deja de recibir correcciones y, cuando los
                // sitios cambien, las extensiones van a fallar sin que se
                // entienda por que. Es el tipo de ajuste que conviene no
                // desactivar de un toque sin querer.
                final seguro = await showPlatformDialog(
                  context: context,
                  title: 'settings.auto-check-update-off-title'.i18n,
                  content: Text('settings.auto-check-update-off-body'.i18n),
                  actions: [
                    PlatformTextButton(
                      onPressed: () => RouterUtils.pop(false),
                      child: Text('common.cancel'.i18n),
                    ),
                    PlatformFilledButton(
                      onPressed: () => RouterUtils.pop(true),
                      child: Text('settings.auto-check-update-off-confirm'.i18n),
                    ),
                  ],
                );
                if (seguro != true) return;
                await PrismHubStorage.setSetting(
                    SettingKey.autoCheckUpdate, false);
                ApplicationUtils.detenerChequeoPeriodico();
              },
            ),
            SettingsSwitchTile(
              title: 'settings.check-new-episodes'.i18n,
              buildSubtitle: () => 'settings.check-new-episodes-subtitle'.i18n,
              buildValue: () =>
                  PrismHubStorage.getSetting(SettingKey.checkNewEpisodes) !=
                  false,
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.checkNewEpisodes, value);
              },
            ),
            // Apagado por defecto (== true, no != false): que el reproductor
            // siga solo es algo que se pide, no algo que deba pasar sin avisar.
            SettingsSwitchTile(
              title: 'settings.autoplay-next'.i18n,
              buildSubtitle: () => 'settings.autoplay-next-subtitle'.i18n,
              buildValue: () =>
                  PrismHubStorage.getSetting(SettingKey.autoPlayNext) == true,
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.autoPlayNext, value);
              },
            ),
            // NSFW
            SettingsSwitchTile(
              title: 'settings.nsfw'.i18n,
              buildSubtitle: () => "settings.nsfw-subtitle".i18n,
              buildValue: () {
                return PrismHubStorage.getSetting(SettingKey.enableNSFW);
              },
              onChanged: (value) async {
                // Al ACTIVAR se pide confirmar la mayoría de edad con la fecha
                // de nacimiento, una sola vez por instalación. Si cancela o no
                // llega a la edad, el interruptor no se mueve.
                if (value && !await Nsfw18AgeDialog.confirmar(context)) {
                  // mounted: el dialogo de edad espera al usuario, y en ese
                  // rato la pantalla de ajustes puede irse (atras, cambio de
                  // pestaña). setState sobre un widget ya desmontado tira
                  // "setState() called after dispose()".
                  if (!mounted) return;
                  setState(() {});
                  return;
                }
                await PrismHubStorage.setSetting(SettingKey.enableNSFW, value);
                if (!value) {
                  // Al APAGAR: cualquier extensión +18 que estuviera activa se
                  // desactiva, porque si no seguiría funcionando pese a que el
                  // ajuste que la habilitaba ya no está. Se anota CUÁLES se
                  // tocaron, para no confundirlas con las que el usuario había
                  // apagado a propósito antes.
                  final apagadas = <String>[];
                  for (final entry in ExtensionUtils.runtimes.entries) {
                    if (entry.value.extension.nsfw &&
                        ExtensionUtils.isEnabled(entry.key)) {
                      ExtensionUtils.setExtensionEnabled(entry.key, false);
                      apagadas.add(entry.key);
                    }
                  }
                  await PrismHubStorage.setSetting(
                      SettingKey.nsfw18AutoDisabled, apagadas.join(','));
                  return;
                }
                // Al ENCENDER: se devuelven a como estaban. Antes esto no se
                // hacía y había que volver a activarlas una por una desde
                // Extensiones instaladas, sin ninguna pista de por qué habían
                // quedado apagadas.
                final guardadas =
                    PrismHubStorage.getSetting(SettingKey.nsfw18AutoDisabled);
                if (guardadas is! String || guardadas.isEmpty) return;
                for (final pkg in guardadas.split(',')) {
                  if (pkg.isEmpty) continue;
                  // Solo las que siguen instaladas: una desinstalada de por
                  // medio no debe reaparecer ni dar error.
                  if (!ExtensionUtils.runtimes.containsKey(pkg)) continue;
                  ExtensionUtils.setExtensionEnabled(pkg, true);
                }
                await PrismHubStorage.setSetting(
                    SettingKey.nsfw18AutoDisabled, '');
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
              // Bloqueado, igual que el proxy. Vaciarlo o escribir cualquier
              // cosa dejaba al app sin catálogo y el síntoma en pantalla era
              // "no hay internet", sin ninguna pista de que el problema era
              // este campo. El repositorio oficial es el único soportado; si
              // alguna vez hace falta cambiarlo, se desbloquea acá.
              enabled: false,
              buildSubtitle: () {
                if (!Platform.isAndroid) {
                  return 'settings.repo-url-subtitle'.i18n;
                }
                return _stripUrlScheme(
                    PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl));
              },
              onChanged: (value) {
                final sane = _sanitizeRepoUrl(value);
                PrismHubStorage.setSetting(SettingKey.prismhubRepoUrl, sane);
                // Si lo que escribió no servía, se avisa: cambiar el ajuste y
                // que calladamente quede otro valor sería peor que el error.
                if (sane != _withUrlScheme(value)) {
                  showPlatformSnackbar(
                    context: context,
                    content: 'settings.repo-url-restored'.i18n,
                  );
                }
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
            const SizedBox(height: 10),
            // En celular esto va detrás de un botón: los cuatro controles más
            // su explicación ocupaban media pantalla de texto plano dentro de
            // una lista de ajustes. En escritorio hay ancho de sobra, así que
            // se deja a la vista.
            if (Platform.isAndroid)
              _SkipIntervalTile(onOpen: _openSkipIntervalPage)
            else
              ..._buildSkipIntervalChildren(),
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
              // Bloqueado: un User-Agent vacío o mal armado hace que los
              // sitios rechacen TODAS las peticiones de las extensiones, y el
              // usuario ve "sin conexión" sin manera de relacionarlo con este
              // campo. El valor correcto ya lo elige el app según la
              // plataforma (móvil en Android, escritorio en Windows/Linux).
              enabled: false,
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
      // Reportar fallos y proponer mejoras. Con fila y botón propios, no
      // solo como enlace suelto entre los de abajo: estando en beta es lo
      // que más conviene que el usuario encuentre.
      SettingsTile(
        isCard: true,
        icon: const PlatformWidget(
          androidWidget: Icon(Icons.feedback_outlined),
          desktopWidget: Icon(fluent.FluentIcons.feedback, size: 24),
        ),
        title: 'settings.feedback'.i18n,
        buildSubtitle: () => 'settings.feedback-subtitle'.i18n,
        trailing: PlatformWidget(
          androidWidget: TextButton(
            onPressed: _abrirSugerencias,
            child: Text('settings.feedback-button'.i18n),
          ),
          desktopWidget: fluent.FilledButton(
            onPressed: _abrirSugerencias,
            child: Text('settings.feedback-button'.i18n),
          ),
        ),
      ),
      const SizedBox(height: 10),
      // El aviso legal también acá, para poder consultarlo cuando se quiera:
      // el del arranque se acepta una vez y no vuelve a verse.
      SettingsTile(
        isCard: true,
        icon: const PlatformWidget(
          androidWidget: Icon(Icons.gavel_rounded),
          desktopWidget: Icon(fluent.FluentIcons.script, size: 24),
        ),
        title: 'settings.legal'.i18n,
        buildSubtitle: () => 'settings.legal-subtitle'.i18n,
        trailing: PlatformWidget(
          androidWidget: TextButton(
            onPressed: _mostrarAvisoLegal,
            child: Text('settings.open'.i18n),
          ),
          desktopWidget: fluent.FilledButton(
            onPressed: _mostrarAvisoLegal,
            child: Text('settings.open'.i18n),
          ),
        ),
        onTap: _mostrarAvisoLegal,
      ),
      const SizedBox(height: 10),
      // Los enlaces del proyecto dejan de ser texto suelto al final de
      // "Acerca de" y pasan a filas con botón, igual que el resto: antes
      // convivían dos formas distintas de ofrecer lo mismo.
      _enlaceTile(
        androidIcon: Icons.code,
        desktopIcon: fluent.FluentIcons.git_graph,
        titulo: 'settings.link-source'.i18n,
        subtitulo: 'settings.link-source-subtitle'.i18n,
        url: 'https://github.com/Litdemonick/Prism_Hub',
      ),
      const SizedBox(height: 10),
      _enlaceTile(
        androidIcon: Icons.extension_outlined,
        desktopIcon: fluent.FluentIcons.repo,
        titulo: 'settings.link-extensions'.i18n,
        subtitulo: 'settings.link-extensions-subtitle'.i18n,
        url: 'https://github.com/Litdemonick/prism-plus',
      ),
      const SizedBox(height: 10),
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
          // Centrado en celular: ahí el bloque ocupa el ancho completo de una
          // pantalla angosta y el badge BETA suelto contra el borde izquierdo,
          // con el párrafo largo debajo, quedaba desalineado. En escritorio se
          // deja alineado a la izquierda, que es como está el resto de Ajustes.
          crossAxisAlignment: Platform.isAndroid
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
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
              textAlign:
                  Platform.isAndroid ? TextAlign.center : TextAlign.start,
              style: const TextStyle(color: HomeTheme.textPrimary, height: 1.4),
            ),
            const SizedBox(height: 20),
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
            // ListView.builder y no ListView(children:): la segunda forma
            // MONTA todos los hijos de una, y esta página son varias secciones
            // pesadas (en escritorio, Expander de fluent). Eso trababa la
            // pantalla unos segundos la primera vez que se abría. Con builder
            // solo se montan las que se ven.
            Builder(builder: (context) {
              final items = _buildContent();
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: items.length,
                itemBuilder: (context, i) => items[i],
              );
            }),
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
            // Ver el mismo cambio en la versión Android.
            Builder(builder: (context) {
              final items = _buildContent();
              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                itemCount: items.length,
                itemBuilder: (context, i) => items[i],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// Entrada a los ajustes de salto en celular: una fila con su icono, título y
// resumen, del mismo estilo que el resto de Ajustes, en vez de volcar cuatro
// controles y un párrafo en el medio de la lista.
class _SkipIntervalTile extends StatelessWidget {
  const _SkipIntervalTile({required this.onOpen});
  // Recibe el context de la FILA, no el de la página de Ajustes: es el que
  // está dentro del Navigator donde hay que empujar.
  final void Function(BuildContext) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOpen(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.fast_forward,
                    color: HomeTheme.accentPink, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'settings.skip-interval'.i18n,
                        style: const TextStyle(
                          color: HomeTheme.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'settings.skip-interval-short'.i18n,
                        style: const TextStyle(
                          color: HomeTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: HomeTheme.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Paso compacto para celular: menos, valor, mas. Sin la pastilla de precision
// (con el dedo, saltos de 0,1s no tienen sentido) y con el valor SIEMPRE
// positivo: el sentido lo decide el lado de la pantalla que se toca, asi que
// mostrar "-2 s" en "Retroceder" solo confundia.
class _MobileStepper extends StatefulWidget {
  const _MobileStepper({required this.settingKey, required this.fallback});
  final String settingKey;
  final double fallback;

  @override
  State<_MobileStepper> createState() => _MobileStepperState();
}

class _MobileStepperState extends State<_MobileStepper> {
  late double _valor = _leer();

  double _leer() {
    final v = PrismHubStorage.getSetting(widget.settingKey);
    final d = v is num ? v.toDouble() : widget.fallback;
    final abs = d.abs();
    return abs == 0 ? widget.fallback.abs() : abs;
  }

  @override
  void didUpdateWidget(covariant _MobileStepper old) {
    super.didUpdateWidget(old);
    final actual = _leer();
    if (actual != _valor) _valor = actual;
  }

  void _cambiar(double delta) {
    final nuevo = (_valor + delta).clamp(1.0, 120.0);
    if (nuevo == _valor) return;
    setState(() => _valor = nuevo);
    // Se guarda con el signo que espera el reproductor: negativo para atras.
    final signo = widget.fallback < 0 ? -1 : 1;
    PrismHubStorage.setSetting(widget.settingKey, nuevo * signo);
  }

  Widget _boton(IconData icono, VoidCallback onTap) {
    return Material(
      color: HomeTheme.bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icono, size: 18, color: HomeTheme.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _boton(Icons.remove, () => _cambiar(-1)),
        SizedBox(
          width: 46,
          child: Text(
            '${_valor.round()} s',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HomeTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        _boton(Icons.add, () => _cambiar(1)),
      ],
    );
  }
}
