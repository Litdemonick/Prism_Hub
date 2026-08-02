// Importar solo puede AGREGAR o ACTUALIZAR, nunca vaciar.
//
// Existe por un fallo visto en vivo: al importar sobre registros que ya
// estaban, las tarjetas de los dos inicios y los dos historiales se quedaron
// sin imagen. El archivo no traia nada malo — simplemente no traia portada, y
// como el registro se reemplaza ENTERO, el reemplazo se llevo puesta la que si
// habia.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/utils/copia_seguridad.dart';

void main() {
  History base() => History()
    ..package = 'io.prismhub.jkanime'
    ..url = 'https://jkanime.net/algo/'
    ..type = ExtensionType.bangumi
    ..episodeGroupId = 0
    ..episodeId = 1
    ..title = 'Algo'
    ..episodeTitle = ''
    ..progress = ''
    ..totalProgress = '';

  test('una copia sin portada no borra la que ya habia', () {
    final entra = base();
    final previo = base()..cover = 'https://cdn/x.jpg';
    CopiaSeguridad.conservarLoQueNoTraeDePrueba(entra, previo);
    expect(entra.cover, 'https://cdn/x.jpg');
  });

  test('si la copia TRAE portada, esa gana', () {
    // Actualizar sigue funcionando: lo que se evita es vaciar, no cambiar.
    final entra = base()..cover = 'https://cdn/nueva.jpg';
    final previo = base()..cover = 'https://cdn/vieja.jpg';
    CopiaSeguridad.conservarLoQueNoTraeDePrueba(entra, previo);
    expect(entra.cover, 'https://cdn/nueva.jpg');
  });

  test('tampoco se vacian los textos del episodio', () {
    final entra = base();
    final previo = base()
      ..episodeTitle = 'Episodio 7'
      ..totalProgress = '1420';
    CopiaSeguridad.conservarLoQueNoTraeDePrueba(entra, previo);
    expect(entra.episodeTitle, 'Episodio 7');
    expect(entra.totalProgress, '1420');
  });

  test('la cuenta de capitulos conocidos no vuelve a cero', () {
    // Cero significa "no se conto", no "hay cero": pisarla haria que el titulo
    // vuelva a anunciar como nuevo lo que ya se vio.
    final entra = base()..knownEpisodeCount = 0;
    final previo = base()..knownEpisodeCount = 12;
    CopiaSeguridad.conservarLoQueNoTraeDePrueba(entra, previo);
    expect(entra.knownEpisodeCount, 12);
  });

  test('una copia vieja no desmarca una obra terminada', () {
    // Eso lo marca el usuario a mano; una copia que no lo sabia no puede
    // deshacerlo.
    final entra = base()..seriesFinished = false;
    final previo = base()..seriesFinished = true;
    CopiaSeguridad.conservarLoQueNoTraeDePrueba(entra, previo);
    expect(entra.seriesFinished, isTrue);
  });
}
