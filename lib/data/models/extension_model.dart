import 'package:isar/isar.dart';

part 'extension_model.g.dart';

/// Tipos de contenido que puede manejar una extensión.
enum ExtensionType { anime, manga, comic, novel }

@collection
class ExtensionModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String package; // e.g. "com.prismhub.animeflv"

  late String name;
  late String version;
  late String author;
  late String scriptUrl;
  String? iconUrl;
  String? repoUrl;

  @Enumerated(EnumType.name)
  late ExtensionType type;

  bool isInstalled = false;
  DateTime? installedAt;
}
