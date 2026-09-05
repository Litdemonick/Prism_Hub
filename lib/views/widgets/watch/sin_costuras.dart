import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Dibuja a su hijo un pelo más alto de lo que mide, para que no quede una
/// rayita entre una página y la siguiente.
///
/// ── El fallo que arregla ────────────────────────────────────────────────
///
/// En la cascada, cada página se muestra al ancho de la pantalla y su alto
/// sale de la proporción de la imagen — o sea, un número con decimales:
/// 1487,32 puntos, no 1487. Puestas una debajo de la otra, el borde entre
/// dos páginas cae A MITAD de un píxel físico de la pantalla.
///
/// Ese píxel a medias no lo puede pintar entero ninguna de las dos: cada una
/// aporta su parte y el resto queda con el fondo del lector, que es oscuro.
/// Desde lejos eso es una línea negra fina cruzando la lectura, en un sitio
/// donde la imagen original no tiene nada. Reportado en vivo con foto.
///
/// Y aparece y desaparece porque depende de dónde quede el desplazamiento:
/// el mismo borde, un par de píxeles más arriba, cae justo y no se ve nada.
/// De ahí el «sale en partes específicas y a veces».
///
/// ── Por qué se resuelve pintando de más y no midiendo mejor ─────────────
///
/// Redondear el alto de cada página no alcanza: aunque las páginas quedaran
/// pegadas en números redondos entre ellas, el desplazamiento de la lista
/// también tiene decimales, así que el borde vuelve a caer partido apenas
/// uno se mueve.
///
/// Acá el hijo se DIBUJA estirado un píxel físico hacia abajo, sin cambiar
/// lo que MIDE: la disposición de la lista queda idéntica —las páginas
/// siguen empezando donde empezaban— pero cada una tapa con su propia
/// última fila el píxel compartido con la de abajo. No queda hueco por
/// donde se asome el fondo, esté donde esté el scroll.
///
/// Un píxel físico de estirado sobre una página de más de mil es del orden
/// del 0,07 %: no hay forma de notarlo, y es exactamente lo que hace falta
/// para cerrar la costura.
class SinCosturas extends SingleChildRenderObjectWidget {
  const SinCosturas({
    super.key,
    required this.pixelesPorPunto,
    required Widget super.child,
  });

  /// Cuántos píxeles físicos entra en un punto lógico en esta pantalla
  /// (`MediaQuery.devicePixelRatioOf`). De acá sale cuánto hay que estirar:
  /// justo un píxel de los de verdad, ni más ni menos.
  final double pixelesPorPunto;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSinCosturas(pixelesPorPunto);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSinCosturas).pixelesPorPunto = pixelesPorPunto;
  }
}

class _RenderSinCosturas extends RenderProxyBox {
  _RenderSinCosturas(this._pixelesPorPunto);

  double _pixelesPorPunto;
  set pixelesPorPunto(double valor) {
    if (valor == _pixelesPorPunto) return;
    _pixelesPorPunto = valor;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final hijo = child;
    if (hijo == null) return;
    // Sin alto no hay proporción que calcular, y con una pantalla que dice
    // cero píxeles por punto tampoco: se dibuja tal cual.
    if (size.height <= 0 || _pixelesPorPunto <= 0) {
      super.paint(context, offset);
      return;
    }
    final unPixel = 1 / _pixelesPorPunto;
    final escala = (size.height + unPixel) / size.height;
    // El estirado va anclado al BORDE DE ARRIBA (la transformación se aplica
    // desde `offset`, que es la esquina superior izquierda de esta caja):
    // la página sigue empezando exactamente donde le toca y lo que sobra
    // cae hacia abajo, encima del borde compartido con la siguiente.
    final matriz = Matrix4.identity()..scaleByDouble(1.0, escala, 1.0, 1.0);
    context.pushTransform(
      needsCompositing,
      offset,
      matriz,
      (contexto, desplazamiento) => super.paint(contexto, desplazamiento),
    );
  }
}
