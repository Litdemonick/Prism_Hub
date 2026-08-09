// ignore_for_file: deprecated_member_use
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class SettingsRadiosTile<T> extends StatefulWidget {
  const SettingsRadiosTile({
    super.key,
    this.icon,
    required this.title,
    this.buildSubtitle,
    required this.itemNameValue,
    required this.applyValue,
    required this.buildGroupValue,
    this.trailing = const Icon(Icons.chevron_right),
    this.isCard = false,
    this.enabled = true,
  });
  final Widget? icon;
  final String title;
  final String Function()? buildSubtitle;
  final Function(T value) applyValue;
  final Map<String, T> itemNameValue;
  final T Function() buildGroupValue;
  final Widget trailing;
  final bool isCard;
  // false bloquea la edición (el valor sigue mostrándose, pero no se puede
  // tocar/abrir el selector) — usado para el tipo de proxy, que causaba
  // problemas de estabilidad si se cambiaba de "Directo".
  final bool enabled;

  @override
  State<SettingsRadiosTile<T>> createState() => _SettingsRadiosTileState<T>();
}

class _SettingsRadiosTileState<T> extends State<SettingsRadiosTile<T>> {
  Widget _buildAndroid(BuildContext context) {
    return SettingsTile(
      isCard: widget.isCard,
      icon: widget.icon,
      title: widget.title,
      buildSubtitle: widget.buildSubtitle,
      trailing: widget.trailing,
      onTap: !widget.enabled
          ? null
          : () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: HomeTheme.cardSurface,
                  title: Text(
                    widget.title,
                    style: TextStyle(color: HomeTheme.textPrimary),
                  ),
                  scrollable: true,
                  // En horizontal el alto útil es poco y el margen por
                  // defecto (40px arriba/abajo) se come buena parte — con
                  // listas largas (ej. idiomas) eso desbordaba.
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  content: Column(
                    children: [
                      for (final item in widget.itemNameValue.entries)
                        RadioListTile<T>(
                          title: Text(
                            item.key,
                            style:
                                TextStyle(color: HomeTheme.textPrimary),
                          ),
                          activeColor: HomeTheme.accentPink,
                          value: item.value,
                          groupValue: widget.buildGroupValue(),
                          onChanged: (value) {
                            Navigator.pop(context);
                            widget.applyValue(value as T);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return SettingsTile(
      isCard: widget.isCard,
      icon: widget.icon,
      title: widget.title,
      buildSubtitle: widget.buildSubtitle,
      trailing: fluent.ComboBox<T>(
        items: [
          for (final item in widget.itemNameValue.entries)
            fluent.ComboBoxItem<T>(
              value: item.value,
              child: Text(item.key),
            )
        ],
        value: widget.buildGroupValue(),
        // fluent ComboBox se deshabilita solo con onChanged: null.
        onChanged: !widget.enabled
            ? null
            : (value) {
                widget.applyValue(value as T);
                setState(() {});
              },
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
