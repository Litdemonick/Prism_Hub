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
      final length = await file.length();
      if (length > 1024 * 1024 * 10) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort — perder una tanda de log no debe romper nada más.
    }
  }
}
