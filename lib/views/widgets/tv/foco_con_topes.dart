import 'package:flutter/widgets.dart';

/// Hace que las flechas del mando signifiquen lo que dicen.
///
/// ── El problema ─────────────────────────────────────────────────────────────
///
/// Reportado en vivo en un televisor: «presiono la flecha derecha todo el rato
/// y me baja abajo automáticamente; no debe, porque no hay nada más a la
/// derecha». Y al revés en las demás zonas.
///
/// No era un fallo de la app sino el comportamiento de fábrica: cuando en la
/// dirección pedida no queda nada, Flutter busca **lo más cercano en cualquier
/// otro sitio** con tal de mover el foco a algún lado. Al llegar al final de
/// una fila, lo más cercano suele estar en la fila de abajo, así que la flecha
/// derecha terminaba bajando.
///
/// Desde el sillón eso es desorientador: uno mantiene apretada una flecha para
/// recorrer una fila y de golpe está en otra, sin haber pedido bajar.
///
/// ── La regla ────────────────────────────────────────────────────────────────
///
/// Un movimiento horizontal tiene que quedarse en la MISMA franja horizontal.
/// Si el foco terminaría en algo que no comparte altura con lo que estaba
/// seleccionado, no es «lo de al lado»: es otra fila, y ahí la flecha no hace
/// nada. Al final de la fila, el foco se queda donde está.
///
/// ── Vertical: la misma idea, pero más angosta ───────────────────────────────
///
/// En vertical NO se exige compartir columna: cada fila de una grilla se
/// desplaza por su cuenta, así que estando en la sexta tarjeta de una fila,
/// abajo puede no haber NINGUNA tarjeta alineada — y exigir que la hubiera
/// dejaría la flecha abajo sin hacer nada, que es peor que lo que se está
/// arreglando.
///
/// Pero hay un escape que sí hace falta cortar: al llegar a la ÚLTIMA fila de
/// una zona (o mientras la siguiente todavía no terminó de llegar), abajo no
/// queda ninguna tarjeta con la que Flutter pueda alinear el salto — y ahí
/// busca lo más cercano en CUALQUIER lado, incluida la columna de categorías
/// a la izquierda, que ocupa toda la altura de la pantalla. Reportado en
/// vivo: «al ir presionando el scroll en una zona me saca y me manda al
/// panel izquierdo». La flecha abajo terminaba en el menú, sin que nadie lo
/// pidiera.
///
/// La regla: un salto vertical no puede terminar COMPLETAMENTE a la
/// izquierda de donde estaba. Eso es justo lo que distingue «otra fila de la
/// misma grilla» (siempre comparte algo de ancho con la fila de arriba,
/// aunque las columnas no queden alineadas) de «la columna de categorías»
/// (angosta, pegada al borde, sin nada en común con una tarjeta que ya
/// estaba bien adentro de la grilla).
class FocoConTopes extends DirectionalFocusAction {
  FocoConTopes() : super();

  /// Cuánto tienen que solaparse en altura para contar como «la misma fila».
  ///
  /// Un tercio del más bajo de los dos. No se pide más porque dentro de una
  /// misma fila las tarjetas no miden todas igual —la enfocada crece— y pedir
  /// un solape casi total dejaría fuera a su vecina justo cuando crece.
  static const _solapeMinimo = 0.34;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final horizontal = intent.direction == TraversalDirection.left ||
        intent.direction == TraversalDirection.right;
    final vertical = intent.direction == TraversalDirection.up ||
        intent.direction == TraversalDirection.down;
    if (!horizontal && !vertical) {
      super.invoke(intent);
      return;
    }
    final antes = primaryFocus;
    final desde = _rectDe(antes);
    super.invoke(intent);
    final despues = primaryFocus;
    if (antes == null || despues == null || identical(antes, despues)) return;
    final hasta = _rectDe(despues);
    if (desde == null || hasta == null) return;
    final seFue =
        horizontal ? !_mismaFranja(desde, hasta) : _escapoALaIzquierda(desde, hasta);
    if (!seFue) return;
    // Se fue de fila (u ocurrió el escape a la columna de categorías): se lo
    // devuelve donde estaba.
    //
    // Deshacer en vez de impedir de antemano porque Flutter no expone a dónde
    // IRÍA el foco sin moverlo. Como todo esto pasa dentro del mismo cuadro,
    // el foco intermedio no llega a dibujarse: desde afuera, la flecha
    // simplemente no hizo nada.
    antes.requestFocus();
  }

  static Rect? _rectDe(FocusNode? nodo) {
    if (nodo == null) return null;
    try {
      final caja = nodo.context?.findRenderObject();
      if (caja is! RenderBox || !caja.hasSize) return null;
      return nodo.rect;
    } catch (_) {
      // Un nodo que se está desmontando justo ahora. Sin medida no se opina.
      return null;
    }
  }

  /// El destino terminó COMPLETAMENTE a la izquierda de donde estaba — no
  /// «una columna más a la izquierda dentro de la misma grilla» (eso
  /// siempre se solapa con el ancho de la tarjeta de origen), sino en una
  /// franja de la pantalla que no comparte nada de ancho con ella. Eso es
  /// la columna de categorías, angosta y pegada al borde.
  static bool _escapoALaIzquierda(Rect desde, Rect hasta) =>
      hasta.right <= desde.left;

  static bool _mismaFranja(Rect a, Rect b) {
    final desde = a.top > b.top ? a.top : b.top;
    final hasta = a.bottom < b.bottom ? a.bottom : b.bottom;
    final solape = hasta - desde;
    if (solape <= 0) return false;
    final menor = a.height < b.height ? a.height : b.height;
    if (menor <= 0) return false;
    return solape / menor >= _solapeMinimo;
  }
}
