import 'package:flutter/material.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// Las rayitas que dicen en cuál de la tanda vas.
///
/// Rayas y no puntos: con puntos, cinco posiciones se leen como cinco puntos
/// sueltos y no como una barra de avance. La raya llena ocupa lugar y se
/// entiende de un vistazo cuánto queda de la tanda.
///
/// Se pueden tocar para saltar directo. Es un objetivo chiquito, así que cada
/// una lleva un área de toque más grande que la raya que se ve.
///
/// ── Por qué está acá y no dentro del Home ───────────────────────────────
///
/// Nació ahí, para el acordeón y para la grilla. Ahora también las usa la lista
/// de extensiones instaladas, que dejó los botones de página por deslizamiento.
/// Compartida en un solo lugar para que las tres se vean iguales: si se copiaba,
/// al rato una tenía las rayas de otro largo o de otro color, que es justo lo
/// que pasó con los títulos de las zonas.
class IndicadoresDePagina extends StatelessWidget {
  const IndicadoresDePagina({
    super.key,
    required this.cantidad,
    required this.actual,
    required this.onTocar,
  });

  /// Cuántas rayitas se dibujan. Ver [maximo]: quien llama recorta la cuenta y
  /// mapea la posición, porque solo él sabe a dónde lleva cada raya.
  final int cantidad;
  final int actual;
  final ValueChanged<int> onTocar;

  /// El tope de rayitas que se dibujan, por más páginas que haya.
  ///
  /// Con veinte páginas, veinte rayas no se leen: son una línea punteada donde
  /// no se distingue cuál está encendida, y encima cambia de ancho cada vez que
  /// entra o sale contenido. Con el tope, la fila mide siempre lo mismo y cada
  /// raya representa un tramo.
  static const maximo = 8;

  @override
  Widget build(BuildContext context) {
    // Con una sola no hay nada que indicar.
    if (cantidad < 2) return const SizedBox.shrink();
    final esTv = PlatformTv.esTelevisionSync;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cantidad; i++)
          _raya(i, esTv),
      ],
    );
  }

  Widget _raya(int i, bool esTv) {
    final raya = Padding(
      // El aire va ADENTRO del área de toque, no entre widgets: así lo que
      // se puede tocar es más grande que la raya sin que las rayas queden
      // separadas de más.
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: i == actual ? 30 : 20,
        height: 3,
        decoration: BoxDecoration(
          color: i == actual
              ? HomeTheme.accentPink
              : HomeTheme.contraste.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    // ── En televisor, cada raya se puede enfocar y saltar con el mando ────
    //
    // Con solo GestureDetector, esto pedía mouse o dedo: la lista de
    // extensiones instaladas dejó los botones de página por esto mismo
    // (con más de cinco extensiones instaladas, saltar de página era
    // imposible con el control remoto — no había otra forma de llegar a
    // las siguientes). El mismo `onTocar` que ya usa el toque sirve tal
    // cual para el D-pad; solo hacía falta darle dónde pararse.
    if (!esTv) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTocar(i),
        child: raya,
      );
    }
    return FocusableCard(
      borderRadius: 6,
      onTap: () => onTocar(i),
      child: raya,
    );
  }
}
