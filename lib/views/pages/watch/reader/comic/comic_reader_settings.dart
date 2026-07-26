import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/watch/comic_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Ajustes del lector de manga — hoy solo el modo de lectura. El modo se
// guarda POR TÍTULO (ver ComicController.setReadMode), así cada obra
// recuerda cómo la venís leyendo: webtoon para manhwa, página a página para
// manga tradicional.
class ComicReaderSettings extends StatelessWidget {
  const ComicReaderSettings(this.tag, {super.key});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ComicController>(tag: tag);
    // Material envolvente: los ListTile de abajo lo exigen como ancestro, y
    // en escritorio este panel se muestra dentro de un Flyout de fluent_ui,
    // que NO trae Material — sin esto tiraba "No Material widget found" y la
    // pantalla entera se ponía roja (confirmado en vivo).
    //
    // Con fondo propio (no transparente): el panel se dibuja ENCIMA del
    // manga, y siendo transparente las páginas se veían atrás mezcladas con
    // el texto, ilegible (confirmado en vivo).
    // Material transparente + tarjeta centrada: antes esto era una franja
    // que cruzaba toda la pantalla pegada al borde, muy fea sobre el manga.
    // Ahora es un panel acotado y centrado, con su propio fondo y borde.
    // Android: esto se muestra dentro de un showModalBottomSheet, que YA
    // trae su propio fondo atenuado, su animación desde abajo y su cierre al
    // tocar afuera. Meterle encima otra capa oscura y una tarjeta centrada
    // quedaba raro y redundante — acá va solo el contenido.
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

    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      // El SafeArea envuelve SOLO la tarjeta, no el fondo: cuando envolvía
      // todo, recortaba el área pintada y quedaba una franja sin oscurecer
      // arriba (confirmado en vivo). Así el atenuado cubre de borde a borde
      // y la tarjeta sigue respetando muescas/barras del sistema.
      //
      // Tocar el fondo cierra el panel. El GestureDetector va acá afuera y
      // la tarjeta lleva el suyo propio que NO propaga (más abajo), así un
      // toque sobre la tarjeta no la cierra sin querer.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: SafeArea(
            // SingleChildScrollView: en horizontal (el lector se usa mucho así)
            // el alto útil es poco y sin scroll esto desbordaba.
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                // Absorbe el toque para que NO llegue al fondo: si no, tocar
                // la propia tarjeta la cerraría.
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      color: HomeTheme.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: HomeTheme.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x77000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _content(c),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Contenido compartido por ambas plataformas — lo único que cambia es cómo
  // se presenta (hoja desde abajo en celular, tarjeta centrada en PC).
  Widget _content(ComicController c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Text(
            'reader.reading-mode'.i18n,
            style: const TextStyle(
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
        const SizedBox(height: 8),
      ],
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
    // Fondo tenue + margen redondeado en la opción activa: antes solo
    // cambiaba el color del texto y costaba ver cuál estaba elegida.
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
                        style: const TextStyle(
                          color: HomeTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle,
                      size: 20, color: HomeTheme.accentPink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
