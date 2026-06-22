import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/pages/code_edit_page.dart';
import 'package:prismhub/views/pages/extension/extension_settings_page.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;

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

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _enabled = value);
    await ExtensionUtils.setExtensionEnabled(widget.extension.package, value);
  }

  Widget _buildAndroid(BuildContext context) {
    return ListTile(
      leading: Opacity(
        opacity: _enabled ? 1 : 0.4,
        child: SizedBox(
          width: 35,
          height: 35,
          child: CacheNetWorkImagePic(
            widget.extension.icon ?? '',
            key: ValueKey(widget.extension.icon),
            fit: BoxFit.contain,
            fallback: const Icon(Icons.extension),
          ),
        ),
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
      onTap: () {
        router.push(Uri(
          path: '/search_extension',
          queryParameters: {'package': widget.extension.package},
        ).toString());
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: _enabled, onChanged: _toggleEnabled),
          IconButton(
            onPressed: () {
          // 弹出菜单
          showModalBottomSheet(
            context: context,
            builder: (context) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: Text('common.settings'.i18n),
                    onTap: () {
                      Get.back();
                      Get.to(ExtensionSettingsPage(package: widget.extension.package));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: Text('extension.edit-code'.i18n),
                    onTap: () async {
                      Get.back();
                      Get.to(CodeEditPage(extension: widget.extension));
                    },
                  ),
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
    return fluent.Card(
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // extension icon
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SizedBox(
                    width: 45,
                    height: 45,
                    child: CacheNetWorkImagePic(
                      widget.extension.icon ?? '',
                      key: ValueKey(widget.extension.icon),
                      fit: BoxFit.contain,
                      fallback: const Icon(fluent.FluentIcons.add_in),
                    ),
                  ),
                ),
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
              onPressed: () {
                router.push(Uri(
                  path: '/search_extension',
                  queryParameters: {'package': widget.extension.package},
                ).toString());
              },
            ),
          ),
          const SizedBox(width: 8),
          fluent.IconButton(
              icon: const Icon(fluent.FluentIcons.settings),
              onPressed: () {
                router.push(Uri(
                  path: '/extension_settings',
                  queryParameters: {'package': widget.extension.package},
                ).toString());
              }),
          const SizedBox(width: 8),
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
                          leading: const Icon(fluent.FluentIcons.code),
                          text: Text('extension.edit-code'.i18n),
                          onPressed: () async {
                            fluent.Flyout.of(context).close();
                            launchUrl(path.toUri(
                              '${ExtensionUtils.extensionsDir}/${widget.extension.package}.js',
                            ));
                          },
                        ),
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
