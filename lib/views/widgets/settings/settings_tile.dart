import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class SettingsTile extends StatefulWidget {
  const SettingsTile({
    super.key,
    this.icon,
    required this.title,
    this.trailing,
    this.buildSubtitle,
    this.onTap,
    this.isCard = false,
  });
  final Widget? icon;
  final String title;
  final String Function()? buildSubtitle;
  final Function()? onTap;
  final Widget? trailing;
  final bool isCard;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  Widget _buildAndroid(BuildContext context) {
    return ListTile(
      leading: widget.icon,
      title: Text(
        widget.title,
        style: const TextStyle(color: HomeTheme.textPrimary),
      ),
      subtitle: widget.buildSubtitle != null
          ? Text(
              widget.buildSubtitle!.call(),
              style: const TextStyle(color: HomeTheme.textMuted),
            )
          : null,
      trailing: widget.trailing,
      onTap: widget.onTap,
    );
  }

  Widget _buildDesktop(BuildContext context) {
    Widget content = Row(
      children: [
        if (widget.icon != null) ...[
          widget.icon!,
          const SizedBox(width: 16),
        ],
        // Expanded, no un ancho libre: sin esto, un subtítulo largo (ej. el
        // aviso de "Bloqueado en Directa por estabilidad...") hacía que la
        // Column creciera a su ancho natural en una sola línea, empujando el
        // trailing (botón/campo) fuera de la ventana — "RIGHT OVERFLOWED",
        // reportado en vivo con captura. Expanded la acota al espacio
        // disponible para que el texto ajuste ahí (Text ya hace wrap por
        // defecto dentro de ese ancho).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.title,
                style: const TextStyle(color: HomeTheme.textPrimary),
              ),
              if (widget.buildSubtitle != null)
                Text(
                  widget.buildSubtitle!.call(),
                  style:
                      const TextStyle(fontSize: 12, color: HomeTheme.textMuted),
                )
            ],
          ),
        ),
        const SizedBox(width: 12),
        widget.trailing ?? const SizedBox(),
      ],
    );

    if (widget.onTap != null) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: content,
        ),
      );
    }

    if (widget.isCard) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HomeTheme.border),
        ),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: content,
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
