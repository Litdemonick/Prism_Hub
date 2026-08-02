import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:prismhub/utils/log.dart';

/// La notificación del reproductor en Android.
///
/// Deja seguir viendo —o transmitiendo— con la app en segundo plano: se ve qué
/// se está reproduciendo, con la portada, y se puede pausar, saltar y cerrar
/// desde ahí sin volver a entrar. Antes, al salir de la app no quedaba ninguna
/// forma de controlar nada; transmitiendo a un televisor eso era especialmente
/// molesto, porque la imagen está en la otra pantalla y el teléfono es el mando.
///
/// **No reproduce nada por su cuenta.** Es solo la cara visible: cada botón
/// llama al reproductor que ya existe, sea el de acá o el televisor. Hacer que
/// reprodujera por su lado significaría tener dos reproductores que se pisan.
class NotificacionReproductor extends BaseAudioHandler {
  NotificacionReproductor._();

  static NotificacionReproductor? _instancia;

  /// Lo que hay que hacer cuando el usuario toca cada botón.
  ///
  /// Se enchufa desde el reproductor al abrirse y se suelta al cerrarse. Si no
  /// hay nadie enchufado, los botones no hacen nada en vez de reventar: la
  /// notificación puede sobrevivir un instante al reproductor que la creó.
  static _Mandos? _mandos;

  /// Quién enchufó los mandos que hay puestos ahora.
  ///
  /// Al pasar de una obra a otra conviven un momento dos reproductores: el que
  /// se abre y el que se está cerrando. Sin saber de quién son los mandos, el
  /// que cierra le borraba los del nuevo y la notificación quedaba dibujada
  /// pero sin responder a nada.
  static Object? _dueno;

