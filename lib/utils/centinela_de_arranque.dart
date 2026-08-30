import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_directory.dart';

/// Saber si la vez anterior la app se cerró mal.
///
/// ── El agujero que tapa ─────────────────────────────────────────────────────
///
/// `main.dart` ya engancha los tres caminos por los que un error de **Dart**
/// puede tumbar la app: `FlutterError.onError` (errores del árbol de widgets),
/// `PlatformDispatcher.instance.onError` (los del motor que no pasan por el
/// árbol) y `ErrorWidget.builder` (los de dibujado). Todos escriben al registro
/// antes de que se pierda nada.
///
/// Pero hay una clase de cierre que **no pasa por ninguno de los tres**, y es
/// justo la que se reportó en televisor («a veces se crashea o se reinicia la
/// app sola»):
///
///  - un fallo del código NATIVO — mpv, MediaCodec, el motor de Flutter — que
///    mata el proceso entero sin darle a Dart la oportunidad de enterarse;
///  - el sistema matando la app por memoria. En Android, y sobre todo en una
///    caja de televisión de 1-2 GB, el sistema cierra procesos sin avisar
///    cuando necesita memoria. Desde adentro es indistinguible de un cierre
///    normal: simplemente ya no hay proceso.
///
/// En los dos casos el registro queda cortado a mitad de frase y en el próximo
/// arranque no hay ni una línea que diga que algo salió mal. Sin esa señal, el
/// «se reinicia sola» es imposible de perseguir: no se sabe si pasó, ni cuándo,
/// ni qué estaba haciendo la app.
///
/// ── Cómo lo detecta ─────────────────────────────────────────────────────────
///
/// Con un archivo centinela, que es el truco de siempre para esto:
///
///  1. Al arrancar se escribe el archivo, con lo que se sabe del momento.
///  2. Al cerrar bien se borra.
///  3. Si en el arranque siguiente el archivo **todavía está**, es que la vez
///     anterior nunca llegó al paso 2 — o sea, el proceso murió de golpe.
///
/// Lo que quedó adentro dice además cuándo empezó esa sesión y qué versión era,
/// que es la mitad del diagnóstico.
///
/// ── Lo que NO puede hacer, dicho claro ──────────────────────────────────────
///
/// No puede decir POR QUÉ murió: cuando el proceso se va de golpe no queda
/// nadie para anotarlo. Solo puede decir QUE murió, cuándo empezó esa sesión y
/// cuánto duró. Con eso alcanza para saber si el problema existe de verdad, si
/// pasa siempre en el mismo momento, y para pedir el registro nativo del
/// aparato — que es donde sí está el motivo.
///
/// Tampoco puede distinguir un cierre forzado por el usuario (matar la app
/// desde el sistema) de un fallo. Se anota igual, y por eso el mensaje habla de
/// «no se cerró normalmente» y no de «se rompió».
class CentinelaDeArranque {
  CentinelaDeArranque._();

  static File get _archivo =>
      File(path.join(PrismHubDirectory.getDirectory, 'sesion_en_curso.json'));

  /// Cómo terminó la sesión ANTERIOR. Null hasta que corre [comenzar].
  static SesionAnterior? _anterior;
  static SesionAnterior? get sesionAnterior => _anterior;

  /// Marca que esta sesión empezó, y devuelve cómo terminó la de antes.
  ///
  /// Se llama lo más temprano posible del arranque, pero **después** de
  /// `PrismHubDirectory.ensureInitialized()`, que es de donde sale la carpeta.
  ///
  /// [version] va opcional a propósito. El global `packageInfo` recién existe
  /// bastante más adelante en `main()` (después de
  /// `ApplicationUtils.ensureInitialized`), y exigirlo obligaría a mover esta
  /// llamada hasta ahí — dejando sin cubrir todo el primer tramo del arranque,
  /// que es donde más duele un cierre mudo porque no hay ni pantalla todavía.
  /// Se prefiere cubrir desde temprano y anotar «desconocida» que cubrir menos.
  ///
  /// Nada de lo que pase acá adentro puede frenar el arranque: si el disco está
  /// lleno, sin permisos o el archivo quedó ilegible, se sigue como si no
  /// existiera. Una herramienta de diagnóstico que impide arrancar es peor que
  /// no tenerla.
  static Future<void> comenzar({String? version}) async {
    try {
      _anterior = await _leerAnterior();
      if (_anterior != null) {
        logger.severe(
          'La sesion anterior no se cerro normalmente: '
          'empezo ${_anterior!.comenzoEn.toIso8601String()}, '
          'duro ${_anterior!.duracion.inSeconds}s, '
          'version ${_anterior!.version}, '
          'aparato ${_anterior!.aparato}. '
          'Un cierre asi no pasa por los enganches de Dart: suele ser un fallo '
          'del codigo nativo o el sistema cerrando la app por memoria.',
        );
        if (_anterior!.rastro.isEmpty) {
          logger.severe('Sin rastro de lo que estaba haciendo.');
        } else {
          logger.severe('LO ULTIMO QUE HIZO LA APP ANTES DE CERRARSE:'
              ' ${_anterior!.rastro.join(" | ")}');
        }
      }
      _comenzoEn = DateTime.now();
      _version = version ?? 'desconocida';
      _rastro.clear();
      await _guardar();
    } catch (e) {
      // A propósito no se relanza: ver el comentario de arriba.
      logger.warning('CentinelaDeArranque.comenzar no pudo escribir: $e');
    }
  }

  static DateTime? _comenzoEn;
  static String _version = 'desconocida';

