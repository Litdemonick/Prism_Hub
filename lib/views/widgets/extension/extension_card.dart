import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/extension_signature.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';

class ExtensionCard extends StatefulWidget {
  const ExtensionCard({
    super.key,
    required this.name,
    required this.version,
    required this.icon,
    required this.package,
    required this.lang,
    required this.nsfw,
    required this.type,
    this.url,
    this.webSite,
    this.license,
    this.description,
    this.signature,
  });
  final String? icon;
  final String? url;
  final String name;
  final String version;
  final String package;
  final String lang;
  final ExtensionType type;
  final bool nsfw;
  final String? webSite;
  final String? license;
  final String? description;
  // Firma Ed25519 de prism+ (del index.json). Si está y valida → oficial; si
  // está pero no valida → manipulada (se rechaza); si falta → externa.
  final String? signature;

  @override
  State<ExtensionCard> createState() => _ExtensionCardState();
}

class _ExtensionCardState extends State<ExtensionCard> {
  bool isLoading = false;
  bool isInstall = false;
  bool hasUpgrade = false;
  late String icon = widget.icon ?? '';

  @override
  void initState() {
    setState(() {
      isInstall = ExtensionUtils.runtimes.containsKey(widget.package);
      hasUpgrade = isInstall &&
          ExtensionUtils.runtimes[widget.package]!.extension.version !=
              widget.version;
    });
    super.initState();
  }

