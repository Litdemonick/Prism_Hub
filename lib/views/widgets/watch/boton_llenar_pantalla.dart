import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// El botón de "llenar pantalla" de los lectores — con su nombre al lado del
/// ícono, a pedido explícito, no solo un ícono suelto.
///
/// Vive acá y no adentro de un lector porque lo usan los dos (cómics y
/// novelas) y son pantallas distintas: tenerlo duplicado era garantía de que
/// tarde o temprano quedaran diferentes entre sí.
class BotonLlenarPantalla extends StatelessWidget {
  const BotonLlenarPantalla({
    super.key,
    required this.activo,
    required this.onTap,
  });

  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: activo
              ? HomeTheme.accentPink.withValues(alpha: 0.18)
              : Colors.transparent,
          border: Border.all(
            color: activo ? HomeTheme.accentPink : HomeTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activo ? Icons.fullscreen_exit : Icons.fullscreen,
              size: 18,
              color: activo ? HomeTheme.accentPink : HomeTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'reader.fill-screen'.i18n,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: activo ? HomeTheme.accentPink : HomeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
