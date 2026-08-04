import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:prismhub/utils/modo_app.dart';

class PrismHubDirectory {
  static late final Directory _appDocDir;
  static late final Directory _cacheDir;

  static ensureInitialized() async {
    _appDocDir = await getApplicationDocumentsDirectory();
    _cacheDir = await getTemporaryDirectory();
  }

  static String get getDirectory => _prismHubDir(_appDocDir);

  static String get getCacheDirectory => _prismHubDir(_cacheDir);

  /// La carpeta de datos, SEPARADA cuando no es una compilación publicable.
  ///
  /// Con una sola carpeta para todo, correr una compilación de pruebas escribía
  /// encima de los ajustes, el historial y los favoritos de la versión
  /// instalada. No es que "la reemplace": le toca los datos de verdad, y un
  /// experimento a medias puede dejarlos inservibles.
  ///
  /// En release el nombre queda igual que siempre (`PrismHub`), así que la
  /// versión instalada sigue leyendo lo suyo sin migrar nada.
  static String _prismHubDir(Directory directory) {
    final dir = path.join(directory.path, 'PrismHub${ModoApp.sufijo}');
    Directory(dir).createSync(recursive: true);
    return dir;
  }
}
