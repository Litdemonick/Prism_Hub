import 'package:json_annotation/json_annotation.dart';

part 'extension.g.dart';

// Los valores nuevos van SIEMPRE al final — FavoritesPage llega por índice de
// ExtensionType.values vía query param (router.dart), así que insertar uno en
// el medio correría los índices de los que ya están y rompería rutas guardadas
// o compartidas. En la base se guardan por NOMBRE (@Enumerated(EnumType.name)
// en History/Favorite), así que agregar al final no toca nada de lo guardado.
//
// mixed        = lectura Y vídeo en el mismo sitio (ej. ShadeManga: manga y
//                anime de verdad).
// mixedReading = varias clases de LECTURA y ningún vídeo (ej. Ikigai: cómics
//                y novelas ligeras). Necesita tipo por obra igual que mixed
//                —una novela es texto y un cómic imágenes, y cada uno abre con
//                su lector— pero NO debe aparecer en los filtros de vídeo, que
//                es lo que pasaba al declararla mixed.
enum ExtensionType { manga, bangumi, fikushon, mixed, mixedReading }

enum ExtensionWatchBangumiType { hls, mp4, torrent }

enum ExtensionLogLevel {
  info,
  error,
}

@JsonSerializable()
class Extension {
  Extension({
    required this.package,
    required this.author,
    required this.version,
    required this.lang,
    required this.license,
    required this.type,
    required this.webSite,
    required this.name,
    this.nsfw = false,
    this.icon,
    this.url,
    this.description,
    this.latestLabel,
    this.contentKind,
  });

  final bool nsfw;
  final String package;
  final String author;
  final String version;
  final String lang;
  final String license;
  final ExtensionType type;
  final String webSite;
  final String name;
  String? icon;
  String? url;
  String? description;

  /// Qué clase de vídeo trae la extensión: `'anime'`, `'accion-real'` o
  /// `'mixto'` (las dos cosas en el mismo sitio, ej. ShadeManga).
  ///
  /// Solo tiene sentido para extensiones de vídeo — una extensión de
  /// lectura pura no necesita declararlo. Lo declara la extensión en su
  /// manifiesto (`@contentKind`) y viaja en la cabecera del paquete.
  ///
  /// ── Por qué es un String? y no un enum ──────────────────────────────
  ///
  /// `$enumDecode` (lo que genera `json_serializable` para un enum) lanza
  /// una excepción si el valor no matchea ningún nombre — correcto para
  /// `type`, que es obligatorio y ya está validado, pero no para un campo
  /// nuevo y opcional: una extensión de la comunidad que declare
  /// `@contentKind live-action` (en vez de `accion-real`) tiene que seguir
  /// instalando y funcionando igual, solo sin entrar a Películas/Series/
  /// Anime hasta que lo corrija. Mismo criterio que ya usa `lang`.
  ///
  /// Ausente, o con un valor que no se reconoce, no rompe nada: la
  /// extensión sigue viéndose en Inicio/Biblioteca/Buscar exactamente
  /// igual que si nunca hubiera existido este campo.
  final String? contentKind;

  /// Cómo llama el sitio a su sección de «lo último»: «Programación»,
  /// «Últimos añadidos», «Novedades».
  ///
  /// Lo declara la extensión en su manifiesto y viaja en la cabecera del
  /// paquete (@latestLabel). El Home lo muestra debajo del nombre de la fila,
  /// para que el usuario sepa QUÉ está viendo y no solo de dónde viene.
  ///
  /// Opcional a propósito: una extensión vieja, o una de la comunidad que no lo
  /// declare, simplemente cae al texto genérico. Nada se rompe por no tenerlo.
  String? latestLabel;

  factory Extension.fromJson(Map<String, dynamic> json) =>
      _$ExtensionFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionToJson(this);
}

@JsonSerializable()
class ExtensionFilter {
  ExtensionFilter({
    required this.title,
    required this.min,
    required this.max,
    required this.defaultOption,
    required this.options,
    this.adultOption,
  });
  final String title;
  final int min;
  final int max;
  @JsonKey(name: "default")
  final String defaultOption;
  final Map<String, String> options;
  // Marca cuál valor de `options` representa "mostrar contenido +18" para
  // este filtro (ej. una extensión mixta manga+anime con su propia sección
  // de adultos, como ShadeManga) — cuando el usuario elige ESE valor
  // puntual, extension_searcher_page.dart chequea el switch de NSFW de
  // Ajustes ANTES de llamar a search(), en vez de mostrar el contenido
  // directo o dejarlo bloqueado sin explicación. null = este filtro no
  // tiene una opción de adultos (el caso normal, la mayoría de extensiones).
  final String? adultOption;

  factory ExtensionFilter.fromJson(Map<String, dynamic> json) =>
      _$ExtensionFilterFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionFilterToJson(this);
}

@JsonSerializable()
class ExtensionListItem {
  ExtensionListItem({
    required this.title,
    required this.url,
    this.cover,
    this.update,
    this.headers,
  });

  final String title;
  final String url;
  final String? cover;
  final String? update;
  late Map<String, String>? headers;

  factory ExtensionListItem.fromJson(Map<String, dynamic> json) =>
      _$ExtensionListItemFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionListItemToJson(this);
}

