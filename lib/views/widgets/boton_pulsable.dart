import 'package:flutter/widgets.dart';

/// Achica levemente lo que envuelve mientras se lo mantiene presionado.
///
/// Los botones de la ficha no daban ninguna señal al tocarlos: entre que se
/// apretaba y que pasaba algo —abrir el reproductor, guardar un favorito— no
/// había forma de saber si el toque había entrado. En el teléfono eso lleva a
/// tocar dos veces.
///
/// Es solo una escala, sin color ni sombra: no pisa el estilo de cada botón, y
/// por eso sirve igual para el árbol Material del teléfono y para el fluent de
/// escritorio.
///
/// No intercepta el toque. Se usa [HitTestBehavior.deferToChild] y no se pasa
/// ningún `onTap`: los eventos siguen llegando al botón de adentro, que es
/// quien decide qué hacer y quién sabe si está habilitado. Envolver con un
/// GestureDetector que consuma el toque habría roto todos los botones.
class BotonPulsable extends StatefulWidget {
  const BotonPulsable({super.key, required this.child});

  final Widget child;

  @override
  State<BotonPulsable> createState() => _BotonPulsableState();
}

class _BotonPulsableState extends State<BotonPulsable> {
  bool _presionado = false;

  void _marcar(bool v) {
    if (_presionado == v || !mounted) return;
    setState(() => _presionado = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _marcar(true),
      // Tanto al soltar como al cancelar: si el dedo se va del botón sin
      // levantar, el toque no cuenta y el botón tiene que volver igual. Sin el
      // cancel quedaba achicado para siempre.
      onPointerUp: (_) => _marcar(false),
      onPointerCancel: (_) => _marcar(false),
      child: AnimatedScale(
        // 0.96 y no menos: se nota al tocar sin que el botón "salte", que en
        // una fila de tres botones pegados se ve nervioso.
        scale: _presionado ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
