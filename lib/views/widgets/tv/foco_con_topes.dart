import 'package:flutter/widgets.dart';
import 'package:prismhub/views/widgets/tv/region_de_foco.dart';

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
    // ── Que Flutter no mueva el eje que nadie tocó ──────────────────────
    //
    // `super.invoke` termina llamando a la política de foco de Flutter, y
    // esa, además de mover el foco, hace `Scrollable.ensureVisible` sobre
    // el destino — que RECORRE TODOS los scrolls ancestros, sin mirar en
    // qué dirección se movió el usuario. O sea que yendo a la DERECHA
    // dentro de una fila, la lista VERTICAL que la contiene también recibe
    // su acomodada y baja sola.
    //
    // Esto es de fábrica y pasa ANTES de que la app pueda opinar: por eso
    // no alcanzaba con que `RescateDeFoco` acomodara un solo eje (ver el
    // comentario largo allá) — el desplazamiento indeseado ya había
    // ocurrido para cuando ese código corría. Reportado en vivo, varias
    // veces: «al ir a la derecha baja automático».
    //
    // Se anotan los scrolls del OTRO eje antes de mover y se los devuelve
    // a donde estaban después. Como el `ensureVisible` de la política es
    // instantáneo (sin animación) y `super.invoke` es síncrono, para
    // cuando se restaura no llegó a dibujarse ni un cuadro: desde afuera,
    // ese eje sencillamente no se movió.
    // ── Y el orden importa: primero el foco, después el scroll ──────────
    //
    // La restauración se hace AL FINAL, cuando el foco ya quedó donde tiene
    // que quedar. Hacerla antes rompía justo el caso del final de una fila:
    // el foco estaba de paso en una tarjeta de otra fila, fuera de la vista;
    // al devolver el scroll a su sitio, la lista reciclaba esa tarjeta y el
    // foco se quedaba en la nada. Desde afuera, la selección DESAPARECÍA —
    // y con el foco perdido, la flecha siguiente disparaba el rescate de
    // `RescateDeFoco`, que busca el primer enfocable que encuentre y
    // terminaba bajando por las tarjetas de abajo. Reportado en vivo las dos
    // cosas: «al ir al último card horizontal desaparece la selección» y
    // «presionando a la derecha sigue scrolleando hacia abajo».
    final ejeDelMovimiento = horizontal ? Axis.horizontal : Axis.vertical;
    // Se anotan TODOS los scrolls, de los dos ejes, porque hacen falta dos
    // cosas distintas: si el movimiento vale, se devuelve solo el eje que
    // nadie tocó; si se deshace, se devuelven los dos — un movimiento que
    // no ocurrió no puede dejar la lista desplazada. Sin esto, al frenar en
    // el borde de una fila la selección se quedaba quieta (bien) pero la
    // pantalla igual se había corrido (mal), que es la mitad de la
    // sensación de que «se mueve solo».
    final todosLosScrolls = _scrollsConSuPosicion(antes?.context);
    final aRestaurar = todosLosScrolls
        .where((s) => s.$1.axis != ejeDelMovimiento)
        .toList(growable: false);
    super.invoke(intent);
    final despues = primaryFocus;
    if (antes == null || despues == null || identical(antes, despues)) {
      _restaurar(aRestaurar);
      _rescatarSiSePerdio(antes);
      return;
    }
    // ── Los DOS rectángulos se miden DESPUÉS de mover ───────────────────
    //
    // Este era el fallo de fondo, y explica el «al bajar me sube arriba».
    //
    // Todas las comparaciones de acá abajo —se movió para donde debía,
    // sigue en el mismo renglón— dan por sentado que los dos rectángulos
    // están medidos en el mismo momento. Y no lo estaban: el de origen se
    // tomaba ANTES de `super.invoke` y el de destino DESPUÉS. En el medio,
    // Flutter desplaza la lista para traer a la vista lo que acaba de
    // enfocar, así que todo lo que hay en pantalla CAMBIA DE SITIO.
    //
    // Bajando, la lista sube el contenido: la tarjeta nueva termina
    // dibujada MÁS ARRIBA de donde estaba la anterior antes del
    // desplazamiento. Comparados así, un salto hacia abajo perfectamente
    // legítimo parecía ir hacia arriba, y esta guarda lo deshacía. Lo que
    // se veía era exactamente eso: la lista se movía, la selección volvía a
    // la tarjeta de antes —ahora dibujada más arriba— y bajar se sentía
    // como subir.
    //
    // Midiendo los dos después, ambos están en el mismo sistema de
    // coordenadas y la comparación vuelve a significar lo que dice.
    final desde = _rectDe(antes);
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
      // Se deshace el movimiento: se devuelven los DOS ejes, no solo el que
      // nadie tocó. Ver el comentario de `todosLosScrolls`.
      antes.requestFocus();
      _restaurar(todosLosScrolls);
      _rescatarSiSePerdio(antes);
      return;
    }
    if (desde == null || hasta == null) {
      _restaurar(aRestaurar);
      _rescatarSiSePerdio(antes);
      return;
    }
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
    // ── Cruzando de región se compara por el CENTRO, no por el borde ─────
    //
    // El panel de categorías, desplegado, se dibuja ENCIMA del contenido:
    // se superpone con la primera tarjeta de cada fila en vez de quedar a
    // su lado. Ahí «el destino empieza más a la izquierda que el origen»
    // deja de ser cierto —los dos empiezan casi en el mismo sitio— y un
    // movimiento perfectamente legítimo hacia el panel se deshacía solo.
    //
    // Reportado en vivo, con foto y reincidente: «no me deja entrar al
    // panel izquierdo, no me deja literal». Reproducido después en un test
    // con el panel desplegado, que es cuando pasa.
    //
    // Comparando los centros, la superposición deja de importar: el ícono
    // del panel siempre tiene su centro más a la izquierda que el de una
    // tarjeta, se pisen o no sus bordes.
    final cambioDeRegion = _cambioDeRegion(antes.context, despues.context);
    final porElCentro = cambioDeRegion == true;
    final desdeX = porElCentro ? desde.center.dx : desde.left;
    final hastaX = porElCentro ? hasta.center.dx : hasta.left;
    final desdeY = porElCentro ? desde.center.dy : desde.top;
    final hastaY = porElCentro ? hasta.center.dy : hasta.top;
    final seMovioComoDebia = switch (intent.direction) {
      TraversalDirection.right => hastaX > desdeX,
      TraversalDirection.left => hastaX < desdeX,
      TraversalDirection.down => hastaY > desdeY,
      TraversalDirection.up => hastaY < desdeY,
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
    // ── Arriba y abajo NO cambian de región ─────────────────────────────
    //
    // La pantalla del televisor tiene dos zonas que se recorren por dentro:
    // la columna de categorías y el contenido (ver RegionDeFocoTv). Un
    // movimiento vertical se queda en la suya; se cambia de una a otra solo
    // yendo a los costados, que es un gesto deliberado.
    //
    // Sin esto pasaban las dos cosas que se reportaron en vivo: estando en
    // el panel izquierdo, bajar se escapaba al contenido; y estando en una
    // zona, bajar terminaba metido en el panel. `_escapoALaIzquierda` ya
    // cubría el segundo caso a ojo, midiendo si el destino caía en la franja
    // pegada al borde — pero eso solo acierta con el panel CONTRAÍDO, y el
    // panel se expande justo cuando uno está adentro. Se conserva como
    // respaldo para las pantallas que todavía no marcan sus regiones.
    // (`cambioDeRegion` se calcula más arriba: hace falta antes, para saber
    // si la dirección se mide por el centro o por el borde.)
    // ── En horizontal, además: tienen que compartir la MISMA fila física ──
    //
    // `_mismoRenglon` y `_mismaFranja` miden si dos rectángulos SE PARECEN
    // en altura — funciona casi siempre, pero "casi" no alcanza en el borde
    // de verdad: al llegar al último elemento de una fila y no quedar
    // ningún vecino de verdad a la derecha, Flutter puede engancharse a
    // CUALQUIER otro foco del árbol que ninguna de las dos reglas anteriores
    // llegue a descartar por casualidad —un botón de otra parte de la
    // pantalla que da la casualidad de estar a una altura parecida—, y ESE
    // sí pasaba: la selección terminaba en algo real pero sin ninguna marca
    // visual de foco, que desde el sillón se ve como que la selección
    // sencillamente desaparece. Reportado en vivo: «al darle a la derecha y
    // ya no hay nada, desaparece la selección».
    //
    // `_mismaFilaHorizontal` no mide parecido: comprueba si los dos widgets
    // cuelgan del MISMO objeto de scroll horizontal, el de la fila en la
    // que se está. Un vecino de verdad siempre lo comparte, así que esto
    // nunca rechaza un movimiento legítimo; cualquier otra cosa —esté a la
    // altura que esté— no lo comparte y queda descartada sin ambigüedad.
    //
    // ── Y en horizontal, cruzar de región es igual de deliberado ─────────
    //
    // Faltaba acá el mismo permiso que ya tiene la rama vertical, arriba:
    // el rail de categorías no cuelga de ninguna fila de tarjetas, así que
    // `_mismaFilaHorizontal` lo rechazaba SIEMPRE como si fuera "otra fila
    // cualquiera" — exactamente lo contrario de lo que dice el comentario
    // de más arriba, que a los costados es como se cruza a propósito entre
    // las dos regiones. Reportado en vivo: «no me deja entrar al panel
    // izquierdo, estando pegado del todo a la izquierda».
    final seFue = !seMovioComoDebia ||
        (horizontal
            ? (cambioDeRegion == true
                ? false
                : (!_mismaFilaHorizontal(antes.context, despues.context) ||
                    !_mismoRenglon(desde, hasta) ||
                    !_mismaFranja(desde, hasta)))
            : (cambioDeRegion ??
                _escapoALaIzquierda(desde, hasta, despues.context)));
    if (!seFue) {
      _restaurar(aRestaurar);
      return;
    }
    // Se fue de fila (u ocurrió el escape a la columna de categorías): se lo
    // devuelve donde estaba.
    //
    // Deshacer en vez de impedir de antemano porque Flutter no expone a dónde
    // IRÍA el foco sin moverlo. Como todo esto pasa dentro del mismo cuadro,
    // el foco intermedio no llega a dibujarse: desde afuera, la flecha
    // simplemente no hizo nada.
    antes.requestFocus();
    // Los DOS ejes: el movimiento no ocurrió, así que el desplazamiento que
    // provocó tampoco puede quedar. Ver el comentario de `todosLosScrolls`.
    _restaurar(todosLosScrolls);
    _rescatarSiSePerdio(antes);
  }

  /// Si después de todo esto el foco quedó en la nada, se lo devuelve a
  /// donde estaba.
  ///
  /// ── Por qué puede quedar en la nada ─────────────────────────────────
  ///
  /// El foco pasa un instante por una tarjeta que no correspondía, y esa
  /// tarjeta puede vivir en una parte de la lista que se recicla en cuanto
  /// el scroll vuelve a su sitio. Si justo pasa eso, `requestFocus` sobre
  /// ella ya no significa nada y no queda nadie enfocado: con el mando eso
  /// es lo peor que puede pasar, porque sin foco las flechas no tienen
  /// desde dónde salir y la pantalla parece congelada.
  ///
  /// `RescateDeFoco` cubre ese caso a lo bruto —busca el primer enfocable
  /// que encuentre—, pero ahí ya se perdió el sitio: terminaba bajando por
  /// las tarjetas de abajo. Acá todavía se sabe exactamente de dónde venía,
  /// así que se lo devuelve ahí y no a cualquier lado.
  static void _rescatarSiSePerdio(FocusNode? antes) {
    if (antes == null) return;
    final actual = primaryFocus;
    if (actual != null && actual is! FocusScopeNode && actual.context != null) {
      return;
    }
    if (antes.context == null || !antes.canRequestFocus) return;
    antes.requestFocus();
  }

  /// ¿El salto cruzó de una región a otra?
  ///
  /// `null` cuando no se puede saber —alguno de los dos lados no está debajo
  /// de ninguna `RegionDeFocoTv`, que es el caso de las pantallas que
  /// todavía no las marcan—: ahí quien pregunta decide con lo que tenga.
  static bool? _cambioDeRegion(BuildContext? antes, BuildContext? despues) {
    final origen = RegionDeFocoTv.de(antes);
    final destino = RegionDeFocoTv.de(despues);
    if (origen == null || destino == null) return null;
    return origen != destino;
  }

  /// Todos los scrolls ancestros, con la posición en la que están ahora.
  static List<(ScrollPosition, double)> _scrollsConSuPosicion(
    BuildContext? ctx,
  ) {
    final resultado = <(ScrollPosition, double)>[];
    if (ctx == null || !ctx.mounted) return resultado;
    var contexto = ctx;
    var scroll = Scrollable.maybeOf(contexto);
    while (scroll != null) {
      final posicion = scroll.position;
      if (posicion.hasPixels) resultado.add((posicion, posicion.pixels));
      contexto = scroll.context;
      scroll = Scrollable.maybeOf(contexto);
    }
    return resultado;
  }

  /// Devuelve cada scroll a donde estaba, si algo lo movió.
  static void _restaurar(List<(ScrollPosition, double)> guardados) {
    for (final (posicion, pixeles) in guardados) {
      if (!posicion.hasPixels) continue;
      // Menos de un píxel no es un movimiento: saltar igual solo cortaría
      // un desplazamiento en curso por nada.
      if ((posicion.pixels - pixeles).abs() < 1) continue;
      posicion.jumpTo(pixeles);
    }
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

  /// El scroll horizontal más cercano por encima de [ctx], o null si no hay
  /// ninguno (el widget no está dentro de ninguna fila que deslice).
  static ScrollPosition? _scrollHorizontalDe(BuildContext? ctx) {
    if (ctx == null || !ctx.mounted) return null;
    var contexto = ctx;
    var scroll = Scrollable.maybeOf(contexto);
    while (scroll != null) {
      if (scroll.position.axis == Axis.horizontal) return scroll.position;
      contexto = scroll.context;
      scroll = Scrollable.maybeOf(contexto);
    }
    return null;
  }

  /// ¿[a] y [b] viven en la MISMA fila horizontal?
  ///
  /// No mide parecido de rectángulos: compara si es literalmente el mismo
  /// objeto de scroll. Dos tarjetas de la misma fila SIEMPRE lo comparten
  /// (cuelgan del mismo `ScrollController`/`Scrollable`); cualquier otra
  /// cosa no puede compartirlo por casualidad.
  ///
  /// ── Y si ninguno de los dos se desplaza ─────────────────────────────
  ///
  /// Una fila FIJA —los destacados de arriba en Inicio, un `Row` común sin
  /// nada que desplazar— no tiene ScrollPosition del que agarrarse. Ahí se
  /// mira `FranjaHorizontalTv` en su lugar: el mismo criterio (identidad,
  /// no parecido), para el mismo problema, en widgets sin scroll. Ver el
  /// comentario largo de esa clase — reportado en vivo: «arriba en las
  /// cards grandes al ir a la derecha no bloquea, se pierde la selección».
  ///
  /// Solo cuando NINGUNO de los dos está marcado de ninguna forma —la barra
  /// de arriba, con sus botones sueltos, no es una fila de tarjetas de
  /// nada— esta comprobación no tiene nada que confirmar: se deja pasar, y
  /// el asunto queda en manos de `_mismoRenglon`/`_mismaFranja` como
  /// siempre. Tratarlo como "no es la misma fila" ahí habría bloqueado
  /// mover el foco entre esos botones, que nunca estuvo roto.
  static bool _mismaFilaHorizontal(BuildContext? a, BuildContext? b) {
    final filaA = _scrollHorizontalDe(a);
    final filaB = _scrollHorizontalDe(b);
    if (filaA != null || filaB != null) {
      if (filaA == null || filaB == null) return false;
      return identical(filaA, filaB);
    }
    final franjaA = FranjaHorizontalTv.de(a);
    final franjaB = FranjaHorizontalTv.de(b);
    if (franjaA != null || franjaB != null) {
      if (franjaA == null || franjaB == null) return false;
      return identical(franjaA, franjaB);
    }
    return true;
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
