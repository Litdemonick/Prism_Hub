import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
    _escucharElCierre();
  }

  static _VigilaElCierre? _vigilante;

  /// Volcar cuando la app se va a segundo plano o se cierra.
  ///
  /// El volcado normal espera 2 segundos, y ese temporizador muere con el
  /// proceso: lo último que pasó no llegaba nunca al archivo. Es la peor
  /// pérdida posible, porque cuando lo que se está diagnosticando es un cierre
  /// inesperado, esas últimas líneas son las únicas que importan.
  ///
  /// El observador lo registra ACÁ y no en main.dart a propósito: así el
  /// registro se ocupa solo de no perder nada y nadie más tiene que acordarse
  /// de llamarlo.
  static void _escucharElCierre() {
    if (_vigilante != null) return;
    try {
      final vigilante = _VigilaElCierre();
      WidgetsBinding.instance.addObserver(vigilante);
      _vigilante = vigilante;
    } catch (_) {
      // Si el binding todavía no está listo se sigue sin esto: perder el
      // volcado al cerrar es molesto, quedarse sin registro entero es peor.
    }
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
    _recordar(log);
    _pending.writeln(log);
    _flushTimer ??= Timer(const Duration(seconds: 2), _flush);
  }

  /// Lo último que pasó, EN MEMORIA, para el visor en vivo.
  ///
  /// El visor no lee el archivo, y no por capricho: en depuración el archivo ni
  /// siquiera existe (todo va a la consola) y en producción solo se escribe si
  /// el interruptor de guardar está encendido. Mirando el archivo, el visor se
  /// vería vacío justo en los dos casos en los que más se lo necesita — alguien
  /// que abre "Ver registro" para entender qué está fallando AHORA no tiene por
  /// qué haber activado nada de antemano. Acá se guarda siempre, pase lo que
  /// pase con el archivo.
  ///
  /// Empieza vacío en cada arranque: es un visor de lo que está pasando, no el
  /// historial. Para lo de sesiones anteriores está Exportar.
  static const _topeEnMemoria = 1500;
  static final ListQueue<String> _memoria = ListQueue<String>();

  /// Sube con cada línea nueva y con cada limpieza.
  ///
  /// El visor compara este número para saber si hay algo nuevo en vez de
  /// redibujarse cada vez que mira. Con una racha de errores —que es cuando el
  /// visor se usa— eso es la diferencia entre repintar la lista cuatro veces
  /// por segundo o cientos.
  static int _generacion = 0;
  static int get generacion => _generacion;

  /// Copia de las líneas en memoria, de la más vieja a la más nueva.
  static List<String> get enMemoria => _memoria.toList(growable: false);

  static void _recordar(String log) {
    _memoria.addLast(log);
    while (_memoria.length > _topeEnMemoria) {
      _memoria.removeFirst();
    }
    _generacion++;
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
  /// con cosas adentro. Y vacía lo que muestra el visor, porque limpiar y
  /// seguir viendo las mismas líneas en pantalla se lee como que el botón no
  /// hizo nada.
  static Future<void> limpiar() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _memoria.clear();
    _generacion++;
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

    // En depuración, a la consola y nada más: ahí se está mirando la consola.
    if (kDebugMode) {
      debugPrint(batch);
      return;
    }

    // En perfilado, a los DOS lados.
    //
    // Antes solo iba a la consola, y perfilar es justamente cuando se está
    // diagnosticando algo: se corría `flutter run --profile`, pasaba el fallo, y
    // al ir a exportar el registro el archivo no tenía ni una línea de esa
    // corrida — quedaba solo en una consola que hay que copiar a mano. Ahora
    // queda escrito, así que se puede exportar y adjuntar como cualquier otra
    // sesión, sin perder el volcado por consola que sirve para verlo en vivo.
    if (kProfileMode) {
      debugPrint(batch);
    } else if (PrismHubStorage.getSetting(SettingKey.saveLog) != true) {
      // En release manda el interruptor de Ajustes. En perfilado no se pregunta:
      // esa compilación no la usa nadie para ver una serie, se usa para medir.
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

/// Vuelca el registro cuando la app deja de estar en primer plano.
///
/// Se atiende `paused` además de `detached`: en Android, `detached` muchas
/// veces NO llega —el sistema mata el proceso sin avisar— así que esperarlo
/// sería quedarse esperando algo que no pasa. `paused` sí llega siempre, y en
/// ese momento todavía se puede escribir.
class _VigilaElCierre with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(PrismLog.flush());
    }
  }
}
