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
  bool updateShouldNotify(RegionDeFocoTv anterior) => anterior.nombre != nombre;
}

/// Marca una franja horizontal de tarjetas que NO se desplaza —un `Row`
/// fijo, no un `ListView`— como una unidad, para que el D-pad no se salga
/// de ella por los costados salvo que de verdad no quede nada más adentro.
///
/// ── Por qué hace falta, además de `RegionDeFocoTv` ──────────────────────
///
/// Una fila que SÍ se desplaza tiene una forma natural de identificarse:
/// su propio `ScrollPosition`, que dos tarjetas de la misma fila siempre
/// comparten (ver `FocoConTopes._mismaFilaHorizontal`). Una fila FIJA —los
/// destacados grandes y medianos de arriba en Inicio, unas pocas tarjetas
/// en un `Row` común, sin nada que desplazar— no tiene ningún objeto así
/// del que agarrarse. Sin uno, al llegar a la última tarjeta de la fila y
/// no quedar ningún vecino real a la derecha, Flutter buscaba el foco más
/// cercano en cualquier otro lado de la pantalla, sin nada que lo frenara
/// ahí. Reportado en vivo: «arriba en las cards grandes al ir a la
/// derecha no bloquea, se pierde la selección».
///
/// ── Por qué es OTRO `InheritedWidget` y no el mismo `RegionDeFocoTv` ────
///
/// `RegionDeFocoTv` ya vive alrededor de esta franja (marcando "esto es
/// contenido", no "rail") y una búsqueda de tipo exacto solo encuentra el
/// ANCESTRO MÁS CERCANO — si esto reusara el mismo widget, una tarjeta de
/// la franja dejaría de "ver" la región de contenido de más afuera, que
/// hace falta para la otra comprobación (que un movimiento vertical no
/// cruce del rail al contenido). Dos preguntas distintas, dos marcadores.
class FranjaHorizontalTv extends InheritedWidget {
  const FranjaHorizontalTv({
    super.key,
    required this.identidad,
    required super.child,
  });

  /// Cualquier objeto estable durante la vida de la franja. Dos franjas
  /// nunca comparten el mismo, así que alcanza con comparar identidad
  /// (`identical`), no igualdad de contenido.
  final Object identidad;

  static Object? de(BuildContext? ctx) {
    if (ctx == null || !ctx.mounted) return null;
    final elemento =
        ctx.getElementForInheritedWidgetOfExactType<FranjaHorizontalTv>();
    final widget = elemento?.widget;
    return widget is FranjaHorizontalTv ? widget.identidad : null;
  }

  @override
  bool updateShouldNotify(FranjaHorizontalTv anterior) =>
      !identical(anterior.identidad, identidad);
}

/// Envuelve una fila FIJA (sin scroll) de tarjetas para que el D-pad la
/// trate como una unidad — ver [FranjaHorizontalTv].
///
/// `StatefulWidget` a propósito: la identidad tiene que ser LA MISMA en
/// cada reconstrucción de esta franja, no una nueva cada vez — si no,
/// cualquier comparación de identidad daría siempre "distinta", como si
/// nunca fuera la misma fila. El `State` sobrevive a los rebuilds; un
/// `Object()` creado en un método `build` normal no.
class FranjaFijaTv extends StatefulWidget {
  const FranjaFijaTv({super.key, required this.child});

  final Widget child;

  @override
  State<FranjaFijaTv> createState() => _FranjaFijaTvState();
}

class _FranjaFijaTvState extends State<FranjaFijaTv> {
  final Object _identidad = Object();

  @override
  Widget build(BuildContext context) =>
      FranjaHorizontalTv(identidad: _identidad, child: widget.child);
}
