import 'package:dio/dio.dart';
import 'package:prismhub/data/metadata/metadata_item.dart';
import 'package:prismhub/data/metadata/metadata_source.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/request.dart';

/// El catálogo de anime y mangas, sacado de AniList.
///
/// ── Por qué AniList y no TMDB ─────────────────────────────────────────────
///
///   · **No pide clave.** Su API pública contesta sin registro, así que estas
///     dos zonas traen contenido desde el primer arranque sin que el usuario
///     configure nada. TMDB pide una clave que viene vacía de fábrica.
///   · **Para mangas TMDB no sirve**: es cine y televisión, ahí no los hay.
///   · Para anime tiene lo que hace falta y TMDB lleva mal: temporada, estado
///     de emisión, cantidad de episodios y los títulos en romaji Y en inglés.
///
/// Ese doble título no es un adorno: es lo que después permite ir a buscar la
/// obra a una fuente de reproducción, que casi nunca la nombra igual que el
/// catálogo. Ver [ObraDelCatalogo.tituloParaBuscar].
///
/// ── El +18 queda afuera, siempre ──────────────────────────────────────────
///
/// Todas las consultas llevan `isAdult: false`. Una portada de hentai
/// apareciendo en "Populares" porque una consulta se olvidó el filtro es el
/// tipo de error que no se perdona, así que va en TODAS y no en algunas. Si
/// algún día la Zona +18 usa AniList, va a ser con su propia instancia y
/// adentro de esa zona, nunca acá.
class CatalogoAniList implements FuenteDeCatalogo {
  CatalogoAniList(this.tipo)
      : assert(tipo == TipoDeObra.anime || tipo == TipoDeObra.manga,
            'AniList solo sirve anime y mangas');

  @override
  final TipoDeObra tipo;

  /// Siempre lista: no hay clave que configurar.
  @override
  bool get lista => true;

  static const _url = 'https://graphql.anilist.co';

  bool get _esAnime => tipo == TipoDeObra.anime;
  String get _tipoAniList => _esAnime ? 'ANIME' : 'MANGA';

  /// Los campos que se piden de cada obra.
  ///
  /// **Solo los que se usan.** Cada campo de más es peso en la respuesta y
  /// trabajo del otro lado, y por acá pasan seis listas en cada apertura.
  static const _campos = '''
    id
    title { romaji english native }
    coverImage { large }
    bannerImage
    description(asHtml: false)
    startDate { year }
    averageScore
    genres
    status
    format
    episodes
    chapters
  ''';

  /// La temporada de anime que corre ahora, y el año.
  ///
  /// AniList parte el año en cuatro: invierno empieza en diciembre, no en
  /// enero. Por eso diciembre pertenece al invierno del año SIGUIENTE — sin
  /// esa corrección, todo diciembre la fila de "esta temporada" mostraría la
  /// que ya terminó.
  static (String, int) _temporadaActual([DateTime? ahora]) {
    final d = ahora ?? DateTime.now();
    return switch (d.month) {
      12 => ('WINTER', d.year + 1),
      1 || 2 => ('WINTER', d.year),
      3 || 4 || 5 => ('SPRING', d.year),
      6 || 7 || 8 => ('SUMMER', d.year),
      _ => ('FALL', d.year),
    };
  }

  /// La temporada que viene, para la fila de "lo que se estrena".
  static (String, int) _temporadaSiguiente() {
    final (t, a) = _temporadaActual();
    return switch (t) {
      'WINTER' => ('SPRING', a),
      'SPRING' => ('SUMMER', a),
      'SUMMER' => ('FALL', a),
      _ => ('WINTER', a + 1),
    };
  }

