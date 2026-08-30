import 'dart:io';

import 'package:flutter/material.dart';

/// Deja seleccionar el texto, pero solo donde no rompe.
///
/// ── El fallo que esto evita ─────────────────────────────────────────────────
///
/// Reportado en vivo desde un teléfono, con el registro adjunto:
///
///     SEVERE: Null check operator used on a null value
///       #0 SelectableRegionState.endGlyphHeight
///          (package:flutter/src/widgets/selectable_region.dart:1783)
///
/// repetido, y detrás una cascada de `State.context` sobre widgets ya
/// desmontados — que es el ErrorWidget reemplazando el subárbol una y otra
/// vez. La pantalla del registro no llegaba a abrirse.
///
/// `endGlyphHeight` es de los MANEJADORES de selección, esos dos círculos con
/// los que se ajusta la selección con el dedo. Existen solo en móvil. Y esta
/// lista se rehace cuatro veces por segundo mientras entran líneas: la región
/// pierde el glifo sobre el que tenía puesto un manejador y revienta al ir a
/// medirlo.
///
/// ── Por qué en escritorio sí ────────────────────────────────────────────────
///
/// Ahí la selección se hace con el ratón y no hay manejadores, así que ese
/// camino no se recorre. Y es donde de verdad se usa: copiar un tramo del
/// registro para pegarlo en un reporte se hace en un PC, no en un televisor
/// con un mando ni en un teléfono donde ya existe el botón de exportar.
class SeleccionableSiSePuede extends StatelessWidget {
  const SeleccionableSiSePuede({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final escritorio =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (!escritorio) return child;
    return SelectionArea(child: child);
  }
}
