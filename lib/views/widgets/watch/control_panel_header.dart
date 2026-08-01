import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/watch/playlist.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/window_caption_buttons.dart';
import 'package:window_manager/window_manager.dart';

class ControlPanelHeader<T extends ReaderController> extends StatefulWidget {
  const ControlPanelHeader(
    this.tag, {
    super.key,
    required this.buildSettings,
  });
  final String tag;
  final Widget Function(BuildContext context)? buildSettings;

  @override
  State<ControlPanelHeader> createState() => _ControlPanelHeaderState<T>();
}

class _ControlPanelHeaderState<T extends ReaderController>
    extends State<ControlPanelHeader> {
  late final _c = Get.find<T>(tag: widget.tag);
  final fluent.FlyoutController _playListFlayoutcontroller =
      fluent.FlyoutController();
  final fluent.FlyoutController _settingFlayoutcontroller =
      fluent.FlyoutController();

  void _goToDetail(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
    // Si se entró desde la propia página de detalle (goWatch), ya hay un
    // DetailPage de este mismo título debajo en la pila — cerrar el lector
    // alcanza para revelarlo. Empujar uno nuevo ACÁ TAMBIÉN lo duplicaba:
    // confirmado en vivo, "atrás" quedaba pegado un toque de más (el primero
    // solo cerraba el duplicado) antes de volver de verdad.
    if (_c.cameFromDetail) return;
    final package = _c.runtime.extension.package;
    final url = _c.detailUrl;
    // Confirmado en vivo: empujar la ruta nueva en el mismo tick que el pop
    // del lector hacía que DetailPage montara mientras el lector (y su
    // ComicController/GetX) todavía estaban terminando de desmontar —
    // "DetailPageController not found" + overflow gigante, ambos síntomas
    // de un build a medio terminar. Postergar el push a después de que este
    // frame (el del pop) termine de procesarse le da tiempo real a
    // GetX/Navigator para asentarse antes de montar la página nueva.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // router.push (go_router) es lo que muestra DetailPage CON los
      // controles de ventana en desktop (ver comentario de arriba sobre el
      // shell/rootNavigator) — pero en Android la app no navega el detalle
      // por ahí, sino con Get.to (mismo patrón que usa
      // ExtensionItemCard._buildAndroid). Usar router.push también en
      // Android empujaba una ruta que nada mostraba: confirmado en vivo,
      // "Ver detalle" no hacía nada ahí aunque en PC sí funcionaba.
      ExtensionUtils.openExtensionDetail(
        context,
        package: package,
        url: url,
      );
    });
  }

  Widget _buildAndroid(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 60,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: AppBar(
          title: Text(_c.title),
          actions: [
            if (widget.buildSettings != null)
              IconButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => widget.buildSettings!(context),
                  );
                },
                icon: const Icon(Icons.settings),
              ),
            IconButton(
              onPressed: () => _goToDetail(context),
              tooltip: 'Ver detalle',
              icon: const Icon(Icons.info_outline),
            ),
            IconButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) {
                    return Obx(
                      () => PlayList(
                        title: _c.title,
                        list: _c.playList.map((e) => e.name).toList(),
                        selectIndex: _c.index.value,
                        onChange: (value) {
                          _c.index.value = value;
                          Get.back();
                        },
                      ),
                    );
                  },
                );
              },
              icon: const Icon(Icons.list),
            ),
          ],
        ),
      ),
    ).animate().fade();
  }

  Widget _buildDesktop(BuildContext context) {
    return Obx(
      () => Container(
        width: double.infinity,
        height: 40,
        color: fluent.FluentTheme.of(context).micaBackgroundColor,
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            fluent.IconButton(
              icon: const Icon(fluent.FluentIcons.back),
              onPressed: () => RouterUtils.closeReader(context),
            ),
            const SizedBox(width: 16),
            // DragToMoveArea only on the title text — buttons stay outside
            // so clicking them never accidentally drags the window.
            Expanded(
              child: DragToMoveArea(
                child: Text(
                  _c.title + _c.playList[_c.index.value].name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (widget.buildSettings != null) ...[
              fluent.FlyoutTarget(
                controller: _settingFlayoutcontroller,
                child: fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.settings),
                  onPressed: () {
                    // full: sin esto el flyout se anclaba pegado al botón de
                    // configuración (arriba a la derecha) — para un menú de
                    // elegir modo de lectura eso queda perdido/incómodo de
                    // leer. full le da todo el ancho de pantalla como
                    // constraints y deja que el propio contenido se
                    // posicione (ComicReaderSettings ya lo centra con
                    // Center en su rama de escritorio).
                    _settingFlayoutcontroller.showFlyout(
                      placementMode: fluent.FlyoutPlacementMode.full,
                      barrierColor: Colors.black.withValues(alpha: 0.35),
                      builder: (context) {
                        return widget.buildSettings!(context);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
            fluent.Tooltip(
              message: 'Ver detalle',
              child: fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.info),
                onPressed: () => _goToDetail(context),
              ),
            ),
            const SizedBox(width: 8),
            fluent.FlyoutTarget(
              controller: _playListFlayoutcontroller,
              child: fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.collapse_menu),
                onPressed: () {
                  _playListFlayoutcontroller.showFlyout(builder: (context) {
                    return SizedBox(
                      width: 300,
                      child: Obx(
                        () => PlayList(
                          title: _c.title,
                          list: _c.playList.map((e) => e.name).toList(),
                          selectIndex: _c.index.value,
                          onChange: (value) {
                            _c.index.value = value;
                            router.pop();
                          },
                        ),
                      ),
                    );
                  });
                },
              ),
            ),
            SizedBox(
              width: 138,
              // La tercera copia de los mismos tres botones. Ver
              // BotonesVentana.
              child: BotonesVentana(
                brightness: fluent.FluentTheme.of(context).brightness,
              ),
            ),
          ],
        ),
      ).animate().fade(),
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
