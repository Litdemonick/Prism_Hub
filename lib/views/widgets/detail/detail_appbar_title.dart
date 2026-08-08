import 'package:flutter/material.dart';

/// El título dentro de la barra, el que aparece cuando la cabecera ya se
/// plegó y el título grande dejó de verse.
class DetailAppbarTitle extends StatefulWidget {
  const DetailAppbarTitle(
    this.text, {
    super.key,
    required this.controller,
    required this.desde,
  });
  final String text;
  final ScrollController controller;

  /// A partir de cuánto desplazamiento se muestra.
  ///
  /// Antes eran 300 puntos fijos, y eso dejaba el título en ningún lado: la
  /// cabecera se pliega del todo bastante antes de los 300 —depende de su alto
  /// real, que ahora se calcula— así que el título grande ya se había
  /// desvanecido y este no llegaba a aparecer nunca. Se veía como que el
  /// scroll se comía la información de arriba. Ahora entra justo cuando el
  /// otro se va (ver MedidasCabecera.relevoDelTitulo).
  final double desde;

  @override
  State<DetailAppbarTitle> createState() => _DetailAppbarTitleState();
}

class _DetailAppbarTitleState extends State<DetailAppbarTitle> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(DetailAppbarTitle anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.controller != widget.controller) {
      anterior.controller.removeListener(_handleScroll);
      widget.controller.addListener(_handleScroll);
    }
    // El umbral cambia al rotar o al cambiar el tamaño de la ventana: hay que
    // volver a decidir con el nuevo, o el título queda mal puesto hasta el
    // siguiente desplazamiento.
    if (anterior.desde != widget.desde) _handleScroll();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.controller.hasClients) return;
    final visible = widget.controller.offset > widget.desde;
    if (visible == _visible) return;
    setState(() => _visible = visible);
  }

  @override
  Widget build(BuildContext context) {
    // Fundido y no un salto seco: el título aparecía de golpe a mitad del
    // desplazamiento.
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      child: Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }
}
