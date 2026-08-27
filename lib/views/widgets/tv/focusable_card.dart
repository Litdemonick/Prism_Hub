import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Envuelve cualquier tarjeta/tile existente (HomeMediaCard, un tile de
/// Ajustes, un destino del sidebar, lo que sea) para hacerla navegable con
/// D-pad de control remoto, sin dejar de aceptar mouse ni toque.
///
/// No dibuja contenido propio ni reemplaza nada: el [child] sigue siendo el
/// widget real. Esto SOLO agrega la capa de foco/interacción por fuera —
/// pensado para envolver tarjetas en las ramas de TV sin duplicar la lógica
/// visual que ya vive en cada una.
///
/// ── Los tres caminos de entrada llevan al mismo lugar ──────────────────
///
/// D-pad/teclado, mouse y toque disparan [onTap] y encienden la MISMA señal
/// visual (`_activo`) — no hay una ruta de código por método de entrada.
///
/// ── Por qué no hay un `FocusTraversalPolicy` a mano ─────────────────────
///
/// Flutter ya trae navegación direccional por defecto: `WidgetsApp` liga las
/// flechas a `DirectionalFocusIntent`, que mueve el foco al widget enfocable
/// más cercano en esa dirección geométrica (`primaryFocus.focusInDirection`).
/// Alcanza con que cada tarjeta sea un `Focus` real — no hace falta
/// reinventar el recorrido de una fila ni el salto a un sidebar: sale solo
/// mientras el layout tenga sentido visualmente.
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    this.child,
    this.builder,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = 8,
    this.accent,
    this.altoMarco,
  }) : assert(
          child != null || builder != null,
          'FocusableCard necesita child o builder',
        );

  /// Alto del resplandor de selección, cuando NO tiene que abarcar al hijo
  /// entero.
  ///
  /// Las tarjetas del catálogo son portada + título debajo, y el resplandor
  /// alrededor de las dos cosas encierra un bloque de texto suelto en el
  /// aire: lo que se está eligiendo es la portada. Pasando su alto, se
  /// dibuja solo alrededor de ella.
  final double? altoMarco;

  /// El caso simple: un hijo fijo, que no necesita saber si tiene el foco.
  final Widget? child;

  /// El caso con más información: el hijo cambia según si el foco está acá
  /// o no — pedido explícito para las zonas de TV, donde el panel de info
  /// (`PanelInfoHover`, el mismo que ya muestra el hover de mouse en PC)
  /// tiene que aparecer con el foco del mando. `TarjetaDeCatalogo` no tiene
  /// forma de saber esto por su cuenta —el resaltado vive acá afuera,
  /// nunca adentro de la tarjeta, para no duplicar la escala/sombra (ver el
  /// comentario en tarjeta_de_catalogo.dart)— así que quien envuelve con
  /// `FocusableCard` es quien puede pasárselo.
  ///
  /// Uno de los dos, `child` o `builder`, tiene que venir.
  final Widget Function(bool tieneFoco)? builder;

  final VoidCallback onTap;

  /// Si no se pasa, el widget crea y descarta el suyo. Pasarlo desde afuera
  /// sirve para pedirle foco a una tarjeta puntual desde el padre (por
  /// ejemplo, la primera de una fila).
  final FocusNode? focusNode;

  final bool autofocus;
  final double borderRadius;

  /// Color del resplandor de foco. Por defecto [HomeTheme.accentPink]; se
  /// pasa [HomeTheme.accentRed] en pantallas de la Zona +18, mismo criterio
  /// que ya usan [HomeMediaCard]/`HomeSection` con su parámetro `accent`.
  final Color? accent;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  FocusNode? _focusNodePropio;
  bool _hover = false;
  bool _tieneFoco = false;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_focusNodePropio ??= FocusNode(debugLabel: 'FocusableCard'));

  @override
  void dispose() {
    _focusNodePropio?.dispose();
    super.dispose();
  }

  void _activar() {
    // Tocar/clickear también pide el foco: así el D-pad retoma la
    // navegación justo desde la tarjeta que se tocó, en vez de perderlo.
    _focusNode.requestFocus();
    widget.onTap();
  }

  /// Trae la tarjeta a la vista cuando el D-pad le da el foco.
  ///
  /// ── Por qué hace falta esto ─────────────────────────────────────────
  ///
  /// Flutter mueve el foco al widget más cercano en esa dirección, pero NO
  /// desplaza el scroll para que se vea — eso es cosa de cada scrollable, y
  /// nadie lo pedía. Sin esto, mover el foco más allá del borde visible de
  /// una fila o de la lista principal deja el foco en un lugar que el
  /// usuario no puede ver: se siente exactamente como "el mando dejó de
  /// responder" o "no deja hacer scroll", aunque el foco sí se movió.
  /// ── Y por qué NO centra siempre ─────────────────────────────────────
  ///
  /// La primera versión centraba la tarjeta enfocada en cada movimiento
  /// (`alignment: 0.5`). Se veía bien de a un paso, pero rompía la
  /// navegación: Flutter elige a dónde va el foco según DÓNDE ESTÁ CADA
  /// COSA en pantalla, y centrar mueve todo el contenido justo mientras esa
  /// cuenta se está haciendo. Apretando arriba dos veces seguidas, la
  /// segunda se calculaba sobre un layout que ya se había corrido y el foco
  /// terminaba en cualquier lado — el "se buguea y me manda a otro lugar".
  ///
  /// Ahora solo se mueve lo MÍNIMO para que la tarjeta entre en pantalla, y
  /// si ya se ve entera no se mueve nada: las dos políticas de abajo hacen
  /// exactamente eso (una resuelve el caso "quedó arriba del borde" y la
  /// otra "quedó abajo"; sobre algo ya visible, ninguna hace nada).
  void _onFocusChange(bool tieneFoco) {
    if (mounted) setState(() => _tieneFoco = tieneFoco);
    if (!tieneFoco) return;
    // ── En televisor de esto se encarga otro, y con razón ─────────────────
    //
    // `RescateDeFoco` hace exactamente lo mismo para TODA la app —también
    // para los botones de Material, que no pasan por acá— y en televisor está
    // siempre montado. O sea que cada movimiento del mando disparaba CUATRO
    // desplazamientos a la vez sobre la misma lista: los dos de acá y los dos
    // de allá, cada uno con su animación de 180 ms, peleándose entre ellos.
    //
    // Fuera de televisor el rescate no está montado, así que acá sí hace
    // falta: es lo que hace que moverse con el teclado en escritorio traiga a
    // la vista lo que se enfoca.
    if (PlatformTv.esTelevisionSync) return;
    // Después del frame: `ensureVisible` necesita que el `RenderObject` ya
    // esté ubicado con el layout nuevo, y justo después de ganar el foco
    // eso todavía puede no estar listo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = context;
      const duracion = Duration(milliseconds: 180);
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: duracion,
        curve: Curves.easeOut,
      );
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: duracion,
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final esConfirmar = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (!esConfirmar) {
      // Las flechas NO se consumen acá — ver el porqué en el doc del widget.
      // Consumirlas dejaría el mando "atascado" en una sola tarjeta.
      return KeyEventResult.ignored;
    }
    widget.onTap();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // ── En TV manda SOLO el foco, no el hover ────────────────────────────
    //
    // Al abrir una ficha desde una tarjeta, la pantalla nueva se monta
    // encima y el puntero nunca "sale" de la tarjeta: `onExit` no llega,
    // así que `_hover` se quedaba en true para siempre. Al volver, esa
    // tarjeta seguía agrandada y con su marco puesto aunque el foco
    // estuviera en otra — dos tarjetas marcadas a la vez, que es el
    // "se queda bugueado" al volver.
    //
    // En un televisor el hover ni existe (no hay puntero salvo que alguien
    // enchufe un mouse, y ahí el foco lo sigue igual), así que sacarlo de
    // la cuenta no pierde nada y elimina el estado que se queda colgado.
    final activo =
        PlatformTv.esTelevisionSync ? _tieneFoco : (_hover || _tieneFoco);
    // El color del resplandor de foco. `accent` sigue existiendo para quien
    // quiera forzar otro (la Zona +18 usa el rojo) — por defecto es el
    // mismo rosa que ya usa el hover de mouse en PC (HomeTheme.accentPink),
    // no un color aparte.
    final marco = widget.accent ?? HomeTheme.accentPink;
    // El foco de D-pad es MÁS marcado que el hover de mouse a propósito: con
    // el mando es la ÚNICA señal de dónde está parado el usuario — sin
    // cursor ni dedo que lo confirmen — así que tiene que notarse aunque se
    // mire de lejos, desde el sillón. El hover de mouse ya tiene al cursor
    // mismo como pista extra, por eso alcanza con menos.
    //
    // Reportado en vivo: en TV el resplandor solo (mismo que el hover de PC)
    // "no se ve mucho" a la distancia normal de sillón, sobre todo con una
    // portada oscura o con arte de por medio. En PC el halo se ve bien
    // porque el cursor ya marca dónde está parado el usuario, encima del
    // halo — en TV el halo es la ÚNICA pista, así que necesita más
    // intensidad Y un borde nítido que no dependa del desenfoque para
    // notarse. El hover de PC queda exactamente igual que antes.
    final esTv = PlatformTv.esTelevisionSync;
    final intensidadDelHalo = esTv ? 0.62 : (_tieneFoco ? 0.42 : 0.30);
    final blurDelHalo = esTv ? 22.0 : 11.0;
    // ── En un aparato modesto, el marco y nada más ───────────────────────
    //
    // La escala es un transform animado: obliga a recomponer la tarjeta en
    // cada cuadro de los 160 ms que dura. En un stick viejo eso es justo lo
    // que se siente como que el mando responde tarde.
    //
    // El resplandor ya dice dónde está parado el usuario —que es lo único
    // que no se puede perder— y que aparezca de golpe no se nota mal: con un
    // control remoto el foco SALTA de tarjeta en tarjeta, no se desliza.
    final conEscala = PerfilDeAparato.nivel != NivelDeAparato.bajo;
    final tarjeta = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _activar,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            // Un crecido corto a propósito.
            //
            // Con 1.06 más el halo, la tarjeta enfocada se salía bastante de
            // su celda y quedaba mordida contra el borde de cualquier lista
            // (que recorta). Quitarle el recorte a las listas es peor: lo
            // que se desplaza fuera se dibuja igual y termina encima de los
            // encabezados. Con 1.03 se nota que está elegida y casi no
            // invade, así que nada queda cortado.
            scale: (activo && conEscala) ? 1.03 : 1.0,
            // ── El resplandor va en una capa APARTE, no alrededor ────────
            //
            // Envolviendo al hijo directamente en el `BoxDecoration` con
            // sombra, cualquier relleno/recorte propio del hijo (una
            // portada con su propio `ClipRRect`) tapa la sombra en vez de
            // dejarla asomar. Como capa de arriba, superpuesta y con su
            // propio relleno transparente (mismo truco que ya usa
            // `_bordeCard` en home_media_card.dart), el hijo mide SIEMPRE
            // lo mismo y la sombra se ve completa alrededor.
            child: Stack(
              children: [
                widget.builder?.call(_tieneFoco) ?? widget.child!,
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  // Sin alto: el marco cubre al hijo entero (`bottom: 0`).
                  // Con alto: solo esa franja de arriba — la portada, sin el
                  // título de abajo. Ver `altoMarco`.
                  bottom: widget.altoMarco == null ? 0 : null,
                  height: widget.altoMarco,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: activo ? 1 : 0,
                      // ── El mismo resplandor que el hover de mouse en PC ──
                      //
                      // Antes era un marco (borde blanco/dorado según la
                      // época) — pedido explícito: que se vea igual que el
                      // hover de `TarjetaDeCatalogo` en PC, que no dibuja
                      // ningún borde: crece un poco y una sombra de tres
                      // capas la despega del fondo (una profunda, una
                      // cercana, y un halo del color de acento encima).
                      //
                      // La caja en sí queda SIN relleno (transparente): lo
                      // único que se ve es la sombra, que por definición se
                      // pinta AFUERA de estos límites — así la portada de
                      // adentro (o el hijo entero, sin `altoMarco`) se ve
                      // intacta y el resplandor solo aparece alrededor.
                      //
                      // El alcance de cada capa está topado igual que en PC
                      // (~13px) para no meterse en el hueco entre tarjetas
                      // de una fila y pintarse encima de la vecina — mismo
                      // motivo, mismo límite, ver el comentario largo en
                      // tarjeta_de_catalogo.dart.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(widget.borderRadius),
                          // Borde nítido, SOLO en TV — ver el comentario de
                          // arriba sobre por qué el halo solo no alcanza sin
                          // cursor. En PC sigue sin dibujar ningún borde,
                          // pedido explícito de que el hover se vea igual que
                          // siempre (sin marco, solo el resplandor).
                          border: esTv
                              ? Border.all(
                                  color: marco.withValues(alpha: 0.95),
                                  width: 2.5,
                                )
                              : null,
                          boxShadow: [
                            const BoxShadow(
                              color: Color(0x8A000000),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                            const BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                            BoxShadow(
                              color: marco.withValues(alpha: intensidadDelHalo),
                              blurRadius: blurDelHalo,
                              spreadRadius: esTv ? 1.5 : 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // ── Cada tarjeta se pinta en su propia capa ─────────────────────────
    //
    // Sin esto, la escala y el marco al enfocarse invalidan el pintado de
    // TODO lo que contenga a la tarjeta: en una fila de diez, mover el foco
    // una posición volvía a pintar la fila entera. Con el límite, lo único
    // que se repinta es la tarjeta que gana el foco y la que lo pierde, y la
    // escala pasa a mover una textura ya lista en vez de rehacerla.
    //
    // Es, de todo lo que se tocó, lo que más se nota con el mando en la mano.
    return RepaintBoundary(child: tarjeta);
  }
}
