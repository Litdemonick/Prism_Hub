import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/motor/motor_de_video.dart';

/// El motor de siempre: mpv, vía media_kit.
///
/// ── Es una envoltura, no una reescritura ────────────────────────────────────
///
/// Todo lo de acá adentro delega en el `Player` que el reproductor ya venía
/// usando. Eso es a propósito y es lo que hace seguro el cambio: el
/// comportamiento tiene que quedar **idéntico**, porque por debajo corre
/// exactamente el mismo código que antes. Si algo cambia al meter esta capa,
/// es un error, no una mejora.
///
/// ── Qué no puede, y por qué importa ─────────────────────────────────────────
///
/// Declara que NO tiene [CapacidadDeMotor.saltoEnFmp4] ni
/// [CapacidadDeMotor.tunelizado]. Las dos ausencias están medidas:
///
///  - El salto en fMP4 lo deja clavado — `mpv-player/mpv#15184`, bug de ffmpeg
///    cerrado como *not planned*. Por eso existe `RecorteFmp4`, que rehace la
///    lista para que empiece donde se quiere en vez de pedirle que salte.
///  - El tunelizado necesita una `SurfaceView`, y media_kit dibuja sobre una
///    textura de Flutter.
///
/// Declararlo acá es lo que permite que el rodeo del fMP4 se encienda **solo
/// cuando corre este motor**, en vez de estar siempre puesto.
class MotorMpv implements MotorDeVideo {
  MotorMpv({required this.player, required this.videoController});

  /// El reproductor de media_kit. Público porque hay cosas propias de mpv que
  /// el controlador todavía le pide directo —ajustar propiedades de libmpv,
  /// leer el caudal, las pistas— y que no tiene sentido meter en la interfaz
  /// común: el otro motor no las tiene.
  final Player player;
  final VideoController videoController;

  @override
  String get nombre => 'mpv';

  @override
  Future<void> abrir(
    String url, {
    Map<String, String>? cabeceras,
    bool arrancar = true,
  }) =>
      player.open(Media(url, httpHeaders: cabeceras), play: arrancar);

  @override
  Future<void> soltar() => player.dispose();

  @override
  Future<void> reproducir() => player.play();

  @override
  Future<void> pausar() => player.pause();

  @override
  Future<void> parar() => player.stop();

  @override
  Future<void> saltarA(Duration donde) => player.seek(donde);

  @override
  Future<void> ponerVolumen(double volumen) => player.setVolume(volumen);

  @override
  Future<void> ponerVelocidad(double velocidad) => player.setRate(velocidad);

  @override
  Duration get posicion => player.state.position;

  @override
  Duration get duracion => player.state.duration;

  @override
  Duration get colchon => player.state.buffer;

  @override
  bool get reproduciendo => player.state.playing;

  @override
  bool get cargando => player.state.buffering;

  @override
  double get volumen => player.state.volume;

  @override
  int? get ancho => player.state.width;

  @override
  int? get alto => player.state.height;

  @override
  Stream<Duration> get posiciones => player.stream.position;

  @override
  Stream<Duration> get duraciones => player.stream.duration;

  @override
  Stream<Duration> get colchones => player.stream.buffer;

  @override
  Stream<bool> get reproducciones => player.stream.playing;

  @override
  Stream<bool> get cargas => player.stream.buffering;

  @override
  Stream<String> get errores => player.stream.error;

  @override
  Stream<bool> get finales => player.stream.completed;

  @override
  Widget vista({required BoxFit ajuste, required Color fondo}) => Video(
        controller: videoController,
        fit: ajuste,
        fill: fondo,
      );

  @override
  bool soporta(CapacidadDeMotor cual) => switch (cual) {
        CapacidadDeMotor.volumenAmplificado => true,
        CapacidadDeMotor.pistas => true,
        CapacidadDeMotor.captura => true,
        // Ver el comentario de la clase: las dos están medidas.
        CapacidadDeMotor.tunelizado => false,
        CapacidadDeMotor.saltoEnFmp4 => false,
      };
}
