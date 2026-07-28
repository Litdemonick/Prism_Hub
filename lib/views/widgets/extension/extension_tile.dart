import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';

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
  bool _unstable = false;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    // Chequeo async contra el índice remoto del repo — no bloquea el primer
    // build (arranca sin badge y aparece un instante después si corresponde).
    ExtensionUtils.hasExtensionUpdate(widget.extension.package).then((value) {
      if (mounted) setState(() => _updateRequired = value);
    });
    ExtensionUtils.isRemoteUnstable(widget.extension.package).then((value) {
      if (mounted) setState(() => _unstable = value);
    });
  }

  // Actualiza sin salir de "Extensiones instaladas" — antes la única forma
  // era navegar al repositorio a mano. Reintenta el chequeo de actualización
  // al terminar para que el badge/botón desaparezcan solos si ya no hace falta.
  Future<void> _performUpdate() async {
    setState(() => _updating = true);
    try {
      await ExtensionUtils.updateInstalledFromRepo(
        widget.extension.package,
        context,
      );
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'extension.install-success'.i18n,
          severity: fluent.InfoBarSeverity.success,
        );
      }
      final stillRequired =
          await ExtensionUtils.hasExtensionUpdate(widget.extension.package);
      if (mounted) setState(() => _updateRequired = stillRequired);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  // La lista de "Extensiones instaladas" no tiene Key por ítem (ver
  // extension_page.dart), así que Flutter reutiliza este mismo State al
  // reconstruir la lista (ej. al recibir ExtensionPageController.callRefresh)
  // en vez de recrearlo — sin esto, _enabled/_updateRequired quedaban
  // pegados para siempre en lo que valía la PRIMERA vez que se montó el
  // tile. Necesario para que (a) el apagado automático de una extensión
  // nsfw (settings_page.dart, al apagar el ajuste +18) se refleje en el
  // switch, y (b) actualizar una extensión desde el REPOSITORIO (otra
  // página) haga desaparecer el "actualización requerida" de acá sin
  // salir y volver a entrar — confirmado en vivo que quedaba pegado.
  @override
  void didUpdateWidget(covariant ExtensionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fresh = ExtensionUtils.isEnabled(widget.extension.package);
    if (fresh != _enabled) {
      setState(() => _enabled = fresh);
    }
    // Sin condición de versión: el botón de refrescar (limpia el caché de
    // versiones remotas y reasigna `runtimes`) NO cambia la versión — solo
    // el estado que hay que re-consultar contra el catálogo. Con la
    // condición de antes, tocar refrescar no disparaba ningún re-chequeo y
    // parecía que el botón no hacía nada (confirmado en vivo). Repetir esto
    // es barato: hasExtensionUpdate/isRemoteUnstable comparten un caché con
    // TTL de 10 min, así que solo pegan a la red cuando de verdad hace falta.
    ExtensionUtils.hasExtensionUpdate(widget.extension.package).then((value) {
      if (mounted && value != _updateRequired) {
        setState(() => _updateRequired = value);
      }
    });
    ExtensionUtils.isRemoteUnstable(widget.extension.package).then((value) {
      if (mounted && value != _unstable) setState(() => _unstable = value);
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

  // Confirmación +18 antes de activar una extensión nsfw — mismo diálogo que
  // ExtensionCard usa al instalar (ver ese archivo), acá se repite porque no
  // comparten contexto de widget.
  Future<bool> _confirmNsfw() async {
    if (!mounted) return false;
    final result = await showPlatformDialog(
      context: context,
      title: 'extension.nsfw-warning-title'.i18n,
      content: Text('extension.nsfw-warning-content'.i18n),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
    return result == true;
  }

  Future<void> _toggleEnabled(bool value) async {
    // Activar una extensión nsfw: si el ajuste +18 de Ajustes está apagado no
    // se deja activar (mensaje explicando por qué); si está prendido, se pide
    // confirmación +18 antes de activarla de verdad. Desactivar nunca se
    // bloquea.
    if (value && widget.extension.nsfw) {
      if (!PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
        if (mounted) {
          showPlatformSnackbar(
            context: context,
            content: 'extension.nsfw-setting-required'.i18n,
            severity: fluent.InfoBarSeverity.warning,
          );
        }
        return;
      }
      if (!await _confirmNsfw()) return;
    }
    setState(() => _enabled = value);
    await ExtensionUtils.setExtensionEnabled(widget.extension.package, value);
  }

  void _openExtensionSearch(BuildContext context) {
    if (_updateRequired) {
      _showUpdateRequiredDialog(context);
      return;
    }
    if (!_enabled) return;
    router.push(Uri(
      path: '/search_extension',
      queryParameters: {'package': widget.extension.package},
    ).toString());
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
      title: Text(
        widget.extension.name,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wrap: con varios badges juntos (versión + tipo + 18+ +
          // inestable) en pantallas angostas, un Row fijo desborda — mismo
          // fix ya aplicado en ExtensionCard del repositorio.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                widget.extension.version,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                ExtensionUtils.typeToString(widget.extension.type),
                style: const TextStyle(fontSize: 12),
              ),
              if (widget.extension.nsfw)
                const Text(
                  '18+',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (_unstable)
                Text(
                  'extension.unstable'.i18n,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (_updateRequired)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 2,
              children: [
                const Icon(Icons.system_update,
                    size: 13, color: Colors.redAccent),
                Text(
                  'extension.update-required'.i18n,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_updating)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: ProgressRing(),
                  )
                else
                  GestureDetector(
                    onTap: _performUpdate,
                    child: Text(
                      'extension-repo.upgrade'.i18n,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
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
      onTap: _enabled || _updateRequired
          ? () => _openExtensionSearch(context)
          : null,
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
    // minHeight (no fijo): todas las filas quedan alineadas parejo aunque
    // esta tenga badges/botón de más — a diferencia de la card del
    // repositorio, acá se usa mínimo en vez de fijo porque el nombre puede
    // ser largo y forzar una segunda línea; con fijo se recortaría.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Container(
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _enabled || _updateRequired
                    ? () => _openExtensionSearch(context)
                    : null,
                child: MouseRegion(
                  cursor: _enabled || _updateRequired
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
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
                            // Wrap: con 18+/inestable sumados a nombre+autor en una
                            // card angosta del grid/lista, un Row fijo desborda —
                            // mismo fix que ExtensionCard del repositorio.
                            if (widget.extension.nsfw || _unstable)
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 2,
                                children: [
                                  if (widget.extension.nsfw)
                                    const Text(
                                      '18+',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  if (_unstable)
                                    Text(
                                      'extension.unstable'.i18n,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            if (_updateRequired)
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  const Icon(fluent.FluentIcons.installation,
                                      size: 12, color: Colors.redAccent),
                                  Text(
                                    'extension.update-required'.i18n,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            if (ExtensionUtils.isFailing(
                                widget.extension.package))
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
              ),
            ),
            // Wrap en vez de columnas Expanded + Spacer fijos: con el botón
            // "Actualizar" sumado a versión/tipo/switch/acciones, una ventana
            // angosta de escritorio desbordaba (confirmado en vivo con el
            // overflow de ShadeManga) — acá reflowea a una línea de abajo en
            // vez de desbordar.
            Expanded(
              flex: 2,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(widget.extension.version),
                  Text(ExtensionUtils.typeToString(widget.extension.type)),
                  if (_updateRequired)
                    _updating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: ProgressRing(),
                          )
                        // Compacto (padding chico): el tamaño default de
                        // fluent sumado al switch/buscar/más mandaba el "..."
                        // solo a su propia línea en ventanas no muy anchas —
                        // confirmado en vivo, desalineaba la fila contra las
                        // demás de la lista.
                        : fluent.FilledButton(
                            style: fluent.ButtonStyle(
                              padding: fluent.WidgetStateProperty.all(
                                const EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                            onPressed: _performUpdate,
                            child: Text(
                              'extension-repo.upgrade'.i18n,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                  fluent.ToggleSwitch(
                    checked: _enabled,
                    onChanged: _toggleEnabled,
                  ),
                  fluent.Tooltip(
                    message: 'Abrir',
                    child: fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.search),
                      // Deshabilitada / actualización pendiente: mismo bloqueo
                      // que en la versión móvil.
                      onPressed: _enabled || _updateRequired
                          ? () => _openExtensionSearch(context)
                          : null,
                    ),
                  ),
                  // "..." solo con Desinstalar — ajustes/editar código
                  // quitados a pedido del usuario.
                  fluent.FlyoutTarget(
                    controller: moreFlyoutController,
                    child: fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.more),
                      onPressed: () {
                        moreFlyoutController.showFlyout(
                          autoModeConfiguration: fluent.FlyoutAutoConfiguration(
                            preferredMode:
                                fluent.FlyoutPlacementMode.bottomLeft,
                          ),
                          builder: (context) {
                            return fluent.MenuFlyout(
                              items: [
                                fluent.MenuFlyoutItem(
                                  leading:
                                      const Icon(fluent.FluentIcons.delete),
                                  text: Text('common.uninstall'.i18n),
                                  onPressed: () {
                                    ExtensionUtils.uninstall(
                                        widget.extension.package);
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
                  ),
                ],
              ),
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
      desktopBuilder: _buildDesktop,
    );
  }
}
