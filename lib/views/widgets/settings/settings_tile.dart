import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/settings/settings_subtitle.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

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
        style: TextStyle(color: HomeTheme.textPrimary),
      ),
      // SettingsSubtitle y no un Text pelado: es el que resalta "+18" en
      // rojo. Este camino (el ListTile de Android) se me había quedado sin
      // cambiar, así que el color solo se veía en escritorio.
      subtitle: widget.buildSubtitle != null
          ? SettingsSubtitle(widget.buildSubtitle!.call(), fontSize: 13)
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
                style: TextStyle(color: HomeTheme.textPrimary),
              ),
              if (widget.buildSubtitle != null)
                SettingsSubtitle(widget.buildSubtitle!.call())
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
        // clipBehavior + el mismo radio de 12 que el resto de las tarjetas de
        // la app: sin recorte, el contenido (y el área táctil) pisaba las
        // esquinas redondeadas y se veían mordidas o cuadradas según el
        // ancho, sobre todo en celular. También unifica el radio, que acá era
        // 10 y en las demás 12.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
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

  /// La fila de Ajustes, en televisor.
  ///
  /// ── Por qué no alcanzaba con la de Android ──────────────────────────
  ///
  /// Android TV ES `Platform.isAndroid`, así que caía en `_buildAndroid` —
  /// un `ListTile` con los tamaños de un teléfono, pensado para mirarse a
  /// treinta centímetros y tocarse con el dedo. En una pantalla que se mira
  /// desde el sillón queda chico, y el ícono y el texto se pierden.
  /// Pedido explícito: "más grande, compacto, botones y formas distintas".
  ///
  /// Es una tarjeta, no una fila suelta: con el foco de un mando saltando
  /// de una a otra, un bloque con bordes propios deja mucho más claro
  /// dónde está parado el usuario que una línea de texto en una lista.
  Widget _buildTv(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            IconTheme(
              data: IconThemeData(size: 28, color: HomeTheme.accentPink),
              child: widget.icon!,
            ),
            const SizedBox(width: 20),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    color: HomeTheme.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.buildSubtitle != null) ...[
                  const SizedBox(height: 4),
                  SettingsSubtitle(
                    widget.buildSubtitle!.call(),
                    fontSize: 15,
                  ),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 16),
            widget.trailing!,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformTv.esTelevisionSync) {
      final tile = _buildTv(context);
      // Las filas que no hacen nada al tocarse (un texto informativo, o una
      // cuyo control ya es enfocable solo —un interruptor, un desplegable—)
      // se dejan sin envolver: enfocarlas sería parar el recorrido del mando
      // en algo que no responde, o robarle el foco al control que sí.
      if (widget.onTap == null) return tile;
      return FocusableCard(
        borderRadius: 14,
        onTap: widget.onTap!,
        child: IgnorePointer(child: tile),
      );
    }
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
