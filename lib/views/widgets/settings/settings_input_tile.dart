import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';

class SettingsIntpuTile extends fluent.StatefulWidget {
  const SettingsIntpuTile({
    super.key,
    this.icon,
    required this.title,
    required this.onChanged,
    required this.buildText,
    required this.buildSubtitle,
    this.trailing = const Icon(Icons.chevron_right),
    this.isCard = false,
    this.enabled = true,
  });
  final Widget? icon;
  final String title;
  final String Function() buildSubtitle;
  final String Function() buildText;
  final Widget trailing;
  final Function(String) onChanged;
  final bool isCard;
  // false bloquea la edición — el valor sigue mostrándose pero no se puede
  // tocar/escribir (usado para la dirección de proxy, que solo tiene sentido
  // si el tipo de proxy no está bloqueado en "Directo").
  final bool enabled;

  @override
  fluent.State<SettingsIntpuTile> createState() => _SettingsIntpuTileState();
}

class _SettingsIntpuTileState extends fluent.State<SettingsIntpuTile> {
  TextEditingController? _controller;
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.buildText());
    // En desktop, commitear al perder el foco (además de al tocar Enter) —
    // sin esto, un usuario que hace click afuera en vez de tocar Enter
    // perdía el cambio silenciosamente.
    _focusNode = FocusNode()
      ..addListener(() {
        if (_focusNode?.hasFocus == false) _commit();
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focusNode?.dispose();
    super.dispose();
  }

  // Confirma el valor una sola vez (al cerrar el diálogo en Android, o al
  // salir del campo/tocar Enter en desktop) en vez de en cada tecla — antes
  // onChanged corría por cada carácter tipeado, así que mientras se
  // reescribía el valor (ej. la URL del repo de extensiones) cada estado a
  // medio escribir disparaba de inmediato un guardado + un refresh de red,
  // lo que se veía como que el programa "bugueaba" mientras se tipeaba.
  void _commit() {
    widget.onChanged(_controller!.text);
  }

  Widget _buildAndroid(BuildContext context) {
    return ListTile(
      leading: widget.icon,
      title: Text(
        widget.title,
        style: const TextStyle(color: HomeTheme.textPrimary),
      ),
      subtitle: Text(
        widget.buildSubtitle(),
        style: const TextStyle(color: HomeTheme.textMuted),
      ),
      trailing: widget.trailing,
      onTap: !widget.enabled
          // Con onTap en null el campo no hacía absolutamente nada al tocarlo
          // y parecía que la app se había colgado. Mejor decir por qué no se
          // puede editar.
          ? () => showPlatformSnackbar(
                context: context,
                content: 'settings.locked-field'.i18n,
              )
          : () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: HomeTheme.cardSurface,
                    // scrollable: hace que título + contenido scrolleen
                    // JUNTOS. Con el teclado abierto en horizontal quedan
                    // ~100px de alto útil y la estructura fija del
                    // AlertDialog (título + campo + botón) no entra ni de
                    // cerca — confirmado en vivo ("BOTTOM OVERFLOWED BY 200
                    // PIXELS"). insetPadding chico suma el resto del espacio
                    // que en horizontal se iba en márgenes laterales.
                    scrollable: true,
                    insetPadding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    title: Text(
                      widget.title,
                      style: const TextStyle(color: HomeTheme.textPrimary),
                    ),
                    content: TextField(
                      controller: _controller,
                      // Sin autofocus: abrir el teclado en el mismo frame
                      // en que el diálogo todavía está entrando (animación)
                      // empeoraba el overflow — con un toque manual del
                      // usuario el diálogo ya está asentado.
                      style: const TextStyle(color: HomeTheme.textPrimary),
                      cursorColor: HomeTheme.accentPink,
                      onSubmitted: (_) {
                        _commit();
                        Navigator.pop(context);
                        setState(() {});
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          _commit();
                          Navigator.pop(context);
                          setState(() {});
                        },
                        child: Text(
                          'common.confirm'.i18n,
                          style: const TextStyle(color: HomeTheme.accentPink),
                        ),
                      ),
                    ],
                  );
                },
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
      trailing: Expanded(
          child: fluent.TextBox(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        onSubmitted: (_) => _commit(),
      )),
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
