import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prismhub/controllers/watch/motor/motor_de_video.dart';
import 'package:prismhub/utils/log.dart';
import 'package:video_player/video_player.dart';

/// El motor nativo de Android: ExoPlayer, vía `video_player`.
///
/// ── Por qué existe, con las dos razones medidas ─────────────────────────────
///
/// **1. Sabe saltar en HLS fMP4.** Pedirle a mpv que salte dentro de una lista
/// fMP4 lo deja clavado: es un bug de ffmpeg (`mpv-player/mpv#15184`),
/// etiquetado `down-upstream:ffmpeg` y cerrado como *not planned*. Este repo
/// tiene 482 líneas de rodeo por eso (`RecorteFmp4`), después de doce intentos
/// revertidos peleándolo de frente. ExoPlayer no usa ffmpeg para HLS: trae su
/// propio lector, y ahí ese bug no está.
///
/// **2. Dibuja sobre una superficie nativa, no sobre una textura.** El camino
/// de media_kit en Android hace dos pasadas de GPU por cuadro (mpv dibuja con
/// OpenGL ES, y después Flutter compone esa textura). Con una superficie
/// nativa el compositor del propio aparato pone la capa de vídeo, sin ninguna
/// de las dos.
///
/// ── Lo que NO hace, y hay que decirlo ───────────────────────────────────────
///
/// No declara [CapacidadDeMotor.tunelizado] todavía. La tunelización —que el
/// decodificador escriba directo al hardware y la sincronía de audio y vídeo
/// la haga el televisor— es de ExoPlayer, pero `video_player` no la expone en
/// su API pública. Prometerla acá sería mentir en el contrato.
///
/// Tampoco tiene el volumen amplificado por encima del original ni la captura
/// de fotogramas. Las dos se preguntan con [soporta] y quien las use ya tiene
/// que estar mirando eso.
///
/// ── Cómo se comporta si algo falla ──────────────────────────────────────────
///
/// [abrir] relanza si no pudo. Es a propósito: quien lo llama necesita poder
/// caer al otro motor, y para eso tiene que enterarse. Todo lo demás traga los
/// errores, porque una vez abierto un fallo al pausar no puede tumbar la app.
class MotorExo implements MotorDeVideo {
  VideoPlayerController? _cx;

  final _posiciones = StreamController<Duration>.broadcast();
  final _duraciones = StreamController<Duration>.broadcast();
  final _colchones = StreamController<Duration>.broadcast();
  final _reproducciones = StreamController<bool>.broadcast();
  final _cargas = StreamController<bool>.broadcast();
  final _volumenes = StreamController<double>.broadcast();
  final _errores = StreamController<String>.broadcast();
  final _finales = StreamController<bool>.broadcast();

  // Lo último avisado, para no repetir el mismo valor en cada latido.
  //
  // `video_player` avisa a ~4 Hz pase lo que pase, incluso en pausa. Sin este
  // filtro, cada uno de esos avisos despertaría a todo lo que escucha —la
  // barra, el guardado del historial, la notificación— para decirles que nada
  // cambió.
  Duration? _ultimaPosicion;
  Duration? _ultimaDuracion;
  Duration? _ultimoColchon;
  bool? _ultimoReproduciendo;
  bool? _ultimoCargando;
  double? _ultimoVolumen;
  bool _yaAvisoElFinal = false;

  @override
  String get nombre => 'exoplayer';

  @override
  Future<void> abrir(
    String url, {
    Map<String, String>? cabeceras,
    bool arrancar = true,
  }) async {
    await _soltarElAnterior();
    _ultimaPosicion = null;
    _ultimaDuracion = null;
    _ultimoColchon = null;
    _ultimoReproduciendo = null;
    _ultimoCargando = null;
    _ultimoVolumen = null;
    _yaAvisoElFinal = false;

    final cx = VideoPlayerController.networkUrl(
      Uri.parse(url),
      // Sin las cabeceras muchas fuentes contestan que no: el Referer y el
      // User-Agent son lo que las convence de entregar el vídeo.
      httpHeaders: cabeceras ?? const {},
    );
    _cx = cx;
    cx.addListener(() => _mirarYAvisar(cx));
    // Se relanza a propósito: quien abre necesita poder caer al otro motor.
    await cx.initialize();
    if (arrancar) await cx.play();
  }

