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
///   · Para anime tiene lo que hace falta y TMDB lleva mal: estado de emisión,
///     temporada, cantidad de episodios y los títulos en romaji Y en inglés.
///
/// Ese doble título no es un adorno: es lo que después permite ir a buscar la
/// obra a una fuente de reproducción, que casi nunca la nombra igual que el
/// catálogo. Ver [ObraDelCatalogo.tituloParaBuscar].
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

  String get _tipoAniList => tipo == TipoDeObra.anime ? 'ANIME' : 'MANGA';

  /// Los campos que se piden de cada obra.
  ///
  /// Se piden **solo los que se usan**. Cada campo de más es peso en la
  /// respuesta y trabajo del otro lado, y por acá pasan cuatro consultas en
  /// cada apertura del Home.
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
    episodes
    chapters
  ''';

  /// Una consulta con varias listas adentro.
  ///
  /// **Van todas en UN solo pedido**, con alias. AniList limita cuántas
  /// consultas por minuto se pueden hacer, y pedir cuatro filas por separado
  /// gastaba cuatro turnos para dibujar una pantalla. Con alias es uno.
  String _consultaDePortada() {
    String lista(String alias, String orden, {String extra = ''}) => '''
      $alias: Page(page: 1, perPage: 20) {
        media(type: $_tipoAniList, sort: $orden, isAdult: false$extra) {
          $_campos
        }
      }
    ''';

    return '''
      query {
        ${lista('tendencias', 'TRENDING_DESC')}
        ${lista('populares', 'POPULARITY_DESC')}
        ${lista('mejores', 'SCORE_DESC')}
        ${lista('nuevos', 'START_DATE_DESC', extra: ', status: RELEASING')}
      }
    ''';
  }

  @override
  Future<RespuestaDelCatalogo> portada() async {
    try {
      final datos = await _pedir(_consultaDePortada());
      if (datos == null) {
        return const RespuestaDelCatalogo.sinDatos(MotivoSinCatalogo.fuenteCaida);
      }
      final esAnime = tipo == TipoDeObra.anime;
      final secciones = <SeccionDelCatalogo>[
        _seccion(datos, 'tendencias', 'catalogo.tendencias'),
        _seccion(datos, 'populares', 'catalogo.populares'),
        _seccion(datos, 'mejores', 'catalogo.mejores'),
        _seccion(
          datos,
          'nuevos',
          esAnime ? 'catalogo.en-emision' : 'catalogo.en-publicacion',
        ),
      ].where((s) => s.obras.isNotEmpty).toList();

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

  SeccionDelCatalogo _seccion(
      Map<String, dynamic> datos, String alias, String titulo) {
    final lista = datos[alias]?['media'] as List<dynamic>? ?? const [];
    return SeccionDelCatalogo(
      titulo: titulo,
      obras: lista.map(_aObra).whereType<ObraDelCatalogo>().toList(),
    );
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
        // Si AniList tarda más que esto, mejor mostrar el aviso y dejar
        // reintentar que dejar la pantalla girando.
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
    );
    final cuerpo = res.data;
    if (cuerpo is! Map) return null;
    // GraphQL contesta 200 aunque haya fallado: el error va en el cuerpo. Sin
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

    // El principal es el que la gente reconoce. El inglés cuando está, y si no
    // el romaji: el nativo va último porque en japonés no le sirve a casi nadie
    // para reconocer la obra de un vistazo.
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
      generos: (crudo['genres'] as List?)?.whereType<String>().toList() ??
          const [],
      enEmision: crudo['status'] == 'RELEASING',
      episodios: (crudo['episodes'] ?? crudo['chapters']) as int?,
    );
  }

  /// La sinopsis viene con HTML aunque se pida `asHtml: false`: AniList deja
  /// pasar los `<br>` y algún `<i>` que el usuario escribió a mano.
  static String? _sinEtiquetas(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    final limpio = texto
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .trim();
    return limpio.isEmpty ? null : limpio;
  }
}
