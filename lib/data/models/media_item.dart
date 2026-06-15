import 'extension_model.dart';

// Helpers de coerción seguros: nunca lanzan si el tipo es inesperado.
String? _str(dynamic v) => v == null ? null : v.toString();
int? _int(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
double? _dbl(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
List<String>? _strList(dynamic v) =>
    v == null ? null : (v as List).map((e) => e?.toString() ?? '').toList();
Map<String, String>? _strMap(dynamic v) {
  if (v == null) return null;
  return {
    for (final e in (v as Map).entries)
      e.key.toString(): e.value?.toString() ?? '',
  };
}

/// Equivale a PrismItem del contrato Prism+.
class MediaItem {
  const MediaItem({
    required this.title,
    required this.url,
    required this.package,
    required this.type,
    this.cover,
    this.description,
    this.tags,
    this.year,
    this.rating,
  });

  final String title;
  final String url;
  final String package;
  final ExtensionType type;
  final String? cover;
  final String? description;
  final List<String>? tags;
  final int? year;
  final double? rating;

  factory MediaItem.fromMap(
    Map<String, dynamic> map, {
    required String package,
    required ExtensionType type,
  }) {
    final overrideType = _parseType(_str(map['type']));
    return MediaItem(
      title:       _str(map['title'])       ?? '',
      url:         _str(map['url'])         ?? '',
      package:     package,
      type:        overrideType ?? type,
      cover:       _str(map['cover']),
      description: _str(map['description']),
      tags:        _strList(map['tags']),
      year:        _int(map['year']),
      rating:      _dbl(map['rating']),
    );
  }

  static ExtensionType? _parseType(String? raw) {
    if (raw == null) return null;
    try {
      return ExtensionType.values.firstWhere((e) => e.name == raw);
    } catch (_) {
      return null;
    }
  }
}

/// Equivale a PrismEpisode del contrato Prism+.
class MediaEpisode {
  const MediaEpisode({
    required this.title,
    required this.url,
    this.thumbnail,
    this.duration,
    this.airDate,
    this.number,
  });

  final String title;
  final String url;
  final String? thumbnail;
  final int? duration;
  final String? airDate;
  final int? number;

  factory MediaEpisode.fromMap(Map<String, dynamic> map) => MediaEpisode(
    title:     _str(map['title'])     ?? '',
    url:       _str(map['url'])       ?? '',
    thumbnail: _str(map['thumbnail']),
    duration:  _int(map['duration']),
    airDate:   _str(map['airDate']),
    number:    _int(map['number']),
  );
}

/// Equivale a PrismSeason del contrato Prism+.
class MediaSeason {
  const MediaSeason({
    required this.title,
    required this.episodes,
    this.year,
    this.cover,
  });

  final String title;
  final List<MediaEpisode> episodes;
  final int? year;
  final String? cover;

  factory MediaSeason.fromMap(Map<String, dynamic> map) => MediaSeason(
    title: _str(map['title']) ?? '',
    year:  _int(map['year']),
    cover: _str(map['cover']),
    episodes: ((map['episodes'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => MediaEpisode.fromMap(e.cast<String, dynamic>()))
        .toList(),
  );
}

/// Equivale a PrismDetail del contrato Prism+.
class MediaDetail {
  const MediaDetail({
    required this.title,
    required this.url,
    required this.package,
    required this.type,
    required this.episodes,
    this.seasons,
    this.cover,
    this.description,
    this.genres,
    this.status,
    this.year,
    this.rating,
    this.extra,
  });

  final String title;
  final String url;
  final String package;
  final ExtensionType type;
  final String? cover;
  final String? description;
  final List<MediaEpisode> episodes;
  final List<MediaSeason>? seasons;
  final List<String>? genres;
  final String? status;
  final int? year;
  final double? rating;
  final Map<String, String>? extra;

  bool get hasSeasonsData => seasons != null && seasons!.isNotEmpty;

  factory MediaDetail.fromMap(
    Map<String, dynamic> map, {
    required String package,
    required String url,
    required ExtensionType type,
  }) {
    final rawEps     = map['episodes'] as List? ?? [];
    final rawSeasons = map['seasons']  as List?;
    return MediaDetail(
      title:       _str(map['title'])       ?? '',
      url:         url,
      package:     package,
      type:        type,
      cover:       _str(map['cover']),
      description: _str(map['description']),
      episodes: rawEps
          .whereType<Map>()
          .map((e) => MediaEpisode.fromMap(e.cast<String, dynamic>()))
          .toList(),
      seasons: rawSeasons
          ?.whereType<Map>()
          .map((s) => MediaSeason.fromMap(s.cast<String, dynamic>()))
          .toList(),
      genres: _strList(map['genres']),
      status: _str(map['status']),
      year:   _int(map['year']),
      rating: _dbl(map['rating']),
      extra:  _strMap(map['extra']),
    );
  }
}

/// Agrupación de items por extensión, usada en la Home.
class HomeSection {
  const HomeSection({
    required this.extensionName,
    required this.package,
    required this.items,
  });
  final String extensionName;
  final String package;
  final List<MediaItem> items;
}
