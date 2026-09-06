import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/horizontal_scroll_fade.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/tema_fluent_seguro.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/tv/region_de_foco.dart';

class HorizontalList extends StatefulWidget {
  const HorizontalList({
    super.key,
    required this.title,
    required this.onClickMore,
    this.itemCount,
    this.itemBuilder,
    this.contentBuilder,
    this.mostrarFlecha = true,
  }) : assert(
          (itemCount != null && itemBuilder != null) || contentBuilder != null,
          "itemCount and itemBuilder or contentBuilder must not be null",
        );
  final String title;
  final void Function() onClickMore;
  final int? itemCount;
  final Widget? Function(BuildContext, int)? itemBuilder;
  final Widget Function(ScrollController)? contentBuilder;

  /// En `false` para una sección que no lleva a ningún lado (`onClickMore`
  /// vacío) — ver el comentario largo en `HorizontalTitle`.
  final bool mostrarFlecha;

  @override
  State<HorizontalList> createState() => _HorizontalListState();
}

class _HorizontalListState extends State<HorizontalList> {
  final ScrollController _controller = ScrollController();

  _horzontalMove(bool left) {
    _controller.animateTo(
      _controller.offset + (left ? -500 : 500),
      duration: const Duration(milliseconds: 500),
      curve: Curves.ease,
    );
  }

  /// El botón "Mostrar todo", enfocable de verdad en televisor.
  ///
  /// ── El problema ─────────────────────────────────────────────────────
  ///
  /// Era un `TextButton` suelto, arriba de la fila y afuera de su
  /// `ListView`: el mando lo alcanzaba (Flutter siempre encuentra ALGO
  /// enfocable), pero para nuestro sistema de "topes" no contaba como
  /// parte de ninguna fila —eso lo decide `FranjaHorizontalTv`/el scroll
  /// horizontal, y este botón no tiene ninguno de los dos—. Sin esa
  /// identidad, apretar a la derecha desde acá no tenía tope: cascadeaba
  /// hacia la fila de tarjetas de abajo. Reportado en vivo, en el
  /// buscador: «en el botón "Mostrar todo" y hago derecha, baja abajo».
  ///
  /// ── La solución ─────────────────────────────────────────────────────
  ///
  /// Envuelto en `FranjaFijaTv`, el botón pasa a ser su propia fila de UNA
  /// tarjeta: a la derecha no hay ninguna vecina, así que el tope frena
  /// ahí en vez de escaparse a cualquier lado. Y con `FocusableCard` en
  /// vez de un `TextButton` a secas, se ve como el resto de lo enfocable
  /// en TV, con su marco y su resplandor.
  Widget _botonMostrarTodo() {
    if (!PlatformTv.esTelevisionSync) {
      return TextButton(
        onPressed: widget.onClickMore,
        child: Text('common.show-all'.i18n),
      );
    }
    return FranjaFijaTv(
      child: FocusableCard(
        borderRadius: 8,
        onTap: widget.onClickMore,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'common.show-all'.i18n,
            style: TextStyle(
              color: HomeTheme.accentPink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // Con estilo explícito y no heredado del tema: en escritorio la
            // raíz es FluentApp, y ahí un Text sin estilo cae en la tipografía
            // de Fluent, que traía el color de su tema oscuro. Sobre el fondo
            // claro el nombre de la extensión quedaba invisible.
            Text(
              widget.title,
              style: TextStyle(
                color: HomeTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            // Mismo criterio que la flecha de escritorio: sin destino real,
            // sin botón que prometa uno.
            if (widget.mostrarFlecha) _botonMostrarTodo(),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.contentBuilder != null)
          widget.contentBuilder!(_controller)
        else
          SizedBox(
            height: 170,
            child: HorizontalScrollFade(
              controller: _controller,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                controller: _controller,
                itemCount: widget.itemCount,
                itemBuilder: ((context, index) {
                  return Container(
                    width: 110,
                    margin: const EdgeInsets.only(right: 16),
                    child: widget.itemBuilder!(context, index),
                  );
                }),
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            HorizontalTitle(
              widget.title,
              onClick: widget.onClickMore,
              mostrarFlecha: widget.mostrarFlecha,
            ),
            const Spacer(),
            Row(
              children: [
                fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.chevron_left),
                    onPressed: () {
                      _horzontalMove(true);
                    }),
                const SizedBox(width: 8),
                fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.chevron_right),
                  onPressed: () {
                    _horzontalMove(false);
                  },
                )
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.contentBuilder != null)
          widget.contentBuilder!(_controller)
        else
          SizedBox(
            height: 280,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              controller: _controller,
              itemCount: widget.itemCount,
              itemBuilder: ((context, index) {
                return Container(
                  width: 170,
                  margin: const EdgeInsets.only(right: 16),
                  child: widget.itemBuilder!(context, index),
                );
              }),
            ),
          ),
        const SizedBox(height: 16),
      ],
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

class HorizontalTitle extends StatefulWidget {
  const HorizontalTitle(
    this.text, {
    super.key,
    required this.onClick,
    this.mostrarFlecha = true,
  });
  final String text;
  final Function() onClick;

  /// La flechita de "hay más para ver acá" — en `false` para una sección
  /// que no lleva a ningún lado (ej. "Más relevantes" en Buscar, cuyo
  /// `onClick` no hace nada): sin esto, el título se veía clickeable —
  /// cursor de mano, resaltado al pasar el mouse, flecha — prometiendo una
  /// navegación que nunca pasaba.
  final bool mostrarFlecha;

  @override
  State<HorizontalTitle> createState() => _HorizontalTitleState();
}

class _HorizontalTitleState extends State<HorizontalTitle> {
  bool _hoverTitle = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.mostrarFlecha) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: HomeTheme.textPrimary,
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) {
        setState(() {
          _hoverTitle = true;
        });
      },
      onExit: (event) {
        setState(() {
          _hoverTitle = false;
        });
      },
      child: GestureDetector(
        onTap: () {
          widget.onClick();
        },
        child: AnimatedContainer(
          padding: EdgeInsets.symmetric(
            horizontal: _hoverTitle ? 20 : 0,
            vertical: 10,
          ),
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            color: _hoverTitle
                ? temaFluent(context).brightness == Brightness.light
                    ? const Color.fromARGB(19, 27, 26, 25)
                    : const Color.fromARGB(19, 186, 186, 186)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              // Con el color puesto, no heredado.
              //
              // Este es el título de la fila en escritorio, y era un TextStyle
              // sin color: caía en la tipografía de Fluent, que trae la suya
              // según SU tema. El nombre de la extensión quedaba invisible
              // sobre el fondo claro — la flecha de al lado sí se veía, porque
              // los iconos de Fluent sí toman el color del tema.
              Text(
                widget.text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: HomeTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                fluent.FluentIcons.chevron_right_med,
                size: 14,
                color: HomeTheme.textPrimary,
              )
            ],
          ),
        ),
      ),
    );
  }
}
