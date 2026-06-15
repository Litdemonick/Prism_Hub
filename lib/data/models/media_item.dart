import 'extension_model.dart';

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
    final overrideType = _parseType(map['type'] as String?);
    return MediaItem(
      title: (map['title'] as String?) ?? '',
      url: (map['url'] as String?) ?? '',
      package: package,
      type: overrideType ?? type,
      cover: map['cover'] as String?,
      description: map['description'] as String?,
      tags: (map['tags'] as List?)?.cast<String>(),
      year: (map['year'] as num?)?.toInt(),
      rating: (map['rating'] as num?)?.toDouble(),
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
    title: (map['title'] as String?) ?? '',
    url: (map['url'] as String?) ?? '',
    thumbnail: map['thumbnail'] as String?,
    duration: (map['duration'] as num?)?.toInt(),
    airDate: map['airDate'] as String?,
    number: (map['number'] as num?)?.toInt(),
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
    title: (map['title'] as String?) ?? '',
    year: (map['year'] as num?)?.toInt(),
    cover: map['cover'] as String?,
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
    final rawEps = map['episodes'] as List? ?? [];
    final rawSeasons = map['seasons'] as List?;
    return MediaDetail(
      title: (map['title'] as String?) ?? '',
      url: url,
      package: package,
      type: type,
      cover: map['cover'] as String?,
      description: map['description'] as String?,
      episodes: rawEps
          .whereType<Map>()
          .map((e) => MediaEpisode.fromMap(e.cast<String, dynamic>()))
          .toList(),
      seasons: rawSeasons
          ?.whereType<Map>()
          .map((s) => MediaSeason.fromMap(s.cast<String, dynamic>()))
          .toList(),
      genres: (map['genres'] as List?)?.cast<String>(),
      status: map['status'] as String?,
      year: (map['year'] as num?)?.toInt(),
      rating: (map['rating'] as num?)?.toDouble(),
      extra: (map['extra'] as Map?)?.cast<String, String>(),
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
