import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Deja recorrer con el control remoto algo que se desplaza.
///
/// ── Por qué hace falta ──────────────────────────────────────────────────────
///
/// Varias pantallas de la app se desplazan con el dedo (en teléfono) o con la
/// rueda del ratón (en escritorio), y ninguna de las dos existe en un
/// televisor. Si además no hay nada adentro que tome el foco —una lista de
/// texto, por ejemplo— las flechas del mando no llegan a ninguna parte y todo
/// lo que no entre en pantalla queda, sencillamente, ilegible.
///
/// Reportado en vivo dos veces: el aviso de versión nueva y la pantalla del
/// registro. En las dos, lo que no entraba no había forma de leerlo.
///
/// ── Cómo se comporta ────────────────────────────────────────────────────────
///
/// Toma el foco al aparecer y traduce arriba/abajo a desplazamiento. Se queda
/// solo con esas dos teclas; el resto pasa de largo, así que los botones que
/// haya alrededor se siguen alcanzando como siempre.
///
/// **Al llegar al tope devuelve la tecla** en vez de quedársela. Es lo que
/// permite que el foco salga hacia los botones: quedársela encerraría al
/// usuario en un texto del que no se puede salir, que es peor que no poder
/// desplazarlo.
///
/// Fuera de televisor devuelve al hijo tal cual — no se interpone en nada.
class DesplazableConMando extends StatefulWidget {
  const DesplazableConMando({
    super.key,
    required this.controlador,
    required this.child,
    this.autofocus = true,
    this.paso = 220,
    this.alCambiarFoco,
  });

  final ScrollController controlador;
  final Widget child;

  /// Avisa cuando esta zona toma o suelta el foco.
  ///
  /// En un televisor lo primero que hay que saber es DÓNDE estás parado, y un
  /// bloque de texto que se desplaza no tiene forma de mostrarlo por su
  /// cuenta — no hay tarjeta que se ilumine. Con esto, quien lo usa puede
  /// dibujar el borde encendido alrededor.
  final ValueChanged<bool>? alCambiarFoco;

  /// Si toma el foco al aparecer. Se apaga cuando hay otra cosa en la pantalla
  /// que debería recibirlo primero.
  final bool autofocus;

  /// Cuánto se mueve por pulsación.
  ///
  /// El valor de fábrica es poco más de media pantalla de televisor: una
  /// pantalla entera desorienta —se pierde el hilo de lo que se venía
  /// leyendo— y unas pocas líneas obligan a machacar el botón.
  final double paso;

  @override
  State<DesplazableConMando> createState() => _DesplazableConMandoState();
}

class _DesplazableConMandoState extends State<DesplazableConMando> {
  /// Mueve la vista. [sostenido] es cierto cuando el botón viene apretado.
  ///
  /// ── Por qué el botón sostenido NO anima ─────────────────────────────────
  ///
  /// Reportado en vivo: «al scrollear presionando se para, y tocando otra vez
  /// como que carga». La causa se ve en el reloj: el mando repite la tecla
  /// cada ~50 ms y la animación duraba 180. Cada repetición arrancaba una
  /// animación NUEVA desde donde estuviera la anterior, cortándola — así que
  /// el texto avanzaba a saltos cortos y por momentos parecía frenarse del
  /// todo, porque cada animación gastaba su curva de entrada y nunca llegaba
  /// a la parte rápida.
  ///
  /// Con el botón sostenido se salta directo, sin curva: el movimiento sale
  /// parejo, que es lo que se espera de mantener apretado. Una pulsación
  /// suelta sí se anima — ahí la animación ayuda a no perder el hilo de dónde
  /// estaba uno leyendo.
  bool _mover(double delta, {required bool sostenido}) {
    if (!widget.controlador.hasClients) return false;
    final pos = widget.controlador.position;
    final destino =
        (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (destino == pos.pixels) return false;
    if (sostenido) {
      widget.controlador.jumpTo(destino);
    } else {
      widget.controlador.animateTo(
        destino,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformTv.esTelevisionSync) return widget.child;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: widget.alCambiarFoco,
      onKeyEvent: (nodo, evento) {
        if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final sostenido = evento is KeyRepeatEvent;
        final tecla = evento.logicalKey;
        // Se aceptan también RePág/AvPág: varios mandos las mandan con los
        // botones de salto rápido, y ahí mover una pantalla entera sí es lo
        // que se espera.
        if (tecla == LogicalKeyboardKey.arrowDown) {
          return _mover(widget.paso, sostenido: sostenido)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (tecla == LogicalKeyboardKey.arrowUp) {
          return _mover(-widget.paso, sostenido: sostenido)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (tecla == LogicalKeyboardKey.pageDown) {
          return _mover(widget.paso * 3, sostenido: sostenido)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (tecla == LogicalKeyboardKey.pageUp) {
          return _mover(-widget.paso * 3, sostenido: sostenido)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}
