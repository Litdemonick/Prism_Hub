import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:get/get.dart';
import 'package:prismhub/views/widgets/settings/settings_subtitle.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';

class SettingsExpanderTile extends StatefulWidget {
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

  @override
  State<SettingsExpanderTile> createState() => _SettingsExpanderTileState();
}

class _SettingsExpanderTileState extends State<SettingsExpanderTile> {
  // El Expander de fluent ANIMA la apertura en el primer frame cuando arranca
  // expandido, así que al entrar a Ajustes la sección de "Acerca de" se abría
  // sola con animación y empujaba todo lo de abajo: la página entera se movía
  // sin que el usuario tocara nada. Se desactiva la animación SOLO para ese
  // primer frame; a partir de ahí vuelve a la normal, así desplegar y plegar
  // a mano se sigue viendo igual que siempre.
  Duration _animation = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _animation = const Duration(milliseconds: 150));
      }
    });
  }

  Widget _buildAndroid(BuildContext context) {
    if (widget.noPage) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text(
              widget.title,
              style:
                  const TextStyle(fontSize: 20, color: HomeTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              widget.subTitle,
              style: const TextStyle(fontSize: 12, color: HomeTheme.textMuted),
            ),
            const SizedBox(height: 15),
            widget.content,
          ],
        ),
      );
    }

    Widget iconWidget = widget.androidIcon != null
        ? Icon(widget.androidIcon, size: 24, color: HomeTheme.accentPink)
        : widget.icon != null
            ? Icon(widget.icon, size: 24, color: HomeTheme.accentPink)
            : widget.leading!;

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
          title: widget.title,
          buildSubtitle: () => widget.subTitle,
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
                  title: Text(widget.title,
                      style: const TextStyle(color: HomeTheme.textPrimary)),
                ),
                // SingleChildScrollView: en horizontal el alto útil es la
                // mitad y este contenido (varias opciones apiladas) no entra
                // — sin scroll desbordaba con la franja amarilla (confirmado
                // en vivo en la subpágina "General").
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  // FluentTheme acá porque en Android NO hay ninguno: la raíz
                  // es GetMaterialApp y FluentApp solo se monta en escritorio.
                  // Algunas secciones usan widgets de fluent (el selector
                  // numérico del reproductor, por ejemplo), que llaman a
                  // FluentTheme.of(context) y revientan sin uno arriba — la
                  // subpágina no llegaba a construirse y parecía que el botón
                  // no hacía nada.
                  child: fluent.FluentTheme(
                    data: fluent.FluentThemeData(
                      brightness: Brightness.dark,
                      accentColor: fluent.Colors.purple,
                      scaffoldBackgroundColor: HomeTheme.bg,
                    ),
                    child: widget.content,
                  ),
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
      initiallyExpanded: widget.open,
      animationDuration: _animation,
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
      leading: widget.icon != null
          ? Icon(widget.icon, size: 24, color: HomeTheme.accentPink)
          : widget.leading,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(widget.title,
              style: const TextStyle(color: HomeTheme.textPrimary)),
          const SizedBox(height: 2),
          SettingsSubtitle(widget.subTitle),
          const SizedBox(height: 15)
        ],
      ),
      content: widget.content,
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
