import 'dart:io';

import 'package:flutter/services.dart';
import 'package:prismhub/utils/log.dart';

/// Si el proceso está corriendo en un Android TV (o una caja Google
/// TV/leanback), en vez de un teléfono o tablet.
///
/// Windows y Linux nunca preguntan al canal: no existe del otro lado, así que
/// ni se intenta.
class PlatformTv {
  static const _canal = MethodChannel('com.example.prismhub/update');

  /// Se resuelve UNA sola vez, durante el arranque (ver `_AppRootState._init`
  /// en main.dart), antes de que se construya la primera pantalla real. El
  /// resto de la app pregunta con [esTelevisionSync]: el mismo criterio
  /// síncrono que ya usa todo el código de plataforma (`Platform.isAndroid`),
  /// para no tener que reescribir cada `build()` alrededor de un `Future`.
  static bool esTelevisionSync = false;

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid) return;
    try {
      esTelevisionSync =
          await _canal.invokeMethod<bool>('isTelevision') ?? false;
    } catch (e) {
      // Si el canal falla (dispositivo viejo, error de plataforma), se sigue
      // como teléfono normal. Nunca puede ser esto lo que tumbe el arranque.
      logger.warning('No se pudo detectar si el dispositivo es TV: $e');
      esTelevisionSync = false;
    }
  }
}
