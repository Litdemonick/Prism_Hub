import 'dart:io';

import 'package:flutter/services.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Pone la pantalla del televisor a la frecuencia del contenido.
///
/// ── El problema, que es de aritmética y no de potencia ──────────────────────
///
/// Casi todo el anime y las películas van a 23,976 o 24 cuadros por segundo, y
/// un televisor va a 60 Hz. Sin pedirle que cambie de modo, esos 24 cuadros hay
/// que repartirlos en 60 refrescos: unos duran dos y otros tres. Eso se ve como
/// un tirón en cualquier movimiento lateral de cámara.
///
/// Y **no mejora con un televisor más potente** — por eso el usuario lo reporta
/// también en los buenos. No es carga: es que las cuentas no dan.
///
/// Es lo que hacen YouTube y Netflix en Android TV, y por eso se ven fluidos.
///
/// ── Solo en televisor, a propósito ──────────────────────────────────────────
///
/// En un teléfono la pantalla es del sistema y cambiarle el modo por un vídeo
/// sería meterse donde no corresponde. En escritorio directamente no aplica: la
/// ventana vive dentro de un escritorio con su propia frecuencia.
///
/// ── Qué pasa si no se puede ─────────────────────────────────────────────────
///
/// Nada. Hay televisores con un solo modo, y otros que no dejan cambiarlo. Se
/// sigue reproduciendo igual, solo que con el tirón de siempre. Un ajuste para
/// que se vea mejor nunca puede impedir que se vea.
class FrecuenciaDePantalla {
  FrecuenciaDePantalla._();

  static const _canal = MethodChannel('com.example.prismhub/update');

  /// Si la app le cambió el modo a la pantalla y todavía no lo devolvió.
  static bool _puesta = false;

  /// Le pide al televisor la frecuencia que le va al contenido.
  ///
  /// [fps] son los cuadros por segundo del vídeo, que mpv informa una vez que
  /// abrió el archivo. Antes de eso no se sabe, así que esto se llama cuando el
  /// dato ya está — no al empezar a cargar.
  static Future<void> ajustarA(double? fps) async {
    if (!Platform.isAndroid || !PlatformTv.esTelevisionSync) return;
    if (fps == null || fps <= 0) return;
    // Fuera de lo que puede ser un vídeo de verdad: mpv a veces informa
    // valores raros mientras todavía está averiguando el formato, y pedirle al
    // televisor un modo por un dato basura lo haría parpadear de gusto.
    if (fps < 10 || fps > 130) return;
    try {
      final quedo = await _canal.invokeMethod<double>(
        'ajustarFrecuenciaDePantalla',
        {'fps': fps},
      );
      if (quedo != null) {
        _puesta = true;
        logger.info('Pantalla puesta a ${quedo.toStringAsFixed(2)} Hz para un '
            'vídeo de ${fps.toStringAsFixed(3)} cuadros');
      } else {
        // Lo normal en muchos televisores. Se anota para que al leer el
        // registro se sepa que se intentó y no que nadie lo pidió.
        logger.info('La pantalla no cambió de modo para '
            '${fps.toStringAsFixed(3)} cuadros (no hay modo mejor, o el '
            'aparato no deja)');
      }
    } catch (e) {
      logger.info('No se pudo ajustar la frecuencia de pantalla: $e');
    }
  }

  /// Devuelve la pantalla a su modo de siempre.
  ///
  /// **Hace falta sí o sí.** Sin esto el televisor queda a 24 Hz para TODO el
  /// sistema al salir del vídeo, y su propio menú se ve a tirones. Se llama al
  /// cerrar el reproductor, y el lado nativo tiene además su propia red por si
  /// la app se va sin pasar por acá.
  static Future<void> soltar() async {
    if (!_puesta) return;
    _puesta = false;
    try {
      await _canal.invokeMethod<void>('soltarFrecuenciaDePantalla');
      logger.info('Pantalla devuelta a su modo de siempre');
    } catch (e) {
      logger.info('No se pudo devolver la frecuencia de pantalla: $e');
    }
  }
}
