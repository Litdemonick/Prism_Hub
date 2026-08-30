import 'dart:convert';
import 'dart:io';

import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_directory.dart';

/// Lo último que llegó del registro de otro aparato, guardado en disco.
///
/// ── Por qué hace falta ──────────────────────────────────────────────────────
///
/// El registro remoto vivía solo en memoria. Mientras la pantalla estaba
/// abierta, si se cortaba la conexión se conservaba lo que ya había llegado —y
/// el aviso lo decía: «lo de abajo es lo último que llegó»—. Pero al salir y
/// volver a entrar, o al abrir uno de los televisores de la lista de «se perdió
/// la conexión», no quedaba nada: la pantalla decía «no llegó a llegar nada»
/// debajo de un cartel que prometía justo lo contrario.
///
/// Y ese es el momento en que más falta hace. Si el televisor se cayó, lo
/// último que llegó ANTES de caerse es exactamente lo que explica por qué.
///
/// ── Qué se guarda y cuánto ──────────────────────────────────────────────────
///
/// Un archivo por televisor, con la cabecera, las líneas y cuándo se recibió.
/// Con tope: un registro en vivo crece sin parar y no tiene sentido llenar el
/// disco de nadie con la sesión entera de otro aparato. Se conservan las
/// últimas [_lineasQueSeGuardan], que son las que se estaban mirando.
///
/// No se guarda nada que el registro no llevara ya: es el mismo texto saneado
/// que el aparato de origen decidió compartir.
class RegistroGuardadoDeOtro {
  RegistroGuardadoDeOtro._();

  /// Cuántas líneas se conservan de cada aparato.
  ///
  /// Dos mil: alcanza para varias sesiones de reproducción y son unos pocos
  /// cientos de kilobytes. Más que eso es guardar historia que ya no se mira.
  static const _lineasQueSeGuardan = 2000;

  static Directory get _carpeta =>
      Directory('${PrismHubDirectory.getDirectory}/registros_de_otros');

  /// Un nombre de archivo estable a partir de la dirección.
  ///
  /// Se limpia en vez de usar un número: así, mirando la carpeta, se entiende
  /// de qué aparato es cada archivo sin tener que descifrar nada.
  static String _archivoDe(String url) {
    final limpio = url.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    // Con tope de largo: hay sistemas de archivos que no aceptan nombres
    // largos, y una dirección con parámetros puede irse a cualquier lado.
    final corto = limpio.length > 120 ? limpio.substring(0, 120) : limpio;
    return '${_carpeta.path}/$corto.log';
  }

  /// Guarda lo último que llegó de [url].
  ///
  /// Nunca lanza: esto es una comodidad, y que no se pueda guardar no puede
  /// impedir seguir mirando el registro en vivo.
  static Future<void> guardar({
    required String url,
    required String cabecera,
    required List<String> lineas,
  }) async {
    try {
      if (!_carpeta.existsSync()) _carpeta.createSync(recursive: true);
      final recortadas = lineas.length > _lineasQueSeGuardan
          ? lineas.sublist(lineas.length - _lineasQueSeGuardan)
          : lineas;
      final sobre = jsonEncode({
        'cuando': DateTime.now().toIso8601String(),
        'cabecera': cabecera,
        'lineas': recortadas,
      });
      await File(_archivoDe(url)).writeAsString(sobre);
    } catch (e) {
      logger.info('No se pudo guardar el registro de $url: $e');
    }
  }

  /// Lo que se guardó la última vez, o null si no hay nada.
  static ({String cabecera, List<String> lineas, DateTime cuando})? leer(
    String url,
  ) {
    try {
      final f = File(_archivoDe(url));
      if (!f.existsSync()) return null;
      final crudo = jsonDecode(f.readAsStringSync());
      if (crudo is! Map) return null;
      final lineas = (crudo['lineas'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>[];
      if (lineas.isEmpty) return null;
      return (
        cabecera: crudo['cabecera']?.toString() ?? '',
        lineas: lineas,
        cuando: DateTime.tryParse(crudo['cuando']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (e) {
      // Un archivo a medio escribir o de una versión anterior: se ignora y se
      // sigue como si no hubiera nada.
      logger.info('No se pudo leer el registro guardado de $url: $e');
      return null;
    }
  }

  /// Borra lo guardado de un aparato, o de todos si [url] es null.
  ///
  /// Se llama desde «olvidar los caídos»: si alguien pide olvidar un televisor,
  /// olvidarlo a medias —sacarlo de la lista pero dejar su registro en disco—
  /// no es lo que pidió.
  static Future<void> olvidar([String? url]) async {
    try {
      if (url != null) {
        final f = File(_archivoDe(url));
        if (f.existsSync()) await f.delete();
        return;
      }
      if (_carpeta.existsSync()) await _carpeta.delete(recursive: true);
    } catch (e) {
      logger.info('No se pudo olvidar el registro guardado: $e');
    }
  }
}
