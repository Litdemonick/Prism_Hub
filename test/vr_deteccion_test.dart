// Cuándo se ofrece el interruptor de "ver VR en una sola pantalla".
//
// Acertar acá importa en las dos direcciones: si no detecta, el usuario abre un
// vídeo VR y no tiene forma de verlo sin gafas; si detecta de más, aparece un
// interruptor que recorta media imagen en un vídeo normal.
//
// El fallo que motivó estas pruebas: se exigía que el vídeo fuera 3 veces más
// ancho que alto, y el formato VR más común —180 lado a lado— es 2:1.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';

void main() {
  bool vr(int w, int h, [String pistas = '']) =>
      VideoPlayerController.pareceVr(w, h, pistas);

  group('por la forma sola', () {
    test('360 lado a lado es VR aunque no lo diga el nombre', () {
      // Ningún vídeo normal es tan ancho, así que no hace falta más.
      expect(vr(7680, 1920), isTrue);
      expect(vr(5760, 1920), isTrue);
    });

    test('un vídeo normal no es VR', () {
      expect(vr(1920, 1080), isFalse);
      expect(vr(3840, 2160), isFalse);
      // Panorámico de cine: ancho, pero no tanto.
      expect(vr(2560, 1080), isFalse);
    });

    test('medidas imposibles no rompen nada', () {
      expect(vr(0, 0), isFalse);
      expect(VideoPlayerController.pareceVr(null, 1080, 'vr'), isFalse);
      expect(VideoPlayerController.pareceVr(1920, null, 'vr'), isFalse);
    });
  });

  group('por la forma más el nombre', () {
    test('180 lado a lado (2:1) es VR cuando el nombre lo dice', () {
      // Este es el caso que no aparecía: 3840x1920 es 2:1, no llega a 3:1.
      expect(vr(3840, 1920, 'Algo VR180 SBS'), isTrue);
      expect(vr(3840, 1920, 'algo-vr-180-sbs.mp4'), isTrue);
      expect(vr(3840, 1920, 'https://x/vr/360/video.mp4'), isTrue);
    });

    test('arriba-abajo (1:1) también, con el nombre', () {
      expect(vr(1920, 1920, 'VR over-under'), isTrue);
      expect(vr(2160, 2160, 'algo 3D'), isTrue);
    });

    test('sin pista en el nombre, un 2:1 se trata como normal', () {
      // Hay vídeo panorámico normal en 2:1, y meterle el recorte de VR le
      // partiría la imagen al medio.
      expect(vr(3840, 1920, 'Un documental cualquiera'), isFalse);
      expect(vr(1920, 1080, 'Un documental cualquiera'), isFalse);
    });

    test('"vr" tiene que ser una palabra, no parte de otra', () {
      // Sin esto, cualquier titulo con "vrai", "servrix" o similar prendia el
      // recorte en un video normal.
      expect(vr(3840, 1920, 'Le vrai documentaire'), isFalse);
      expect(vr(3840, 1920, 'covr band live'), isFalse);
    });
  });
}
