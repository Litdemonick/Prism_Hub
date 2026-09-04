import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/models/favorite.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/models/import_result.dart';
import 'package:prismhub/utils/extension.dart';

class ImportService {
  static const int maxLinks = 500;
  // Maximum file size is 2MB to prevent parsing humongous files.
  static const int maxFileSize = 2 * 1024 * 1024;

  static Future<ImportResult> importFromFile({
    required void Function(int current, int total) onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return _emptyResult();
    }

    final file = File(result.files.single.path!);
    final size = await file.length();
    if (size > maxFileSize) {
      throw Exception('file-too-large');
    }

    final bytes = await file.readAsBytes();
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    return importFromText(text: content, onProgress: onProgress);
  }

  static Future<ImportResult> importFromText({
    required String text,
    required void Function(int current, int total) onProgress,
  }) async {
    if (text.trim().isEmpty) return _emptyResult();

    final urls = extractUrls(text);
    if (urls.isEmpty) return _emptyResult();

    final limitReached = urls.length > maxLinks;
    final toProcess = limitReached ? urls.take(maxLinks).toList() : urls;

    int current = 0;
    int imported = 0;
    int duplicates = 0;
    int nsfw = 0;
    int errors = 0;
    final Map<String, int> byExtension = {};
    final List<ImportError> errorList = [];

    final repoIndex = await ExtensionUtils.fetchRepoIndex();

    // Procesa en lotes para no saturar
    const batchSize = 5;
    for (var i = 0; i < toProcess.length; i += batchSize) {
      final batch = toProcess.skip(i).take(batchSize).toList();

      await Future.wait(batch.map((url) async {
        try {
          final res = await _processSingleUrl(url, repoIndex);
          if (res.imported) {
            imported++;
            if (res.nsfw) nsfw++;
            final name = res.extensionName ?? 'Desconocida';
            byExtension[name] = (byExtension[name] ?? 0) + 1;
          } else if (res.duplicate) {
            duplicates++;
          }
        } catch (e) {
          errors++;
          errorList.add(ImportError(url: url, reason: e.toString()));
        } finally {
          current++;
          onProgress(current, toProcess.length);
        }
      }));
      // Rate limiting: pequeña pausa entre lotes.
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return ImportResult(
      totalProcessed: toProcess.length,
      totalImported: imported,
      totalDuplicates: duplicates,
      totalNsfw: nsfw,
      totalErrors: errors,
      totalSkipped: urls.length - toProcess.length, // O las descartadas
      importedByExtension: byExtension,
      errors: errorList,
      elapsed: Duration.zero, // TODO: Measure time
      limitReached: limitReached,
    );
  }

  static List<String> extractUrls(String text) {
    // 1. Sanitización básica
    var safeText = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    safeText = safeText.replaceAll(RegExp(r'(UNION SELECT|DROP TABLE|--;|/\*)', caseSensitive: false), '');
    safeText = safeText.replaceAll(RegExp(r'\.\./'), '');

    // 2. Extraer URLs (http:// o https://)
    final urlRegex = RegExp(r'https?://[^\s<>"\[\]()]+|www\.[^\s<>"\[\]()]+');
    final matches = urlRegex.allMatches(safeText);
    
    final result = <String>{}; // Set para deduplicar
    for (final match in matches) {
      var url = match.group(0)!;
      // Normalizar
      if (url.startsWith('www.')) url = 'https://$url';
      url = url.trim();
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);
      
      // Descartar basura (redes sociales y páginas comunes que no son mangas)
      final lowerUrl = url.toLowerCase();
      if (lowerUrl.contains('google.com/search') ||
          lowerUrl.contains('facebook.com') ||
          lowerUrl.contains('twitter.com') ||
          lowerUrl.contains('discord.gg') ||
          lowerUrl.contains('t.me') ||
          lowerUrl.contains('youtube.com') ||
          url.length > 2048) {
        continue;
      }

      // Descartar rutas que sabemos que son páginas de sistema, no de contenido.
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final path = uri.path.toLowerCase();
        // Si no tiene ruta o es solo '/', es la página principal
        if (path.isEmpty || path == '/') continue;

        // Páginas típicas de usuario o sistema en sitios de manga/anime
        final junkSegments = {
          'profile', 'foro', 'rank', 'mis-manhwas', 'library', 'latest',
          'login', 'register', 'uploads', 'bookmarks', 'history', 'favorites',
          'siguiendo', 'pendiente', 'finalizado', 'popular', 'usuario',
          'cuenta', 'panel', 'seguidos', 'user', 'dashboard', 'mi-cuenta',
          'animes-vistos', 'mangas-vistos', 'lista', 'tendencias', 'top',
          'donaciones', 'contacto', 'dmca', 'terms', 'privacy'
        };
        
        // Revisamos los segmentos exactos de la ruta (ej: /manga/el-rank-1 no se bloquea por tener 'rank')
        bool isJunk = false;
        final segments = uri.pathSegments.map((s) => s.toLowerCase());
        for (final segment in segments) {
          if (junkSegments.contains(segment)) {
            isJunk = true;
            break;
          }
        }
        if (isJunk) continue;
      }

      result.add(url);
    }

