import 'package:flutter/material.dart';
import 'package:prismhub/utils/color.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';

class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.alt,
    this.url,
    this.noText = false,
    required this.headers,
  });
  final String? url;
  final String alt;
  final bool noText;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    if (url?.isNotEmpty == true) {
      return CacheNetWorkImagePic(
        url!,
        width: double.infinity,
        height: double.infinity,
        headers: headers,
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      // decoration (no color:) — Container exige decoration != null cuando
      // clipBehavior no es Clip.none, si no tira "Failed assertion" en
      // tiempo de ejecución (el error rojo que tapaba toda la tarjeta).
      decoration: BoxDecoration(color: ColorUtils.getColorByText(alt)),
      // hardEdge: sin esto, un título largo en una portada angosta (ej. el
      // thumbnail chico del detalle) rendereaba más líneas de las que
      // entraban en alto y se veía "sangrando" fuera de la tarjeta en vez
      // de recortarse limpio.
      clipBehavior: Clip.hardEdge,
      child: noText
          ? const SizedBox.expand()
          : Center(
              child: Text(
                alt,
                style: const TextStyle(
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            ),
    );
  }
}
