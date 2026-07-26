import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class ExtensionTile extends StatefulWidget {
  const ExtensionTile(this.extension, {super.key});
  final Extension extension;

  @override
  State<ExtensionTile> createState() => _ExtensionTileState();
}

class _ExtensionTileState extends State<ExtensionTile> {
  final fluent.FlyoutController moreFlyoutController =
      fluent.FlyoutController();

  late bool _enabled = ExtensionUtils.isEnabled(widget.extension.package);
  bool _updateRequired = false;

  @override
  void initState() {
    super.initState();
    // Chequeo async contra el índice remoto del repo — no bloquea el primer
    // build (arranca sin badge y aparece un instante después si corresponde).
    ExtensionUtils.hasExtensionUpdate(widget.extension.package).then((value) {
      if (mounted) setState(() => _updateRequired = value);
    });
  }

  void _showUpdateRequiredDialog(BuildContext context) {
    showPlatformDialog(
      context: context,
      title: 'extension.update-required'.i18n,
      content: Text('extension.update-required-dialog'.i18n),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () {
            RouterUtils.pop();
            router.push('/extension_repo');
          },
          child: Text('extension.go-to-update'.i18n),
        ),
      ],
    );
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _enabled = value);
    await ExtensionUtils.setExtensionEnabled(widget.extension.package, value);
  }

  // Misma caja con marca que ExtensionCard (repositorio) — antes el ícono (o
  // su fallback) quedaba flotando suelto sobre la fila.
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
        widget.extension.icon ?? '',
        key: ValueKey(widget.extension.icon),
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
      leading: Opacity(
        opacity: _enabled ? 1 : 0.4,
        child: _iconBox(size: 40, iconSize: 20),
      ),
      title: Text(widget.extension.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.extension.version}  ${ExtensionUtils.typeToString(widget.extension.type)} ',
            style: const TextStyle(fontSize: 12),
          ),
          if (_updateRequired)
            Row(
              children: [
                const Icon(Icons.system_update,
                    size: 13, color: Colors.redAccent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'extension.update-required'.i18n,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          if (ExtensionUtils.isFailing(widget.extension.package))
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 13, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'extension.not-working'.i18n,
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ),
        ],
      ),
      // Deshabilitada: no se puede entrar a buscar/navegar dentro de ella
      // desde acá — el toggle apagado ahora también bloquea este atajo.
      // Actualización pendiente: bloquea el uso igual (aunque esté
      // habilitada) y en vez de navegar explica que hay que actualizar.
      onTap: _updateRequired
          ? () => _showUpdateRequiredDialog(context)
          : (_enabled
              ? () {
                  router.push(Uri(
                    path: '/search_extension',
                    queryParameters: {'package': widget.extension.package},
                  ).toString());
                }
              : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: _enabled, onChanged: _toggleEnabled),
          IconButton(
            onPressed: () {
          // 弹出菜单 — solo desinstalar (ajustes/editar código quitados a
          // pedido del usuario).
          showModalBottomSheet(
            context: context,
            builder: (context) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete),
                    title: Text('common.uninstall'.i18n),
                    onTap: () {
                      ExtensionUtils.uninstall(widget.extension.package);
                      Get.back();
                    },
                  ),
                ],
              );
            },
          );
            },
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _iconBox(size: 45, iconSize: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.extension.name,
                        style: const TextStyle(
                          fontSize: 17,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        widget.extension.author,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (_updateRequired)
                        Row(
                          children: [
                            const Icon(fluent.FluentIcons.installation,
                                size: 12, color: Colors.redAccent),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'extension.update-required'.i18n,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      if (ExtensionUtils.isFailing(widget.extension.package))
                        Row(
                          children: [
                            const Icon(fluent.FluentIcons.warning,
                                size: 12, color: Colors.orange),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'extension.not-working'.i18n,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.orange),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Text(widget.extension.version)),
          Expanded(
            child: Text(ExtensionUtils.typeToString(widget.extension.type)),
          ),
          const Spacer(),
          fluent.ToggleSwitch(
            checked: _enabled,
            onChanged: _toggleEnabled,
          ),
          const SizedBox(width: 8),
          fluent.Tooltip(
            message: 'Abrir',
            child: fluent.IconButton(
              icon: const Icon(fluent.FluentIcons.search),
              // Deshabilitada / actualización pendiente: mismo bloqueo que en
              // la versión móvil.
              onPressed: _updateRequired
                  ? () => _showUpdateRequiredDialog(context)
                  : (_enabled
                      ? () {
                          router.push(Uri(
                            path: '/search_extension',
                            queryParameters: {
                              'package': widget.extension.package
                            },
                          ).toString());
                        }
                      : null),
            ),
          ),
          const SizedBox(width: 8),
          // "..." solo con Desinstalar — ajustes/editar código quitados a
          // pedido del usuario.
          fluent.FlyoutTarget(
            controller: moreFlyoutController,
            child: fluent.IconButton(
              icon: const Icon(fluent.FluentIcons.more),
              onPressed: () {
                moreFlyoutController.showFlyout(
                  autoModeConfiguration: fluent.FlyoutAutoConfiguration(
                    preferredMode: fluent.FlyoutPlacementMode.bottomLeft,
                  ),
                  builder: (context) {
                    return fluent.MenuFlyout(
                      items: [
                        fluent.MenuFlyoutItem(
                          leading: const Icon(fluent.FluentIcons.delete),
                          text: Text('common.uninstall'.i18n),
                          onPressed: () {
                            ExtensionUtils.uninstall(widget.extension.package);
                            fluent.Flyout.of(context).close();
                          },
                        ),
                      ],
                    );
                  },
                  barrierDismissible: true,
                  dismissWithEsc: true,
                );
              },
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