  /// Traduce el estado de `video_player` a los avisos de la fachada.
  ///
  /// El paquete no da streams separados: da UN aviso cuando algo cambió, y hay
  /// que mirar qué fue. Por eso se compara contra lo último visto.
  void _mirarYAvisar(VideoPlayerController cx) {
    final v = cx.value;

    if (v.hasError) {
      final texto = v.errorDescription ?? 'error desconocido';
      logger.severe('exoplayer: $texto');
      if (!_errores.isClosed) _errores.add(texto);
      return;
    }
    if (!v.isInitialized) return;

    if (v.position != _ultimaPosicion) {
      _ultimaPosicion = v.position;
      if (!_posiciones.isClosed) _posiciones.add(v.position);
    }
    if (v.duration != _ultimaDuracion) {
      _ultimaDuracion = v.duration;
      if (!_duraciones.isClosed) _duraciones.add(v.duration);
    }
    final colchon = _colchonDe(v);
    if (colchon != _ultimoColchon) {
      _ultimoColchon = colchon;
      if (!_colchones.isClosed) _colchones.add(colchon);
    }
    if (v.isPlaying != _ultimoReproduciendo) {
      _ultimoReproduciendo = v.isPlaying;
      if (!_reproducciones.isClosed) _reproducciones.add(v.isPlaying);
    }
    if (v.isBuffering != _ultimoCargando) {
      _ultimoCargando = v.isBuffering;
      if (!_cargas.isClosed) _cargas.add(v.isBuffering);
    }
    final vol = v.volume * 100;
    if (vol != _ultimoVolumen) {
      _ultimoVolumen = vol;
      if (!_volumenes.isClosed) _volumenes.add(vol);
    }

    // El final se avisa UNA vez.
    //
    // `isCompleted` se queda en true mientras el vídeo siga al final, así que
    // sin este candado se avisaría en cada latido y el encadenado al episodio
    // siguiente se dispararía en bucle.
    if (v.isCompleted && !_yaAvisoElFinal) {
      _yaAvisoElFinal = true;
      if (!_finales.isClosed) _finales.add(true);
    }
  }

  /// Hasta dónde llegó la descarga.
  ///
  /// `video_player` da una LISTA de tramos cargados, no un solo número: al
  /// saltar quedan huecos, y lo descargado puede ser «del 0 al 2 y del 10 al
  /// 15». La barra dibuja una sombra sola, así que se toma el tramo que
  /// contiene la posición actual — que es el único que de verdad sirve para
  /// seguir viendo desde donde se está.
  Duration _colchonDe(VideoPlayerValue v) {
    for (final tramo in v.buffered) {
      if (tramo.start <= v.position && tramo.end >= v.position) {
        return tramo.end;
      }
    }
    return v.position;
  }

  @override
  Future<void> soltar() async {
    await _soltarElAnterior();
    for (final c in [
      _posiciones,
      _duraciones,
      _colchones,
      _reproducciones,
      _cargas,
      _volumenes,
      _errores,
      _finales,
    ]) {
      if (!c.isClosed) await c.close();
    }
  }

  Future<void> _soltarElAnterior() async {
    final viejo = _cx;
    _cx = null;
    if (viejo == null) return;
    try {
      await viejo.dispose();
    } catch (e) {
      logger.info('exoplayer: no se pudo soltar el anterior: $e');
    }
  }

  /// Todo lo que no sea abrir traga el error.
  ///
  /// Una vez que el vídeo está andando, que falle un pausar o un salto no
  /// puede tumbar nada: se anota y se sigue.
  Future<void> _intentar(String que, Future<void> Function() accion) async {
    final cx = _cx;
    if (cx == null) return;
    try {
      await accion();
    } catch (e) {
      logger.info('exoplayer: $que falló: $e');
    }
  }

