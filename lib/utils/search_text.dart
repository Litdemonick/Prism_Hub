// Utilidad compartida por TODAS las zonas de búsqueda del app (búsqueda
// general, dentro de una extensión, Instaladas, Repositorio, Historial,
// Favoritos, vincular TMDB/Anilist) — antes cada una comparaba texto a su
// manera (`.toLowerCase().contains()` suelto) sin tolerar tildes ni orden
// de palabras distinto, y lo que se mandaba a cada extensión/API iba sin
// ninguna limpieza.
class SearchText {
  SearchText._();

  // Tabla chica propia (alcance es/pt/fr) en vez de sumar un paquete nuevo
  // (`diacritic`, etc.) solo para esto — no hace falta cobertura Unicode
  // completa, el contenido de la app es mayormente en español.
  static const Map<String, String> _accentMap = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };

  // RegExp compilados UNA sola vez (campos estáticos) en vez de construirlos
  // de nuevo en cada llamada a normalize()/sanitizeForRemoteQuery() — estas
  // corren dentro de loops de filtrado (una vez por título en Historial/
  // Favoritos/resultados de búsqueda), así que recompilar el patrón en cada
  // pasada es trabajo repetido de sobra. Los patrones son siempre FIJOS
  // (nunca se arman a partir del texto del usuario), así que tampoco hay
  // riesgo de ReDoS.
  static final RegExp _nonAlnumPattern = RegExp(r'[^a-z0-9\s]');
  static final RegExp _extraSpacesPattern = RegExp(r'\s+');
  static final RegExp _remoteSymbolsPattern = RegExp(r'[<>{}\[\]|^`]');

  static String _stripAccents(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_accentMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  // Normalización AGRESIVA — solo para comparar LOCALMENTE (nunca para lo
  // que se manda a una extensión/API, ahí sí importan mayúsculas/tildes).
  // minúsculas + sin tildes + solo letras/números/espacios + espacios
  // colapsados/trim.
  static String normalize(String input) {
    final lower = _stripAccents(input.toLowerCase());
    final cleaned = lower.replaceAll(_nonAlnumPattern, ' ');
    return cleaned.replaceAll(_extraSpacesPattern, ' ').trim();
  }

  static List<String> _tokens(String normalized) =>
      normalized.isEmpty ? const [] : normalized.split(' ');

  // Tokeniza la búsqueda UNA sola vez — para filtrar una lista de N
  // títulos, conviene llamar esto una vez afuera del loop y pasarle el
  // resultado a matchesTokens() por cada título, en vez de renormalizar la
  // MISMA palabra buscada N veces (que es lo que hacía matchesQuery() antes
  // si se llamaba dentro de un .where()/.sort()).
  static List<String> queryTokens(String query) => _tokens(normalize(query));

  // Sin importar el orden de las palabras ("ritmo cardiaco" == "cardiaco
  // ritmo"), tildes, mayúsculas o símbolos sueltos (">", etc) — cada token
  // de la búsqueda (ya tokenizado, ver queryTokens) tiene que aparecer en
  // algún lado del título. Tokens vacíos matchean cualquier título.
  static bool matchesTokens(String title, List<String> queryTokens) {
    if (queryTokens.isEmpty) return true;
    final normalizedTitle = normalize(title);
    return queryTokens.every(normalizedTitle.contains);
  }

  // Conveniencia para comparar UN solo título contra una query cruda (no
  // hay loop involucrado) — para filtrar una LISTA, preferir
  // queryTokens()+matchesTokens() para no renormalizar la query por cada
  // ítem.
  static bool matchesQuery(String title, String query) =>
      matchesTokens(title, queryTokens(query));

  // Sanitización LIVIANA — esto SÍ se manda a una extensión/API remota
  // (mantiene mayúsculas/tildes, el destino puede necesitarlas para su
  // propio matching). Solo saca símbolos sueltos que no aportan nada a una
  // búsqueda de texto y espacios de sobra. OJO: esto no reemplaza el
  // escape real de seguridad — eso lo sigue haciendo jsonEncode() en
  // ExtensionService.search() antes de insertar el string en el JS que se
  // evalúa; esto es una limpieza adicional, no el mecanismo de seguridad.
  static String sanitizeForRemoteQuery(String raw) {
    final noSymbols = raw.replaceAll(_remoteSymbolsPattern, ' ');
    return noSymbols.replaceAll(_extraSpacesPattern, ' ').trim();
  }

  // Prefijos de la query, del más largo (completo) al más corto (una sola
  // palabra) — para reintentar una búsqueda remota que no encontró nada.
  // Cada extensión hace su propio matching en el sitio real (fuera de
  // nuestro control): algunas exigen que el título empiece exactamente con
  // lo escrito, así que agregar más palabras a una búsqueda que ya
  // encontraba algo puede tirar la búsqueda a cero si el título real tiene
  // texto ANTES (ej. "The Movie: Boku no Kokoro..." buscando "boku no
  // kokoro"). Reintentar con menos palabras (sacando de a una desde el
  // final) da más chances de encontrar el título real sin perder lo que ya
  // encontraba una query más corta.
  static List<String> broadenedRemoteQueries(String sanitizedQuery) {
    final tokens = sanitizedQuery
        .trim()
        .split(_extraSpacesPattern)
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length <= 1) return [sanitizedQuery];
    return [
      for (var end = tokens.length; end >= 1; end--)
        tokens.sublist(0, end).join(' '),
    ];
  }

  // Sinónimos de categoría — le permite al Repositorio de extensiones
  // entender "anime"/"manga"/etc como un filtro de TIPO, no solo un
  // nombre literal a buscar. Los sets que devuelve son los mismos
  // ExtensionUtils.videoTypes/readingTypes que ya usan los chips de
  // filtro "Tipo", así que "video"/"lectura" quedan siempre consistentes
  // en un solo lugar (ver ExtensionUtils).
  static const Set<String> _videoSynonyms = {
    'video',
    'anime',
    'animes',
    'serie',
    'series',
    'pelicula',
    'peliculas',
    'peli',
    'pelis',
    'movie',
    'movies',
  };
  static const Set<String> _readingSynonyms = {
    'lectura',
    'manga',
    'mangas',
    'manhwa',
    'manhwas',
    'manhua',
    'manhuas',
    'novela',
    'novelas',
    'comic',
    'comics',
  };

  // Devuelve null si ningún token de la búsqueda coincide con una
  // categoría conocida (o si aparecen sinónimos de AMBAS categorías a la
  // vez — ambiguo, mejor no filtrar por tipo en ese caso).
  static Set<T>? inferTypeFromQuery<T>(
    String query,
    Set<T> videoTypes,
    Set<T> readingTypes,
  ) {
    final tokens = _tokens(normalize(query));
    if (tokens.isEmpty) return null;
    final hasVideo = tokens.any(_videoSynonyms.contains);
    final hasReading = tokens.any(_readingSynonyms.contains);
    if (hasVideo && !hasReading) return videoTypes;
    if (hasReading && !hasVideo) return readingTypes;
    return null;
  }
}