  /// Todas las filas en UN solo pedido, con alias.
  ///
  /// AniList limita cuántas consultas por minuto se aceptan. Pedir seis filas
  /// por separado gastaba seis turnos para dibujar una pantalla, y con dos
  /// zonas abiertas se llegaba al tope enseguida. Con alias es uno.
  String _consultaDePortada() {
    String lista(String alias, String orden, {String extra = ''}) => '''
      $alias: Page(page: 1, perPage: 24) {
        media(type: $_tipoAniList, sort: $orden, isAdult: false$extra) {
          $_campos
        }
      }
    ''';

    if (_esAnime) {
      final (temp, anio) = _temporadaActual();
      final (tempSig, anioSig) = _temporadaSiguiente();
      return '''
        query {
          ${lista('descubre', 'TRENDING_DESC')}
          ${lista('temporada', 'POPULARITY_DESC', extra: ', season: $temp, seasonYear: $anio')}
          ${lista('emision', 'POPULARITY_DESC', extra: ', status: RELEASING')}
          ${lista('populares', 'POPULARITY_DESC')}
          ${lista('mejores', 'SCORE_DESC')}
          ${lista('proxima', 'POPULARITY_DESC', extra: ', season: $tempSig, seasonYear: $anioSig')}
        }
      ''';
    }
    // Mangas: no hay temporadas, pero sí dos cortes que valen la pena y que
    // el usuario pidió por nombre — manhwas y novelas ligeras.
    return '''
      query {
        ${lista('descubre', 'TRENDING_DESC')}
        ${lista('publicacion', 'POPULARITY_DESC', extra: ', status: RELEASING')}
        ${lista('populares', 'POPULARITY_DESC')}
        ${lista('mejores', 'SCORE_DESC')}
        ${lista('manhwas', 'POPULARITY_DESC', extra: ', countryOfOrigin: "KR"')}
        ${lista('novelas', 'POPULARITY_DESC', extra: ', format: NOVEL')}
      }
    ''';
  }

  /// Cómo se llama cada fila y en qué orden salen.
  ///
  /// El orden importa: lo primero que se ve tiene que ser lo que más invita a
  /// entrar. Por eso "Descubre" (lo que está pegando ahora) va arriba y
  /// "Populares de siempre" —que es lo mismo todos los meses— va más abajo.
  List<(String, String)> get _filas => _esAnime
      ? const [
          ('descubre', 'catalogo.descubre'),
          ('temporada', 'catalogo.esta-temporada'),
          ('emision', 'catalogo.en-emision'),
          ('populares', 'catalogo.populares'),
          ('mejores', 'catalogo.mejores'),
          ('proxima', 'catalogo.proxima-temporada'),
        ]
      : const [
          ('descubre', 'catalogo.descubre'),
          ('publicacion', 'catalogo.en-publicacion'),
          ('populares', 'catalogo.populares'),
          ('mejores', 'catalogo.mejores'),
          ('manhwas', 'catalogo.manhwas'),
          ('novelas', 'catalogo.novelas'),
        ];

  @override
  Future<RespuestaDelCatalogo> portada() async {
    try {
      final datos = await _pedir(_consultaDePortada());
      if (datos == null) {
        return const RespuestaDelCatalogo.sinDatos(
            MotivoSinCatalogo.fuenteCaida);
      }
      final secciones = <SeccionDelCatalogo>[];
      // Una obra puede caer en varias filas (lo que está de moda suele ser
      // también popular). Repetida en la misma pantalla queda pobre, así que
      // solo se muestra en la PRIMERA fila donde aparece.
      final yaMostradas = <String>{};
      for (final (alias, titulo) in _filas) {
        final lista = datos[alias]?['media'] as List<dynamic>? ?? const [];
        final obras = <ObraDelCatalogo>[];
        for (final crudo in lista) {
          final obra = _aObra(crudo);
          if (obra == null) continue;
          if (!yaMostradas.add(obra.clave)) continue;
          obras.add(obra);
        }
        // Una fila con dos cosas se ve peor que no tenerla.
        if (obras.length >= 4) {
          secciones.add(SeccionDelCatalogo(titulo: titulo, obras: obras));
        }
      }

      if (secciones.isEmpty) {
        return const RespuestaDelCatalogo.sinDatos(
          MotivoSinCatalogo.fuenteCaida,
          detalle: 'AniList contestó, pero sin ninguna obra',
        );
      }
      return RespuestaDelCatalogo.ok(secciones);
    } catch (e) {
      logger.info('[catálogo] AniList ($_tipoAniList) falló: $e');
      return RespuestaDelCatalogo.sinDatos(
        MotivoSinCatalogo.fuenteCaida,
        detalle: e.toString(),
      );
    }
  }