  @override
  Future<void> reproducir() => _intentar('reproducir', () => _cx!.play());

  @override
  Future<void> pausar() => _intentar('pausar', () => _cx!.pause());

  @override
  Future<void> parar() => _intentar('parar', () async {
        await _cx!.pause();
        await _cx!.seekTo(Duration.zero);
      });

  @override
  Future<void> saltarA(Duration donde) =>
      _intentar('saltar', () => _cx!.seekTo(donde));

  @override
  Future<void> ponerVolumen(double volumen) => _intentar('volumen', () {
        // La fachada habla de 0 a 100 (y más arriba es amplificar, que este
        // motor no puede); `video_player` habla de 0 a 1.
        return _cx!.setVolume((volumen / 100).clamp(0.0, 1.0));
      });

  @override
  Future<void> ponerVelocidad(double velocidad) =>
      _intentar('velocidad', () => _cx!.setPlaybackSpeed(velocidad));

  @override
  Duration get posicion => _cx?.value.position ?? Duration.zero;

  @override
  Duration get duracion => _cx?.value.duration ?? Duration.zero;

  @override
  Duration get colchon {
    final v = _cx?.value;
    return v == null ? Duration.zero : _colchonDe(v);
  }

  @override
  bool get reproduciendo => _cx?.value.isPlaying ?? false;

  @override
  bool get cargando => _cx?.value.isBuffering ?? false;

  @override
  double get volumen => (_cx?.value.volume ?? 1) * 100;

  @override
  int? get ancho => _cx?.value.size.width.toInt();

  @override
  int? get alto => _cx?.value.size.height.toInt();

  @override
  Stream<Duration> get posiciones => _posiciones.stream;

  @override
  Stream<Duration> get duraciones => _duraciones.stream;

  @override
  Stream<Duration> get colchones => _colchones.stream;

  @override
  Stream<bool> get reproducciones => _reproducciones.stream;

  @override
  Stream<bool> get cargas => _cargas.stream;

  @override
  Stream<double> get volumenes => _volumenes.stream;

  @override
  Stream<String> get errores => _errores.stream;

  @override
  Stream<bool> get finales => _finales.stream;

  @override
  Widget vista({
    required BoxFit ajuste,
    required Color fondo,
    Alignment alineacion = Alignment.center,
    Widget? encima,
  }) {
    final cx = _cx;
    // Todavía sin abrir, o abriendo: el fondo solo. Sin esto se vería un hueco
    // transparente mientras se resuelve el servidor.
    if (cx == null || !cx.value.isInitialized) {
      return ColoredBox(
        color: fondo,
        child: encima ?? const SizedBox.expand(),
      );
    }
    return ColoredBox(
      color: fondo,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // FittedBox con el tamaño real del vídeo: es lo que hace que
          // `ajuste` y `alineacion` signifiquen lo mismo que en el otro motor.
          // `VideoPlayer` a secas estira para llenar y no respeta ninguno de
          // los dos.
          FittedBox(
            fit: ajuste,
            alignment: alineacion,
            child: SizedBox(
              width: cx.value.size.width,
              height: cx.value.size.height,
              child: VideoPlayer(cx),
            ),
          ),
          if (encima != null) encima,
        ],
      ),
    );
  }

  @override
  bool soporta(CapacidadDeMotor cual) => switch (cual) {
        // Las dos razones por las que existe este motor.
        CapacidadDeMotor.saltoEnFmp4 => true,
        // ExoPlayer la tiene, pero `video_player` no la expone. Ver arriba.
        CapacidadDeMotor.tunelizado => false,
        CapacidadDeMotor.volumenAmplificado => false,
        CapacidadDeMotor.pistas => false,
        CapacidadDeMotor.captura => false,
      };
}
