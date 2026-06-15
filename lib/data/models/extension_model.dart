import 'package:isar/isar.dart';

part 'extension_model.g.dart';

enum ExtensionType {
  anime,
  manga,
  comic,
  novel,
  movie,
  series,
  documentary,
  live,
  video,
  music,
  podcast,
  other,
}

@collection
class ExtensionModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String package;

  late String name;
  late String version;
  late String author;
  late String scriptUrl;
  String? iconUrl;
  String? repoUrl;

  // Ruta local al bundle .js descargado
  String? localScriptPath;

  @Enumerated(EnumType.name)
  late ExtensionType type;

  bool isInstalled = false;
  DateTime? installedAt;
}
