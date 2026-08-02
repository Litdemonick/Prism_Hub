import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prismhub/utils/color.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';

/// Redondea hacia arriba a tramos de 128 píxeles.
///
/// Sirve para que el tamaño de decodificación —que es parte de la clave con la
/// que Flutter guarda la imagen en caché— no cambie con cada píxel que cambie
/// la caja. Ver el uso en Cover.
int _tramo(double pixeles) {
  const paso = 128;
  final n = pixeles.ceil().clamp(1, 4096);
  return ((n + paso - 1) ~/ paso * paso).clamp(paso, 4096);
}

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
            // Se decodifica al LADO MÁS GRANDE de la caja, redondeado.
            //
            // Antes se usaba solo el ancho. Con BoxFit.cover eso alcanza cuando
            // la imagen es más ancha que alta y la caja también, pero no
            // siempre: una miniatura apaisada dentro de una tarjeta vertical se
            // escala por el ALTO, y ahí decodificar al ancho de la caja deja un
            // mapa de bits más chico del que hace falta. Después se agranda para
            // llenar, y eso es exactamente lo que se veía borroso.
            //
            // Con el lado más grande, cualquiera de las dos orientaciones queda
            // con píxeles de sobra. Se decodifica un poco más de lo justo en
            // algunos casos, que al lado de una imagen borrosa es barato.
            //
            // Lo del redondeo NO es un detalle: Flutter guarda la imagen en
            // caché con una clave que incluye el tamaño de decodificación. En el
            // encabezado del detalle, el alto cambia en cada fotograma mientras
            // se colapsa al desplazarse — sin redondear, la clave cambiaría
            // igual de seguido y la imagen se volvería a decodificar entera una
            // y otra vez, que es de donde salía el parpadeo en negro. Por
            // tramos de 128 la clave se queda quieta casi todo el recorrido.
            cacheWidth: bounded
                ? _tramo(math.max(constraints.maxWidth, constraints.maxHeight) *
                    dpr)
                : null,
            // medium y no low: al achicar una portada grande a una tarjeta
            // chica, low se salta píxeles y deja los bordes dentados.
            filterQuality: FilterQuality.medium,
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