  @override
  Future<List<ObraDelCatalogo>> buscar(String texto, {int pagina = 1}) async {
    if (texto.trim().isEmpty) return const [];
    final consulta = '''
      query (\$busqueda: String, \$pagina: Int) {
        Page(page: \$pagina, perPage: 30) {
          media(type: $_tipoAniList, search: \$busqueda, isAdult: false) {
            $_campos
          }
        }
      }
    ''';
    try {
      final datos = await _pedir(consulta, variables: {
        'busqueda': texto.trim(),
        'pagina': pagina,
      });
      final lista = datos?['Page']?['media'] as List<dynamic>? ?? const [];
      return lista.map(_aObra).whereType<ObraDelCatalogo>().toList();
    } catch (e) {
      logger.info('[catálogo] búsqueda en AniList falló: $e');
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _pedir(
    String consulta, {
    Map<String, dynamic>? variables,
  }) async {
    final res = await dio.post<dynamic>(
      _url,
      data: {'query': consulta, if (variables != null) 'variables': variables},
      options: Options(
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        // Corto a propósito: esto dibuja una pantalla, no descarga un vídeo.
        // Si AniList tarda más, mejor mostrar el aviso y dejar reintentar que
        // dejar la pantalla girando.
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
    );
    final cuerpo = res.data;
    if (cuerpo is! Map) return null;
    // GraphQL contesta 200 aunque haya fallado: el error va en el CUERPO. Sin
    // mirar esto, un fallo se veía como "no hay contenido".
    final errores = cuerpo['errors'];
    if (errores is List && errores.isNotEmpty) {
      logger.info('[catálogo] AniList devolvió errores: $errores');
      return null;
    }
    final datos = cuerpo['data'];
    return datos is Map<String, dynamic> ? datos : null;
  }

  ObraDelCatalogo? _aObra(dynamic crudo) {
    if (crudo is! Map) return null;
    final id = crudo['id'];
    if (id == null) return null;

    final titulos = crudo['title'] as Map? ?? const {};
    final romaji = (titulos['romaji'] as String?)?.trim();
    final ingles = (titulos['english'] as String?)?.trim();
    final nativo = (titulos['native'] as String?)?.trim();

    // El principal es el que la gente reconoce: el inglés cuando está y si no
    // el romaji. El nativo va último porque en japonés no le sirve a casi
    // nadie para reconocer la obra de un vistazo.
    final principal = (ingles?.isNotEmpty == true ? ingles : null) ??
        (romaji?.isNotEmpty == true ? romaji : null) ??
        (nativo?.isNotEmpty == true ? nativo : null);
    if (principal == null) return null;

    final alternativo = principal == romaji ? ingles : romaji;

    return ObraDelCatalogo(
      id: id.toString(),
      fuente: FuenteDeMetadatos.anilist,
      tipo: tipo,
      titulo: principal,
      tituloAlternativo:
          (alternativo?.isNotEmpty == true && alternativo != principal)
              ? alternativo
              : null,
      portada: (crudo['coverImage'] as Map?)?['large'] as String?,
      fondo: crudo['bannerImage'] as String?,
      sinopsis: _sinEtiquetas(crudo['description'] as String?),
      anio: (crudo['startDate'] as Map?)?['year'] as int?,
      // Ya viene de 0 a 100, que es como lo guarda ObraDelCatalogo.
      puntaje: crudo['averageScore'] as int?,
      generos:
          (crudo['genres'] as List?)?.whereType<String>().toList() ?? const [],
      enEmision: crudo['status'] == 'RELEASING',
      episodios: (crudo['episodes'] ?? crudo['chapters']) as int?,
    );
  }

  /// La sinopsis viene con HTML aunque se pida `asHtml: false`: AniList deja
  /// pasar los `<br>` y algún `<i>` que alguien escribió a mano.
  static String? _sinEtiquetas(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    final limpio = texto
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&mdash;', '—')
        .trim();
    return limpio.isEmpty ? null : limpio;
  }
}
