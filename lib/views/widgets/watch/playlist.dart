import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class PlayList extends fluent.StatelessWidget {
  const PlayList({
    super.key,
    required this.title,
    required this.list,
    required this.selectIndex,
    required this.onChange,
  });
  final String title;
  final List<String> list;
  final int selectIndex;
  final Function(int) onChange;

  Widget _buildAndroid(BuildContext context) {
    // Fuera de rango la lista arranca en la primera, que es mejor que
    // reventar: pasa si la extensión devuelve menos capítulos que la última
    // vez y el índice guardado apunta a uno que ya no está.
    final actual = list.isEmpty ? 0 : selectIndex.clamp(0, list.length - 1);

    return Material(
      color: HomeTheme.cardSurface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // El título arriba, igual que en la hoja de ajustes del lector.
            // Antes la lista abría sin nada: una tira de nombres sueltos, sin
            // decir de qué obra son ni qué es lo que se está eligiendo.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: HomeTheme.textPrimary,
                ),
              ),
            ),
            Flexible(
              child: ScrollablePositionedList.builder(
                itemCount: list.length,
                initialScrollIndex: actual,
                padding: const EdgeInsets.only(bottom: 12),
                itemBuilder: (context, index) {
                  return PlaylistAndroidTile(
                    title: list[index],
                    // Por índice y no por nombre.
                    //
                    // Comparaba `list[selectIndex] == contact`, o sea el TEXTO.
                    // Con dos capítulos que se llaman igual —pasa seguido: dos
                    // partes de un especial, o una extensión que devuelve el
                    // nombre vacío— se encendían los dos a la vez, y ninguno de
                    // los dos era necesariamente el que estabas leyendo.
                    selected: index == actual,
                    onTap: () => onChange(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final actual = list.isEmpty ? 0 : selectIndex.clamp(0, list.length - 1);
    return ScrollablePositionedList.builder(
      itemCount: list.length,
      initialScrollIndex: actual,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        return fluent.ListTile.selectable(
          title: Text(list[index]),
          onPressed: () {
            onChange(index);
          },
          // Por índice, mismo motivo que en Android.
          selected: index == actual,
        );
      },
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

/// Una fila de la lista de capítulos.
///
/// ── Por qué se rehizo ───────────────────────────────────────────────────
///
/// Era un `Card` que, al estar elegido, se pintaba entero del rosa del tema:
/// una pastilla maciza y saturada cruzando la pantalla, con el texto en
/// negativo. No se parecía a nada más de la app —la hoja de ajustes del propio
/// lector, que está a un botón de distancia, usa el rosa apenas insinuado de
/// fondo y el texto en rosa— así que las dos hojas del mismo lector se veían
/// como de dos apps distintas.
///
/// Ahora es la misma fila que allá: redondeada, con el fondo apenas teñido, el
/// texto en rosa y la tilde a la derecha. Y las que no están elegidas no pintan
/// nada, así que la lista se lee como una lista y no como una pila de cajas.
class PlaylistAndroidTile extends StatelessWidget {
  const PlaylistAndroidTile({
    super.key,
    required this.title,
    required this.onTap,
    required this.selected,
  });
  final String title;
  final Function() onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected
            ? HomeTheme.accentPink.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                  Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(
                      Icons.check_circle,
                      size: 20,
                      color: HomeTheme.accentPink,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
