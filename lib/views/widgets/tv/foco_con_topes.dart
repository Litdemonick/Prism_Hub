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
    // ── Sin poder medir el destino, en horizontal se frena ──────────────
    //
    // Acá había un agujero por el que se colaba justo el caso que este tope
    // existe para cortar. Al llegar al final de una fila, Flutter engancha
    // un nodo de otra parte —la fila de arriba, normalmente— que la lista
    // acaba de construir por adelantado y que TODAVÍA NO tiene tamaño. Sin
    // medida, esta guarda se rendía y lo dejaba pasar. Reportado en vivo:
    // «al presionar a la derecha pasa todas las cards y luego sube a las de
    // arriba, no hay topes en la fila que estoy».
    //
    // Un destino que no se puede medir en un movimiento horizontal no es un
    // vecino de la fila: los vecinos de verdad ya están puestos y medidos,
    // porque se están viendo. Así que se deshace, que es exactamente lo que
    // tiene que pasar al final de una fila.
    //
    // En vertical no se aplica lo mismo: ahí el destino legítimo SÍ suele
    // ser algo recién construido —la fila de abajo que entra en pantalla— y
    // frenar por no poder medirla sería trabar el scroll.
    if (horizontal && hasta == null && antes.context != null) {
      antes.requestFocus();
      return;
    }
    if (desde == null || hasta == null) return;
    // ── La regla que no depende de umbrales ─────────────────────────────
    //
    // `_mismaFranja` y `_escapoALaIzquierda` miden CUÁNTO se solapan dos
    // rectángulos contra un porcentaje fijo — funcionan, pero un umbral
    // pensado para una resolución puede fallar en otra. Acá hay una regla
    // más simple y siempre cierta, sin importar tamaños de pantalla ni de
    // tarjeta: **si apretaste derecha, lo que se enfoca tiene que estar más
    // a la derecha que lo de antes** (y lo mismo para las otras tres
    // flechas). Si no lo está, Flutter no encontró un vecino de verdad —
    // enganchó cualquier cosa con tal de mover el foco a algún lado— y no
    // hay forma de que ESO sea lo que el usuario pidió.
    //
    // Reportado en vivo, dos síntomas del mismo agujero que los umbrales de
    // abajo no cubrían: «al llegar al final de una fila y seguir apretando
    // derecha, empieza a bajar solo» (el destino "de al lado" en realidad
    // fue uno de la fila de ABAJO, con solape suficiente para pasar
    // `_mismaFranja` pero sin haberse movido ni un píxel a la derecha) y
    // «al bajar, la selección rebota para arriba sola» (bajando, el destino
    // cayó dentro de la franja del rail por muy poco, sin serlo).
    final seMovioComoDebia = switch (intent.direction) {
      TraversalDirection.right => hasta.left > desde.left,
      TraversalDirection.left => hasta.left < desde.left,
      TraversalDirection.down => hasta.top > desde.top,
      TraversalDirection.up => hasta.top < desde.top,
    };
    // ── Por qué "se movió a la derecha" NO alcanza solo ─────────────────
    //
    // Una tarjeta de la fila de ABAJO, si esa fila está corrida hacia la
    // derecha (cada fila se desplaza por su cuenta, no comparten offset),
    // también queda "más a la derecha que antes" — `seMovioComoDebia` la
    // deja pasar igual que a la vecina de verdad. Reportado en vivo,
    // reincidente: «al llegar al final de la fila y seguir con la derecha,
    // sigue bajando a las cards de abajo». Hace falta ADEMÁS confirmar que
    // el destino sigue en el mismo renglón — ver `_mismoRenglon`.
    final seFue = !seMovioComoDebia ||
        (horizontal
            ? (!_mismoRenglon(desde, hasta) || !_mismaFranja(desde, hasta))
            : _escapoALaIzquierda(desde, hasta, despues.context));
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

  /// El destino es la columna de categorías, y no una fila más abajo.
  ///
  /// ── Por qué no alcanza con «terminó a la izquierda» ──────────────────
  ///
  /// Esa era la regla anterior, y funcionaba cuando las zonas eran una
  /// grilla: ahí las columnas quedaban alineadas, así que la tarjeta de
  /// abajo siempre compartía algo de ancho con la de arriba y el único
  /// destino que caía «del todo a la izquierda» era el rail.
  ///
  /// Con las filas por extensión eso dejó de ser cierto. Cada fila se
  /// desplaza por su cuenta, así que estando en la séptima tarjeta de una
  /// fila, la de abajo puede estar entera más a la izquierda —es otra fila,
  /// con otro desplazamiento— y la regla la confundía con el rail: la flecha
  /// abajo se deshacía sola y la zona quedaba trabada. Reportado en vivo:
  /// «en las zonas no me deja hacer scroll hacia abajo, se bloquea».
  ///
  /// ── La regla que sí distingue las dos cosas ──────────────────────────
  ///
  /// El rail no es «algo que está a la izquierda»: es una franja angosta
  /// PEGADA AL BORDE de la pantalla. Una tarjeta de otra fila, por muy a la
  /// izquierda que esté, empieza después del rail — nunca dentro de él.
  ///
  /// Así que además de irse del todo hacia la izquierda, el destino tiene
  /// que terminar dentro de esa franja del borde para contar como escape.
  /// Un salto normal entre filas no la toca, y el del rail cae de lleno.
  static bool _escapoALaIzquierda(Rect desde, Rect hasta, BuildContext? ctx) {
    if (hasta.right > desde.left) return false;
    final ancho = _anchoDePantalla(ctx);
    // Sin poder medir la pantalla se deja pasar: perder un salto legítimo
    // entre filas —que traba la zona entera— es mucho peor que dejar escapar
    // uno al rail, que se resuelve apretando derecha.
    if (ancho == null) return false;
    return hasta.right <= ancho * _franjaDelRail;
  }

  /// Qué parte del ancho de la pantalla ocupa el rail de categorías.
  ///
  /// Contraído mide entre 48 y 58 puntos (ver `_anchoSidebarContraidoTv`) y
  /// expandido llega a bastante más, pero el foco solo puede caer en él
  /// desde el contenido cuando está contraído. En el televisor más angosto
  /// que soportamos eso es menos de un doceavo del ancho; el 15 % deja
  /// margen de sobra sin llegar nunca a la primera tarjeta de una fila, que
  /// empieza recién pasado el rail más su aire.
  static const _franjaDelRail = 0.15;

  static double? _anchoDePantalla(BuildContext? ctx) {
    if (ctx == null || !ctx.mounted) return null;
    final ancho = MediaQuery.maybeSizeOf(ctx)?.width;
    return (ancho != null && ancho > 0) ? ancho : null;
  }

  static bool _mismaFranja(Rect a, Rect b) {
    final desde = a.top > b.top ? a.top : b.top;
    final hasta = a.bottom < b.bottom ? a.bottom : b.bottom;
    final solape = hasta - desde;
    if (solape <= 0) return false;
    final menor = a.height < b.height ? a.height : b.height;
    if (menor <= 0) return false;
    return solape / menor >= _solapeMinimo;
  }

  /// Cuánto puede diferir el CENTRO vertical de dos tarjetas y seguir
  /// contando como «la misma fila». No depende de un porcentaje de nada:
  /// dentro de una fila, todas las tarjetas están alineadas al mismo
  /// renglón, así que sus centros prácticamente coinciden (la que tiene el
  /// foco puede estar un poco más alta por el crecido, de ahí que no sea
  /// cero). La fila de ABAJO, en cambio, está corrida por lo menos el alto
  /// de una fila entera — típicamente 150 a 250px en TV — así que 40px de
  /// tolerancia separa clarísimo un caso del otro, sea cual sea la
  /// resolución de la pantalla o el ancho de las tarjetas.
  static const _toleranciaDeRenglon = 40.0;

  /// El destino sigue en la MISMA fila horizontal que el origen.
  ///
  /// ── Por qué hace falta, además de `_mismaFranja` ─────────────────────
  ///
  /// `_mismaFranja` exige que se solapen al menos un tercio de alto — y una
  /// fila corrida hacia la derecha (cada fila se desplaza por su cuenta)
  /// puede tener una tarjeta que, por casualidad de tamaños, solapa lo
  /// suficiente con la de la fila de arriba como para pasar esa cuenta,
  /// aunque sea claramente OTRA fila. Reportado en vivo, dos veces: la
  /// flecha derecha seguía bajando al final de la fila. Comparar el CENTRO
  /// en vez de superposición no tiene ese punto ciego: dos filas distintas
  /// casi nunca coinciden de centro a centro, compartan o no algo de alto.
  static bool _mismoRenglon(Rect a, Rect b) =>
      (a.center.dy - b.center.dy).abs() < _toleranciaDeRenglon;
}