    return result.toList();
  }

  static Future<_ProcessRes> _processSingleUrl(
      String url, List<dynamic> repoIndex) async {
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('URL inválida');

    final host = uri.host;
    
    // 1. Validar extensión
    final validation = _validateExtension(host, repoIndex);
    if (!validation.isValid) {
      throw Exception(validation.error);
    }
    
    final extService = validation.service!;
    final extension = extService.extension;

    // 2. Clasificar el link (Directo vs Perfil)
    if (_isProfileLink(uri.path)) {
      throw Exception('Links de perfil no soportados todavía');
    }

    // 3. Obtener detalle
    await extService.asegurarMotor();
    
    // El estándar en prism-plus es usar rutas relativas (ej. /leer/manga)
    // Extraemos la ruta relativa para probarla primero.
    String relativeUrl = url;
    if (url.startsWith(uri.origin)) {
      relativeUrl = url.substring(uri.origin.length);
      if (relativeUrl.isEmpty) relativeUrl = '/';
    }

    ExtensionDetail? detail;
    String workingUrl = relativeUrl;

    Future<ExtensionDetail?> fetchSafe(String targetUrl) async {
      try {
        final d = await extService.detail(targetUrl);
        // `title` es obligatorio en `ExtensionDetail`, así que no hace falta
        // preguntar por null: lo que sí pasa es que una extensión devuelva la
        // propia URL como título cuando no encontró la ficha.
        if (d.title.isEmpty || d.title == targetUrl || d.title == url) {
          return null;
        }
        return d;
      } catch (e) {
        return null;
      }
    }

    // 1. Intentar con ruta relativa (Estándar PrismPlus)
    detail = await fetchSafe(relativeUrl);
    
    // 2. Intentar con ruta absoluta (Algunas extensiones viejas)
    if (detail == null) {
      detail = await fetchSafe(url);
      if (detail != null) workingUrl = url;
    }

    // 3. (Fallback Inteligente) Si ambas fallan, tal vez el usuario pegó un link de CAPÍTULO en vez de MANGA.
    // Intentamos recortar el número de capítulo de la URL usando heurísticas comunes.
    if (detail == null) {
      final chopRegex = RegExp(r'-\d+(\.\d+)?(_\d+)?$|/(chapter|capitulo|episodio|c|cap)/\d+.*$');
      
      String choppedRel = chopRegex.hasMatch(relativeUrl) ? relativeUrl.replaceAll(chopRegex, '') : relativeUrl;
      String choppedAbs = chopRegex.hasMatch(url) ? url.replaceAll(chopRegex, '') : url;

      // Lista de URLs a intentar, de más probable a menos probable
      final Set<String> toTest = {};
      
      if (choppedRel != relativeUrl) toTest.add(choppedRel);
      if (choppedAbs != url) toTest.add(choppedAbs);

      // Algunos sitios usan /leer/ para capítulos pero /comic/ o /manga/ para los detalles.
      final replacements = {
        '/leer/': ['/comic/', '/manga/', '/series/', '/'],
        '/capitulo/': ['/series/', '/manga/', '/comic/'],
        '/chapter/': ['/manga/', '/comic/'],
      };

      for (final entry in replacements.entries) {
        if (choppedRel.startsWith(entry.key) || choppedRel.contains(entry.key)) {
          for (final rep in entry.value) {
            toTest.add(choppedRel.replaceFirst(entry.key, rep));
          }
        }
      }

      // Muchas extensiones modernas esperan SOLAMENTE el slug (la última parte de la ruta).
      final uriChopped = Uri.tryParse(choppedRel);
      if (uriChopped != null && uriChopped.pathSegments.isNotEmpty) {
        toTest.add(uriChopped.pathSegments.last); // El puro slug
        toTest.add('/${uriChopped.pathSegments.last}');
      }

      // Probar cada una de las opciones generadas
      for (final testUrl in toTest) {
        if (testUrl.isEmpty || testUrl == '/') continue;
        detail = await fetchSafe(testUrl);
        if (detail != null) {
          workingUrl = testUrl;
          break;
        }
      }
    }

    if (detail == null) {
      throw Exception('No se pudo obtener el detalle. Comprueba que el link sea válido.');
    }

    // 4. Validar que sea contenido de lectura
    // El tipo por-obra solo lo mandan las extensiones mixtas; el resto cae al
    // que declara la extensión, que siempre está. O sea que acá nunca hay un
    // tipo desconocido —el comentario anterior contemplaba ese caso, que no
    // puede darse— y la regla es simple: si no sirve para leer y encima es de
    // vídeo, este enlace no va.
    //
    // Una mixta pasa igual, porque cuenta como las dos cosas.
    final detailType = detail.type ?? extension.type;
    if (!ExtensionUtils.readingTypes.contains(detailType) &&
        ExtensionUtils.videoTypes.contains(detailType)) {
      throw Exception('Este link es de contenido de vídeo, no de lectura');
    }

    // 5. Detectar NSFW
    bool isNsfw = extension.nsfw;

    if (detail.genres != null) {
      final nsfwKeywords = [
        'adulto', 'adult', '18+', '+18', 'nsfw', 'hentai', 'ecchi', 
        'maduro', 'mature', 'smut', 'doujinshi', 'gore', 'seinen', 'josei'
      ];
      final hasNsfwGenre = detail.genres!.any((g) =>
          nsfwKeywords.any((k) => g.toLowerCase().contains(k)));
      if (hasNsfwGenre) isNsfw = true;
    }

    // 6. Comprobar duplicados
    final existingHistory = await DatabaseService.getHistoryByPackageAndUrl(
        extension.package, workingUrl);
    final isFav = await DatabaseService.isFavorite(package: extension.package, url: workingUrl);
    if (isFav) {
      return _ProcessRes(duplicate: true, extensionName: extension.name);
    }

    // 7. Guardar favorito
    final favorite = Favorite()
      ..package = extension.package
      ..url = workingUrl
      ..type = detailType
      ..title = detail.title
      ..cover = detail.cover
      ..isNsfw = isNsfw;
    await DatabaseService.putFavoriteRaw(favorite);

    // 8. Guardar historial (progreso) SOLO si no tiene un historial previo
    // De esta forma protegemos los capítulos que el usuario ya haya visto.
    if (existingHistory == null) {
      int episodeGroupId = 0;
      int episodeId = 0;
      String? episodeTitle;
      bool foundSpecificEpisode = false;

      // Buscar si el link original que pegó el usuario coincide con un episodio específico
      if (detail.episodes != null) {
        for (int g = 0; g < detail.episodes!.length; g++) {
          final group = detail.episodes![g];
          for (int i = 0; i < group.urls.length; i++) {
            final ep = group.urls[i];
            // Comparamos contra la url absoluta y relativa originales
            if (ep.url == url || ep.url == relativeUrl || url.endsWith(ep.url) || relativeUrl.endsWith(ep.url)) {
              episodeGroupId = g;
              episodeId = i;
              episodeTitle = ep.name;
              foundSpecificEpisode = true;
              break;
            }
          }
          if (foundSpecificEpisode) break;
        }
      }

      // Si no pegó un link de capítulo o no se encontró, tomamos el último por defecto
      if (!foundSpecificEpisode) {
        if (detail.episodes != null && detail.episodes!.isNotEmpty) {
          final group = detail.episodes!.last;
          if (group.urls.isNotEmpty) {
            episodeTitle = group.urls.last.name;
            episodeGroupId = detail.episodes!.length - 1;
            episodeId = group.urls.length - 1;
          }
        }
      }

      final history = History()
        ..package = extension.package
        ..url = workingUrl
        ..title = detail.title
        ..type = detailType
        ..cover = detail.cover
        ..episodeTitle = episodeTitle ?? ''
        ..progress = ''
        ..totalProgress = ''
        ..episodeGroupId = episodeGroupId
        ..episodeId = episodeId
        ..isNsfw = isNsfw;
      await DatabaseService.putHistory(history);
    }

    return _ProcessRes(
        imported: true, nsfw: isNsfw, extensionName: extension.name);
  }

  static _ValidationResult _validateExtension(String host, List<dynamic> repoIndex) {
    String cleanHost(String h) => h.startsWith('www.') ? h.substring(4) : h;
    final targetHost = cleanHost(host);

    // ── Sin dominio no se busca nada ──────────────────────────────────────
    //
    // `Uri.tryParse` no falla con un enlace sin esquema: "olympus.com/manga/1"
    // le parece una RUTA, así que devuelve un Uri valido con el host VACÍO. Y
    // más abajo se compara ese host contra el de cada extensión, que también
    // puede venir vacío —el manifiesto que se sintetiza al instalar desde el
    // catálogo pone `webSite` en blanco cuando el índice no lo trae—.
    //
    // Vacío contra vacío da igual, así que un enlace pegado sin el https://
    // enganchaba la PRIMERA extensión sin sitio declarado y trataba de
    // importar desde ella. Cortando acá, el usuario recibe el mensaje que
    // corresponde en vez de un error raro de otra extensión.
    if (targetHost.isEmpty) {
      return _ValidationResult.error(
        'Ese enlace no tiene un sitio reconocible. Copiá la dirección '
        'completa, con https:// adelante.',
      );
    }

    // Buscar en instaladas y activadas primero
    for (final entry in ExtensionUtils.enabledRuntimes.entries) {
      final ext = entry.value.extension;
      // `isNotEmpty` y no `!= null`: `webSite` es obligatorio en el modelo, así
      // que nunca es nulo — pero sí puede venir en blanco, que es el caso que
      // esta guarda tenía que cubrir.
      final extHost = ext.webSite.isNotEmpty
          ? cleanHost(Uri.tryParse(ext.webSite)?.host ?? '')
          : '';
      if (extHost == targetHost) {
        // Verificar si es de lectura
        if (!ExtensionUtils.readingTypes.contains(ext.type)) {
          return _ValidationResult.error('Esta extensión es de vídeo, no de lectura');
        }
        if (ExtensionUtils.isRemoteUnstableCached(ext.package)) {
          return _ValidationResult.error('La extensión ${ext.name} está temporalmente fuera de servicio');
        }
        return _ValidationResult.ok(entry.value);
      }
    }

    // Buscar en instaladas pero desactivadas
    for (final entry in ExtensionUtils.runtimes.entries) {
      final ext = entry.value.extension;
      // `isNotEmpty` y no `!= null`: `webSite` es obligatorio en el modelo, así
      // que nunca es nulo — pero sí puede venir en blanco, que es el caso que
      // esta guarda tenía que cubrir.
      final extHost = ext.webSite.isNotEmpty
          ? cleanHost(Uri.tryParse(ext.webSite)?.host ?? '')
          : '';
      if (extHost == targetHost) {
        return _ValidationResult.error('Tenés ${ext.name} pero está desactivada. Activala en Extensiones instaladas.');
      }
    }

    // Buscar en el catálogo
    for (final raw in repoIndex) {
      if (raw is Map) {
        final webSite = raw['webSite']?.toString();
        final extHost = (webSite != null && webSite.isNotEmpty)
            ? cleanHost(Uri.tryParse(webSite)?.host ?? '')
            : '';
        if (extHost == targetHost) {
          final name = raw['name']?.toString() ?? 'la extensión';
          return _ValidationResult.error('Necesitás instalar $name desde el Repositorio para importar links de $host.');
        }
      }
    }

    return _ValidationResult.error('No hay extensión disponible para $host.');
  }

  static bool _isProfileLink(String path) {
    final p = path.toLowerCase();
    if (p.isEmpty || p == '/') return false;
    
    // Solo un segmento o palabras clave
    final segments = p.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length == 1) return true;

    final profileKeywords = ['/perfil', '/mis-', '/profile', '/my-', '/bookmarks', '/library'];
    if (profileKeywords.any((k) => p.contains(k))) return true;

    return false;
  }

  static ImportResult _emptyResult() {
    return const ImportResult(
      totalProcessed: 0,
      totalImported: 0,
      totalDuplicates: 0,
      totalNsfw: 0,
      totalErrors: 0,
      totalSkipped: 0,
      importedByExtension: {},
      errors: [],
      elapsed: Duration.zero,
    );
  }
}

class _ProcessRes {
  final bool imported;
  final bool duplicate;
  final bool nsfw;
  final String? extensionName;

  _ProcessRes({
    this.imported = false,
    this.duplicate = false,
    this.nsfw = false,
    this.extensionName,
  });
}

class _ValidationResult {
  final bool isValid;
  final String? error;
  final ExtensionService? service;

  _ValidationResult.ok(this.service)
      : isValid = true,
        error = null;

  _ValidationResult.error(this.error)
      : isValid = false,
        service = null;
}
