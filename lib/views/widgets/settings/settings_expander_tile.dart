import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:get/get.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';

class SettingsExpanderTile extends StatelessWidget {
  const SettingsExpanderTile({
    super.key,
    this.icon,
    this.androidIcon,
    this.leading,
    required this.content,
    required this.title,
    required this.subTitle,
    this.open = false,
    this.noPage = false,
  });
  final IconData? icon;
  final IconData? androidIcon;
  final Widget? leading;
  final String title;
  final String subTitle;
  final bool open;
  final Widget content;
  // 不使用二级页面
  final bool noPage;

  Widget _buildAndroid(BuildContext context) {
    if (noPage) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text(
              title,
              style:
                  const TextStyle(fontSize: 20, color: HomeTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              subTitle,
              style: const TextStyle(fontSize: 12, color: HomeTheme.textMuted),
            ),
            const SizedBox(height: 15),
            content,
          ],
        ),
      );
    }

    Widget iconWidget = androidIcon != null
        ? Icon(androidIcon, size: 24, color: HomeTheme.accentPink)
        : icon != null
            ? Icon(icon, size: 24, color: HomeTheme.accentPink)
            : leading!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      // El color de fondo va en un Material, no en la decoración del
      // Container: el ListTile de adentro pinta su fondo y su efecto de
      // toque sobre el Material más cercano, y con el color en el Container
      // esos efectos quedaban tapados — Flutter lo avisaba en cada arranque
      // ("ListTile background color or ink splashes may be invisible", una
      // vez por tarjeta).
      child: Material(
        color: HomeTheme.cardSurface,
        child: SettingsTile(
          icon: iconWidget,
          title: title,
          buildSubtitle: () => subTitle,
          onTap: () {
            Get.to(
              () => Scaffold(
                backgroundColor: HomeTheme.bg,
                // El teclado se superpone en vez de encoger — los campos de
                // esta subpágina abren diálogo propio, así que no hace falta
                // que el body se achique (y achicándose desbordaba).
                resizeToAvoidBottomInset: false,
                appBar: AppBar(
                  backgroundColor: HomeTheme.bg,
                  title: Text(title,
                      style: const TextStyle(color: HomeTheme.textPrimary)),
                ),
                // SingleChildScrollView: en horizontal el alto útil es la
                // mitad y este contenido (varias opciones apiladas) no entra
                // — sin scroll desbordaba con la franja amarilla (confirmado
                // en vivo en la subpágina "General").
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: content,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return fluent.Expander(
      initiallyExpanded: open,
      headerBackgroundColor:
          fluent.WidgetStateProperty.all(HomeTheme.cardSurface),
      contentBackgroundColor: HomeTheme.cardSurface,
      headerShape: (open) => RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(10),
          bottom: open ? Radius.zero : const Radius.circular(10),
        ),
        side: const BorderSide(color: HomeTheme.border),
      ),
      contentShape: (open) => const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
        side: BorderSide(color: HomeTheme.border),
      ),
      leading: icon != null
          ? Icon(icon, size: 24, color: HomeTheme.accentPink)
          : leading,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: HomeTheme.textPrimary)),
          const SizedBox(height: 2),
          Text(
            subTitle,
            style: const TextStyle(fontSize: 12, color: HomeTheme.textMuted),
          ),
          const SizedBox(height: 15)
        ],
      ),
      content: content,
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
