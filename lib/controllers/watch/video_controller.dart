// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_orientation/auto_orientation.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/data/providers/anilist_provider.dart';
import 'package:prismhub/data/providers/bt_server_provider.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/views/dialogs/bt_dialog.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/bt_server.dart';
import 'package:prismhub/utils/cast_aparato.dart';
import 'package:prismhub/utils/cast_formatos.dart';
import 'package:prismhub/utils/cast_hls_ts.dart';
import 'package:prismhub/utils/cast_log.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/cast_metadata.dart';
import 'package:prismhub/utils/notificacion_reproductor.dart';
import 'package:prismhub/utils/audio_hls.dart';
import 'package:prismhub/utils/bomba_de_datos.dart';
import 'package:prismhub/utils/cast_relay_server.dart';
import 'package:prismhub/controllers/watch/recorte_fmp4.dart';
import 'package:prismhub/utils/watch_state.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/data/services/stream_sniffer_service.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart'
    show isDirectStream, isKnownNativeServer;
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:crypto/crypto.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:flutter_hls_parser/flutter_hls_parser.dart';

class VideoPlayerController extends GetxController with WidgetsBindingObserver {
  static Future<void> _lastPlaybackShutdown = Future<void>.value();

  static Future<void> waitForPreviousShutdown() => _lastPlaybackShutdown;

  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playIndex;
  final int episodeGroupId;
  final ExtensionService runtime;
  final String anilistID;
  final bool autoResume;
  // Zona +18: viene de DetailPageController.isNsfw — ver el mismo campo en
  // ReaderController para el porqué.
  final bool isNsfw;

  VideoPlayerController({
    required this.title,
    required this.playList,
    required this.detailUrl,
    required this.playIndex,
    required this.episodeGroupId,
    required this.runtime,
    required this.anilistID,
    this.autoResume = false,
    this.isNsfw = false,
  });

  // Antes el tag de Get.put/Get.find era solo el título — dos títulos
  // iguales de extensiones distintas (o volver a entrar rápido al mismo
  // capítulo antes de que el onClose() async del controller viejo termine
  // de desmontarse) podían compartir tag y pisarse. Se compone con
  // detailUrl+episodeGroupId, que juntos identifican unívocamente ESTA
  // sesión de reproducción puntual.
  static String buildTag(String title, String detailUrl, int episodeGroupId) {
    return '$title|$detailUrl|$episodeGroupId';
  }

  // 播放器
  // Techo del volumen del reproductor, en por ciento del original.
  //
  // 100 es "como se grabó". Por encima de eso se amplifica, que es lo que hace
  // falta con material grabado bajo. Ver donde se aplica (volume-max) para por
  // qué justo 200.
  static const double volumenMaximo = 200;

  final player = Player();
  late final videoController = VideoController(player);

  final showSidebar = false.obs;
  final isOpenSidebar = false.obs;
  final isFullScreen = false.obs;

  /// Pantalla completa en Android: el vídeo solo, sin la hora ni la batería.
  ///
  /// ── Por qué es un botón APARTE de "llenar pantalla" ─────────────────────
  ///
  /// "Llenar pantalla" cambia cómo encaja la IMAGEN en el marco (BoxFit). Esto
  /// cambia el marco en sí, escondiendo las barras del sistema para que el
  /// vídeo ocupe hasta donde ellas estaban. Las dos cosas se pueden combinar.
  ///
  /// ── Por qué es MANUAL, y no automático como antes ────────────────────────
  ///
  /// Las barras del sistema se dejaron SIEMPRE visibles por defecto —a pedido,
  /// porque escondidas dejaban la única salida en una flecha fija encima del
  /// vídeo—. Este interruptor es la excepción: el usuario que sí quiere
  /// inmersión total la pide a propósito, tocando el botón, en vez de que la
  /// app se la imponga.
  final pantallaCompletaAndroid = false.obs;

  /// La orientación de la última vez que se llamó a pantallaSegunOrientacion.
  ///
  /// Esa función solo la llama la página en cada reconstrucción (ver
  /// _androidSegunOrientacion), así que no reacciona sola a que cambien
  /// OTRAS cosas de las que depende (ver el worker de llenarPantalla en
  /// onInit). Guardada acá, ese worker puede volver a pedir el modo correcto
  /// sin necesitar que la orientación haya cambiado también.
  bool _acostadoActual = false;
  late final index = playIndex.obs;

  // 快捷键
  late final keyboardShortcuts = <KeyboardKey, VoidCallback>{
    LogicalKeyboardKey.escape: () {
      // Estando en pantalla completa, el primer ESC solo sale de ahi — que es
      // lo que hace cualquier reproductor y lo que uno espera. Antes cerraba
      // el reproductor de una, asi que apretar ESC para volver a la ventana
      // terminaba sacandote del episodio.
      if (isFullScreen.value) {
        unawaited(toggleFullscreen());
        return;
      }
      unawaited(closeRoute());
    },
    LogicalKeyboardKey.keyF: () => toggleFullscreen(),
    // safePlay/safePause/playOrPause y no player.*: son los que saben si
    // hay un aparato conectado. Con player.* estas teclas movian el
    // reproductor de aca, que mientras se transmite esta parado.
    LogicalKeyboardKey.mediaPlay: () => safePlay(),
    LogicalKeyboardKey.mediaPause: () => safePause(),
    LogicalKeyboardKey.mediaPlayPause: () => playOrPause(),
    LogicalKeyboardKey.mediaTrackNext: () => player.next(),
    LogicalKeyboardKey.mediaTrackPrevious: () => player.previous(),
    LogicalKeyboardKey.space: () => playOrPause(),
    LogicalKeyboardKey.keyJ: () {
      final rate = position.value +
          Duration(
            milliseconds:
                (PrismHubStorage.getSetting(SettingKey.keyJ) * 1000).toInt(),
          );
      _seekFromShortcut(rate);
    },
    LogicalKeyboardKey.keyI: () {
      final rate = position.value +
          Duration(
              milliseconds:
                  (PrismHubStorage.getSetting(SettingKey.keyI) * 1000).toInt());
      _seekFromShortcut(rate);
    },
    LogicalKeyboardKey.arrowLeft: () {
      final rate = position.value +
          Duration(
              milliseconds:
                  (PrismHubStorage.getSetting(SettingKey.arrowLeft) * 1000)
                      .toInt());
      _seekFromShortcut(rate);
    },
    LogicalKeyboardKey.arrowRight: () {
      final rate = position.value +
          Duration(
              milliseconds:
                  (PrismHubStorage.getSetting(SettingKey.arrowRight) * 1000)
                      .toInt());
      _seekFromShortcut(rate);
    },
    // El tope era 100, o sea el volumen original: con una pista grabada baja no
    // quedaba nada por hacer. Ahora llega hasta volumenMaximo.
    LogicalKeyboardKey.arrowUp: () {
      // Transmitiendo, el volumen que importa es el del APARATO: el de aca no
      // sale por ningun lado porque el sonido lo hace el televisor.
      if (dlnaDevice.value != null) {
        ajustarVolumenCast(0.05);
        return;
      }
      final volume = player.state.volume + 5.0;
      player.setVolume(volume.clamp(0.0, volumenMaximo));
    },
    LogicalKeyboardKey.arrowDown: () {
      if (dlnaDevice.value != null) {
        ajustarVolumenCast(-0.05);
        return;
      }
      final volume = player.state.volume - 5.0;
      player.setVolume(volume.clamp(0.0, volumenMaximo));
    },
  };

  // 字幕
  final subtitles = <SubtitleTrack>[].obs;

  /// Los idiomas que ofrece la lista maestra de HLS.
  ///
  /// **Cómo están armados estos servidores, que es lo que explica todo.**
  /// Medido en vimeos el 2026-08-06, pidiendo cada lista que menciona el
  /// maestro y mirando qué pedacitos trae:
  ///
  ///   #EXT-X-MEDIA:TYPE=AUDIO,NAME="Español",…,URI=".../index-a1.m3u8"
  ///   #EXT-X-MEDIA:TYPE=AUDIO,NAME="English",…,URI=".../index-a2.m3u8"
  ///   #EXT-X-STREAM-INF:RESOLUTION=1280x720,…,AUDIO="audio0"
  ///   .../vtp8u5tj06i8_h/index-v1-a2.m3u8      → seg-1-v1-a2.ts
  ///
  /// El nombre del archivo lleva el audio adentro: `v1-a2` es **vídeo 1 con el
  /// audio 2 pegado**, y el audio 2 es el inglés. O sea que la variante que se
  /// reproduce ya viene doblada al inglés, y las pistas sueltas de arriba son
  /// la alternativa.
  ///
  /// Dos cosas se siguen de ahí:
  ///
  /// **Por qué mpv veía un solo audio.** La variante es autosuficiente, así que
  /// ffmpeg usa el audio que trae pegado y ni abre las otras.
  ///
  /// **Por qué decía «Español» y sonaba en inglés.** El maestro marca el
  /// español con `DEFAULT=YES` —porque para el reproductor de la web lo es— y
  /// nosotros dejábamos sonar el audio del vídeo, que es el a2. La etiqueta
  /// decía una cosa y el altavoz otra.
  ///
  /// Y de ahí sale el arreglo: cambiar de idioma es pedir la MISMA variante con
  /// otro número. Comprobado que `index-v1-a1.m3u8` existe, responde con el
  /// mismo vale y baja vídeo de verdad.
  final audiosHls = <PistaDeAudio>[].obs;

  /// Cuál está sonando. -1 es "no hay idiomas que elegir".
  ///
  /// Sale de mirar qué `-aN` traen las variantes del maestro, no de creerle al
  /// `DEFAULT=YES`: el que suena es el que está pegado al vídeo.
  final audioHlsElegido = (-1).obs;

  /// Si se está cambiando el idioma, para que se vea en pantalla.
  final cambiandoAudio = false.obs;

  /// Lo que se le pasó a mpv la última vez, para poder repetirlo con otro
  /// idioma sin volver a resolver el servidor.
  String? _fuenteUrl;
  Map<String, String>? _fuenteHeaders;

  /// Cambia el idioma del audio.
  ///
  /// **Se rehace la lista maestra apuntando al audio elegido.** El vídeo y el
  /// audio quedan en el mismo archivo, como venían, así que van sincronizados
  /// por construcción: no hay dos relojes que juntar.
  ///
  /// Antes se cargaba la pista suelta como audio externo. Eso son dos demuxers
  /// distintos, cada uno con su reloj, y al engancharlos en marcha el audio
  /// arrancaba donde él creía que iba: se escuchaba corrido, y encima el
  /// reproductor se trababa. Saltar a la posición justo después tampoco alcanzó.
  ///
  /// El maestro rehecho se guarda en un archivo y se abre desde ahí. Sus
  /// direcciones son absolutas, así que a mpv le da igual de dónde salga la
  /// lista: los pedacitos los sigue pidiendo al servidor con las mismas
  /// cabeceras.
  ///
  /// **No es instantáneo**, y no puede serlo: mpv tiene que volver a abrir. En
  /// la web sí lo es porque hls.js cambia la pista dentro de la misma sesión y
  /// conserva el reloj — mpv no tiene forma de hacer eso. A cambio, queda bien
  /// sincronizado y en el idioma que dice.
  Future<void> elegirAudioHls(int indice) async {
    if (indice < 0 || indice >= audiosHls.length) return;
    if (indice == audioHlsElegido.value) return;
    // Dos cambios encimados dejaban a mpv abriendo dos fuentes a la vez, y de
    // ahí salía que se trabara y no respondiera al play.
    if (cambiandoAudio.value) return;
    final actual = _fuenteUrl;
    final headers = _fuenteHeaders;
    if (actual == null || headers == null) return;

    cambiandoAudio.value = true;
    final donde = position.value;
    final quiere = audiosHls[indice];
    try {
      hasRenderedFrame.value = false;
      // Fuente nueva: se olvida el cuadro anterior y la red se rearma
      // sola con el primer cuadro de esta. Ver hasRenderedFrame.
      _hayCuadro = false;
      _posicionAlPrimerCuadro = null;
      _redDeLaRueda?.cancel();
      _redDeLaRueda = null;
      final conIdioma = AudioHls.conAudio(actual, quiere.numero);
      await player.open(Media(conIdioma, httpHeaders: headers));
      _fuenteUrl = conIdioma;
      audioHlsElegido.value = indice;
      if (donde > Duration.zero) await _saltarCuandoSePueda(donde);
      logger.info('audio cambiado a ${quiere.nombre} (a${quiere.numero})');
    } catch (e) {
      logger.warning('no se pudo cambiar el audio', e);
    } finally {
      cambiandoAudio.value = false;
    }
  }

  // 画质
  final currentQuality = "".obs;
  final qualityMap = <String, String>{};

  // 是否已经自动跳转到上次播放进度
  bool _isAutoSeekPosition = false;

  // Posición de continuación pendiente (segundos). Null = no hay nada guardado.
  // Se fija antes de cargar el video para evitar que el auto-seek la consuma.
  int? _pendingResumeSeconds;

  // Nombre del servidor que está EFECTIVAMENTE abierto/cargado en el player
  // ahora mismo (distinto de currentServerName, que cambia apenas se toca una
  // pestaña aunque todavía no se resolvió nada). Se usa para detectar cuando
  // el usuario vuelve al servidor que ya tenía andando, para no recargarlo.
  String? _lastOpenedServerName;
  // Señal para la UI: cuando tiene valor, mostrar el diálogo "¿Continuar?".
  final Rxn<int> resumePrompt = Rxn<int>(null);

  /// Si el tutorial de gestos esta tapando el reproductor ahora mismo.
  ///
  /// Vive en el controlador y no en el widget del tutorial porque hay tres
  /// piezas separadas que necesitan saberlo: el propio tutorial, y los controles
  /// de celular y de escritorio, que son los que abren el dialogo de "parece que
  /// estabas mirando esto". Ese dialogo salia ENCIMA del tutorial, y aceptarlo
  /// mandaba a reproducir con el tutorial todavia puesto.
  ///
  /// Lo pone y lo saca VideoPlayerConten, que es quien decide mostrarlo.
  final tutorialArriba = false.obs;

  // 信息列队
  final messageQueue = <Message>[];
  final Rx<Widget?> cuurentMessageWidget = Rx(null);

  // 播放速度
  final currentSpeed = 1.0.obs;
  final speedList = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  // torrent 媒体文件
  final torrentMediaFileList = <String>[].obs;
  final currentTorrentFile = ''.obs;
  String _torrenHash = "";

  // 调用 watch 方法获取到的数据
  ExtensionBangumiWatch? watchData;
  final error = "".obs;
  final isGettingWatchData = true.obs;
  // Último texto de error de media_kit — para deduplicar el toast y no parpadear.
  String _lastErrorEvent = '';
  // Cuenta errores de decodificación en ráfaga (audio/video corrupto) — sin
  // esto un stream roto podía inundar el log para siempre, uno por cada
  // frame fallido, sin límite y sin avisarle nada útil al usuario.
  int _decodeErrorBurstCount = 0;
  DateTime? _decodeErrorBurstStart;
  // Si el buffering se queda trabado (ej. mp4upload: el archivo es real y se
  // reconoce bien, pero el servidor deja de responder a mitad de descarga sin
  // tirar ningún error) media_kit no avisa nada — el usuario se queda mirando
  // el spinner para siempre sin ninguna salida. Este timer trata "más de 20s
  // en buffering seguido" como un fallo real del servidor.
  Timer? _bufferingStallTimer;
  Timer? _qualitySwitchTimer;

  // Selector de servidores (llenado desde X-Servers header de la extensión)
  final availableServers = <String, String>{}.obs; // nombre → embed URL
  final serverReferers = <String, String>{}; // nombre → referer (no observable)
  // nombre → si reproduce acá dentro (rayo) o abre el navegador (mundo), según
  // lo que diga la extensión. Solo están los que ella declara; del resto no hay
  // entrada y se sigue adivinando por nombre y host (ver isKnownNativeServer).
  //
  // Lo dice la extensión porque es la única que puede saberlo: el mismo nombre
  // de servidor reproduce nativo en un sitio y no en otro. "StreamWish" es el
  // caso de manual — en JKAnime anda y en HentaiLA y AnimeFenix termina en
  // premilkyway.com, que está bloqueado. Por nombre no hay forma de acertarle
  // a los dos.
  final serverNative =
      <String, bool>{}; // no observable, igual que serverReferers

  /// Si a este servidor le corresponde el rayo (reproduce acá dentro) o el
  /// mundo (abre el navegador interno).
  ///
  /// Manda lo que diga la extensión, que es la que midió ESE servidor en ESE
  /// sitio. Si no dice nada, se adivina por nombre y host como siempre.
  bool esServidorNativo(String name, String url) =>
      serverNative[name] ?? isKnownNativeServer(name, url);
  final currentServerName = ''.obs;
  final serverFailedMessage = ''.obs;
  // false entre "el servidor abrió" y "ya se ve el primer frame real" — media
  //_kit puede tardar un rato en pintar el primer cuadro aunque duration/
  // videoParams ya hayan llegado (streaming HLS: el buffering inicial pasa
  // SIN el flag de buffering en true, así que sin esto la pantalla quedaba
  // en negro sin ningún spinner, como si estuviera trabada de verdad).
  /// Ahora se apaga cuando el vídeo AVANZA, no cuando aparece el cuadro.
  ///
  /// mpv decodifica el primer cuadro y **se queda en pausa** llenando el
  /// colchón (`cache-pause-initial`, con `cache-pause-wait`). Apagando la
  /// rueda ahí, lo que se veía era: rueda, imagen congelada unos segundos, y
  /// recién después el vídeo. Parecía que se colgaba justo al empezar.
  ///
  /// El colchón NO se toca: está en 3 s porque con menos el vídeo se cortaba al
  /// primer bache en los servidores lentos. Lo que cambia es solo cuándo se
  /// apaga la rueda, para que tape la espera en vez de mostrar un cuadro que no
  /// se mueve.
  final hasRenderedFrame = false.obs;

  /// mpv ya decodificó el primer cuadro. No alcanza para apagar la rueda.
  bool _hayCuadro = false;

  /// Dónde estaba la posición cuando apareció el cuadro.
  ///
  /// Sirve para medir si el vídeo avanzó **de verdad**. Al principio alcanzaba
  /// con que la posición pasara de cero, y eso se cumple con cuarenta
  /// milisegundos: la rueda se apagaba al primer parpadeo y quedaba la imagen
  /// quieta los segundos que mpv tardaba en llenar el colchón. Medido el
  /// 2026-08-06 con Vimeos — «rueda apagada» a las 19.107 y el vídeo todavía en
  /// `posición: 0s` a las 25.469, seis segundos de imagen congelada sin rueda.
  Duration? _posicionAlPrimerCuadro;

  /// Cuánto tiene que avanzar para dar por hecho que está reproduciendo.
  ///
  /// Con menos entra el parpadeo de mpv al posicionarse; con mucho más, la
  /// rueda se quedaría puesta encima de un vídeo que ya se ve andando.
  static const _avanceParaCreerle = Duration(milliseconds: 700);

  /// El vídeo todavía no arrancó: se está esperando el primer cuadro.
  ///
  /// **Mientras esto sea cierto no se le hace caso a play, pausa ni saltos.**
  /// Ahí el reproductor está a medio abrir, y tocarlo es la forma más rápida de
  /// dejarlo en un estado del que no vuelve — pedirle pausa a mpv antes de que
  /// termine de colocarse, o un salto a una posición que todavía no existe.
  /// Quien lo toca no está haciendo nada raro: ve una rueda y prueba.
  ///
  /// Se corta con las mismas condiciones con las que los controles deciden
  /// mostrar la rueda: si hay un error en pantalla, un aviso de servidor caído
  /// o falta elegir servidor, NO se está cargando nada y el botón tiene que
  /// responder. Y casteando tampoco: ahí el reproductor de acá está parado a
  /// propósito y el que manda es el aparato.
  bool get esperandoElPrimerCuadro =>
      dlnaDevice.value == null &&
      !isGettingWatchData.value &&
      !hasRenderedFrame.value &&
      error.value.isEmpty &&
      serverFailedMessage.value.isEmpty &&
      !awaitingServerChoice.value &&
      !isWebViewActive.value;

  /// Si la barra de progreso NO se debe poder tocar ahora mismo.
  ///
  /// Un único sitio para las dos plataformas: la barra de escritorio y la del
  /// teléfono preguntan lo mismo, así que no puede pasar que una deje hacer lo
  /// que la otra bloquea.
  ///
  /// `seek()` ya ignora los saltos en estos estados, pero eso el usuario no lo
  /// ve: arrastraba la barra, la barra se movía, y el vídeo no iba a ningún
  /// lado. Bloquearla de verdad hace que el reproductor no mienta.
  ///
  /// Se bloquea mientras:
  ///  - se resuelve o se cambia de servidor (`isGettingWatchData`);
  ///  - se espera el primer cuadro de una fuente recién abierta;
  ///  - hay un salto con recorte en curso, que es una reapertura entera;
  ///  - está el diálogo de «¿continuar donde ibas?» esperando respuesta.
  bool get barraBloqueada =>
      isGettingWatchData.value ||
      esperandoElPrimerCuadro ||
      _saltandoConRecorte.value ||
      resumePrompt.value != null;

  /// Red de seguridad: la rueda no puede quedarse girando para siempre.
  ///
  /// Se apaga sola al avanzar el vídeo, y también cuando la app pausa a
  /// propósito (el diálogo de "¿continuar donde te quedaste?"). Pero si
  /// apareciera un caso que no previmos —una fuente que muestra el cuadro y
  /// nunca avanza, o un pausado que llega por un camino distinto—, esto la
  /// apaga igual y se vuelve al comportamiento de antes en vez de dejar al
  /// usuario mirando una rueda eterna.
  ///
  /// Seis segundos: el doble de lo que puede tardar el colchón.
  Timer? _redDeLaRueda;

  void _ponerRedDeSeguridadDeLaRueda() {
    if (hasRenderedFrame.value || _redDeLaRueda != null) return;
    _redDeLaRueda = Timer(const Duration(seconds: 6), () {
      _redDeLaRueda = null;
      if (_disposed || hasRenderedFrame.value) return;
      logger.info('rueda apagada: RED DE SEGURIDAD — el cuadro apareció y el '
          'vídeo no avanzó en 6 s');
      // Y se mide EN ESE INSTANTE, que es el que interesa: acá se sabe si
      // estaba en pausa, esperando datos, o parado por otra cosa.
      unawaited(_medir('no avanzó en 6 s'));
      hasRenderedFrame.value = true;
    });
  }

  /// El vídeo ya se está viendo de verdad: se apaga la rueda.
  ///
  /// Se dice POR QUÉ se apagó. Sin esto no había forma de saber, mirando un
  /// registro, si una compilación llevaba este cambio o el de antes — y eso ya
  /// costó una vuelta entera de pruebas.
  void _marcarQueYaSeVe([String porQue = 'el vídeo avanzó']) {
    if (hasRenderedFrame.value) return;
    if (!_hayCuadro) {
      logger.info('rueda: todavía no hay cuadro ($porQue), se sigue esperando');
      return;
    }
    _redDeLaRueda?.cancel();
    _redDeLaRueda = null;
    hasRenderedFrame.value = true;
    logger.info('rueda apagada: $porQue');
  }

  // Flag de buffering YA corregido con la posición real — ver
  // player.stream.buffering.listen más abajo. El flag crudo de mpv
  // (paused-for-cache) confirmado en vivo que a veces queda pegado en true
  // para siempre (el evento de "ya terminó de bufferizar" no siempre llega
  // por la plataforma), aunque el video ya esté reproduciendo frames nuevos
  // — eso hacía que el spinner de carga siguiera girando después de que el
  // contenido ya cargó. Si la posición avanzó hace poco, no puede estar
  // bufferizando de verdad, sin importar lo que diga el flag crudo.
  final isActuallyBuffering = false.obs;

  /// La imagen esta congelada aunque el video deberia estar corriendo.
  ///
  /// No se apoya en los avisos de mpv: con la red mal, mpv se queda bloqueado
  /// LEYENDO y deja de avisar nada — ni siquiera que esta llenando el buffer —,
  /// asi que la rueda no salia y la pantalla quedaba quieta sin ninguna
  /// explicacion. Esto mira lo unico que siempre se puede comprobar: que la
  /// posicion no avanza.
  final imagenCongelada = false.obs;
  Timer? _vigilanteDeAtasco;

  /// Cuanto tiene que estar quieta la posicion para darla por atascada. Poco
  /// para que la señal aparezca rapido, pero mas que un hipo de un fotograma.
  static const _atascoParaAvisar = Duration(seconds: 2);

  /// Y cuanto para dar el intento por perdido y ofrecer una salida. mpv esta
  /// puesto para reintentar solo, asi que sin este techo se queda intentando
  /// para siempre sin decir nada.
  static const _atascoParaRendirse = Duration(seconds: 25);

  /// Le pregunta a mpv por qué está pasando lo que está pasando.
  ///
  /// SOLO lee y escribe en el registro: no cambia una sola opción del
  /// reproductor. Es a propósito — hasta ahora, cada vez que el vídeo se paraba,
  /// no había un solo número para saber si faltaba red o sobraba trabajo, y se
  /// terminaba tocando la configuración a ciegas. Las cuatro cosas que lo
  /// distinguen:
  ///
  ///  - `demuxer-cache-duration`: cuántos segundos de vídeo hay descargados por
  ///    delante. En cero cuando se para = no llega la red.
  ///  - `cache-speed`: a qué velocidad está entrando. Comparado con el caudal de
  ///    la variante dice si el servidor da abasto o no.
  ///  - `video-bitrate`: qué variante eligió mpv. Clave con `hls-bitrate`: mpv
  ///    elige UNA al abrir y no la cambia nunca, aunque la red no la sostenga.
  ///  - `frame-drop-count`: si el equipo no llega a decodificar. Colchón lleno y
  ///    cuadros tirados = es la máquina, no la conexión.
  /// Muestreo periódico mientras se reproduce.
  ///
  /// Medir SOLO en el momento del parón no sirvió: al primer cuadro mpv todavía
  /// no calculó nada y devolvía siempre los mismos valores fijos (0.833078 s de
  /// colchón y un caudal de dos cifras, imposible para vídeo que se está
  /// viendo). Lo que hace falta es la CURVA: cómo evoluciona el colchón mientras
  /// corre. Si baja de 3 a 0 con el caudal por debajo de lo que pide la
  /// variante, es la conexión; si se mantiene lleno y aun así se para, no lo es.
  /// SACADO: el muestreo periódico se llevó puesta la app.
  ///
  /// Preguntarle propiedades a mpv desde un temporizador propio significa entrar
  /// a la librería nativa en un momento que no controla nadie. Si justo el
  /// reproductor se está cerrando, se entra con un manejador que ya no existe:
  /// la interfaz se cae y el audio sigue sonando de fondo, porque el proceso
  /// nativo sobrevive. Confirmado en vivo apenas se agregó, y coherente con los
  /// SIGSEGV al liberar el reproductor que este archivo ya documenta.
  ///
  /// La curva que hacía falta ya se obtuvo, así que no se reemplaza por una
  /// versión "más protegida": la medición que queda se dispara desde los avisos
  /// del propio reproductor, donde éste está vivo por definición.
  Timer? _muestreo;

  /// Deja escrito qué configuración quedó REALMENTE puesta en mpv.
  ///
  /// Se llama una vez al abrir. Ponerle una opción a mpv y que la acepte no es
  /// lo mismo: un nombre viejo, un valor que no entiende o una opción que no
  /// aplica a esta fuente se ignoran en silencio. Sin leerlas de vuelta se
  /// termina discutiendo sobre ajustes que quizá nunca estuvieron activos.
  Future<void> _confirmarAjustes() async {
    if (_disposed || _shutdownStarted || _playerDisposed) return;
    if (player.platform is! NativePlayer) return;
    final np = player.platform as NativePlayer;
    try {
      final ajustes = <String>[];
      for (final nombre in const [
        'cache',
        'cache-secs',
        'cache-pause-initial',
        'cache-pause-wait',
        'demuxer-readahead-secs',
        'demuxer-max-bytes',
        'hls-bitrate',
        'demuxer-lavf-o',
        // Para poder ver si la preferencia de idioma quedó puesta de verdad, en
        // vez de suponerlo cuando algo suena en inglés.
        'alang',
      ]) {
        final valor = (await np.getProperty(nombre)).trim();
        ajustes.add('$nombre=${valor.isEmpty ? '—' : valor}');
      }
      logger.info('mpv quedó con: ${ajustes.join(' · ')}');
    } catch (e) {
      logger.info('no se pudo releer la configuración de mpv: $e');
    }
  }

  Future<void> _medir(String motivo) async {
    // Tres candados antes de entrar a la librería nativa, no uno.
    //
    // Con el reproductor cerrándose, preguntarle una propiedad entra a libmpv
    // con un manejador que puede estar ya liberado: la app se cae y el audio
    // sigue sonando de fondo. Por eso además de _disposed se miran las marcas
    // del apagado, que se ponen ANTES de liberar nada.
    if (_disposed || _shutdownStarted || _playerDisposed) return;
    if (player.platform is! NativePlayer) return;
    final np = player.platform as NativePlayer;
    try {
      String d(String v) => v.trim().isEmpty ? '—' : v.trim();
      final colchon = d(await np.getProperty('demuxer-cache-duration'));
      final caudal = d(await np.getProperty('cache-speed'));
      final bitrate = d(await np.getProperty('video-bitrate'));
      final tirados = d(await np.getProperty('frame-drop-count'));
      // **El ESTADO del reproductor, no solo cuánto lleva descargado.**
      //
      // Sin esto se discutió tres veces sobre por qué el vídeo no arrancaba
      // mirando únicamente el colchón, y las tres se cambió el ajuste
      // equivocado. Estas cuatro dicen sin ambigüedad si está en pausa, si está
      // esperando datos, o si está esperando otra cosa:
      //
      //   pause             lo pausó alguien (la app o quien mira)
      //   paused-for-cache  mpv esperando datos
      //   core-idle         no está decodificando nada
      //   time-pos          el segundo exacto, con decimales
      final pausa = d(await np.getProperty('pause'));
      final porCache = d(await np.getProperty('paused-for-cache'));
      final quieto = d(await np.getProperty('core-idle'));
      final donde = d(await np.getProperty('time-pos'));
      logger.info('medición ($motivo) · colchón: $colchon s · entrando: '
          '$caudal B/s · variante: $bitrate bps · cuadros tirados: $tirados · '
          'calidad: ${currentQuality.value} · posición: '
          '${position.value.inSeconds}s · time-pos: $donde · pause: $pausa · '
          'paused-for-cache: $porCache · core-idle: $quieto');
    } catch (e) {
      logger
          .info('medición ($motivo): no se pudieron leer las propiedades — $e');
    }
  }

  void _arrancarVigilanteDeAtasco() {
    _vigilanteDeAtasco?.cancel();
    _muestreo?.cancel();
    _vigilanteDeAtasco = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed) return;
      // Casteando no aplica: el reproductor de aca esta parado a proposito.
      if (dlnaDevice.value != null) {
        if (imagenCongelada.value) imagenCongelada.value = false;
        return;
      }
      // Nada que vigilar si todavia no empezo, si esta pausado a proposito, o
      // si el video corre por el navegador.
      if (!hasRenderedFrame.value ||
          !isPlaying.value ||
          isWebViewActive.value ||
          isGettingWatchData.value) {
        if (imagenCongelada.value) imagenCongelada.value = false;
        return;
      }
      final ultimo = _lastPositionAdvanceAt;
      if (ultimo == null) return;
      final quieto = DateTime.now().difference(ultimo);
      final congelada = quieto >= _atascoParaAvisar;
      if (imagenCongelada.value != congelada) {
        imagenCongelada.value = congelada;
      }
      // Se rindio: se avisa UNA vez y se deja de insistir, para que el usuario
      // pueda elegir en vez de mirar una rueda eterna.
      if (quieto >= _atascoParaRendirse && !_atascoAvisado) {
        _atascoAvisado = true;
        logger.warning(
            'El video lleva ${quieto.inSeconds}s sin avanzar: se avisa');
        unawaited(_medir('imagen congelada'));
        sendMessage(Message(
          Text('video.stalled'.i18n),
          time: const Duration(seconds: 8),
        ));
      }
    });
  }

  bool _atascoAvisado = false;

  // Búsqueda en curso (arrastrar o tocar la barra de progreso). Hace falta
  // aparte de isActuallyBuffering porque ese flag se APAGA justo en este caso:
  // al buscar, la posición cambia, y el listener de posición interpreta
  // cualquier avance como "hay frames nuevos, no está bufferizando". Sin esto
  // la imagen se congelaba unos segundos sin ninguna señal de que estaba
  // cargando.
  final isSeeking = false.obs;
  Timer? _seekWatchdog;
  // Primera posición que llega DESPUÉS del salto. Apagar la rueda en cuanto
  // la posición cambia no servía: al saltar, mpv actualiza la posición al
  // destino de inmediato —antes de reportar que está bufferizando—, así que
  // la condición de apagado se cumplía en milisegundos y la rueda se iba
  // justo antes de que la imagen se congelara. Se espera a la SEGUNDA
  // posición distinta: esa ya es reproducción de verdad avanzando.
  Duration? _positionAfterSeek;

  /// Adonde quiere llegar el usuario, mientras siga tocando.
  ///
  /// Los saltos seguidos se JUNTAN en uno solo. Tocar cinco veces "+10s" tiene
  /// que llevar 50 segundos adelante, no disparar cinco busquedas: cada una
  /// tarda —y casteando encima rearma el flujo entero— asi que mandarlas todas
  /// dejaba la imagen congelada un rato largo y a veces terminaba en cualquier
  /// lado, porque cada toque se calculaba sobre una posicion que todavia era la
  /// vieja.
  Duration? _destinoDeSalto;
  Timer? _juntadorDeSaltos;

  /// Cuanto se espera a que el usuario deje de tocar antes de mandar el salto.
  ///
  /// Corto a proposito: mas que esto y un solo toque se siente lento.
  static const _esperaEntreSaltos = Duration(milliseconds: 350);

  /// Si la barra esta mostrando adonde VA en vez de donde esta.
  ///
  /// Dura desde el primer toque hasta que el reproductor —o el televisor—
  /// informa que llego. No alcanza con soltarlo al mandar el salto: entre que
  /// se manda y el video llega siguen entrando posiciones viejas, y cada una
  /// haria volver la barra atras de un tiron antes de saltar adelante.
  bool get haySaltoPendiente => _destinoDeSalto != null;

  /// Cuanto margen se acepta para dar por llegado un salto.
  ///
  /// Un salto no cae nunca en el milisegundo exacto: el reproductor va al
  /// fotograma clave mas cercano, y un televisor informa de a segundos.
  static const _margenDeSalto = Duration(seconds: 3);

  /// Mira si la posicion que acaba de informar ya es la del salto pedido.
  ///
  /// Devuelve true si esa posicion se puede usar para la barra. Mientras el
  /// salto siga en camino devuelve false y la barra se queda en el destino.
  bool _aceptarPosicion(Duration informada) {
    final destino = _destinoDeSalto;
    if (destino == null) return true;
    // Todavia juntando toques: no se mando nada, no puede haber llegado.
    if (_juntadorDeSaltos?.isActive ?? false) return false;
    if ((informada - destino).abs() > _margenDeSalto) return false;
    _destinoDeSalto = null;
    return true;
  }

  void markSeeking() {
    isSeeking.value = true;
    _positionAfterSeek = null;
    _seekWatchdog?.cancel();
    // Red de seguridad: si el servidor no responde nunca, la rueda no se
    // queda girando para siempre.
    _seekWatchdog = Timer(const Duration(seconds: 8), () {
      isSeeking.value = false;
      // Y que la barra vuelva a seguir al video: si el salto no llego nunca,
      // dejarla clavada en un destino al que nadie va es peor que mostrar la
      // verdad.
      _destinoDeSalto = null;
    });
  }

  // Los atajos de teclado llamaban a player.seek() DIRECTO, salteándose la
  // marca de búsqueda que sí hace seek(): con las teclas y las flechas la
  // imagen se congelaba sin ninguna rueda, aunque con la barra de progreso
  // funcionara. Todos pasan por acá.
  void _seekFromShortcut(Duration objetivo) {
    // Acotado al video: retroceder al principio daba un tiempo NEGATIVO, y
    // varios aparatos rechazan eso en vez de ir al inicio.
    final dur = duration.value;
    var to = objetivo < Duration.zero ? Duration.zero : objetivo;
    if (dur > Duration.zero && to > dur) to = dur;
    final salto = (to - position.value).inSeconds;
    _anunciarSalto(salto);
    // seek() del controlador y NO player.seek(): el primero sabe si hay un
    // aparato conectado y le habla a el. Con player.seek() las teclas movian el
    // reproductor de aca, que mientras se transmite esta parado — o sea que en
    // PC adelantar y retroceder no hacian absolutamente nada al castear.
    //
    // markSeeking lo hace seek() por dentro, asi que aca ya no va.
    unawaited(seek(to));
  }

  // Cuántos segundos saltó el último atajo, para mostrarlo en pantalla. Vive
  // en el controller y no en la vista porque el salto se dispara desde acá
  // (los atajos de teclado son del controller) y así la misma señal sirve en
  // escritorio y en celular.
  final lastSkipSeconds = Rx<int?>(null);
  Timer? _skipBadgeTimer;

  /// Cuánto volumen tiene el reproductor de acá, para mostrarlo un momento.
  ///
  /// En PC no había ninguna señal: se tocaban las flechas o se movía el
  /// deslizador y el sonido cambiaba sin que nada dijera en cuánto quedó.
  ///
  /// Null cuando no hay nada que mostrar. Transmitiendo se queda siempre en
  /// null: ahí el volumen que importa es el del televisor y ese ya se avisa
  /// dentro del panel de casteo (ver [ajustarVolumenCast]).
  final avisoVolumen = RxnString();
  Timer? _avisoVolumenTimer;

  /// El último volumen visto, para no avisar del valor con el que se abre.
  double? _ultimoVolumen;

  /// Escucha el volumen del reproductor y lo anuncia cuando cambia.
  ///
  /// Se engancha al flujo y no a cada botón a propósito: así queda cubierto
  /// todo lo que lo mueva —las flechas, el deslizador, o lo que se agregue
  /// después— sin tener que acordarse de avisar en cada sitio.
  void _seguirVolumenLocal() {
    _addSubscription(player.stream.volume.listen((v) {
      if (_disposed) return;
      // Transmitiendo manda el volumen del televisor, que se avisa aparte.
      if (dlnaDevice.value != null) return;
      final antes = _ultimoVolumen;
      _ultimoVolumen = v;
      // El primer valor es con el que se abrió el reproductor, no un cambio.
      if (antes == null || (antes - v).abs() < 0.5) return;
      avisoVolumen.value = v > 100
          // Por encima de 100 es amplificación: sin el signo, 150 y 100 se
          // leerían igual de "normales".
          ? '+${(v - 100).round()}%'
          : '${v.round()}%';
      _avisoVolumenTimer?.cancel();
      _avisoVolumenTimer = Timer(const Duration(milliseconds: 1300), () {
        avisoVolumen.value = null;
      });
    }));
  }

  void _anunciarSalto(int segundos) {
    if (segundos == 0) return;
    lastSkipSeconds.value = segundos;
    _skipBadgeTimer?.cancel();
    _skipBadgeTimer = Timer(const Duration(milliseconds: 900), () {
      lastSkipSeconds.value = null;
    });
  }

  void _clearSeeking() {
    if (!isSeeking.value) return;
    isSeeking.value = false;
    _positionAfterSeek = null;
    _seekWatchdog?.cancel();
    _seekWatchdog = null;
  }

  final isVideoSurfaceMounted = false.obs;
  DateTime? _lastPositionAdvanceAt;
  Duration? _lastPositionSeen;
  DateTime? _lastHistoryTouchAt;
  bool _historyTouchInFlight = false;
  // true cuando hay más de un servidor y todavía no se intentó reproducir
  // ninguno — la UI muestra la lista para elegir en vez de un spinner. Se
  // apaga en cuanto el usuario elige uno (switchServer).
  final awaitingServerChoice = false.obs;
  // Cuando el sniffer headless no puede capturar el stream (CF-protected),
  // se emite la petición de abrir el WebView visible. El widget listener
  // (desktop/mobile controls) lo intercepta y llama openWebViewPlayer().
  final webViewFallback = Rxn<Map<String, String>>(null);
  // true después de la primera vez que se abrió el WebView para este fallback
  // — cambia el texto del botón de "Abre en el navegador" a "Volver al
  // navegador" cuando el usuario ya estuvo ahí y solo está retomando.
  final webViewOpenedOnce = false.obs;
  // true mientras la pantalla de WebView está efectivamente empujada arriba
  // de esta (no solo "ya se abrió alguna vez", como webViewOpenedOnce).
  // VideoPlayerConten lo usa para sacar el widget Video (y su textura nativa
  // de mpv/ANGLE) del árbol mientras tanto — confirmado en vivo (y con
  // reportes idénticos en los repos de flutter_inappwebview y media_kit)
  // que WebView2 y la textura de video de mpv compiten por GPU en Windows,
  // al punto de congelar la app entera ("No responde", ni con hot restart)
  // cuando ambos están activos en la misma ventana a la vez. player.stop()
  // solo no alcanza: para de decodificar, pero no libera la textura/
  // superficie nativa que sigue registrada mientras el widget siga montado.
  final isWebViewActive = false.obs;
  // URL de la página del episodio en el sitio (X-Page-Url). Se carga en un
  // WebView oculto y se sniffe su player como fallback universal.
  String _episodePageUrl = '';

  // 字幕配置
  final subtitleFontSize = 46.0.obs;
  final subtitleFontWeight = FontWeight.normal.obs;
  final subtitleTextAlign = TextAlign.center.obs;
  final subtitleFontColor = Colors.white.obs;
  final subtitleBackgroundColor = Colors.black.obs;
  final subtitleBackgroundOpacity = 0.5.obs;

  // 侧边栏初始化 tab
  final initSidebarTab = SidebarTab.episodes.obs;

  // 播放方式
  final playMode = PlaylistMode.none.obs;

  /// Si al terminar un episodio hay que pasar solo al siguiente.
  ///
  /// Se lee del ajuste cada vez y no se guarda en un campo: asi cambiarlo desde
  /// los ajustes vale de inmediato, sin tener que salir y volver a entrar al
  /// episodio. Apagado por defecto — que el reproductor siga solo es algo que
  /// se pide, no algo que deba pasar sin avisar.
  bool get autoPlayNextActivado =>
      PrismHubStorage.getSetting(SettingKey.autoPlayNext) == true;

  // 进度
  final position = Duration.zero.obs;

  // 总时长
  final duration = Duration.zero.obs;

  // Cuánto lleva descargado/cacheado el demuxer más allá de la posición
  // actual — mpv sigue llenando este buffer en segundo plano aunque el
  // video esté en pausa (pausar solo detiene decodificación, no la
  // descarga). Usado para la "sombra" de buffer en la barra de progreso.
  final buffer = Duration.zero.obs;

  // 播放状态
  final isPlaying = false.obs;

  // dlna 设备
  final dlnaDevice = Rx<AparatoDeCasteo?>(null);

  // 定时器
  Timer? _dlnaTimer;
  final List<Worker> _workers = [];
  final List<StreamSubscription> _subscriptions = [];

  // Ultimo fallo del relay ya avisado, para no repetir el mismo aviso una vez
  // por segundo mientras corre el timer de estado.
  String? _fallaDeCastAvisada;

  /// El vídeo de esta transmisión, reempaquetado a MPEG-TS.
  ///
  /// Null cuando se está mandando el original. Cuando viene, el televisor está
  /// recibiendo un flujo que se arma sobre la marcha: no tiene un largo con el
  /// que calcular a qué byte saltar, así que adelantar no es pedirle que salte
  /// sino **rearmarle el flujo desde otro pedacito**. Ver [_saltarEnCastTs].
  PlanTs? _planTs;

  /// En qué momento del episodio empieza el flujo que está recibiendo.
  ///
  /// El televisor cuenta desde cero porque para él cada salto es un vídeo
  /// nuevo; esto es lo que hay que sumarle para saber por dónde va de verdad.
  Duration _desfaseTs = Duration.zero;

  /// Enganchando con el aparato: mandarle el video y que arranque puede tardar
  /// varios segundos, y hasta ahora no se veia nada en ese rato — parecia que
  /// el toque no habia hecho efecto. Tambien evita que se dispare dos veces.
  final castConectando = false.obs;

  /// Resolviendo el episodio siguiente para mandarlo al mismo aparato.
  ///
  /// Aparte de castConectando porque el aviso tiene que decir otra cosa: no es
  /// "conectando con el dispositivo" sino "cambiando de episodio", que es lo
  /// que de verdad esta pasando y puede tardar bastante mas.
  final castCambiandoEpisodio = false.obs;

  /// Aviso breve que se muestra DENTRO del panel de casteo, en el renglon del
  /// estado. Fuera del panel quedaba una segunda caja oscura encima de la
  /// primera; adentro es una sola cosa que cambia de texto.
  final castAviso = Rxn<String>();

  /// Velocidad que informa el aparato, cuando no es la normal.
  ///
  /// Si desde el televisor se pone x2, x4..., la app no se enteraba: seguia
  /// diciendo "transmitiendo" como si nada, y el usuario veia la barra de
  /// progreso corriendo raro sin explicacion. El estado que devuelve el aparato
  /// trae la velocidad, asi que se lee de ahi.
  final castVelocidad = Rxn<String>();

  /// Saltando a otro punto del video EN el aparato.
  ///
  /// El televisor tarda en llegar y mientras tanto deja la imagen congelada; de
  /// este lado no pasaba nada y parecia que el salto se habia perdido. Con esto
  /// el panel muestra la rueda y dice que espere.
  final castBuscando = false.obs;
  Duration? _objetivoDeSalto;
  Timer? _castBuscandoTimer;

  /// Volumen del APARATO, de 0 a 100.
  ///
  /// Deslizando de arriba abajo con la transmision puesta, lo que se movia era
  /// el volumen del telefono — que no sale por ningun lado, porque el sonido lo
  /// esta haciendo el televisor. Ahora se le manda a el.
  final castVolumen = 50.obs;
  Timer? _volumenCastTimer;

  /// Velocidad pedida al aparato manteniendo apretado (1 = normal).
  final castVelocidadPedida = 1.obs;

  /// Se le mando el video y todavia no empezo a verse.
  ///
  /// Aceptar la orden y empezar a reproducir son dos cosas distintas: el
  /// aparato contesta enseguida y despues se toma lo suyo para bajar y llenar
  /// el buffer. Antes el aviso de carga se apagaba con la respuesta, asi que
  /// desaparecia a los pocos milisegundos mientras la pantalla grande seguia en
  /// negro. Esto se mantiene hasta que el aparato informa que esta
  /// REPRODUCIENDO de verdad.
  final castEsperandoPlay = false.obs;
  Timer? _esperaPlayTimer;

  /// Comprueba si el aparato llego a pedirnos el video. Ver connectDLNADevice.
  Timer? _pedidoCastTimer;

  /// La direccion que le mandamos NOSOTROS al aparato.
  ///
  /// DLNA no tiene ningun bloqueo: si otro telefono le manda otro video al
  /// mismo televisor, el segundo simplemente pisa al primero. Guardando lo que
  /// mandamos se puede comparar contra lo que el aparato dice estar
  /// reproduciendo y darnos cuenta de que ya no es nuestro.
  String? _urlEnviadaAlCast;

  /// Cada cuantas vueltas del sondeo se comprueba que el video siga siendo el
  /// nuestro. Cada segundo seria un pedido de mas por segundo al televisor para
  /// algo que no cambia casi nunca.
  static const _vueltasEntreControles = 5;
  int _vueltasDesdeElControl = 0;

  /// Posicion del ultimo momento en que se confirmo que el video era nuestro.
  ///
  /// Entre un control y el siguiente pueden pasar unos segundos, y si en el
  /// medio otro dispositivo tomo el televisor, la posicion que informa pasa a
  /// ser la del OTRO video. Guardar esa en el historial escribiria el progreso
  /// ajeno sobre el episodio propio, asi que al detectar el robo se vuelve a
  /// este valor, que si era nuestro.
  Duration _posicionUltimoControl = Duration.zero;

  /// Controles seguidos en los que el aparato dijo estar con otra direccion.
  /// Ver _comprobarQueSigaSiendoNuestro.
  int _desajustesSeguidos = 0;

  /// Lee el volumen que tiene puesto el aparato, para arrancar desde ahi.
  Future<void> _leerVolumenDelCast(AparatoDeCasteo aparato) async {
    try {
      final v = await aparato.leerVolumen();
      if (v != null) castVolumen.value = v.clamp(0, 100);
    } catch (e) {
      // Sin este dato se arranca desde el ultimo conocido: subir y bajar sigue
      // andando, solo que la primera vez puede dar un salto.
      logger.warning('El aparato no informo su volumen', e);
    }
  }

  /// Si este aparato acepta que le cambien el volumen.
  ///
  /// Se descubre probando —no hay forma de preguntarlo antes— y una vez que se
  /// sabe que no, se deja de intentar: seguir mandandole ordenes que rechaza en
  /// cada movimiento del dedo es inundarlo para nada.
  bool castVolumenSoportado = true;

  /// Sube o baja el volumen del aparato. [delta] va en fraccion (-1 a 1).
  void ajustarVolumenCast(double delta) {
    final aparato = dlnaDevice.value;
    if (aparato == null) return;
    if (!castVolumenSoportado) {
      castAviso.value = 'video.cast-volume-no'.i18n;
      Timer(const Duration(seconds: 3), () {
        if (castAviso.value == 'video.cast-volume-no'.i18n) {
          castAviso.value = null;
        }
      });
      return;
    }
    final nuevo = (castVolumen.value + (delta * 100).round()).clamp(0, 100);
    if (nuevo == castVolumen.value) return;
    castVolumen.value = nuevo;
    castAviso.value = '${'video.cast-volume'.i18n} $nuevo%';
    // Se manda al soltar, no en cada pixel.
    //
    // Arrastrar dispara decenas de eventos por segundo y cada uno seria un
    // pedido HTTP al televisor: se lo inundaba y el volumen llegaba tarde y a
    // los saltos. Con este respiro se manda solo el ultimo valor.
    _volumenCastTimer?.cancel();
    _volumenCastTimer = Timer(const Duration(milliseconds: 220), () async {
      var acepto = true;
      try {
        await aparato.ponerVolumen(castVolumen.value);
      } catch (e) {
        // Hay aparatos que directamente no dejan cambiarles el volumen desde
        // afuera. Antes el numero se movia igual y el televisor seguia como
        // estaba, asi que parecia que la app no obedecia.
        acepto = false;
        logger.warning('El aparato no acepto el volumen', e);
      }
      if (_disposed || dlnaDevice.value != aparato) return;
      if (!acepto) {
        castVolumenSoportado = false;
        castAviso.value = 'video.cast-volume-no'.i18n;
        Timer(const Duration(seconds: 3), () {
          if (castAviso.value == 'video.cast-volume-no'.i18n) {
            castAviso.value = null;
          }
        });
        return;
      }
      // El cartel se va solo un rato despues del ultimo movimiento.
      Timer(const Duration(milliseconds: 900), () {
        if (castAviso.value?.startsWith('video.cast-volume'.i18n) ?? false) {
          castAviso.value = null;
        }
      });
    });
  }

  /// Manda al aparato a x2, x4, x8... o de vuelta a la normal.
  ///
  /// Muchos aparatos solo aceptan la velocidad normal y contestan un error; en
  /// ese caso se avisa y se vuelve a 1, en vez de dejar creer que anda.
  Future<void> pedirVelocidadCast(int velocidad) async {
    final aparato = dlnaDevice.value;
    if (aparato == null) return;
    final acepto = await aparato.ponerVelocidad(velocidad);
    if (!acepto) {
      castVelocidadPedida.value = 1;
      castAviso.value = 'video.cast-speed-unsupported'.i18n;
      Timer(const Duration(milliseconds: 1800), () {
        if (castAviso.value == 'video.cast-speed-unsupported'.i18n) {
          castAviso.value = null;
        }
      });
      return;
    }
    castVelocidadPedida.value = velocidad;
  }

  void _empezoSaltoEnCast(Duration objetivo) {
    _objetivoDeSalto = objetivo;
    castBuscando.value = true;
    _castBuscandoTimer?.cancel();
    // Techo por si el aparato nunca informa haber llegado: mejor soltar el
    // aviso que dejarlo girando para siempre.
    _castBuscandoTimer = Timer(const Duration(seconds: 8), () {
      castBuscando.value = false;
      _objetivoDeSalto = null;
    });
  }

  void _revisarSaltoEnCast() {
    final objetivo = _objetivoDeSalto;
    if (!castBuscando.value || objetivo == null) return;
    // Llego: el aparato ya informa una posicion cerca de donde se le pidio.
    if ((position.value - objetivo).abs() <= const Duration(seconds: 3)) {
      _castBuscandoTimer?.cancel();
      castBuscando.value = false;
      _objetivoDeSalto = null;
    }
  }

  // Foto del casteo justo antes de empezar a cerrar, para que el historial
  // pueda guardar por donde iba el TELEVISOR. Ver _beginPlaybackShutdown.
  bool _casteabaAlCerrar = false;
  Duration _posicionCastAlCerrar = Duration.zero;
  Duration _duracionCastAlCerrar = Duration.zero;

  /// Si tiene sentido ofrecer el casteo AHORA.
  ///
  /// Regla: si el reproductor nativo no esta reproduciendo bien, castear
  /// tampoco va a andar — el aparato pide el mismo video por su cuenta y se va
  /// a topar con lo mismo. Ofrecer el boton igual solo lleva a una pantalla
  /// negra en el televisor y a un "no se pudo reproducir" sin explicacion, asi
  /// que se apaga y se dice por que.
  ///
  /// Se apoya en observables (duration, isGettingWatchData...) para que un Obx
  /// que lo lea se entere solo cuando cambia.
  bool get puedeCastear {
    // Ya conectado: el boton tiene que seguir vivo para poder cortar.
    if (dlnaDevice.value != null) return true;
    // Todavia resolviendo el servidor: no hay nada que mandar.
    if (isGettingWatchData.value) return false;
    if (watchData == null) return false;
    // El respaldo por WebView reproduce DENTRO de una pagina web, no hay una
    // direccion de video que el televisor pueda pedir.
    if (isWebViewActive.value || webViewFallback.value != null) return false;
    // Con duracion conocida es que mpv abrio el medio de verdad. Mientras siga
    // en cero, o no abrio o esta fallando.
    return duration.value > Duration.zero;
  }

  /// Por que no se puede castear, para el aviso del boton apagado.
  /// Si el botón de castear tiene que estar en pantalla.
  ///
  /// Mientras el vídeo todavía se está abriendo, **no**. Antes se dibujaba
  /// igual, apagado, y en el teléfono cada toque escupía un aviso: tocarlo tres
  /// veces mientras cargaba dejaba tres avisos encimados. Y no aportaba nada,
  /// porque es un estado que dura unos segundos y se resuelve solo.
  ///
  /// Cuando el motivo es PERMANENTE el botón sí se queda: en el respaldo por
  /// navegador no hay una dirección que mandarle al televisor, y ahí el aviso
  /// explica algo que no va a cambiar por esperar. Esconderlo dejaría al
  /// usuario buscando un botón que estaba hace un momento.
  bool get mostrarBotonDeCast {
    // Ya conectado: tiene que seguir para poder cortar.
    if (dlnaDevice.value != null) return true;
    if (isWebViewActive.value || webViewFallback.value != null) return true;
    return puedeCastear;
  }

  String get motivoSinCast {
    if (isGettingWatchData.value) return 'video.cast-wait'.i18n;
    if (isWebViewActive.value || webViewFallback.value != null) {
      return 'video.cast-webview'.i18n;
    }
    return 'video.cast-unavailable'.i18n;
  }

  // URL de relay activa (si el stream necesitó headers) — se limpia del
  // servidor local al desconectar, ver disconnectDLNADevice().
  String? _dlnaRelayUrl;

  @override
  void onInit() async {
    _enUso = this;
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      // ── Se abre COMO ESTÉ el teléfono, y se puede girar ────────────────
      //
      // Antes se BLOQUEABA la orientación en horizontal: girar no hacía nada y
      // el vídeo se veía siempre acostado. El modo inmersivo también se pedía
      // acá; ahora lo maneja la página según la orientación, en
      // `pantallaSegunOrientacion`, porque de pie hay que ver la barra de
      // estado y la de navegación.
      //
      // Antes acá se forzaba la horizontal, con lo que abrir el reproductor
      // teniendo el teléfono de pie daba un giro a acostado y —desde que se
      // permite el vertical— otro giro de vuelta a vertical. Dos giros y medio
      // segundo de pantalla dando vueltas para terminar donde ya estaba.
      //
      // Ahora no se fuerza nada: se sueltan las cuatro orientaciones y manda el
      // sensor. De pie abre de pie, acostado abre acostado, y girar funciona en
      // los dos sentidos. Que un vídeo se vea mejor acostado es cierto, pero
      // eso lo decide quien mira girando el teléfono, no la app girándoselo.
      await AutoOrientation.fullAutoMode();
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _initSettings();
    _initPlayer();
    // Configurar libmpv para evitar crashes en Linux:
    // - hwdec=no: evita error vaapi not supported by libswscale
    // - reconnect=0 (solo Linux): evita SIGSEGV ~16s post-EHOSTUNREACH cuando
    //   libmpv intenta reconectar HLS y falla en la limpieza interna. En
    //   Windows este SIGSEGV nunca se vio, y desactivar reconnect ahí tiene
    //   un costo real: confirmado en vivo (mp4upload) que un solo hipo de red
    //   de más de network-timeout (5s) deja el buffering trabado PARA
    //   SIEMPRE sin ningún error — reconnect es justo lo que permitiría
    //   recuperarse solo en vez de necesitar el watchdog de buffering.
    // - network-timeout: en Linux 5s ("fallo rápido", ver más arriba). En el
    //   resto, 5s resultó demasiado agresivo: confirmado en vivo (mp4upload)
    //   que el servidor arranca lento (~5.5 Mbps) y recién unos segundos
    //   después acelera de verdad (~30 Mbps sostenido) — con un timeout tan
    //   corto, mpv corta la conexión ANTES de que llegue a acelerar, y cada
    //   corte reinicia el ciclo lento desde cero. Un navegador real no tiene
    //   ese límite artificial y por eso le anda bien. 20s le da margen real
    //   para pasar la fase lenta sin ser tan largo como para tapar un host
    //   genuinamente caído (el watchdog de buffering de arriba igual corta a
    //   los 20s si after todo esto sigue sin progresar).
    if (player.platform is NativePlayer) {
      final np = player.platform as NativePlayer;
      if (Platform.isLinux) {
        // hwdec=no era el único caso que de verdad lo necesitaba (vaapi no
        // soportado por libswscale ahí) — estaba aplicándose SIN QUERER
        // también en Android/Windows, forzando decodificación por software
        // en todos lados. Eso es justo lo que hacía sentir el reproductor
        // menos fluido que YouTube (más CPU, más chance de tirar frames en
        // 1080p+) — con hwdec en 'auto-safe' fuera de Linux, mpv usa
        // MediaCodec en Android / D3D11VA en Windows cuando el dispositivo
        // lo soporta, cayendo solo a software si no.
        await np.setProperty('hwdec', 'no');
        await np.setProperty('network-timeout', '5');
        // seg_max_retry: ver el comentario largo en la rama de abajo. Vale
        // igual acá; no toca reconnect, que en Linux sigue apagado a propósito.
        await np.setProperty('demuxer-lavf-o',
            'reconnect=0,reconnect_delay_max=0,seg_max_retry=3');
      } else {
        await np.setProperty('hwdec', 'auto-safe');
        await np.setProperty('network-timeout', '20');
        // seg_max_retry: cuántas veces se reintenta UN pedacito que falló.
        //
        // Viene en 0 de fábrica, y en cero un pedacito que falla **se abandona**
        // sin un solo reintento. Medido en vivo con playmudos: la reproducción
        // venía bien y de golpe apareció "tcp: ffurl_read returned ..." — un
        // error de lectura de red a mitad de un pedacito. Un microcorte, el wifi
        // que cambia de canal o el CDN que cierra la conexión alcanzan para eso.
        // Con una conexión buena casi no pasa; con una mala, pasa todo el rato,
        // y cada vez se perdía vídeo.
        //
        // Tres intentos: suficiente para pasar un bache y acotado como para no
        // quedarse insistiendo contra un servidor de verdad caído.
        //
        // Lo que NO hace falta tocar, comprobado en la documentación de ffmpeg:
        // `http_persistent` (reusar la conexión entre pedacitos) y
        // `http_multiple` (bajar con varias conexiones a la vez) **ya vienen
        // encendidos** en el demuxer de HLS. O sea que aprovechar bien la
        // conexión ya estaba resuelto de fábrica, y agregar opciones del
        // protocolo HTTP por encima solo puede pisar lo que ya funciona.
        await np.setProperty(
            'demuxer-lavf-o',
            'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5,'
                'seg_max_retry=3');
      }
      // Muchos m3u8 de hosts (voe, netu, etc.) referencian segmentos en otro
      // dominio; mpv los marca "unsafe" y se niega a cargarlos.
      await np.setProperty('load-unsafe-playlists', 'yes');

      // Subir el volumen MÁS ALLÁ del original.
      //
      // Hay material que viene grabado muy bajo —doblajes caseros, capturas de
      // stream— y con el volumen del sistema al máximo igual no se escucha. El
      // tope de mpv es 100 (o sea, el original), así que no había nada que
      // hacer desde la app.
      //
      // Dos cosas distintas y las dos hacen falta:
      //
      //  - volume-max sube el techo. Se queda en 200: hasta ahí el aumento es
      //    aprovechable, y más arriba lo único que se gana es recortar los
      //    picos, que es exactamente "dañar el audio".
      //  - replaygain-clip evita justamente ese recorte cuando la pista ya
      //    venía fuerte y se la empuja igual.
      //
      // Esto solo levanta el techo; el volumen sigue donde estaba hasta que
      // alguien lo suba a mano.
      await np.setProperty('volume-max', '$volumenMaximo');
      await np.setProperty('replaygain-clip', 'no');
      // Que la app aparezca en el mezclador de volumen de Windows.
      //
      // Windows solo lista ahí a los programas con una SESIÓN DE AUDIO abierta,
      // y mpv cierra el dispositivo apenas deja de sonar algo: al pausar o al
      // terminar un vídeo, PrismHub desaparecía del mezclador y no había forma
      // de dejarle su propio volumen puesto. Con esto el dispositivo queda
      // abierto emitiendo silencio, así que la entrada se mantiene y el volumen
      // que le pongas ahí se respeta entre vídeos.
      //
      // SOLO Windows a propósito: en Android mantener la salida abierta retiene
      // el foco de audio y deja a la app sonando "en silencio" para el sistema,
      // que es justo lo que hace que otras apps no puedan reproducir bien.
      if (Platform.isWindows) {
        await np.setProperty('audio-stream-silence', 'yes');
      }
      // UA de navegador: CDNs de anime (luluvdo, streamwish, etc.) bloquean
      // el UA por defecto de mpv ("Lavf/xx.xx"). Usar el mismo UA que el app.
      final ua = PrismHubStorage.getUASetting();
      if (ua != null && ua.isNotEmpty) {
        await np.setProperty('user-agent', ua);
      }
      // ── mpv NO guarda ni restaura posiciones por su cuenta ────────────────
      //
      // mpv trae de fábrica el «reanudar donde ibas»: al cerrar un archivo
      // anota el minuto en su carpeta de watch-later, y al reabrirlo salta ahí
      // solo. Eso lo maneja la app —con su historial y su cartel— así que acá
      // no puede haber un segundo mecanismo decidiendo por su cuenta.
      //
      // Rompía en Android: cualquier episodio de AnimeAV1 arrancaba SIEMPRE en
      // el minuto 19, aunque se abriera desde cero y aunque se borrara el
      // historial de la app. La razón: con el recorte la fuente es
      // `http://127.0.0.1:PUERTO/lista_1.m3u8`, y ese nombre es el mismo para
      // todos los episodios, así que mpv creía que era siempre el mismo archivo
      // y le aplicaba la posición guardada de otro.
      //
      // Se cazó con un detector de saltos: la pila mostró que ningún código de
      // la app pedía ese salto — lo hacía mpv solo.
      await np.setProperty('resume-playback', 'no');
      await np.setProperty('save-position-on-quit', 'no');
      // Buffer para streaming (segmentos HLS de 5-10 s).
      //
      // Decía "en desktop sube solo porque hay más RAM" y no era cierto: el
      // valor estaba fijo en 50 MiB en todas las plataformas.
      //
      // Con eso, 4K no llega a andar bien aunque el stream lo ofrezca. Se pide
      // guardar 30 segundos por delante, pero 30 segundos de 4K a ~25 Mb/s son
      // unos 94 MiB: el tope de 50 MiB corta el adelanto a la mitad, y cada
      // bache de red se convierte en una pausa para cargar. En 1080p el mismo
      // tope sobra —de ahí que nunca se hubiera notado—, así que subirlo no
      // cambia nada de lo que ya funcionaba.
      //
      // En escritorio hay RAM para el caso completo. En el teléfono se sube
      // menos: alcanza para que 4K deje de cortarse sin quedarse con una
      // porción de memoria que el sistema pueda querer de vuelta.
      await np.setProperty('cache', 'yes');
      // Juntar un colchón ANTES de empezar, en vez de arrancar con lo puesto.
      //
      // mpv de fábrica arranca en cuanto puede decodificar el primer cuadro, sin
      // esperar a tener nada guardado por delante. Con un servidor rápido es lo
      // ideal. Medido acá con playmudos: el vídeo empezaba con **0,83 segundos**
      // de colchón — ochocientos milisegundos—, así que el primer bache lo
      // dejaba sin datos y se paraba enseguida. Una y otra vez, sin importar
      // cuánto se tocara el reconectar: el problema era arrancar sin nada.
      //
      // Con esto se esperan los segundos de cache-pause-wait antes del primer
      // cuadro. Es un intercambio consciente: se tarda un poco más en ver la
      // imagen, y a cambio no se corta a los dos segundos. Y solo se nota en los
      // servidores lentos — donde la descarga va holgada, ese colchón se llena
      // casi al instante y el arranque se siente igual que antes.
      await np.setProperty('cache-pause-initial', 'yes');
      // Cuánto se junta antes de arrancar, y cuánto se vuelve a juntar después
      // de quedarse sin datos. De fábrica es 1 segundo, que para el caso de
      // arriba es casi lo mismo que nada: reanudaría para volver a cortarse.
      // **Tres, y NO es lo que hace que el vídeo tarde en arrancar.**
      //
      // Se probó con ocho y con uno el 2026-08-06 buscando el parón del
      // arranque, y ninguno cambió nada:
      //
      //     con 8 → colchón 6,98 s, el vídeo quieto (esperaba llegar a 8)
      //     con 3 → colchón 2,92 s, el vídeo quieto
      //     con 1 → colchón 2,92 s, el vídeo quieto IGUAL
      //
      // Con el umbral en uno y casi tres segundos de colchón ya no hay nada que
      // esperar, así que lo que tiene parado el vídeo es otra cosa. Queda en
      // tres, que es el valor con el que se venía y el que evita que un parón a
      // mitad reanude para cortarse enseguida.
      await np.setProperty('cache-pause-wait', '3');
      await np.setProperty('cache-secs', '30');
      await np.setProperty(
          'demuxer-max-bytes', Platform.isAndroid ? '96MiB' : '192MiB');
      await np.setProperty('demuxer-readahead-secs', '10');
      // **El español primero, cuando la fuente trae varios idiomas.**
      //
      // Estos sitios son de contenido en español y quien los usa quiere el
      // latino, pero muchos servidores pegan el inglés como pista por omisión y
      // así arrancaba. Con esto mpv elige él mismo la pista en español si la
      // hay, y si no hay se queda con la que traiga — que es justo lo que se
      // busca: nunca queda mudo ni en un idioma que no está.
      //
      // Va además de la elección por dirección que hace `_comoAbrir` para los
      // maestros con `-aN`, y no en su lugar: aquélla solo sirve donde la
      // dirección lleva el número de pista, y ésta funciona en cualquier fuente
      // con varias pistas de verdad —un MP4 con dos audios, un maestro con
      // renditions separadas— y en las dos plataformas por igual.
      //
      // Se listan varias formas del mismo idioma porque los sitios las escriben
      // como se les ocurre: `es`, `spa`, `es-419`, `Latino`.
      await np.setProperty('alang', 'spa,es,es-419,es-LA,es-MX,esp,lat');
      // Con qué calidad ARRANCA solo. No es un tope.
      //
      // Antes arrancaba siempre en la más alta que ofreciera el stream, o sea
      // 4K cuando lo había. En un equipo que no lo aguanta eso se traduce en
      // fotogramas perdidos y tirones, y quien lo sufre no tiene por qué
      // saber que la causa es la resolución.
      //
      // Arrancando por debajo de ese límite, en la práctica cae en 1080p, que
      // cualquier equipo de los últimos años mueve sin despeinarse.
      //
      // El menú de calidades NO cambia: sigue listando todas las variantes que
      // publique el sitio, 4K incluido, y elegir una a mano abre esa variante
      // directamente sin pasar por esta preferencia. Así el que tiene equipo
      // para 4K lo elige igual, y el que no, deja de arrancar mal por defecto.
      //
      // Y si alguien prefiere arrancar siempre en la máxima, lo enciende en
      // Ajustes una vez y se acabó.
      final siempreMaxima =
          PrismHubStorage.getSetting(SettingKey.empezarEnMaximaCalidad) == true;
      await np.setProperty(
        'hls-bitrate',
        // 10 Mbps: por encima de lo que pide un 1080p normal y por debajo de
        // lo que pide un 4K. mpv elige la mejor variante que no lo supere.
        siempreMaxima ? 'max' : '10000000',
      );
      // Proxy de Ajustes → mpv: desbloquea CDNs filtrados por el ISP.
      // Sin esto el proxy solo llega a la resolución del embed, no al stream.
      final proxyType =
          PrismHubStorage.getSetting(SettingKey.proxyType)?.toString() ??
              'DIRECT';
      final proxyAddr =
          PrismHubStorage.getSetting(SettingKey.proxy)?.toString() ?? '';
      // El tipo se guarda como 'PROXY'/'SOCKS5'/'SOCKS4' (formato que espera
      // flutter_socks_proxy del lado Dio) — mpv/ffmpeg necesita un esquema de
      // URL real (http/socks5/socks4), no ese literal. Confirmado que con el
      // literal tal cual mpv no reconoce "PROXY://" y el proxy no llega al
      // stream aunque sí llegue a la resolución del embed vía Dio.
      const proxyScheme = {
        'PROXY': 'http',
        'SOCKS5': 'socks5',
        'SOCKS4': 'socks4',
      };
      final scheme = proxyScheme[proxyType];
      if (scheme != null && proxyAddr.isNotEmpty) {
        await np.setProperty('http-proxy', '$scheme://$proxyAddr');
      }
      // Y se relee lo que quedó puesto de verdad. Ver _confirmarAjustes.
      unawaited(_confirmarAjustes());
    }
    play();

    super.onInit();
  }

  void _addWorker(Worker worker) {
    _workers.add(worker);
  }

  void _addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  _initSettings() {
    subtitleFontSize.value =
        PrismHubStorage.getSetting(SettingKey.subtitleFontSize);
    subtitleFontColor.value = Color(
      PrismHubStorage.getSetting(
        SettingKey.subtitleFontColor,
      ),
    );
    final fontWeightText =
        PrismHubStorage.getSetting(SettingKey.subtitleFontWeight);
    subtitleFontWeight.value =
        fontWeightText == 'bold' ? FontWeight.bold : FontWeight.normal;
    subtitleBackgroundColor.value = Color(PrismHubStorage.getSetting(
      SettingKey.subtitleBackgroundColor,
    ));
    subtitleBackgroundOpacity.value = PrismHubStorage.getSetting(
      SettingKey.subtitleBackgroundOpacity,
    );
    subtitleTextAlign.value = TextAlign.values[PrismHubStorage.getSetting(
      SettingKey.subtitleTextAlign,
    )];

    _addWorker(ever(subtitleFontSize, (callback) {
      PrismHubStorage.setSetting(SettingKey.subtitleFontSize, callback);
    }));
    _addWorker(ever(subtitleFontColor, (callback) {
      PrismHubStorage.setSetting(
        SettingKey.subtitleFontColor,
        callback.toARGB32(),
      );
    }));
    _addWorker(ever(subtitleFontWeight, (callback) {
      PrismHubStorage.setSetting(
        SettingKey.subtitleFontWeight,
        callback == FontWeight.bold ? 'bold' : 'normal',
      );
    }));
    _addWorker(ever(subtitleBackgroundColor, (callback) {
      PrismHubStorage.setSetting(
        SettingKey.subtitleBackgroundColor,
        callback.toARGB32(),
      );
    }));
    _addWorker(ever(subtitleBackgroundOpacity, (callback) {
      PrismHubStorage.setSetting(
        SettingKey.subtitleBackgroundOpacity,
        callback,
      );
    }));
    _addWorker(ever(subtitleTextAlign, (callback) {
      PrismHubStorage.setSetting(
        SettingKey.subtitleTextAlign,
        callback.index,
      );
    }));
  }

  _initPlayer() {
    // 切换剧集
    _addWorker(ever(index, (callback) async {
      // Otro episodio: la notificación tiene que decir cuál, no quedarse con el
      // nombre del anterior. Se rehace en vez de actualizarse porque cambia el
      // título, y con él la ficha entera.
      unawaited(_mostrarNotificacion());
      // Casteando, el episodio nuevo tiene que ir tambien al televisor.
      //
      // Antes play() abria el episodio nuevo ACA mientras el televisor seguia
      // con el anterior: sonaban los dos a la vez, cada uno con otra cosa, y la
      // unica salida era desconectar y volver a elegir el aparato.
      final aparato = dlnaDevice.value;
      if (aparato == null) {
        await play();
        return;
      }
      // Transmitiendo, el episodio nuevo se resuelve con el reproductor de aca
      // EN SILENCIO.
      //
      // play() abre el video y arranca a reproducir; recien despues
      // connectDLNADevice lo para. En ese hueco sonaba el episodio nuevo por el
      // telefono encima de lo que ya estaba saliendo por el televisor.
      final volumenPrevio = player.state.volume;
      castCambiandoEpisodio.value = true;
      try {
        await player.setVolume(0);
      } catch (_) {
        // Si no se puede bajar, igual conviene seguir: peor es no encadenar.
      }
      try {
        await play();
        if (_disposed || watchData == null) return;
        // Sigue siendo el mismo aparato? Si se desconecto o se cambio mientras
        // se resolvia el episodio, mandarselo seria pisarle la eleccion.
        // Por identificador y no por instancia: comparar objetos daria
        // siempre distinto y el episodio nuevo nunca llegaria al televisor.
        if (dlnaDevice.value?.id != aparato.id) return;
        await connectDLNADevice(aparato);
      } finally {
        // Si el aparato acepto, el aviso sigue hasta que se vea de verdad —
        // lo apaga el sondeo. Si no acepto, se apaga aca mismo.
        if (!castEsperandoPlay.value) castCambiandoEpisodio.value = false;
        // El volumen vuelve siempre: si el casteo fallo y se sigue viendo aca,
        // dejarlo mudo seria peor que el problema que se estaba evitando.
        if (!_disposed) {
          try {
            await player.setVolume(volumenPrevio);
          } catch (_) {}
        }
      }
    }));

    // 切换倍速
    _addWorker(ever(currentSpeed, (callback) {
      player.setRate(callback);
    }));

    // 显示剧集列表
    _addWorker(ever(showSidebar, (callback) {
      if (!showSidebar.value) {
        isOpenSidebar.value = false;
      }
    }));

    // Prender/apagar "llenar pantalla" de pie cambia si el video puede
    // pintar debajo de la barra de estado (ver pantallaSegunOrientacion) —
    // sin este worker, tocar el interruptor en el panel no volvía a pedir
    // el modo del sistema hasta el próximo cambio de orientación.
    _addWorker(ever(llenarPantalla, (_) {
      if (_disposed) return;
      pantallaSegunOrientacion(acostado: _acostadoActual);
    }));

    // 自动切换下一集
    _addSubscription(player.stream.completed.listen((event) {
      // Cerrando: no se toca nada.
      //
      // Este aviso llega por un stream, y las suscripciones se cancelan en
      // onClose DESPUES de varios await. En esa ventana, un video que termina
      // justo al salir volvia a arrancar en bucle — el apagado ya habia bajado
      // el volumen, pero esto lo reanudaba y se seguia escuchando.
      if (_disposed) return;
      if (!event || playMode.value == PlaylistMode.single) {
        return;
      }
      if (playMode.value == PlaylistMode.loop) {
        player.seek(Duration.zero);
        safePlay();
        return;
      }

      // Algunos hosts cortan la conexión a mitad de capítulo y ffmpeg lo
      // reporta como "completed" (EOF) en vez de un error de red — sin este
      // chequeo, un corte de stream se sentía como si el reproductor
      // saltara solo al siguiente episodio. Si falta bastante para el
      // final real, no es un final real: tratarlo como el mismo corte a
      // mitad de stream que se recupera arriba (mismo mecanismo, misma
      // posición conservada).
      final dur = duration.value;
      final pos = position.value;
      if (hasRenderedFrame.value && dur > Duration.zero) {
        final remaining = dur - pos;
        final farFromEnd = remaining > const Duration(seconds: 15) &&
            remaining.inMilliseconds > dur.inMilliseconds * 0.08;
        if (farFromEnd) {
          logger.severe(
              '"completed" sospechoso a mitad de capítulo (faltan ${remaining.inSeconds}s de ${dur.inSeconds}s) — se trata como corte, no como fin real.');
          _midStreamResumeAt = pos;
          _failOrRetryServer(currentServerName.value);
          return;
        }
      }

      if (index.value == playList.length - 1) {
        sendMessage(Message(Text('video.play-complete'.i18n)));
        return;
      }
      // Solo si el usuario lo pidio. Ver SettingKey.autoPlayNext.
      if (!autoPlayNextActivado) {
        sendMessage(Message(Text('video.episode-finished'.i18n)));
        return;
      }
      if (!player.state.buffering) {
        index.value++;
      }
    }));

    // 讀取現在的畫質
    _addSubscription(player.stream.height.listen((event) async {
      if (player.state.width != null) {
        final width = player.state.width;
        // Mismo nombre que en el menú de calidades: antes acá decía
        // "1920x1080" y en el menú otra cosa, y no se entendía cuál estaba
        // puesta.
        final etiqueta = etiquetaCalidad(width, event);
        currentQuality.value = etiqueta.isEmpty ? "${width}x$event" : etiqueta;
      }
    }));

    _seguirVolumenLocal();

    // Primer cuadro real pintado.
    //
    // **Pero acá NO se apaga la rueda.** Ver `_hayCuadro`: mpv decodifica el
    // primer cuadro y se queda en pausa llenando el colchón, así que apagarla
    // en este momento mostraba la imagen congelada unos segundos antes de que
    // arrancara. Se apaga cuando el vídeo AVANZA.
    _addSubscription(player.stream.videoParams.listen((p) {
      final primerCuadro = !_hayCuadro;
      if ((p.w ?? 0) > 0 && (p.h ?? 0) > 0) {
        final antes = _hayCuadro;
        _hayCuadro = true;
        if (!antes) {
          logger.info('rueda: primer cuadro listo, se espera a que el vídeo '
              'avance para apagarla');
        }
        _ponerRedDeSeguridadDeLaRueda();
      }
      // Al primer cuadro se anota QUÉ variante eligió mpv. Es el dato que falta
      // para saber si un vídeo que se para eligió una calidad que la conexión no
      // sostiene — mpv no la cambia nunca por su cuenta.
      if (primerCuadro && _hayCuadro) {
        unawaited(_medir('arrancó'));
      }
      // El VR se decide ACA y no en el aviso de la altura.
      //
      // Alla se leia el ancho por separado, y si todavia no habia llegado en
      // ese instante el video no quedaba marcado como VR — y como la altura no
      // vuelve a cambiar, no se reintentaba nunca. Eso hacia que el interruptor
      // no apareciera en videos que si lo eran. Aca las dos medidas vienen
      // juntas en el mismo aviso, asi que no hay nada que se pueda cruzar.
      if ((p.w ?? 0) > 0 && (p.h ?? 0) > 0) {
        esVideoVr.value = _pareceVr(p.w, p.h, _pistasDeVr);
        // Y aca se decide que pasa con el recorte que traia el video ANTERIOR.
        //
        // Al abrir contenido nuevo el recorte se quita siempre (ver
        // _olvidarRecorteVr), asi que este es el momento en que se sabe si
        // corresponde volver a ponerlo: recien ahora se conocen las medidas del
        // video nuevo, que son las que necesita el recorte.
        //
        // Una sola vez por video. Este aviso llega mas de una vez, y reaplicar
        // el recorte en cada uno seria pelearle al usuario que lo apago a mano.
        if (_vrPorReaplicar) {
          _vrPorReaplicar = false;
          // Transmitiendo no: el recorte lo hace mpv y el televisor decodifica
          // por su cuenta, asi que no le llega. Igual que el interruptor, que
          // queda deshabilitado mientras se castea.
          if (esVideoVr.value && dlnaDevice.value == null) {
            unawaited(alternarVrUnaPantalla());
          }
        }
      }
    }));

    // 自动恢复上次播放进度 (solo cuando el diálogo no lo maneja)
    _addSubscription(player.stream.duration.listen((event) async {
      if (_isAutoSeekPosition || event.inSeconds == 0) return;
      // Si hay un diálogo de resume pendiente, él maneja el seek — no interferir.
      if (_pendingResumeSeconds != null || resumePrompt.value != null) {
        _isAutoSeekPosition = true;
        return;
      }

      // 获取上次播放进度
      final history = await DatabaseService.getHistoryByPackageAndUrl(
        runtime.extension.package,
        detailUrl,
      );

      if (history != null &&
          history.progress.isNotEmpty &&
          history.episodeId == index.value &&
          history.episodeGroupId == episodeGroupId) {
        final guardado = int.tryParse(history.progress) ?? 0;
        // ── Y acá el segundo candado ──────────────────────────────────────
        //
        // El de arriba (al guardar) evita que entren posiciones imposibles de
        // ahora en adelante, pero las que YA están en la base de alguien que
        // viene usando el app siguen ahí. Sin esto, esa gente seguiría
        // arrancando en cualquier lado hasta que el vídeo terminara una vez.
        //
        // Se compara contra la duración REAL, la que acaba de informar el
        // reproductor — este listener es justamente el de la duración, así que
        // acá ya se sabe cuánto dura el vídeo de verdad.
        //
        // Contra la duración GUARDADA no alcanzaba, y ese fue el agujero: en
        // la fuente donde el problema aparece, la posición y la duración se
        // inflan JUNTAS. Un progreso de 800 s sobre una duración guardada de
        // 850 s se ve perfectamente sano, pasa el control, y el vídeo salta a
        // un punto que no existe. Por eso en el teléfono empezó a arrancar
        // desde cero y en el escritorio seguía saltando: distinta base de
        // datos, distintos números guardados.
        //
        // Cinco segundos de margen: reanudar justo en el último instante es lo
        // mismo que verlo terminado.
        final duracionReal = event.inSeconds;
        final fueraDeRango = guardado < 0 || guardado > duracionReal - 5;
        if (fueraDeRango) {
          logger.info('historial: se ignora una posición guardada imposible '
              '($guardado s sobre $duracionReal s reales) y se empieza de cero');
        } else if (guardado > 0) {
          final recorte = _recorte;
          if (recorte != null) {
            // ── Con recorte NO se retoma por acá ─────────────────────────
            //
            // Este camino restaura la posición guardada con un `player.seek()`
            // en cuanto se conoce la duración. Con el recorte hace daño:
            //
            //  - es un salto de mpv sobre fMP4, o sea el que no funciona;
            //  - y se dispara en CADA apertura, incluidas las del failover.
            //    En el teléfono el codec AV1 no abre por hardware, así que hay
            //    failover casi siempre: se reabría, este listener leía el
            //    historial —que la app acababa de guardar— y devolvía el vídeo
            //    al minuto viejo. De ahí que en PC fuera bien y en celular
            //    empezara siempre en el 19, incluso borrando el historial: se
            //    volvía a escribir solo antes de que esto lo leyera.
            //
            // Quien retoma con recorte es el cartel de «¿continuar donde
            // ibas?», que va por `confirmResume` y rehace la lista. Acá no hay
            // nada que hacer.
            logger.info('recorte fMP4: no se retoma en ${guardado}s por el '
                'listener de duración — de eso se encarga el cartel');
          } else {
            _isAutoSeekPosition = true;
            player.seek(Duration(seconds: guardado));
            sendMessage(Message(Text('video.resume-last-playback'.i18n)));
          }
        }
      }
    }));

    // 监听 track
    _addSubscription(player.stream.tracks.listen((event) {
      if (event.subtitle.isEmpty) {
        return;
      }

      final latestLanguageSelected = PrismHubStorage.getSetting(
        SettingKey.subtitleLastLanguageSelected,
      );
      final latestTitleSelected = PrismHubStorage.getSetting(
        SettingKey.subtitleLastTitleSelected,
      );
      if (latestLanguageSelected == null && latestTitleSelected == null) {
        return;
      }

      final subtitle = [...event.subtitle, ...subtitles].firstWhereOrNull(
        (element) {
          if (element.id == "no" || element.id == "auto") {
            return false;
          }
          return element.language == latestLanguageSelected ||
              element.title == latestTitleSelected;
        },
      );

      if (subtitle != null) {
        player.setSubtitleTrack(subtitle);
      }
    }));

    // 总时长监听
    _addSubscription(player.stream.duration.listen((event) {
      if (dlnaDevice.value != null) {
        return;
      }
      // Con recorte, mpv solo conoce el largo del pedazo que se le dio. La
      // barra tiene que seguir mostrando el episodio entero, o al saltar al
      // minuto 20 el vídeo "duraría" 91 minutos en vez de 111.
      final recorte = _recorte;
      duration.value = recorte != null && recorte.duracionTotal > Duration.zero
          ? recorte.duracionTotal
          : event;
      // Con el largo ya conocido la notificación puede dibujar su barra. Es
      // también la primera vez que hay algo real que mostrar.
      if (event > Duration.zero) unawaited(_mostrarNotificacion());
    }));

    // 监听播放状态
    _addSubscription(player.stream.playing.listen((event) {
      if (dlnaDevice.value != null) {
        return;
      }
      isPlaying.value = event;
      if (event) {
        unawaited(_touchHistory());
      }
    }));

    // La notificación sigue a isPlaying, venga de donde venga.
    //
    // Antes el refresco inmediato estaba dentro del aviso de arriba, que se
    // CORTA cuando se está transmitiendo (ahí quien reproduce es el televisor y
    // el reproductor de acá está parado). O sea que justo casteando —que es
    // cuando la notificación es el único mando que queda— el botón tardaba
    // hasta un segundo en cambiar, y tocarlo dos veces rápido dejaba el icono
    // diciendo una cosa y el televisor haciendo otra.
    //
    // Colgado del observable, se entera igual si el cambio vino del
    // reproductor de acá, del televisor o de un botón de la propia
    // notificación.
    _addWorker(ever(isPlaying, (_) {
      // Sin el freno de tiempo: pausar y reanudar tiene que verse en el acto,
      // no en el próximo segundo.
      _ultimoRefrescoNotificacion = null;
      _refrescarNotificacion();
    }));

    // 监听进度
    _addSubscription(player.stream.position.listen((crudo) {
      if (dlnaDevice.value != null) {
        return;
      }
      // Con recorte, mpv cuenta desde el principio del PEDAZO que se le dio, no
      // del episodio. Se traduce acá arriba, una sola vez, para que todo lo de
      // abajo —aceptar la posición, la notificación, el guardado del minuto—
      // trabaje en minutos del episodio de verdad. Sin recorte el desfase es
      // cero y esto no cambia nada.
      final event = crudo + (_recorte?.desfase ?? Duration.zero);
      // ── Detector de saltos que nadie pidió ────────────────────────────────
      //
      // TEMPORAL, para cazar un salto fantasma: en Android el vídeo empieza
      // siempre en el mismo minuto aunque se abra desde cero, y ya se
      // descartaron tres caminos (el cartel de continuar, `_midStreamResumeAt`
      // y el retomar del listener de duración).
      //
      // Si la posición CRUDA de mpv da un brinco sin que haya un salto en
      // curso, lo movió alguien más. Queda anotado con la pila de llamadas, que
      // es lo único que dice QUIÉN.
      if (_ultimaCruda != null &&
          !_saltandoConRecorte.value &&
          _destinoDeSalto == null &&
          (crudo - _ultimaCruda!).abs() > const Duration(seconds: 3)) {
        logger.warning(
            'SALTO FANTASMA: mpv pasó de ${_ultimaCruda!.inSeconds}s a '
            '${crudo.inSeconds}s sin que nadie lo pidiera',
            StackTrace.current);
      }
      _ultimaCruda = crudo;
      // Con un salto en camino la barra muestra adonde VA a ir. Pisarla con la
      // posicion actual la haria volver atras entre toque y toque, que es lo
      // que impedia encadenar saltos.
      if (!_aceptarPosicion(event)) return;
      // ¿Avanzó DE VERDAD? Ver _posicionAlPrimerCuadro: que la posición pase de
      // cero no alcanza, eso pasa apenas mpv se coloca. Se mide contra dónde
      // estaba cuando apareció el cuadro, así también vale cuando se retoma un
      // episodio por la mitad.
      if (_hayCuadro && !hasRenderedFrame.value) {
        final desde = _posicionAlPrimerCuadro ??= event;
        if (event - desde >= _avanceParaCreerle) {
          _marcarQueYaSeVe(
              'el vídeo avanzó ${(event - desde).inMilliseconds} ms');
        }
      }
      position.value = event;
      _refrescarNotificacion();
      // Avance real de posición → hay frames nuevos reproduciéndose, así que
      // NO puede estar bufferizando de verdad ahora mismo, sin importar lo
      // que diga el flag crudo (ver isActuallyBuffering).
      if (_lastPositionSeen == null || event != _lastPositionSeen) {
        _lastPositionSeen = event;
        _lastPositionAdvanceAt = DateTime.now();
        if (isActuallyBuffering.value) isActuallyBuffering.value = false;
        // La búsqueda terminó: hay frames nuevos y ya no se está llenando el
        // buffer. Se comprueba el flag crudo de mpv, no isActuallyBuffering,
        // que acabamos de apagar dos líneas arriba.
        if (isSeeking.value) {
          if (_positionAfterSeek == null) {
            // El salto en sí. Todavía no hay reproducción.
            _positionAfterSeek = event;
          } else if (event != _positionAfterSeek && !player.state.buffering) {
            // Segunda posición distinta y sin buffer pendiente: ya está
            // reproduciendo. Si el tramo estaba cargado esto llega en el
            // frame siguiente y la rueda apenas parpadea; si no, se queda
            // girando hasta que llegue.
            _clearSeeking();
          }
        }
      }
    }));

    // Vuelve la red, o se pasa de wifi a datos: se recupera solo.
    //
    // Al cambiar de red, la conexion que estaba bajando el video se corta y
    // ademas la direccion deja de servir: muchas fuentes la firman contra la IP
    // publica que tenias al pedirla, asi que desde la red nueva contestan que
    // no. Lo que se veia era el cartel de "servidor no disponible" con el audio
    // todavia sonando desde lo que quedaba en el buffer, y no se recuperaba
    // nunca: habia que salir del episodio y volver a entrar.
    //
    // Se pide una resolucion NUEVA (no se reabre la vieja, que ya no sirve) y
    // se retoma en el punto donde iba.
    _addWorker(ever(ConnectivityUtils.isOnline, (online) {
      if (online != true || _disposed) return;
      // Casteando no: el televisor baja el video por su cuenta y tiene su
      // propia conexion; ahi el vigilante del aparato es el que manda.
      if (dlnaDevice.value != null) return;
      // Con el respaldo por navegador tampoco: ese no lo manejamos nosotros.
      if (isWebViewActive.value || isGettingWatchData.value) return;
      // Solo si de verdad se rompio algo. Un cambio de red mientras todo va
      // bien no tiene por que interrumpir nada.
      final roto =
          imagenCongelada.value || serverFailedMessage.value.isNotEmpty;
      if (!roto) return;
      // Se da un respiro: apenas cambia la interfaz, la red nueva todavia no
      // resuelve nombres y el reintento saldria fallado igual.
      Timer(const Duration(milliseconds: 1200), () {
        if (_disposed || dlnaDevice.value != null) return;
        if (!imagenCongelada.value && serverFailedMessage.value.isEmpty) return;
        // ── Se vuelve a chequear, no solo al entrar al Timer ────────────
        //
        // Este chequeo YA se hacía antes de programar el Timer, pero no
        // DESPUÉS de esperarlo. En esos 1,2 s puede haber arrancado otra
        // resolución del mismo servidor —el usuario tocó "reintentar" a
        // mano, o el vigilante de atasco disparó la suya— y sin volver a
        // mirar acá, este Timer abría una SEGUNDA fuente por encima de la que
        // ya estaba en camino: dos `player.open()` casi a la vez, y un
        // instante con el audio de las dos sonando junto. Reportado en vivo.
        if (isWebViewActive.value || isGettingWatchData.value) return;
        logger.info('Cambio de red: se vuelve a resolver el video');
        _midStreamResumeAt = position.value;
        // El contador de reintentos se reinicia: los fallos anteriores fueron
        // por la red que se cayo, no porque el servidor este mal.
        _serverRetryCount = 0;
        serverFailedMessage.value = '';
        _failOrRetryServer(currentServerName.value);
      });
    }));

    // Vigilante de imagen congelada: ver imagenCongelada.
    _arrancarVigilanteDeAtasco();

    // Vigía de buffering atascado — ver comentario en _bufferingStallTimer.
    // Cuánto lleva descargado por delante, para la sombra de la barra.
    //
    // El controlador declaraba este dato pero no lo llenaba nadie: la barra lo
    // leía de mpv por su cuenta. Al unificarla para que funcione también
    // casteando —donde mpv está parado y sus números son cero— la sombra se
    // quedó sin quien se la diera. Va acá, que es donde vive el resto del estado
    // de reproducción, y así hay UN solo lugar del que leerlo.
    //
    // Casteando no se toca: ahí el colchón que importa es el del televisor, y el
    // de mpv sería un cero que borraría la sombra.
    _addSubscription(player.stream.buffer.listen((event) {
      if (dlnaDevice.value != null) return;
      buffer.value = event;
    }));

    _addSubscription(player.stream.buffering.listen((buffering) {
      if (dlnaDevice.value != null) return;
      // Si la posición avanzó hace menos de 800ms, el flag crudo está
      // desfasado (evento de "terminó de bufferizar" perdido) — se ignora.
      final advancedRecently = _lastPositionAdvanceAt != null &&
          DateTime.now().difference(_lastPositionAdvanceAt!) <
              const Duration(milliseconds: 800);
      isActuallyBuffering.value = buffering && !advancedRecently;
      _bufferingStallTimer?.cancel();
      _bufferingStallTimer = null;
      // Un parón de verdad (no el flag desfasado de mpv) y ya con el vídeo en
      // marcha: se mide y queda en el registro. Solo lee, no cambia nada.
      if (buffering && !advancedRecently && hasRenderedFrame.value) {
        unawaited(_medir('se paró a reproducir'));
      }
      if (buffering) {
        // Que tarde en cargar NO es que el servidor esté caído: se espera.
        //
        // Antes, a los 35 segundos bufferizando se daba el servidor por muerto y
        // se volvía a resolver la fuente solo. Eso hacía tres cosas malas de una:
        // reabría el vídeo desde cero justo cuando estaba por terminar de
        // cargar, tiraba el colchón que había juntado, y encima empezaba de
        // nuevo la cuenta — o sea que un servidor lento nunca llegaba a
        // reproducir por culpa del propio reintento.
        //
        // Medido en vivo: la fuente entregaba 0,79 Mbps para un vídeo de 6 Mbps.
        // Ahí no hay nada roto que reintentar; hay que esperar, o cambiar de
        // servidor a mano, y eso lo decide el usuario. A los 25 segundos ya se
        // le avisa que el vídeo no avanza (ver el vigilante de imagen
        // congelada), así que tiene la información para elegir.
        //
        // Solo queda el rastro en el registro, con la medición al lado para
        // saber si es caudal o es otra cosa.
        _bufferingStallTimer = Timer(const Duration(seconds: 35), () {
          // Pausado no está cargando nada: no hay atasco que registrar.
          if (!player.state.playing) return;
          logger.warning('Lleva 35 s cargando en "${currentServerName.value}". '
              'Se sigue esperando: no se da por caído ni se cambia de servidor '
              'solo.');
          unawaited(_medir('35 s cargando'));
        });
      }
    }));

    // 错误监听 — detectar fallo de reproducción
    _addSubscription(player.stream.error.listen((event) {
      // "Could not open codec": casi siempre es el decodificador por HARDWARE
      // que no puede con este vídeo, no un vídeo roto.
      //
      // El caso que lo destapó: un VR de Eporner de 4320x2160. Los VR vienen
      // side-by-side, o sea con el doble de ancho, y la mayoría de los
      // decodificadores por hardware topan en 4096 — 4320 se pasa. mpv abre el
      // stream, falla al abrir el códec y no se ve nada, aunque el archivo
      // esté perfecto.
      //
      // Se reintenta UNA vez con decodificación por software, que no tiene ese
      // límite. Cuesta más CPU, pero es la diferencia entre verlo y no verlo.
      // Una sola vez: si con software tampoco abre, el problema es otro y
      // seguir reintentando solo taparía el error real.
      if (event.toLowerCase().contains('could not open codec') &&
          !_reintentoPorSoftware &&
          player.platform is NativePlayer) {
        _reintentoPorSoftware = true;
        logger.warning(
            'Codec sin abrir — reintentando por software (posible video mas '
            'ancho de lo que soporta el hardware)');
        unawaited(_reintentarSinHardware());
        return;
      }
      // Errores de decodificación (audio/video corrupto) pueden llegar en
      // ráfaga, uno por cada frame roto — confirmado en vivo: cientos de
      // "Error decoding audio" por segundo, inundando el log para siempre
      // sin avisarle nada útil al usuario ni cortar la reproducción rota.
      // Se loggea solo el primero de cada ráfaga, y si sigue mucho tiempo se
      // trata como un fallo real de servidor.
      if (event.toLowerCase().contains('error decoding')) {
        final now = DateTime.now();
        if (_decodeErrorBurstStart == null ||
            now.difference(_decodeErrorBurstStart!) >
                const Duration(seconds: 3)) {
          _decodeErrorBurstStart = now;
          _decodeErrorBurstCount = 0;
        }
        _decodeErrorBurstCount++;
        if (_decodeErrorBurstCount == 1) {
          logger.severe('media_kit error: $event');
        }
        if (_decodeErrorBurstCount == 20 && serverFailedMessage.value.isEmpty) {
          logger.severe(
              'media_kit error: ráfaga de errores de decodificación, tratando como servidor roto ($event)');
          serverFailedMessage.value = availableServers.length > 1
              ? 'Servidor "${currentServerName.value}" con audio/video dañado.\n'
                  'Cambiá de servidor con el botón Servidor.'
              : 'Error de reproducción (audio/video dañado). Intentá más tarde.';
        }
        return;
      }
      logger.severe('media_kit error: $event');
      final isDup = event == _lastErrorEvent;
      _lastErrorEvent = event;
      // Errores técnicos de libmpv/ffmpeg no se muestran al usuario:
      // son ruido interno (timeout TCP, file format, etc.) que solo confunde.
      // El estado de fallo se comunica con el overlay estable serverFailedMessage.
      final eventLower = event.toLowerCase();
      final isTechnical = event.contains('Failed to open') ||
          event.contains('tcp:') ||
          event.contains('ffurl_read') ||
          event.contains('Failed to recognize') ||
          event.contains('No such') ||
          event.contains('Connection refused') ||
          event.contains('Operation timed out') ||
          // "Media source is not playable" (reportado en vivo con FuegoCine,
          // intermitente): no estaba en esta lista, así que se le mostraba al
          // usuario el texto técnico crudo Y TAMPOCO disparaba el
          // auto-recuperación de abajo (esa condición tampoco lo cubría) —
          // se quedaba colgado esperando que el usuario recargue a mano.
          eventLower.contains('not playable');
      if (!isGettingWatchData.value && !isDup && !isTechnical) {
        sendMessage(Message(Text(event)));
      }
      // Si el error indica que el stream no es accesible, notificar
      if (eventLower.contains('not found') ||
          eventLower.contains('403') ||
          eventLower.contains('500') ||
          eventLower.contains('no such') ||
          eventLower.contains('not playable') ||
          eventLower.contains('failed')) {
        // hasRenderedFrame=true acá significa que YA se venía reproduciendo
        // bien y esto es un corte real a mitad de capítulo (no un fallo de
        // conexión inicial — ese caso ya lo maneja play()/switchServer() por
        // su cuenta). En vez de dejar el video parado esperando que el
        // usuario note el cartel y cambie de servidor a mano, se recupera
        // solo (mismo mecanismo de auto-failover ya validado en vivo),
        // conservando la posición para no reiniciar el capítulo desde 0.
        if (hasRenderedFrame.value) {
          logger.severe(
              'Corte a mitad de reproducción en "${currentServerName.value}" ($event) — recuperando automáticamente.');
          _midStreamResumeAt = position.value;
          _failOrRetryServer(currentServerName.value);
        } else if (serverFailedMessage.value.isEmpty) {
          if (availableServers.length > 1) {
            serverFailedMessage.value =
                'Servidor "${currentServerName.value}" no disponible.\n'
                'Cambia de servidor con el botón Servidor.';
          } else {
            serverFailedMessage.value =
                'Error de reproducción. Intenta más tarde.';
          }
        }
      }
    }));
  }

  // 播放
  play() async {
    // 如果已经 delete 当前 controller
    if (_disposed) {
      return;
    }
    player.stop();
    isGettingWatchData.value = true;
    awaitingServerChoice.value = false;
    hasRenderedFrame.value = false;
    // Fuente nueva: se olvida el cuadro anterior y la red se rearma
    // sola con el primer cuadro de esta. Ver hasRenderedFrame.
    _hayCuadro = false;
    _posicionAlPrimerCuadro = null;
    _redDeLaRueda?.cancel();
    _redDeLaRueda = null;
    // Las calidades son de ESTE video, no de los anteriores.
    //
    // Se llenaba con qualityMap[...] = ... y no se limpiaba nunca, asi que
    // cambiar de episodio iba APILANDO: en el menu aparecian las calidades del
    // que se estaba viendo mas las de todos los anteriores de la sesion, y las
    // viejas apuntaban a un stream que ya no era ese. Elegir una de esas
    // reproducia otra cosa.
    //
    // Se limpia aca —donde ya se reinicia el resto del estado del contenido
    // anterior— y no dentro de getQuality(), porque getQuality solo corre para
    // streams directos: viniendo de uno HLS a uno que no lo es, no habria
    // pasado nunca por ahi y el menu se habria quedado con lo viejo.
    qualityMap.clear();
    // Contenido nuevo: el reintento por software vuelve a estar disponible.
    _reintentoPorSoftware = false;
    // El recorte de VR es del REPRODUCTOR, no del archivo.
    //
    // Abrir otro video no lo saca, y las medidas con las que se calculo son las
    // del anterior: en uno de otra resolucion recorta cualquier cosa. Lo grave
    // es el caso en que el video nuevo NO es VR — ahi el interruptor desaparece
    // del panel, porque solo sale en videos VR, y el recorte se queda puesto
    // sin ninguna forma de apagarlo salvo saliendo del reproductor.
    await _olvidarRecorteVr();
    // No arrastrar el "avanzó hace poco" del video/servidor ANTERIOR — sin
    // esto, un corte real justo al cambiar de contenido podía quedar sin
    // spinner un instante porque todavía valía el timestamp viejo.
    _lastPositionAdvanceAt = null;
    _lastPositionSeen = null;
    _lastHistoryTouchAt = null;
    // Contenido nuevo: se vuelve a elegir la calidad de arranque, y el
    // aviso de atasco vuelve a estar disponible.
    _calidadInicialElegida = false;
    _atascoAvisado = false;
    imagenCongelada.value = false;
    _historyTouchInFlight = false;
    isActuallyBuffering.value = false;
    _lastErrorEvent = '';
    _pageSniffAttempted = false;
    _webViewElapsedSeconds = 0;
    _pendingResumeSeconds = null;
    resumePrompt.value = null;
    _lastOpenedServerName = null;
    _serverRetryCount = 0;
    _triedAndFailedServers.clear();
    _midStreamResumeAt = null;
    try {
      await getWatchData();
      if (_disposed) return;
    } catch (e) {
      if (_disposed) return;
      logger.severe(e);
      serverFailedMessage.value =
          'No se pudo cargar el episodio. Intentá más tarde.';
      isGettingWatchData.value = false;
      await _safePlayerInit();
      return;
    }

    // Verificar progreso guardado antes de cargar — si hay posición significativa
    // se le pregunta al usuario si desea continuar (el stream.duration listener
    // queda inhibido mientras _pendingResumeSeconds != null).
    {
      final hist = await DatabaseService.getHistoryByPackageAndUrl(
        runtime.extension.package,
        detailUrl,
      );
      if (_disposed) return;
      if (hist != null &&
          hist.progress.isNotEmpty &&
          hist.episodeId == index.value &&
          hist.episodeGroupId == episodeGroupId) {
        final secs = int.tryParse(hist.progress) ?? 0;
        final total = int.tryParse(hist.totalProgress) ?? 0;
        // No preguntar "¿continuar?" si ya estaba prácticamente terminado
        // (últimos 30s o 95% visto) — a esa altura no tiene sentido
        // "retomar" un capítulo que de hecho ya se vio entero.
        final nearEnd =
            total > 0 && (total - secs <= 30 || secs >= total * 0.95);
        if (secs > 5 && !nearEnd) _pendingResumeSeconds = secs;
      }
    }

    // Con más de un servidor para elegir, la app no prueba nada sola — el
    // usuario elige de la lista (con el recordado/nativo ya marcado ahí) y
    // recién ahí se resuelve+intenta ESE (switchServer). Antes se probaban
    // los 5-6 servidores de una al abrir el capítulo, cargando/gastando red
    // de más aunque el usuario ni fuera a usar la mayoría de esos intentos.
    //
    // Excepción: si YA hay un servidor recordado que funcionó antes en este
    // mismo episodio (típicamente al volver desde "Continuar viendo"), no
    // tiene sentido hacer elegir de nuevo. Se resuelve directo llamando a
    // switchServer (el MISMO flujo que usa el usuario al elegir a mano) — no
    // alcanza con reusar la ruta de "servidor único" de más abajo porque esa
    // solo sabe abrir directo o mandar al sniffer de WebView, y la mayoría de
    // los servidores son embeds que la propia extensión sabe resolver mejor
    // (runtime.watch). switchServer ya dispara el diálogo de "¿continuar?"
    // si corresponde una vez que abre.
    if (watchData!.type != ExtensionWatchBangumiType.torrent &&
        dlnaDevice.value == null &&
        availableServers.length > 1) {
      if (autoResume && _applyPreferredServer()) {
        if (_shouldResumeInWebView() && _openPreferredWebViewFallback()) {
          return;
        }
        // No tocar isGettingWatchData acá: switchServer ya lo pone en true
        // apenas arranca — pisarlo a false y volver a true un instante
        // después solo generaba un parpadeo del spinner de carga.
        unawaited(switchServer(currentServerName.value));
        return;
      }
      awaitingServerChoice.value = true;
      isGettingWatchData.value = false;
      return;
    }

    try {
      if (watchData!.type == ExtensionWatchBangumiType.torrent) {
        try {
          await getTorrentMediaFile();
          if (_disposed) return;
        } catch (e) {
          if (_disposed) return;
          logger.severe(e);
          error.value = friendlyError(e);
          return;
        }

        // El torrent puede no traer ningún archivo de video reproducible
        // (solo subtítulos, o un torrent de audio/otro contenido) —
        // torrentMediaFileList.first sobre una lista vacía tiraba
        // StateError sin ningún mensaje útil.
        if (torrentMediaFileList.isEmpty) {
          isGettingWatchData.value = false;
          error.value =
              'Este torrent no tiene archivos de video reproducibles.';
          return;
        }

        playTorrentFile(torrentMediaFileList.first);
      } else {
        if (dlnaDevice.value != null) {
          await dlnaDevice.value!.cargar(
            url: watchData!.url,
            titulo: '$title — ${playList[index.value].name}',
            mime: mimeDeUrl(watchData!.url),
          );
          if (_disposed) return;
        } else {
          // Si recordamos un servidor que ya funcionó en este episodio, usarlo
          // como primario para no re-buscar entre todos (carga más rápido).
          _applyPreferredServer();
          final primaryUrl = watchData!.url;
          if (isDirectStream(primaryUrl)) unawaited(getQuality());

          logger.info(
              'Intentando servidor primario: ${currentServerName.value} → $primaryUrl');
          bool worked;
          if (primaryUrl.startsWith('page://')) {
            // La extensión no resolvió ningún servidor pero dio la URL de la
            // página: ir directo al page-sniff (cargar el sitio en WebView).
            worked = await _trySniffPage();
          } else if (isDirectStream(primaryUrl)) {
            worked = await _tryOpenPlayer(primaryUrl, watchData!.headers);
          } else {
            // El primario es un embed sin resolver (voe, netu, streamwish...).
            // No gastar 12s en media_kit intentando reproducir un HTML: ir
            // directo al sniffer WebView, que sí sabe sacar el stream real.
            worked = await _trySniff(currentServerName.value, primaryUrl);
          }
          if (_disposed) return;

          if (!worked &&
              watchData!.headers != null &&
              watchData!.headers!.containsKey('X-Netu-Alts')) {
            try {
              final List<dynamic> alts =
                  jsonDecode(watchData!.headers!['X-Netu-Alts']!);
              for (final altUrlDyn in alts) {
                final altUrl = altUrlDyn.toString();
                logger.info('Intentando URL alternativa: $altUrl');
                worked = await _tryOpenPlayer(altUrl, watchData!.headers);
                if (_disposed) return;
                if (worked) {
                  watchData = ExtensionBangumiWatch(
                    type: watchData!.type,
                    url: altUrl,
                    subtitles: watchData!.subtitles,
                    headers: watchData!.headers,
                    audioTrack: watchData!.audioTrack,
                  );
                  break;
                }
              }
            } catch (e) {
              logger.warning('Error parseando X-Netu-Alts: $e');
            }
          }

          if (!worked) {
            logger.severe(
                'Servidor primario fallido: ${currentServerName.value}');
            if (availableServers.length > 1) {
              serverFailedMessage.value =
                  'Servidor "${currentServerName.value}" no accesible.\n'
                  'Elegí otro servidor con el botón Servidor.';
            } else if (_episodePageUrl.isNotEmpty && !_pageSniffAttempted) {
              if (!await _trySniffPage()) {
                serverFailedMessage.value =
                    'Servidor no accesible. Intentá más tarde.';
              }
            } else {
              serverFailedMessage.value =
                  'Servidor no accesible. Intentá más tarde.';
            }
            // Este era el bug real: el fallo del servidor PRIMARIO (la
            // primera carga) nunca pasaba por _setServerFailed/_trySniff, así
            // que webViewFallback quedaba en null y el botón "Abrir en
            // WebView" no aparecía nunca en el primer intento (solo se
            // llegaba a ver si el usuario cambiaba de servidor a mano).
            // _trySniffPage/_trySniff ya lo completan solos cuando encuentran
            // un stream que media_kit rechaza — esto cubre el resto (ej.
            // Moon, que nunca llega a dar un stream sniffeable sin un clic
            // humano real).
            if (webViewFallback.value == null &&
                !isDirectStream(primaryUrl) &&
                !primaryUrl.startsWith('page://') &&
                !primaryUrl.startsWith('error://')) {
              // OJO con el orden: asignar webViewFallback.value dispara el
              // worker ever() (video_player_desktop/mobile_controls.dart) de
              // forma SINCRÓNICA, en el mismo momento de esta línea — si
              // webViewOpenedOnce se resetea DESPUÉS, ese worker todavía ve
              // el valor viejo (true, de una sesión de WebView anterior en
              // este mismo episodio) y no vuelve a abrir el navegador
              // interno solo, dejando al usuario colgado en el frame
              // congelado (reportado en vivo). Por eso el reset va primero.
              webViewOpenedOnce.value = false;
              webViewFallback.value = {
                'url': primaryUrl,
                'name': currentServerName.value,
                'referer': serverReferers[currentServerName.value] ?? '',
              };
              // Ídem _setServerFailed: recordarlo igual que un servidor
              // nativo exitoso, para que la próxima vez no haga elegir de
              // cero (ver comentario completo allá).
              if (currentServerName.value.isNotEmpty) {
                unawaited(PrismHubStorage.setLastWorkingServer(
                  runtime.extension.package,
                  playList[index.value].url,
                  currentServerName.value,
                ));
              }
            }
            // El mensaje genérico de arriba ("no accesible, elegí otro") no
            // explica lo que en realidad hace falta cuando SÍ hay un
            // fallback disponible: un clic humano real en el navegador (ej.
            // Moon). Si terminamos con uno, pisar el mensaje con algo que
            // apunte directo al botón.
            if (webViewFallback.value != null) {
              // Este mensaje queda visible en el reproductor NATIVO tanto
              // antes de navegar (instante, casi no se ve) como DESPUÉS si
              // el usuario vuelve del navegador interno — por eso el texto
              // tiene que ser válido en ambos momentos, no sonar a "ya te
              // estoy abriendo algo" (eso quedaría mintiendo una vez que ya
              // volvió). El aviso de "por qué estás acá" en el momento
              // justo va DENTRO del navegador interno (SnackBar en
              // webview_player_page.dart), no acá.
              serverFailedMessage.value =
                  'No se puede reproducir en el reproductor nativo.\n'
                  'Podés verlo desde el navegador interno.';
            }
            isGettingWatchData.value = false;
            await _safePlayerInit();
            return;
          }
          // Servidor cargó OK — iniciar en pausa para que el usuario
          // decida cuándo reproducir.
          await player.pause();
          if (watchData!.audioTrack != null) {
            await player.setAudioTrack(
              AudioTrack.uri(watchData!.audioTrack!),
            );
          }
          // Si hay progreso guardado, emitir señal al UI para mostrar el diálogo.
          if (_pendingResumeSeconds != null) {
            // Pausado a proposito para preguntar: la rueda no puede quedar
            // girando detras del dialogo. Ver hasRenderedFrame.
            _marcarQueYaSeVe('pausado a propósito para preguntar');
            resumePrompt.value = _pendingResumeSeconds;
            _pendingResumeSeconds = null;
          }
        }
      }
      // Playback resolved successfully — clear any previous "not working" flag.
      ExtensionUtils.clearRuntimeError(runtime.extension.package);
      // Recordar el servidor que funcionó para este episodio: la próxima vez se
      // prueba primero y no se re-busca entre todos.
      if (currentServerName.value.isNotEmpty) {
        _lastOpenedServerName = currentServerName.value;
        _markNativePlayback(currentServerName.value);
      }
      isGettingWatchData.value = false;
      // 添加来自扩展的字幕
      subtitles.addAll(
        (watchData!.subtitles ?? []).map(
          (e) => SubtitleTrack.uri(
            e.url,
            language: e.language,
            title: e.title,
          ),
        ),
      );
      player.setSubtitleTrack(SubtitleTrack.no());
    } on StartServerException catch (_) {
      // 如果是 启动 bt server 失败
      if (Platform.isAndroid) {
        await showDialog(
          context: currentContext,
          builder: (context) => const BTDialog(),
        );
      } else {
        await fluent.showDialog(
          context: currentContext,
          builder: (context) => const BTDialog(),
        );
      }

      // 延时 3 秒再重试
      await Future.delayed(const Duration(seconds: 3));
      play();
      return;
    } catch (e) {
      // Antes mostraba e.toString() crudo Y dejaba isGettingWatchData en
      // true para siempre — cualquier excepción no prevista acá (ej.
      // torrentMediaFileList vacío en playTorrentFile) dejaba el spinner de
      // carga girando sin parar, sin mensaje útil, sin forma de recuperarse
      // salvo salir del reproductor. El rethrow tampoco servía de nada: esta
      // función se llama sin await en varios lados (onInit, ever(index,...)),
      // así que solo terminaba como una excepción de Future no manejada.
      logger.severe(e);
      isGettingWatchData.value = false;
      sendMessage(
        Message(
          Text(friendlyError(e)),
          time: const Duration(seconds: 5),
        ),
      );
    }
  }

  // 获取 watch 数据
  /// La extensión dejó de estar disponible y no tiene sentido seguir.
  ///
  /// Distinto de que falle un servidor: ahí se reintenta con otro. Acá no hay
  /// con qué reintentar, así que se corta todo y se ofrece salir.
  final extensionCaida = RxnString();

  /// Corta la reproducción porque la extensión ya no está.
  ///
  /// Pasa de verdad y en medio de la sesión: el usuario la desactiva o la borra
  /// desde otra pantalla, o el catálogo la marca inestable mientras está
  /// viendo. Antes eso salía como un error de red cualquiera y el reproductor
  /// seguía reintentando contra algo que ya no existe — la rueda girando para
  /// siempre y sin forma de entender qué pasaba.
  ///
  /// Se para todo lo que sigue latiendo (el reproductor, el vigilante de
  /// atasco, los reintentos de servidor) y se deja el aviso, que la pantalla
  /// muestra con un botón de salir.
  void _cortarPorExtensionCaida(String motivoI18n) {
    if (_disposed || extensionCaida.value != null) return;
    extensionCaida.value = motivoI18n;
    // Que no quede nada reintentando: sin esto los vigilantes seguirían
    // disparando sobre una extensión que ya no puede contestar.
    ++_switchServerGen;
    _vigilanteDeAtasco?.cancel();
    _muestreo?.cancel();
    isGettingWatchData.value = false;
    isSeeking.value = false;
    _seekWatchdog?.cancel();
    try {
      player.pause();
    } catch (_) {
      // Si el reproductor ya no está, no hay nada que pausar.
    }
    // Transmitiendo, también se le suelta el televisor: lo que está mostrando
    // sale de una extensión que ya no puede servir el siguiente episodio.
    if (dlnaDevice.value != null) unawaited(disconnectDLNADevice());
  }

  /// Comprueba que la extensión siga estando antes de pedirle nada.
  ///
  /// Devuelve true si hay que frenar. Se llama ANTES de cada pedido: el
  /// catálogo puede tardar en marcarla, así que la app no puede esperar a que
  /// alguien más se entere.
  bool _extensionSeCayo() {
    final motivo = ExtensionUtils.motivoNoDisponible(runtime.extension.package);
    if (motivo == null) return false;
    _cortarPorExtensionCaida(motivo);
    return true;
  }

  getWatchData() async {
    if (_extensionSeCayo()) return;
    watchData = null;
    subtitles.clear();
    availableServers.clear();
    serverReferers.clear();
    serverFailedMessage.value = '';
    webViewFallback.value = null;
    final playUrl = playList[index.value].url;
    watchData = await runtime.watch(playUrl, typeHint: ExtensionType.bangumi)
        as ExtensionBangumiWatch;

    final headers = watchData!.headers;
    if (headers != null) {
      // Parsear lista de servidores (embed URLs crudos)
      if (headers.containsKey('X-Servers')) {
        try {
          final Map<String, dynamic> parsed = jsonDecode(headers['X-Servers']!);
          availableServers.value =
              parsed.map((k, v) => MapEntry(k, v.toString()));
        } catch (_) {}
      }
      // Parsear referers por servidor
      if (headers.containsKey('X-Server-Referers')) {
        try {
          final Map<String, dynamic> parsed =
              jsonDecode(headers['X-Server-Referers']!);
          serverReferers
              .addAll(parsed.map((k, v) => MapEntry(k, v.toString())));
        } catch (_) {}
      }
      // Rayo/mundo dicho por la extensión, cuando lo dice. Solo vienen los
      // servidores que ella declara: los que no, quedan afuera del mapa y los
      // sigue decidiendo isKnownNativeServer por su cuenta.
      serverNative.clear();
      if (headers.containsKey('X-Server-Native')) {
        try {
          final Map<String, dynamic> parsed =
              jsonDecode(headers['X-Server-Native']!);
          parsed.forEach((k, v) {
            if (v is bool) serverNative[k] = v;
          });
        } catch (_) {}
      }
      // Servidor actual
      currentServerName.value = headers['X-Primary-Server'] ??
          (availableServers.isNotEmpty ? availableServers.keys.first : '');
      // URL de la página del episodio para el page-sniff (fallback universal).
      _episodePageUrl = headers['X-Page-Url'] ?? '';
      // Limpiar cabeceras especiales — no enviar al player
      watchData!.headers = Map.from(headers)
        ..remove('X-Servers')
        ..remove('X-Server-Referers')
        ..remove('X-Server-Native')
        ..remove('X-Primary-Server')
        ..remove('X-Page-Url');
    }
  }

  // Se incrementa en cada switchServer(): si el usuario cambia de servidor de
  // nuevo antes de que el anterior termine de resolver, la llamada vieja se
  // descarta en vez de "ganar la carrera" y pisar la elección más nueva —
  // confirmado en vivo: sin esto, cambiar de servidor rápido dejaba sonando
  // el anterior porque su resolución tardía llegaba después y sobreescribía
  // el player ya abierto por el servidor elegido en realidad.
  int _switchServerGen = 0;

  // Corta la cadena sniffer/page-sniff (varios pasos de 8-15s cada uno,
  // puede sumar más de un minuto) apenas el usuario navega para atrás —
  // confirmado en vivo que sin esto la cadena sigue corriendo entera en
  // segundo plano aunque la pantalla ya no esté, compitiendo por el mismo
  // WebView nativo y dejando la app sintiéndose trabada. No cancela el paso
  // YA en curso (eso depende del plugin nativo), pero evita encolar el
  // siguiente paso una vez que el actual termina.
  /// El reproductor que se esta usando ahora, si hay alguno.
  ///
  /// Existe para que el aviso de actualizacion pueda callar lo que se este
  /// reproduciendo antes de taparlo. Ese aviso sale encima de cualquier
  /// pantalla y bloquea a proposito, pero sin esto el video seguia sonando
  /// detras: quedaba el audio de algo que ya no se ve, y el usuario tenia que
  /// adivinar de donde salia.
  static VideoPlayerController? _enUso;

  /// Pausa lo que se este reproduciendo. No falla si no hay nada.
  static Future<void> pausarLoQueSuene() async {
    final c = _enUso;
    if (c == null || c._disposed) return;
    try {
      // Con tope: si el reproductor esta colgado, el aviso NO puede quedarse
      // esperandolo. Vale mas mostrar la actualizacion que apagar el audio.
      await c.player.pause().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Un reproductor a medio cerrar puede rechazar la orden. No es motivo
      // para no mostrar el aviso.
    }
  }

  /// Apagado de emergencia: la app se está cerrando.
  ///
  /// ── Por qué no alcanza con el apagado normal ────────────────────────────
  ///
  /// `_shutdownPlayback` hace bien su trabajo, pero es una SECUENCIA LARGA:
  /// baja el volumen, captura la miniatura de «Continuar viendo», guarda el
  /// historial y recién ahí libera el reproductor. Eso está pensado para
  /// cuando el usuario SALE del reproductor y la app sigue viva, y ahí cada
  /// paso vale la pena.
  ///
  /// Cuando el proceso se está muriendo no hay tiempo para nada de eso. Y ahí
  /// aparecía lo que se reportó: **la app se cerraba y el audio seguía
  /// sonando**, porque mpv nunca llegó a recibir la orden de parar.
  ///
  /// Esto es lo contrario: lo mínimo, ya, sin esperar a nadie y sin await. Se
  /// pierde la miniatura de «Continuar viendo» — y está bien, es lo barato de
  /// perder cuando la alternativa es dejar audio sonando en un equipo donde ya
  /// no hay ninguna ventana que lo pare.
  ///
  /// Es `static` a propósito: quien cierra la app no tiene por qué saber si
  /// hay un reproductor abierto ni cómo encontrarlo.
  static void apagarTodoYa() {
    final c = _enUso;
    if (c == null) return;
    // Se marca ANTES de tocar nada: si algo más dispara el apagado normal
    // mientras tanto, tiene que encontrar el camino ya cerrado en vez de
    // arrancar una segunda secuencia sobre un reproductor que se está yendo.
    c._disposed = true;
    c._shutdownStarted = true;
    _enUso = null;

    // Las tres órdenes salen JUNTAS y sin esperar respuesta. Alcanza con que
    // llegue una para que deje de sonar, y si alguna se cuelga —el bug de
    // hilos de media_kit que ya está documentado más abajo— no arrastra a las
    // otras. Con `await` una sola bastaría para que no se ejecute ninguna.
    try {
      unawaited(c.player.setVolume(0).catchError((_) {}));
      unawaited(c.player.pause().catchError((_) {}));
      unawaited(c.player.stop().catchError((_) {}));
    } catch (e) {
      // Ni siquiera esto puede tirar: estamos en el camino de cierre y una
      // excepción acá dejaría la app colgada al salir.
      logger.info('No se pudo apagar el reproductor al cerrar: $e');
    }
  }

  bool _disposed = false;
  bool get disposed => _disposed;
  final Completer<void> _shutdownCompleter = Completer<void>();
  Future<void>? _shutdownFuture;
  bool _playerDisposed = false;
  bool _shutdownStarted = false;
  bool _routeClosing = false;

  // _routeClosing entra acá y no solo _disposed: closeRoute() lo marca
  // SINCRÓNICO, como lo primero de todo, antes de esperar la captura del
  // fotograma y el pausado (hasta 2s cada uno) — _disposed recién se pone
  // en true bastante después, cuando ese cierre asíncrono termina de
  // llegar a _beginPlaybackShutdown(). En esa ventana, una resolución
  // lenta que ya estaba en camino (getWatchData, switchServer) todavía
  // veía _disposed en false y podía terminar llamando a player.open() —
  // en el reproductor que se estaba cerrando. Reportado en vivo: se salió
  // de un episodio que tardaba en cargar, se entró a otro, y el audio del
  // primero empezó a sonar encima del segundo.
  bool _isPlaybackClosed([int? generation]) =>
      _disposed ||
      _routeClosing ||
      (generation != null && generation != _switchServerGen);

  // Reintento automático antes de rendirse: confirmado en vivo (Streamwish)
  // que algunos hosts asignan un servidor de backend al azar en CADA
  // resolución (el link cambia de subdominio cada vez) — si te toca uno
  // lento/caído, un simple reintento (que pide una URL firmada nueva) puede
  // caer en uno sano. Se resetea al elegir un servidor distinto o al abrir
  // uno con éxito, para no gastar el único reintento en fallos viejos.
  int _serverRetryCount = 0;
  static const _maxServerRetries = 1;

  // Servidores que ya se probaron y fallaron en esta cadena de auto-failover
  // (ver _setServerFailed) — se resetea al elegir un servidor a mano
  // (selectServer), para que un reintento manual del usuario siempre tenga
  // chance real en vez de saltarse todo por "ya lo probamos".
  final Set<String> _triedAndFailedServers = {};

  // Posición a restaurar después de una recuperación automática a mitad de
  // episodio (corte real de stream, no un fallo de conexión inicial — ver
  // player.stream.error.listen y el watchdog de buffering). switchServer()
  // siempre abre la fuente nueva desde 0; sin esto, un simple hipo de red a
  // mitad de capítulo reiniciaba el episodio entero en vez de seguir donde
  // se cortó.
  Duration? _midStreamResumeAt;

  void _beginPlaybackShutdown() {
    // ── Lo PRIMERO de todo: que deje de sonar ─────────────────────────────
    //
    // Antes lo primero que se hacía era bajar el volumen, sí, pero dentro de
    // `_shutdownPlayback`, que es la parte asíncrona y corre DESPUÉS de todo
    // esto. Y hay caminos de cierre que ni siquiera llegan ahí: si el
    // reproductor se cierra mientras está el respaldo por navegador, o si algo
    // en el medio de este desarmado tira una excepción, `_shutdownPlayback`
    // queda sin llamarse y el audio sigue sonando encima de la pantalla
    // anterior. Reportado en vivo: «cerré el reproductor y se seguía
    // escuchando».
    //
    // Acá arriba de todo no puede fallar: es lo primero que corre en el único
    // punto por el que pasan TODOS los cierres. Sin await —no hay que esperar
    // a nadie para callar— y con la excepción tragada, porque si el
    // reproductor ya está desarmado esto tira y no importa: si ya está
    // desarmado, tampoco está sonando.
    //
    // Pausar además de bajar el volumen: con volumen cero el vídeo sigue
    // corriendo y gastando, y si algo lo reanuda vuelve a oírse. Los dos van en
    // paralelo, alcanza con que llegue uno.
    try {
      unawaited(player.setVolume(0).catchError((_) {}));
      unawaited(player.pause().catchError((_) {}));
    } catch (_) {}

    ++_switchServerGen;
    _disposed = true;
    // Solo si sigo siendo yo: entre dos episodios puede haberse registrado ya
    // el controlador siguiente, y borrarlo dejaria el aviso sin a quien pausar.
    if (identical(_enUso, this)) _enUso = null;
    isVideoSurfaceMounted.value = false;
    isWebViewActive.value = false;
    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }
    _dlnaTimer?.cancel();
    _bufferingStallTimer?.cancel();
    _qualitySwitchTimer?.cancel();
    _redDeLaRueda?.cancel();
    _redDeLaRueda = null;
    // Cada lectura abierta es un socket contra el servidor: al cerrar el
    // reproductor hay que soltarlas o quedan colgadas hasta reiniciar la app.
    _soltarLaBomba();
    // Estos dos son de un solo disparo, asi que no dejan nada dando vueltas,
    // pero si el reproductor se cierra en el medio saltan despues y escriben
    // sobre observables de un controlador ya destruido.
    _seekWatchdog?.cancel();
    // Sin esto, un salto pedido justo antes de cerrar saltaba despues sobre un
    // reproductor que ya no existe.
    _juntadorDeSaltos?.cancel();
    _destinoDeSalto = null;
    _avisoVolumenTimer?.cancel();
    avisoVolumen.value = null;
    // Una orden de pausa/reproduccion pedida justo antes de cerrar saltaba
    // despues sobre un aparato que ya se solto.
    _playPedidoTimer?.cancel();
    _playPedido = null;
    // La notificación se va con el reproductor: dejarla en la barra sin nadie
    // del otro lado sería un panel de control que no controla nada.
    // Con el dueño: al pasar de una obra a otra este reproductor se cierra
    // DESPUÉS de que el nuevo ya se anunció, y sin eso le apagaba la
    // notificación al que acababa de empezar.
    if (Platform.isAndroid) NotificacionReproductor.esconder(this);
    _skipBadgeTimer?.cancel();
    _castBuscandoTimer?.cancel();
    _volumenCastTimer?.cancel();
    _esperaPlayTimer?.cancel();
    _pedidoCastTimer?.cancel();
    _vigilanteDeAtasco?.cancel();
    _muestreo?.cancel();
    imagenCongelada.value = false;
    final device = dlnaDevice.value;
    // Se anota que se estaba casteando y por donde iba ANTES de soltar nada.
    //
    // Esto corre antes de que se guarde el historial, y ahi hace falta saberlo:
    // el reproductor de aca lleva parado desde que empezo la transmision, asi
    // que su posicion vale cero y el progreso se perderia entero. Preguntar por
    // dlnaDevice mas adelante no sirve, porque tres lineas mas abajo ya es null.
    if (device != null && !_casteabaAlCerrar) {
      _casteabaAlCerrar = true;
      _posicionCastAlCerrar = position.value;
      _duracionCastAlCerrar = duration.value;
    }
    dlnaDevice.value = null;
    if (device != null) {
      // unawaited + catchError: device.stop() devuelve un Future, asi que un
      // try/catch alrededor NO atrapa nada — si el aparato esta apagado o fuera
      // de la red, el fallo quedaba como error asincrono sin dueño.
      unawaited(device.soltar().catchError((Object e) {
        logger.warning('El aparato no respondio al cerrar el reproductor', e);
      }));
    }
    if (_dlnaRelayUrl != null) {
      CastRelayServer.unregister(_dlnaRelayUrl!);
      _dlnaRelayUrl = null;
    }
  }

  void stopPlaybackImmediately() {
    _beginPlaybackShutdown();
    unawaited(shutdownPlayback(saveHistory: false));
  }

  Future<void> _ensureVideoSurfaceMounted() async {
    if (_disposed || isVideoSurfaceMounted.value) return;
    isVideoSurfaceMounted.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  Future<void> shutdownPlayback({bool saveHistory = true}) {
    final future = _shutdownFuture ??= _shutdownPlayback(
      saveHistory: saveHistory,
    );
    _lastPlaybackShutdown = future.catchError((_) {});
    return future;
  }

  Future<void> _shutdownPlayback({required bool saveHistory}) async {
    if (_playerDisposed) return;
    if (_shutdownStarted) return;
    _shutdownStarted = true;

    // Lo PRIMERO de todo: callar el audio.
    //
    // Iba mucho mas abajo, despues de capturar el fotograma para "Continuar
    // viendo" —que tiene su propio tope de 2 s— y de guardar el historial. O
    // sea que al salir el video seguia sonando encima de la pantalla anterior
    // todo ese rato. Reportado dos veces: "tarda 3-5 segundos en callarse".
    //
    // Se puede adelantar sin perder nada: bajar el volumen y pausar son
    // operaciones normales del reproductor, de las que pasan mil veces durante
    // la reproduccion, y no son parte del desarmado. La captura sigue andando
    // igual porque toma el fotograma que ya esta en pantalla, que no depende
    // del volumen ni de si esta pausado. Lo que NO se puede adelantar es
    // stop()/dispose(), que es lo que deja al player sin poder capturar.
    //
    // Los dos intentos van en paralelo: alcanza con que uno llegue para que
    // deje de sonar, y si uno se cuelga —el bug de hilos que se explica mas
    // abajo— ya no demora al otro.
    // SOLO el volumen. Pausar va DESPUES de capturar el fotograma.
    //
    // Se habian adelantado los dos juntos y eso rompio la captura: screenshot()
    // le pide un cuadro al reproductor, y con el reproductor ya pausado se
    // queda esperando uno que nadie va a renderizar — visto en el log,
    // "TimeoutException after 0:00:02" justo al salir.
    //
    // Bajar el volumen no tiene ese problema: no toca el video, solo el audio.
    // Asi se consigue lo que se buscaba —que deje de sonar al instante— sin
    // perder la miniatura de "Continuar viendo".
    await player
        .setVolume(0)
        .timeout(const Duration(seconds: 2))
        .catchError((_) {});

    // El frame se toma ACÁ, antes de tocar nada del player, y se pasa hecho a
    // _saveHistory. Capturar más abajo (con el desarmado ya empezado) es lo
    // que obligaba a pasar captureScreenshot:false: una vez que arrancó el
    // shutdown, player.screenshot() puede quedarse esperando un callback
    // nativo que ya no va a llegar — el mismo bug de threading de media_kit
    // 1.2.5 que se explica más abajo. Pero sin captura, la tarjeta de
    // "Continuar viendo" nunca mostraba dónde había quedado el usuario.
    //
    // Acá el player todavía está sano (es el mismo estado que en cualquier
    // momento de la reproducción) y además va con timeout, así que en el peor
    // caso se pierde la miniatura, nunca se cuelga el cierre.
    //
    // Casteando no se captura: el reproductor de aca lleva parado desde que
    // empezo la transmision, asi que saldria un cuadro negro que ademas pisaria
    // la miniatura buena que ya estaba guardada. En ese caso _saveHistory
    // conserva la anterior.
    final frame =
        (saveHistory && dlnaDevice.value == null && !_casteabaAlCerrar)
            ? await _capturarFrameActual()
            : null;

    // Recien aca se pausa: el fotograma ya esta tomado.
    await player.pause().timeout(const Duration(seconds: 2)).catchError((_) {});

    _beginPlaybackShutdown();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    if (saveHistory) {
      try {
        await _saveHistory(frameCapturado: frame);
      } catch (_) {}
    }

    // Timeouts en cada paso: media_kit_video 1.2.5 (versión instalada) tiene
    // un bug de threading confirmado en vivo en Windows ("channel sent a
    // message from native to Flutter on a non-platform thread" — corregido
    // recién en 1.3.1, que no se pudo traer porque arrastra un cascada de
    // upgrades mayores incompatibles: volume_controller, screen_brightness,
    // package_info_plus). Sin este timeout, si ESE bug deja a stop()/
    // dispose() colgado esperando un callback nativo que nunca llega en el
    // hilo correcto, este método (y por lo tanto _lastPlaybackShutdown) no
    // termina NUNCA — waitForPreviousShutdown() en la próxima apertura queda
    // esperando para siempre y toda la pantalla del reproductor se ve
    // congelada (controles pintados pero nada responde). Preferible perder
    // prolijitud en la liberación nativa a que un cuelgue de la librería
    // tilde la apertura siguiente entera.
    try {
      await player.stop().timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 180));
    } catch (_) {}

    if (_playerDisposed) return;
    _playerDisposed = true;
    try {
      await player.dispose().timeout(const Duration(seconds: 3));
    } catch (e) {
      logger.severe('player.dispose error: $e');
    }
  }

  Future<void> closeRoute([BuildContext? context]) async {
    if (_routeClosing) return;
    _routeClosing = true;

    // Callar el audio: lo primero de todo, y SOLO eso.
    //
    // Antes acá se lanzaba el apagado entero. Eso callaba rápido, pero dejaba
    // la captura del fotograma corriendo AL MISMO TIEMPO que la salida de
    // pantalla completa — y esa salida redimensiona la superficie de video
    // justo mientras screenshot() espera un cuadro. Una carrera que a veces se
    // pierde, y cuando se pierde la miniatura de "Continuar viendo" se queda
    // con la del cierre anterior.
    //
    // Bajar el volumen es instantáneo y no toca el video, así que da lo que se
    // buscaba —que deje de sonar apenas se toca salir— sin competir con nada.
    // El apagado, con la captura adentro, va más abajo, cuando la ventana ya
    // dejó de moverse.
    unawaited(player.setVolume(0).catchError((_) {}));

    // Con TOPE, y sin dejar que un fallo frene la salida.
    //
    // Estos dos pasos se esperaban sin limite. Cuando se cae internet, libmpv
    // se queda bloqueado leyendo y satura el hilo de plataforma: estas llamadas
    // —que van por ese mismo hilo— no vuelven nunca, y la pantalla se quedaba
    // sin cerrar. De ahi que hubiera que matar el app entera para salir.
    //
    // Acomodar la ventana es prolijidad; cerrar es lo que el usuario pidio. Si
    // no se puede acomodar a tiempo, se cierra igual — onClose lo vuelve a
    // intentar despues.
    if (isFullScreen.value) {
      await WindowManager.instance
          .setFullScreen(false)
          .timeout(const Duration(seconds: 2))
          .catchError((Object e) {
        logger.warning('No se pudo salir de pantalla completa al cerrar', e);
      });
    }
    // ANTES de popear: así las barras de sistema y la rotación ya están
    // normales cuando la pantalla de destino se dibuja, en vez de depender de
    // que onClose (que corre al destruirse el controller, después del pop)
    // llegue a tiempo. Es idempotente, onClose lo vuelve a llamar sin
    // problema.
    await restoreSystemUiOnExit()
        .timeout(const Duration(seconds: 2))
        .catchError((Object e) {
      logger.warning('No se pudieron restaurar las barras al cerrar', e);
    });

    // Recién ahora el apagado completo. La ventana ya terminó de acomodarse,
    // así que la captura del fotograma no compite con un redimensionado.
    final shutdown = shutdownPlayback();

    var popped = false;
    // Prioridad 1: el context DEL PROPIO widget de controles (pasado por el
    // llamador). WatchPage/VideoPlayer se empuja con
    // Navigator.of(context, rootNavigator: true).push(...) desde
    // resume_history.dart/detail_controller.dart — "rootNavigator: true"
    // busca el Navigator MÁS ANCESTRO en todo el árbol, que en desktop
    // (fluent.FluentApp.router envolviendo un GoRouter con su propio
    // ShellRoute) no es necesariamente el mismo que rootNavigatorKey de
    // router.dart. Confirmado en vivo: con esa ruta abierta,
    // rootNavigatorKey.currentState.maybePop() Y router.canPop()/pop()
    // (que internamente hacen el mismo chequeo) no encontraban nada para
    // popear — el reproductor quedaba en pantalla con el Player YA dispuesto
    // (shutdownPlayback ya corrió arriba) y cada tap sobre los controles
    // tiraba "[Player] has been disposed" hasta que había que cerrar la app
    // entera a mano. Navigator.of(context) SIN rootNavigator busca el
    // Navigator más CERCANO — que, desde un context que vive dentro de esta
    // misma ruta, es por definición el Navigator que la aloja de verdad.
    // ModalRoute.of(context) es la ruta que contiene ESTE reproductor
    // puntual (no "lo que sea que esté arriba", que es lo que hacía
    // ambigüo maybePop() cuando dos pantallas del mismo episodio llegaban a
    // compartir tag de GetX — bug ya corregido de raíz en video_player.dart,
    // tag único por sesión). Con esa causa resuelta, route.isCurrent es
    // confiable: pop() anima la salida normal. removeRoute (sin animación)
    // queda solo como red de seguridad si por lo que sea esta ruta ya no
    // fuera la de arriba.
    if (context != null && context.mounted) {
      final nav = Navigator.maybeOf(context);
      final route = ModalRoute.of(context);
      if (nav != null && route != null && route.isActive) {
        if (route.isCurrent) {
          nav.pop();
        } else {
          nav.removeRoute(route);
        }
        popped = true;
      }
    }
    if (!popped) {
      popped = await rootNavigatorKey.currentState?.maybePop() ?? false;
    }
    if (!popped && Get.key.currentState?.canPop() == true) {
      Get.back();
      popped = true;
    }
    if (!popped && router.canPop()) {
      router.pop();
      popped = true;
    }
    unawaited(shutdown);
  }

  // Tocar una pestaña de servidor solo ELIGE (marca cuál se va a intentar);
  // no resuelve ni reproduce nada todavía — eso pasa recién cuando el
  // usuario toca el botón de play (centro o abajo), que llama switchServer
  // con el nombre que haya quedado acá. Pausa lo que estuviera sonando para
  // no dejar audio de fondo mientras la elección queda pendiente.
  //
  // Suma a la misma "generación" que switchServer: si había un switchServer
  // anterior todavía resolviendo en segundo plano (el usuario tocó play para
  // un servidor y después, antes de que terminara, tocó otra pestaña), sin
  // esto ese intento viejo podía terminar de cargar más tarde y pisar la
  // elección nueva — arrancaba a reproducir el que el usuario ya no quería.
  void selectServer(String name) {
    if (_disposed) return;
    if (!availableServers.containsKey(name)) return;
    ++_switchServerGen;
    _serverRetryCount = 0;
    _triedAndFailedServers.clear();
    _midStreamResumeAt = null;

    // Si es el mismo servidor que ya está efectivamente cargado en el player
    // (el usuario solo estaba mirando otras pestañas y volvió a esta), no hay
    // nada que recargar — antes esto forzaba un switchServer nuevo al tocar
    // "reproducir" y perdía el punto donde estaba, aunque en los hechos no se
    // había cambiado de servidor.
    final canResumeLoadedNativeServer = name == _lastOpenedServerName &&
        hasRenderedFrame.value &&
        serverFailedMessage.value.isEmpty &&
        webViewFallback.value == null &&
        player.state.duration > Duration.zero;
    if (canResumeLoadedNativeServer) {
      currentServerName.value = name;
      awaitingServerChoice.value = false;
      serverFailedMessage.value = '';
      safePlay();
      return;
    }

    currentServerName.value = name;
    awaitingServerChoice.value = true;
    isGettingWatchData.value = false;
    // Limpiar el fallo del servidor ANTERIOR — sin esto, el cartel de "no se
    // puede reproducir" (atado solo a serverFailedMessage, no a
    // awaitingServerChoice) quedaba pegado en pantalla aunque el usuario ya
    // hubiera elegido otro servidor distinto para intentar.
    serverFailedMessage.value = '';
    webViewFallback.value = null;
    webViewOpenedOnce.value = false;
    _bufferingStallTimer?.cancel();
    safePause();
  }

  // Cambia al servidor on-demand:
  //   1. Llama runtime.watch(url) — el wrapper del build maneja 3 casos:
  //        a) URL directa .m3u8/.mp4 → fast-path, devuelve inmediatamente.
  //        b) URL de embed conocido → resolveEmbed on-demand vía SDK.
  //        c) URL de episodio → extensión la procesa normalmente.
  //   2. Si la extensión no puede resolver (error/vacío) → fallback WebView sniffer.
  /// Cambia de servidor, y si se estaba transmitiendo manda el nuevo al mismo
  /// aparato en vez de dejar cada uno con una cosa distinta.
  ///
  /// El cambio de servidor abre el stream nuevo en el reproductor de ACA y no
  /// tocaba el casteo para nada: el televisor se quedaba con el stream viejo, el
  /// telefono arrancaba el nuevo con sonido, y la pantalla seguia diciendo que
  /// se estaba transmitiendo. Dos videos distintos sonando a la vez.
  Future<void> switchServer(String name) async {
    final aparato = dlnaDevice.value;
    if (aparato == null) return _switchServerLocal(name);

    // Cambiar de CALIDAD y cambiar de SERVIDOR no son lo mismo, aunque los dos
    // pasen por aca (ver _servidoresSonCalidades).
    //
    // Una calidad distinta es el MISMO video: se le manda al aparato y sigue
    // donde iba. Un servidor distinto es otra fuente entera, con otro formato y
    // otras cabeceras, y con el Chromecast eso no se puede hacer en caliente:
    // su receptor es una aplicacion web que ya tiene cargado lo anterior, y
    // pisarlo a mitad de camino lo deja en negro sin decir nada. Se corta
    // limpio y se avisa, que es lo unico honesto.
    final esCalidad = _servidoresSonCalidades;
    if (!esCalidad && aparato.esChromecast) {
      sendMessage(Message(Text('video.cast-server-cambiado'.i18n)));
      await disconnectDLNADevice();
      return _switchServerLocal(name);
    }

    // Que el usuario sepa que esta pasando: resolver la fuente y volver a
    // mandarsela al televisor lleva unos segundos, y sin esto la imagen se
    // quedaba congelada sin ninguna señal.
    castConectando.value = true;
    castAviso.value = (esCalidad
            ? 'video.cast-cambiando-calidad'
            : 'video.cast-cambiando-servidor')
        .i18n;

    // Donde iba, para no volver al principio por cambiar de servidor.
    final donde = position.value;
    // Se resuelve EN SILENCIO: abrir el servidor nuevo arranca la reproduccion
    // aca, y sin esto sonaba encima de lo que salia por el televisor.
    final volumenPrevio = player.state.volume;
    try {
      await player.setVolume(0);
    } catch (_) {}
    try {
      await _switchServerLocal(name);
      if (_disposed || watchData == null) return;
      // Se desconecto o se cambio de aparato mientras resolvia: no se le pisa.
      if (dlnaDevice.value != aparato) return;
      // Este servidor va por WebView: no hay una direccion que el televisor
      // pueda pedir, asi que se corta la transmision y se avisa, en vez de
      // dejarla mostrando algo que ya no es lo que se esta viendo.
      if (webViewFallback.value != null || isWebViewActive.value) {
        sendMessage(Message(Text('video.cast-webview'.i18n)));
        await disconnectDLNADevice();
        return;
      }
      // Fallo el cambio: el televisor se queda con lo que ya andaba, que es
      // mejor que cortarle la reproduccion por un servidor que no sirvio.
      if (serverFailedMessage.value.isNotEmpty) return;
      await connectDLNADevice(aparato);
      if (_disposed || dlnaDevice.value != aparato) return;
      await _irAEnElAparato(aparato, donde);
    } finally {
      if (!_disposed) {
        // El aviso se suelta pase lo que pase. Si el cambio fallo, quien lo
        // detecto ya puso SU mensaje —el de formato, el de resolucion— y este
        // encima lo taparia; y si salio bien, dejarlo seria mentir.
        castConectando.value = false;
        if (castAviso.value == 'video.cast-cambiando-calidad'.i18n ||
            castAviso.value == 'video.cast-cambiando-servidor'.i18n) {
          castAviso.value = null;
        }
        try {
          await player.setVolume(volumenPrevio);
        } catch (_) {}
      }
    }
  }

  _switchServerLocal(String name) async {
    if (_disposed) return;
    if (!availableServers.containsKey(name)) return;
    final myGen = ++_switchServerGen;
    serverFailedMessage.value = '';
    webViewFallback.value = null;
    awaitingServerChoice.value = false;
    hasRenderedFrame.value = false;
    // Fuente nueva: se olvida el cuadro anterior y la red se rearma
    // sola con el primer cuadro de esta. Ver hasRenderedFrame.
    _hayCuadro = false;
    _posicionAlPrimerCuadro = null;
    _redDeLaRueda?.cancel();
    _redDeLaRueda = null;
    _lastPositionAdvanceAt = null;
    _lastPositionSeen = null;
    isActuallyBuffering.value = false;
    _clearSeeking();
    _bufferingStallTimer?.cancel();

    final embedUrl = availableServers[name]!;
    logger.info('switchServer: $name → $embedUrl');

    isGettingWatchData.value = true;

    ExtensionBangumiWatch newWatch;
    try {
      newWatch = await runtime.watch(embedUrl, typeHint: ExtensionType.bangumi)
          as ExtensionBangumiWatch;
    } catch (e) {
      if (_isPlaybackClosed(myGen)) return;
      logger.severe('switchServer: runtime.watch falló para $name: $e');
      if (isDirectStream(embedUrl)) {
        // La extensión no sabe manejar URLs directas — intentar reproducir directo
        await _playDirectFallback(name, embedUrl);
      } else {
        final ok = await _trySniff(name, embedUrl,
            timeout: const Duration(seconds: 5));
        if (_isPlaybackClosed(myGen)) return;
        if (!ok) {
          _failOrRetryServer(name);
        } else {
          _isAutoSeekPosition = true;
          _lastOpenedServerName = name;
          _markNativePlayback(name);
          if (_pendingResumeSeconds != null) {
            await player.pause();
            // Pausado a proposito para preguntar: la rueda no puede quedar
            // girando detras del dialogo. Ver hasRenderedFrame.
            _marcarQueYaSeVe('pausado a propósito para preguntar');
            resumePrompt.value = _pendingResumeSeconds;
            _pendingResumeSeconds = null;
          }
        }
      }
      if (myGen == _switchServerGen) isGettingWatchData.value = false;
      return;
    }
    if (_isPlaybackClosed(myGen)) return;

    if (newWatch.url.isEmpty ||
        newWatch.url.startsWith('error://') ||
        newWatch.url.startsWith('page://')) {
      logger.warning(
          'switchServer: extensión retornó error/page para $name (${newWatch.url})');
      if (isDirectStream(embedUrl)) {
        // La extensión no sabe manejar URLs directas — intentar reproducir directo
        await _playDirectFallback(name, embedUrl);
      } else {
        final ok = await _trySniff(name, embedUrl,
            timeout: const Duration(seconds: 5));
        if (_isPlaybackClosed(myGen)) return;
        if (!ok) {
          _failOrRetryServer(name);
        } else {
          _isAutoSeekPosition = true;
          _lastOpenedServerName = name;
          _markNativePlayback(name);
          if (_pendingResumeSeconds != null) {
            await player.pause();
            // Pausado a proposito para preguntar: la rueda no puede quedar
            // girando detras del dialogo. Ver hasRenderedFrame.
            _marcarQueYaSeVe('pausado a propósito para preguntar');
            resumePrompt.value = _pendingResumeSeconds;
            _pendingResumeSeconds = null;
          }
        }
      }
      if (myGen == _switchServerGen) isGettingWatchData.value = false;
      return;
    }

    // Extensión resolvió exitosamente — construir headers y abrir el player
    currentServerName.value = name;
    final headers = <String, String>{};
    // Preservar Referer: del resultado de la extensión o del mapa local
    final referer = newWatch.headers?['Referer'] ?? serverReferers[name];
    if (referer != null) headers['Referer'] = referer;
    // Copiar headers útiles (excluir X-* que solo aplican al listado de episodio)
    //
    // Menos las que son una DECLARACIÓN del servidor sobre cómo hay que leerlo:
    // esas nacen en la carpeta de ese servidor dentro de la extensión y tienen
    // que llegar hasta acá. Se sacan más adelante, antes de abrir nada, para que
    // no salgan a la red como si fueran cabeceras de verdad (ver
    // _tryOpenPlayer).
    if (newWatch.headers != null) {
      for (final e in newWatch.headers!.entries) {
        if (!e.key.startsWith('X-') || e.key == _lecturaContinua) {
          headers[e.key] = e.value;
        }
      }
    }

    watchData = ExtensionBangumiWatch(
      type: newWatch.type,
      url: newWatch.url,
      subtitles: watchData!.subtitles,
      headers: headers.isEmpty ? null : headers,
      audioTrack: watchData!.audioTrack,
    );
    _isAutoSeekPosition = true;

    final opened =
        await _tryOpenPlayer(newWatch.url, headers.isEmpty ? null : headers);
    if (_isPlaybackClosed(myGen)) return;
    if (!opened) {
      // La extensión "resolvió" algo (newWatch.url no está vacío/error/page)
      // pero media_kit no llegó a abrirlo a tiempo — antes de rendirse,
      // reintentar (ver _failOrRetryServer): algunos hosts firman contra un
      // backend elegido al azar en cada resolución, así que una URL nueva
      // puede caer en uno sano.
      _failOrRetryServer(name);
    } else {
      _serverRetryCount = 0;
      serverFailedMessage.value = '';
      _lastOpenedServerName = name;
      _markNativePlayback(name);
      if (isDirectStream(newWatch.url)) unawaited(getQuality());
      // Si había un progreso guardado pendiente de confirmar (recién se
      // arrancó el episodio, no un cambio de servidor a mitad de reproducir),
      // preguntar acá — antes esto solo pasaba por la ruta de servidor único,
      // así que abrir vía switchServer (elegido a mano o recordado) nunca
      // mostraba el diálogo y arrancaba de cero en silencio.
      if (_pendingResumeSeconds != null) {
        await player.pause();
        // Pausado a proposito para preguntar: la rueda no puede quedar
        // girando detras del dialogo. Ver hasRenderedFrame.
        _marcarQueYaSeVe('pausado a propósito para preguntar');
        resumePrompt.value = _pendingResumeSeconds;
        _pendingResumeSeconds = null;
      }
    }
    isGettingWatchData.value = false;
  }

  // 获取 torrent 媒体文件
  getTorrentMediaFile() async {
    if (Get.find<MainController>().btServerisRunning.value == false) {
      await BTServerUtils.startServer();
    }
    sendMessage(
      Message(
        Text('video.torrent-downloading'.i18n),
      ),
    );
    // 下载 torrent
    final torrentFile = path.join(
      PrismHubDirectory.getCacheDirectory,
      'temp.torrent',
    );
    await dio.download(watchData!.url, torrentFile);

    final file = File(torrentFile);
    _torrenHash = await BTServerApi.addTorrent(file.readAsBytesSync());
    final files = await BTServerApi.getFileList(_torrenHash);

    torrentMediaFileList.clear();

    for (final file in files) {
      if (_isSubtitle(file)) {
        subtitles.add(
          SubtitleTrack.uri(
            '${BTServerApi.baseApi}/torrent/$_torrenHash/$file',
            title: path.basename(file),
          ),
        );
      } else {
        torrentMediaFileList.add(file);
      }
    }
  }

  // 获取画质
  getQuality() async {
    final url = watchData!.url;
    // Las cabeceras tal como las trajo la extensión, SIN agregarle un
    // User-Agent de navegador.
    //
    // Se probó agregárselo, porque con Desu (nika.playmudos.com, detrás de
    // Cloudflare) esta consulta contesta 403 y el menú de calidades queda vacío
    // aunque el vídeo se reproduzca perfecto. Funcionó… y salió peor: al
    // conseguir el playlist, se leen las variantes, y eso dispara la elección de
    // calidad de arranque, que llama a switchQuality y **vuelve a abrir la
    // fuente desde cero** a los pocos segundos de haber empezado. Confirmado en
    // vivo: buffering y parones donde antes no había ninguno.
    //
    // O sea que el 403 estaba tapando el problema de rebote. Mientras cambiar de
    // calidad implique reabrir el vídeo entero, conseguir el menú acá sale más
    // caro que no tenerlo. Si algún día la reapertura arranca en el punto donde
    // iba (en vez de en 0 y saltar después), esto se puede volver a intentar.
    final headers = watchData!.headers;
    logger.info(url);

    late dynamic response;
    try {
      response = await dio.get(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        // Red no alcanzable — notificar al usuario
        logger.severe(e);
        if (availableServers.length > 1) {
          serverFailedMessage.value =
              'Servidor "${currentServerName.value}" no disponible.\n'
              'Cambia de servidor con el botón Servidor para ver el anime.';
        } else {
          serverFailedMessage.value =
              'Servidor no disponible. Intenta más tarde.';
        }
      } else {
        // HTTP 4xx/5xx: puede que libmpv lo reproduzca igual (Range headers)
        logger.info(
            'getQuality HTTP error ${e.response?.statusCode}, continuing');
      }
      return;
    } catch (e) {
      logger.severe(e);
      return;
    }

    // 请求判断 content-type 是否为 m3u8
    final contentType = response.headers.value('content-type')?.toLowerCase();
    if (contentType == null ||
        !contentType.contains('mpegurl') &&
            !contentType.contains('m3u8') &&
            !contentType.contains('mp2t')) {
      logger.info('not m3u8');
      return;
    }

    // 接收数据到变量
    final completer = Completer<String>();
    final stream = response.data.stream;
    final buffer = StringBuffer();

    stream.listen(
      (data) {
        buffer.write(utf8.decode(data));
      },
      onDone: () {
        completer.complete(buffer.toString());
      },
      onError: (error) {
        completer.completeError(error);
      },
    );

    String m3u8Content;
    try {
      m3u8Content = await completer.future;
    } catch (e) {
      // El stream de descarga del m3u8 puede cortarse a mitad de camino (red
      // inestable) — sin este try/catch, completer.completeError() de la
      // línea de arriba se propagaba como una excepción de Future sin
      // manejar (getQuality() se llama vía unawaited()).
      logger.severe(e);
      return;
    }
    if (m3u8Content.isEmpty) {
      return;
    }

    late HlsPlaylist playlist;
    try {
      playlist = await HlsPlaylistParser.create().parseString(
        response.realUri,
        m3u8Content,
      );
    } catch (e) {
      // No solo ParserException — parseString no garantiza que sea el único
      // tipo de excepción que puede tirar ante contenido corrupto.
      logger.severe(e);
      return;
    }

    if (playlist is HlsMasterPlaylist) {
      try {
        // Cada calidad sale de SU variante, con la url que trae la variante.
        //
        // Antes se armaba emparejando dos listas por posición: los nombres
        // salían de `variants` y las urls de `mediaPlaylistUrls`. No son la
        // misma lista — mediaPlaylistUrls son las variantes MÁS las pistas de
        // audio, vídeo y subtítulos declaradas aparte. Con que el stream
        // trajera una sola pista de audio separada, los largos ya no
        // coincidían, Map.fromIterables tiraba error, se lo comía el catch de
        // acá y el menú de calidades quedaba VACÍO.
        //
        // Y ahí está lo peor: los streams que ofrecen 1440 y 4K son
        // justamente los que traen el audio aparte. O sea que el menú fallaba
        // sobre todo en los videos donde más importaba. Cuando los largos
        // coincidían de casualidad, el emparejamiento por posición podía
        // asignarle a una resolución la url de otra.
        final porResolucion = <String, _VarianteCalidad>{};
        for (final v in playlist.variants) {
          final w = v.format.width;
          final h = v.format.height;
          final bw = v.format.bitrate ?? 0;
          // Hay variantes que declaran solo BANDWIDTH, sin RESOLUTION. Antes
          // entraban al menú como "nullxnull"; ahora se las nombra por su
          // caudal, que es el único dato que dieron.
          final nombre = (w != null && h != null)
              ? etiquetaCalidad(w, h)
              : bw > 0
                  ? '${(bw / 1000000).toStringAsFixed(1)} Mb/s'
                  : '';
          if (nombre.isEmpty) continue;
          // Misma resolución declarada dos veces (distinto caudal): se queda
          // la de mejor calidad en vez de la que viniera última.
          final previa = porResolucion[nombre];
          if (previa != null && previa.bitrate >= bw) continue;
          porResolucion[nombre] =
              _VarianteCalidad(v.url.toString(), bw, (h ?? 0) * 100000 + bw);
        }

        // De mayor a menor: 4K y 1440 arriba de todo, que es donde se las
        // busca. Antes salían en el orden en que las listaba el sitio.
        final ordenadas = porResolucion.entries.toList()
          ..sort((a, b) => b.value.orden.compareTo(a.value.orden));
        for (final e in ordenadas) {
          qualityMap[e.key] = e.value.url;
        }
        _elegirCalidadInicial(ordenadas);
      } catch (e) {
        logger.severe(e);
      }
    }
  }

  // 播放 torrent 媒体文件
  playTorrentFile(String file) async {
    currentTorrentFile.value = file;
    (player.platform as NativePlayer).setProperty("network-timeout", "60");
    await _ensureVideoSurfaceMounted();
    // _isPlaybackClosed() y no _disposed a secas: este es otro punto que
    // abre audio directo (no pasa por _tryOpenPlayer), así que necesita la
    // misma protección contra _routeClosing. Ver el comentario largo ahí.
    if (_isPlaybackClosed()) return;
    player.open(Media('${BTServerApi.baseApi}/torrent/$_torrenHash/$file'));
  }

  // 切换全屏
  toggleFullscreen() async {
    await WindowManager.instance.setFullScreen(!isFullScreen.value);
    isFullScreen.value = !isFullScreen.value;
  }

  /// El botón manual de pantalla completa en Android. Ver
  /// [pantallaCompletaAndroid].
  void alternarPantallaCompletaAndroid() {
    if (!Platform.isAndroid) return;
    // Cambiar el modo del sistema mientras se está abriendo una fuente
    // nueva (isGettingWatchData) le mueve la superficie al reproductor justo
    // en medio de esa apertura — reportado en vivo un cierre de la app
    // entero al tocar este botón apenas arrancaba a cargar un servidor.
    // Bloqueado mientras carga, igual que el resto de los controles que
    // tocan la fuente (elegir capítulo, servidor): apenas termina, el botón
    // vuelve a responder solo.
    if (isGettingWatchData.value) return;
    pantallaCompletaAndroid.value = !pantallaCompletaAndroid.value;
    // Se aplica ACÁ mismo y no se espera al próximo cambio de orientación:
    // `pantallaSegunOrientacion` ya respeta este valor, pero solo se llama
    // desde la página en cada reconstrucción — tocar el botón tiene que
    // esconder o mostrar las barras EN EL ACTO, no en el próximo cuadro que
    // decida redibujarse por otro motivo.
    if (pantallaCompletaAndroid.value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _barrasDelSistemaVisibles();
    }
  }

  /// Si ya se eligio la calidad de arranque para ESTE video.
  ///
  /// Una sola vez: sin esto, cualquier recarga de la lista de calidades
  /// volveria a mover la calidad y pisaria lo que el usuario haya elegido.
  bool _calidadInicialElegida = false;

  /// Deja el video en 1080p si lo tiene, y si no en lo mejor que tenga.
  ///
  /// El tope por caudal que se le pone a mpv al abrir evita que arranque en 4K,
  /// pero no es exacto: el caudal no es la resolucion. Un 1080p grabado a 12
  /// Mbps queda por ENCIMA de ese tope, asi que mpv elegia el 720p aunque
  /// hubiera 1080p disponible. Aca ya se conocen las alturas reales de cada
  /// variante, que es el dato que de verdad importa.
  ///
  /// No es un tope: el menu sigue ofreciendo todas, y elegir a mano manda.
  void _elegirCalidadInicial(
      List<MapEntry<String, _VarianteCalidad>> deMayorAMenor) {
    if (_calidadInicialElegida || _disposed) return;
    _calidadInicialElegida = true;
    // Con el ajuste encendido no se toca nada: arranca en la mas alta.
    if (PrismHubStorage.getSetting(SettingKey.empezarEnMaximaCalidad) == true) {
      return;
    }
    if (deMayorAMenor.isEmpty) return;
    // Una sola calidad: no hay nada que elegir, y "cambiar" a la que ya está
    // sonando cuesta una reapertura entera del vídeo.
    //
    // Medido en vivo con Streamwish, que publica un maestro con UNA variante:
    // el vídeo tardaba veintiún segundos en arrancar y, un segundo después de
    // aparecer la imagen, se registraba "Calidad de arranque: 720p" y volvía a
    // cargar de cero. Desde afuera: carga, muestra, y se cuelga otra vez.
    //
    // La comprobación de abajo —que evita cambiar a la que ya se está viendo—
    // no lo atrapaba porque compara DIRECCIONES: la del maestro y la de su
    // única variante son distintas aunque el contenido sea exactamente el
    // mismo.
    if (deMayorAMenor.length < 2) {
      logger.info('Una sola calidad (${deMayorAMenor.first.key}): no se cambia '
          'nada, ya es la que se está viendo');
      return;
    }
    // La altura viaja dentro de "orden" (ver _VarianteCalidad).
    int altura(_VarianteCalidad v) => v.orden ~/ 100000;
    // La mejor que no pase de 1080. Si TODAS pasan, la mas chica de todas, que
    // es lo mas cerca de 1080 que ofrece ese video.
    final cabe = deMayorAMenor.where((e) => altura(e.value) <= 1080).toList();
    final elegida = cabe.isNotEmpty ? cabe.first : deMayorAMenor.last;
    // Ya esta reproduciendo esa misma: no se toca, para no recargar de gusto.
    if (watchData?.url == elegida.value.url) return;
    // Casteando tampoco: cambiar la calidad ahi implica volver a mandarselo al
    // aparato, y no es momento de hacerlo por nuestra cuenta.
    if (dlnaDevice.value != null) return;
    logger.info('Calidad de arranque: ${elegida.key}');
    unawaited(switchQuality(elegida.value.url));
  }

  // 切换画质
  switchQuality(String qualityUrl) async {
    final headers = watchData!.headers;

    // Transmitiendo, la calidad nueva va al TELEVISOR.
    //
    // Antes esto solo abria la calidad nueva en el reproductor de aca y no
    // tocaba el casteo: el televisor se quedaba con la calidad vieja y el
    // telefono empezaba a sonar encima con la nueva.
    final aparato = dlnaDevice.value;
    if (aparato != null) {
      // Donde iba, para no volver al principio por cambiar de calidad.
      final donde = position.value;
      // La direccion de la calidad elegida pasa a ser la del contenido, para
      // que el relay le sirva ESA al televisor.
      watchData = ExtensionBangumiWatch(
        type: watchData!.type,
        url: qualityUrl,
        subtitles: watchData!.subtitles,
        headers: headers,
        audioTrack: watchData!.audioTrack,
      );
      // Que se vea que esta cambiando: volver a mandarle el video al televisor
      // lleva unos segundos y la imagen se queda quieta mientras tanto.
      castConectando.value = true;
      castAviso.value = 'video.cast-cambiando-calidad'.i18n;
      try {
        await connectDLNADevice(aparato);
        if (_disposed || dlnaDevice.value != aparato) return;
        await _irAEnElAparato(aparato, donde);
      } finally {
        if (!_disposed) {
          castConectando.value = false;
          // Solo el propio: si el cambio fallo, quien lo detecto ya puso su
          // mensaje —el de formato, el de resolucion— y taparlo seria perder
          // justo lo que explica que paso.
          if (castAviso.value == 'video.cast-cambiando-calidad'.i18n) {
            castAviso.value = null;
          }
        }
      }
      return;
    }

    final currentSecond = player.state.position.inSeconds;
    await _ensureVideoSurfaceMounted();
    if (_disposed) return;
    await player.open(
      Media(qualityUrl, httpHeaders: headers),
    );
    //跳轉到切換之前的時間
    // Antes este timer no se guardaba en ningún campo ni tenía límite de
    // intentos — si el seek real cae en el keyframe más cercano y nunca
    // coincide exactamente con currentSecond (pasa seguido), quedaba
    // llamando player.seek()/player.state cada segundo para siempre, y si
    // el usuario cerraba el reproductor antes de que coincidiera, sobre un
    // Player ya dispuesto. Guardado en un campo (cancelado en onClose) +
    // límite de 10 intentos como red de seguridad.
    _qualitySwitchTimer?.cancel();
    var attempts = 0;
    _qualitySwitchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      attempts++;
      player.seek(Duration(seconds: currentSecond));
      if (player.state.position.inSeconds == currentSecond || attempts >= 10) {
        timer.cancel();
      }
    });
  }

  // 设置字幕
  setSubtitleTrack(SubtitleTrack subtitle) {
    player.setSubtitleTrack(subtitle);
    PrismHubStorage.setSetting(
      SettingKey.subtitleLastLanguageSelected,
      subtitle.language,
    );
    PrismHubStorage.setSetting(
      SettingKey.subtitleLastTitleSelected,
      subtitle.title,
    );
  }

  Future<String?> _historyCoverFallback([History? existing]) async {
    final current = existing?.cover;
    if (current != null && current.isNotEmpty) return current;
    try {
      final cached = await DatabaseService.getPrismHubDetail(
        runtime.extension.package,
        detailUrl,
      );
      if (cached == null) return null;
      final detail = ExtensionDetail.fromJson(jsonDecode(cached.data));
      final cover = detail.cover;
      return cover != null && cover.isNotEmpty ? cover : null;
    } catch (_) {
      return null;
    }
  }

  // Apagar la pantalla o irse a otra app manda la app a `paused`, y Android
  // puede matar el proceso desde ahí sin volver a avisar: onClose no llega a
  // correr nunca y se pierde el minuto que llevabas viendo. Este es el último
  // momento garantizado para dejarlo escrito.
  /// La portada del título, para la notificación. Se resuelve una vez.
  String? _portadaParaNotificacion;

  /// Cuándo se actualizó por última vez lo que muestra la notificación.
  DateTime? _ultimoRefrescoNotificacion;

  /// Pone al día la notificación con lo que está pasando.
  ///
  /// Como máximo una vez por segundo: la posición llega decenas de veces por
  /// segundo y cada actualización cruza al lado nativo. Sin el freno era trabajo
  /// constante para mover un número que igual solo se ve al segundo.
  void _refrescarNotificacion() {
    if (!Platform.isAndroid || _disposed) return;
    final ahora = DateTime.now();
    final ultimo = _ultimoRefrescoNotificacion;
    if (ultimo != null && ahora.difference(ultimo).inMilliseconds < 1000) {
      return;
    }
    _ultimoRefrescoNotificacion = ahora;
    NotificacionReproductor.actualizar(
      dueno: this,
      reproduciendo: isPlaying.value,
      posicion: position.value,
      duracion: duration.value,
    );
  }

  /// Enciende (o refresca) la notificación del reproductor en Android.
  ///
  /// Es la única forma de controlar lo que se está viendo con la app en segundo
  /// plano. Transmitiendo a un televisor es donde más falta hace: la imagen está
  /// en la otra pantalla y el teléfono es el mando, así que salir de la app
  /// dejaba sin manera de pausar o pasar de episodio.
  ///
  /// Cada botón llama a lo que ya existe —los mismos métodos que los botones de
  /// la pantalla— así que no hay un segundo camino que pueda desincronizarse.
  Future<void> _mostrarNotificacion() async {
    if (!Platform.isAndroid || _disposed) return;
    try {
      _portadaParaNotificacion ??= await _historyCoverFallback(
        await DatabaseService.getHistoryByPackageAndUrl(
            runtime.extension.package, detailUrl),
      );
      if (_disposed) return;
      NotificacionReproductor.mostrar(
        dueno: this,
        titulo: title,
        episodio: index.value >= 0 && index.value < playList.length
            ? playList[index.value].name
            : '',
        portada: _portadaParaNotificacion,
        duracion: duration.value,
        reproduciendo: isPlaying.value,
        enTelevisor: dlnaDevice.value != null,
        alReproducir: safePlay,
        alPausar: safePause,
        alSaltar: (donde) => unawaited(seek(donde)),
        // Los mismos límites que los botones de la pantalla: sin esto, tocar
        // "siguiente" en el último episodio se iba fuera de la lista.
        alSiguiente: () {
          if (index.value + 1 < playList.length) index.value++;
        },
        alAnterior: () {
          if (index.value > 0) index.value--;
        },
        alCerrar: () => unawaited(closeRoute()),
      );
    } catch (e) {
      // Sin notificación se puede ver igual: no se corta nada por esto.
      logger.info('No se pudo mostrar la notificación del reproductor: $e');
    }
  }

  /// La app no está en pantalla ahora mismo.
  ///
  /// Importa para el casteo: en segundo plano Android recorta la red (Doze), así
  /// que las consultas al televisor pueden fallar aunque el televisor esté
  /// reproduciendo perfecto. Sin distinguirlo, dejar la app un rato de lado y
  /// volver cortaba una transmisión que estaba sana.
  bool _enSegundoPlano = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // El observador se quita en onClose, pero un aviso puede llegar entre que
    // empieza a destruirse y eso: sin esta guarda se tocaria un reproductor ya
    // liberado, que en media_kit tumba la app entera.
    if (_disposed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _enSegundoPlano = true;
      // ── Se PAUSA al irse de la app ────────────────────────────────────────
      //
      // Acá solo se anotaba el historial y se volvía. O sea que saliendo con la
      // barra del sistema —inicio, recientes, el gesto— el vídeo se quedaba
      // reproduciendo y se seguía escuchando con la app afuera. Reportado en
      // vivo, y parecía intermitente («a veces se corrige solo») porque si
      // después volvías a entrar y cerrabas bien, el apagado normal lo callaba:
      // no era aleatorio, dependía de lo que hicieras después.
      //
      // Los otros dos caminos ya estaban cubiertos —`detached` (cerrar la app)
      // calla el audio unas líneas más abajo, y `closeRoute` baja el volumen en
      // su primera línea—; este era el único que faltaba.
      //
      // Solo en Android, a propósito. En escritorio `hidden` llega al
      // minimizar, y ahí dejar la música sonando es lo que uno espera de una
      // ventana minimizada — nadie reportó lo contrario y pausarle a alguien lo
      // que está escuchando sería peor que el problema.
      //
      // Sin await ni excepción hacia afuera: callar no puede depender de que
      // alguien conteste, y si el reproductor ya está desarmado esto tira y no
      // importa, porque entonces tampoco está sonando.
      if (Platform.isAndroid) {
        try {
          unawaited(player.pause().catchError((_) {}));
        } catch (_) {}
      }
      // refreshHome en false: la pantalla de Home no está visible en ese
      // momento, y refrescarla mientras la app se va es trabajo al pedo.
      unawaited(_touchHistory(refreshHome: false, force: true));
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _enSegundoPlano = false;
      // La hora y la batería se vuelven a esconder.
      //
      // El modo inmersivo se pide UNA sola vez, en onInit, y Android lo suelta
      // al volver de segundo plano — que en un teléfono es tan simple como
      // apagar y encender la pantalla. Cuando lo suelta, la barra de estado se
      // queda puesta arriba del vídeo hasta salir y volver a entrar.
      //
      // Volver a pedirlo no puede romper nada: si ya está puesto, no cambia
      // nada. Mismo arreglo que en la pantalla del navegador interno.
      //
      // Y lo que se vuelve a pedir son las barras VISIBLES, no el modo
      // inmersivo: acá se escondían al volver de segundo plano, así que apagar
      // y encender la pantalla dejaba al usuario sin hora ni barra de
      // navegación aunque el resto del reproductor ya no las esconda.
      if (Platform.isAndroid) {
        _barrasDelSistemaVisibles();
      }
      // Cuenta limpia: los fallos de mientras no estuvo en pantalla no valen,
      // porque pudieron ser del recorte de red y no del televisor.
      _fallosDeCastSeguidos = 0;
      // Y se pregunta YA en vez de esperar a la próxima vuelta del reloj: si
      // mientras tanto el televisor se apagó o alguien le mandó otra cosa, es
      // ahora cuando el usuario está mirando la pantalla.
      if (dlnaDevice.value != null) unawaited(_getDLNAStatus());
      return;
    }

    if (state == AppLifecycleState.detached) {
      // ── Lo PRIMERO: callar el audio ──────────────────────────────────────
      //
      // Reportado en vivo: se cerraba la app y el vídeo se seguía escuchando.
      // El apagado normal no llega a correr acá —es una secuencia larga y el
      // proceso se está muriendo— así que va el de emergencia, que manda las
      // órdenes y no espera a nadie. Ver apagarTodoYa.
      //
      // Antes que soltar el televisor a propósito: eso es una petición por red
      // que puede tardar, y lo que el usuario tiene delante es el sonido.
      apagarTodoYa();

      // Y se le suelta el televisor.
      //
      // Sin esto quedaba reproduciendo nuestro vídeo para siempre, y encima
      // pidiéndoselo a un relay que muere con el proceso — o sea que terminaba
      // en un error o en negro, sin nadie que pudiera pararlo desde la app.
      //
      // Sin await a propósito: en `detached` puede no quedar tiempo para
      // esperar una respuesta por red, y bloquear el cierre sería peor que no
      // llegar a soltarlo.
      final aparato = dlnaDevice.value;
      if (aparato != null) {
        unawaited(aparato.soltar().catchError((Object e) {
          logger.info('No se pudo soltar el aparato al cerrar: $e');
        }));
      }
    }
  }

  Future<void> _touchHistory({
    bool refreshHome = true,
    // El anti-rebote de 5s existe para no escribir en cada tick de
    // reproducción, pero al pasar a segundo plano hay UNA sola oportunidad:
    // si justo se guardó hace 4 segundos, saltearla perdía ese tramo.
    bool force = false,
  }) async {
    if (_disposed || _historyTouchInFlight) return;
    final now = DateTime.now();
    if (!force &&
        _lastHistoryTouchAt != null &&
        now.difference(_lastHistoryTouchAt!) < const Duration(seconds: 5)) {
      return;
    }
    _historyTouchInFlight = true;
    _lastHistoryTouchAt = now;
    try {
      final existing = await DatabaseService.getHistoryByPackageAndUrl(
        runtime.extension.package,
        detailUrl,
      );
      if (_disposed) return;
      final cover = await _historyCoverFallback(existing);
      final epName = playList[index.value].name;
      // El respaldo a los valores crudos de mpv solo vale SIN recorte: con él,
      // los de mpv son los del pedazo y meterían en el historial una posición
      // que no es la del episodio. Ver el comentario largo en _saveHistory.
      final conRecorte = _recorte != null;
      final totalSeconds = duration.value.inSeconds > 0 || conRecorte
          ? duration.value.inSeconds
          : player.state.duration.inSeconds;
      final progressSeconds = position.value.inSeconds > 0 || conRecorte
          ? position.value.inSeconds
          : player.state.position.inSeconds;
      await DatabaseService.putHistory(
        History()
          ..url = detailUrl
          ..cover = cover
          ..episodeGroupId = episodeGroupId
          ..package = runtime.extension.package
          ..type = ExtensionType.bangumi
          ..episodeId = index.value
          ..episodeTitle = epName
          ..title = title
          ..progress = progressSeconds.toString()
          ..totalProgress = totalSeconds > 0 ? totalSeconds.toString() : ''
          ..isNsfw = isNsfw
          // Al día solo si es el último episodio Y ya lo terminó. OJO: esto
          // corre apenas ARRANCA la reproducción, así que decidirlo solo por la
          // posición en la lista marcaba completado en el segundo uno y sacaba
          // el episodio de "Continuar viendo" mientras se estaba mirando.
          ..watchState = calcularWatchState(
            index: index.value,
            total: playList.length,
            progreso: progressSeconds,
            progresoTotal: totalSeconds,
          )
          // Referencia para detectar episodios nuevos más adelante.
          ..knownEpisodeCount = playList.length
          // Abrió el episodio: la novedad deja de serlo.
          ..newEpisodeLabel = null,
      );
      if (refreshHome) {
        await HomePageController.refreshAll();
      }
    } catch (e) {
      logger.warning('touch history fallÃ³: $e');
    } finally {
      _historyTouchInFlight = false;
    }
  }

  /// Nombre base de las capturas de ESTE episodio. Todas las versiones
  /// guardadas empiezan así, y por eso se pueden encontrar y limpiar después.
  String get _baseFrame => md5
      .convert(utf8.encode('${title}_${playList[index.value].name}'))
      .toString();

  Directory get _dirFrames => Directory(
      path.join(PrismHubDirectory.getCacheDirectory, 'history_cover'));

  /// Guarda un frame nuevo y devuelve su ruta.
  ///
  /// La ruta lleva una marca de tiempo A PROPÓSITO. Antes era fija —el md5 del
  /// título y el episodio— así que al volver a mirar se sobrescribía el MISMO
  /// archivo. Flutter cachea las imágenes decodificadas por ruta, no por
  /// contenido: la tarjeta seguía mostrando el primer frame para siempre aunque
  /// en disco ya hubiera otro. Se veía como que la captura solo se actualizaba
  /// la primera vez.
  ///
  /// Sacar la imagen de la caché a mano no alcanzaba: las tarjetas la piden con
  /// `cacheWidth` (ver HomeMediaCard), y eso envuelve el proveedor en un
  /// ResizeImage con su propia clave — y con tres anchos distintos según dónde
  /// se dibuje. Con una ruta nueva por captura la clave cambia sola y no queda
  /// nada que invalidar, ni en el Inicio, ni en la Zona +18, ni en el Historial.
  ///
  /// Las capturas anteriores de este mismo episodio se borran acá, así que en
  /// disco queda siempre una sola por episodio.
  Future<String?> _guardarFrame(Uint8List bytes) async {
    try {
      final dir = _dirFrames;
      await dir.create(recursive: true);
      final base = _baseFrame;
      final destino = File(path.join(
        dir.path,
        '$base-${DateTime.now().millisecondsSinceEpoch}',
      ));
      await destino.writeAsBytes(bytes, flush: true);
      await _limpiarFramesViejos(base, conservar: destino.path);
      return destino.path;
    } catch (e) {
      logger.warning('No se pudo guardar el frame del vídeo: $e');
      return null;
    }
  }

  /// Borra las capturas anteriores del episodio, menos la que se acaba de
  /// escribir. Incluye el archivo de nombre fijo que dejaban las versiones
  /// anteriores de la app.
  Future<void> _limpiarFramesViejos(String base,
      {required String conservar}) async {
    try {
      final dir = _dirFrames;
      if (!await dir.exists()) return;
      await for (final entidad in dir.list()) {
        if (entidad is! File) continue;
        final nombre = path.basename(entidad.path);
        if (nombre != base && !nombre.startsWith('$base-')) continue;
        if (entidad.path == conservar) continue;
        try {
          await entidad.delete();
        } catch (_) {
          // Puede estar en uso por un decode en curso; se limpia la próxima vez.
        }
      }
    } catch (e) {
      logger.warning('No se pudieron limpiar los frames viejos: $e');
    }
  }

  /// Última captura guardada de este episodio, o null si no hay ninguna. Se usa
  /// cuando no se pudo tomar una nueva, para no perder la que ya había.
  Future<String?> _frameGuardado() async {
    try {
      final dir = _dirFrames;
      if (!await dir.exists()) return null;
      final base = _baseFrame;
      File? mejor;
      DateTime? mejorFecha;
      await for (final entidad in dir.list()) {
        if (entidad is! File) continue;
        final nombre = path.basename(entidad.path);
        if (nombre != base && !nombre.startsWith('$base-')) continue;
        final fecha = (await entidad.stat()).modified;
        if (mejorFecha == null || fecha.isAfter(mejorFecha)) {
          mejor = entidad;
          mejorFecha = fecha;
        }
      }
      return mejor?.path;
    } catch (e) {
      logger.warning('No se pudo leer el frame guardado: $e');
      return null;
    }
  }

  /// Toma el frame que se está viendo justo ahora, para usarlo de portada en
  /// "Continuar viendo". Nunca lanza y nunca se cuelga: si no se puede, la
  /// tarjeta se queda con la portada de siempre.
  Future<Uint8List?> _capturarFrameActual() async {
    // hasRenderedFrame: sin un frame pintado, screenshot() devuelve negro.
    if (_disposed || _playerDisposed || !hasRenderedFrame.value) return null;
    try {
      return await player.screenshot().timeout(const Duration(seconds: 2));
    } catch (e) {
      logger.warning('No se pudo capturar el frame del video: $e');
      return null;
    }
  }

  // 保存历史记录
  _saveHistory(
      {bool captureScreenshot = true, Uint8List? frameCapturado}) async {
    // Envuelto entero: crea directorios, saca una captura del player y
    // escribe archivos. Cualquiera de esas cosas puede fallar por espacio,
    // permisos o porque el player ya se está cerrando — y como esto se
    // llama desde caminos sin await (cierre, cambio de episodio), una
    // excepción acá sería un error asíncrono sin dueño. Guardar el
    // progreso es "mejor esfuerzo": que falle no debe romper nada más.
    try {
      if (duration.value.inSeconds == 0) {
        return;
      }

      final epName = playList[index.value].name;

      // Transmitiendo, el progreso lo lleva el TELEVISOR, no el reproductor de
      // aca — que esta parado a proposito desde que empezo el casteo.
      //
      // Se leia player.state.position/duration, que en ese rato valen cero: al
      // salir del episodio mientras se casteaba se guardaba progreso 0 y se
      // perdia todo lo visto. Las Rx position/duration si estan al dia, porque
      // el timer de estado las va llenando con lo que informa el aparato.
      // Se mira tambien _casteabaAlCerrar: al cerrar el reproductor, el
      // desmontaje suelta el aparato ANTES de llegar aca, asi que preguntar
      // solo por dlnaDevice daria false justo en el caso que importa.
      // ── Se guarda la posición del EPISODIO, no la de mpv ─────────────────
      //
      // Con el recorte de fMP4, mpv reproduce un pedazo que arranca en cero, así
      // que `player.state.position` es la posición DENTRO del pedazo. Guardando
      // eso, estar en el minuto 14 de un episodio abierto desde el 13:54 se
      // anotaba como **6 segundos**, y al volver el diálogo ofrecía continuar en
      // 00:06. Visto en vivo.
      //
      // `position.value` es la misma posición cuando no hay recorte —el desfase
      // vale cero— y la correcta cuando lo hay. Igual para la duración: con
      // recorte, la de mpv es la del pedazo, y guardarla haría que el vídeo
      // pareciera más corto de lo que es.
      final casteando = dlnaDevice.value != null || _casteabaAlCerrar;
      final posicionSeg = !casteando
          ? position.value.inSeconds
          : (dlnaDevice.value != null
              ? position.value.inSeconds
              : _posicionCastAlCerrar.inSeconds);
      final duracionSeg = !casteando
          ? duration.value.inSeconds
          : (dlnaDevice.value != null
              ? duration.value.inSeconds
              : _duracionCastAlCerrar.inSeconds);

      // ── El progreso que se guarda tiene que ser creíble ──────────────────
      //
      // Si la posición cae fuera de la duración, no se guarda: se deja en cero
      // y el vídeo empieza de nuevo la próxima vez.
      //
      // Por qué hace falta: hay fuentes donde la posición y la duración crecen
      // mientras el vídeo carga (anotado en PROGRESO para Pornhub, medido: la
      // lista es VOD y trae su marca de final, así que el problema es de este
      // lado). Cuando eso pasa se guardaba una posición inventada, y a la
      // siguiente reproducción el reanudar saltaba ahí: el usuario abría un
      // vídeo y arrancaba en cualquier lado. Peor todavía, mpv pedía un
      // pedacito muy adelantado y el CDN contestaba 410 — visto en vivo,
      // «Failed to open segment 202 of playlist 0» repetido hasta rendirse.
      //
      // El candado va acá, al GUARDAR, y no solo al reanudar: una vez que el
      // número malo entra a la base, se arrastra a la lista de Continuar, al
      // Historial y al porcentaje. Mejor no dejarlo entrar.
      //
      // Vale para todas las extensiones a propósito: la posición puede salirse
      // de rango en cualquier fuente de HLS, y guardar algo imposible nunca es
      // lo correcto.
      final progresoCreible =
          duracionSeg > 0 && posicionSeg >= 0 && posicionSeg <= duracionSeg;
      if (!progresoCreible && duracionSeg > 0) {
        logger.info('historial: no se guarda una posición imposible '
            '($posicionSeg s sobre $duracionSeg s de duración)');
      }
      final posicionAGuardar = progresoCreible ? posicionSeg : 0;

      // El frame puede venir ya tomado desde _shutdownPlayback (el caso normal
      // al cerrar el reproductor, donde capturar acá sería tarde) o tomarse en
      // el momento, para las llamadas que ocurren con la reproducción viva.
      //
      // Casteando no se intenta capturar: el reproductor de aca esta parado y
      // la captura saldria negra, pisando la buena que ya estaba guardada.
      final data = frameCapturado ??
          ((captureScreenshot && !casteando)
              ? await _capturarFrameActual()
              : null);

      logger.info('save history');

      // Si no se pudo capturar nada, se conserva la última que hubiera: no
      // tener frame nuevo no es motivo para perder el que ya estaba.
      final savedCover =
          data != null ? await _guardarFrame(data) : await _frameGuardado();
      await DatabaseService.putHistory(
        History()
          ..url = detailUrl
          ..cover = savedCover ?? await _historyCoverFallback()
          ..episodeGroupId = episodeGroupId
          ..package = runtime.extension.package
          // ExtensionType.bangumi fijo (no runtime.extension.type): este
          // controller SOLO se usa para video — para una extensión "mixed"
          // (ej. ShadeManga) usar el tipo fijo de la extensión guardaría
          // "mixed" en el historial, que ExtensionTypeBadge/typeToString no
          // saben mostrar como "video" ni "lectura".
          ..type = ExtensionType.bangumi
          ..episodeId = index.value
          ..episodeTitle = epName
          ..title = title
          ..progress = posicionAGuardar.toString()
          ..totalProgress = duracionSeg.toString()
          ..isNsfw = isNsfw
          // Al día solo si es el último episodio Y llegó al final de verdad.
          ..watchState = calcularWatchState(
            index: index.value,
            total: playList.length,
            progreso: posicionSeg,
            progresoTotal: duracionSeg,
          )
          // Referencia para detectar episodios nuevos más adelante.
          ..knownEpisodeCount = playList.length
          // Abrió el episodio: la novedad deja de serlo.
          ..newEpisodeLabel = null,
      );
      await HomePageController.refreshAll();
    } catch (e, st) {
      logger.warning('No se pudo guardar el historial de vídeo: \$e', e, st);
    }
  }

  // Progreso acumulado mientras se mira por el fallback de WebView. Vive acá
  // (no en WebViewPlayerPage) para que sobreviva a un cambio de servidor: si
  // el usuario prueba otro servidor, se cierra la página WebView vieja y se
  // abre una nueva — sin este contador a nivel controller, cada cambio de
  // servidor reiniciaba el progreso guardado a 0. Se resetea en play() (nuevo
  // episodio), no al cambiar de servidor dentro del mismo episodio.
  int _webViewElapsedSeconds = 0;

  // Guarda progreso mientras se mira por el fallback de WebView (botón
  // "Abrir en el navegador"). Ese modo no usa el player nativo (media_kit),
  // así que _saveHistory() de arriba no sirve: no hay player.state.position
  // ni player.screenshot() real. Se usa en cambio un contador de segundos
  // transcurridos (aproximado, no la posición real del video del sitio) y
  // una captura de la propia WebView como portada — mismo mecanismo, otra
  // fuente. Sin esto, mirar por WebView nunca aparecía en "Continuar viendo".
  // La captura cruda de la WebView trae la barra de progreso/controles del
  // reproductor propio del sitio pegada abajo (parte de la página, no algo
  // que podamos ocultar antes de capturar) — se veía como una línea fina en
  // la portada de "Continuar viendo", reportado en vivo con captura. Se
  // recorta esa franja inferior y se escala el resto de vuelta al tamaño
  // original (zoom), así la portada queda como un frame limpio.
  Uint8List _cropWebViewPlayerBar(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return bytes;
      const cropFraction = 0.08;
      final cropPx = (image.height * cropFraction).round();
      if (cropPx <= 0 || cropPx >= image.height) return bytes;
      final cropped = img.copyCrop(
        image,
        x: 0,
        y: 0,
        width: image.width,
        height: image.height - cropPx,
      );
      final zoomed = img.copyResize(
        cropped,
        width: image.width,
        height: image.height,
      );
      return Uint8List.fromList(img.encodePng(zoomed));
    } catch (e) {
      logger.warning('No se pudo recortar la captura del WebView: $e');
      return bytes;
    }
  }

  Future<void> saveWebViewProgress(Uint8List? screenshot,
      {bool isFinal = false}) async {
    _webViewElapsedSeconds += 15;
    final epName = playList[index.value].name;
    // Solo la captura FINAL (al salir/pasar a segundo plano) actualiza la
    // portada guardada — ver WebViewPlayerPage._captureFinalProgress. Las
    // llamadas periódicas (isFinal:false) ya vienen con screenshot:null
    // desde ahí, pero se chequea isFinal explícitamente para no depender
    // solo de esa convención.
    //
    // Esa captura final SIEMPRE pisa a la anterior, venga de donde venga.
    // Antes se protegía el frame nativo para que una captura de WebView no lo
    // reemplazara, pero eso dejaba clavada la portada de la primera vez: si
    // retomabas por WebView y salías en otro punto del vídeo, la tarjeta seguía
    // mostrando dónde habías quedado la sesión anterior. Lo último que miraste
    // es lo que corresponde ver.
    String? savedCover;
    if (isFinal && screenshot != null) {
      savedCover = await _guardarFrame(_cropWebViewPlayerBar(screenshot));
    }
    savedCover ??= await _frameGuardado();
    final fallbackCover = savedCover ?? await _historyCoverFallback();

    await DatabaseService.putHistory(
      History()
        ..url = detailUrl
        ..cover = fallbackCover
        ..episodeGroupId = episodeGroupId
        ..package = runtime.extension.package
        // ExtensionType.bangumi fijo (no runtime.extension.type): este
        // controller SOLO se usa para video — para una extensión "mixed"
        // (ej. ShadeManga) usar el tipo fijo de la extensión guardaría
        // "mixed" en el historial, que ExtensionTypeBadge/typeToString no
        // saben mostrar como "video" ni "lectura".
        ..type = ExtensionType.bangumi
        ..episodeId = index.value
        ..episodeTitle = epName
        ..title = title
        ..progress = _webViewElapsedSeconds.toString()
        // Total desconocido a propósito (no hay forma de saber la duración
        // real del video del sitio desde acá) — el resto de la app ya trata
        // un totalProgress vacío como "sin dato", no como "recién empezado".
        ..totalProgress = ''
        ..isNsfw = isNsfw
        // Por WebView no hay duración real del video del sitio, así que
        // calcularWatchState no puede confirmar que haya terminado y lo deja
        // en curso. Es a propósito: preferimos que sobre en "Continuar" antes
        // que esconder algo a medias.
        ..watchState = calcularWatchState(
          index: index.value,
          total: playList.length,
          progreso: _webViewElapsedSeconds,
          progresoTotal: 0,
        )
        // Referencia para detectar episodios nuevos más adelante.
        ..knownEpisodeCount = playList.length
        // Abrió el episodio: la novedad deja de serlo.
        ..newEpisodeLabel = null,
    );
    await HomePageController.refreshAll();
  }

  // 判断文件是否是字幕
  _isSubtitle(String file) {
    return file.endsWith('.srt') ||
        file.endsWith('.vtt') ||
        file.endsWith(".ass");
  }

  // 发送消息
  sendMessage(Message message) {
    messageQueue.add(message);

    if (messageQueue.length == 1) {
      _processNextMessage();
    }
  }

  // 处理消息提示
  _processNextMessage() async {
    if (messageQueue.isEmpty) {
      cuurentMessageWidget.value = null;
      return;
    }

    final message = messageQueue.first;
    cuurentMessageWidget.value = message.child;
    // 等待消息显示完毕
    await Future.delayed(message.time);
    messageQueue.removeAt(0);
    _processNextMessage();
  }

  // 切换侧边栏
  // Tocar el MISMO botón del footer con el panel ya abierto en ese tab lo
  // cierra (comportamiento de toggle de siempre); tocar OTRO botón mientras
  // el panel ya está abierto cambia el contenido en vez de solo cerrarlo —
  // antes cualquier botón cerraba el panel sin importar cuál se tocó, así
  // que ir de "Episodios" a "Servidor" necesitaba dos toques.
  /// ¿Hay algo entre lo que elegir para cambiar la calidad?
  ///
  /// Las calidades llegan por DOS caminos distintos y hasta ahora solo se
  /// miraba uno:
  ///
  ///  - `qualityMap` se llena leyendo el playlist maestro de un HLS.
  ///  - `availableServers` se llena con la cabecera X-Servers que manda la
  ///    extensión, y ahí es donde vienen las calidades de los sitios que
  ///    entregan un MP4 por resolución — Eporner manda las siete así.
  ///
  /// El nombre "servidores" quedó de cuando esa cabecera se usaba solo para
  /// eso, pero lo que trae es lo que la extensión ofrezca: en unos casos son
  /// servidores alternativos y en otros son calidades.
  ///
  /// Mirando solo `qualityMap`, el botón de calidad respondía "no hay
  /// calidades" en un vídeo que tenía siete. Se veía en el teléfono, donde el
  /// botón de calidad es la única forma de cambiarla.
  bool get hayCalidades => qualityMap.isNotEmpty || _servidoresSonCalidades;

  /// ¿Lo que hay en `availableServers` son CALIDADES y no servidores?
  ///
  /// La cabecera X-Servers se usa para las dos cosas segun la extension: unas
  /// mandan fuentes alternativas ("Voe", "StreamWish", "Servidor 2") y otras
  /// una url por resolucion ("2160p(4K) HD", "1080p HD"). Por el nombre del
  /// campo no se distinguen, pero por el de las entradas si.
  ///
  /// Se exige que TODAS parezcan una resolucion. Con una sola que no lo sea ya
  /// es una lista de servidores: mejor mostrarla como servidores —que es lo que
  /// mas se parece a la verdad— que esconder fuentes que el usuario necesita
  /// para poder reproducir.
  bool get _servidoresSonCalidades =>
      availableServers.isNotEmpty &&
      availableServers.keys.every(_pareceCalidad);

  static bool _pareceCalidad(String nombre) {
    final n = nombre.toLowerCase();
    // "1080p", "2160p(4k) hd", "720 p"… y las formas cortas 4K/2K/8K.
    //
    // El `\d*` después de la "p" es para los sitios que pegan los cuadros por
    // segundo al final: "720p60", "1080p60". Sin eso ahí no hay separación de
    // palabra entre la "p" y el "6", así que esa etiqueta NO parecía una
    // calidad — y como se exige que TODAS lo parezcan, una sola con fps hacía
    // que la lista entera se tomara por servidores y subiera a la tira de
    // arriba, duplicando lo que ya ofrece el botón de calidad.
    return RegExp(r'\d{3,4}\s*p\d*\b').hasMatch(n) ||
        RegExp(r'\b[248]k\b').hasMatch(n);
  }

  /// Qué panel abrir al tocar el botón de calidad, según de dónde vengan.
  ///
  /// ── Manda dónde hay algo PARA ELEGIR ────────────────────────────────────
  ///
  /// Antes alcanzaba con que el HLS trajera una variante para abrir su panel. Y
  /// hay sitios donde el maestro trae UNA SOLA: cada resolución es un maestro
  /// aparte, y las demás llegan por la cabecera de la extensión.
  ///
  /// Ahí la cuenta salía al revés: el panel de calidades se abría con una única
  /// opción —la que ya estaba sonando— y las otras tres o cuatro quedaban
  /// invisibles, en el otro panel, aunque la extensión las hubiera mandado.
  /// Medido en un teléfono: el registro decía «Una sola calidad (1080p)» y el
  /// botón mostraba solo esa, con 1080p a 4 Mbps como única salida.
  ///
  /// Ahora se abre el panel que de verdad tiene de qué elegir. Con dos o más
  /// variantes en el HLS gana el HLS, que es la fuente más fiel. Con una sola,
  /// y si lo que mandó la extensión son resoluciones, se ofrecen esas.
  ///
  /// Y si un vídeo tiene UNA calidad y nada más, se sigue abriendo su panel con
  /// esa: no se pide nada de más ni se inventan opciones que no existen.
  SidebarTab get pestanaDeCalidad {
    if (qualityMap.length > 1) return SidebarTab.qualitys;
    if (_servidoresSonCalidades) return SidebarTab.servers;
    return qualityMap.isNotEmpty ? SidebarTab.qualitys : SidebarTab.servers;
  }

  /// Ver un vídeo VR en una sola imagen, sin gafas.
  ///
  /// Los vídeos VR vienen con las dos vistas lado a lado en el mismo cuadro:
  /// la del ojo izquierdo y la del derecho, casi iguales. Con gafas eso da la
  /// profundidad; sin gafas se ve la misma escena repetida dos veces, cada una
  /// aplastada a la mitad del ancho. Es inmirable, y es lo que le pasa a
  /// cualquiera que abra un VR en un teléfono o en la computadora.
  ///
  /// Activado, se recorta el cuadro a la mitad izquierda y se muestra solo esa
  /// vista. Se pierde el efecto 3D —que sin gafas no existía igual— y queda una
  /// imagen normal, con su proporción correcta.
  ///
  /// Es un filtro de mpv y no un recorte del reproductor: el recorte se hace
  /// antes de dibujar, así que no cuesta un cuadro de más ni pelea con el
  /// tamaño de la ventana.
  final vrUnaPantalla = false.obs;

  /// El recorte, escrito para el mpv que trae media_kit.
  ///
  /// `crop` a secas NO existe: es sintaxis del mplayer viejo y mpv la rechaza
  /// con "Option vf: crop doesn't exist" (visto en vivo al probar esto). El
  /// recorte de verdad lo pone FFmpeg, y a los filtros de FFmpeg se llega por
  /// el envoltorio `lavfi`.
  ///
  /// iw/ih son el ancho y el alto de ENTRADA, así que sirve para cualquier
  /// resolución sin consultarla antes. La posición 0:0 toma la mitad
  /// izquierda, que es la vista del ojo izquierdo.
  static const _filtroVr = 'lavfi=[crop=iw/2:ih:0:0]';

  /// Desplazamiento del recorte, de 0 a 1, dentro de la mitad sobrante.
  ///
  /// 0 muestra la vista del ojo izquierdo, 1 la del derecho, y el medio queda
  /// entre las dos. Sirve para mirar el resto del cuadro sin gafas.
  final vrDesplazamiento = 0.0.obs;

  /// ¿Este video es VR?
  ///
  /// Los VR vienen con las dos vistas lado a lado, o sea el doble de ancho que
  /// un video normal para la misma altura. Con eso alcanza para reconocerlos
  /// sin preguntarle nada al sitio.
  ///
  /// Se mira desde UN solo lugar para que los ajustes y el tutorial coincidan:
  /// no puede pasar que el tutorial explique como mover la camara y el ajuste
  /// para hacerlo no este.
  /// OBSERVABLE y no un getter suelto.
  ///
  /// Como getter leia player.state, que no es reactivo, asi que un Obx que solo
  /// mirara esto no tenia a que suscribirse: GetX lo detecta y tira "improper
  /// use of a GetX has been detected", con el panel de ajustes mostrando el
  /// error en vez de los ajustes.
  ///
  /// Siendo observable, ademas, la interfaz se acomoda sola cuando el video
  /// termina de cargar y recien ahi se conocen sus medidas.
  final esVideoVr = false.obs;

  /// Si el video parece estar grabado para gafas.
  ///
  /// Antes se pedia que fuera 3 veces mas ancho que alto, y eso dejaba afuera
  /// el formato VR mas comun: un **180 lado a lado** es 2:1 (3840x1920) y uno
  /// **arriba-abajo** es 1:1. Solo un 360 lado a lado llega a 3:1, asi que el
  /// interruptor no aparecia justo en los videos donde mas se usa.
  ///
  /// Pero 2:1 y 1:1 son tambien proporciones de video normal, asi que ahi sola
  /// la forma no alcanza y se mira el nombre: estos videos vienen casi siempre
  /// marcados como VR, 180, 360, SBS o 3D. Con una forma imposible para un
  /// video normal no hace falta ninguna pista.
  @visibleForTesting
  static bool pareceVr(int? w, int? h, String pistas) =>
      _pareceVr(w, h, pistas);

  static bool _pareceVr(int? w, int? h, String pistas) {
    if (w == null || h == null || w <= 0 || h <= 0) return false;
    final proporcion = w / h;
    // Tan ancho que no puede ser otra cosa.
    if (proporcion >= 2.9) return true;
    // De 1:1 en adelante, con el nombre diciendolo.
    if (proporcion < 0.9) return false;
    // ── Las pistas tienen que ser PALABRAS, no trozos ────────────────────
    //
    // Antes esto buscaba `180|360|sbs|3d` en cualquier parte del texto, y en
    // las pistas entra la DIRECCION del video. Casi todas llevan la calidad
    // ahi —`360p`, `720p`— y `360p` contiene `360`: el interruptor de VR
    // aparecia en practicamente todos los videos. Reportado en Android.
    //
    // Lo mismo con `3d` y `sbs` dentro de un hash cualquiera: `a3d9f2` traia
    // `3d`, y esos identificadores estan en casi todas las direcciones.
    //
    // Ahora cada marca tiene que ir suelta: sin letra ni numero pegado de
    // ningun lado. Asi `360p` NO cuenta (le sigue una p) y `1360` tampoco (le
    // precede un numero), pero `vr 360`, `_360_` o `360°` si.
    return RegExp(
      r'(^|[^a-z0-9])(vr|sbs|3d|180|360)([^a-z0-9]|$)'
      r'|over.?under',
      caseSensitive: false,
    ).hasMatch(pistas);
  }

  /// El texto donde buscar esas pistas: como se llama el video y de donde sale.
  String get _pistasDeVr => [
        title,
        if (index.value >= 0 && index.value < playList.length)
          playList[index.value].name,
        watchData?.url ?? '',
      ].join(' ');

  /// Estirar la imagen para que ocupe toda la pantalla.
  ///
  /// Para videos NORMALES. Un video con otra proporcion que la pantalla deja
  /// franjas negras, y en el telefono —donde la pantalla es alta y angosta—
  /// esas franjas se comen medio alto. Activado se recorta un poco a los lados
  /// a cambio de llenar.
  ///
  /// Se guarda por video y no como ajuste global a proposito: es una decision
  /// de "este contenido puntual", no una preferencia permanente.
  final llenarPantalla = false.obs;

  /// Ya se reintento este contenido con decodificacion por software.
  /// Se limpia al cargar contenido nuevo (ver donde se reinicia el estado).
  bool _reintentoPorSoftware = false;

  /// Vuelve a abrir lo mismo, pero decodificando por software.
  ///
  /// Se conserva la posicion: si el fallo aparecio a mitad de reproduccion, no
  /// hay por que volver al principio.
  Future<void> _reintentarSinHardware() async {
    if (_disposed || player.platform is! NativePlayer) return;
    final np = player.platform as NativePlayer;
    final donde = position.value;
    try {
      await np.setProperty('hwdec', 'no');

      // ── Con recorte se reabre la LISTA RECORTADA, no la de la red ────────
      //
      // Sin esto, el reintento abría `watchData.url` —el m3u8 original de
      // zilla— y el recorte quedaba fuera de juego. En Android eso pasaba
      // SIEMPRE: el AV1 de AnimeAV1 no abre por hardware, así que este camino
      // se dispara en cada apertura.
      //
      // Consecuencias que se vieron en vivo, y que no se entendían: el vídeo
      // arrancaba en un minuto que nadie pidió, la barra y el salto se
      // comportaban distinto que en PC, y ninguno de los arreglos del recorte
      // parecía tener efecto en el teléfono — porque mpv no estaba
      // reproduciendo la lista recortada.
      final recorte = _recorte;
      if (recorte != null) {
        logger.info('recorte fMP4: el reintento por software vuelve a la lista '
            'recortada, no a la de la red');
        await _saltarConRecorte(recorte, donde);
        return;
      }

      final actual = watchData;
      if (actual == null) return;
      await player.open(Media(actual.url, httpHeaders: actual.headers));
      // Mismo cuidado que en "continuar viendo": pedirle el salto a mpv
      // apenas vuelve open() se pierde si todavia no conoce la duracion.
      if (donde > Duration.zero) await _saltarCuandoSePueda(donde);
    } catch (e) {
      logger.warning('El reintento por software tambien fallo', e);
    }
  }

  /// Mueve la imagen del VR a lo ancho del cuadro.
  ///
  /// Con el recorte puesto se ve una porción del vídeo, y sin gafas no hay
  /// forma de mirar el resto: la parte de afuera queda inalcanzable. Corriendo
  /// el recorte se puede recorrer el cuadro entero.
  ///
  /// No hace nada si el modo VR está apagado: ahí se ve todo y no hay nada que
  /// recorrer.
  Future<void> moverVr(double delta) async {
    if (!vrUnaPantalla.value || player.platform is! NativePlayer) return;
    final nuevo = (vrDesplazamiento.value + delta).clamp(0.0, 1.0);
    if (nuevo == vrDesplazamiento.value) return;
    vrDesplazamiento.value = nuevo;
    await _aplicarRecorteVr(player.platform as NativePlayer, true);
  }

  /// Aplica el recorte con las medidas REALES del vídeo.
  ///
  /// Se usa `video-crop`, que es la opción que mpv tiene para esto, en vez de
  /// meter un filtro en la cadena de `vf`. Con `vf` hay que acertarle a una
  /// sintaxis —`crop=…` es del mplayer viejo y no existe; el envoltorio
  /// `lavfi` depende de cómo esté compilado— y si no se acierta, mpv rechaza la
  /// orden y el recorte no pasa. `video-crop` toma píxeles y ya.
  ///
  /// Las medidas salen del propio reproductor, así que no hay que adivinar
  /// resolución. Si todavía no las reporta, no se intenta: sin ancho no hay
  /// mitad que recortar.
  Future<bool> _aplicarRecorteVr(NativePlayer np, bool activar) async {
    if (!activar) {
      await np.setProperty('video-crop', '');
      return (await np.getProperty('video-crop')).trim().isEmpty;
    }
    final w = player.state.width ?? 0;
    final h = player.state.height ?? 0;
    if (w <= 1 || h <= 1) return false;

    final mitad = w ~/ 2;
    final x =
        ((w - mitad) * vrDesplazamiento.value).round().clamp(0, w - mitad);
    await np.setProperty('video-crop', '${mitad}x$h+$x+0');
    return (await np.getProperty('video-crop')).trim().isNotEmpty;
  }

  /// El recorte de VR quedo pendiente de volver a ponerse en el video nuevo.
  ///
  /// Lo pone _olvidarRecorteVr y lo consume el aviso de medidas, que es donde
  /// se sabe si el video nuevo tambien es VR. Ver el listener de videoParams.
  bool _vrPorReaplicar = false;

  /// Quita el recorte de VR antes de abrir otro video.
  ///
  /// Deja anotado si estaba puesto, para que el video nuevo lo recupere si
  /// tambien es VR: pasar de un episodio VR al siguiente no tiene por que
  /// obligar a volver a encender el interruptor.
  Future<void> _olvidarRecorteVr() async {
    _vrPorReaplicar = vrUnaPantalla.value;
    if (!vrUnaPantalla.value) return;
    vrUnaPantalla.value = false;
    if (player.platform is! NativePlayer) return;
    final np = player.platform as NativePlayer;
    try {
      await _aplicarRecorteVr(np, false);
      // Y el filtro, que es el camino de respaldo cuando esta version de mpv no
      // tiene video-crop. Solo si hay algo puesto: nadie mas escribe vf, pero
      // borrarlo a ciegas seria pisar lo que pusiera otro.
      if ((await np.getProperty('vf')).trim().isNotEmpty) {
        await np.setProperty('vf', '');
      }
    } catch (e) {
      logger.warning(
          'No se pudo quitar el recorte de VR del vídeo anterior', e);
    }
  }

  Future<void> alternarVrUnaPantalla() async {
    if (player.platform is! NativePlayer) return;
    final np = player.platform as NativePlayer;
    final nuevo = !vrUnaPantalla.value;
    try {
      // Primero la vía de mpv pensada para esto. Si esta versión no la tiene,
      // se cae al filtro, que es lo que había antes.
      if (await _aplicarRecorteVr(np, nuevo)) {
        vrUnaPantalla.value = nuevo;
        return;
      }
      await np.setProperty('vf', nuevo ? _filtroVr : '');

      // Se vuelve a leer para confirmar que quedó puesto.
      //
      // Que setProperty no tire excepción NO alcanza: mpv acepta la orden y
      // recién después decide que el filtro no le sirve, y ese rechazo llega
      // por su canal de errores, no por acá. Sin comprobarlo, el interruptor
      // quedaba encendido mientras la imagen seguía igual — que es justo lo
      // peor: parece que la función no hace nada en vez de avisar.
      final puesto = (await np.getProperty('vf')).trim();
      final quedoBien = nuevo ? puesto.isNotEmpty : puesto.isEmpty;
      if (!quedoBien) {
        logger.warning('mpv no aceptó el filtro de VR (vf="$puesto")');
        vrUnaPantalla.value = false;
        return;
      }
      vrUnaPantalla.value = nuevo;
    } catch (e) {
      logger.warning('No se pudo cambiar el modo VR', e);
      vrUnaPantalla.value = false;
    }
  }

  /// ¿El botón de servidores aporta algo APARTE del de calidad?
  ///
  /// Los dos abren el mismo panel cuando la extensión entrega sus calidades por
  /// X-Servers, que es lo que hacen los sitios con un MP4 por resolución. En el
  /// teléfono eso dejaba dos botones pegados haciendo exactamente lo mismo: uno
  /// decía "1080p" y el otro era el de servidores, y los dos abrían la misma
  /// lista de calidades.
  ///
  /// Se esconde SOLO cuando esa lista son calidades disfrazadas de servidores,
  /// que es cuando los dos botones abren lo mismo.
  ///
  /// La primera versión de esto exigía además que hubiera `qualityMap`, y eso
  /// estuvo mal: `qualityMap` solo se llena con un playlist HLS, así que en la
  /// mayoría de las extensiones está vacío aunque los servidores sean
  /// servidores de verdad. Resultado: desaparecieron las fuentes alternativas
  /// en casi todas y no se podía elegir servidor en ningún lado.
  bool get servidoresSonAparte =>
      availableServers.isNotEmpty && !_servidoresSonCalidades;

  toggleSideBar(SidebarTab tab) {
    if (showSidebar.value && initSidebarTab.value == tab) {
      showSidebar.value = false;
      return;
    }
    initSidebarTab.value = tab;
    showSidebar.value = true;
  }

  // 添加本地字幕文件
  addSubtitleFile() async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt'],
      allowMultiple: false,
    );
    if (file == null) {
      return;
    }
    final data = await File(file.files.first.path!).readAsString();
    subtitles.add(
      SubtitleTrack.data(
        data,
        title: file.files.first.name,
      ),
    );
  }

  // 连接 DLNA 设备
  connectDLNADevice(AparatoDeCasteo aparato) async {
    // Se puede llegar aca despues de un await (cambio de episodio casteando)
    // con el reproductor ya cerrado.
    if (_disposed) return;
    if (watchData == null) {
      sendMessage(Message(Text('等待视频加载'.i18n)));
      return;
    }
    // Dos conexiones a la vez no: tocar el aparato dos veces, o elegir otro
    // mientras el primero todavia esta enganchando, dejaba dos enganches
    // pisandose y el estado a medio armar.
    if (castConectando.value) return;
    castConectando.value = true;

    // Si ya se estaba transmitiendo a OTRO aparato, hay que soltar el anterior
    // ANTES de enganchar el nuevo. Sin esto el televisor viejo se quedaba
    // reproduciendo por su cuenta —nadie le decia que parara— y su relay
    // quedaba registrado para siempre, porque _dlnaRelayUrl se pisaba con el
    // nuevo sin soltar el de antes.
    final anterior = dlnaDevice.value;
    if (anterior != null && anterior.id != aparato.id) {
      // Por IDENTIFICADOR y no por instancia: cada busqueda crea objetos nuevos
      // del mismo televisor, asi que comparar los objetos daria siempre "es
      // otro" y se soltaria el que en realidad se acaba de elegir.
      unawaited(Future(() async {
        try {
          await anterior.soltar();
        } catch (e) {
          logger.warning('El aparato anterior no respondio al soltarlo', e);
        }
      }));
    }
    if (_dlnaRelayUrl != null) {
      CastRelayServer.unregister(_dlnaRelayUrl!);
      _dlnaRelayUrl = null;
    }

    var url = watchData!.url;
    // El tipo se saca de la direccion REAL, no de la del relay: la del relay
    // termina en /relay/<token> y no dice nada del formato.
    final urlOriginal = url;
    final headers = watchData!.headers;
    CastRelayServer.ultimoError = null;
    _fallaDeCastAvisada = null;
    // Cuenta limpia para el vigilante de estado: los fallos y el "ya lo vi
    // reproducir" de una transmision anterior no valen para esta.
    _fallosDeCastSeguidos = 0;
    _vioReproduciendoEnCast = false;
    _lecturasParadoSeguidas = 0;
    _consultandoCast = false;
    // El renderer DLNA pide la URL con SU propio cliente HTTP — no hay
    // forma de decirle que mande el Referer/User-Agent que la fuente
    // exige. Sin esto, cualquier fuente con headers obligatorios se veía
    // sana localmente pero fallaba en silencio en el TV. Con headers, se
    // pasa por el relay local en vez de la URL directa (ver
    // cast_relay_server.dart).
    // ¿Este aparato puede con lo que le vamos a mandar?
    //
    // Se le pregunta ANTES en vez de mandarle y ver qué pasa, porque un
    // televisor que no puede con el formato **acepta igual la orden**: contesta
    // que sí, muestra el título que le mandamos en la ficha y no dibuja nunca
    // nada. Desde afuera eso se ve idéntico a que esté funcionando, y era
    // exactamente lo que pasaba: HLS —que es lo que sirven casi todas las
    // extensiones— no lo reproduce ningún televisor DLNA. Medido: Kodi publica
    // 94 formatos con HLS entre ellos y reproduce; el televisor publica 29 sin
    // ninguno de HLS y se queda en negro.
    //
    // Cuando no puede, se le manda el mismo vídeo reempaquetado como MPEG-TS,
    // que sí está en su lista y no cuesta recodificar nada (cast_hls_ts.dart).
    PlanTs? planTs;
    _planTs = null;
    _desfaseTs = Duration.zero;
    var mime = mimeDeUrl(urlOriginal);
    // La linea de cabecera de toda la transmision: contra que aparato, por que
    // protocolo y con que formato se arranca. Todo lo que venga despues en el
    // registro cuelga de aca.
    //
    // De las cabeceras de la fuente van solo los NOMBRES: en Referer y Cookie
    // viaja la direccion del contenido, y el archivo se comparte.
    CastLog.paso('Arranca: ${aparato.ficha} — origen '
        '${CastLog.donde(urlOriginal)} mime=$mime — cabeceras de la fuente: '
        '${headers == null || headers.isEmpty ? 'ninguna' : headers.keys.join(', ')}');
    if (aparato is AparatoDlna && mime.contains('mpegurl')) {
      if (!await FormatosDelAparato.aceptaHls(aparato.device)) {
        final aceptaTs = await FormatosDelAparato.aceptaTs(aparato.device);
        CastLog.paso('${aparato.nombre} no acepta HLS; '
            'MPEG-TS: ${aceptaTs ? "sí" : "no"}');
        if (aceptaTs) {
          // El MISMO User-Agent que usa el relay, no uno leído a mano: si el
          // ajuste está vacío hay que caer en el de navegador, porque con el
          // que pone dart:io las fuentes detrás de Cloudflare contestan 403.
          planTs = await CastHlsATs.analizar(
            urlOriginal,
            headers ?? const {},
            CastRelayServer.uaPorDefecto,
          );
        }
        if (planTs == null) {
          // Ni HLS ni reempaquetado: mandarlo igual sería dejar la pantalla en
          // negro sin explicación, que es de donde venimos.
          CastLog.fallo('${aparato.nombre} no soporta el formato del vídeo y '
              'no se pudo reempaquetar: no se le manda nada');
          castConectando.value = false;
          castAviso.value = null;
          sendMessage(Message(Text('video.cast-formato-aparato'.i18n)));
          return;
        }
        mime = 'video/mpeg';
        CastLog.paso('Se reempaqueta a MPEG-TS: ${planTs.pedacitos.length} '
            'pedacitos, ${planTs.duracion.inMinutes} min');
        _planTs = planTs;
        // El largo lo sabemos NOSOTROS por la lista, aunque el televisor no
        // pueda saberlo del flujo. Sin esto la barra queda vacía y no habría
        // dónde tocar para adelantar.
        duration.value = planTs.duracion;
      }
    }

    // Con reempaquetado el relay es obligatorio aunque no haya cabeceras: es el
    // relay el que va pegando los pedacitos.
    if (planTs != null || (headers != null && headers.isNotEmpty)) {
      try {
        url = await CastRelayServer.registerAndGetUrl(
          targetUrl: url,
          headers: headers,
          planTs: planTs,
        );
        _dlnaRelayUrl = url;
      } catch (e) {
        CastLog.fallo('El relay no se pudo levantar, se castea la dirección '
            'directa: $e');
        if (planTs != null) {
          // Sin relay no hay reempaquetado posible, y la lista cruda ya sabemos
          // que este aparato no la reproduce.
          castConectando.value = false;
          castAviso.value = null;
          sendMessage(Message(Text('video.cast-sin-alcance'.i18n)));
          return;
        }
      }
    }
    dlnaDevice.value = aparato;
    _urlEnviadaAlCast = url;
    _vueltasDesdeElControl = 0;
    _desajustesSeguidos = 0;
    _posicionUltimoControl = Duration.zero;
    try {
      // preparar() antes de nada: en DLNA no hace falta, pero el Chromecast
      // tiene que abrir su conexion y lanzar su reproductor primero. Si eso
      // falla no se sigue, que seria mandarle el video a nadie.
      if (!await aparato.preparar()) {
        throw StateError('El aparato no acepto la conexion');
      }
      await aparato.cargar(
        url: url,
        titulo: '$title — ${playList[index.value].name}',
        mime: mime,
        // Con reempaquetado NO se puede saltar por bytes, y hay que decírselo:
        // ese flujo se arma sobre la marcha y no tiene largo. Prometerle lo
        // contrario hace que el aparato cierre la conexión y la reabra creyendo
        // que puede seguir desde otro punto — y como no puede, le llega desde el
        // principio. Ver cast_metadata.dart.
        puedeSaltar: planTs == null,
      );
      CastLog.paso('El aparato aceptó la orden; se le anunció '
          '${CastLog.anuncio(url)}');
    } catch (e) {
      // Un aparato que no contesta dejaba la excepcion suelta y la pantalla en
      // modo casteo sin que nada se estuviera reproduciendo. Se deshace todo y
      // se avisa, que es lo unico honesto que se puede hacer.
      CastLog.fallo('El aparato no aceptó el vídeo', e);
      dlnaDevice.value = null;
      if (_dlnaRelayUrl != null) {
        CastRelayServer.unregister(_dlnaRelayUrl!);
        _dlnaRelayUrl = null;
      }
      sendMessage(Message(Text('video.cast-failed'.i18n)));
      return;
    } finally {
      // En finally y no al final del camino feliz: si algo de lo que viene
      // despues fallara, esta bandera quedaba en true PARA SIEMPRE y el boton
      // de transmitir y el de reproducir se quedaban apagados sin forma de
      // recuperarlos salvo salir del episodio.
      castConectando.value = false;
    }
    // Recien aca se para el reproductor de aca: si se paraba antes y el
    // televisor terminaba fallando, quedaban los dos sin reproducir nada.
    //
    // Con su propio catch: que no se pueda parar el de aca no invalida que el
    // televisor ya este reproduciendo, y sin esto la excepcion se llevaba
    // puesta la creacion del timer de estado — la transmision quedaba andando
    // pero la app sin enterarse de nada de lo que pasaba en el televisor.
    try {
      await player.stop();
    } catch (e) {
      logger.warning('No se pudo parar el reproductor local al castear', e);
    }
    // Cancelar cualquier timer previo antes de crear uno nuevo — si el
    // usuario elige otro dispositivo DLNA sin desconectar el anterior
    // primero, sin esto quedaban DOS timers corriendo _getDLNAStatus() cada
    // segundo para siempre (uno por cada dispositivo elegido en la sesión).
    _dlnaTimer?.cancel();
    // Si el reproductor se cerro mientras se enganchaba, no se arranca ningun
    // timer: quedaria latiendo cada segundo sobre un controlador destruido.
    if (_disposed || dlnaDevice.value == null) return;
    // Se arranca desde el volumen que YA tiene el aparato, para que el primer
    // deslizamiento no le pegue un salto.
    // Cuenta limpia por aparato: que el anterior no dejara cambiarle el volumen
    // no dice nada de este.
    castVolumenSoportado = true;
    // La notificación pasa a decir que está sonando en el televisor, y sus
    // botones a hablarle a él.
    unawaited(_mostrarNotificacion());
    unawaited(_leerVolumenDelCast(aparato));
    castVelocidadPedida.value = 1;
    // Sigue "cargando" hasta que el aparato diga que reproduce de verdad.
    castEsperandoPlay.value = true;
    // A los ocho segundos se comprueba si el aparato LLEGO a pedirnos el video.
    //
    // Un televisor en negro se ve igual en dos casos muy distintos: cuando no
    // nos alcanza por la red, y cuando nos alcanza pero no puede con el
    // formato. El relay sabe cual de los dos es —si le pidieron algo o no—, y
    // sin decirlo se termina probando a ciegas.
    _pedidoCastTimer?.cancel();
    _bytesDelCastVistos = 0;
    _revisionesDelCast = 0;
    _pedidoCastTimer = Timer(_esperaDeVeredicto, _veredictoDelCast);
    _esperaPlayTimer?.cancel();
    // Techo por si nunca lo informa (firmware que no actualiza su estado): el
    // aviso se va y quedan los controles, mejor que una rueda eterna.
    _esperaPlayTimer = Timer(const Duration(seconds: 30), () {
      castEsperandoPlay.value = false;
      castCambiandoEpisodio.value = false;
    });
    _dlnaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _getDLNAStatus();
    });
  }

  /// Cuánto se espera antes de decir nada sobre una transmisión que no arranca.
  static const _esperaDeVeredicto = Duration(seconds: 8);

  /// Cuántas veces más se vuelve a mirar mientras siga entrando vídeo.
  static const _maxRevisionesDelCast = 3;

  int _bytesDelCastVistos = 0;
  int _revisionesDelCast = 0;

  /// Por qué el aparato todavía no muestra nada.
  ///
  /// Son TRES casos y antes se distinguían dos, así que el que faltaba salía en
  /// pantalla siendo mentira. Medido en vivo: el aviso de "recibió el vídeo pero
  /// no puede reproducirlo" se mostró **139 milisegundos antes** de que el
  /// televisor informara que estaba REPRODUCIENDO. Estaba cargando, nada más.
  ///
  ///  - No pidió nada: no llega hasta nosotros. Es red.
  ///  - Pidió pero no bajó un solo byte: preguntó por el formato (el HEAD con el
  ///    que un DLNA consulta si le sirve) y lo rechazó. Eso sí es formato.
  ///  - Está bajando: no hay nada roto, está cargando. Se espera.
  ///
  /// El error de fondo era dar por "bajó datos" lo que solo decía "pidió": un
  /// HEAD, que es lo primero que manda un televisor, ya marcaba la sesión como
  /// pedida sin que se hubiera entregado nada. Ahora se cuentan los bytes.
  void _veredictoDelCast() {
    if (_disposed || dlnaDevice.value == null) return;
    if (isPlaying.value) return;
    if (_dlnaRelayUrl == null) return;

    final pidio = CastRelayServer.huboPedido(_dlnaRelayUrl);
    final bytes = CastRelayServer.bytesServidos(_dlnaRelayUrl);
    final segundos = (_revisionesDelCast + 1) * _esperaDeVeredicto.inSeconds;

    if (!pidio) {
      CastLog.paso(
          'A los $segundos s sin imagen: el aparato NO pidió nada → no '
          'llega hasta nosotros, es red');
      castAviso.value = 'video.cast-sin-alcance'.i18n;
      return;
    }

    // Sigue entrando vídeo: se le da otra vuelta antes de decir nada.
    if (bytes > _bytesDelCastVistos &&
        _revisionesDelCast < _maxRevisionesDelCast) {
      _revisionesDelCast++;
      _bytesDelCastVistos = bytes;
      CastLog.paso('A los $segundos s sin imagen todavía, pero el aparato ya '
          'bajó ${(bytes / 1024).round()} KiB y sigue bajando → está cargando, '
          'se espera (revisión $_revisionesDelCast de $_maxRevisionesDelCast)');
      _pedidoCastTimer?.cancel();
      _pedidoCastTimer = Timer(_esperaDeVeredicto, _veredictoDelCast);
      return;
    }

    if (bytes == 0) {
      // Preguntó y se fue sin bajar nada: el formato no le sirve. Bajar la
      // calidad no ayudaría, porque no llegó a mirar el vídeo sino la ficha.
      CastLog.paso('A los $segundos s sin imagen: el aparato pidió desde '
          '${CastRelayServer.quienPidio(_dlnaRelayUrl)} pero no bajó NI UN BYTE '
          '→ preguntó por el formato y lo rechazó');
      castAviso.value = 'video.cast-formato'.i18n;
      return;
    }

    // Bajó datos y dejó de bajar sin dar imagen: eso ya sí es no poder con lo
    // que le mandamos. Si es 4K o 2K lo más probable es que sea la RESOLUCIÓN y
    // no el formato — los televisores publican "video/mp4" a secas, sin decir
    // hasta qué resolución llegan.
    CastLog.fallo('A los $segundos s sin imagen: el aparato bajó '
        '${(bytes / 1024).round()} KiB y se detuvo → no puede con lo que le '
        'mandamos');
    if (_bajarCalidadParaElTelevisor()) return;
    castAviso.value = 'video.cast-formato'.i18n;
  }

  /// Manda el aparato a un punto exacto del video.
  ///
  /// No se usa seek() del controlador: ese calcula un salto RELATIVO contra
  /// position.value, y justo despues de re-enganchar ese valor todavia es el de
  /// antes del cambio — el salto saldria a cualquier lado.
  /// Manda el aparato a un punto exacto del video.
  ///
  /// Se espera un poco antes: recien arrancado, varios aparatos ignoran el
  /// salto porque todavia no terminaron de cargar el video.
  Future<void> _irAEnElAparato(AparatoDeCasteo aparato, Duration donde) async {
    if (donde <= Duration.zero) return;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (_disposed || dlnaDevice.value?.id != aparato.id) return;
    try {
      await aparato.irA(donde);
    } catch (e) {
      logger.warning('No se pudo retomar el punto en el aparato', e);
    }
  }

  /// Vuelve a mandarle el video al MISMO dispositivo.
  ///
  /// El televisor puede fallar por cosas pasajeras —un corte de red, que la
  /// direccion firmada de la fuente caduco entre que se pidio y se envio, o que
  /// el aparato todavia estaba ocupado con lo anterior— y hasta ahora la unica
  /// salida era desconectar y volver a elegirlo de la lista.
  ///
  /// Se vuelve a PEDIR la direccion a la fuente, no se reenvia la de antes.
  ///
  /// Las fuentes firman la direccion para una IP y con un vencimiento adentro
  /// (Eporner, por ejemplo, la arma como `<vence>_<ip>_<n>/archivo.mp4`).
  /// Cuando vence, la fuente contesta 403 y el aparato solo dice "no se pudo
  /// reproducir". Reenviar esa misma direccion falla exactamente igual —
  /// confirmado en el registro de Kodi del usuario, con dos intentos separados
  /// por tres minutos dando los dos 403 sobre la misma direccion de origen.
  Future<void> reintentarCast() async {
    final device = dlnaDevice.value;
    if (device == null) return;
    // Ya hay un reintento o un enganche en curso: tocar de nuevo no encola otro.
    if (castConectando.value) return;
    // Se enciende YA, antes de tocar la red.
    //
    // Volver a resolver el video puede tardar varios segundos, y en ese rato el
    // boton no daba ninguna señal: parecia que no habia hecho nada y se
    // terminaba tocando de nuevo. Ahora el panel muestra la rueda desde el
    // primer momento y el boton queda bloqueado.
    castConectando.value = true;
    try {
      // Se limpia el relay anterior: registrar uno nuevo sin soltar el viejo
      // deja entradas colgadas por cada reintento.
      if (_dlnaRelayUrl != null) {
        CastRelayServer.unregister(_dlnaRelayUrl!);
        _dlnaRelayUrl = null;
      }
      try {
        await device.soltar();
      } catch (_) {
        // Puede estar ya parado o no responder: no frena el reintento.
      }
      // Direccion nueva y fresca. Si esto falla se avisa y no se sigue:
      // castear con la vieja seria repetir el mismo error a proposito.
      try {
        await getWatchData();
      } catch (e) {
        logger.warning('No se pudo volver a resolver el video para el cast', e);
        sendMessage(Message(Text(friendlyError(e))));
        return;
      }
      if (_disposed || watchData == null) return;
    } finally {
      // Se apaga justo antes de pasarle la posta a connectDLNADevice, que la
      // vuelve a encender de inmediato (su cuerpo corre sin ningun await de por
      // medio hasta ahi, asi que no se ve ningun parpadeo). Sin esto, su propia
      // proteccion contra dobles enganches cortaria el reintento en seco.
      castConectando.value = false;
    }
    await connectDLNADevice(device);
  }

  // 断开 DLNA 设备
  //
  // [pararAparato] en false cuando la transmision ya NO es nuestra: si otro
  // dispositivo tomo el televisor, mandarle stop le cortaria el video a el.
  disconnectDLNADevice({bool pararAparato = true}) async {
    if (dlnaDevice.value == null) {
      return;
    }
    final device = dlnaDevice.value!;
    // Donde iba el televisor, para no volver al principio.
    final donde = position.value;
    // Se suelta el aparato ANTES de nada: asi la pantalla deja de mostrar el
    // modo casteo en el acto, sin esperar a que el televisor conteste. Un
    // televisor lento tardaba segundos en responder al stop y en ese rato la
    // app se veia trabada.
    dlnaDevice.value = null;
    _dlnaTimer?.cancel();
    // Se le manda parar sin esperarlo, pero atajando el error: sin el catch, un
    // aparato ya apagado o fuera de la red tiraba una excepcion suelta que
    // nadie manejaba.
    if (pararAparato) {
      unawaited(Future(() async {
        try {
          await device.soltar();
        } catch (e) {
          logger.warning('El aparato no respondio al cortar la transmision', e);
        }
      }));
    }
    _urlEnviadaAlCast = null;
    _planTs = null;
    _desfaseTs = Duration.zero;
    if (_dlnaRelayUrl != null) {
      CastRelayServer.unregister(_dlnaRelayUrl!);
      _dlnaRelayUrl = null;
    }
    // Se limpia el ultimo fallo del relay: si no, al volver a castear mas tarde
    // saldria de nuevo el aviso de un error que ya paso.
    CastRelayServer.ultimoError = null;
    _fallaDeCastAvisada = null;
    // Todos los estados del panel se apagan juntos: si alguno quedaba puesto,
    // al volver a castear mas tarde el panel arrancaba mostrando una espera que
    // ya no existia.
    castConectando.value = false;
    castEsperandoPlay.value = false;
    castCambiandoEpisodio.value = false;
    castBuscando.value = false;
    castVelocidad.value = null;
    castVelocidadPedida.value = 1;
    castAviso.value = null;
    _desajustesSeguidos = 0;
    _objetivoDeSalto = null;
    _castBuscandoTimer?.cancel();
    _esperaPlayTimer?.cancel();
    _pedidoCastTimer?.cancel();
    _volumenCastTimer?.cancel();

    // Y el reproductor local vuelve a andar.
    //
    // Al empezar a transmitir se llama a player.stop(), porque el video pasa a
    // verse en el televisor y dejarlo decodificando aca seria gastar bateria
    // para nada. Pero al desconectar nadie lo volvia a abrir: quedaba la
    // pantalla negra con los controles muertos, y la unica salida era salir del
    // episodio y entrar de nuevo.
    //
    // Se retoma donde estaba el televisor, que es lo que uno espera al cortar
    // la transmision para seguir mirando en el dispositivo.
    if (_disposed) return;
    final actual = watchData;
    if (actual == null) return;
    // Todavia no hay imagen: mpv tiene que volver a abrir el video desde cero.
    // Sin esto quedaba en true de antes de castear y la rueda de carga no
    // aparecia, asi que el rato hasta el primer cuadro se veia como una
    // pantalla negra trabada.
    hasRenderedFrame.value = false;
    // Fuente nueva: se olvida el cuadro anterior y la red se rearma
    // sola con el primer cuadro de esta. Ver hasRenderedFrame.
    _hayCuadro = false;
    _posicionAlPrimerCuadro = null;
    _redDeLaRueda?.cancel();
    _redDeLaRueda = null;
    try {
      await player.open(Media(actual.url, httpHeaders: actual.headers));
      // El salto va DESPUES de que open() termino, que es cuando mpv ya conoce
      // la duracion; pedirlo antes se pierde y el episodio arrancaba de cero.
      // Mismo cuidado que en "continuar viendo": pedirle el salto a mpv
      // apenas vuelve open() se pierde si todavia no conoce la duracion.
      if (donde > Duration.zero) await _saltarCuandoSePueda(donde);
    } catch (e) {
      logger.warning(
          'No se pudo retomar la reproduccion local tras el cast', e);
      // Que no quede la rueda girando para siempre si la reapertura fallo.
      hasRenderedFrame.value = true;
      sendMessage(Message(Text(friendlyError(e))));
    }
  }

  // Consultas al aparato que ya estan en vuelo, fallos seguidos, y si alguna
  // vez llego a reproducir. Ver _getDLNAStatus.
  bool _consultandoCast = false;
  int _fallosDeCastSeguidos = 0;
  bool _vioReproduciendoEnCast = false;
  int _lecturasParadoSeguidas = 0;

  /// Cuantas consultas seguidas pueden fallar antes de dar la transmision por
  /// perdida. Se consulta cada segundo, asi que son ~5 segundos de silencio:
  /// suficiente para aguantar un bache de red y poco para que se note.
  static const _fallosParaDarPorPerdido = 5;

  /// Comprueba que el aparato siga reproduciendo lo que le mandamos nosotros.
  ///
  /// Si otro dispositivo le mando otra cosa, se suelta la transmision SIN
  /// pararle el video: ya no es nuestro, y pararlo seria cortarle la
  /// reproduccion a quien la tomo.
  void _comprobarQueSigaSiendoNuestro(String? actual) {
    final nuestra = _urlEnviadaAlCast;
    if (nuestra == null) return;
    // Todavia no empezo lo que le acabamos de mandar: NO se comprueba.
    //
    // Al cambiar de episodio se le manda una direccion nueva, pero el aparato
    // sigue informando la ANTERIOR hasta que termina de cambiar. Comprobando en
    // ese hueco, las direcciones no coinciden y se concluia que otro
    // dispositivo se habia quedado con el televisor: cambiar de episodio
    // casteando cortaba la transmision sola.
    if (castEsperandoPlay.value || castCambiandoEpisodio.value) {
      _desajustesSeguidos = 0;
      return;
    }
    // Vacio o desconocido: no se concluye nada. Solo se actua cuando el aparato
    // dice con todas las letras que esta con OTRA direccion. Los aparatos que
    // no informan esto (el Chromecast, por ejemplo) caen aca y no pasa nada.
    if (actual == null || actual.isEmpty) return;
    if (actual == nuestra) {
      _desajustesSeguidos = 0;
      // Confirmado nuestro: se anota por donde iba, para poder volver a este
      // punto si en el proximo control resulta que nos lo tomaron.
      _posicionUltimoControl = position.value;
      return;
    }

    // Tiene que no coincidir DOS controles seguidos.
    //
    // Un aparato puede informar la direccion vieja un momento despues de haber
    // aceptado la nueva; con una sola lectura, ese instante bastaba para cortar
    // la transmision. Alguien que de verdad tomo el televisor sigue con lo suyo
    // en el control siguiente.
    if (++_desajustesSeguidos < 2) return;
    _desajustesSeguidos = 0;

    logger.info('Otro dispositivo tomo el televisor: $actual');
    // La posicion que informa el aparato ya es la del OTRO video. Se vuelve a
    // la ultima que se confirmo nuestra ANTES de desconectar, que es la que va
    // a usar el historial y la que retoma el reproductor de aca.
    if (_posicionUltimoControl > Duration.zero) {
      position.value = _posicionUltimoControl;
    }
    sendMessage(Message(
      Text('video.cast-taken-over'.i18n),
      time: const Duration(seconds: 6),
    ));
    unawaited(disconnectDLNADevice(pararAparato: false));
  }

  // 获取 DLNA 播放状态
  _getDLNAStatus() async {
    final device = dlnaDevice.value;
    if (device == null) {
      return;
    }
    // Una consulta por vez.
    //
    // El timer dispara cada segundo y NO espera a que esta funcion termine. Con
    // el televisor apagado, cada consulta se queda colgada hasta que la red se
    // rinda —decenas de segundos— y mientras tanto arrancaba otra cada segundo:
    // se apilaban conexiones muertas de a montones, justo cuando el aparato ya
    // no estaba para contestar ninguna.
    if (_consultandoCast) return;
    _consultandoCast = true;
    // Este método corre desde un Timer.periodic de 1s mientras dure el cast
    // (ver connectDLNADevice) — sin try/catch, un TV desconectado/
    // inalcanzable o un formato de posición inesperado (firmware distinto)
    // tira la MISMA excepción sin manejar una vez por segundo para siempre,
    // sin que el usuario vea ningún aviso.
    // El aparato solo sabe decir "no se pudo reproducir". El motivo de verdad
    // lo vio el relay cuando la fuente lo rechazo, asi que se lo muestra al
    // usuario en cuanto aparece — una sola vez, que si no el aviso se repetiria
    // cada segundo mientras dure el timer.
    final falla = CastRelayServer.ultimoError;
    if (falla != null && falla != _fallaDeCastAvisada) {
      _fallaDeCastAvisada = falla;
      sendMessage(Message(Text(falla), time: const Duration(seconds: 6)));
    }
    try {
      final info = await device.leerEstado();
      if (info == null) throw StateError('El aparato no informo su estado');
      // Contesto: lo que hubiera pasado antes fue un bache y ya paso.
      _fallosDeCastSeguidos = 0;
      final reproduciendo = info.reproduciendo;
      // Con una orden nuestra en vuelo, lo que informa es lo de ANTES de esa
      // orden: pisarlo hacia parpadear el boton entre pausa y reproducir.
      if (_aceptarReproduciendo(reproduciendo)) {
        isPlaying.value = reproduciendo;
      }
      // La notificación también, que transmitiendo es el único mando que queda
      // con la app en segundo plano: el reproductor de acá está parado y no
      // emite nada, así que sin esto se quedaba con lo último que vio.
      _refrescarNotificacion();
      if (reproduciendo) {
        _vioReproduciendoEnCast = true;
        // Empezo de verdad: recien aca se saca el aviso de carga.
        if (castEsperandoPlay.value) {
          _esperaPlayTimer?.cancel();
          castEsperandoPlay.value = false;
          // El aviso de cambio de episodio dura hasta ACA, no hasta que el
          // aparato acepta: si no, decia "cambiando de episodio" un instante y
          // despues pasaba a "conectando" mientras la pantalla grande seguia
          // en negro, contando dos cosas para una sola espera.
          castCambiandoEpisodio.value = false;
        }
      }

      // Velocidad puesta EN el aparato (x2, x4...). Solo cuando no es la
      // normal: con la normal no hay nada que decir.
      castVelocidad.value = info.velocidad;

      // Lo pararon DESDE el televisor (con su control remoto, o porque
      // termino). Se distingue de una pausa: pausar informa PAUSED_PLAYBACK,
      // parar informa STOPPED o que ya no hay nada cargado.
      //
      // Antes esto se leia como "no esta reproduciendo" a secas, asi que la
      // pantalla decia "En pausa, toca para seguir" y tocar no hacia nada:
      // se le pedia reanudar a un aparato que ya no tenia el video cargado.
      final parado = info.parado;
      // Tiene que estar parado DOS vueltas seguidas.
      //
      // Manejando desde el control del televisor, adelantar hace que varios
      // reproductores informen STOPPED un instante mientras vuelven a llenar el
      // buffer. Con una sola lectura, usar el control remoto para adelantar
      // cortaba la transmision. Una parada de verdad sigue parada al segundo.
      _lecturasParadoSeguidas = parado ? _lecturasParadoSeguidas + 1 : 0;
      if (_lecturasParadoSeguidas >= 2 && _vioReproduciendoEnCast) {
        // Se acabo el episodio, o lo pararon a mano? El aparato informa lo
        // mismo en los dos casos, asi que se mira DONDE quedo.
        //
        // position/duration conservan la ultima lectura buena, porque la rama
        // de parado corta antes de refrescarlas.
        final dur = duration.value;
        final pos = position.value;
        final falta = dur - pos;
        final termino = dur > Duration.zero &&
            (falta <= const Duration(seconds: 15) ||
                falta.inMilliseconds <= dur.inMilliseconds * 0.08);

        if (termino && playMode.value == PlaylistMode.loop) {
          // En bucle: de nuevo desde el principio, en el mismo aparato.
          logger.info('Fin del episodio en el aparato: se repite');
          _lecturasParadoSeguidas = 0;
          try {
            // seek() y no seekByCurrent(): el segundo espera el XML crudo que
            // devuelve position(), no una hora suelta.
            await device.irA(Duration.zero);
            await device.reproducir();
          } catch (e) {
            logger.warning('No se pudo repetir el episodio en el aparato', e);
          }
          return;
        }

        if (termino &&
            // Mismo ajuste que mirando aca: encadenar es algo que se pide.
            autoPlayNextActivado &&
            playMode.value != PlaylistMode.single &&
            index.value < playList.length - 1) {
          // Encadena al siguiente SIN soltar el aparato.
          //
          // El encadenado normal lo dispara player.stream.completed del
          // reproductor de aca, que mientras se transmite esta parado a
          // proposito y no emite nunca — asi que casteando no habia encadenado.
          // Al mover el indice, el vigilante de episodio resuelve el siguiente
          // y lo vuelve a mandar al MISMO aparato, sin cortar la transmision.
          logger.info('Fin del episodio en el aparato: va el siguiente');
          _lecturasParadoSeguidas = 0;
          _vioReproduciendoEnCast = false;
          index.value++;
          return;
        }

        if (termino) {
          // Era el ultimo (o la lista esta en modo de uno solo).
          sendMessage(Message(Text('video.play-complete'.i18n)));
        } else {
          sendMessage(Message(Text('video.cast-stopped-device'.i18n)));
        }
        logger.info('La transmision se corto desde el aparato');
        await disconnectDLNADevice();
        return;
      }

      // Solo si el aparato las informo: null no es cero. Pisar la posicion con
      // cero en una vuelta que no trajo el dato hacia saltar la barra al
      // principio y volver, que ademas disparaba el aviso de "buscando".
      // Reempaquetado: el televisor cuenta desde cero en cada salto, porque
      // para el cada uno es un video nuevo. Lo que va en la barra es eso mas el
      // punto del episodio donde arranco el flujo que esta recibiendo.
      //
      // Y la duracion NO se toca: el largo lo sacamos de la lista, y el
      // televisor solo puede informar lo que lleva bajado de un flujo que
      // todavia se esta armando.
      final plan = _planTs;
      if (plan != null) {
        // Mismo motivo que en el reproductor de aca: con un salto en camino la
        // barra muestra adonde va y no se pisa.
        final donde = info.posicion;
        if (donde != null && _aceptarPosicion(_desfaseTs + donde)) {
          position.value = _desfaseTs + donde;
        }
        duration.value = plan.duracion;
      } else {
        final donde = info.posicion;
        if (donde != null && _aceptarPosicion(donde)) {
          position.value = donde;
        }
        // Solo si de verdad informo un largo. Un cero es "no lo se", y dejarlo
        // pasar borraba el que la app ya conocia de haber abierto el video
        // antes de castear — con la barra quedando sin recorrido.
        final largo = info.duracion;
        if (largo != null && largo > Duration.zero) duration.value = largo;
      }
      // Ya llego a donde se le pidio? Entonces se saca la rueda de "buscando".
      _revisarSaltoEnCast();

      // Si el aparato dijo por que no pudo, se muestra.
      //
      // El receptor avisa el motivo —formato que no entiende, direccion que no
      // pudo bajar— y eso se estaba descartando: en la pantalla del televisor
      // quedaba el titulo sobre negro y de este lado no habia forma de saber
      // cual de las dos cosas era.
      if (device is AparatoChromecast) {
        final fallo = device.fallo;
        if (fallo != null && fallo != _fallaDeCastAvisada) {
          _fallaDeCastAvisada = fallo;
          sendMessage(Message(
            Text('${'video.cast-device-error'.i18n} ($fallo)'),
            time: const Duration(seconds: 8),
          ));
        }
      }

      // Sigue siendo NUESTRO video?
      //
      // DLNA no tiene ningun bloqueo: si otro telefono le manda otro video al
      // mismo televisor, el segundo pisa al primero sin avisar a nadie. Del
      // lado del primero no se notaba nada — seguia diciendo "transmitiendo",
      // la barra pasaba a seguir el OTRO video, y lo peor: al guardar el
      // historial se anotaba el progreso del video ajeno sobre el episodio
      // propio. Y al desconectar le paraba la reproduccion al otro.
      if (++_vueltasDesdeElControl >= _vueltasEntreControles) {
        _vueltasDesdeElControl = 0;
        _comprobarQueSigaSiendoNuestro(info.urlActual);
      }
    } catch (e) {
      // Se apago, se quedo sin red, o se salio de la app del televisor.
      //
      // Antes esto solo dejaba una linea en el registro, una vez por segundo y
      // para siempre: la app seguia diciendo "Reproduciendo en <aparato>" sobre
      // una pantalla negra, sin ninguna señal de que ya no habia nadie del otro
      // lado. Se aguantan unos segundos por si es un bache, y si no vuelve se
      // da por perdida y se retoma aca donde iba.
      // En segundo plano no se cuenta.
      //
      // Android recorta la red cuando la app no está en pantalla, asi que estos
      // fallos no dicen nada del televisor: puede estar reproduciendo perfecto.
      // Contandolos, dejar la app de lado un rato y volver cortaba una
      // transmision sana. Al volver a primer plano se pregunta de nuevo y ahi
      // si vale lo que conteste.
      if (_enSegundoPlano) {
        logger.info('_getDLNAStatus fallo en segundo plano (no cuenta): $e');
        return;
      }
      _fallosDeCastSeguidos++;
      logger.warning('_getDLNAStatus falló '
          '($_fallosDeCastSeguidos/$_fallosParaDarPorPerdido): $e');
      if (_fallosDeCastSeguidos >= _fallosParaDarPorPerdido) {
        sendMessage(Message(Text('video.cast-lost'.i18n),
            time: const Duration(seconds: 5)));
        await disconnectDLNADevice();
      }
    } finally {
      // Siempre, pase lo que pase: si quedara en true, no se volveria a
      // consultar nunca y el estado del televisor se congelaria.
      _consultandoCast = false;
    }
  }

  // Verifica si el host de una URL es alcanzable vía TCP.
  // Dart maneja EHOSTUNREACH (errno 113) limpiamente;
  // libmpv/libavformat tienen un bug que causa SIGSEGV con ese errno.
  /// Cuánto se espera el saludo TCP antes de dar el host por lento.
  ///
  /// Era 1 segundo. Alcanza por ethernet contra un servidor cercano, que es
  /// donde se probó; no alcanza contra un CDN lejano, por wifi de 2,4 GHz, ni
  /// cuando la resolución del nombre se hace esperar. 2,5 s cubre esos casos sin
  /// volverse una espera notoria.
  static const _esperaDeHost = Duration(milliseconds: 2500);

  Future<bool> _isHostReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasAuthority || uri.host.isEmpty) return true;
      final port = (uri.hasPort && uri.port > 0)
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      final reloj = Stopwatch()..start();
      final socket = await Socket.connect(
        uri.host,
        port,
        timeout: _esperaDeHost,
      );
      socket.destroy();
      logger.info(
          'Host alcanzable: ${uri.host}:$port (${reloj.elapsedMilliseconds} ms)');
      return true;
    } on SocketException catch (e) {
      // Que se agote la espera NO es un host caído, y tratarlos igual costaba
      // servidores perfectamente sanos.
      //
      // Medido en vivo con Streamwish: la app declaró "inalcanzable" a
      // okqtss1gbbnca8e.premilkyway.com, dio el servidor por caído y abrió el
      // navegador — y ese mismo host, probado a mano en ese momento, aceptaba la
      // conexión en **190 milisegundos** y contestaba 200. Un segundo de espera
      // no alcanza para distinguir "muerto" de "tardó", y hay motivos sobrados
      // para tardar: una respuesta IPv6 que no lleva a ningún lado, una
      // resolución de nombre lenta, un saludo TLS con un CDN lejano.
      //
      // El único motivo real de este chequeo es el SIGSEGV de libmpv con
      // EHOSTUNREACH, y ESE caso siempre llega con un error del sistema
      // operativo; un vencimiento de plazo no lo trae. Así que solo se veta
      // cuando el sistema dijo explícitamente que no se puede llegar. Si
      // simplemente tardó, se deja que libmpv lo intente, que para eso tiene sus
      // propios plazos (network-timeout=20).
      if (e.osError == null) {
        logger
            .warning('El host tardó más de ${_esperaDeHost.inMilliseconds} ms '
                'en aceptar la conexión; se intenta igual: $url');
        return true;
      }
      logger.severe('Host inalcanzable: $url — ${e.message}');
      return false;
    } catch (_) {
      return true; // Error desconocido: dejar que libmpv lo intente
    }
  }

  // Intenta abrir el player con la URL dada.
  // Retorna true si el player fue abierto correctamente.
  // Retorna false si la URL es error:// o el host no es alcanzable.
  static const _browserUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  /// Con esto una extensión declara que a ESE servidor hay que leerle el archivo
  /// de una sola vez en vez de pedirle tramos sueltos.
  ///
  /// **No es una cabecera HTTP**: es una declaración que viaja por el mismo
  /// canal que las demás `X-` y se saca antes de pedirle nada a la fuente.
  ///
  /// La app no sabe qué servidores la necesitan ni tiene por qué saberlo: el que
  /// tiene la medición es el resolver del servidor, en su carpeta dentro de la
  /// extensión (hoy, `jkanime/servidores/mp4upload/`). Así arreglar un servidor
  /// no le cambia el camino a ningún otro. Ver BombaDeDatos.
  static const _lecturaContinua = 'X-Lectura-Continua';

  /// La dirección local que está sirviendo la bomba, si hay alguna andando.
  String? _bombaUrl;

  /// Suelta la bomba anterior y sus lecturas abiertas contra la fuente.
  void _soltarLaBomba() {
    final vieja = _bombaUrl;
    if (vieja == null) return;
    _bombaUrl = null;
    BombaDeDatos.soltar(vieja);
  }

  // ── Adelantar en fMP4 (solo AnimeAV1) ──────────────────────────────────────
  //
  // Null salvo que la fuente sea una lista fMP4 de la única extensión que las
  // sirve. Mientras sea null, el reproductor se comporta igual que siempre:
  // todos los enganches de abajo preguntan por él primero.
  RecorteFmp4? _recorte;

  /// Deja listo (o no) el recorte para la fuente que se está por abrir.
  ///
  /// Suelta el de la fuente anterior siempre: dos episodios seguidos tienen
  /// listas distintas y quedarse con la vieja daría saltos a otro vídeo.
  Future<void> _prepararRecorte(String url, Map<String, String> cabeceras) async {
    final anterior = _recorte;
    _recorte = null;
    if (anterior != null) {
      // Fuente nueva: NADA del salto anterior sobrevive. Sin esto quedaban un
      // salto encolado que se ejecutaba sobre el vídeo nuevo, la barra en el
      // minuto del vídeo viejo (se vio en vivo: `posición: 836s` sobre una
      // fuente recién abierta en cero) y el cuadro congelado del otro servidor
      // tapando la imagen.
      logger.info('recorte fMP4: se suelta el de la fuente anterior');
      _saltoPendiente = null;
      _destinoDeSalto = null;
      cuadroCongelado.value = null;
      unawaited(anterior.limpiar());
    }
    try {
      _recorte = await RecorteFmp4.preparar(
        url: url,
        paquete: runtime.extension.package,
        cabeceras: cabeceras,
      );
    } catch (e) {
      // Una mejora no puede impedir que se abra el vídeo.
      logger.warning('recorte fMP4: se sigue sin él', e);
      _recorte = null;
    }
  }

  /// Si las cabeceras del recorte están puestas como propiedad de mpv.
  bool _cabecerasDeRecortePuestas = false;

  /// Le pasa a mpv las cabeceras que necesitan los pedacitos del recorte.
  ///
  /// **Sin esto el recorte da 403 y no reproduce nada** — medido en vivo: la
  /// lista se arma perfecta (142 pedacitos) y después `Failed to open
  /// .../segs/000.html`. La razón es que al abrir un ARCHIVO LOCAL, las
  /// `httpHeaders` del `Media` no viajan a los pedacitos, que sí son remotos:
  /// media_kit las aplica mirando la fuente principal, y esa ahora es un
  /// `.m3u8` en disco. Los de zilla exigen `Sec-Fetch-Site: same-origin`.
  ///
  /// Va como propiedad del reproductor, que sí alcanza a todas las peticiones
  /// HTTP que haga mpv, vengan de donde vengan.
  ///
  /// Van unidas por comas y **sin escapar**, que suena mal y es lo correcto:
  ///
  /// `http-header-fields` es una lista, y varias cabeceras de navegador llevan
  /// comas adentro (`sec-ch-ua` es `"Chromium";v="131", "Not_A Brand";v="24"`),
  /// así que lo prudente parecía usar el escapado de listas de mpv,
  /// `%LARGO%contenido`. **Medido: por `setProperty` ese escapado no se
  /// interpreta** — mpv se guarda el `%27%Sec-Fetch-Site: same-origin` tal cual
  /// y los pedacitos vuelven a dar 403. Es cosa del parser de la línea de
  /// órdenes, no de la API de propiedades.
  ///
  /// Y las comas resultaron inofensivas: con las once cabeceras planas, la
  /// reproducción avanza 8,9 s en 10 y sin un solo error. Banco:
  /// `temp/prueba_cabeceras.dart`.
  ///
  ///     1 cabecera,  sin escapar    ✔ 8,4s ·  0 errores
  ///     1 cabecera,  escapada       ✗ 0,0s · 31 errores
  ///     11 cabeceras, sin escapar   ✔ 8,9s ·  0 errores
  ///     11 cabeceras, escapadas     ✗ 0,0s · 31 errores
  Future<void> _cabecerasParaElRecorte(Map<String, String> cabeceras) async {
    final np = player.platform;
    if (np is! NativePlayer) return;
    try {
      if (_recorte == null) {
        // Se vuelve a una fuente normal: la propiedad no puede quedar pegada
        // con las cabeceras del episodio anterior.
        if (_cabecerasDeRecortePuestas) {
          await np.setProperty('http-header-fields', '');
          _cabecerasDeRecortePuestas = false;
        }
        return;
      }
      // `demuxer-lavf-o` NO se toca, y eso es a propósito: la lista se sirve
      // por 127.0.0.1, así que para mpv la entrada sigue siendo HTTP y las
      // opciones que dejó `_comoAbrir` le valen igual. Ver el comentario largo
      // en RecorteFmp4 sobre por qué un servidor y no un archivo.
      // ── Fuera las que llevan COMAS en el valor ──────────────────────────
      //
      // `http-header-fields` separa por comas, y dos de las que manda la
      // extensión las llevan adentro:
      //
      //     Accept-Language: es-ES,es;q=0.9,en;q=0.8
      //     sec-ch-ua: "Chromium";v="131", "Not_A Brand";v="24"
      //
      // mpv las parte y manda trozos que no son cabeceras (`es;q=0.9`,
      // `"Not_A Brand";v="24"`). Un servidor remoto tolerante los ignora —por
      // eso zilla nunca se quejó— pero el servidor de la lista **corta la
      // conexión**, y mpv ni llega a pedirla: «Failed to open http://127.0.0.1
      // /lista_1.m3u8» a los 10 ms, con CERO pedidos recibidos.
      //
      // Medido con las once y con las nueve, mismo episodio y mismo servidor:
      //
      //     11 cabeceras (con comas)   0 pedidos · 0,0 s   ✗
      //      9 cabeceras (sin comas)   2 pedidos · 19,0 s  ✔
      //
      // Y no se pierde nada que haga falta: lo que abre los pedacitos de zilla
      // es `Sec-Fetch-Site: same-origin`, medido aparte quitando y poniendo de
      // a una sobre el juego completo.
      final sinComas = Map<String, String>.of(cabeceras)
        ..removeWhere((_, v) => v.contains(','));
      final lista =
          sinComas.entries.map((e) => '${e.key}: ${e.value}').join(',');
      await np.setProperty('http-header-fields', lista);
      _cabecerasDeRecortePuestas = true;
      // Se lee de vuelta y se anota. En este repo ya hubo dos cambios que se
      // dieron por buenos sin haberse aplicado nunca (mpv acepta la orden y
      // deja la propiedad vacía), así que acá se comprueba que ENTRÓ.
      final quedo = await np.getProperty('http-header-fields');
      logger.info('recorte fMP4: ${sinComas.length} de ${cabeceras.length} '
          'cabeceras ${quedo.isEmpty ? "(VACÍO — no entraron)" : "puestas"} '
          '(se sacan las que llevan comas)');
    } catch (e) {
      logger.warning('recorte fMP4: no se pudieron poner las cabeceras', e);
    }
  }

  /// El último cuadro de antes del salto, para tapar el negro de la reapertura.
  ///
  /// Saltar con recorte no es un `seek`: es abrir otra fuente. Entre que mpv
  /// suelta la anterior y dibuja el primer cuadro de la nueva no tiene NADA que
  /// pintar, y eso se ve como un parpadeo negro. Se congela el cuadro anterior
  /// encima y se suelta en cuanto hay imagen nueva.
  ///
  /// Null casi siempre: solo vive el rato que dura la reapertura.


  /// Recorre a toda velocidad lo que sobra del pedacito, para caer en el
  /// segundo exacto.
  ///
  /// ── El problema ──────────────────────────────────────────────────────────
  ///
  /// El recorte deja el vídeo al principio de un pedacito, unos segundos antes
  /// del punto pedido: se pide el 41 y queda en el 31.
  ///
  /// Para mostrar el segundo 41 hay que arrancar en el fotograma clave del 31 y
  /// decodificar hasta el 41. Eso normalmente lo hace ffmpeg en silencio dentro
  /// del seek — y el seek es justo lo que no funciona en fMP4. Las dos formas
  /// de pedírselo están descartadas con medición: el salto corto no hace nada,
  /// y la opción `start` **cierra la app** (arranca sin el fotograma clave).
  ///
  /// ── Lo que se hace ───────────────────────────────────────────────────────
  ///
  /// Lo mismo, pero a mano: se reproduce ese tramo a 8x con el sonido cortado y
  /// la imagen congelada encima, así que el decodificador pasa por todos los
  /// fotogramas —tiene su referencia, no se rompe nada— y quien mira solo ve la
  /// imagen quieta un instante más. Diez segundos de vídeo son poco más de uno
  /// de espera.
  ///
  /// Degrada solo: si algo falla, el vídeo se queda donde lo dejó el recorte,
  /// que es exactamente el comportamiento de antes.
  Future<void> _afinarCorriendoRapido(
      RecorteFmp4 recorte, Duration destino) async {
    final falta = destino - recorte.desfase;
    if (falta <= const Duration(milliseconds: 700) ||
        falta > const Duration(seconds: 30)) {
      return;
    }
    final np = player.platform;
    if (np is! NativePlayer) return;

    final reloj = Stopwatch()..start();
    try {
      // Sin sonido: a 8x sería un chillido.
      await np.setProperty('mute', 'yes');
      // ── Rápido lejos, despacio cerca ────────────────────────────────────
      //
      // A 8x, entre dos comprobaciones el vídeo avanza 320 ms, así que frenar
      // solo al llegar deja pasarse un cuarto de segundo largo. Bajando a 2x en
      // el último tramo, el sobrepaso queda por debajo de una décima —
      // imperceptible— y casi no cuesta tiempo, porque son los últimos dos
      // segundos de vídeo y no los diez.
      // ── La velocidad de crucero depende de quién decodifica ─────────────
      //
      // En Android el AV1 de AnimeAV1 no abre por hardware y lo decodifica la
      // CPU («Codec sin abrir — reintentando por software» en el registro). A
      // 8x eso puede no dar abasto, así que ahí se pide 4x: tarda el doble de
      // tiempo real, pero llega. En PC hay GPU y 8x entra sin despeinarse.
      final crucero = Platform.isAndroid ? '4' : '8';
      var velocidad = '';
      // Para detectar que no avanza: si el decodificador no llega, seguir
      // esperando no arregla nada y deja al usuario mirando una imagen quieta.
      var ultimaVista = player.state.position;
      var quietoDesde = DateTime.now();
      while (!_disposed && reloj.elapsed < const Duration(seconds: 8)) {
        // Si ya se pidió otro salto, este destino quedó viejo: seguir corriendo
        // hacia él es tiempo perdido y encima retrasa el que sí importa.
        if (_saltoPendiente != null) {
          logger.info('recorte fMP4: se corta el afinado, hay otro salto');
          break;
        }
        final donde = player.state.position;
        final resta = falta - donde;
        if (resta <= Duration.zero) break;

        // ¿Se está moviendo? Un segundo y medio sin avanzar es que no llega.
        if (donde > ultimaVista) {
          ultimaVista = donde;
          quietoDesde = DateTime.now();
        } else if (DateTime.now().difference(quietoDesde) >
            const Duration(milliseconds: 1500)) {
          logger.info('recorte fMP4: se corta el afinado, el vídeo no avanza '
              '(quedan ${resta.inMilliseconds} ms) — se deja donde está');
          break;
        }

        final quiere = resta > const Duration(seconds: 2) ? crucero : '2';
        if (quiere != velocidad) {
          await np.setProperty('speed', quiere);
          velocidad = quiere;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } catch (e) {
      logger.info('recorte fMP4: no se pudo afinar corriendo rápido', e);
    } finally {
      // Se restaura SIEMPRE, pase lo que pase: dejar el vídeo a 8x y en
      // silencio sería mucho peor que caer unos segundos antes.
      try {
        await np.setProperty('speed', '1');
        await np.setProperty('mute', 'no');
      } catch (_) {}
    }
    if (_disposed) return;
    logger.info('recorte fMP4: afinado corriendo ${falta.inMilliseconds} ms a 8x '
        'en ${reloj.elapsedMilliseconds} ms reales → '
        '${(player.state.position + recorte.desfase).inSeconds}s');
  }

  /// Suelta el cuadro congelado cuando el vídeo volvió a avanzar.
  ///
  /// Y de paso apaga la rueda de búsqueda: sin esto se quedaba girando un rato
  /// después de que la imagen ya se veía. La lógica normal la apaga al ver dos
  /// posiciones distintas seguidas, y en una reapertura la primera tarda en
  /// llegar, así que la rueda sobrevivía a la vuelta de la imagen.
  Future<void> _soltarCuadroCuandoHayaImagen({Duration? desdeAquiSuma}) async {
    // Desde dónde cuenta el avance. Con el afinado, el vídeo ya está en el
    // punto pedido cuando esto arranca, así que el umbral tiene que ser
    // RELATIVO a ahí: si no, se cumple en el acto y se destapa la imagen antes
    // de que mpv haya pintado el primer cuadro nuevo — el parpadeo otra vez.
    final base = desdeAquiSuma ?? Duration.zero;
    final reloj = Stopwatch()..start();
    while (!_disposed && reloj.elapsed < const Duration(seconds: 6)) {
      // Se mira seguido: cada vuelta que se tarda de más es un cuadro nuevo
      // tapado por la foto vieja, y eso se nota como una transición pesada.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      // ── La posición CRUDA de mpv, no `position.value` ──────────────────
      //
      // `position.value` no sirve de referencia acá: `seek()` la mueve al
      // destino ANTES de mandar el salto (para que se puedan encadenar), así
      // que ya vale lo mismo que valdrá después. Comparando contra ella la
      // condición no se cumplía nunca y el cuadro congelado se quedaba pegado
      // los seis segundos del tope, tapando la imagen nueva. Peor que el
      // parpadeo que venía a tapar.
      //
      // La cruda sí sirve: tras reabrir arranca en cero y sube sola. En cuanto
      // se mueve hay imagen nueva, y ese es el momento de soltar la foto.
      //
      // El umbral era de medio segundo y se veía como una transición lenta: la
      // imagen nueva ya estaba pintada y la foto vieja seguía encima medio
      // segundo más. Con 120 ms alcanza para no confundir el cero inicial con
      // reproducción, y el cambio pasa desapercibido.
      // Y además tiene que estar reproduciendo: con el búfer todavía llenándose
      // la posición se mueve pero la imagen no está, y destapar ahí es
      // exactamente el parpadeo que se quiere evitar.
      if (player.state.position - base > const Duration(milliseconds: 120) &&
          !player.state.buffering) {
        break;
      }
    }
    if (_disposed) return;

    // ── Se suelta TODO lo que enciende la rueda, no solo la búsqueda ───────
    //
    // Con `_clearSeeking()` sola no alcanzaba y la rueda seguía girando un buen
    // rato con la imagen ya en pantalla. Los otros dos que la encienden:
    //
    //  - `_destinoDeSalto`: mientras está puesto, `_aceptarPosicion` rechaza
    //    todo lo que informe mpv, así que la posición no se actualiza y nada
    //    da la búsqueda por terminada. El corte cae al principio de un
    //    pedacito, o sea unos segundos ANTES del minuto pedido, y esa
    //    diferencia bastaba para que no se soltara solo.
    //  - `isActuallyBuffering`: mpv lo deja pegado en true al cambiar de
    //    fuente, y se apaga al ver avanzar la posición — que es justo lo que
    //    el punto anterior estaba bloqueando.
    //
    // Acá ya hay imagen nueva confirmada, así que los tres sobran.
    cuadroCongelado.value = null;
    _destinoDeSalto = null;
    if (isActuallyBuffering.value) isActuallyBuffering.value = false;
    _clearSeeking();
  }

  /// El último cuadro de antes del salto, congelado hasta que haya imagen nueva.
  ///
  /// Es lo que evita el negro al saltar: la imagen se queda quieta y cambia
  /// cuando llega la nueva, como en YouTube. Null casi siempre — solo vive lo
  /// que dura la reapertura.
  final Rx<Uint8List?> cuadroCongelado = Rx<Uint8List?>(null);

  /// La última posición cruda que informó mpv. Solo para el detector de saltos
  /// fantasma del listener de posición — temporal.
  Duration? _ultimaCruda;

  /// Rehace la lista para que empiece en [destino] y la abre.
  ///
  /// Es lo que reemplaza al `player.seek()` cuando hay recorte. Cuesta una
  /// reapertura (~1,5 s medidos en zilla), pero hoy el salto directo
  /// sencillamente no llega nunca.
  Future<void> _saltarConRecorte(RecorteFmp4 recorte, Duration destino) async {
    // ── Uno por vez ────────────────────────────────────────────────────────
    //
    // Con la barra da igual —los saltos se juntan y llega uno solo— pero con
    // las teclas no: cada toque del salto por intervalo puede disparar su
    // reapertura, y dos `player.open()` encimados dejan a mpv abriendo dos
    // fuentes a la vez. Es el mismo cuadro que ya está documentado como causa
    // del audio duplicado.
    //
    // Se anota el ÚLTIMO destino pedido y lo atiende el que está corriendo al
    // terminar: así cinco toques seguidos son una reapertura al punto final,
    // no cinco encadenadas.
    if (_saltandoConRecorte.value) {
      _saltoPendiente = destino;
      return;
    }
    _saltandoConRecorte.value = true;
    try {
      await _hacerElSaltoConRecorte(recorte, destino);
    } finally {
      _saltandoConRecorte.value = false;
    }
    final pendiente = _saltoPendiente;
    _saltoPendiente = null;
    // Y se atiende SOLO si el recorte sigue siendo el de la fuente actual. Si
    // en el medio se cambió de servidor o de episodio, `_recorte` ya es otro y
    // este pedido quedó viejo: hacerlo abriría un pedazo del vídeo anterior.
    if (pendiente != null && !_disposed && identical(_recorte, recorte)) {
      await _saltarConRecorte(recorte, pendiente);
    } else if (pendiente != null) {
      logger.info('recorte fMP4: se descarta un salto pendiente, la fuente '
          'cambió mientras tanto');
    }
  }

  final _saltandoConRecorte = false.obs;
  Duration? _saltoPendiente;

  /// Si el vídeo venía reproduciendo cuando empezó el salto.
  ///
  /// Al tocar la barra o el intervalo con recorte se pausa —si no, la escena
  /// sigue corriendo mientras la barra ya apunta a otro lado— y al terminar hay
  /// que dejarlo como estaba: saltar no puede reanudar algo que el usuario
  /// había pausado a propósito.
  bool _reproduciaAntesDelSalto = true;

  /// Deja el reproductor como estaba cuando un salto no se pudo hacer.
  ///
  /// Todo lo que se enciende al empezar un salto tiene que apagarse acá, o la
  /// pantalla queda peor que si no se hubiera tocado nada: la barra clavada en
  /// un minuto al que nunca se llegó, la rueda girando sin fin y el cuadro
  /// viejo tapando la imagen. El vídeo sigue reproduciendo donde estaba.
  void _rendirseConElSalto() {
    cuadroCongelado.value = null;
    _destinoDeSalto = null;
    _clearSeeking();
    // La barra vuelve a donde el vídeo está de verdad, no donde se quiso ir.
    if (_recorte != null) {
      position.value = player.state.position + _recorte!.desfase;
    }
  }

  Future<void> _hacerElSaltoConRecorte(
      RecorteFmp4 recorte, Duration destino) async {
    // ── La barra va al destino YA ──────────────────────────────────────────
    //
    // Cuando el salto viene de la barra o de las teclas esto ya lo hizo
    // `seek()`. Pero «continuar viendo» NO pasa por ahí: llama derecho a
    // `_saltarCuandoSePueda`, así que la barra se quedaba en la posición vieja
    // hasta que mpv terminaba de reabrir —un segundo largo— y recién ahí
    // saltaba al minuto bueno. Eso es lo que se ve como «pone una posición que
    // no es y después la corrige».
    //
    // `_destinoDeSalto` además protege ese rato: sin él, las posiciones que mpv
    // informa mientras todavía reproduce el tramo anterior pisan la barra y la
    // hacen ir y venir.
    _destinoDeSalto = destino;
    position.value = destino;
    markSeeking();
    // El reloj del vigilante arranca de cero acá también: si no, cuenta como
    // «el vídeo no avanza» todo el rato que tarda la reapertura, que es trabajo
    // nuestro y no un problema del vídeo.
    _lastPositionAdvanceAt = DateTime.now();

    // ── La imagen se congela ANTES de reabrir ──────────────────────────────
    //
    // Como hace YouTube: el último cuadro se queda quieto y cambia recién
    // cuando hay imagen nueva. Sin negro en el medio.
    //
    // El orden es lo que importa, y es donde fallaba antes: la foto se pedía en
    // paralelo con la apertura, así que mpv soltaba la imagen mientras la foto
    // todavía se estaba sacando (mide 374-901 ms) y el negro se veía igual.
    // Ahora se espera a tenerla EN PANTALLA y recién entonces se reabre. Cuesta
    // esa espera, y es justamente lo que se está comprando.
    //
    // Si no se puede sacar, se sigue igual: se verá el parpadeo, pero saltar es
    // la función y tapar el hueco es la comodidad.
    final relojFoto = Stopwatch()..start();
    try {
      final foto = await player
          .screenshot()
          .timeout(const Duration(milliseconds: 900));
      if (foto != null && foto.isNotEmpty) cuadroCongelado.value = foto;
    } catch (_) {}
    if (_disposed) return;
    logger.info('recorte fMP4: imagen congelada en '
        '${relojFoto.elapsedMilliseconds} ms'
        '${cuadroCongelado.value == null ? " (no se pudo — se verá el parpadeo)" : ""}');

    // Dónde está el vídeo AHORA, para que un salto adelante no termine detrás.
    // Es la posición real del episodio, no la del pedazo. Ver listaDesde.
    final estabaEn = player.state.position + recorte.desfase;
    final ruta = await recorte.listaDesde(destino, sinQuedarAtrasDe: estabaEn);
    // La barra pasa YA al minuto donde va a quedar el vídeo, y se queda ahí.
    //
    // Cuál es ese minuto depende de si el tramo sobrante se va a recorrer a 8x
    // (ver _afinarCorriendoRapido):
    //
    //  - con afinado, el vídeo termina en el minuto PEDIDO;
    //  - sin él, termina donde empieza el pedacito.
    //
    // Y `_destinoDeSalto` tiene que quedar en ese mismo valor: mientras está
    // puesto, las posiciones intermedias no pisan la barra. Sin eso, durante el
    // avance rápido se veía el contador trepar de 780 a 790 a la vista, que es
    // justo lo que el afinado viene a disimular.
    if (ruta != null && !_disposed) {
      final delPedacito = recorte.desfaseQueViene;
      final sobra = destino - delPedacito;
      final habraAfinado = sobra > const Duration(milliseconds: 700) &&
          sobra <= const Duration(seconds: 30);
      final real = habraAfinado ? destino : delPedacito;
      _destinoDeSalto = real;
      position.value = real;
    }
    if (ruta == null || _disposed) {
      // Que el salto falle no puede dejar la pantalla rota: sin esto quedaban
      // la barra clavada en un destino al que nunca se llegó, la rueda girando
      // para siempre y el cuadro viejo congelado encima. El vídeo sigue
      // reproduciendo donde estaba, así que hay que devolverle el mando.
      _rendirseConElSalto();
      return;
    }

    // ── El salto cae al PRINCIPIO del pedacito, y no hay forma de afinarlo ──
    //
    // Se pide el 41 y queda en el 31. Es la granularidad del formato: los
    // pedacitos de zilla duran ~10 s y cada uno empieza con un fotograma clave.
    //
    // Se intentaron las dos formas de cerrar esa diferencia, y las DOS están
    // descartadas con medición. No reintentarlas:
    //
    //  1. `player.seek()` corto después de abrir → no hace nada. Es el mismo
    //     bug de fMP4 en pequeño: el registro decía «ajuste fino de 5000 ms» y
    //     el vídeo se quedaba igual en 11 s.
    //
    //  2. La opción `start` de mpv, para arrancar unos segundos adentro →
    //     **CIERRA LA APP**. Arrancar a mitad de un pedacito deja al
    //     decodificador AV1 sin el fotograma de referencia:
    //
    //         Missing reference frame needed for show_existing_frame
    //         No sequence header available: unable to decode frame header
    //         Missing Sequence Header
    //         Lost connection to device
    //
    //     Y tiene sentido: el keyframe está al principio del pedacito, que es
    //     justo lo que `start` se saltea.
    //
    // Así que el salto cae donde cae. La barra muestra el minuto real, que es
    // lo que importa para no mentirle a quien mira.
    try {
      // Sin httpHeaders, igual que en la apertura: las de los pedacitos ya
      // están puestas como propiedad de mpv y siguen ahí entre aperturas.
      await player.open(Media(ruta));
      if (_disposed) return;
      // Recién ACÁ entra el desfase nuevo. Antes de `open()` mpv todavía
      // informa la posición del tramo anterior, y sumarle el desfase de la
      // lista nueva daba una posición inventada. Eso rompía dos cosas a la vez:
      // el contador saltaba a cero o a cualquier lado, y como `_aceptarPosicion`
      // nunca reconocía esa posición, la búsqueda no se daba por terminada y la
      // rueda giraba para siempre aunque el vídeo estuviera reproduciendo bien.
      recorte.confirmar();

      // ── El vigilante de «imagen congelada» no puede acusar a sus propios
      //    saltos ─────────────────────────────────────────────────────────
      //
      // Ese vigilante mide cuánto hace que la posición no avanza. Mientras
      // dura una reapertura, `_aceptarPosicion` rechaza las posiciones que
      // informa mpv —son del tramo viejo— así que ese reloj no se toca y sigue
      // corriendo. Con varios saltos seguidos llegaba a 39 s y saltaba
      // «El video lleva 39s sin avanzar» sobre un vídeo que reproducía
      // perfecto. Es exactamente lo mismo que se hace al abrir una fuente.
      _lastPositionAdvanceAt = DateTime.now();
      _lastPositionSeen = null;
      imagenCongelada.value = false;
      safePlay();
      // Y el tramo que sobra del pedacito se recorre a toda velocidad, tapado.
      await _afinarCorriendoRapido(recorte, destino);
      // El cuadro congelado se suelta cuando hay imagen nueva de verdad, no al
      // volver `open()`: ahí mpv todavía está abriendo y soltarlo deja el
      // parpadeo igual. Se espera a que la posición avance, con tope por si no
      // llega nunca —quedarse con una foto pegada sería peor que el parpadeo—.
      // Y se lo deja como estaba antes del salto. El afinado necesita que
      // reproduzca para avanzar, así que la pausa solo se puede reponer acá,
      // cuando ya llegó.
      if (!_reproduciaAntesDelSalto && _saltoPendiente == null) {
        try {
          player.pause();
        } catch (_) {}
      }
      // La imagen se destapa recién cuando el vídeo REPRODUCE en el punto
      // nuevo. Si hubo afinado, ya está ahí, así que se cuenta desde ese punto
      // y no desde cero.
      unawaited(_soltarCuadroCuandoHayaImagen(
          desdeAquiSuma: player.state.position));
    } catch (e) {
      _rendirseConElSalto();
      logger.warning('recorte fMP4: no se pudo reabrir en $destino', e);
    }
  }

  Future<bool> _tryOpenPlayer(String url, Map<String, String>? headers) async {
    // _isPlaybackClosed() y no _disposed a secas en toda esta función: acá
    // es donde de verdad se abre el audio, así que es el lugar que más le
    // importa enterarse de un cierre de ruta en curso (_routeClosing) y no
    // solo de un dispose ya terminado. Ver el comentario largo en
    // _isPlaybackClosed.
    if (_isPlaybackClosed()) return false;
    if (url.startsWith('error://')) {
      logger.severe('URL de error recibida: $url');
      return false;
    }
    if (!await _isHostReachable(url)) {
      return false;
    }
    if (_isPlaybackClosed()) return false;
    // Montar el widget Video ANTES de abrir la fuente — sin esto mpv nunca
    // tiene una superficie real donde pintar (pantalla negra pese a que
    // audio/progreso sí avanzan) y su pipeline de render queda a medio
    // inicializar, el mismo estado que _safePlayerInit documenta como causa
    // de SIGSEGV al hacer dispose/stop más tarde. playTorrentFile y
    // switchQuality ya lo hacían; este es el chokepoint común de TODA la
    // reproducción de servidores (primario, switchServer, fallback directo,
    // sniffer), así que faltaba justo acá.
    await _ensureVideoSurfaceMounted();
    if (_isPlaybackClosed()) return false;
    // Inyectar User-Agent de browser si no viene en los headers.
    // libmpv por defecto envía "Lavf/X.X.X" que los CDNs de streaming bloquean.
    final hdrs = <String, String>{'User-Agent': _browserUA};
    if (headers != null) hdrs.addAll(headers);
    // La declaración de la extensión se lee y se SACA: de acá para abajo todo lo
    // que quede en el mapa sale a la red, y esto no es una cabecera de verdad.
    //
    // Se saca de las DOS: de `hdrs`, que es lo que se le pasa a mpv, y de una
    // copia de las de la extensión, que es lo que sigue viaje. Copia y no el
    // mapa original: ese es de `watchData` y lo comparten otros.
    final lecturaContinua = hdrs.remove(_lecturaContinua) == '1';
    final headersLimpias = headers == null
        ? null
        : (Map<String, String>.of(headers)..remove(_lecturaContinua));
    // La bomba anterior se suelta ANTES de abrir otra fuente: cada una deja
    // lecturas abiertas contra el servidor y nadie más las va a cerrar.
    _soltarLaBomba();
    // Cómo conviene abrir esta fuente: tal cual, por el relay para esquivar
    // nodos caídos, o directamente no intentarlo. Ver _comoAbrir.
    // Las pistas del maestro anterior no valen para esta fuente: se olvidan
    // antes de mirarla. `_comoAbrir` las vuelve a llenar si esta trae.
    // Se reemplaza en vez de vaciar: si lo que hay adentro vino inmodificable,
    // `clear()` tira una excepción y corta la reproducción antes de empezar.
    audiosHls.value = <PistaDeAudio>[];
    audioHlsElegido.value = -1;
    final plan = await _comoAbrir(url, headersLimpias, lecturaContinua);
    if (_isPlaybackClosed()) return false;
    _fuenteUrl = plan.url ?? url;
    _fuenteHeaders = hdrs;
    // ── Se para lo anterior ANTES de abrir lo nuevo, siempre ────────────
    //
    // Este es el chokepoint por el que pasa TODA apertura (primaria,
    // switchServer, fallback directo, sniffer, calidad) — así que es el
    // lugar correcto para una red de seguridad contra el audio duplicado
    // reportado en vivo: al perder la conexión y recuperarla (o al confirmar
    // "continuar donde ibas" justo cuando otra resolución ya estaba en
    // camino), dos caminos podían terminar pidiendo abrir una fuente casi a
    // la vez, y por un instante sonaban las dos superpuestas.
    //
    // `player.open()` en teoría ya reemplaza la fuente anterior, pero eso pasa
    // DEL LADO NATIVO (mpv) y de forma asíncrona; si un segundo `open()`
    // llega antes de que el primero terminó de soltar su audio, la ventana
    // quedaba abierta. Parar y ESPERARLO acá, del lado Dart, antes de cada
    // apertura, cierra esa ventana pase lo que pase del otro lado.
    //
    // Con tope: si el reproductor está en un estado raro (la misma
    // condición documentada en shutdownPlayback), no puede trabar la
    // apertura siguiente por un stop() que nunca vuelve.
    try {
      await player.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (_isPlaybackClosed()) return false;

    // ── Adelantar en fMP4: se abre una lista recortada, no la de la red ──────
    //
    // Solo AnimeAV1, y solo si la lista trae de verdad un `#EXT-X-MAP`. En fMP4
    // pedirle a mpv que salte lo deja clavado —bug de ffmpeg cerrado como "not
    // planned"— así que en vez de pedirle que salte se le da una lista que ya
    // empieza donde se quiere. Ver `RecorteFmp4`.
    //
    // Si no aplica, `_recorte` queda en null y de acá para abajo todo sigue
    // exactamente como antes.
    await _prepararRecorte(plan.url ?? url, hdrs);

    // ── Siempre se abre en el PRINCIPIO ────────────────────────────────────
    //
    // Se probó abrir directo en el minuto guardado, para ahorrarse la
    // reapertura al contestar «continuar». Técnicamente andaba, pero el flujo
    // quedaba al revés: el vídeo ya estaba en el minuto cuando aparecía el
    // cartel preguntando si querías ir ahí, así que aceptar no hacía nada
    // visible y el mensaje sobraba.
    //
    // El orden correcto es el de siempre: empieza en cero, y el cartel es lo
    // que lleva al minuto guardado si se acepta. Descartado a propósito, no se
    // perdió: si alguna vez se quiere quitar esa reapertura, hay que quitar
    // también el cartel, no dejar los dos.
    final listaRecortada = await _recorte?.listaDesde(Duration.zero);
    // Las cabeceras de los pedacitos van como propiedad de mpv, no en el
    // Media: ver _cabecerasParaElRecorte.
    await _cabecerasParaElRecorte(hdrs);

    // Y con recorte el Media va SIN httpHeaders a propósito. Si se las pasara
    // igual, media_kit volvería a escribir `http-header-fields` con su propio
    // formato —pegando las cabeceras con comas, sin escapar— y pisaría el que
    // se acaba de poner bien.
    await player.open(listaRecortada != null
        ? Media(listaRecortada)
        : Media(plan.url ?? url, httpHeaders: hdrs));
    // El desfase entra recién con la fuente ya abierta — igual que en el salto.
    // Sin esto, abrir directo en el minuto guardado dejaba la barra contando
    // desde cero sobre un vídeo que empieza más adelante.
    _recorte?.confirmar();

    if (_isPlaybackClosed()) {
      try {
        unawaited(player.stop());
      } catch (_) {}
      return false;
    }

    // media_kit accepts any URL in open() but only reports an unplayable
    // source (e.g. "Failed to recognize file format" for an HTML embed like
    // mega.nz) later, asynchronously, via the error stream. Race a real
    // success signal (duration / video params) against the error stream so a
    // dead source fails over to the next server instead of showing a stuck
    // player.
    final completer = Completer<bool>();
    final subs = <StreamSubscription>[];
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    subs.add(player.stream.error.listen((e) {
      logger.warning('media_kit no pudo reproducir ($url): $e');
      finish(false);
    }));
    subs.add(player.stream.duration.listen((d) {
      if (d > Duration.zero) finish(true);
    }));
    subs.add(player.stream.videoParams.listen((p) {
      if ((p.w ?? 0) > 0 && (p.h ?? 0) > 0) finish(true);
    }));

    // Confirmado en vivo varias veces (Streamwish, y de nuevo con Voe/voe.sx):
    // la URL resuelta es real y válida, pero media_kit puede tardar bastante
    // más de 8s (incluso más de 25s con Voe, cuyo CDN espejo cloudwindow-route
    // es lento para arrancar) en reconocer el formato/duración la primera
    // vez — el chequeo reportaba "falló" y el video arrancaba solo, sano,
    // unos segundos después. 35s da margen real; el watchdog de buffering
    // (más abajo, mismo margen) ya cubre el caso de un servidor genuinamente
    // colgado DESPUÉS de abrir, así que no hace falta que este timeout sea
    // corto "por las dudas" — total nada queda esperando para siempre (y
    // ahora que un fallo pasa automáticamente al siguiente servidor, esperar
    // un poco más acá sale más barato que antes).
    final ok = await Future.any<bool>([
      completer.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () => false,
      ),
      _shutdownCompleter.future.then((_) => false),
    ]);
    for (final s in subs) {
      unawaited(s.cancel());
    }
    if (_disposed) {
      try {
        unawaited(player.stop());
      } catch (_) {}
      return false;
    }
    if (!ok) {
      logger.info('Fuente no reproducible, se intentará failover: $url');
    } else if (_midStreamResumeAt != null) {
      if (_recorte != null) {
        // ── Con recorte, esto NO se aplica ────────────────────────────────
        //
        // Esta marca existe para recuperarse de un corte a mitad de capítulo:
        // se guarda dónde iba y se vuelve ahí tras reabrir. Con el recorte
        // sobra y hace daño:
        //
        //  - la lista ya se armó desde el punto que corresponde, así que no hay
        //    nada que recuperar;
        //  - es un `player.seek()` sobre fMP4, o sea el salto que no funciona;
        //  - y devolvía al minuto viejo justo cuando se había pedido el
        //    principio. Reportado en vivo: cancelar el cartel de continuar y
        //    querer ir al comienzo terminaba de vuelta en el 19.
        //
        // Se descarta la marca, que es lo que la deja de arrastrar.
        logger.info('recorte fMP4: se descarta la vuelta al minuto '
            '${_midStreamResumeAt!.inSeconds}s — la lista ya empieza donde toca');
        _midStreamResumeAt = null;
      } else {
        // Recuperación de un corte a mitad de capítulo (ver
        // _midStreamResumeAt) — seguir donde se quedó en vez de arrancar
        // la fuente nueva desde 0.
        player.seek(_midStreamResumeAt!);
        _midStreamResumeAt = null;
      }
    }
    return ok;
  }

  // Nombre del servidor recordado para el diálogo "¿Continuar donde te
  // quedaste?" — mismo storage que usa _applyPreferredServer, solo lectura.
  String? get rememberedServerName => PrismHubStorage.getLastWorkingServer(
        runtime.extension.package,
        playList[index.value].url,
      );

  /// Si al retomar conviene ir derecho al navegador en vez de intentar nativo.
  ///
  /// **Ojo con la clave de ese recuerdo: es el EPISODIO, no el servidor.** O sea
  /// que apenas UNO de los servidores del episodio cae al navegador, queda
  /// marcado el episodio entero — y a partir de ahí CUALQUIER servidor que se
  /// retome abre el navegador sin siquiera intentar el reproductor de la app.
  ///
  /// Eso hacía que un servidor que reproduce perfecto, como UA Directo o UA
  /// Goodstream en FuegoCine, se abriera en el navegador para siempre solo
  /// porque otro de la lista había fallado antes. Y no se recuperaba solo: el
  /// recuerdo solo se pisa cuando algo vuelve a reproducir nativo, que es
  /// justamente lo que este atajo impedía.
  ///
  /// Por eso ahora manda lo que diga la extensión: si declara que ese servidor
  /// reproduce en la app, se intenta nativo aunque el recuerdo diga otra cosa.
  /// Si falla de verdad, la app cae al navegador sola como siempre — se pierde
  /// un intento, no la reproducción.
  ///
  /// El atajo se conserva para los que la extensión marca como de navegador:
  /// ahí sí ahorra el intento inútil y abre más rápido.
  bool _shouldResumeInWebView() {
    final nombre = currentServerName.value;
    final url = availableServers[nombre];
    if (url != null && url.isNotEmpty && esServidorNativo(nombre, url)) {
      return false;
    }
    return PrismHubStorage.getLastPlaybackMode(
          runtime.extension.package,
          playList[index.value].url,
        ) ==
        'webview';
  }

  bool _openPreferredWebViewFallback() {
    final name = currentServerName.value;
    if (name.isEmpty) return false;
    final url = availableServers[name];
    if (url == null || url.isEmpty || url.startsWith('error://')) {
      return false;
    }
    webViewOpenedOnce.value = false;
    webViewFallback.value = {
      'url': url,
      'name': name,
      'referer': serverReferers[name] ?? '',
    };
    serverFailedMessage.value =
        'No se puede reproducir en el reproductor nativo.\n'
        'Puedes verlo desde el navegador interno.';
    awaitingServerChoice.value = false;
    isGettingWatchData.value = false;
    return true;
  }

  void markWebViewPlayback(Map<String, String>? fallback) {
    final episodeUrl = playList[index.value].url;
    final name = fallback?['name'] ?? currentServerName.value;
    if (name.isNotEmpty && availableServers.containsKey(name)) {
      unawaited(PrismHubStorage.setLastWorkingServer(
        runtime.extension.package,
        episodeUrl,
        name,
      ));
    }
    unawaited(PrismHubStorage.setLastPlaybackMode(
      runtime.extension.package,
      episodeUrl,
      'webview',
    ));
  }

  /// Decide CÓMO abrir una fuente HLS: tal cual, por el relay, o ni intentarlo.
  ///
  /// Hace tres cosas que antes no se podían, y las tres salieron de mediciones:
  ///
  /// 1. **Esquivar nodos caídos.** Estas listas reparten los pedacitos entre
  ///    varios nodos del mismo CDN y algunos entregan a 2 MB/s mientras otros no
  ///    terminan el archivo en quince segundos. Los pedacitos los pide mpv, así
  ///    que la única forma de elegir el nodo es ponerse en el medio.
  /// 2. **Seguir las listas maestras.** Un maestro no trae pedacitos sino otras
  ///    listas, así que antes se abría directo y nos perdíamos todo lo de
  ///    arriba. Ahora se sigue hasta la lista de la variante.
  /// 3. **Descartar rápido una fuente que no va a andar.** Medido con
  ///    Streamwish: el maestro se bajó bien, se le pasó a mpv, y **treinta y
  ///    cinco segundos después** se dio por no reproducible. Si el maestro se
  ///    puede leer pero su variante no, la fuente está muerta y eso se sabe en
  ///    un segundo — no hay motivo para esperar los treinta y cinco.
  ///
  /// Ante cualquier duda se abre tal cual, como siempre: nunca puede dejar el
  /// vídeo peor que antes.
  /// Deja o no que mpv salte dentro del archivo, según lo que se vaya a abrir.
  ///
  /// `reconnect_streamed` le dice a ffmpeg que trate la fuente como un flujo
  /// que NO se puede recorrer: ante un corte, reconecta y sigue leyendo de
  /// corrido en vez de volver a pedir desde donde estaba. Para HLS es lo que
  /// se quiere, porque son pedacitos independientes.
  ///
  /// Para un archivo entero es un desastre. Un MP4 puede tener su índice al
  /// FINAL, y sin poder saltar hay que leer todo el archivo para llegar a él.
  /// Medido en vivo con un servidor de FuegoCine: 638 MB con el índice al
  /// fondo, entrando a 20 KB/s y la posición clavada en cero, mientras el
  /// mismo archivo pedido aparte llegaba a 3,4 MB/s. Se veía como que el vídeo
  /// carga, arranca y se para todo el rato.
  ///
  /// Se descartó que fueran las cabeceras: medido con y sin Referer y con y
  /// sin User-Agent de navegador, la velocidad del servidor no cambia.
  ///
  /// `reconnect` (a secas) se deja puesto en los dos casos: reconectar cuando
  /// se corta la conexión sigue siendo bueno. Lo que estorba es lo otro.
  Future<void> _dejarSaltarDentroDelArchivo(
    bool archivoEntero,
    String url,
    Map<String, String>? headers,
  ) async {
    final np = player.platform;
    if (np is! NativePlayer) return;
    // En Linux reconnect va apagado a propósito (ver dónde se ponen estas
    // opciones al arrancar) — no se toca desde acá.
    if (Platform.isLinux) return;
    // `multiple_requests=1` solo en el archivo entero: que ffmpeg REUSE la misma
    // conexión para pedir otro tramo, en vez de abrir una nueva cada vez.
    //
    // Es lo que faltaba para los MP4 mal entrelazados, y recién ahora se sabe
    // por qué. Medido el 2026-08-05 con dos títulos de FuegoCine, los dos con el
    // índice al final, uno se corta y el otro va perfecto:
    //
    //   el que falla   vídeo del MB 0 al 568 · audio del MB 568 al 608
    //   el que anda    vídeo y audio mezclados cada ~1 KB de punta a punta
    //
    // O sea que el que falla NO está entrelazado: el audio está entero al final.
    // Para armar cada segundo hay que leer vídeo al principio y audio a 568 MB
    // de distancia — dos saltos de medio giga por segundo. Y cada salto, sin
    // esto, es cerrar la conexión y abrir otra: TCP más TLS, unos 250 ms que se
    // van en apretón de manos. A dos por segundo se va medio segundo de cada
    // segundo en saludar, y por eso entran 40 KB/s con el servidor dando 7 MB/s.
    //
    // **Por qué antes se creyó que esto no servía:** figuraba descartado porque
    // "demuxer-lavf-o va al lector de MP4, no al protocolo". Es falso, y lo
    // prueba la propia línea de al lado: `reconnect` es una opción del protocolo
    // HTTP de ffmpeg y se pasa por acá desde siempre, y funciona. libavformat
    // baja al protocolo las opciones que el demuxer no reconoce.
    //
    // Va SOLO en el archivo entero. En una lista de pedacitos cada uno es una
    // dirección distinta y no hay nada que reusar.
    // ── `multiple_requests=1`: por qué está, con la medición al lado ───────
    //
    // **Este servidor cobra caro cada pedido nuevo.** Medido en mp4upload el
    // 2026-08-06, sobre el mismo archivo y la misma red:
    //
    //   pedido abierto (`bytes=0-`), leyendo de corrido   1812 KB/s
    //   lo mismo desde el medio, tras un salto            1789 KB/s
    //   un trozo cerrado de 1 MB                           514 KB/s
    //   un trozo cerrado de 256 KB                         171 KB/s
    //
    // Tarda cerca de un segundo y medio en empezar a contestar, y recién ahí
    // agarra velocidad. O sea que lo que importa no es el ancho de banda sino
    // CUÁNTOS pedidos se hacen: pidiendo de a poco y reconectando cada vez, el
    // caudal se derrumba a unos 6 KB/s y el vídeo se congela con el colchón en
    // cero.
    //
    // Y el servidor contesta `connection: close`, así que sin esta opción cada
    // lectura después de un salto abre una conexión nueva y paga ese segundo y
    // medio otra vez. `multiple_requests` le pide a ffmpeg que mande los
    // pedidos siguientes por la conexión que ya tiene.
    //
    // Va SOLO en el archivo entero: en una lista de pedacitos cada uno es una
    // dirección distinta y no hay nada que reusar.
    //
    // **Ojo con volver a sacarla.** Ya se sacó dos veces hoy por conclusiones
    // equivocadas: se la estaba midiendo junto a otro cambio del mismo día
    // —poner las pistas de vídeo en automático antes de cada apertura— que era
    // el que dejaba la pantalla en negro. Con los dos encima ninguna prueba
    // decía nada. Si hay que volver a evaluarla, que sea sola.
    final opciones = archivoEntero
        ? 'reconnect=1,reconnect_delay_max=5,seg_max_retry=3,'
            'multiple_requests=1'
        : 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5,'
            'seg_max_retry=3';
    try {
      await np.setProperty('demuxer-lavf-o', opciones);
      // Se relee lo que quedó puesto de verdad, no lo que se pidió: si mpv
      // ignora el cambio, en el registro se ve la diferencia en vez de tener
      // que suponerlo.
      final quedo = await np.getProperty('demuxer-lavf-o');
      // Se dice aparte si la reutilización de conexión ENTRÓ, y se lee de lo
      // que quedó puesto de verdad, no de lo que se pidió. Es el dato que hay
      // que mirar cuando un archivo mal entrelazado sigue cortándose: si acá
      // dice "no", el problema es que la opción no llegó, no el archivo.
      logger.info('saltar dentro del archivo: '
          '${archivoEntero ? 'SÍ (archivo entero)' : 'no (lista de pedacitos)'}'
          ' · quedó: $quedo');
      _anotarDondeEstaElIndice(url, headers);
    } catch (e) {
      // Que no se pueda ajustar no puede impedir reproducir: se sigue con lo
      // que haya quedado puesto al arrancar.
      logger.info('no se pudo ajustar el salto dentro del archivo: $e');
    }
  }

  /// Anota en el registro dónde tiene el índice el archivo que se va a abrir.
  ///
  /// Es SOLO para el registro: no cambia ni un ajuste del reproductor. Está
  /// puesto con tres candados para que no pueda estropear nada de lo que hoy
  /// funciona en las demás extensiones:
  ///
  /// 1. **No se espera.** Sale sin bloquear, así que no le agrega ni un
  ///    milisegundo a la apertura del vídeo, ande rápido o lento el servidor.
  /// 2. **Va después de mpv.** Los pocos servidores que dan enlaces de un solo
  ///    uso lo gastarían con el primer pedido: se deja que ese sea el de mpv y
  ///    no el nuestro. Si para cuando miramos el enlace ya no sirve, se anota
  ///    que no se pudo ver y listo — el vídeo ya está andando.
  /// 3. **Solo archivos de vídeo.** Con una lista cerrada de extensiones, así
  ///    una dirección rara no se lleva un pedido que no le toca.
  void _anotarDondeEstaElIndice(String url, Map<String, String>? headers) {
    const enteros = ['.mp4', '.mkv', '.webm', '.mov', '.avi', '.m4v'];
    final ruta = url.split('?').first.toLowerCase();
    if (!enteros.any(ruta.endsWith)) return;
    unawaited(Future.delayed(const Duration(seconds: 5), () async {
      logger
          .info('índice del archivo: ${await _comoEstaElIndice(url, headers)}');
    }));
  }

  /// Dónde tiene el índice un MP4: al principio, al final, o no se pudo ver.
  ///
  /// El índice (`moov`) es la tabla que dice en qué byte está cada segundo de
  /// vídeo y de audio. Puede ir al principio o al final, según con qué programa
  /// se armó el archivo, y la diferencia es enorme al reproducir por internet:
  ///
  ///  - al principio → se lee de entrada y después el archivo va de corrido
  ///  - al final     → para armar cada segundo hay que ir al fondo y volver
  ///
  /// Medido con dos títulos del MISMO servidor y el MISMO host: el de 4,6 GB
  /// con el índice al principio reproduce perfecto, y el de 638 MB con el
  /// índice al final se corta todo el rato — 114 saltos de posición para bajar
  /// menos de 1 MB, mientras el servidor entrega 8-9 MB/s. No es el servidor ni
  /// el tamaño: es cómo quedó armado ese archivo.
  ///
  /// Cuesta UN pedido de 2 KB. Devuelve las TRES respuestas por separado —al
  /// final, al principio, no se pudo ver— y no un sí/no: juntar "está sano" con
  /// "no se pudo mirar" deja el registro diciendo lo mismo en dos situaciones
  /// que no tienen nada que ver, y ahí no se sabe cuál de las dos pasó.
  Future<String> _comoEstaElIndice(
      String url, Map<String, String>? headers) async {
    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {...?headers, 'Range': 'bytes=0-2047'},
          receiveTimeout: const Duration(seconds: 6),
          // 206 es lo esperado; 200 significa que ignoró el rango y mandó el
          // archivo entero, y eso tampoco es un error para lo que hace falta.
          validateStatus: (c) => c != null && c < 400,
        ),
      );
      final datos = res.data;
      if (datos == null || datos.length < 16) {
        return 'no se pudo ver (llegó vacío)';
      }
      final texto = String.fromCharCodes(datos);
      final moov = texto.indexOf('moov');
      final mdat = texto.indexOf('mdat');
      // **No confundir "no lo veo desde acá" con "está roto".**
      //
      // Esta sonda mira solo los primeros 2 KB. Si ahí no aparece `mdat`, antes
      // decía "no parece un MP4" — y eso hizo perder un rato largo con
      // mp4upload, cuyo archivo es un MP4 impecable: empieza con `ftyp`, mide
      // 295 MB y baja a 1 MB/s. Lo único que pasaba es que su `mdat` cae más
      // allá de los 2 KB que se leen.
      //
      // Así que primero se comprueba si es un MP4 —el `ftyp` de los primeros
      // bytes lo dice— y recién después se opina sobre dónde está el índice.
      final esMp4 = texto.indexOf('ftyp') >= 0 && texto.indexOf('ftyp') < 16;
      if (mdat < 0) {
        return esMp4
            ? 'es un MP4, pero el índice no entra en los primeros 2 KB'
            : 'no se pudo ver (no parece un MP4)';
      }
      return moov < 0 || moov > mdat
          ? 'AL FINAL — de los que se cortan'
          : 'al principio — de los que van de corrido';
    } catch (e) {
      return 'no se pudo ver ($e)';
    }
  }

  Future<_ComoAbrir> _comoAbrir(
    String url,
    Map<String, String>? headers,
    bool lecturaContinua,
  ) async {
    // La ficha del servidor, SIEMPRE, aunque no haya nada que hacer. Sirve para
    // revisar extensión por extensión sin cruzar líneas a mano.
    final sinParametros = url.split('?').first.toLowerCase();
    final servidor = currentServerName.value.isEmpty
        ? 'servidor sin nombre'
        : currentServerName.value;
    final donde = Uri.tryParse(url)?.host ?? '?';
    if (!isDirectStream(url) || !sinParametros.endsWith('.m3u8')) {
      logger.info('ficha · $servidor · ${sinParametros.endsWith('.mp4') ? 'MP4 '
              'directo' : 'no es una lista HLS'} · $donde · va directo a mpv, no '
          'hay pedacitos que repartir');
      final entero = !sinParametros.endsWith('.m3u8');
      await _dejarSaltarDentroDelArchivo(entero, url, headers);
      // Este servidor cobra carísimo cada pedido nuevo y la extensión lo
      // declaró: se le lee el archivo de una sola vez. Solo para archivo entero
      // — en una lista de pedacitos cada uno es una dirección distinta y no hay
      // ninguna lectura que sostener.
      if (entero && lecturaContinua) {
        // Con las MISMAS cabeceras con las que habría salido mpv: de acá en
        // adelante la que le pide a la fuente es la bomba, y la fuente no tiene
        // por qué notar el cambio. Sin el User-Agent de navegador, varios CDNs
        // contestan 403.
        final porLaBomba = await BombaDeDatos.registrar(
          url: url,
          cabeceras: {'User-Agent': _browserUA, ...?headers},
        );
        if (porLaBomba != null) {
          _bombaUrl = porLaBomba;
          logger.info('ficha · $servidor · SE LE LEE DE UNA SOLA VEZ · $donde '
              'cobra ~1,5 s por cada pedido nuevo, así que la app le mantiene '
              'la lectura abierta y le sirve al reproductor desde ahí');
          return _ComoAbrir.con(porLaBomba);
        }
        logger.info('ficha · $servidor · no se pudo leer de una sola vez · va '
            'directo a mpv como siempre');
      }
      return const _ComoAbrir.talCual();
    }
    await _dejarSaltarDentroDelArchivo(false, url, headers);

    final hdrs = <String, String>{'User-Agent': _browserUA};
    if (headers != null) hdrs.addAll(headers);
    final reloj = Stopwatch()..start();

    String? maestro;
    try {
      maestro = await _bajarLista(url, hdrs);
    } catch (e) {
      logger.info('ficha · $servidor · no se pudo leer la lista · va directo a '
          'mpv como siempre: $e');
      return const _ComoAbrir.talCual();
    }
    if (maestro == null || !maestro.contains('#EXTM3U')) {
      logger.info('ficha · $servidor · dice .m3u8 pero no lo es · $donde · va '
          'directo a mpv');
      return const _ComoAbrir.talCual();
    }

    var lista = maestro;
    var direccion = url;

    // Las pistas de audio del maestro, para poder ofrecerlas en el menú.
    // Se rehace en cada fuente: son de ESTE vídeo y no del anterior.
    final delMaestro = AudioHls.delMaestro(maestro);
    // Copia propia por el mismo motivo: lo que se le asigna al RxList tiene
    // que ser una lista que se pueda tocar después.
    audiosHls.value = List<PistaDeAudio>.of(delMaestro.pistas);
    audioHlsElegido.value = delMaestro.sonando;

    // ── Con varios idiomas: se abre la variante del idioma que corresponde ──
    //
    // **Y arranca en español**, que es lo que se quiere en estos sitios. El
    // servidor pega el inglés al vídeo —la variante se llama `v1-a2` y el a2 es
    // el inglés—, así que sin esto el episodio empieza en inglés aunque el
    // maestro marque el español como preferido.
    //
    // Se le da a mpv la variante directa y no el maestro. Se probó al revés y
    // no sirve para estos servidores: como cada variante ya trae su audio
    // pegado, ffmpeg usa ese y ni abre las otras pistas, así que el maestro no
    // aporta ni la elección de idioma ni un segundo audio en el menú. Lo único
    // que aportaría es cambiar de calidad, y a cambio se escucha en el idioma
    // equivocado.
    //
    // También se probó rehacer el maestro en un archivo propio apuntando al
    // audio elegido. mpv lo abre y no carga nada: una lista en disco que
    // adentro apunta a internet es para él una "lista insegura". Ni siquiera
    // con `load-unsafe-playlists` arrancó — medido en vivo, entró siempre por
    // el camino de respaldo.
    if (delMaestro.pistas.isNotEmpty) {
      final quiere = AudioHls.preferido(delMaestro.pistas, delMaestro.sonando);
      final variante = _mejorVarianteDe(maestro, Uri.parse(url));
      if (variante != null) {
        final antes = variante.toString();
        final conIdioma = AudioHls.conAudio(antes, quiere.numero);
        // **Solo se dice "español" si de verdad se cambió.**
        //
        // `_conAudio` reescribe el `-aN` de la dirección, y si esa dirección no
        // tiene esa forma devuelve la MISMA sin avisar. Antes se marcaba el
        // idioma preferido igual, así que el selector decía «Español» y se
        // escuchaba inglés — reportado en vivo con Goodstream el 2026-08-06. El
        // menú mintiendo es peor que el idioma equivocado: quien lo ve piensa
        // que ya lo tiene puesto y ni prueba a cambiarlo.
        final seCambio = conIdioma != antes;
        audioHlsElegido.value =
            seCambio ? delMaestro.pistas.indexOf(quiere) : delMaestro.sonando;
        logger.info('ficha · $servidor · idiomas: '
            '${audiosHls.map((a) => '${a.nombre} (a${a.numero})').join(', ')}'
            ' · el vídeo trae a${delMaestro.pistas[delMaestro.sonando].numero}'
            '${seCambio ? ' · se abre en ${quiere.nombre}' : ' · NO se pudo '
                'cambiar de idioma por la dirección (no lleva -aN), se abre en '
                '${delMaestro.pistas[delMaestro.sonando].nombre} y el selector '
                'lo dice'}');
        await _dejarSaltarDentroDelArchivo(false, url, headers);
        return _ComoAbrir.con(conIdioma);
      }
    }

    // Lista maestra: se elige una variante y se sigue.
    if (maestro.contains('#EXT-X-STREAM-INF')) {
      final variante = _mejorVarianteDe(maestro, Uri.parse(url));
      final calidades = RegExp(r'#EXT-X-STREAM-INF').allMatches(maestro).length;
      if (variante == null) {
        logger.info('ficha · $servidor · lista MAESTRA con $calidades '
            'calidad(es) pero ninguna utilizable · va directo a mpv');
        return const _ComoAbrir.talCual();
      }
      try {
        final deLaVariante = await _bajarLista(variante.toString(), hdrs);
        if (deLaVariante == null || !deLaVariante.contains('#EXTM3U')) {
          throw StateError('la variante no devolvió una lista');
        }
        lista = deLaVariante;
        direccion = variante.toString();
        logger.info('ficha · $servidor · lista MAESTRA con $calidades '
            'calidad(es) · $donde · se sigue hasta la variante '
            '(${variante.host}) en ${reloj.elapsedMilliseconds} ms');
      } catch (e) {
        // La variante no contestó. ESTO NO ALCANZA PARA DAR LA FUENTE POR
        // MUERTA, aunque al principio se hizo así para ahorrar los 35 segundos
        // que tarda mpv en rendirse.
        //
        // Costó un vídeo entero: en Pornhub cada calidad es un maestro con una
        // sola variante firmada, y un fallo pasajero en ESE segundo pedido
        // descartaba la fuente completa. El usuario veía "no se encontró ningún
        // embed", salía, volvía a entrar y andaba — el síntoma clásico de algo
        // que se descarta por un tropiezo y no porque esté roto.
        //
        // Además nosotros pedimos con dio y mpv pide con lo suyo: que a dio le
        // vaya mal no prueba que a mpv le vaya a ir mal. Así que se abre igual
        // y se deja que decida el reproductor, que es el que sabe.
        logger.warning('ficha · $servidor · la variante no respondió ($e) · se '
            'abre igual y decide mpv');
        return const _ComoAbrir.talCual();
      }
    }

    final base = Uri.parse(direccion);
    final nodos = <String>{};
    var pedacitos = 0;
    for (final linea in const LineSplitter().convert(lista)) {
      final limpia = linea.trim();
      if (limpia.isEmpty || limpia.startsWith('#')) continue;
      pedacitos++;
      final host = base.resolve(limpia).host;
      if (host.isNotEmpty) nodos.add(host);
    }
    if (nodos.isEmpty) {
      logger
          .info('ficha · $servidor · la lista no traía pedacitos · va directo');
      return const _ComoAbrir.talCual();
    }
    logger.info(
        'ficha · $servidor · lista de $pedacitos pedacitos repartidos en '
        '${nodos.length} nodo(s) · leída en ${reloj.elapsedMilliseconds} ms');

    // Un solo nodo: no hay a quién cambiarle, así que el relay no aportaría nada
    // y solo agregaría un intermediario. Pero si veníamos de un maestro, se le
    // pasa a mpv la variante YA resuelta: es un viaje menos al CDN, y en estos
    // servidores cada viaje se paga en segundos.
    //
    // **Salvo que ese atajo le esconda algo a mpv.** El maestro es el único que
    // declara las pistas alternativas —los `#EXT-X-MEDIA` con los audios y los
    // subtítulos— y la lista de calidades. La variante sola no las trae: es un
    // único flujo, con su audio pegado y nada más.
    //
    // Medido en LaMovie el 2026-08-06: el maestro de vimeos declara DOS audios,
    // «Español» por omisión e «English», y al entregarle la variante el
    // reproductor quedaba con uno solo y sin selector de idioma. Lo mismo con la
    // calidad: dos variantes en el maestro, una sola elegible después.
    //
    // Así que cuando hay algo que elegir se le da el maestro y lo resuelve mpv,
    // que para eso está. El viaje de más se paga una vez; perder el audio en
    // inglés se paga toda la película.
    if (nodos.length < 2) {
      final conVariante = direccion != url;
      final hayPistas = maestro.contains('#EXT-X-MEDIA');
      final variasCalidades =
          RegExp(r'#EXT-X-STREAM-INF').allMatches(maestro).length > 1;
      if (conVariante && (hayPistas || variasCalidades)) {
        final que = <String>[
          if (hayPistas) 'pistas de audio o subtítulos',
          if (variasCalidades) 'varias calidades',
        ].join(' y ');
        logger.info('ficha · $servidor · un solo nodo (${nodos.first}) · se le '
            'pasa el MAESTRO a mpv: trae $que y la variante sola las perdería');
        return const _ComoAbrir.talCual();
      }
      logger.info('ficha · $servidor · un solo nodo (${nodos.first}) · va '
          'directo a mpv${conVariante ? ', con la variante ya resuelta (un '
              'viaje menos al CDN)' : ''}');
      return conVariante
          ? _ComoAbrir.con(direccion)
          : const _ComoAbrir.talCual();
    }

    try {
      final relay = await CastRelayServer.registerAndGetUrl(
        targetUrl: direccion,
        headers: hdrs,
        esquivarNodosCaidos: true,
      );
      logger.info('ficha · $servidor · PASA POR EL RELAY para esquivar nodos '
          'caídos · nodos: ${nodos.join(', ')}');
      return _ComoAbrir.con(relay);
    } catch (e) {
      logger.info('ficha · $servidor · el relay no se pudo levantar · va '
          'directo a mpv: $e');
      return direccion == url
          ? const _ComoAbrir.talCual()
          : _ComoAbrir.con(direccion);
    }
  }

  /// Baja una lista HLS como texto. Tira si no se pudo.
  Future<String?> _bajarLista(String url, Map<String, String> hdrs) async {
    final res = await dio.get<String>(
      url,
      options: Options(
        headers: hdrs,
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 6),
      ),
    );
    return res.data;
  }

  /// La variante que abriría mpv: la mejor que no pase del tope de caudal.
  ///
  /// Se usa el MISMO criterio que `hls-bitrate` para no cambiar qué calidad se
  /// ve: si mpv elegiría la de 6 Mbps, se sigue esa. Si todas superan el tope se
  /// toma la más chica, que es lo más cerca que hay de lo pedido.
  Uri? _mejorVarianteDe(String maestro, Uri base) {
    const tope = 10000000;
    final lineas = const LineSplitter().convert(maestro);
    Uri? mejor;
    var mejorCaudal = -1;
    Uri? masChica;
    var caudalMasChico = -1;
    for (var i = 0; i < lineas.length; i++) {
      if (!lineas[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final caudal = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(lineas[i])?.group(1) ??
                  '') ??
          0;
      for (var j = i + 1; j < lineas.length; j++) {
        final destino = lineas[j].trim();
        if (destino.isEmpty || destino.startsWith('#')) continue;
        final uri = base.resolve(destino);
        if (caudal <= tope && caudal > mejorCaudal) {
          mejorCaudal = caudal;
          mejor = uri;
        }
        if (caudalMasChico < 0 || caudal < caudalMasChico) {
          caudalMasChico = caudal;
          masChica = uri;
        }
        break;
      }
    }
    return mejor ?? masChica;
  }

  void _markNativePlayback(String name) {
    final episodeUrl = playList[index.value].url;
    if (name.isNotEmpty) {
      unawaited(PrismHubStorage.setLastWorkingServer(
        runtime.extension.package,
        episodeUrl,
        name,
      ));
    }
    unawaited(PrismHubStorage.setLastPlaybackMode(
      runtime.extension.package,
      episodeUrl,
      'native',
    ));
  }

  // Si hay un servidor recordado para este episodio, se usa como primario
  // para no re-buscar entre todos. Devuelve true si currentServerName quedó
  // apuntando a un recordado válido (ya sea porque lo acaba de aplicar o
  // porque ya estaba puesto) — con esto play() sabe si puede saltearse la
  // elección manual de servidor y arrancar solo. No exige que sea URL directa
  // — la mayoría de los servidores son embeds que switchServer/runtime.watch
  // sabe resolver perfectamente, no hace falta que ya vengan resueltos acá.
  bool _applyPreferredServer() {
    final saved = PrismHubStorage.getLastWorkingServer(
      runtime.extension.package,
      playList[index.value].url,
    );
    if (saved == null) return false;
    final savedUrl = availableServers[saved];
    if (savedUrl == null) return false;
    if (saved == currentServerName.value) return true;
    logger.info('Usando servidor recordado: $saved');
    currentServerName.value = saved;
    final headers = <String, String>{};
    final ref = serverReferers[saved];
    if (ref != null && ref.isNotEmpty) headers['Referer'] = ref;
    watchData = ExtensionBangumiWatch(
      type: watchData!.type,
      url: savedUrl,
      subtitles: watchData!.subtitles,
      headers: headers.isEmpty ? null : headers,
      audioTrack: watchData!.audioTrack,
    );
    return true;
  }

  // Responde al diálogo "¿Continuar donde te quedaste?" — usuario aceptó.
  //
  // **El salto se pedía y se perdía.** Se llamaba a `seek` en el mismo instante
  // en que el usuario tocaba el botón, y en ese momento mpv puede no conocer
  // todavía la duración del vídeo: sin duración no sabe adónde ir y descarta el
  // pedido sin decir nada. El aviso decía "te quedaste en el minuto tal", uno
  // aceptaba, y el episodio arrancaba de cero.
  //
  // No es nuevo en este archivo: al volver de castear ya estaba anotado que el
  // salto tiene que ir DESPUÉS de que `open()` terminó, que es cuando mpv ya
  // conoce la duración. Faltaba acá.
  //
  // Así que se espera a que la conozca, se salta, y se COMPRUEBA que haya
  // llegado. Si no llegó se reintenta: con HLS el primer salto a veces cae en
  // un pedacito que todavía no se bajó y mpv vuelve solo al principio.
  Future<void> confirmResume(int seconds) async {
    // Cerrando: no se arranca nada. El dialogo de «continuar» puede quedar
    // contestado justo cuando el reproductor ya se esta yendo —se toca
    // «continuar» y se sale— y esto lo hacia reproducir igual, encima del
    // apagado. Ver safePlay.
    if (_disposed) return;
    _isAutoSeekPosition = true;
    resumePrompt.value = null;
    final destino = Duration(seconds: seconds);
    safePlay();
    if (_disposed) return;
    await _saltarCuandoSePueda(destino);
  }

  /// Salta a [destino] en cuanto el reproductor esté en condiciones, y se
  /// asegura de que haya quedado ahí.
  Future<void> _saltarCuandoSePueda(Duration destino) async {
    // Hasta doce segundos esperando la duración. Es de sobra para lo que tarda
    // un HLS en abrir, y si no llegó en ese rato es que algo más está mal: se
    // intenta igual, porque quedarse sin saltar es peor que un salto fallido.
    final reloj = Stopwatch()..start();
    while (!_disposed && reloj.elapsed < const Duration(seconds: 12)) {
      final total = duration.value;
      if (total > Duration.zero && total > destino) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (_disposed) return;

    // Con recorte, «continuar viendo» tampoco puede saltar: se rehace la lista
    // para que empiece en el minuto guardado. Sin esto el episodio arrancaría
    // desde cero justo en la extensión donde el salto no anda.
    //
    // Y va UNA sola vez, fuera del bucle de reintentos de abajo: ese bucle
    // existe porque un salto de mpv en HLS a veces no agarra y hay que
    // repetirlo, pero acá no hay salto que pueda fallar —la lista ya empieza
    // donde tiene que empezar— y cada intento cuesta una reapertura entera
    // (~1,5 s). Reintentar tres veces serían tres reaperturas seguidas.
    final recorteActivo = _recorte;
    if (recorteActivo != null) {
      await _saltarConRecorte(recorteActivo, destino);
      return;
    }

    for (var intento = 1; intento <= 3; intento++) {
      try {
        await player.seek(destino);
      } catch (e) {
        logger.warning('no se pudo saltar a $destino', e);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (_disposed) return;
      final donde = position.value;
      // Diez segundos de margen: mpv salta al punto de corte más cercano, que
      // en HLS es el principio de un pedacito y casi nunca el segundo exacto.
      if ((donde - destino).abs() < const Duration(seconds: 10)) {
        logger.info('continuar viendo: quedó en '
            '${donde.inMinutes}:${(donde.inSeconds % 60).toString().padLeft(2, '0')}');
        return;
      }
      logger.info('continuar viendo: el salto a $destino no agarró '
          '(quedó en $donde), intento $intento de 3');
    }
  }

  // Responde al diálogo "¿Continuar donde te quedaste?" — usuario canceló.
  void cancelResume() {
    // Mismo motivo que confirmResume: contestar el dialogo mientras se sale no
    // puede volver a arrancar el video.
    if (_disposed) return;
    _isAutoSeekPosition = true;
    resumePrompt.value = null;
    // Cancelar no tiene nada que mover: la fuente se abre siempre en el
    // principio, así que quedarse donde está YA es empezar de nuevo.
    //
    // Pero sí hay que BORRAR todo lo que después podría llevarte de vuelta al
    // minuto viejo. Si no, se cancelaba y el reproductor te devolvía ahí igual
    // —visto en vivo: cancelar y terminar en el 19— porque quedaban dos marcas
    // pendientes por otro lado.
    _pendingResumeSeconds = null;
    _midStreamResumeAt = null;
    safePlay();
  }

  // Antes de rendirse con este servidor, reintentar UNA vez pidiendo una
  // resolución nueva (ver comentario en _serverRetryCount) — algunos hosts
  // (confirmado: Streamwish) firman una URL nueva contra un servidor de
  // backend elegido al azar en cada resolución, así que un simple reintento
  // puede caer en uno sano sin que el usuario tenga que hacer nada.
  void _failOrRetryServer(String name) {
    // Antes de reintentar, ¿la extensión sigue estando?
    //
    // Sin esto, una extensión que se cae a mitad de sesión se veía como un
    // servidor que falla: se reintentaba tres veces contra algo que ya no puede
    // contestar, y recién al final salía "probá otro servidor" — un consejo
    // inútil, porque los otros salen de la misma extensión.
    if (_extensionSeCayo()) return;
    if (_serverRetryCount < _maxServerRetries) {
      _serverRetryCount++;
      logger.info(
          'switchServer: $name falló, reintentando ($_serverRetryCount/$_maxServerRetries) con una resolución nueva.');
      unawaited(switchServer(name));
      return;
    }
    _setServerFailed(name);
  }

  // Antes probaba el SIGUIENTE servidor disponible automáticamente cuando
  // uno fallaba — a pedido explícito, esto ya NO pasa: el reproductor debe
  // esperar 100% a que el usuario elija otro servidor a mano (botón
  // Servidor), nunca auto-avanzar sin ninguna interacción. El único
  // reintento automático que queda es _failOrRetryServer probando de nuevo
  // EL MISMO servidor con una resolución nueva (algunos hosts firman contra
  // un backend al azar en cada resolución) — eso no es "cambiar de
  // servidor", es reintentar el mismo.
  void _setServerFailed(String name) {
    _triedAndFailedServers.add(name);
    // Mismo criterio que el fallo del servidor PRIMARIO (play()): si la URL
    // del servidor no es un stream directo, ofrecer el WebView en vez de
    // solo un mensaje de texto sin salida — antes esto SOLO se hacía en el
    // primer intento; cualquier fallo que llegara acá (corte a mitad de
    // reproducción, reintento agotado vía switchServer) dejaba
    // webViewFallback en null para siempre, así que el WebView nunca se
    // abría (confirmado en vivo: "Servidor no disponible" sin ninguna
    // salida real en FuegoCine y otras extensiones de video).
    final url = availableServers[name];
    if (webViewFallback.value == null &&
        url != null &&
        !isDirectStream(url) &&
        !url.startsWith('page://') &&
        !url.startsWith('error://')) {
      // Orden importa: ver comentario en play() sobre por qué el reset va
      // ANTES de asignar webViewFallback.value (ese ever() dispara
      // sincrónico).
      webViewOpenedOnce.value = false;
      webViewFallback.value = {
        'url': url,
        'name': name,
        'referer': serverReferers[name] ?? '',
      };
      // Recordarlo igual que un servidor que sí funcionó nativo — antes
      // esto SOLO pasaba tras un _tryOpenPlayer exitoso, así que un título
      // que solo anda por WebView nunca quedaba guardado como preferido:
      // cada vez que volvías, tocaba elegir servidor de la lista de cero
      // en vez de reintentar directo el mismo que ya sabías que funciona
      // (aunque sea por WebView).
      unawaited(PrismHubStorage.setLastWorkingServer(
        runtime.extension.package,
        playList[index.value].url,
        name,
      ));
    }
    if (webViewFallback.value != null) {
      // Sin "Abriendo..." — ese texto quedaba engañoso una vez que el
      // usuario ya cerró el navegador interno y volvió acá (el botón de
      // abajo es la forma real de volver a abrirlo, no algo automático que
      // ya está pasando).
      serverFailedMessage.value =
          'No se puede reproducir en el reproductor nativo.\n'
          'Podés verlo desde el navegador interno.';
    } else {
      serverFailedMessage.value = availableServers.length > 1
          ? 'Servidor "$name" no disponible.\nElegí otro servidor con el botón Servidor.'
          : 'Servidor "$name" no disponible. Intentá más tarde.';
    }
    logger.info(
        'switchServer: $name falló. ${webViewFallback.value != null ? "Abriendo WebView." : "Esperando a que el usuario elija otro servidor."}');
  }

  // Intenta reproducir directamente una URL que ya es un stream (m3u8/mp4).
  // Usado cuando la extensión no sabe manejar la URL (ej: Desu ya resuelto).
  Future<void> _playDirectFallback(String name, String directUrl) async {
    if (_disposed) return;
    currentServerName.value = name;
    final headers = <String, String>{};
    final referer = serverReferers[name];
    if (referer != null && referer.isNotEmpty) headers['Referer'] = referer;
    if (!await _tryOpenPlayer(directUrl, headers.isEmpty ? null : headers)) {
      if (_disposed) return;
      _failOrRetryServer(name);
    } else {
      if (_disposed) return;
      _serverRetryCount = 0;
      serverFailedMessage.value = '';
      webViewFallback.value = null;
      _lastOpenedServerName = name;
      _markNativePlayback(name);
      if (_pendingResumeSeconds != null) {
        await player.pause();
        // Pausado a proposito para preguntar: la rueda no puede quedar
        // girando detras del dialogo. Ver hasRenderedFrame.
        _marcarQueYaSeVe('pausado a propósito para preguntar');
        resumePrompt.value = _pendingResumeSeconds;
        _pendingResumeSeconds = null;
      }
    }
  }

  // Intenta reproducir un embed que el resolver nativo no pudo resolver, usando
  // el sniffer de WebView oculto: carga la página del host, deja correr su JS y
  // captura el .m3u8/.mp4 que pide su propio player. Es el fallback universal.
  // Retorna true si encontró un stream y media_kit lo abrió.
  Future<bool> _trySniff(
    String name,
    String embedUrl, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_disposed) return false;
    if (embedUrl.startsWith('error://')) return false;
    final low = embedUrl.toLowerCase();
    // Estos hosts no exponen streams HLS/MP4: abren ventanas de descarga, requieren
    // interacción de usuario o cifran el contenido sin URL interceptable.
    if (low.contains('mega.nz') ||
        low.contains('mega.co.nz') ||
        low.contains('savefiles.') ||
        low.contains('mediafire.') ||
        low.contains('1fichier.') ||
        low.contains('zippyshare.') ||
        low.contains('racaty.') ||
        low.contains('katfile.') ||
        low.contains('rapidgator.') ||
        low.contains('nitroflare.')) {
      return false;
    }
    try {
      logger.info(
          'Sniffer WebView → $name: $embedUrl (timeout: ${timeout.inSeconds}s)');
      final referer = serverReferers[name];
      final sniffed = await StreamSnifferService.sniff(
        embedUrl,
        referer: referer,
        timeout: timeout,
      );
      if (_disposed) return false;
      if (sniffed == null) {
        logger.info('Sniffer no encontró stream para $name');
        return false;
      }
      logger.info('Sniffer encontró stream para $name: ${sniffed.url}');
      final headers = {'Referer': sniffed.referer};
      if (!await _tryOpenPlayer(sniffed.url, headers)) {
        if (_disposed) return false;
        logger.info(
            'Sniffer: media_kit rechazado por CDN → $name. Guardando para botón WebView.');
        // Guardar embed URL para botón "Ver en WebView" manual — NO abrir automáticamente.
        // Orden importa: ver comentario en play() sobre por qué el reset va
        // ANTES de asignar webViewFallback.value.
        webViewOpenedOnce.value = false;
        webViewFallback.value = {
          'url': embedUrl,
          'name': name,
          'referer': serverReferers[name] ?? '',
        };
        return false;
      }
      if (_disposed) return false;
      currentServerName.value = name;
      watchData = ExtensionBangumiWatch(
        type: watchData!.type,
        url: sniffed.url,
        subtitles: watchData!.subtitles,
        headers: headers,
        audioTrack: watchData!.audioTrack,
      );
      serverFailedMessage.value = '';
      return true;
    } catch (e) {
      logger.warning('Sniffer excepción en $name: $e');
      return false;
    }
  }

  // Fallback universal de dos etapas:
  // Etapa 1 — extrae embed URLs de la página (window.videos, [data-player], iframe[src])
  //           via callHandler (no crea iframes, que en WebView2 no reciben _hookSource).
  // Etapa 2 — sniffea cada embed en su propio WebView (frame principal → callHandler ok).
  // Si ningún embed funcionó o la página no tenía embeds detectables, intenta un
  // sniff directo de la página (iframes estáticos capturados via postMessage relay).
  bool _pageSniffAttempted = false;
  Future<bool> _trySniffPage() async {
    if (_disposed || _episodePageUrl.isEmpty || _pageSniffAttempted) {
      return false;
    }
    _pageSniffAttempted = true;
    final episodeUrl = playList[index.value].url;
    try {
      // Fast-path: si ya sabemos qué embed funcionó para este episodio, probarlo
      // directo sin escanear toda la página (ahorra ~15s en cargas siguientes).
      final cachedEmbed = PrismHubStorage.getPageSniffEmbed(
        runtime.extension.package,
        episodeUrl,
      );
      if (cachedEmbed != null) {
        logger.info('Page-sniff fast-path: embed cacheado → $cachedEmbed');
        if (await _trySniff('Cached', cachedEmbed)) return true;
        logger.info('Page-sniff fast-path falló, re-escaneando página');
      }

      // Etapa 1: extraer embed URLs de la página del episodio.
      logger.info('Page-sniff etapa 1: extrayendo embeds de $_episodePageUrl');
      final embedUrls = await StreamSnifferService.getEmbedUrls(
        _episodePageUrl,
        timeout: const Duration(seconds: 15),
      );
      if (_disposed) return false;

      if (embedUrls.isNotEmpty) {
        // Etapa 2: sniffear cada embed en WebView propio.
        for (int i = 0; i < embedUrls.length && i < 6; i++) {
          final embedUrl = embedUrls[i];
          logger.info(
              'Page-sniff etapa 2 [${i + 1}/${embedUrls.length}]: $embedUrl');
          if (await _trySniff('Embed ${i + 1}', embedUrl)) {
            // Guardar el embed que funcionó para carga rápida en el próximo intento.
            unawaited(PrismHubStorage.setPageSniffEmbed(
              runtime.extension.package,
              episodeUrl,
              embedUrl,
            ));
            return true;
          }
        }
        logger.info('Page-sniff etapa 2: ningún embed produjo stream');
      } else {
        logger.info('Page-sniff etapa 1: sin embeds, intentando sniff directo');
      }

      if (_disposed) return false;
      // Fallback: sniff directo de la página (iframes estáticos + auto-play).
      final sniffed = await StreamSnifferService.sniff(
        _episodePageUrl,
        timeout: const Duration(seconds: 15),
      );
      if (_disposed) return false;
      if (sniffed == null) {
        logger.info('Page-sniff no encontró stream');
        return false;
      }
      logger.info('Page-sniff encontró stream: ${sniffed.url}');
      final headers = {'Referer': sniffed.referer};
      if (!await _tryOpenPlayer(sniffed.url, headers)) {
        if (_disposed) return false;
        logger.info(
            'Page-sniff: media_kit rechazado. Guardando para botón WebView.');
        // Orden importa: ver comentario en play() sobre por qué el reset va
        // ANTES de asignar webViewFallback.value.
        webViewOpenedOnce.value = false;
        webViewFallback.value = {
          'url': _episodePageUrl,
          'name': 'WebView',
          'referer': '',
        };
        return false;
      }
      if (_disposed) return false;
      currentServerName.value =
          currentServerName.value.isEmpty ? 'Auto' : currentServerName.value;
      watchData = ExtensionBangumiWatch(
        type: watchData!.type,
        url: sniffed.url,
        subtitles: watchData!.subtitles,
        headers: headers,
        audioTrack: watchData!.audioTrack,
      );
      serverFailedMessage.value = '';
      return true;
    } catch (e) {
      logger.warning('Page-sniff excepción: $e');
      return false;
    }
  }

  // Inicializa mpv con una fuente local de video negro (sin red).
  // REQUERIDO antes de que el usuario navegue atrás cuando player.open()
  // nunca fue llamado: sin esto, mpv_render_context_free (video_output_dispose)
  // crashea con SIGSEGV porque el pipeline de render nunca procesó frames.
  Future<void> _safePlayerInit() async {
    if (_disposed) return;
    try {
      // av://lavfi:color genera frames localmente sin red — siempre disponible
      // play:false evita que mpv empiece a reproducir (wakelock=1)
      await player.open(
        Media('av://lavfi:color=black:size=2x2:rate=1'),
        play: false,
      );
      if (_disposed) return;
      // Esperar a que mpv procese el open antes de stop()
      await Future.delayed(const Duration(milliseconds: 300));
      if (_disposed) return;
      await player.stop();
      // Esperar a que el stop complete (estado 'idle') antes de retornar
      // Si retornamos muy rápido y el usuario navega atrás, video_output_dispose
      // puede correr mientras el stop aún está en progreso → crash
      await Future.delayed(const Duration(milliseconds: 500));
      if (_disposed) return;
      logger.info('_safePlayerInit completado');
    } catch (e) {
      logger.severe('_safePlayerInit error: $e');
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        await player.stop();
      } catch (_) {}
    }
  }

  // 播放器相关操作
  playOrPause() async {
    // Red de seguridad: si por lo que sea la pantalla del reproductor sigue
    // viva/tocable después de shutdownPlayback() (ver closeRoute), el Player
    // nativo ya está disposed — llamarlo de nuevo tira una excepción de
    // aserción de media_kit que terminaba matando la app entera.
    if (_disposed) return;
    // Mismo motivo que en safePlay: con el tutorial arriba nada arranca el
    // video, ni siquiera un atajo de teclado que se cuele.
    if (tutorialArriba.value) return;
    // Cargando no se toca. Ver esperandoElPrimerCuadro.
    if (esperandoElPrimerCuadro) {
      logger.info('play/pausa ignorado: el vídeo todavía está cargando');
      return;
    }
    // Con el diálogo de «¿continuar donde ibas?» en pantalla tampoco. Ahí el
    // vídeo está pausado A PROPÓSITO esperando una respuesta, y un toque al
    // botón lo ponía a reproducir desde el principio por debajo del diálogo:
    // el usuario contestaba «continuar» sobre un vídeo que ya había arrancado
    // en otro lado. La única forma de salir de ese estado es contestar.
    if (resumePrompt.value != null) {
      logger.info('play/pausa ignorado: está el diálogo de continuar viendo');
      return;
    }
    // Ni en mitad de un salto con recorte: ahí mpv está cambiando de fuente,
    // y un play/pausa justo en ese instante deja el estado al revés de lo que
    // muestra el botón (se toca «pausa», la fuente nueva arranca reproduciendo
    // por su cuenta, y el icono queda mintiendo). Dura lo que la reapertura.
    if (_saltandoConRecorte.value) {
      logger.info('play/pausa ignorado: hay un salto en curso');
      return;
    }
    if (dlnaDevice.value == null) {
      player.playOrPause();
      return;
    }
    await _pedirAlAparato(reproducir: !isPlaying.value);
  }

  /// Lo ultimo que se le pidio al aparato y todavia no confirmo.
  ///
  /// Null cuando no hay nada en vuelo. Ver [_pedirAlAparato].
  bool? _playPedido;
  Timer? _playPedidoTimer;

  /// Cuanto se espera antes de mandarle la orden al aparato.
  static const _esperaPlayPausa = Duration(milliseconds: 250);

  /// Le pide al aparato que reproduzca o que pause, aguantando el toqueteo.
  ///
  /// Transmitiendo, si el aparato esta reproduciendo solo se sabe por el sondeo
  /// de cada segundo. Con eso, dos toques seguidos al boton mandaban PAUSAR las
  /// dos veces —el segundo se decidia con un estado que todavia era el de antes
  /// del primero— y el video quedaba al reves de lo que mostraba el boton.
  ///
  /// Asi que el boton cambia en el acto y la orden sale una sola vez, con lo
  /// ultimo que se haya pedido. Mientras tanto no se le hace caso a lo que
  /// informa el aparato, que sigue contando lo de antes.
  Future<void> _pedirAlAparato({required bool reproducir}) async {
    final aparato = dlnaDevice.value;
    if (aparato == null) return;
    // El boton responde ya, sin esperar al televisor.
    isPlaying.value = reproducir;
    _playPedido = reproducir;
    _playPedidoTimer?.cancel();
    _playPedidoTimer = Timer(_esperaPlayPausa, () async {
      final quiero = _playPedido;
      if (quiero == null || _disposed || dlnaDevice.value != aparato) return;
      try {
        if (quiero) {
          await aparato.reproducir();
        } else {
          await aparato.pausar();
        }
      } catch (e) {
        // El aparato no contesto o no acepto: se deshace el cambio del boton
        // en vez de dejarlo diciendo algo que no pasa.
        logger.warning('El aparato no acepto reproducir/pausar', e);
        if (_disposed || dlnaDevice.value != aparato) return;
        _playPedido = null;
        isPlaying.value = !reproducir;
        castAviso.value = 'video.cast-failed'.i18n;
        Timer(const Duration(seconds: 3), () {
          if (castAviso.value == 'video.cast-failed'.i18n) {
            castAviso.value = null;
          }
        });
      }
    });
  }

  /// Si lo que informa el aparato ya coincide con lo ultimo que le pedimos.
  ///
  /// Mientras no coincida se ignora: esta contando lo de antes de la orden.
  bool _aceptarReproduciendo(bool informado) {
    final pedido = _playPedido;
    if (pedido == null) return true;
    // Todavia sin mandar: no puede haber cambiado nada.
    if (_playPedidoTimer?.isActive ?? false) return false;
    if (informado != pedido) return false;
    _playPedido = null;
    return true;
  }

  // Wrappers seguros para los botones de play/pause "crudos" de los
  // controles (antes llamaban controller.player.play/.pause DIRECTO, sin
  // pasar por ningún guard) — confirmado en vivo que esos dos botones son
  // los que seguían tirando "[Player] has been disposed" y tumbando la app
  // entera incluso después de que closeRoute() cerrara la pantalla bien.
  void safePlay() {
    if (_disposed) return;
    // Con el tutorial encima el video se queda quieto. El vigilante de
    // VideoPlayerConten ya vuelve a pausar si algo lo arranca, pero eso deja
    // sonar un instante; cortarlo aca evita que llegue a empezar.
    //
    // No frena al propio tutorial: al cerrarse baja esta bandera ANTES de pedir
    // que arranque.
    if (tutorialArriba.value) return;
    // Transmitiendo, quien reproduce es el televisor.
    //
    // Estos dos no lo miraban: tocaban el reproductor de aca, que mientras se
    // transmite esta parado a proposito. O sea que las teclas de medios y los
    // botones que pasan por aca no hacian absolutamente nada al castear.
    if (dlnaDevice.value != null) {
      unawaited(_pedirAlAparato(reproducir: true));
      return;
    }
    try {
      player.play();
    } catch (e) {
      logger.severe('safePlay() error: $e');
    }
  }

  void safePause() {
    if (_disposed) return;
    if (dlnaDevice.value != null) {
      unawaited(_pedirAlAparato(reproducir: false));
      return;
    }
    try {
      player.pause();
    } catch (e) {
      logger.severe('safePause() error: $e');
    }
  }

  seek(Duration destino) async {
    if (_disposed) return;
    // **La barra de progreso, bloqueada mientras carga.**
    //
    // Acá y no en la barra: seek() es el único punto de entrada de la barra, de
    // los atajos de teclado y de los botones de salto, así que cortarlo una vez
    // los cubre todos en las tres plataformas y no hay forma de esquivarlo.
    //
    // Solo mientras se espera el PRIMER cuadro. Un salto durante un parón a
    // mitad de reproducción sí se atiende: ahí el vídeo ya está abierto, y
    // encadenar saltos es justamente lo que se quiere poder hacer cuando algo
    // se traba.
    if (esperandoElPrimerCuadro) {
      logger.info('salto a ${destino.inSeconds}s ignorado: el vídeo todavía '
          'está cargando');
      return;
    }
    // Ni mientras se cambia de servidor. Ahí `hasRenderedFrame` sigue en true
    // —es el cuadro del vídeo ANTERIOR, que todavía se ve— así que la guarda de
    // arriba no alcanza, y la barra seguía aceptando toques.
    //
    // Medido en vivo: tocando la barra durante un cambio a UPNShare, dos saltos
    // se fueron al recorte de zilla (el servidor que se estaba dejando) mientras
    // el nuevo todavía se estaba armando. De ahí el progreso arrancando en cero
    // y el vídeo cargando dos veces.
    if (isGettingWatchData.value) {
      logger.info('salto a ${destino.inSeconds}s ignorado: se está cambiando '
          'de servidor');
      return;
    }
    // Acá y no en cada botón: seek() es el único punto de entrada para la
    // barra de progreso, los atajos de teclado y los saltos, así que marcarlo
    // una vez cubre todos los casos en las tres plataformas.
    markSeeking();

    // Acotado al vídeo: pasarse del final o de cero deja un tiempo que varios
    // aparatos rechazan en vez de ir al extremo.
    final largo = duration.value;
    var donde = destino < Duration.zero ? Duration.zero : destino;
    if (largo > Duration.zero && donde > largo) donde = largo;

    // La barra se mueve YA, sin esperar a que el vídeo llegue.
    //
    // Es lo que hace que tocar el salto varias veces seguidas avance de verdad:
    // el siguiente toque se calcula sobre esta posición. Antes se calculaba
    // sobre la que informaba el reproductor —o el televisor—, que todavía era
    // la vieja, así que cinco toques seguidos saltaban lo mismo que uno.
    _destinoDeSalto = donde;
    position.value = donde;

    // Transmitiendo, la rueda de "esperá que el televisor llegue" se enciende
    // YA y no cuando se manda el salto.
    //
    // Entre soltar la barra y mandar la orden pasan unas decimas, y en ese rato
    // no habia ninguna señal: en el telefono se soltaba la barra y no se notaba
    // si estaba cargando o si se habia colgado. Ahi la imagen la tiene el
    // televisor, asi que sin aviso no hay nada que mirar.
    if (dlnaDevice.value != null) _empezoSaltoEnCast(donde);

    // Y el salto se manda cuando el usuario deja de tocar, una sola vez.
    _juntadorDeSaltos?.cancel();
    // Ojo: NO se suelta _destinoDeSalto al mandarlo. Se suelta cuando el
    // reproductor informe que llego (ver _aceptarPosicion), o cuando salte la
    // red de seguridad de markSeeking si no llega nunca.
    // ── Con recorte, el vídeo se PARA en cuanto se toca ────────────────────
    //
    // Entre el toque y el salto pasan la ventana de agrupación y la reapertura.
    // Con el vídeo corriendo durante todo eso, saltar varias veces seguidas se
    // veía y se oía raro: la escena seguía avanzando mientras la barra ya
    // apuntaba a otro lado.
    //
    // Se recuerda si estaba reproduciendo, porque al terminar el salto hay que
    // dejarlo como estaba: si el usuario había pausado a propósito, saltar no
    // puede ponerlo a reproducir.
    if (_recorte != null && dlnaDevice.value == null) {
      _reproduciaAntesDelSalto = isPlaying.value;
      try {
        player.pause();
      } catch (_) {}
    }

    // Con recorte se espera un poco más antes de mandarlo.
    //
    // Ahí un salto no es instantáneo: cuesta reabrir la fuente y recorrer el
    // resto del pedacito. Con la ventana corta, tocar cinco veces seguidas
    // encolaba cinco saltos de segundos cada uno y el reproductor hacía cosas
    // raras un buen rato. Juntándolos mejor, cinco toques son UN salto al punto
    // final. Sin recorte queda como estaba, que ahí un toque de más no cuesta
    // nada.
    _juntadorDeSaltos = Timer(
        _recorte != null
            ? const Duration(milliseconds: 700)
            : _esperaEntreSaltos, () {
      final adonde = _destinoDeSalto;
      if (adonde == null || _disposed) return;
      unawaited(_mandarSalto(adonde));
    });
  }

  /// Manda el salto ya juntado al que este reproduciendo.
  Future<void> _mandarSalto(Duration duration) async {
    if (_disposed) return;
    if (dlnaDevice.value == null) {
      // En fMP4 no se salta: se rehace la lista para que empiece ahí. Pedirle
      // el salto a mpv en ese formato lo deja clavado — ver RecorteFmp4.
      //
      // Transmitiendo NO se usa: ahí la dirección se la queda el televisor, que
      // salta por su cuenta y no pasa por mpv.
      final recorte = _recorte;
      if (recorte != null) {
        await _saltarConRecorte(recorte, duration);
        return;
      }
      player.seek(duration);
      return;
    }
    // Hay aparatos que no saben ir a un punto exacto (el mando de Roku
    // adelanta a saltos y nada mas). Se dice, en vez de mandar la orden y
    // dejar la rueda girando esperando algo que no va a pasar.
    // Video reempaquetado: el televisor no puede saltar dentro de un flujo que
    // se va armando sobre la marcha, asi que se le rearma desde el pedacito que
    // corresponde. El mando sigue siendo este aparato.
    if (_planTs != null) {
      await _saltarEnCastTs(duration);
      return;
    }
    if (!dlnaDevice.value!.permiteSaltar) {
      castAviso.value = 'video.cast-no-seek'.i18n;
      Timer(const Duration(milliseconds: 2000), () {
        if (castAviso.value == 'video.cast-no-seek'.i18n)
          castAviso.value = null;
      });
      return;
    }
    // El aparato tarda en llegar y deja la imagen congelada mientras tanto: se
    // avisa antes de mandarlo, no despues.
    _empezoSaltoEnCast(duration);
    // Salto ABSOLUTO y no relativo: antes se calculaba la diferencia contra la
    // posicion conocida y se mandaba eso, asi que una posicion desactualizada
    // dejaba el salto en cualquier lado.
    await dlnaDevice.value!.irA(duration);
  }

  /// Techo de resolucion a partir del cual se sospecha del televisor.
  ///
  /// 1080p es lo que reproduce practicamente cualquier aparato con DLNA; de ahi
  /// para arriba es donde empiezan a quedarse cortos.
  static const _techoParaTelevisor = 1080;

  /// Cuantos pixeles de alto es una calidad, por su nombre.
  ///
  /// Los nombres vienen de dos lados —del playlist maestro de un HLS y de la
  /// cabecera que manda la extension— y no siempre traen el numero: "4K" y
  /// "2K" son igual de comunes que "2160p".
  static int _alturaDeNombre(String nombre) {
    final n = nombre.toLowerCase();
    final conNumero = RegExp(r'(\d{3,4})\s*p\b').firstMatch(n);
    if (conNumero != null) return int.tryParse(conNumero.group(1)!) ?? 0;
    if (RegExp(r'\b8k\b').hasMatch(n)) return 4320;
    if (RegExp(r'\b4k\b').hasMatch(n)) return 2160;
    if (RegExp(r'\b2k\b').hasMatch(n)) return 1440;
    return 0;
  }

  /// El televisor bajo el video y no pudo: si esta en 4K o 2K, se baja la
  /// calidad y se dice por que.
  ///
  /// Un televisor publica los FORMATOS que acepta pero no hasta que RESOLUCION
  /// llega, asi que esto no se puede preguntar antes — solo se puede deducir
  /// cuando ya fallo. Y el sintoma es inconfundible: bajo los datos (por eso
  /// llegamos hasta aca) y aun asi no dibuja nada.
  ///
  /// Devuelve true si encontro una calidad mas baja y la puso. En ese caso no
  /// se muestra el aviso generico: se muestra este, que dice lo que pasa de
  /// verdad y que ya se esta arreglando solo.
  bool _bajarCalidadParaElTelevisor() {
    // Las calidades vienen de dos lados segun la extension. Ver hayCalidades.
    final opciones = <String, String>{
      if (qualityMap.isNotEmpty) ...qualityMap,
      if (_servidoresSonCalidades) ...availableServers,
    };
    if (opciones.length < 2) return false;

    final actual = _servidoresSonCalidades && currentServerName.value.isNotEmpty
        ? currentServerName.value
        : opciones.entries
            .firstWhere((e) => e.value == watchData?.url,
                orElse: () => const MapEntry('', ''))
            .key;
    final alturaActual = _alturaDeNombre(actual);
    if (alturaActual <= _techoParaTelevisor) return false;

    // La mejor que el televisor tenga chance de aguantar.
    final candidatas = opciones.entries.where((e) {
      final h = _alturaDeNombre(e.key);
      return h > 0 && h <= _techoParaTelevisor;
    }).toList()
      ..sort(
          (a, b) => _alturaDeNombre(b.key).compareTo(_alturaDeNombre(a.key)));
    if (candidatas.isEmpty) return false;
    final elegida = candidatas.first;

    logger.info('El televisor no pudo con $actual: se baja a ${elegida.key}');
    castAviso.value = 'video.cast-resolucion'
        .i18n
        .replaceAll('%s', actual)
        .replaceAll('%t', elegida.key);
    // switchQuality ya sabe que casteando la calidad nueva va al TELEVISOR y
    // no al reproductor de aca.
    unawaited(_servidoresSonCalidades
        ? switchServer(elegida.key)
        : switchQuality(elegida.value));
    return true;
  }

  /// Adelanta en una transmision reempaquetada a MPEG-TS.
  ///
  /// El televisor esta recibiendo un flujo sin largo conocido, asi que pedirle
  /// que salte no sirve de nada. Lo que se hace es armarle **otro flujo** que
  /// empieza en el pedacito donde cae ese momento y mandarselo como si fuera un
  /// video nuevo. Para el usuario es lo mismo: toca la barra y el televisor
  /// sigue desde ahi.
  ///
  /// Se puede porque la lista dice cuanto dura cada pedacito, asi que se sabe
  /// en cual cae cualquier minuto del episodio (ver PlanTs.indiceDe).
  Future<void> _saltarEnCastTs(Duration donde) async {
    final plan = _planTs;
    final aparato = dlnaDevice.value;
    if (plan == null || aparato == null) return;

    final indice = plan.indiceDe(donde);
    final recortado = plan.recortadoDesde(indice);
    // El salto cae en el principio del pedacito, no en el segundo exacto: es
    // donde el flujo puede empezar a decodificarse. Se informa ESE, para que la
    // barra no diga un numero y el televisor este en otro.
    _empezoSaltoEnCast(recortado.inicio);
    // Y se corrige adonde se espera llegar, que es lo que compara
    // _aceptarPosicion: si quedara el segundo exacto que se pidio, la posicion
    // real nunca caeria dentro del margen y la barra se quedaria clavada.
    _destinoDeSalto = recortado.inicio;

    final viejo = _dlnaRelayUrl;
    try {
      final url = await CastRelayServer.registerAndGetUrl(
        targetUrl: plan.pedacitos[indice].toString(),
        headers: plan.headers,
        planTs: recortado,
      );
      await aparato.cargar(
        url: url,
        titulo: '$title — ${playList[index.value].name}',
        mime: 'video/mpeg',
        // Acá SIEMPRE es reempaquetado (por eso el mime fijo), así que nunca se
        // puede saltar por bytes. Ver el mismo comentario en connectDLNADevice.
        puedeSaltar: false,
      );
      _dlnaRelayUrl = url;
      _urlEnviadaAlCast = url;
      _desfaseTs = recortado.inicio;
      position.value = recortado.inicio;
      // El anterior recien aca: si algo de lo de arriba fallara, soltarlo antes
      // habria dejado la transmision cortada Y sin forma de volver.
      if (viejo != null && viejo != url) CastRelayServer.unregister(viejo);
      // La cuenta del vigilante arranca de nuevo: para el es un video distinto
      // y las lecturas del anterior no valen.
      _vioReproduciendoEnCast = false;
      _lecturasParadoSeguidas = 0;
      _desajustesSeguidos = 0;
    } catch (e) {
      logger.warning('No se pudo adelantar en el televisor', e);
      castBuscando.value = false;
      castAviso.value = 'video.cast-no-seek'.i18n;
      Timer(const Duration(milliseconds: 2000), () {
        if (castAviso.value == 'video.cast-no-seek'.i18n)
          castAviso.value = null;
      });
    }
  }

  // Devuelve barras de sistema y rotación al estado normal. Es idempotente a
  // propósito: se llama tanto desde onClose (destrucción del controller) como
  // desde closeRoute (salida explícita del usuario). Antes solo estaba en
  // onClose, y si por lo que sea ese no llegaba a correr, el celular quedaba
  // trabado en horizontal para TODA la app hasta reiniciarla — reportado en
  // vivo. Llamarlo dos veces no molesta; no llamarlo nunca sí.
  Future<void> restoreSystemUiOnExit() async {
    if (!Platform.isAndroid) return;
    // El botón manual no puede sobrevivir al reproductor: si quedara en true,
    // la próxima vez que se abra otro vídeo arrancaría en pantalla completa sin
    // que nadie lo haya tocado.
    pantallaCompletaAndroid.value = false;
    // manual + overlays completos (no edgeToEdge): confirmado en vivo que
    // volver a edgeToEdge al salir dejaba la hora/batería "comidas" por el
    // SafeArea de la página de destino — MediaQuery no llegaba a refrescar el
    // padding superior a tiempo tras el cambio de modo, así que el contenido
    // se dibujaba encima de donde iría el status bar. Pedir manual con TODOS
    // los overlays fuerza que ambas barras vuelvan a mostrarse reservando su
    // espacio, sin depender de ese timing.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    // Y los colores, por lo mismo que en _barrasDelSistemaVisibles: pedir el
    // modo reinicia el estilo, así que salir del reproductor dejaba la app con
    // los iconos del sistema en claro — invisibles con el modo claro puesto.
    ModoDeColor.aplicarBarrasDelSistema();
    // ── Se vuelve a pedir, más tarde ──────────────────────────────────────
    //
    // Reportado en vivo: al volver de un episodio, la barra flotante de
    // Inicio/Buscar/etc quedaba tapada por la barra de navegación del
    // teléfono —como si no supiera cuánto mide—, y se acomodaba sola apenas
    // se mandaba el app a segundo plano y se volvía (sin reiniciarla). Eso
    // encaja con MediaQuery quedándose con el relleno inferior viejo un
    // rato después de este cambio de modo, igual que ya pasaba con el
    // superior (ver el comentario de arriba) — y sin edgeToEdge de por
    // medio para poder evitarlo del todo esta vez, porque el pedido ya es
    // `manual`. Repetirlo una vez que la transición de salida terminó de
    // asentarse le da a Android una segunda oportunidad de entregar el
    // relleno real; no cuesta nada si ya estaba bien.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!Platform.isAndroid) return;
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      ModoDeColor.aplicarBarrasDelSistema();
    });
    // 如果是平板则不改变
    // Libera el bloqueo nativo que dejó landscapeAutoMode(forceSensor: true)
    // en onInit — pedir portraitUp/portraitDown acá bloqueaba la rotación
    // libre para siempre (hasta reiniciar la app), porque nada más en la app
    // vuelve a pedir "todas las orientaciones". fullAutoMode restaura la
    // auto-rotación real según el sensor/config del sistema.
    // esTablet y no el isTablet de antes: aquel se calculaba una vez y se
    // guardaba, y acá el app SIEMPRE está acostado — si esta era la primera
    // pantalla en preguntar, un teléfono quedaba marcado como tablet y este
    // bloque no corría nunca. O sea que salir del reproductor dejaba la app
    // trabada en horizontal hasta reiniciarla.
    if (!LayoutUtils.esTablet) {
      await AutoOrientation.fullAutoMode();
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  /// Enciende o apaga el modo inmersivo según cómo esté el teléfono.
  ///
  /// Acostado se esconden las barras del sistema: el vídeo ocupa la pantalla y
  /// nada más importa. De pie NO: ahí el vídeo es una franja arriba y debajo
  /// queda la app, así que esconder la barra de navegación deja al usuario sin
  /// forma de salir salvo el gesto, y la de estado hace falta para ver la hora
  /// y la batería mientras se mira algo largo.
  ///
  /// La llama la página cada vez que cambia la orientación. Es idempotente: si
  /// ya está en el modo que corresponde, pedirlo de nuevo no cuesta nada.
  void pantallaSegunOrientacion({required bool acostado}) {
    if (!Platform.isAndroid) return;
    _acostadoActual = acostado;
    // Reportado en vivo: girar el teléfono adentro del reproductor abría el
    // teclado en pantalla solo, sin que nadie tocara ningún campo de texto.
    // Acá no hay ningún TextField —los controles del reproductor son solo
    // botones y sliders— así que no debería haber nada que lo pida nunca.
    // El sospechoso es el propio cambio de SystemUiMode de acá abajo: en
    // algunos aparatos, tocar el WindowInsetsController para las barras del
    // sistema arrastra consigo el estado del teclado. Se lo esconde a
    // mano en cada llamada —no cuesta nada si ya estaba escondido— en vez
    // de intentar adivinar en qué aparato puntual pasa.
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    // El botón manual de pantalla completa manda por encima de la orientación:
    // sin esto, la página llama a este método en cada rebuild (ver
    // `_androidSegunOrientacion`) y le pisaba el modo inmersivo apenas volvía a
    // dibujarse un cuadro.
    if (pantallaCompletaAndroid.value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }
    // ── Las barras del sistema NO se esconden nunca ─────────────────────────
    //
    // Acostado se pedía modo inmersivo: el vídeo ocupaba todo y desaparecían la
    // hora, la batería y la barra de navegación. A pedido, eso ya no se hace en
    // ninguna orientación — las dos barras se quedan siempre, en el reproductor
    // y fuera de él.
    //
    // No es solo estética. Escondidas, la única salida visible era la flecha
    // del propio reproductor, y por eso esa flecha tenía que quedarse fija
    // encima del vídeo todo el tiempo. Con las barras puestas, el gesto de
    // atrás siempre está disponible, y recién ahí la flecha puede desvanecerse
    // con el resto de los controles — que es lo que se pidió junto con esto.
    // Las dos cosas van juntas: una sin la otra deja la pantalla sin salida.
    //
    // El `if (acostado)` queda por si algún día vuelve a hacer falta
    // diferenciar, pero hoy las dos ramas piden lo mismo.
    if (acostado) {
      _barrasDelSistemaVisibles();
      return;
    }
    // ── De pie CON "llenar pantalla": el vídeo pinta hasta la cámara ──────
    //
    // Pedido a propósito, sabiendo el riesgo: `edgeToEdge` es lo que se sacó
    // en su momento porque el vídeo tapaba la hora y la batería (ver el
    // comentario de la rama de abajo). Acá se vuelve a pedir, pero SOLO
    // mientras "llenar pantalla" está prendido — es una decisión explícita
    // de quien la activa, no el comportamiento por defecto. Apagar el
    // interruptor, cambiar a acostado o salir del reproductor vuelven todos
    // al modo de siempre (ver el worker de llenarPantalla en onInit y
    // restoreSystemUiOnExit), así que el riesgo viejo queda acotado a este
    // interruptor puntual.
    if (llenarPantalla.value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // El cambio de modo reinicia el estilo de las barras — mismo motivo
      // que en _barrasDelSistemaVisibles, con los iconos fijos en claros
      // (ver _iconosDelSistemaParaVideo) y no según el modo de la app.
      _iconosDelSistemaParaVideo();
      return;
    }
    // ── De pie: `manual` con las dos barras, NO `edgeToEdge` ──────────────
    //
    // Con edgeToEdge las barras se ven pero el contenido se dibuja DEBAJO, así
    // que la hora y la batería quedaban tapadas por el vídeo. Y peor: si esta
    // era la última orden antes de salir, la app entera se quedaba así y no se
    // veía la hora ni después de cerrar el reproductor. Reportado en vivo.
    //
    // `manual` con todos los overlays es lo que ya pide el resto de la app al
    // salir del reproductor (ver la restauración más abajo): fuerza que las dos
    // barras vuelvan RESERVANDO su espacio, sin depender de que el MediaQuery
    // alcance a refrescar el relleno superior a tiempo.
    _barrasDelSistemaVisibles();
  }

  /// Las dos barras del sistema, visibles y RESERVANDO su espacio.
  ///
  /// `manual` con todos los overlays, y no `edgeToEdge`: con edgeToEdge las
  /// barras se ven pero el contenido se dibuja DEBAJO, así que la hora y la
  /// batería quedaban tapadas por el vídeo. Y peor: si esa era la última orden
  /// antes de salir, la app entera quedaba así y no se veía la hora ni después
  /// de cerrar el reproductor. Reportado en vivo.
  ///
  /// Es lo mismo que pide el resto de la app al salir del reproductor, ahora en
  /// un solo lugar para que no se puedan separar.
  static void _barrasDelSistemaVisibles() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    // ── Y SUS COLORES, que el cambio de modo se lleva puestos ──────────────
    //
    // `setEnabledSystemUIMode` reinicia el estilo de las barras a los valores
    // por defecto de Android, que son iconos CLAROS.
    //
    // Pedir el modo y no volver a pedir el estilo era el agujero: son dos
    // cosas separadas y la primera pisa a la segunda.
    _iconosDelSistemaParaVideo();
  }

  /// Los iconos del sistema, siempre CLAROS mientras se está en el
  /// reproductor — no según el modo claro/oscuro de la app
  /// (ModoDeColor.aplicarBarrasDelSistema, que usa el resto de la app).
  ///
  /// Ese otro tiene sentido en una pantalla con un fondo fijo: elige iconos
  /// oscuros si el fondo de la app es claro. Acá el fondo real es el VIDEO,
  /// que no tiene nada que ver con si la app está en modo claro u oscuro —
  /// con modo claro puesto y una escena oscura (lo más común), los iconos
  /// oscuros que elegiría el otro quedaban invisibles contra el video.
  /// Reportado en vivo. Claros siempre es lo seguro acá, y es lo mismo que
  /// hace cualquier reproductor de video conocido.
  static void _iconosDelSistemaParaVideo() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void onClose() async {
    WidgetsBinding.instance.removeObserver(this);
    _beginPlaybackShutdown();
    if (PrismHubStorage.getSetting(SettingKey.autoTracking) == true &&
        anilistID != "") {
      AniListProvider.editList(
        status: AnilistMediaListStatus.current,
        progress: playIndex + 1,
        mediaId: anilistID,
      );
    }
    await restoreSystemUiOnExit();
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
    // Las listas recortadas que quedaron en la carpeta temporal. Son unos KB,
    // pero se acumularían una por salto y por episodio.
    final recorte = _recorte;
    _recorte = null;
    if (recorte != null) unawaited(recorte.limpiar());
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
    // El corte de la transmision (parar el aparato, soltar el relay, cortar el
    // timer de estado) ya lo hizo _beginPlaybackShutdown() al principio de este
    // metodo, y ahi tambien quedo anotado por donde iba el televisor para que
    // shutdownPlayback lo guarde en el historial.
    await shutdownPlayback();
    logger.info('dispose video controller');
    super.onClose();
  }
}

class Message {
  final Widget child;
  final Duration time;
  Message(this.child, {this.time = const Duration(seconds: 3)});
}

// Una variante de calidad del stream, mientras se arma el menú.
class _VarianteCalidad {
  const _VarianteCalidad(this.url, this.bitrate, this.orden);

  final String url;
  final int bitrate;
  // Para ordenar de mayor a menor: manda la altura y el caudal desempata.
  final int orden;
}

/// Cómo se llama una calidad en el menú: "4K", "1440p", "1080p"…
///
/// Antes se mostraba la resolución cruda ("1920x1080"). Es exacta pero no es
/// como la gente pide una calidad, y con números grandes ("3840x2160") cuesta
/// más reconocer de un vistazo que eso es el 4K.
///
/// Se nombra por la ALTURA, que es la convención de todos lados. La resolución
/// completa se sigue mostrando al lado cuando no es una de las conocidas: hay
/// recortes panorámicos donde la altura sola engaña.
String etiquetaCalidad(int? width, int? height) {
  if (height == null || height <= 0) return '';
  if (height >= 4320) return '8K';
  if (height >= 2160) return '4K';
  if (height >= 1440) return '1440p';
  if (height >= 1080) return '1080p';
  if (height >= 720) return '720p';
  if (height >= 480) return '480p';
  if (height >= 360) return '360p';
  return '${height}p';
}

/// Cómo abrir una fuente, decidido antes de tocar el reproductor.
///
/// Dos resultados: tal cual, o por esta otra dirección. Hubo un tercero —"ni lo
/// intentes"— para descartar rápido lo que no iba a andar, y se sacó: descartar
/// por nuestra cuenta le quitaba al usuario vídeos que sí funcionaban. Quien
/// dice si una fuente sirve es el reproductor. Ver _comoAbrir.
class _ComoAbrir {
  const _ComoAbrir.talCual() : url = null;
  const _ComoAbrir.con(this.url);

  /// Dirección a abrir. Null = la original.
  final String? url;
}

/// Un idioma de audio de los que ofrece una lista maestra de HLS.
