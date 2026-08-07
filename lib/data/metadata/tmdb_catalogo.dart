import 'package:dio/dio.dart';
import 'package:prismhub/data/metadata/metadata_item.dart';
import 'package:prismhub/data/metadata/metadata_source.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';

/// El catálogo de series y películas, sacado de TMDB.
///
/// ── Lo que hay que saber antes de tocar esto ──────────────────────────────
///
/// **Pide una clave, y viene vacía de fábrica** (`SettingKey.tmdbKey`). Hasta
/// hoy TMDB solo enriquecía una ficha que ya existía, así que sin clave no se
/// notaba. Acá sí: si estas dos zonas dependen de TMDB y no hay clave, quedan
/// en blanco.
///
/// Por eso [lista] existe y por eso la respuesta viaja con su motivo: la
/// pantalla tiene que poder decir «te falta la clave» —que se arregla en
/// Ajustes— en vez de «no hay nada», que no lleva a ningún lado.
///
/// **Para mangas no sirve**: TMDB es cine y televisión. Esa zona va por
/// AniList (ver [CatalogoAniList]).
class CatalogoTMDB implements FuenteDeCatalogo {
  CatalogoTMDB(this.tipo)
      : assert(tipo == TipoDeObra.serie || tipo == TipoDeObra.pelicula,
            'TMDB solo sirve series y películas');

  @override
  final TipoDeObra tipo;

  static const _base = 'https://api.themoviedb.org/3';

  /// El tamaño de portada. `w500` y no el original a propósito: el original
  /// puede pesar varios megas por imagen y acá se muestran decenas en una
  /// grilla. A este ancho la tarjeta ya se ve nítida.
  static const _imagenes = 'https://image.tmdb.org/t/p/w500';
  static const _fondos = 'https://image.tmdb.org/t/p/w780';

  static String get _clave =>
      PrismHubStorage.getSetting(SettingKey.tmdbKey)?.toString() ?? '';

  @override
  bool get lista => _clave.isNotEmpty;

  bool get _esSerie => tipo == TipoDeObra.serie;

  /// Las filas de cada zona: nombre de la fila y ruta de TMDB.
  ///
  /// El orden importa: arriba va lo que más invita a entrar —lo que está
  /// sonando esta semana— y las listas que casi no cambian van más abajo.
  List<(String, String)> get _filas => _esSerie
      ? const [
          ('catalogo.esta-semana', '/trending/tv/week'),
          ('catalogo.populares', '/tv/popular'),
          ('catalogo.al-aire', '/tv/on_the_air'),
          ('catalogo.mejores', '/tv/top_rated'),
        ]
      : const [
          ('catalogo.esta-semana', '/trending/movie/week'),
          ('catalogo.en-cartel', '/movie/now_playing'),
          ('catalogo.populares', '/movie/popular'),
          ('catalogo.mejores', '/movie/top_rated'),
          ('catalogo.proximamente', '/movie/upcoming'),
        ];

  @override
  Future<RespuestaDelCatalogo> portada() async {
    if (!lista) {
      return const RespuestaDelCatalogo.sinDatos(
        MotivoSinCatalogo.faltaLaClave,
        detalle: 'TMDB sin clave configurada',
      );
    }
    try {
      // Estas SÍ van en paralelo, al revés que AniList.
      //
      // TMDB es REST: no hay forma de pedir cuatro listas en una sola
      // consulta, y su límite de peticiones es holgado. En serie serían cuatro
      // idas y vueltas encadenadas — con 300 ms cada una, más de un segundo
      // mirando una pantalla vacía.
      final respuestas = await Future.wait(
        _filas.map((f) => _pedir(f.$2)),
        eagerError: false,
      );

      final secciones = <SeccionDelCatalogo>[];
      // Una película puede estar en «esta semana» y también en «populares».
      // Repetida en la misma pantalla queda pobre: se muestra en la primera.
      final yaMostradas = <String>{};
      for (var i = 0; i < _filas.length; i++) {
        final lista = respuestas[i];
        if (lista == null) continue;
        final obras = <ObraDelCatalogo>[];
        for (final crudo in lista) {
          final obra = _aObra(crudo);
          if (obra == null) continue;
          if (!yaMostradas.add(obra.clave)) continue;
          obras.add(obra);
        }
        if (obras.length >= 4) {
          secciones.add(
              SeccionDelCatalogo(titulo: _filas[i].$1, obras: obras));
        }
      }

      if (secciones.isEmpty) {
        return const RespuestaDelCatalogo.sinDatos(
          MotivoSinCatalogo.fuenteCaida,
          detalle: 'TMDB no devolvió ninguna obra',
        );
      }
      return RespuestaDelCatalogo.ok(secciones);
    } catch (e) {
      logger.info('[catálogo] TMDB (${tipo.name}) falló: $e');
      return RespuestaDelCatalogo.sinDatos(
        MotivoSinCatalogo.fuenteCaida,
        detalle: e.toString(),
      );
    }
  }

