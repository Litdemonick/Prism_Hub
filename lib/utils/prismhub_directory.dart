import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PrismHubDirectory {
  static late final Directory _appDocDir;
  static late final Directory _cacheDir;

  static ensureInitialized() async {
    _appDocDir = await getApplicationDocumentsDirectory();
    _cacheDir = await getTemporaryDirectory();
  }

  static String get getDirectory => _prismHubDir(_appDocDir);

  static String get getCacheDirectory => _prismHubDir(_cacheDir);

  static String _prismHubDir(Directory directory) {
    final dir = path.join(directory.path, 'PrismHub');
    Directory(dir).createSync(recursive: true);
    return dir;
  }
}
