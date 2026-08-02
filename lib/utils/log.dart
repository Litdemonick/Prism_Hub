import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:path/path.dart' as path;

final logger = Logger('PrismHub');

class PrismLog {
  static final logFilePath = path.join(PrismHubDirectory.getDirectory, 'PrismHub.log');

  static final StringBuffer _pending = StringBuffer();
  static Timer? _flushTimer;

  static void ensureInitialized() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      final log =
          '${record.loggerName} ${record.level.name} ${record.time}: ${record.message} ${record.error ?? ''} ${record.stackTrace ?? ''}';
      _queueLog(log);
    });
  }

  // Bufferea en memoria y recién vuelca cada 2s como mucho, de forma
  // asíncrona — antes, EN AMBOS modos (debug Y release), cada línea de log
  // se procesaba una por una en el momento (writeAsStringSync bloqueante en
  // release; debugPrint por línea en debug). Con una racha de errores
  // repitiéndose seguido (ej. timeouts de red en cadena por un proxy roto,
  // reintentos de servidor de video, cada uno con ~20 líneas de stack
  // trace), eso eran decenas de operaciones bloqueantes por segundo en el
  // hilo de UI — se sentía como tirones/traba constante que empeoraba
  // cuanto más se acumulaban logs. Bufferizado, una racha de 50 errores en
  // un segundo genera un solo volcado (a archivo o consola) en vez de 50.
  static void _queueLog(String log) {
    _pending.writeln(log);
    _flushTimer ??= Timer(const Duration(seconds: 2), _flush);
  }

  /// Vuelca YA lo que haya pendiente, sin esperar los 2 segundos.
  ///
  /// Hace falta en dos momentos y en los dos se perdían líneas:
  ///
  ///  - Al cerrar la app: el temporizador moría con el proceso y esa tanda no
  ///    llegaba nunca al archivo. Justo la que más importa, porque si lo que
  ///    se está diagnosticando es un cierre inesperado, lo último que pasó es
  ///    lo único que sirve.
  ///  - Antes de exportar o de abrir el visor: si no, lo de los últimos
  ///    segundos —que es lo que la persona acaba de ver fallar— todavía está
  ///    en memoria y el archivo sale sin eso.
  static Future<void> flush() async {
    _flushTimer?.cancel();
    await _flush();
  }

  /// Borra el registro. Para el botón de reseteo.
  ///
  /// Tira también lo que estaba en memoria: si no, los 2 segundos anteriores
  /// se escribirían encima del archivo recién vaciado y quedaría "limpiado"
  /// con cosas adentro.
  static Future<void> limpiar() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    try {
      final file = File(logFilePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Que no se pueda borrar no puede tumbar la app.
    }
  }

  /// El registro entero, para mostrarlo o exportarlo.
  ///
  /// Vuelca primero lo pendiente, así lo que se lee incluye lo último que
  /// pasó y no una foto de hace dos segundos.
  static Future<String> leer() async {
    await flush();
    try {
      final file = File(logFilePath);
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// Tope del archivo.
  static const _topeBytes = 10 * 1024 * 1024;

  /// Cuánto se conserva al recortar.
  ///
  /// No se recorta justo hasta el tope: si quedara al borde, el recorte se
  /// dispararía otra vez con las líneas siguientes y estaríamos reescribiendo
  /// diez megas cada pocos segundos. Dejándolo a la mitad, el recorte vuelve a
  /// hacer falta recién dentro de mucho.
  static const _conservarBytes = 5 * 1024 * 1024;

  static Future<void> _flush() async {
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final batch = _pending.toString();
    _pending.clear();

    if (!kReleaseMode) {
      debugPrint(batch);
      return;
    }

    if (PrismHubStorage.getSetting(SettingKey.saveLog) != true) {
      return;
    }
    try {
      final file = File(logFilePath);
      await file.writeAsString(batch, mode: FileMode.append, flush: false);
      if (await file.length() > _topeBytes) await _recortar(file);
    } catch (_) {
      // Best-effort — perder una tanda de log no debe romper nada más.
    }
  }

  /// Al pasar el tope se tira lo VIEJO y se conserva lo reciente.
  ///
  /// Antes acá había un file.delete(): al cruzar los 10 MB se borraba el
  /// archivo entero y se empezaba de cero. O sea que en cualquier momento se
  /// podían perder meses de registro de golpe y sin aviso — y si alguien
  /// estaba por reportar un fallo justo en ese momento, se quedaba sin nada
  /// que adjuntar. Encima tiraba lo ÚLTIMO, que es siempre lo que sirve.
  ///
  /// Se corta en el primer salto de línea para no dejar una línea partida al
  /// principio, que se vería como basura en el visor.
  static Future<void> _recortar(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length <= _conservarBytes) return;
      var desde = bytes.length - _conservarBytes;
      const salto = 10; // '\n'
      while (desde < bytes.length && bytes[desde] != salto) {
        desde++;
      }
      if (desde < bytes.length) desde++;
      await file.writeAsBytes(bytes.sublist(desde), flush: true);
    } catch (_) {
      // Si el recorte falla se deja el archivo como está: tener un registro
      // grande es mucho mejor que no tener ninguno.
    }
  }
}
