import 'package:flutter/foundation.dart';

/// En qué modo está corriendo esta copia de la app.
///
/// Sirve para que **una compilación de pruebas no pise la versión instalada**.
/// Antes las dos eran indistinguibles: compartían la carpeta de datos, el
/// candado de instancia única y, en Android, el mismo identificador de
/// aplicación. Resultado: probar un cambio te escribía encima de tus ajustes,
/// tu historial y tus favoritos reales, y en Android te reemplazaba la app.
///
/// Todo se decide con `kReleaseMode`, así que **no hay nada que acordarse de
/// sacar antes de publicar**: al compilar el release, el sufijo desaparece
/// solo y la app vuelve a usar la carpeta y el puerto de siempre.
class ModoApp {
  ModoApp._();

  /// ¿Es una compilación publicable? En depuración y en perfil da `false`.
  static const esRelease = kReleaseMode;

  /// Sufijo para separar la copia de pruebas de la instalada. Vacío en release.
  ///
  /// Se usa para la carpeta de datos y para el nombre visible. Tiene que ser
  /// algo válido como nombre de carpeta en los tres sistemas.
  static String get sufijo => esRelease ? '' : '-dev';

  /// Cómo se llama el modo, para mostrárselo al usuario.
  ///
  /// Devuelve null en release: ahí no hay nada que aclarar y no debe aparecer
  /// ningún distintivo.
  static String? get etiqueta {
    if (kReleaseMode) return null;
    if (kProfileMode) return 'perfil';
    return 'depuración';
  }

  /// La versión con el modo al lado, para las pantallas que la muestran.
  ///
  /// En release devuelve la versión tal cual. En pruebas queda, por ejemplo,
  /// `1.0.23 · perfil`, que es lo que permite saber de un vistazo cuál de las
  /// dos copias se está usando.
  static String versionConModo(String version) =>
      etiqueta == null ? version : '$version · ${etiqueta!}';
}
