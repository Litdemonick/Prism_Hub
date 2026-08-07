/// Qué tipo de obra es, para el catálogo.
///
/// Es a propósito más chico que el tipo de las extensiones: acá solo importa
/// cómo se muestra y de qué fuente sale, no cómo se reproduce.
enum TipoDeObra { anime, serie, pelicula, manga }

/// De dónde salió la ficha.
///
/// Se guarda con el ítem porque el `id` **solo tiene sentido dentro de su
/// fuente**: el 21 de AniList y el 21 de TMDB no son la misma obra. Sin esto,
/// mezclar dos fuentes en la misma pantalla es un error esperando pasar.
enum FuenteDeMetadatos { anilist, tmdb }

/// Una obra del catálogo, ya normalizada.
///
/// Las fuentes devuelven formas muy distintas —AniList es GraphQL con títulos
/// en tres idiomas, TMDB es REST con rutas de imagen relativas— y la pantalla
/// no tiene por qué saber nada de eso. Cada proveedor traduce lo suyo a esto.
///
/// **Todo es opcional menos el título y la identidad.** Una fuente puede no
/// traer año, o puntaje, o portada, y eso no puede romper una fila entera: la
/// tarjeta simplemente muestra menos.
class ObraDelCatalogo {
  const ObraDelCatalogo({
    required this.id,
    required this.fuente,
    required this.tipo,
    required this.titulo,
    this.tituloAlternativo,
    this.portada,
    this.fondo,
    this.sinopsis,
    this.anio,
    this.puntaje,
    this.generos = const [],
    this.enEmision = false,
    this.episodios,
  });

  /// El identificador **dentro de su fuente**. Ver [FuenteDeMetadatos].
  final String id;
  final FuenteDeMetadatos fuente;
  final TipoDeObra tipo;

  final String titulo;

  /// El otro título con el que se la conoce (romaji vs inglés, o el original).
  ///
  /// Sirve para dos cosas: mostrarlo debajo del principal, y —más importante—
  /// **buscar la obra en las fuentes de reproducción**, que casi nunca usan el
  /// mismo nombre que el catálogo.
  final String? tituloAlternativo;

  final String? portada;
  final String? fondo;
  final String? sinopsis;
  final int? anio;

  /// De 0 a 100, venga como venga en la fuente.
  ///
  /// AniList lo da así; TMDB lo da de 0 a 10 con decimales. Se normaliza en el
  /// proveedor para que la tarjeta no tenga que preguntarse de dónde salió.
  final int? puntaje;

  final List<String> generos;
  final bool enEmision;

  /// Cuántos episodios o capítulos tiene, si la fuente lo sabe.
  final int? episodios;

  /// Clave estable para listas y para no repetir la misma obra dos veces.
  String get clave => '${fuente.name}:${tipo.name}:$id';

  /// El mejor texto para ir a buscarla a una fuente de reproducción.
  ///
  /// Se prefiere el alternativo cuando el principal está en un alfabeto que los
  /// sitios no usan: casi ninguno indexa por el título en japonés.
  String get tituloParaBuscar {
    final alt = tituloAlternativo;
    if (alt == null || alt.isEmpty) return titulo;
    return _pareceLatino(titulo) ? titulo : alt;
  }

  static bool _pareceLatino(String s) {
    for (final c in s.runes) {
      // Más allá del latín extendido ya es otro alfabeto (japonés, coreano,
      // chino, cirílico). Con que haya UNO alcanza para no usarlo al buscar.
      if (c > 0x024F) return false;
    }
    return true;
  }
}

/// Una fila del Home: un título y sus obras.
class SeccionDelCatalogo {
  const SeccionDelCatalogo({
    required this.titulo,
    required this.obras,
  });

  final String titulo;
  final List<ObraDelCatalogo> obras;
}
