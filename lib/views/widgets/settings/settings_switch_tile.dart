import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class SettingsSwitchTile extends StatefulWidget {
  const SettingsSwitchTile({
    super.key,
    this.icon,
    required this.title,
    required this.buildValue,
    required this.onChanged,
    this.buildSubtitle,
    this.isCard = false,
  });
  final Widget? icon;
  final String title;
  final String Function()? buildSubtitle;
  final bool Function() buildValue;
  final Function(bool) onChanged;
  final bool isCard;

  @override
  State<SettingsSwitchTile> createState() => _SettingsSwitchTileState();
}

class _SettingsSwitchTileState extends State<SettingsSwitchTile> {
  void _alternar() {
    widget.onChanged(!widget.buildValue());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      isCard: widget.isCard,
      icon: widget.icon,
      title: widget.title,
      buildSubtitle: widget.buildSubtitle,
      // ── La fila entera activa el interruptor, no solo el Switch/Toggle ──
      //
      // Sin esto, `SettingsTile` no tenía `onTap` y por lo tanto NUNCA se
      // envolvía en `FocusableCard` en televisor (ver el `if` que decide eso
      // en `SettingsTile.build`): de todos los ajustes, los interruptores
      // eran los únicos sin marco de foco y sin garantía de que el D-pad
      // llegara al `Switch` en sí, que es un blanco chico dentro de la fila.
      //
      // Con la fila entera como blanco, tocar en cualquier parte también
      // alterna en mouse/dedo — que ya es lo que hacen la mayoría de las
      // apps de ajustes — y en TV el SELECT del mando cae sobre algo del
      // tamaño de toda la fila, no del interruptor solo.
      onTap: _alternar,
      trailing: IgnorePointer(
        // El propio Switch/Toggle deja de escuchar toques: si los dos
        // reaccionaran, un clic en el interruptor lo alternaría dos veces
        // (una por él, otra por la fila) y quedaría en el estado de
        // arranque. `IgnorePointer` no afecta el D-pad: eso lo maneja
        // `onTap` de arriba, no un gesto sobre este widget puntual.
        child: PlatformWidget(
          androidWidget: Switch(
            value: widget.buildValue(),
            onChanged: (_) {},
          ),
          desktopWidget: fluent.ToggleSwitch(
            checked: widget.buildValue(),
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }
}
