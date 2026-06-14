import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/extension_model.dart';
import '../../data/models/history_model.dart';
import '../../data/models/favorite_model.dart';

class DatabaseService {
  DatabaseService._();

  static late Isar _db;
  static Isar get db => _db;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await Isar.open(
      [ExtensionModelSchema, HistoryModelSchema, FavoriteModelSchema],
      directory: dir.path,
      name: 'prism_hub',
    );
  }
}
