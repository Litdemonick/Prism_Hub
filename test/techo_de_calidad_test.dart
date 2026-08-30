import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Qué calidad de vídeo se pide según la pantalla que tiene el aparato.
///
/// ── Por qué esto importa ────────────────────────────────────────────────────
///
/// Se pedía 1080p en todos lados. En un televisor de 1280x720 eso es decodificar
/// un tercio más de imagen de la que se puede mostrar y descargar casi el doble
/// de datos. Medido en un MediaTek de 0,9 GB con Android 9: «colchón: 0 s ·
/// entrando: 506 B/s», el colchón vacío y la reproducción parándose sola.
///
/// La regla es: la primera altura estándar que CUBRA la pantalla. Quedarse
/// corto se nota —una imagen chica estirada se ve mal—; pasarse un poco, no.
void main() {
  int techo(double alto) =>
      VideoPlayerController.techoParaPantallaDe(alto);

  group('y también del aparato', () {
    // El tope de la pantalla no cubre a un teléfono lento: su pantalla es de
    // 1080p o más, así que ese tope no lo frena nunca aunque tenga dos núcleos
    // y poca memoria. Ni a un televisor con panel 4K y procesador de 2018, que
    // es el caso más común. Por eso hay un segundo tope, y manda el más bajo.
    test('un aparato modesto no pasa de 720', () {
      expect(VideoPlayerController.techoParaNivel(NivelDeAparato.bajo), 720);
    });

    test('uno medio llega a 1080', () {
      expect(VideoPlayerController.techoParaNivel(NivelDeAparato.medio), 1080);
    });

    test('uno capaz no se frena por acá: decide la pantalla', () {
      expect(VideoPlayerController.techoParaNivel(NivelDeAparato.alto), 2160);
    });
  });

  group('el techo de calidad sale de la pantalla', () {
    test('un televisor de 720p pide 720, no 1080', () {
      expect(techo(720), 720);
    });

    test('uno de 1080p pide 1080', () {
      expect(techo(1080), 1080);
    });

    test('un Fire TV 4K pide 2160, no se queda en 1080', () {
      // El pedido explícito: si el televisor es más potente, la app tiene que
      // aprovecharlo en vez de tratarlo como al más modesto.
      expect(techo(2160), 2160);
    });

    test('uno de 1440 pide 1440', () {
      expect(techo(1440), 1440);
    });

    test('una pantalla entre dos escalones sube al de arriba', () {
      // 800 px: con 720 la imagen quedaría estirada, con 1080 no. Se prefiere
      // pasarse antes que quedarse corto.
      expect(techo(800), 1080);
      expect(techo(1200), 1440);
    });

    test('más alta que 4K se queda en 4K', () {
      // Es lo máximo que publican las fuentes; pedir más no traería nada.
      expect(techo(4320), 2160);
    });

    test('una medida que no puede ser un televisor deja el de siempre', () {
      // Sin un dato creíble, un tope inventado es peor que el de antes.
      expect(techo(0), 1080);
      expect(techo(320), 1080);
      // Ni un número que no es un número, ni uno infinito: los dos salen de
      // una medida que falló, no de una pantalla enorme.
      expect(techo(double.nan), 1080);
      expect(techo(double.infinity), 1080);
    });
  });
}
