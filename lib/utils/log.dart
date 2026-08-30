import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/sesiones_del_registro.dart';
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
  /// Escribe una línea tal cual, sin el encabezado de `logging`.
  ///
  /// ── Para qué hace falta ─────────────────────────────────────────────────
  ///
  /// Todo lo que pasa por `logger` sale con `prismhub INFO <fecha y hora>: `
  /// adelante. Para una línea de registro eso es exactamente lo que se quiere.
  /// Para el recuadro de presentación es lo que lo rompe: es un dibujo hecho
  /// con caracteres, y con un prefijo delante —de largo variable, porque los
  /// microsegundos no siempre ocupan lo mismo— cada línea arranca en una
  /// columna distinta y el recuadro deja de cerrar. Reportado en vivo: «el
  /// prism, el unicode, se corta».
  ///
  /// Pasa por el mismo saneado y el mismo camino que el resto: lo único que
  /// se saltea es el encabezado.
  static void crudo(String linea) => _queueLog(linea);

  /// Manda al registro TAMBIÉN lo que se escribe con `debugPrint`.
  ///
  /// ── Por qué hacía falta ─────────────────────────────────────────────────
  ///
  /// La app tiene medio centenar de `debugPrint` repartidos: fallos de red que
  /// se atrapan y se siguen, cosas que no se pudieron leer, avisos de por qué
  /// se tomó un camino y no otro. Nada de eso llegaba al archivo — quedaba
  /// solo en una consola que en un televisor o un teléfono nadie tiene
  /// abierta, justo los dos sitios donde el registro es la única herramienta.
  ///
  /// Pedido explícito: «debe ser full transparente para poder fixear bien la
  /// app en todas las plataformas». Esto cierra el agujero más grande que
  /// quedaba, sin tener que ir cambiando cincuenta llamadas de una en una — y
  /// atrapa además lo que escriben Flutter y los complementos.
  ///
  /// Pasa por el mismo saneado que todo lo demás, así que sumar esto no
  /// expone nada nuevo.
  static void capturarDebugPrint() {
    if (_debugPrintOriginal != null) return;
    final original = debugPrint;
    _debugPrintOriginal = original;
    debugPrint = (String? mensaje, {int? wrapWidth}) {
      // El propio volcado del registro usa debugPrint. Sin esta guarda, cada
      // línea volcada se volvería a encolar y de ahí a volcarse otra vez: una
      // vuelta infinita que además crece sola.
      if (!_volcando && mensaje != null && mensaje.isNotEmpty) {
        _queueLog('consola · $mensaje');
      }
      original(mensaje, wrapWidth: wrapWidth);
    };
  }

  static DebugPrintCallback? _debugPrintOriginal;
  static bool _volcando = false;

  static void _queueLog(String log) {
    final limpio = sanear(log);
    _recordar(limpio);
    _pending.writeln(limpio);
    _flushTimer ??= Timer(const Duration(seconds: 2), _flush);
  }

  // ── Lo que NO puede salir en el registro ─────────────────────────────────
  //
  // El registro se comparte para diagnosticar: se exporta, se pega en un
  // reporte, se manda por mensaje. Así que no puede llevar dos clases de cosa:
  //
  //  1. **Credenciales.** Las direcciones de los CDN suelen firmarse con un
  //     token en la consulta (`?token=…&expires=…`, `?md5=…`). Quien tenga esa
  //     línea puede bajar el vídeo haciéndose pasar por esta sesión.
  //  2. **Qué estaba viendo la persona.** La ruta de una dirección suele traer
  //     el nombre del título. Un registro compartido no tiene por qué contar
  //     eso de nadie.
  //
  // Y lo que SÍ tiene que quedar, porque es el diagnóstico: el servidor
  // (cuál falló), el formato (.m3u8, .mp4, .ts) y la forma del error.
  //
  // Va acá, en el único punto por el que pasan TODAS las líneas, y no en cada
  // sitio que registra algo: son decenas y alcanza con que a uno se le escape
  // para que la protección no sirva.
  static final _direcciones = RegExp(r'https?://[^\s"<>\]]+');
  static final _rutaDeUsuario =
      RegExp(r'([A-Za-z]:\\Users\\|/home/|/Users/)([^\\/\s]+)');

  /// Deja una línea de registro en condiciones de compartirse.
  ///
  /// Público para poder probarlo: es la clase de cosa que si se rompe en
  /// silencio nadie se entera hasta que ya se filtró algo.
  static String sanear(String linea) {
    var salida = linea.replaceAllMapped(_direcciones, (m) {
      final crudo = m.group(0)!;
      final uri = Uri.tryParse(crudo);
      if (uri == null || uri.host.isEmpty) return '‹dirección›';
      // La extensión del archivo se conserva: distinguir un .m3u8 de un .mp4
      // es la mitad de entender por qué un servidor no reprodujo.
      final ultimo = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final punto = ultimo.lastIndexOf('.');
      final formato =
          (punto > 0 && punto < ultimo.length - 1) ? ultimo.substring(punto) : '';
      // El puerto queda: un 127.0.0.1 con puerto es el relay local, y saber
      // que una dirección pasó por ahí importa.
      final donde = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      return '${uri.scheme}://$donde/…$formato';
    });
    // El nombre de usuario del sistema aparece en cualquier ruta de archivo.
    salida = salida.replaceAllMapped(
        _rutaDeUsuario, (m) => '${m.group(1)}‹usuario›');
    return salida;
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

  /// Borra la sesión de ahora, dejando el historial intacto.
  ///
  /// ── Por qué no borra el archivo entero ──────────────────────────────────
  ///
  /// [limpiar] tira todo, aperturas anteriores incluidas. Eso está bien para
  /// un botón de reseteo de fábrica y muy mal para el de esta pantalla:
  /// pedido explícito, «el historial no se limpia, siempre se guarda la
  /// info». Y tiene razón de fondo — el historial es justamente lo que
  /// explica un cierre, así que un botón que se lo lleva de paso destruye lo
  /// único que sirve para arreglar el problema que llevó a apretarlo.
  ///
  /// ── Y por qué se puede limpiar solo una zona ────────────────────────────
  ///
  /// [dejar] decide qué líneas de la sesión de ahora sobreviven. Se usa para
  /// limpiar solo la zona que se está mirando: quien está en «Reproductor»
  /// limpiando ruido de una prueba no quiere perder lo de las extensiones,
  /// que ni estaba viendo. Sin [dejar] no sobrevive ninguna, que es lo que
  /// corresponde estando en «Todo».
  ///
  /// [escribirCabecera] se llama con el archivo ya recortado y antes de
  /// devolver las supervivientes, para que la sesión quede empezada por su
  /// presentación y no por líneas sueltas sin contexto. Va acá adentro y no
  /// afuera porque el orden importa y repartirlo entre dos sitios es pedir
  /// que algún día se llamen al revés.
  static Future<void> limpiarSesionActual({
    bool Function(String)? dejar,
    void Function()? escribirCabecera,
  }) async {
    await flush();
    List<String> sobreviven = const [];
    try {
      final file = File(logFilePath);
      final texto = (await file.exists()) ? await file.readAsString() : '';
      final lineas = texto
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList(growable: false);
      final sesiones = partirEnSesiones(lineas);
      final anteriores = sesiones.length <= 1
          ? const <String>[]
          : sesiones
              .sublist(0, sesiones.length - 1)
              .expand((s) => s.lineas)
              .toList(growable: false);
      if (sesiones.isNotEmpty && dejar != null) {
        sobreviven =
            sesiones.last.lineas.where(dejar).toList(growable: false);
      }
      await file.writeAsString(
        anteriores.isEmpty ? '' : '${anteriores.join('\n')}\n',
        flush: true,
      );
    } catch (_) {
      // Si el archivo no se deja tocar se sigue igual: al menos la pantalla
      // queda limpia, que es lo que se pidió.
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _memoria.clear();
    _generacion++;
    escribirCabecera?.call();
    for (final l in sobreviven) {
      _queueLog(l);
    }
    await flush();
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
      _aLaConsola(batch);
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
      _aLaConsola(batch);
    }
    // ── El archivo se escribe SIEMPRE, en las cuatro plataformas ─────────
    //
    // Había un interruptor de Ajustes que lo decidía, y estaba al revés de lo
    // que hace falta: el archivo es lo ÚNICO que explica un cierre. La app se
    // cierra sola, se vuelve a abrir, y lo que pasó antes solo existe si quedó
    // escrito — en la memoria no, porque esa se fue con el proceso.
    //
    // O sea que el interruptor solo servía para que, justo cuando algo falla,
    // no hubiera nada que mirar. Y quien lo necesita no puede saber de
    // antemano que iba a necesitarlo.
    //
    // No cuesta: se escribe en tandas cada dos segundos, y el archivo se
    // recorta solo (ver _recortar). Y lo que se escribe va saneado, así que
    // guardarlo siempre no expone nada — ver `sanear`.
    try {
      final file = File(logFilePath);
      await file.writeAsString(batch, mode: FileMode.append, flush: false);
      if (await file.length() > _topeBytes) await _recortar(file);
    } catch (_) {
      // Best-effort — perder una tanda de log no debe romper nada más.
    }
  }

  /// Vuelca a la consola marcando que estamos volcando.
  ///
  /// La marca es lo que corta la vuelta infinita: mientras esté puesta, lo que
  /// salga por `debugPrint` no se vuelve a encolar. Ver [capturarDebugPrint].
  static void _aLaConsola(String batch) {
    _volcando = true;
    try {
      debugPrint(batch);
    } finally {
      _volcando = false;
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
