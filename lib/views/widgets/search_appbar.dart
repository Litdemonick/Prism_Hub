import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

class SearchAppBar extends StatefulWidget implements PreferredSizeWidget {
  SearchAppBar({
    super.key,
    required this.title,
    required this.textEditingController,
    this.actions,
    this.bottom,
    this.flexibleSpace,
    this.toolbarHeight,
    this.onSubmitted,
    this.onChanged,
    this.hintText,
    this.leading,
    this.backgroundColor,
  }) : preferredSize =
            _PreferredAppBarSize(toolbarHeight, bottom?.preferredSize.height);
  // Ambos opcionales y en null por defecto — los usos existentes quedan
  // exactamente igual. Los usa la zona +18 del buscador, que se abre como ruta
  // encima y por eso necesita una salida visible (acá no hay pestañas) y el
  // acento rojo para que se note que no es el buscador normal. Ojo: `leading`
  // solo se aplica cuando el campo de búsqueda está cerrado; con el campo
  // abierto manda el botón propio de la AppBar, que lo cierra.
  final Widget? leading;
  final Color? backgroundColor;
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? flexibleSpace;
  final double? toolbarHeight;
  final TextEditingController textEditingController;
  final Function(String)? onSubmitted;
  final Function(String)? onChanged;
  final String? hintText;

  @override
  State<SearchAppBar> createState() => _SearchAppBarState();

  @override
  final Size preferredSize;
}

class _SearchAppBarState extends State<SearchAppBar> {
  late bool _showSearch = widget.textEditingController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: widget.backgroundColor,
      leading: _showSearch
          ? IconButton(
              onPressed: () {
                setState(() {
                  widget.textEditingController.clear();
                  widget.onSubmitted?.call('');
                  _showSearch = false;
                });
              },
              icon: const Icon(Icons.arrow_back),
            )
          : widget.leading,
      title: _showSearch
          ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (_, __) async {
                if (_showSearch) {
                  setState(() {
                    widget.textEditingController.clear();
                    widget.onSubmitted?.call('');
                    _showSearch = false;
                  });
                  return;
                }
              },
              child: TextField(
                controller: widget.textEditingController,
                decoration: InputDecoration(
                  hintText: widget.hintText ?? widget.title,
                  border: InputBorder.none,
                ),
                autofocus: true,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
              ),
            )
          : Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // El mismo título que el resto de las zonas.
              //
              // Acá iba un Text pelado, así que Buscar y Extensiones —las dos
              // que usan esta barra— caían al estilo por defecto del tema:
              // más chico, más finito y gris, al lado de Inicio o Biblioteca
              // que ya estaban en blanco y a 25. Se notaba al cambiar de
              // pestaña.
              style: HomeTheme.tituloDeZona(
                // Acostado en un teléfono, 25 en la barra se come alto que le
                // hace falta al contenido.
                bajo: MediaQuery.sizeOf(context).height < 520,
              ),
            ),
      actions: [
        IconButton(
          onPressed: () {
            setState(() {
              if (_showSearch) {
                widget.textEditingController.clear();
                widget.onSubmitted?.call('');
                return;
              }
              _showSearch = !_showSearch;
            });
          },
          icon: Icon(_showSearch ? Icons.close : Icons.search),
        ),
        ...widget.actions ?? [],
      ],
      bottom: widget.bottom,
      flexibleSpace: widget.flexibleSpace,
    );
  }
}

class _PreferredAppBarSize extends Size {
  _PreferredAppBarSize(this.toolbarHeight, this.bottomHeight)
      : super.fromHeight(
            (toolbarHeight ?? kToolbarHeight) + (bottomHeight ?? 0));

  final double? toolbarHeight;
  final double? bottomHeight;
}
