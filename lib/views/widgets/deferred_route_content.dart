import 'package:flutter/widgets.dart';

/// Muestra [placeholder] mientras la animación de push de la ruta ([pushAnimation])
/// todavía está corriendo, y recién arma el contenido real (vía [builder])
/// cuando esa animación termina (o si ya terminó al montar, ej. transición
/// instantánea/hot reload).
///
/// Sin esto, construir la pantalla real (Get.put de un controller pesado,
/// Player() nativo de media_kit, etc.) en el mismo frame que arranca el push
/// competía por CPU con la transición todavía en curso — confirmado en vivo
/// que eso se sentía como un salto/tirón al abrir el reproductor de video,
/// ni bien empezaba el slide-in.
class DeferredRouteContent extends StatefulWidget {
  const DeferredRouteContent({
    super.key,
    required this.pushAnimation,
    required this.builder,
    this.placeholder = const SizedBox.shrink(),
  });

  final Animation<double> pushAnimation;
  final WidgetBuilder builder;
  final Widget placeholder;

  @override
  State<DeferredRouteContent> createState() => _DeferredRouteContentState();
}

class _DeferredRouteContentState extends State<DeferredRouteContent> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.pushAnimation.isCompleted) {
      _ready = true;
    } else {
      widget.pushAnimation.addStatusListener(_onStatus);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      widget.pushAnimation.removeStatusListener(_onStatus);
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    widget.pushAnimation.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ready ? widget.builder(context) : widget.placeholder;
  }
}