  /// Las últimas cosas que hizo la app, en orden.
  ///
  /// ── Para qué ────────────────────────────────────────────────────────────
  ///
  /// El centinela ya decía QUE la sesión anterior murió de golpe, pero no qué
  /// estaba haciendo. Y eso es la mitad del diagnóstico: no es lo mismo morir
  /// abriendo un vídeo, recorriendo el catálogo o cambiando de zona.
  ///
  /// Cuando el proceso se va de golpe —fallo nativo, o el sistema cerrando la
  /// app por memoria— no queda nadie para anotar nada. Así que se anota
  /// ANTES, sobre la marcha: cada paso importante deja su marca en el archivo,
  /// y si la sesión no vuelve, esas marcas son lo último que se sabe.
  ///
  /// ── Por qué solo las últimas ────────────────────────────────────────────
  ///
  /// Guardar todo obligaría a escribir un archivo cada vez más grande en cada
  /// paso, en un aparato al que justamente le falta aire. Con las últimas doce
  /// alcanza para ver el camino que llevó al cierre.
  static final _rastro = <String>[];
  static const _cuantasSeGuardan = 12;

  /// Anota algo que la app acaba de hacer.
  ///
  /// Va corto y sin datos del usuario: el archivo se comparte para
  /// diagnosticar. «abrió el reproductor», no qué episodio.
  static void marcar(String que) {
    try {
      if (_comenzoEn == null) return;
      final desde = DateTime.now().difference(_comenzoEn!).inSeconds;
      _rastro.add('+${desde}s $que');
      if (_rastro.length > _cuantasSeGuardan) _rastro.removeAt(0);
      // Se escribe en el momento, sin esperar: si el proceso muere en el paso
      // siguiente, esta marca tiene que estar ya en el disco.
      unawaited(_guardar());
    } catch (_) {
      // Un instrumento de diagnóstico no puede tumbar nada.
    }
  }

  static Future<void> _guardar() async {
    try {
      await _archivo.writeAsString(
        jsonEncode({
          'comenzoEn': (_comenzoEn ?? DateTime.now()).toIso8601String(),
          'version': _version,
          'aparato': _aparato,
          'rastro': _rastro,
        }),
        flush: true,
      );
    } catch (_) {
      // Sin permiso o sin espacio: se sigue igual.
    }
  }

  /// Marca que esta sesión dejó de estar en primer plano por las buenas.
  ///
  /// ── Se llama en `paused`, no en `detached`. Y es a propósito ─────────────
  ///
  /// En Android `detached` **no está garantizado**: el sistema puede matar el
  /// proceso sin entregarlo nunca (lo dice el comentario del propio
  /// `didChangeAppLifecycleState` de `_AppRoot`, ya de antes). Si el centinela
  /// se borrara solo ahí, en Android quedaría casi siempre sin borrar y todos
  /// los arranques dirían «se cerró mal». Un aviso que salta siempre no avisa
  /// nada.
  ///
  /// Pero además, borrar en `paused` es lo que hace la señal **útil**, no solo
  /// lo que la hace funcionar: que Android cierre una app que está en segundo
  /// plano para recuperar memoria es comportamiento normal y esperado, no un
  /// fallo. Contarlo como cierre malo llenaría el registro de ruido y taparía
  /// justo lo que se busca.
  ///
  /// Borrando en `paused`, el centinela solo sobrevive si la app murió
  /// **estando en primer plano** — que es exactamente el caso reportado:
  /// usando la app, mirando un episodio, y de golpe se reinicia.
  ///
  /// Es sincrónico a propósito: cuando llega este aviso puede quedar muy poco
  /// tiempo antes de que el proceso se vaya, y una escritura asíncrona a medio
  /// terminar dejaría el archivo puesto, marcando como fallo un cierre que
  /// estuvo perfecto.
  static void terminarBien() {
    try {
      final f = _archivo;
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Si no se puede borrar, el próximo arranque lo va a leer como un cierre
      // malo. Es un falso positivo molesto pero inofensivo, y preferible a
      // hacer ruido justo cuando la app se está yendo.
    }
  }

  static Future<SesionAnterior?> _leerAnterior() async {
    final f = _archivo;
    if (!await f.exists()) return null;
    try {
      final datos = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final comenzo = DateTime.tryParse(datos['comenzoEn'] as String? ?? '');
      if (comenzo == null) return null;
      return SesionAnterior(
        comenzoEn: comenzo,
        duracion: DateTime.now().difference(comenzo),
        version: datos['version'] as String? ?? 'desconocida',
        aparato: datos['aparato'] as String? ?? 'desconocido',
        rastro: (datos['rastro'] as List?)?.cast<String>() ?? const [],
      );
    } catch (e) {
      // Archivo a medio escribir: justamente lo que deja un cierre de golpe.
      // Cuenta como sesión anterior mal terminada, pero sin datos.
      logger.warning('Centinela ilegible (se cuenta como cierre malo): $e');
      return SesionAnterior(
        comenzoEn: DateTime.fromMillisecondsSinceEpoch(0),
        duracion: Duration.zero,
        version: 'desconocida',
        aparato: 'desconocido',
        rastro: const [],
      );
    }
  }

  static String get _aparato {
    if (kIsWeb) return 'web';
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }
}

/// Lo que se pudo recuperar de una sesión que no cerró bien.
class SesionAnterior {
  const SesionAnterior({
    required this.comenzoEn,
    required this.duracion,
    required this.version,
    required this.aparato,
    required this.rastro,
  });

  final DateTime comenzoEn;
  final Duration duracion;
  final String version;
  final String aparato;

  /// Lo último que hizo la app antes de morir, en orden.
  final List<String> rastro;
}