  /// Enciende el servicio. Una sola vez en toda la vida de la app.
  ///
  /// Android no deja levantar y bajar esto a repetición: el servicio se crea al
  /// arrancar y después solo se le cambia lo que muestra.
  static Future<void> encender() async {
    if (_instancia != null) return;
    try {
      _instancia = await AudioService.init(
        builder: NotificacionReproductor._new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.prismhub.app.reproductor',
          androidNotificationChannelName: 'Reproducción',
          // Sin sonido ni vibración: es un panel de control, no un aviso.
          androidNotificationChannelDescription:
              'Controles de lo que estás viendo',
          // En pausa NO se suelta el primer plano. Es a propósito y va contra
          // lo que hace una app de música normal.
          //
          // Al pausar, este servicio sale de primer plano Y suelta el wakelock
          // (ver exitPlayingState en AudioService.java). Ahí Android queda libre
          // de congelar o matar el proceso, y transmitiendo eso rompe de verdad:
          // cuando el vídeo va POR el teléfono —las fuentes que exigen cabeceras
          // y todo lo reempaquetado a MPEG-TS— el televisor le pide cada pedazo
          // al servidor que corre dentro de la app. Si el proceso muere con el
          // vídeo en pausa, al volver a darle play el televisor ya no tiene de
          // dónde bajar.
          //
          // No queda colgado para siempre: al cerrar el reproductor se deja el
          // estado en reposo, y con eso el propio servicio hace stopSelf y suelta
          // el wakelock (ver esconder()).
          androidStopForegroundOnPause: false,
          // No fija: el usuario tiene que poder descartarla, y descartarla es lo
          // mismo que cerrar (ver onTaskRemoved).
          androidNotificationOngoing: false,
        ),
      );
    } catch (e) {
      // Que no se pueda crear la notificación NO puede impedir ver un video.
      // Se sigue sin ella.
      logger.warning('No se pudo encender la notificación del reproductor', e);
    }
  }

  static NotificacionReproductor _new() => NotificacionReproductor._();

  /// Conecta la notificación a un reproductor y la muestra.
  static void mostrar({
    required Object dueno,
    required String titulo,
    required String episodio,
    String? portada,
    required Duration duracion,
    required bool reproduciendo,
    required bool enTelevisor,
    required VoidCallback alReproducir,
    required VoidCallback alPausar,
    required void Function(Duration) alSaltar,
    required VoidCallback alSiguiente,
    required VoidCallback alAnterior,
    required VoidCallback alCerrar,
  }) {
    final yo = _instancia;
    if (yo == null) return;
    _dueno = dueno;
    _mandos = _Mandos(
      alReproducir: alReproducir,
      alPausar: alPausar,
      alSaltar: alSaltar,
      alSiguiente: alSiguiente,
      alAnterior: alAnterior,
      alCerrar: alCerrar,
    );
    yo.mediaItem.add(MediaItem(
      id: '$titulo|$episodio',
      title: episodio.isEmpty ? titulo : episodio,
      album: titulo,
      // Transmitiendo se dice, porque los botones actúan sobre el televisor y
      // no sobre el teléfono: sin decirlo, pausar desde acá se siente raro.
      artist: enTelevisor ? 'PrismHub · En el televisor' : 'PrismHub',
      duration: duracion > Duration.zero ? duracion : null,
      artUri: _aUri(portada),
    ));
    yo._refrescar(reproduciendo: reproduciendo, posicion: Duration.zero);
  }

  /// Actualiza lo que muestra sin rehacerla.
  static void actualizar({
    required Object dueno,
    required bool reproduciendo,
    required Duration posicion,
    Duration? duracion,
  }) {
    // Solo el que la puso. Un reproductor que se está cerrando todavía puede
    // emitir un último estado, y ese pisaría el del que acaba de empezar.
    if (!identical(_dueno, dueno)) return;
    final yo = _instancia;
    if (yo == null || _mandos == null) return;
    if (duracion != null && duracion > Duration.zero) {
      final actual = yo.mediaItem.value;
      if (actual != null && actual.duration != duracion) {
        yo.mediaItem.add(actual.copyWith(duration: duracion));
      }
    }
    yo._refrescar(reproduciendo: reproduciendo, posicion: posicion);
  }

  /// La saca de la barra. Se llama al cerrar el reproductor.
  ///
  /// Solo la esconde el que la puso: al pasar de una obra a otra el reproductor
  /// viejo se cierra DESPUÉS de que el nuevo ya se anunció, y sin esta
  /// comprobación el que se va apagaba la notificación del que acababa de
  /// empezar.
  static void esconder([Object? dueno]) {
    if (dueno != null && !identical(_dueno, dueno)) return;
    _mandos = null;
    _dueno = null;
    final yo = _instancia;
    if (yo == null) return;
    yo.mediaItem.add(null);
    yo.playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  static Uri? _aUri(String? portada) {
    if (portada == null || portada.isEmpty) return null;
    final uri = Uri.tryParse(portada);
    // Solo direcciones de red: una ruta suelta del disco no la puede leer el
    // sistema desde su propio proceso y deja la notificación sin imagen.
    if (uri == null || !uri.hasScheme) return null;
    return uri;
  }

  void _refrescar({required bool reproduciendo, required Duration posicion}) {
    playbackState.add(PlaybackState(
      // El orden es el que se ve en la notificación.
      controls: [
        MediaControl.skipToPrevious,
        if (reproduciendo) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      // Cuáles salen en la versión chica (la de una línea), donde solo caben
      // tres: las dos que más se usan y la de cerrar.
      androidCompactActionIndices: const [1, 2, 3],
      systemActions: const {MediaAction.seek},
      processingState: AudioProcessingState.ready,
      playing: reproduciendo,
      updatePosition: posicion,
    ));
  }

  // ── Lo que llega desde la notificación ────────────────────────────────────
  //
  // Todo pasa por los mandos del reproductor de turno. Envuelto en try porque
  // esto lo dispara el sistema: una excepción acá no tiene a nadie que la
  // atrape y se lleva puesta la app.

  @override
  Future<void> play() async => _seguro(() => _mandos?.alReproducir());

  @override
  Future<void> pause() async => _seguro(() => _mandos?.alPausar());

  @override
  Future<void> seek(Duration position) async =>
      _seguro(() => _mandos?.alSaltar(position));

  @override
  Future<void> skipToNext() async => _seguro(() => _mandos?.alSiguiente());

  @override
  Future<void> skipToPrevious() async => _seguro(() => _mandos?.alAnterior());

  @override
  Future<void> stop() async {
    _seguro(() => _mandos?.alCerrar());
    esconder();
  }

  /// Si el usuario descarta la notificación, es lo mismo que cerrar: dejarla
  /// andando sin forma de controlarla sería peor.
  @override
  Future<void> onTaskRemoved() async => stop();

  void _seguro(void Function() accion) {
    try {
      accion();
    } catch (e) {
      logger.warning('Fallo un botón de la notificación', e);
    }
  }
}

typedef VoidCallback = void Function();

class _Mandos {
  const _Mandos({
    required this.alReproducir,
    required this.alPausar,
    required this.alSaltar,
    required this.alSiguiente,
    required this.alAnterior,
    required this.alCerrar,
  });

  final VoidCallback alReproducir;
  final VoidCallback alPausar;
  final void Function(Duration) alSaltar;
  final VoidCallback alSiguiente;
  final VoidCallback alAnterior;
  final VoidCallback alCerrar;
}
