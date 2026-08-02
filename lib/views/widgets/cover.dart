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
    this.alignment = Alignment.center,
  });
  final String? url;
  final String alt;
  final bool noText;
  final Map<String, String>? headers;
  // Qué parte de la imagen queda centrada al recortar con cover — por
  // defecto el centro, pero el fondo del detalle (una portada angosta
  // estirada como banner ancho) se ve mejor mostrando más de la parte de
  // abajo en vez del centro exacto.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (url?.isNotEmpty == true) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final bounded =
              constraints.maxWidth.isFinite && constraints.maxHeight.isFinite;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          return CacheNetWorkImagePic(
            url!,
            width: double.infinity,
            height: double.infinity,
            headers: headers,
            alignment: alignment,
            // Solo el ANCHO decide a qué tamaño se decodifica. El alto NO.
            //
            // Flutter guarda la imagen en caché con una clave que incluye el
            // tamaño de decodificación. Pasando el alto de las restricciones
            // vivas, esa clave cambiaba en CADA fotograma mientras el
            // encabezado del detalle se colapsa al hacer scroll: la imagen se
            // volvía a decodificar entera una y otra vez, y en el rato que
            // tarda cada decodificación no hay nada que pintar. Eso es el
            // parpadeo en negro al desplazarse.
            //
            // El ancho no cambia al desplazarse en vertical, así que como clave
            // es estable: se decodifica UNA vez y se reusa todo el scroll. La
            // proporción la mantiene el propio decodificador, y el recorte al
            // alto disponible lo hace el BoxFit como siempre.
            cacheWidth: bounded
                ? (constraints.maxWidth * dpr).ceil().clamp(1, 4096).toInt()
                : null,
          );
        },
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
