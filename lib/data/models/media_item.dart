import 'extension_model.dart';

/// Resultado de latest() o search() — equivale a PrismItem del contrato TS.
class MediaItem {
  const MediaItem({
    required this.title,
    required this.url,
    required this.package,
    required this.type,
    this.cover,
    this.description,
    this.tags,
  });

  final String title;
  final String url;
  final String package; // extensión propietaria
  final ExtensionType type;
  final String? cover;
  final String? description;
  final List<String>? tags;

  factory MediaItem.fromMap(
    Map<String, dynamic> map, {
    required String package,
    required ExtensionType type,
  }) => MediaItem(
    title: (map['title'] as String?) ?? '',
    url: (map['url'] as String?) ?? '',
    package: package,
    type: type,
    cover: map['cover'] as String?,
    description: map['description'] as String?,
    tags: (map['tags'] as List?)?.cast<String>(),
  );
}

/// Episodio / capítulo individual — equivale a PrismEpisode del contrato TS.
class MediaEpisode {
  const MediaEpisode({required this.title, required this.url});

  final String title;
  final String url;

  factory MediaEpisode.fromMap(Map<String, dynamic> map) => MediaEpisode(
    title: (map['title'] as String?) ?? '',
    url: (map['url'] as String?) ?? '',
  );
}

/// Resultado de detail() — equivale a PrismDetail del contrato TS.
class MediaDetail {
  const MediaDetail({
    required this.title,
    required this.url,
    required this.package,
    required this.type,
    required this.episodes,
    this.cover,
    this.description,
    this.extra,
  });

  final String title;
  final String url;
  final String package;
  final ExtensionType type;
  final String? cover;
  final String? description;
  final List<MediaEpisode> episodes;
  final Map<String, String>? extra;

  factory MediaDetail.fromMap(
    Map<String, dynamic> map, {
    required String package,
    required String url,
    required ExtensionType type,
  }) {
    final rawEps = map['episodes'] as List? ?? [];
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
