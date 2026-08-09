import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/watch/comic_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

class ComicReaderSettings extends StatelessWidget {
  const ComicReaderSettings(this.tag, {super.key});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ComicController>(tag: tag);

    if (Platform.isAndroid) {
      return Material(
        color: HomeTheme.cardSurface,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _content(c),
          ),
        ),
      );
    }

    // Desktop settings are opened from a Fluent Flyout (placementMode: full,
    // ver ControlPanelHeader) que da toda la pantalla como constraints y
    // deja que el contenido se posicione solo — Center lo pone en el medio
    // en vez de pegado a donde estaba el botón de configuración.
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomeTheme.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _content(c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(ComicController c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Text(
            'reader.reading-mode'.i18n,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: HomeTheme.textPrimary,
            ),
          ),
        ),
        Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeTile(
                mode: MangaReadMode.webTonn,
                icon: Icons.swap_vert,
                title: 'reader.mode-webtoon'.i18n,
                subtitle: 'reader.mode-webtoon-subtitle'.i18n,
                current: c.readType.value,
                onSelect: c.setReadMode,
              ),
              _ModeTile(
                mode: MangaReadMode.standard,
                icon: Icons.chevron_right,
                title: 'reader.mode-ltr'.i18n,
                subtitle: 'reader.mode-ltr-subtitle'.i18n,
                current: c.readType.value,
                onSelect: c.setReadMode,
              ),
              _ModeTile(
                mode: MangaReadMode.rightToLeft,
                icon: Icons.chevron_left,
                title: 'reader.mode-rtl'.i18n,
                subtitle: 'reader.mode-rtl-subtitle'.i18n,
                current: c.readType.value,
                onSelect: c.setReadMode,
              ),
            ],
          ),
        ),
        Divider(height: 24, color: HomeTheme.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            'reader.strip-align'.i18n,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: HomeTheme.textPrimary,
            ),
          ),
        ),
        // No cierra el panel al elegir, a diferencia del modo de lectura: acá
        // se quiere ver el efecto y probar las tres sin tener que reabrirlo.
        Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AlignTile(
                value: ComicController.alineacionIzquierda,
                icon: Icons.align_horizontal_left,
                title: 'reader.strip-align-left'.i18n,
                current: c.stripAlign.value,
                onSelect: c.setStripAlign,
              ),
              _AlignTile(
                value: ComicController.alineacionCentro,
                icon: Icons.align_horizontal_center,
                title: 'reader.strip-align-center'.i18n,
                current: c.stripAlign.value,
                onSelect: c.setStripAlign,
              ),
              _AlignTile(
                value: ComicController.alineacionDerecha,
                icon: Icons.align_horizontal_right,
                title: 'reader.strip-align-right'.i18n,
                current: c.stripAlign.value,
                onSelect: c.setStripAlign,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Fila de alineación de la franja. Igual que _ModeTile pero de una sola
/// línea (no hace falta subtítulo: los iconos ya lo dicen) y sin cerrar el
/// panel al elegir.
class _AlignTile extends StatelessWidget {
  const _AlignTile({
    required this.value,
    required this.icon,
    required this.title,
    required this.current,
    required this.onSelect,
  });

  final String value;
  final IconData icon;
  final String title;
  final String current;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected
            ? HomeTheme.accentPink.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSelect(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? HomeTheme.accentPink : HomeTheme.textMuted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected
                          ? HomeTheme.accentPink
                          : HomeTheme.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: HomeTheme.accentPink,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.current,
    required this.onSelect,
  });

  final MangaReadMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final MangaReadMode current;
  final void Function(MangaReadMode) onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = mode == current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected
            ? HomeTheme.accentPink.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            onSelect(mode);
            Navigator.of(context).maybePop();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? HomeTheme.accentPink : HomeTheme.textMuted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          color: selected
                              ? HomeTheme.accentPink
                              : HomeTheme.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: HomeTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: HomeTheme.accentPink,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
