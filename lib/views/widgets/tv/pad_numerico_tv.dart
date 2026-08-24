import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// Un teclado numérico en pantalla, para el PIN en televisor.
///
/// El campo de PIN de siempre es un `TextField`: al enfocarlo, Android
/// levanta su teclado, que en una TV ocupa media pantalla y se maneja con el
/// mando de forma bastante incómoda. Con este pad el PIN se escribe con las
/// flechas y OK, sin que aparezca nada encima.
///
/// Va en el acento rojo de la Zona +18 (mismo criterio que el resto de esa
/// zona), y quien lo usa decide qué hacer con cada dígito.
class PadNumericoTv extends StatelessWidget {
  const PadNumericoTv({
    super.key,
    required this.onDigito,
    required this.onBorrar,
    this.accent,
  });

  final void Function(String digito) onDigito;
  final VoidCallback onBorrar;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? HomeTheme.accentRed;
    Widget tecla(String texto, {VoidCallback? alTocar, IconData? icono}) {
      return FocusableCard(
        borderRadius: 12,
        accent: color,
        onTap: alTocar ?? () => onDigito(texto),
        child: Container(
          width: 72,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HomeTheme.border),
          ),
          child: icono != null
              ? Icon(icono, size: 22, color: HomeTheme.textPrimary)
              : Text(
                  texto,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: HomeTheme.textPrimary,
                  ),
                ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final fila in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in fila) ...[
                  tecla(d),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // El hueco donde iría una tecla, para que el 0 quede centrado
            // debajo del 8 como en cualquier teclado numérico.
            const SizedBox(width: 82),
            tecla('0'),
            const SizedBox(width: 10),
            tecla('', icono: Icons.backspace_outlined, alTocar: onBorrar),
          ],
        ),
      ],
    );
  }
}
