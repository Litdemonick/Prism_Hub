import 'package:isar/isar.dart';

part 'favorite_model.g.dart';

@collection
class FavoriteModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String url;

  late String title;
  late String extensionPackage;
  String? cover;
  late DateTime addedAt;
}
