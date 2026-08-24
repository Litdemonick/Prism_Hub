import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  });

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
    final activo = _hover || _tieneFoco;
    final accent = widget.accent ?? HomeTheme.accentPink;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (tieneFoco) {
        if (mounted) setState(() => _tieneFoco = tieneFoco);
      },
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _activar,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 150),
            scale: activo ? 1.05 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: activo ? accent : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
