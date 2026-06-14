import 'extension_model.dart';

/// DTO para parsear una extensión desde el index.json de un repositorio.
/// No persiste en Isar — es solo un objeto en memoria.
class ExtensionDto {
  const ExtensionDto({
    required this.name,
    required this.package,
    required this.version,
    required this.author,
    required this.type,
    required this.scriptUrl,
    required this.repoUrl,
    this.iconUrl,
  });

  final String name;
  final String package;
  final String version;
  final String author;
  final ExtensionType type;
  final String scriptUrl;
  final String repoUrl;
  final String? iconUrl;

  factory ExtensionDto.fromJson(Map<String, dynamic> json, String repoUrl) =>
      ExtensionDto(
        name: json['name'] as String,
        package: json['package'] as String,
        version: json['version'] as String,
        author: json['author'] as String,
        type: ExtensionType.values.firstWhere(
          (e) => e.name == (json['type'] as String? ?? 'anime'),
          orElse: () => ExtensionType.anime,
        ),
        scriptUrl: json['script'] as String,
        repoUrl: repoUrl,
        iconUrl: json['icon'] as String?,
      );
}

/// Respuesta completa de un index.json de repositorio.
class RepoIndex {
  const RepoIndex({required this.extensions});
  final List<ExtensionDto> extensions;

  factory RepoIndex.fromJson(Map<String, dynamic> json, String repoUrl) {
    final list = (json['extensions'] as List?) ?? [];
    return RepoIndex(
      extensions: list
          .whereType<Map<String, dynamic>>()
          .map((e) => ExtensionDto.fromJson(e, repoUrl))
          .toList(),
    );
  }
}
