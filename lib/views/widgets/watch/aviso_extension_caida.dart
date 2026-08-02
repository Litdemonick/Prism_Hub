import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';

/// Lo que se ve cuando la extensión dejó de estar mientras se veía o se leía.
///
/// Es distinto de "falló el servidor, probá otro": acá no hay otro. Los
/// servidores, los episodios y los capítulos salen todos de la misma extensión,
/// así que si esa se cayó no queda nada que reintentar y ofrecerlo sería mandar
/// al usuario a dar vueltas.
///
/// Por eso el único botón es salir. Y es un botón de verdad y no solo un texto:
/// la pantalla del reproductor tapa todo y con el vídeo parado no siempre queda
/// claro cómo se sale.
///
/// Compartido entre el reproductor y el lector para que digan exactamente lo
/// mismo: es la misma situación y confundiría que se explicara de dos formas.
class AvisoExtensionCaida extends StatelessWidget {
  const AvisoExtensionCaida({
    super.key,
    required this.motivo,
    required this.onSalir,
  });

  /// Ya traducido: qué le pasó a la extensión.
  final String motivo;
  final VoidCallback onSalir;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.orange.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_off_outlined,
                color: Colors.orange, size: 34),
            const SizedBox(height: 12),
            Text(
              motivo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onSalir,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text('extension.gone-exit'.i18n),
            ),
          ],
        ),
      ),
    );
  }
}
