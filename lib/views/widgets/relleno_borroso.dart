import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// El relleno que va DETRÁS de una imagen que no llena su caja: la misma
/// imagen estirada a cubrir y desdibujada, para que los costados no queden en
/// negro.
///
/// ── Por qué es un widget compartido y no dos copias ─────────────────────
///
/// El mismo truco estaba escrito dos veces —en la tarjeta de «Continuar
/// viendo» y en la portada de la ficha— con dos formas distintas de resolver
/// lo mismo. Acá vive una sola, y con ella la decisión de cuánto puede gastar
/// este aparato.
///
/// ── Cómo se consigue el borroso, y por qué no siempre igual ─────────────
///
/// `ImageFilter.blur` es lo más caro que dibuja Flutter: obliga a componer la
/// imagen en una capa aparte, desenfocarla y volver a pegarla. Con una tarjeta
/// pasa desapercibido; en una fila con varias, o a pantalla completa, no.
///
/// En escritorio y teléfono se sigue haciendo así, porque ahí sobra GPU y el
/// resultado es el mejor. En un televisor se consigue lo mismo de otra manera:
/// **decodificando la imagen diminuta y dejando que se estire**. Al ampliar,
/// el propio suavizado del motor la deja difusa — el efecto es prácticamente
/// el mismo y no cuesta ni un filtro ni una capa de más. De paso ocupa una
/// fracción de la memoria, que es el otro problema de estos aparatos.
class RellenoBorroso extends StatelessWidget {
  const RellenoBorroso({
    super.key,
    required this.imagen,
    required this.anchoDeLaCaja,
    this.velo = const Color(0x66000000),
  });

  /// Dibuja la imagen del relleno, estirada a cubrir, decodificada al ancho
  /// que se le pide.
  ///
  /// Es un callback y no un `Widget` ya armado porque el ancho de
  /// decodificación es justamente lo que cambia según el aparato, y eso solo
  /// lo puede aplicar quien construye la imagen (una viene de la red y otra de
  /// un archivo local).
  final Widget Function(int cacheWidth) imagen;

  /// El ancho, en puntos, del lugar que va a ocupar el relleno. De acá sale a
  /// qué tamaño conviene decodificar.
  final double anchoDeLaCaja;

  /// El velo oscuro que va encima, para que la imagen de adelante resalte y el
  /// texto siga legible. En null no se pone ninguno.
  final Color? velo;

  /// Por cuánto se divide la resolución del relleno.
  ///
  /// Va desenfocado igualmente, así que más resolución no se ve; lo único que
  /// hace es ocupar memoria. En televisor se achica mucho más porque ahí ese
  /// achicado ES el desenfoque (ver la explicación de la clase).
  static int get _divisor =>
      PerfilDeAparato.nivel.elegir(alto: 4, medio: 16, bajo: 16);

  /// Cuánto desenfoque de verdad se aplica. Cero = ninguno.
  static double get _sigma =>
      PerfilDeAparato.nivel.elegir(alto: 18, medio: 0, bajo: 0);

  @override
  Widget build(BuildContext context) {
    final ancho = (anchoDeLaCaja *
            MediaQuery.devicePixelRatioOf(context) /
            _divisor)
        .ceil()
        .clamp(1, 4096);
    Widget fondo = imagen(ancho);
    final sigma = _sigma;
    if (sigma > 0) {
      fondo = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: fondo,
      );
    }
    if (velo == null) return fondo;
    return Stack(
      fit: StackFit.expand,
      children: [
        fondo,
        // Un color plano encima, no un `Opacity` alrededor: pintar un
        // rectángulo semitransparente es de lo más barato que hay, mientras
        // que `Opacity` obliga a componer todo el subárbol en una capa aparte
        // solo para bajarle la intensidad.
        ColoredBox(color: velo!),
      ],
    );
  }
}
