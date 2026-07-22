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
      if (!script.contains('==PrismHubExtension==') && !script.contains('==MiruExtension==') && !script.contains('@package')) {
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

  Widget _buildAndroid(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 35,
        height: 35,
        child: CacheNetWorkImagePic(
          icon,
          fit: BoxFit.contain,
          fallback: const Icon(Icons.extension),
        ),
      ),
      title: Text(widget.name),
      subtitle: DefaultTextStyle(
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall!.color,
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(widget.version),
              ),
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
                              padding: const EdgeInsets.symmetric(horizontal: 8),
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
    return fluent.Card(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: CacheNetWorkImagePic(
              icon,
              width: 64,
              height: 64,
              fit: BoxFit.contain,
              fallback: const Icon(fluent.FluentIcons.add_in, size: 32),
            ),
          ),
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
                      fluent.FilledButton(
                        child: Text('extension-repo.upgrade'.i18n),
                        onPressed: () async {
                          await _install();
                          setState(() {});
                        },
                      ),
                    fluent.FilledButton(
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
