import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/pages/extension/catalogo_del_repo.dart';

/// Cómo se lee el catálogo del repositorio y cómo se filtra.
///
/// ── Por qué esto tiene prueba ───────────────────────────────────────────
///
/// Porque acá adentro está la compuerta de las +18, y de todo lo que puede
/// fallar en esta app esa es la que peor se ve: una extensión adulta
/// apareciendo en una lista donde nadie la pidió. Estaba escrita dentro del
/// `build` de una pantalla, y al hacer la segunda pantalla habría quedado
/// copiada en dos sitios.
///
/// Y porque el catálogo no es un formato cerrado: las banderas llegan como
/// texto o como booleano según quién publicó la entrada, y la dirección del
/// guion cambió de nombre entre versiones. Eso no se ve leyendo el código —
/// se ve cuando una extensión no se instala y nadie sabe por qué.
void main() {
  Map<String, dynamic> entrada({
    String package = 'com.ejemplo',
    String name = 'Ejemplo',
    Object? nsfw,
    Object? unstable,
    String? script,
    String? url,
    String type = 'bangumi',
    String lang = 'es',
  }) =>
      {
        'package': package,
        'name': name,
        'version': '1.0.0',
        'lang': lang,
        'type': type,
        if (nsfw != null) 'nsfw': nsfw,
        if (unstable != null) 'unstable': unstable,
        if (script != null) 'script': script,
        if (url != null) 'url': url,
      };

  group('leer una entrada', () {
    test('las banderas valen como texto y como booleano', () {
      // El catálogo trae las dos formas segun quien publico la entrada.
      // Aceptar solo una dejaba extensiones adultas contadas como normales.
      expect(EntradaDelRepo.leer(entrada(nsfw: true))!.nsfw, isTrue);
      expect(EntradaDelRepo.leer(entrada(nsfw: 'true'))!.nsfw, isTrue);
      expect(EntradaDelRepo.leer(entrada(nsfw: false))!.nsfw, isFalse);
      expect(EntradaDelRepo.leer(entrada())!.nsfw, isFalse);
      expect(EntradaDelRepo.leer(entrada(unstable: 'true'))!.unstable, isTrue);
    });

    test('la dirección del guion sale de script o de url', () {
      // `script` es la de hoy; `url`, la de los repos viejos. Quedarse con
      // una sola deja al otro sin poder instalar nada.
      expect(EntradaDelRepo.leer(entrada(script: 'a.js'))!.url, 'a.js');
      expect(EntradaDelRepo.leer(entrada(url: 'b.js'))!.url, 'b.js');
      expect(
        EntradaDelRepo.leer(entrada(script: 'a.js', url: 'b.js'))!.url,
        'a.js',
        reason: 'con las dos, manda la nueva',
      );
      expect(EntradaDelRepo.leer(entrada())!.url, isNull);
    });

    test('una entrada incompleta se descarta en vez de romper', () {
      // Un catálogo a medio publicar no puede tirar abajo la pantalla.
      expect(EntradaDelRepo.leer(<String, dynamic>{}), isNull);
      expect(EntradaDelRepo.leer({'package': 'x'}), isNull);
      expect(EntradaDelRepo.leer('esto no es un mapa'), isNull);
      expect(EntradaDelRepo.leer(null), isNull);
    });

    test('un tipo que este app no conoce cae en vídeo, no revienta', () {
      expect(
        EntradaDelRepo.leer(entrada(type: 'algo_del_futuro'))!.type,
        ExtensionType.bangumi,
      );
    });

    test('leerTodas saltea las que no se pueden leer', () {
      final leidas = EntradaDelRepo.leerTodas([
        entrada(package: 'a'),
        <String, dynamic>{'package': 'incompleta'},
        entrada(package: 'b'),
      ]);
      expect(leidas.map((e) => e.package), ['a', 'b']);
    });
  });

  group('la compuerta de las +18', () {
    final catalogo = EntradaDelRepo.leerTodas([
      entrada(package: 'normal', name: 'Normal'),
      entrada(package: 'adulta', name: 'Adulta', nsfw: true),
    ]);

    bool nunca(String _) => false;

    test('sin el PIN de esta visita no salen, diga lo que diga el filtro', () {
      for (final filtro in ['all', 'sfw', 'nsfw']) {
        final salen = const FiltrosDelRepo(nsfwDesbloqueado: false)
            .aplicar(catalogo, esNueva: nunca)
            .map((e) => e.package);
        expect(salen, ['normal'], reason: 'con nsfw=$filtro');
      }
    });

    test('pedir el filtro +18 SIN el PIN no las muestra', () {
      // Es el caso que importa: el filtro es una ayuda para encontrar, la
      // compuerta es el PIN. Si esto se invirtiera, elegir «+18» en el menú
      // alcanzaría para verlas.
      final salen = const FiltrosDelRepo(nsfw: 'nsfw', nsfwDesbloqueado: false)
          .aplicar(catalogo, esNueva: nunca);
      expect(salen, isEmpty);
    });

    test('con el PIN dado, el filtro decide', () {
      List<String> con(String nsfw) =>
          FiltrosDelRepo(nsfw: nsfw, nsfwDesbloqueado: true)
              .aplicar(catalogo, esNueva: nunca)
              .map((e) => e.package)
              .toList();
      expect(con('all'), ['normal', 'adulta']);
      expect(con('sfw'), ['normal']);
      expect(con('nsfw'), ['adulta']);
    });
  });

  group('los demás filtros', () {
    final catalogo = EntradaDelRepo.leerTodas([
      entrada(package: 'a', name: 'Naruto Sub', lang: 'es'),
      entrada(package: 'b', name: 'Pelis HD', lang: 'en'),
      entrada(package: 'c', name: 'Rota', lang: 'es', unstable: true),
    ]);

    List<String> con(FiltrosDelRepo f, {bool Function(String)? esNueva}) =>
        f
            .aplicar(catalogo, esNueva: esNueva ?? (_) => false)
            .map((e) => e.package)
            .toList();

    test('sin filtros salen todas', () {
      expect(con(const FiltrosDelRepo()), ['a', 'b', 'c']);
    });

    test('el texto busca por nombre', () {
      expect(con(const FiltrosDelRepo(texto: 'naruto')), ['a']);
      expect(con(const FiltrosDelRepo(texto: 'rota')), ['c']);
      expect(con(const FiltrosDelRepo(texto: 'no existe')), isEmpty);
    });

    test('escribir un tipo trae todas las de ese tipo, no solo las que se '
        'llaman así', () {
      // A propósito, y fácil de romper si alguien lo lee como un fallo:
      // escribir «pelis» o «anime» en el buscador filtra por TIPO, para no
      // tener que ir al selector aparte. Las tres del catálogo de prueba son
      // de vídeo, así que salen las tres aunque ninguna se llame así.
      expect(con(const FiltrosDelRepo(texto: 'pelis')), ['a', 'b', 'c']);
    });

    test('el idioma filtra', () {
      expect(con(const FiltrosDelRepo(idioma: 'en')), ['b']);
    });

    test('el nivel separa estables de rotas', () {
      expect(con(const FiltrosDelRepo(nivel: 'unstable')), ['c']);
      expect(con(const FiltrosDelRepo(nivel: 'stable')), ['a', 'b']);
    });

    test('«nuevas» lo contesta quien guarda la lista, no los datos', () {
      // El catálogo no trae fecha de publicación: «nueva» es «no estaba la
      // última vez que se abrió el repositorio», y eso solo lo sabe el
      // controlador. Por eso entra como función y no como campo.
      expect(
        con(const FiltrosDelRepo(instalacion: 'new'),
            esNueva: (p) => p == 'b'),
        ['b'],
      );
    });

    test('los filtros se combinan', () {
      expect(
        con(const FiltrosDelRepo(idioma: 'es', nivel: 'stable')),
        ['a'],
      );
    });
  });
}
