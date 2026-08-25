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
    required this.child,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = 8,
    this.accent,
    this.altoMarco,
  });

  /// Alto del marco de selección, cuando NO tiene que abarcar al hijo entero.
  ///
  /// Las tarjetas del catálogo son portada + título debajo, y el marco
  /// alrededor de las dos cosas encierra un bloque de texto suelto en el
  /// aire: lo que se está eligiendo es la portada. Pasando su alto, el marco
  /// se dibuja solo sobre ella.
  final double? altoMarco;

  final Widget child;
  final VoidCallback onTap;

  /// Si no se pasa, el widget crea y descarta el suyo. Pasarlo desde afuera
  /// sirve para pedirle foco a una tarjeta puntual desde el padre (por
  /// ejemplo, la primera de una fila).
  final FocusNode? focusNode;

  final bool autofocus;
  final double borderRadius;

  /// Color del borde de foco. Por defecto [HomeTheme.accentPink]; se pasa
  /// [HomeTheme.accentRed] en pantallas de la Zona +18, mismo criterio que ya
  /// usan [HomeMediaCard]/`HomeSection` con su parámetro `accent`.
  final Color? accent;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  FocusNode? _focusNodePropio;
  bool _hover = false;
  bool _tieneFoco = false;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_focusNodePropio ??= FocusNode(debugLabel: 'FocusableCard'));

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
    // El color del marco de foco. `accent` sigue existiendo para quien
    // quiera forzar otro (la Zona +18 usa el rojo), pero por defecto es el
    // dorado — ver HomeTheme.focoTv.
    final marco = widget.accent ?? HomeTheme.focoTv;
    // El foco de D-pad es MÁS marcado que el hover de mouse a propósito: con
    // el mando es la ÚNICA señal de dónde está parado el usuario — sin
    // cursor ni dedo que lo confirmen — así que tiene que notarse aunque se
    // mire de lejos, desde el sillón. El hover de mouse ya tiene al cursor
    // mismo como pista extra, por eso alcanza con menos.
    final grosor = _tieneFoco ? 3.5 : 2.0;
    // ── En un aparato modesto, el marco y nada más ───────────────────────
    //
    // La escala es un transform animado: obliga a recomponer la tarjeta en
    // cada cuadro de los 160 ms que dura. En un stick viejo eso es justo lo
    // que se siente como que el mando responde tarde.
    //
    // El marco dorado ya dice dónde está parado el usuario —que es lo único
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
            // ── El borde va ENCIMA, no alrededor ─────────────────────────
            //
            // Con `Border.all` en el contenedor que envuelve al hijo, el
            // grosor del borde le come lugar POR DENTRO: al enfocarse, la
            // portada se achicaba unos píxeles y al desenfocarse volvía a
            // crecer. Sumado a la escala, eso es el temblor feo que se veía
            // al mover el foco de una tarjeta a otra.
            //
            // Como capa de arriba (mismo truco que ya usa `_bordeCard` en
            // home_media_card.dart) el hijo mide SIEMPRE lo mismo: lo único
            // que cambia es la línea pintada encima.
            child: Stack(
              children: [
                widget.child,
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
                      // Un solo marco, dorado.
                      //
                      // Antes era del acento (rosa) con una línea clara por
                      // dentro, porque sobre un botón YA rosa el marco se
                      // fundía con el fondo. Esa línea doble se veía sucia y
                      // dura de cerca; el dorado resuelve lo mismo con una
                      // sola línea limpia — no se parece a ningún relleno de
                      // la app, así que se distingue sobre cualquier cosa.
                      //
                      // Va dibujado con `Container` y no con `DecoratedBox`
                      // pelado para poder pedir `Clip.antiAlias`: sin eso,
                      // la curva de las esquinas sale escalonada (los
                      // "pixeles" que se veían en el borde).
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(widget.borderRadius),
                          // Solo la línea, sin halo ni sombra: el dorado ya
                          // contrasta con todo lo de la app, y el resplandor
                          // alrededor ensuciaba la portada en vez de
                          // ayudar.
                          border: Border.all(color: marco, width: grosor),
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