@JsonSerializable()
class ExtensionDetail {
  ExtensionDetail({
    required this.title,
    this.cover,
    this.desc,
    this.episodes,
    this.headers,
    this.genres,
    this.type,
    this.status,
  });

  final String title;
  final String? cover;
  final String? desc;
  final List<ExtensionEpisodeGroup>? episodes;
  late Map<String, String>? headers;
  // Estado de publicación que manda la extensión (el SDK lo define como
  // 'ongoing' | 'completed' | 'upcoming' | 'hiatus'). Opcional: no todas
  // las extensiones lo scrapean, y las que no, simplemente no muestran el
  // badge en el detalle en vez de inventar un estado.
  final String? status;
  // No todas las extensiones lo devuelven (jkanime/animeytx/manhwaweb/olympus
  // sí, vía su propio scraping del sitio) — por eso es opcional.
  final List<String>? genres;
  // Solo lo llenan extensiones "mixed" (manga+anime en una, ej. ShadeManga):
  // como la extensión declara un único ExtensionType fijo en su manifest,
  // este campo por-título es la única forma de saber si ESTE detalle puntual
  // se debe abrir con el lector de manga o el reproductor de video — ver
  // ExtensionUtils.resolveType(). El resto de extensiones no lo manda nunca.
  final ExtensionType? type;

  factory ExtensionDetail.fromJson(Map<String, dynamic> json) =>
      _$ExtensionDetailFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionDetailToJson(this);
}

@JsonSerializable()
class ExtensionEpisodeGroup {
  ExtensionEpisodeGroup({
    required this.title,
    required this.urls,
  });
  final String title;
  final List<ExtensionEpisode> urls;

  factory ExtensionEpisodeGroup.fromJson(Map<String, dynamic> json) =>
      _$ExtensionEpisodeGroupFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionEpisodeGroupToJson(this);
}

@JsonSerializable()
class ExtensionEpisode {
  ExtensionEpisode({
    required this.name,
    required this.url,
  });
  final String name;
  final String url;

  factory ExtensionEpisode.fromJson(Map<String, dynamic> json) =>
      _$ExtensionEpisodeFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionEpisodeToJson(this);
}

@JsonSerializable()
class ExtensionBangumiWatch {
  ExtensionBangumiWatch({
    required this.type,
    required this.url,
    this.subtitles,
    this.headers,
    this.audioTrack,
  });
  final ExtensionWatchBangumiType type;
  final String url;
  final List<ExtensionBangumiWatchSubtitle>? subtitles;
  late Map<String, String>? headers;
  late String? audioTrack;

  factory ExtensionBangumiWatch.fromJson(Map<String, dynamic> json) =>
      _$ExtensionBangumiWatchFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionBangumiWatchToJson(this);
}

@JsonSerializable()
class ExtensionBangumiWatchSubtitle {
  final String? language;
  final String title;
  final String url;
  ExtensionBangumiWatchSubtitle({
    required this.title,
    required this.url,
    this.language,
  });

  factory ExtensionBangumiWatchSubtitle.fromJson(Map<String, dynamic> json) =>
      _$ExtensionBangumiWatchSubtitleFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionBangumiWatchSubtitleToJson(this);
}

@JsonSerializable()
class ExtensionMangaWatch {
  ExtensionMangaWatch({
    required this.urls,
    this.headers,
  });

  final List<String> urls;
  late Map<String, String>? headers;

  factory ExtensionMangaWatch.fromJson(Map<String, dynamic> json) =>
      _$ExtensionMangaWatchFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionMangaWatchToJson(this);
}

@JsonSerializable()
class ExtensionFikushonWatch {
  final List<String> content;
  final String title;
  final String? subtitle;
  ExtensionFikushonWatch({
    required this.content,
    required this.title,
    this.subtitle,
  });

  factory ExtensionFikushonWatch.fromJson(Map<String, dynamic> json) =>
      _$ExtensionFikushonWatchFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionFikushonWatchToJson(this);
}

@JsonSerializable()
class ExtensionLog {
  ExtensionLog({
    required this.extension,
    required this.content,
    required this.time,
    required this.level,
  });

  final DateTime time;
  final Extension extension;
  final String content;
  final ExtensionLogLevel level;

  factory ExtensionLog.fromJson(Map<String, dynamic> json) =>
      _$ExtensionLogFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionLogToJson(this);
}

@JsonSerializable()
class ExtensionNetworkLog {
  final Extension extension;
  String? responseBody;
  String? requestBody;
  Map<String, dynamic>? requestHeaders;
  Map<String, dynamic>? responseHeaders;
  String url;
  String method;
  int? statusCode;

  ExtensionNetworkLog({
    required this.extension,
    required this.url,
    required this.method,
    this.statusCode,
    this.responseBody,
    this.requestBody,
    this.requestHeaders,
    this.responseHeaders,
  });

  factory ExtensionNetworkLog.fromJson(Map<String, dynamic> json) =>
      _$ExtensionNetworkLogFromJson(json);

  Map<String, dynamic> toJson() => _$ExtensionNetworkLogToJson(this);
}