  @override
  Future<List<ObraDelCatalogo>> buscar(String texto, {int pagina = 1}) async {
    if (!lista || texto.trim().isEmpty) return const [];
    final ruta = _esSerie ? '/search/tv' : '/search/movie';
    final lista_ = await _pedir(ruta, extra: {
      'query': texto.trim(),
      'page': pagina,
    });
    return (lista_ ?? const [])
        .map(_aObra)
        .whereType<ObraDelCatalogo>()
        .toList();
  }

  /// Pide una ruta y devuelve su lista de resultados, o null si falló.
  ///
  /// Devuelve null en vez de tirar: una fila que falla **no puede llevarse
  /// puesta la pantalla entera**. Las otras tres se muestran igual.
  Future<List<dynamic>?> _pedir(
    String ruta, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final res = await dio.get<dynamic>(
        '$_base$ruta',
        queryParameters: {
          'api_key': _clave,
          // En español, que es el idioma de la app. TMDB devuelve el título y
          // la sinopsis traducidos cuando los tiene.
          'language': 'es-ES',
          ...extra,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      final cuerpo = res.data;
      if (cuerpo is! Map) return null;
      return cuerpo['results'] as List<dynamic>?;
    } catch (e) {
      logger.info('[catálogo] TMDB $ruta falló: $e');
      return null;
    }
  }

  ObraDelCatalogo? _aObra(dynamic crudo) {
    if (crudo is! Map) return null;
    final id = crudo['id'];
    if (id == null) return null;

    // Series y películas no usan el mismo campo para lo mismo: `name` contra
    // `title`, `first_air_date` contra `release_date`. Se miran los dos porque
    // /trending puede mezclar tipos.
    final titulo = ((crudo['name'] ?? crudo['title']) as String?)?.trim();
    if (titulo == null || titulo.isEmpty) return null;
    final original =
        ((crudo['original_name'] ?? crudo['original_title']) as String?)
            ?.trim();

    final fecha =
        (crudo['first_air_date'] ?? crudo['release_date']) as String?;
    final anio = (fecha != null && fecha.length >= 4)
        ? int.tryParse(fecha.substring(0, 4))
        : null;

    final poster = crudo['poster_path'] as String?;
    final fondo = crudo['backdrop_path'] as String?;

    // TMDB puntúa de 0 a 10 con decimales; ObraDelCatalogo guarda de 0 a 100.
    // Se normaliza acá para que la tarjeta no tenga que saber de dónde salió.
    final voto = crudo['vote_average'];
    final puntaje = voto is num ? (voto * 10).round().clamp(0, 100) : null;

    final sinopsis = (crudo['overview'] as String?)?.trim();

    return ObraDelCatalogo(
      id: id.toString(),
      fuente: FuenteDeMetadatos.tmdb,
      tipo: tipo,
      titulo: titulo,
      tituloAlternativo:
          (original != null && original.isNotEmpty && original != titulo)
              ? original
              : null,
      portada: poster == null ? null : '$_imagenes$poster',
      fondo: fondo == null ? null : '$_fondos$fondo',
      // Vacía cuando TMDB no tiene la traducción: mejor sin sinopsis que con
      // una cadena vacía que después se dibuja como un hueco.
      sinopsis: (sinopsis == null || sinopsis.isEmpty) ? null : sinopsis,
      anio: anio,
      puntaje: puntaje,
      enEmision: false,
    );
  }
}
