import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// La flecha de volver de la ficha, que cambia de color según qué tenga detrás.
///
/// ── Por qué no alcanza con un color fijo ────────────────────────────────
///
/// Esta flecha vive en la barra de la ficha, y esa barra tiene DOS fondos muy
/// distintos según dónde esté el desplazamiento:
///
///   · **Desplegada**: detrás está la PORTADA, que es una imagen y suele ser
///     oscura. Ahí la flecha tiene que ser blanca, en los dos modos — igual
///     que el título grande (ver [HomeTheme.sobrePortada]).
///   · **Plegada**: detrás está el fondo de la app, que sí sigue al modo. Ahí
///     una flecha blanca desaparecería en modo claro.
///
/// Estaba tomando el color del tema, o sea el de la barra plegada, y con el
/// modo claro puesto quedaba una flecha casi negra encima de la portada: la
/// única salida de la pantalla, invisible.
///
/// Es el mismo mecanismo que usa [DetailAppbarTitle] para aparecer, y con el
/// mismo umbral, así que las dos cosas cambian a la vez.
class DetailAppbarBack extends StatefulWidget {
  const DetailAppbarBack({
    super.key,
    required this.controller,
    required this.desde,
    required this.onVolver,
  });

  final ScrollController controller;

  /// A partir de cuánto desplazamiento la barra ya está plegada.
  final double desde;

  final VoidCallback onVolver;

  @override
  State<DetailAppbarBack> createState() => _DetailAppbarBackState();
}

class _DetailAppbarBackState extends State<DetailAppbarBack> {
  bool _plegada = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_alDesplazar);
  }

  @override
  void didUpdateWidget(DetailAppbarBack anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.controller != widget.controller) {
      anterior.controller.removeListener(_alDesplazar);
      widget.controller.addListener(_alDesplazar);
    }
    if (anterior.desde != widget.desde) _alDesplazar();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_alDesplazar);
    super.dispose();
  }

  void _alDesplazar() {
    if (!widget.controller.hasClients) return;
    final plegada = widget.controller.offset > widget.desde;
    if (plegada == _plegada) return;
    setState(() => _plegada = plegada);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.onVolver,
      // Fundido y no un salto seco, igual que el título que entra al lado.
      icon: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: _plegada ? HomeTheme.textPrimary : HomeTheme.sobrePortada,
        ),
        duration: const Duration(milliseconds: 160),
        builder: (context, color, _) => Icon(Icons.arrow_back, color: color),
      ),
    );
  }
}
