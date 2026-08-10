import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/watch/novel_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/watch/boton_llenar_pantalla.dart';

class NovelReaderSettings extends StatefulWidget {
  const NovelReaderSettings(this.tag, {super.key});
  final String tag;

  @override
  State<NovelReaderSettings> createState() => _NovelReaderSettingsState();
}

class _NovelReaderSettingsState extends State<NovelReaderSettings> {
  late final NovelController _c = Get.find<NovelController>(tag: widget.tag);

  Widget _buildAndroid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text("novel-settings.font-size".i18n)),
              // Solo Android, igual que en el lector de cómics: en
              // escritorio no va este botón.
              Obx(
                () => BotonLlenarPantalla(
                  activo: _c.llenarPantalla.value,
                  onTap: () =>
                      _c.llenarPantalla.value = !_c.llenarPantalla.value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Obx(
            () => Slider(
              value: _c.fontSize.value,
              onChanged: (value) {
                _c.fontSize.value = value;
              },
              min: 12,
              max: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    // Center: el Flyout que abre esto (ControlPanelHeader) usa
    // placementMode: full, que da toda la pantalla como constraints y deja
    // que el contenido se posicione solo — sin esto quedaba pegado arriba a
    // la izquierda en vez de en el medio.
    return Center(
      child: fluent.Card(
        backgroundColor: fluent.FluentTheme.of(context).micaBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("novel-settings.font-size".i18n),
            const SizedBox(height: 16),
            Obx(
              () => SizedBox(
                width: 200,
                child: fluent.Slider(
                  value: _c.fontSize.value,
                  onChanged: (value) {
                    _c.fontSize.value = value;
                  },
                  min: 12,
                  max: 24,
                ),
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
