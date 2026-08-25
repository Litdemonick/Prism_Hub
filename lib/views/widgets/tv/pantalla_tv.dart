import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// El envoltorio que usa toda pantalla PROPIA de Android TV (no las que
/// reusan una de teléfono/escritorio con `FocusableCard` puesto por dentro).
///
/// ── Por qué hace falta, y qué venía pasando sin él ───────────────────────
///
/// Cada pantalla de TV rearmaba a mano el mismo `Scaffold` con el mismo
/// margen de seguridad, y una se olvidó: el buscador de TV usaba un
/// `EdgeInsets.all(28)` fijo en vez del overscan real, así que en un
/// televisor que recorta el borde el teclado en pantalla quedaba pegado al
/// filo. Con esto una pantalla nueva NO PUEDE nacer sin margen seguro —lo
/// pone este widget, no cada una por su cuenta.
///
/// Trae, en un solo lugar:
///
///   · El fondo (`HomeTheme.bg`) y, si se pasa uno, una capa detrás del
///     contenido — la portada difuminada de una ficha, el resplandor
///     animado, lo que corresponda a esa pantalla.
///   · El margen de overscan (`HomeTheme.overscanTv`), aplicado UNA vez en
///     el contenedor raíz — nunca en cada widget hijo, que es como se
///     termina duplicando o, peor, olvidando.
///   · Un `FocusTraversalGroup` que delimita la pantalla: así el foco no se
///     escapa hacia atrás, a lo que quedó montado detrás en el
///     `IndexedStack` de la barra principal.
class PantallaTv extends StatelessWidget {
  const PantallaTv({super.key, required this.child, this.fondo});

  /// El contenido real de la pantalla. Se dibuja YA adentro del margen de
  /// overscan — no hay que volver a aplicarlo.
  final Widget child;

  /// Lo que va DETRÁS del contenido, a pantalla completa y sin overscan (un
  /// fondo tiene que llegar hasta el borde de verdad, aunque el contenido no
  /// pueda). Null = liso, con el color de fondo de siempre.
  final Widget? fondo;

  @override
  Widget build(BuildContext context) {
    final overscan = HomeTheme.overscanTv(context);
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: Stack(
        children: [
          if (fondo != null) Positioned.fill(child: fondo!),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(overscan),
              child: FocusTraversalGroup(child: child),
            ),
          ),
        ],
      ),
    );
  }
}
