import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract final class AppDirectory {
  static late String _base;

  static Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _base = p.join(docs.path, 'prism_hub');
    await Directory(extensionsDir).create(recursive: true);
  }

  static String get extensionsDir => p.join(_base, 'extensions');

  static String extensionScript(String package) =>
      p.join(extensionsDir, '$package.js');
}
