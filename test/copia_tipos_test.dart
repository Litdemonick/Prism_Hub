// Los favoritos y el historial vuelven a SU sección.
//
// Inicio y la Zona +18 separan en dos: "Favoritos — Vídeo" y "Favoritos —
// Lectura", y lo mismo con Continuar. La regla la pone home_page: bangumi es
// vídeo, todo lo demás es lectura. Si el tipo no vuelve exacto de la copia, un
// manga aparece entre los animes o al revés.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/copia_seguridad.dart';

void main() {
  ExtensionType tipo(Object? v) => CopiaSeguridad.tipoDePrueba(v);

  // La misma regla que usa Inicio para separar las dos secciones.
  bool esVideo(ExtensionType t) => t == ExtensionType.bangumi;

  test('cada tipo vuelve exactamente igual', () {
    for (final t in ExtensionType.values) {
      expect(tipo(t.name), t, reason: 'se perdió el tipo ${t.name}');
    }
  });

  test('el vídeo vuelve a la sección de vídeo', () {
    expect(esVideo(tipo('bangumi')), isTrue);
  });

  test('la lectura vuelve a la sección de lectura', () {
    // Las cuatro que no son vídeo.
    for (final n in ['manga', 'fikushon', 'mixed', 'mixedReading']) {
      expect(esVideo(tipo(n)), isFalse, reason: '"$n" cayó en vídeo');
    }
  });

  test('un tipo desconocido cae en lectura, no en vídeo', () {
    // A propósito: en lectura una tarjeta de proporción rara se ve mal pero se
    // ve; en vídeo, además de romper la fila, el reproductor intentaría abrir
    // algo que no es un vídeo.
    for (final raro in ['algoNuevo', '', null, 123]) {
      expect(esVideo(tipo(raro)), isFalse, reason: '"$raro" cayó en vídeo');
    }
  });
}
