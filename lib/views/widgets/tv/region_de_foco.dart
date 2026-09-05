import 'package:flutter/widgets.dart';

/// Marca a qué "zona segura" del televisor pertenece un trozo de pantalla.
///
/// ── Para qué ────────────────────────────────────────────────────────────
///
/// Con un mando, la pantalla se divide en regiones que uno recorre por
/// dentro: la columna de categorías de la izquierda es una, y el contenido
/// de la derecha es otra. Moverse ARRIBA y ABAJO tiene que quedarse siempre
/// dentro de la región en la que uno está; se cambia de región solo yendo a
/// los costados, que es un movimiento deliberado.
///
/// Sin eso pasa lo que se reportó en vivo: estando en el panel izquierdo,
/// bajar se escapaba al contenido; y estando en una zona, bajar terminaba en
/// el panel. Uno pierde de vista dónde está parado, que es lo peor que puede
/// pasar navegando a tres metros de la pantalla.
///
/// ── Por qué un marcador y no la geometría ───────────────────────────────
///
/// `FocoConTopes` ya tenía una regla por píxeles: «si el destino cae en la
/// franja pegada al borde izquierdo, es el panel». Funciona con el panel
/// CONTRAÍDO, que es cuando mide poco, pero el panel se expande al recibir
/// el foco — y expandido ya no entra en ninguna franja angosta, así que la
/// cuenta dejaba de distinguir una cosa de la otra justo cuando el usuario
/// está adentro de él.
///
/// Preguntando por el marcador no hay umbral que ajustar ni resolución que
/// contemplar: o el widget está debajo de una región o no lo está.
class RegionDeFocoTv extends InheritedWidget {
  const RegionDeFocoTv({
    super.key,
    required this.nombre,
    required super.child,
  });

  /// Identificador de la región. No se muestra en ningún lado: solo sirve
  /// para comparar dos nodos entre sí.
  final String nombre;

  /// El panel de categorías de la izquierda.
  static const rail = 'rail';

  /// Todo lo que se ve a la derecha del panel.
  static const contenido = 'contenido';

  /// En qué región vive [ctx], o null si no está debajo de ninguna.
  ///
  /// Usa `getElementForInheritedWidgetOfExactType` y no `dependOn…` a
  /// propósito: esto se consulta desde el manejo de una tecla, no desde un
  /// `build`, y no tiene ningún sentido que quien pregunte se suscriba a
  /// cambios de algo que nunca cambia.
  static String? de(BuildContext? ctx) {
    if (ctx == null || !ctx.mounted) return null;
    final elemento =
        ctx.getElementForInheritedWidgetOfExactType<RegionDeFocoTv>();
    final widget = elemento?.widget;
    return widget is RegionDeFocoTv ? widget.nombre : null;
  }

  @override
  bool updateShouldNotify(RegionDeFocoTv anterior) =>
      anterior.nombre != nombre;
}
