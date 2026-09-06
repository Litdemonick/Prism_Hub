import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/platform_tv.dart';

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
  // En TV el campo se muestra SIEMPRE.
  //
  // En teléfono/escritorio arranca cerrado y se abre con la lupa, porque ahí
  // el campo se usa de a ratos y el título vale más. En TV el teclado en
  // pantalla ya está a la izquierda, permanente: tener que apretar una lupa
  // primero para que aparezca dónde se escribe es un paso de más, y el
  // recorrido con el mando se vuelve ir y volver entre dos puntas.
  late bool _showSearch = PlatformTv.esTelevisionSync ||
      widget.textEditingController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: widget.backgroundColor,
      // ── En TV, ninguna flecha puesta sola ────────────────────────────
      //
      // `AppBar` agrega su PROPIA flecha de volver cuando `leading` es
      // null y la ruta puede hacer pop —de fábrica, sin que nadie la
      // pida—. Pasar `leading: null` en TV para que quien use este
      // widget ponga la flecha donde le corresponda (en el buscador de
      // una extensión, junto al botón "123" del teclado) no alcanzaba:
      // la de fábrica volvía a aparecer sola. Reportado en vivo con
      // foto: dos flechas juntas. Apagando esto en TV, `leading: null`
      // por fin significa "ninguna", no "la del sistema".
      automaticallyImplyLeading: !PlatformTv.esTelevisionSync,
      // ── En TV, nunca el botón de cerrar la búsqueda ─────────────────
      //
      // `_showSearch` nace en `true` en TV a propósito —el campo se
      // muestra siempre, sin lupa que tocar primero (ver el comentario de
      // arriba)—, pero eso hacía que ESTE botón (el de cerrar la
      // búsqueda y volver al título) también saliera siempre: un
      // `IconButton` de Material, sin marco de foco, plantado en la
      // esquina de una pantalla que ya tiene el teclado a un lado.
      // Reportado en vivo con foto: «dejá la flecha a la izquierda, no
      // pegada al teclado». Acá no hay "cerrar la búsqueda" que valga —en
      // TV el campo no se cierra nunca— así que directamente no compite
      // por ese lugar: se deja lo que quien use el AppBar haya puesto en
      // `leading` (nada, casi siempre).
      leading: PlatformTv.esTelevisionSync
          ? widget.leading
          : (_showSearch
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
              : widget.leading),
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
              child: _envolverEnTv(
                TextField(
                  controller: widget.textEditingController,
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? widget.title,
                    border: InputBorder.none,
                    isDense: PlatformTv.esTelevisionSync,
                    contentPadding: PlatformTv.esTelevisionSync
                        ? const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10)
                        : null,
                  ),
                  style: PlatformTv.esTelevisionSync
                      ? const TextStyle(fontSize: 17)
                      : null,
                  // En TV este campo solo MUESTRA lo que se va escribiendo: se
                  // escribe con el teclado en pantalla (ver TecladoTv). Sin
                  // esto, el campo pedía el foco al abrir y Android levantaba
                  // su propio teclado encima de los resultados — justo lo que
                  // el teclado propio viene a evitar.
                  readOnly: PlatformTv.esTelevisionSync,
                  canRequestFocus: !PlatformTv.esTelevisionSync,
                  // Y sin autofocus en TV: al volver de una ficha, esta barra
                  // se reconstruye y su autofocus se llevaba el foco puesto,
                  // así que la tarjeta desde la que habías salido dejaba de
                  // estar marcada y el mando arrancaba de nuevo desde arriba.
                  autofocus: !PlatformTv.esTelevisionSync,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                ),
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
        // La lupa (y su cruz para cerrar) no van en TV: ahí el campo está
        // siempre puesto y lo que se escribe se borra desde el propio
        // teclado en pantalla, que tiene su tecla para eso. El botón sería
        // un destino más que cruzar con el mando para algo que ya está
        // resuelto al lado de donde se escribe.
        if (!PlatformTv.esTelevisionSync)
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

  /// Un marco rosado alrededor del campo, para que se note DE UN VISTAZO
  /// que ahí es donde se escribe.
  ///
  /// ── Por qué hacía falta ────────────────────────────────────────────
  ///
  /// Sin ningún borde ni fondo, este campo se leía como un título más de
  /// la barra —letras sueltas contra el fondo, iguales a cualquier otro
  /// texto de la pantalla—. Pedido explícito, con foto: «marca la zona
  /// del campo de texto en rosado bonito para que se note que ahí se
  /// escribe». Mismo lenguaje visual que ya usa `_CampoDeBusqueda`, del
  /// teclado en pantalla, para lo mismo.
  ///
  /// Fuera de TV no cambia nada: ahí el campo ya se distingue solo, con
  /// el cursor parpadeando apenas se lo toca.
  Widget _envolverEnTv(Widget campo) {
    if (!PlatformTv.esTelevisionSync) return campo;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: HomeTheme.accentPink.withValues(alpha: 0.75),
          width: 1.6,
        ),
      ),
      child: campo,
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
