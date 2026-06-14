import 'package:isar/isar.dart';

part 'history_model.g.dart';

@collection
class HistoryModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String url;

  late String title;
  late String extensionPackage;
  String? cover;

  /// Índice del episodio/capítulo que el usuario vio por última vez.
  int progress = 0;

  late DateTime updatedAt;
}
