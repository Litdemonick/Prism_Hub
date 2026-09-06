import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/fondo_tv.dart';

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
  /// pueda).
  ///
  /// Null NO es «sin fondo»: es «el de la app». Antes sí quedaba liso, y por
  /// eso el repositorio, la ficha y la lista de extensiones se veían de un
  /// gris distinto al del resto — se notaba el salto al entrar. El fondo de
  /// PrismHub en televisor es uno solo y está en todas las pantallas
  /// (`FondoTv`); pasar algo acá es para taparlo con otra cosa en una
  /// pantalla puntual, como la portada difuminada de una ficha.
  final Widget? fondo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: Stack(
        // ── El contenido ocupa la pantalla, no lo que midan sus hijos ────
        //
        // Un hijo de `Stack` sin posicionar recibe restricciones SUELTAS:
        // puede quedarse tan chico como su contenido. Al buscador eso le
        // pasaba factura — su columna de teclado mide lo que mide, así que
        // la pantalla entera se encogía contra el borde de arriba y abajo
        // quedaba una franja muerta. Reportado con foto: «el fondo se movió
        // arriba y no está en toda la pantalla».
        //
        // Con `expand`, el contenido recibe el tamaño completo y cada
        // pantalla reparte su alto como quiera.
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: fondo ?? const FondoTv()),
          SafeArea(
            child: Padding(
              // Un solo sitio decide el margen. Ver HomeTheme.margenTv:
              // a los costados va entero, arriba y abajo un tercio, para no
              // regalar el 18 % de la altura de la pantalla.
              padding: HomeTheme.margenTv(context),
              child: FocusTraversalGroup(child: child),
            ),
          ),
        ],
      ),
    );
  }
}
