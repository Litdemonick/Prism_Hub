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
    if (status != AnimationStatus.completed) return;
    widget.pushAnimation.removeStatusListener(_onStatus);
    // ── Al cuadro SIGUIENTE, no a este ──────────────────────────────────
    //
    // Reportado en vivo, con foto: "Bad state: RenderBox was not laid out:
    // RenderFractionalTranslation". Esa clase es la que arma `SlideTransition`
    // por dentro (traduce al hijo un porcentaje de SU PROPIO tamaño, así que
    // necesita medirlo) — y las dos rutas que usan este widget
    // (detail_controller.dart al abrir el reproductor, resume_history.dart
    // al "Continuar") van envueltas en un `SlideTransition`.
    //
    // El aviso de que la animación llegó a 1.0 llega DURANTE la fase de
    // animación del cuadro, antes de que ese mismo cuadro termine su
    // recorrido de layout/paint. Haciendo `setState` ahí mismo, el cambio de
    // `placeholder` (liviano) a la pantalla real —acá, nada menos que
    // `WatchPage` con su `Player()` nativo— se reconstruye TODAVÍA dentro
    // de ese cuadro, mientras el `SlideTransition` de arriba sigue
    // dibujando la transición que recién está terminando. Si el nuevo
    // árbol no llega a completar su propio layout antes de que el de
    // arriba pinte, revienta con esa aserción.
    //
    // Con `addPostFrameCallback`, el cambio de verdad pasa a ocurrir en el
    // cuadro DESPUÉS de que este ya cerró su ciclo completo — el
    // `SlideTransition` ya terminó de pintar la transición, y arma el
    // contenido real desde un cuadro limpio.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
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
