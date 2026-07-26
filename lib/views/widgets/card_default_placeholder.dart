import 'dart:io';

import 'package:flutter/material.dart';

// Tarjeta mientras una extensión todavía no trajo resultados — antes era un
// pulso de opacidad sobre un rectángulo gris liso (abstracto, no parecía una
// tarjeta real). A pedido explícito: mostrar directamente
// carddefaultoffline.png con el mismo tamaño/forma exacto de la tarjeta
// final (ExtensionItemCard/GridItemTile), así al llegar los datos reales
// solo cambia la imagen y el título — el contenedor nunca se mueve ni
// cambia de tamaño.
class CardDefaultPlaceholder extends StatelessWidget {
  const CardDefaultPlaceholder({super.key});

  // Igual que Cover (cover.dart): width/height infinity para llenar la caja
  // que le da el padre en vez de basarse en el tamaño intrínseco del PNG —
  // el padre (el Container de ancho fijo dentro del ListView horizontal en
  // search_all_tile.dart) es quien realmente define el tamaño final.
  Widget _image() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/carddefaultoffline.png',
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) return _image();
    // Reserva el mismo alto que ocupa el título en la tarjeta real
    // (GridItemTile: SizedBox(height: 8) + título de 20) — sin esto, la
    // tarjeta placeholder queda más baja y todo el resto de la fila salta
    // hacia arriba/abajo apenas llega la primera tarjeta real.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _image()),
        const SizedBox(height: 8),
        const SizedBox(height: 20),
      ],
    );
  }
}
