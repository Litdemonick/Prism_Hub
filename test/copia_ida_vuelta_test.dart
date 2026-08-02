// Un registro entero, de la base al archivo y de vuelta.
//
// Es la comprobacion que de verdad importa. Si algo se pierde en ese viaje, al
// importar aparecen tarjetas sin imagen. Y si la DIRECCION cambia aunque sea un
// caracter, deja de reconocer el registro que ya estaba y se crea otro al lado:
// eso son los duplicados.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/models/favorite.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/utils/copia_seguridad.dart';

void main() {
  // Un registro como los de verdad, con una portada de las que usan las
  // extensiones.
  History muestra() => History()
    ..package = 'io.prismhub.jkanime'
    ..url = 'https://jkanime.net/futsutsuka-na-oyako-de-wa-arimasu-ga/'
    ..cover = 'https://cdn.jkanime.net/assets/images/animes/image/'
        'futsutsuka-na-oyako-de-wa-arimasu-ga.jpg'
    ..type = ExtensionType.bangumi
    ..episodeGroupId = 0
    ..episodeId = 3
    ..title = 'Futsutsuka na Oyako de wa Arimasu ga'
    ..episodeTitle = 'Episodio 4'
    ..progress = '742'
    ..totalProgress = '1420'
    ..date = DateTime.parse('2026-08-02T08:57:00.000')
    ..isNsfw = false
    ..watchState = WatchState.pending
    ..seriesFinished = false
    ..knownEpisodeCount = 12;

  test('la portada sobrevive al ida y vuelta', () {
    // Si esto falla, las tarjetas importadas quedan sin imagen.
    final v = CopiaSeguridad.idaYVueltaHistorial(muestra());
    expect(v.cover, muestra().cover);
  });

  test('la direccion vuelve IDENTICA', () {
    // Con lo que se reconoce el registro. Un solo caracter distinto y al
    // importar de nuevo se crea otro al lado en vez de actualizar el que hay.
    final v = CopiaSeguridad.idaYVueltaHistorial(muestra());
    expect(v.url, muestra().url);
    expect(v.package, muestra().package);
  });

  test('importar dos veces da la MISMA clave', () {
    // Lo que garantiza que no se dupliquen: package+url es como se busca el
    // registro existente.
    final una = CopiaSeguridad.idaYVueltaHistorial(muestra());
    final otra = CopiaSeguridad.idaYVueltaHistorial(una);
    expect(otra.url, una.url);
    expect(otra.package, una.package);
  });

  test('el resto del registro tambien vuelve entero', () {
    final o = muestra();
    final v = CopiaSeguridad.idaYVueltaHistorial(o);
    expect(v.title, o.title);
    expect(v.episodeTitle, o.episodeTitle);
    expect(v.progress, o.progress);
    expect(v.totalProgress, o.totalProgress);
    expect(v.episodeId, o.episodeId);
    expect(v.type, o.type);
    expect(v.isNsfw, o.isNsfw);
    expect(v.date, o.date);
    expect(v.knownEpisodeCount, o.knownEpisodeCount);
  });

  test('un favorito tambien vuelve entero, con su portada', () {
    final o = Favorite()
      ..package = 'io.prismhub.eporner'
      ..url = 'https://www.eporner.com/video-abc123/algo/'
      ..cover = 'https://static-eu-cdn.eporner.com/thumbs/static4/x/y.jpg'
      ..type = ExtensionType.bangumi
      ..title = 'Un titulo'
      ..date = DateTime.parse('2026-08-01T10:00:00.000')
      ..isNsfw = true;
    final v = CopiaSeguridad.idaYVueltaFavorito(o);
    expect(v.cover, o.cover);
    expect(v.url, o.url);
    expect(v.isNsfw, isTrue);
  });
}