  _install() async {
    setState(() {
      isLoading = true;
    });
    try {
      // Use direct url from index.json if available, otherwise fallback to repo convention
      final baseUrl = widget.url ??
          PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl) +
              "/repo/${widget.package}.js";
      // Cache-bust: GitHub raw cachea el .js unos minutos — sin esto, instalar
      // justo después de publicar una versión nueva podía traer la vieja.
      final bust = DateTime.now().millisecondsSinceEpoch;
      final sep = baseUrl.contains('?') ? '&' : '?';
      final url = '$baseUrl${sep}t=$bust';
      debugPrint(url);
      final res = await dio.get<String>(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      if (res.data == null) throw Exception("Does not seem to be an extension");

      String script = res.data!;
      // Seguridad: si la entrada del catálogo trae firma, debe validar contra la
      // llave pública de prism+. Si no valida, la extensión fue alterada → no se
      // instala. Si no trae firma, es externa (no oficial) y se permite igual:
      // PrismHub es open source y admite sideload de terceros.
      bool officialVerified = false;
      if (widget.signature != null && widget.signature!.isNotEmpty) {
        if (!ExtensionSignature.isOfficial(script, widget.signature)) {
          throw Exception('extension.invalid-signature'.i18n);
        }
        // Firma oficial válida → puede instalarse aunque sea una nativa.
        officialVerified = true;
      }
      // Inject metadata header if missing (e.g. CDN cache serving old file)
      if (!script.contains('==PrismHubExtension==') &&
          !script.contains('==MiruExtension==') &&
          !script.contains('@package')) {
        final typeName = widget.type.toString().split('.').last;
        final header = '// ==PrismHubExtension==\n'
            '// @name         ${widget.name}\n'
            '// @version      ${widget.version}\n'
            '// @author       PrismHub\n'
            '// @lang         ${widget.lang}\n'
            '// @license      ${widget.license ?? "MIT"}\n'
            '// @icon         ${widget.icon ?? ""}\n'
            '// @package      ${widget.package}\n'
            '// @type         $typeName\n'
            '// @webSite      ${widget.webSite ?? ""}\n'
            '// @description  ${widget.description ?? widget.name}\n'
            '// ==/PrismHubExtension==\n\n';
        script = header + script;
      }
      if (!mounted) return;
      await ExtensionUtils.installByScript(script, context,
          officialVerified: officialVerified);
      // Confirmación visible: antes el éxito no avisaba nada y parecía que
      // "no pasó nada" al instalar.
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'extension.install-success'.i18n,
          severity: fluent.InfoBarSeverity.success,
        );
      }
    } catch (e) {
      // installByScript ya muestra un diálogo de error con el detalle; aquí solo
      // registramos. El estado real se sincroniza abajo desde runtimes.
      debugPrint(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          // Reflejar el estado REAL: si el init falló, la extensión no quedó en
          // runtimes → el botón vuelve a "Instalar" en vez de mentir "instalada".
          isInstall = ExtensionUtils.runtimes.containsKey(widget.package);
          hasUpgrade = isInstall &&
              ExtensionUtils.runtimes[widget.package]!.extension.version !=
                  widget.version;
        });
      }
    }
  }

  // Caja con fondo propio para el ícono — antes el ícono (o su fallback,
  // cuando la extensión no trae uno) quedaba flotando suelto sobre el fondo
  // de la tarjeta; con marca (borde + superficie) se ve intencional en vez
  // de una imagen rota.
  Widget _iconBox({required double size, required double iconSize}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: HomeTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: CacheNetWorkImagePic(
        icon,
        fit: BoxFit.contain,
        fallback: Icon(
          fluent.FluentIcons.puzzle,
          size: iconSize,
          color: HomeTheme.accentPink,
        ),
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return ListTile(
      leading: _iconBox(size: 40, iconSize: 20),
      title: Text(widget.name),
      subtitle: DefaultTextStyle(
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall!.color,
          ),
          // Wrap en vez de Row: con varios badges juntos (versión + tipo +
          // idioma + 18+ + oficial) en pantallas angostas de celular, un Row
          // fijo tiraba RenderFlex overflow — confirmado en vivo ("overflow
          // by 28 pixels"). Wrap baja el resto a una segunda línea en vez de
          // desbordar, igual que ya hace la versión de escritorio.
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(widget.version),
              Text(ExtensionUtils.typeToString(widget.type)),
              Text(widget.lang),
              if (widget.nsfw)
                const Text(
                  '18+',
                  style: TextStyle(
                    color: Colors.redAccent,
                  ),
                ),
              // Solo indica que el catálogo trae firma de prism+ (no
              // valida acá — eso pasa recién al instalar, ver _install()).
              // Es solo informativo, no editable.
              if (widget.signature != null && widget.signature!.isNotEmpty)
                Text(
                  'extension.official-badge'.i18n,
                  style: const TextStyle(
                    color: HomeTheme.accentPink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          )),
      trailing: SizedBox(
        width: hasUpgrade ? 96 : 90,
        child: isLoading
            ? const SizedBox(
                width: 25,
                height: 25,
                child: ProgressRing(),
              )
            : isInstall
                ? Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      if (hasUpgrade)
                        SizedBox(
                          height: 32,
                          child: FilledButton(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              await _install();
                              setState(() {});
                            },
                            child: Text('extension-repo.upgrade'.i18n),
                          ),
                        ),
                      SizedBox(
                        height: 32,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            await ExtensionUtils.uninstall(widget.package);
                            setState(() {
                              isInstall = false;
                            });
                          },
                          child: Text('common.uninstall'.i18n),
                        ),
                      ),
                    ],
                  )
                : TextButton(
                    onPressed: () async {
                      await _install();
                    },
                    child: Text('common.install'.i18n),
                  ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _iconBox(size: 64, iconSize: 30),
          const SizedBox(height: 8),
          Text(widget.name, style: const TextStyle(fontSize: 17)),
          DefaultTextStyle(
            style: TextStyle(
              fontSize: 12,
              color: fluent.FluentTheme.of(context).inactiveColor,
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(ExtensionUtils.typeToString(widget.type)),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(widget.lang),
                ),
                if (widget.nsfw)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      '18+',
                      style: TextStyle(
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                if (widget.signature != null && widget.signature!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'extension.official-badge'.i18n,
                      style: const TextStyle(
                        color: HomeTheme.accentPink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 8,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  widget.version,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 25,
                  height: 25,
                  child: ProgressRing(),
                )
              else if (isInstall)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasUpgrade)
                      // Actualizar es la acción destacada (relleno, acento
                      // morado); Desinstalar queda como botón simple — antes
                      // los dos eran FilledButton y competían por atención,
                      // sin distinguir cuál es la acción recomendada.
                      fluent.FilledButton(
                        child: Text('extension-repo.upgrade'.i18n),
                        onPressed: () async {
                          await _install();
                          setState(() {});
                        },
                      ),
                    fluent.Button(
                      child: Text('common.uninstall'.i18n),
                      onPressed: () async {
                        await ExtensionUtils.uninstall(widget.package);
                        setState(() {
                          isInstall = false;
                        });
                      },
                    ),
                  ],
                )
              else
                fluent.FilledButton(
                  onPressed: () async {
                    await _install();
                  },
                  child: Text('common.install'.i18n),
                )
            ],
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
