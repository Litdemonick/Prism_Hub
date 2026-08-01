// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_orientation/auto_orientation.dart';
import 'package:dio/dio.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
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
import 'package:prismhub/utils/cast_relay_server.dart';
import 'package:prismhub/utils/watch_state.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/data/services/stream_sniffer_service.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart'
    show isDirectStream;
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:crypto/crypto.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
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
    LogicalKeyboardKey.mediaPlay: () => player.play(),
    LogicalKeyboardKey.mediaPause: () => player.pause(),
    LogicalKeyboardKey.mediaPlayPause: () => player.playOrPause(),
    LogicalKeyboardKey.mediaTrackNext: () => player.next(),
    LogicalKeyboardKey.mediaTrackPrevious: () => player.previous(),
    LogicalKeyboardKey.space: () => player.playOrPause(),
    LogicalKeyboardKey.keyJ: () {
      final rate = player.state.position +
          Duration(
            milliseconds:
                (PrismHubStorage.getSetting(SettingKey.keyJ) * 1000).toInt(),
          );
      _seekFromShortcut(rate);
    },
    LogicalKeyboardKey.keyI: () {
      final rate = player.state.position +
          Duration(
              milliseconds:
                  (PrismHubStorage.getSetting(SettingKey.keyI) * 1000).toInt());
      _seekFromShortcut(rate);
    },
    LogicalKeyboardKey.arrowLeft: () {
      final rate = player.state.position +
          Duration(
              milliseconds:
                  (PrismHubStorage.getSetting(SettingKey.arrowLeft) * 1000)
                      .toInt());
      _seekFromShortcut(rate);
    },
    LogicalKeyboardKey.arrowRight: () {
      final rate = player.state.position +
          Duration(
              milliseconds:
                  (PrismHubStorage.getSetting(SettingKey.arrowRight) * 1000)
                      .toInt());
      _seekFromShortcut(rate);
    },
    // El tope era 100, o sea el volumen original: con una pista grabada baja no
    // quedaba nada por hacer. Ahora llega hasta volumenMaximo.
    LogicalKeyboardKey.arrowUp: () {
      final volume = player.state.volume + 5.0;
      player.setVolume(volume.clamp(0.0, volumenMaximo));
    },
    LogicalKeyboardKey.arrowDown: () {
      final volume = player.state.volume - 5.0;
      player.setVolume(volume.clamp(0.0, volumenMaximo));
    },
  };

  // 字幕
  final subtitles = <SubtitleTrack>[].obs;

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
  final currentServerName = ''.obs;
  final serverFailedMessage = ''.obs;
  // false entre "el servidor abrió" y "ya se ve el primer frame real" — media
  //_kit puede tardar un rato en pintar el primer cuadro aunque duration/
  // videoParams ya hayan llegado (streaming HLS: el buffering inicial pasa
  // SIN el flag de buffering en true, así que sin esto la pantalla quedaba
  // en negro sin ningún spinner, como si estuviera trabada de verdad).
  final hasRenderedFrame = false.obs;
  // Flag de buffering YA corregido con la posición real — ver
  // player.stream.buffering.listen más abajo. El flag crudo de mpv
  // (paused-for-cache) confirmado en vivo que a veces queda pegado en true
  // para siempre (el evento de "ya terminó de bufferizar" no siempre llega
  // por la plataforma), aunque el video ya esté reproduciendo frames nuevos
  // — eso hacía que el spinner de carga siguiera girando después de que el
  // contenido ya cargó. Si la posición avanzó hace poco, no puede estar
  // bufferizando de verdad, sin importar lo que diga el flag crudo.
  final isActuallyBuffering = false.obs;

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

  void markSeeking() {
    isSeeking.value = true;
    _positionAfterSeek = null;
    _seekWatchdog?.cancel();
    // Red de seguridad: si el servidor no responde nunca, la rueda no se
    // queda girando para siempre.
    _seekWatchdog = Timer(const Duration(seconds: 8), () {
      isSeeking.value = false;
    });
  }

  // Los atajos de teclado llamaban a player.seek() DIRECTO, salteándose la
  // marca de búsqueda que sí hace seek(): con las teclas y las flechas la
  // imagen se congelaba sin ninguna rueda, aunque con la barra de progreso
  // funcionara. Todos pasan por acá.
  void _seekFromShortcut(Duration to) {
    final salto = (to - player.state.position).inSeconds;
    markSeeking();
    _anunciarSalto(salto);
    player.seek(to);
  }

  // Cuántos segundos saltó el último atajo, para mostrarlo en pantalla. Vive
  // en el controller y no en la vista porque el salto se dispara desde acá
  // (los atajos de teclado son del controller) y así la misma señal sirve en
  // escritorio y en celular.
  final lastSkipSeconds = Rx<int?>(null);
  Timer? _skipBadgeTimer;

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
  final dlnaDevice = Rx<DLNADevice?>(null);

  // 定时器
  Timer? _dlnaTimer;
  final List<Worker> _workers = [];
  final List<StreamSubscription> _subscriptions = [];

  // URL de relay activa (si el stream necesitó headers) — se limpia del
  // servidor local al desconectar, ver disconnectDLNADevice().
  String? _dlnaRelayUrl;

  @override
  void onInit() async {
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      // 切换到横屏
      SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await AutoOrientation.landscapeAutoMode(forceSensor: true);
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
        await np.setProperty(
            'demuxer-lavf-o', 'reconnect=0,reconnect_delay_max=0');
      } else {
        await np.setProperty('hwdec', 'auto-safe');
        await np.setProperty('network-timeout', '20');
        await np.setProperty('demuxer-lavf-o',
            'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
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
      // UA de navegador: CDNs de anime (luluvdo, streamwish, etc.) bloquean
      // el UA por defecto de mpv ("Lavf/xx.xx"). Usar el mismo UA que el app.
      final ua = PrismHubStorage.getUASetting();
      if (ua != null && ua.isNotEmpty) {
        await np.setProperty('user-agent', ua);
      }
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
      await np.setProperty('cache-secs', '30');
      await np.setProperty(
          'demuxer-max-bytes', Platform.isAndroid ? '96MiB' : '192MiB');
      await np.setProperty('demuxer-readahead-secs', '10');
      // La variante de MAYOR calidad de las que ofrece el stream — o sea que
      // cuando hay 4K, se usa 4K. La lista de calidades del menú sale de las
      // variantes del propio playlist, sin tope puesto por la app, así que
      // aparece cualquier resolución que el sitio publique.
      await np.setProperty('hls-bitrate', 'max');
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
    _addWorker(ever(index, (callback) {
      play();
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

    // 自动切换下一集
    _addSubscription(player.stream.completed.listen((event) {
      if (!event || playMode.value == PlaylistMode.single) {
        return;
      }
      if (playMode.value == PlaylistMode.loop) {
        player.seek(Duration.zero);
        player.play();
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

    // Primer cuadro real pintado — recién acá se apaga el spinner de carga
    // del centro (ver comentario en hasRenderedFrame).
    _addSubscription(player.stream.videoParams.listen((p) {
      if ((p.w ?? 0) > 0 && (p.h ?? 0) > 0) hasRenderedFrame.value = true;
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
        _isAutoSeekPosition = true;
        player.seek(Duration(seconds: int.tryParse(history.progress) ?? 0));
        sendMessage(Message(Text('video.resume-last-playback'.i18n)));
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
      duration.value = event;
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

    // 监听进度
    _addSubscription(player.stream.position.listen((event) {
      if (dlnaDevice.value != null) {
        return;
      }
      position.value = event;
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

    // Vigía de buffering atascado — ver comentario en _bufferingStallTimer.
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
      if (buffering) {
        // Confirmado en vivo (Voe/voe.sx, cloudwindow-route): el buffering
        // inicial puede tardar más de 20s y aun así terminar arrancando
        // sano — subido a 35s para darle el mismo margen que
        // _tryOpenPlayer. Ahora que un fallo pasa automáticamente al
        // siguiente servidor (ver _setServerFailed), esperar un poco más
        // acá antes de rendirse sale más barato que antes.
        _bufferingStallTimer = Timer(const Duration(seconds: 35), () {
          // Si el usuario pausó (a propósito o justo cuando empezó a
          // bufferizar) esto NO es un servidor trabado — pausado no
          // necesita seguir cargando nada, así que no hay "atasco" real
          // que declarar. Sin este chequeo, dejar el video en pausa un
          // rato largo terminaba mostrando "servidor no disponible" solo.
          if (!player.state.playing) return;
          if (serverFailedMessage.value.isEmpty) {
            logger.severe(
                'Buffering atascado 35s+ en "${currentServerName.value}" — tratando como servidor caído.');
            final stuckName = currentServerName.value;
            if (stuckName.isNotEmpty) {
              // Si ya se había pintado un cuadro antes de trabarse, es un
              // corte a mitad de capítulo — recuperar en la misma posición
              // en vez de reiniciar desde 0 (ver _midStreamResumeAt).
              if (hasRenderedFrame.value) {
                _midStreamResumeAt = position.value;
              }
              _failOrRetryServer(stuckName);
            } else {
              serverFailedMessage.value =
                  'Se quedó cargando. Elegí otro servidor.';
            }
          }
        });
      }
    }));

    // 错误监听 — detectar fallo de reproducción
    _addSubscription(player.stream.error.listen((event) {
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
    // No arrastrar el "avanzó hace poco" del video/servidor ANTERIOR — sin
    // esto, un corte real justo al cambiar de contenido podía quedar sin
    // spinner un instante porque todavía valía el timestamp viejo.
    _lastPositionAdvanceAt = null;
    _lastPositionSeen = null;
    _lastHistoryTouchAt = null;
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
          await dlnaDevice.value!.setUrl(watchData!.url);
          if (_disposed) return;
          await dlnaDevice.value!.play();
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
  getWatchData() async {
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
      // Servidor actual
      currentServerName.value = headers['X-Primary-Server'] ??
          (availableServers.isNotEmpty ? availableServers.keys.first : '');
      // URL de la página del episodio para el page-sniff (fallback universal).
      _episodePageUrl = headers['X-Page-Url'] ?? '';
      // Limpiar cabeceras especiales — no enviar al player
      watchData!.headers = Map.from(headers)
        ..remove('X-Servers')
        ..remove('X-Server-Referers')
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
  bool _disposed = false;
  bool get disposed => _disposed;
  final Completer<void> _shutdownCompleter = Completer<void>();
  Future<void>? _shutdownFuture;
  bool _playerDisposed = false;
  bool _shutdownStarted = false;
  bool _routeClosing = false;

  bool _isPlaybackClosed([int? generation]) =>
      _disposed || (generation != null && generation != _switchServerGen);

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
    ++_switchServerGen;
    _disposed = true;
    isVideoSurfaceMounted.value = false;
    isWebViewActive.value = false;
    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }
    _dlnaTimer?.cancel();
    _bufferingStallTimer?.cancel();
    _qualitySwitchTimer?.cancel();
    final device = dlnaDevice.value;
    dlnaDevice.value = null;
    if (device != null) {
      try {
        device.stop();
      } catch (_) {}
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
    final frame = saveHistory ? await _capturarFrameActual() : null;

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
    // Callar el audio va PRIMERO, y los dos intentos en paralelo.
    //
    // Antes iba encadenado: bajar el volumen y, recién cuando ESO terminaba,
    // pausar. Con el tope de 2 s de cada paso, si el primero se colgaba —que es
    // justo lo que hace el bug de hilos de arriba— había que esperarlo entero
    // antes de siquiera intentar el segundo: hasta cuatro segundos de audio
    // sonando con el reproductor ya cerrado y la pantalla anterior a la vista.
    // Reportado en vivo como "tarda 3-5 segundos en callarse".
    //
    // En paralelo alcanza con que UNO de los dos llegue para que deje de sonar,
    // y el que se cuelgue ya no demora al otro. En el caso normal, donde ninguno
    // se cuelga, el audio se corta al instante igual que antes.
    await Future.wait<void>([
      player.setVolume(0).timeout(const Duration(seconds: 2)).catchError((_) {}),
      player.pause().timeout(const Duration(seconds: 2)).catchError((_) {}),
    ]);

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

    // El apagado arranca ACÁ, lo primero de todo.
    //
    // Estaba más abajo, después de salir de pantalla completa y de restaurar
    // las barras del sistema — dos operaciones que van al sistema operativo y
    // vuelven, y que se esperaban una tras otra. Recién después se empezaba a
    // callar el audio, así que a los segundos que ya costaba el apagado se le
    // sumaban esos. Lanzarlo primero no cambia nada de lo que hacen las otras
    // dos, que siguen igual: solo dejan de ir adelante en la fila.
    final shutdown = shutdownPlayback();

    if (isFullScreen.value) {
      await WindowManager.instance.setFullScreen(false);
    }
    // ANTES de popear: así las barras de sistema y la rotación ya están
    // normales cuando la pantalla de destino se dibuja, en vez de depender de
    // que onClose (que corre al destruirse el controller, después del pop)
    // llegue a tiempo. Es idempotente, onClose lo vuelve a llamar sin
    // problema.
    await restoreSystemUiOnExit();
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
  switchServer(String name) async {
    if (_disposed) return;
    if (!availableServers.containsKey(name)) return;
    final myGen = ++_switchServerGen;
    serverFailedMessage.value = '';
    webViewFallback.value = null;
    awaitingServerChoice.value = false;
    hasRenderedFrame.value = false;
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
    if (newWatch.headers != null) {
      for (final e in newWatch.headers!.entries) {
        if (!e.key.startsWith('X-')) headers[e.key] = e.value;
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
    if (_disposed) return;
    player.open(Media('${BTServerApi.baseApi}/torrent/$_torrenHash/$file'));
  }

  // 切换全屏
  toggleFullscreen() async {
    await WindowManager.instance.setFullScreen(!isFullScreen.value);
    isFullScreen.value = !isFullScreen.value;
  }

  // 切换画质
  switchQuality(String qualityUrl) async {
    final currentSecond = player.state.position.inSeconds;
    final headers = watchData!.headers;
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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // refreshHome en false: la pantalla de Home no está visible en ese
      // momento, y refrescarla mientras la app se va es trabajo al pedo.
      unawaited(_touchHistory(refreshHome: false, force: true));
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
      final totalSeconds = duration.value.inSeconds > 0
          ? duration.value.inSeconds
          : player.state.duration.inSeconds;
      final progressSeconds = position.value.inSeconds > 0
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
  String get _baseFrame =>
      md5.convert(utf8.encode('${title}_${playList[index.value].name}')).toString();

  Directory get _dirFrames =>
      Directory(path.join(PrismHubDirectory.getCacheDirectory, 'history_cover'));

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
  _saveHistory({bool captureScreenshot = true, Uint8List? frameCapturado}) async {
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
      // El frame puede venir ya tomado desde _shutdownPlayback (el caso normal
      // al cerrar el reproductor, donde capturar acá sería tarde) o tomarse en
      // el momento, para las llamadas que ocurren con la reproducción viva.
      final data = frameCapturado ??
          (captureScreenshot ? await _capturarFrameActual() : null);

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
          ..progress = player.state.position.inSeconds.toString()
          ..totalProgress = player.state.duration.inSeconds.toString()
          ..isNsfw = isNsfw
          // Al día solo si es el último episodio Y llegó al final de verdad.
          ..watchState = calcularWatchState(
            index: index.value,
            total: playList.length,
            progreso: player.state.position.inSeconds,
            progresoTotal: player.state.duration.inSeconds,
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
  bool get hayCalidades =>
      qualityMap.isNotEmpty || availableServers.length > 1;

  /// Qué panel abrir al tocar el botón de calidad, según de dónde vengan.
  SidebarTab get pestanaDeCalidad =>
      qualityMap.isNotEmpty ? SidebarTab.qualitys : SidebarTab.servers;

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
  connectDLNADevice(DLNADevice device) async {
    if (watchData == null) {
      sendMessage(Message(Text('等待视频加载'.i18n)));
      return;
    }
    var url = watchData!.url;
    final headers = watchData!.headers;
    // El renderer DLNA pide la URL con SU propio cliente HTTP — no hay
    // forma de decirle que mande el Referer/User-Agent que la fuente
    // exige. Sin esto, cualquier fuente con headers obligatorios se veía
    // sana localmente pero fallaba en silencio en el TV. Con headers, se
    // pasa por el relay local en vez de la URL directa (ver
    // cast_relay_server.dart).
    if (headers != null && headers.isNotEmpty) {
      try {
        url = await CastRelayServer.registerAndGetUrl(
          targetUrl: url,
          headers: headers,
        );
        _dlnaRelayUrl = url;
      } catch (e) {
        logger.warning('CastRelayServer falló, casteando URL directa: $e');
      }
    }
    dlnaDevice.value = device;
    await device.setUrl(url);
    await device.play();
    await player.stop();
    // Cancelar cualquier timer previo antes de crear uno nuevo — si el
    // usuario elige otro dispositivo DLNA sin desconectar el anterior
    // primero, sin esto quedaban DOS timers corriendo _getDLNAStatus() cada
    // segundo para siempre (uno por cada dispositivo elegido en la sesión).
    _dlnaTimer?.cancel();
    _dlnaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _getDLNAStatus();
    });
  }

  // 断开 DLNA 设备
  disconnectDLNADevice() async {
    if (dlnaDevice.value == null) {
      return;
    }
    final device = dlnaDevice.value!;
    dlnaDevice.value = null;
    device.stop();
    _dlnaTimer?.cancel();
    if (_dlnaRelayUrl != null) {
      CastRelayServer.unregister(_dlnaRelayUrl!);
      _dlnaRelayUrl = null;
    }
  }

  // 获取 DLNA 播放状态
  _getDLNAStatus() async {
    final device = dlnaDevice.value;
    if (device == null) {
      return;
    }
    // Este método corre desde un Timer.periodic de 1s mientras dure el cast
    // (ver connectDLNADevice) — sin try/catch, un TV desconectado/
    // inalcanzable o un formato de posición inesperado (firmware distinto)
    // tira la MISMA excepción sin manejar una vez por segundo para siempre,
    // sin que el usuario vea ningún aviso.
    try {
      final transportInfo = await device.getTransportInfo();
      isPlaying.value = transportInfo.contains("PLAYING");
      final dlnaPosition = await device.position();
      final positionParser = PositionParser(dlnaPosition);
      final absTimeArr = positionParser.AbsTime.split(":");
      if (absTimeArr.length < 3) return;
      final absTime = Duration(
        hours: int.tryParse(absTimeArr[0]) ?? 0,
        minutes: int.tryParse(absTimeArr[1]) ?? 0,
        seconds: int.tryParse(absTimeArr[2]) ?? 0,
      );
      position.value = absTime;
      duration.value = Duration(seconds: positionParser.TrackDurationInt);
    } catch (e) {
      logger.warning('_getDLNAStatus falló: $e');
    }
  }

  // Verifica si el host de una URL es alcanzable vía TCP.
  // Dart maneja EHOSTUNREACH (errno 113) limpiamente;
  // libmpv/libavformat tienen un bug que causa SIGSEGV con ese errno.
  Future<bool> _isHostReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasAuthority || uri.host.isEmpty) return true;
      final port = (uri.hasPort && uri.port > 0)
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(
        uri.host,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      logger.info('Host alcanzable: ${uri.host}:$port');
      return true;
    } on SocketException catch (e) {
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

  Future<bool> _tryOpenPlayer(String url, Map<String, String>? headers) async {
    if (_disposed) return false;
    if (url.startsWith('error://')) {
      logger.severe('URL de error recibida: $url');
      return false;
    }
    if (!await _isHostReachable(url)) {
      return false;
    }
    if (_disposed) return false;
    // Montar el widget Video ANTES de abrir la fuente — sin esto mpv nunca
    // tiene una superficie real donde pintar (pantalla negra pese a que
    // audio/progreso sí avanzan) y su pipeline de render queda a medio
    // inicializar, el mismo estado que _safePlayerInit documenta como causa
    // de SIGSEGV al hacer dispose/stop más tarde. playTorrentFile y
    // switchQuality ya lo hacían; este es el chokepoint común de TODA la
    // reproducción de servidores (primario, switchServer, fallback directo,
    // sniffer), así que faltaba justo acá.
    await _ensureVideoSurfaceMounted();
    if (_disposed) return false;
    // Inyectar User-Agent de browser si no viene en los headers.
    // libmpv por defecto envía "Lavf/X.X.X" que los CDNs de streaming bloquean.
    final hdrs = <String, String>{'User-Agent': _browserUA};
    if (headers != null) hdrs.addAll(headers);
    await player.open(Media(url, httpHeaders: hdrs));
    if (_disposed) {
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
      // Recuperación de un corte a mitad de capítulo (ver
      // _midStreamResumeAt) — seguir donde se quedó en vez de arrancar
      // la fuente nueva desde 0.
      player.seek(_midStreamResumeAt!);
      _midStreamResumeAt = null;
    }
    return ok;
  }

  // Nombre del servidor recordado para el diálogo "¿Continuar donde te
  // quedaste?" — mismo storage que usa _applyPreferredServer, solo lectura.
  String? get rememberedServerName => PrismHubStorage.getLastWorkingServer(
        runtime.extension.package,
        playList[index.value].url,
      );

  bool _shouldResumeInWebView() {
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
  void confirmResume(int seconds) {
    _isAutoSeekPosition = true;
    resumePrompt.value = null;
    player.seek(Duration(seconds: seconds));
    player.play();
  }

  // Responde al diálogo "¿Continuar donde te quedaste?" — usuario canceló.
  void cancelResume() {
    _isAutoSeekPosition = true;
    resumePrompt.value = null;
    player.play();
  }

  // Antes de rendirse con este servidor, reintentar UNA vez pidiendo una
  // resolución nueva (ver comentario en _serverRetryCount) — algunos hosts
  // (confirmado: Streamwish) firman una URL nueva contra un servidor de
  // backend elegido al azar en cada resolución, así que un simple reintento
  // puede caer en uno sano sin que el usuario tenga que hacer nada.
  void _failOrRetryServer(String name) {
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
    if (dlnaDevice.value == null) {
      player.playOrPause();
      return;
    }
    if (isPlaying.value) {
      await dlnaDevice.value!.pause();
    } else {
      await dlnaDevice.value!.play();
    }
  }

  // Wrappers seguros para los botones de play/pause "crudos" de los
  // controles (antes llamaban controller.player.play/.pause DIRECTO, sin
  // pasar por ningún guard) — confirmado en vivo que esos dos botones son
  // los que seguían tirando "[Player] has been disposed" y tumbando la app
  // entera incluso después de que closeRoute() cerrara la pantalla bien.
  void safePlay() {
    if (_disposed) return;
    try {
      player.play();
    } catch (e) {
      logger.severe('safePlay() error: $e');
    }
  }

  void safePause() {
    if (_disposed) return;
    try {
      player.pause();
    } catch (e) {
      logger.severe('safePause() error: $e');
    }
  }

  seek(Duration duration) async {
    if (_disposed) return;
    // Acá y no en cada botón: seek() es el único punto de entrada para la
    // barra de progreso, los atajos de teclado y los saltos, así que marcarlo
    // una vez cubre todos los casos en las tres plataformas.
    markSeeking();
    if (dlnaDevice.value == null) {
      player.seek(duration);
      return;
    }
    final curr = await dlnaDevice.value!.position();
    final diff = duration - position.value;
    await dlnaDevice.value!.seekByCurrent(curr, diff.inSeconds);
  }

  // Devuelve barras de sistema y rotación al estado normal. Es idempotente a
  // propósito: se llama tanto desde onClose (destrucción del controller) como
  // desde closeRoute (salida explícita del usuario). Antes solo estaba en
  // onClose, y si por lo que sea ese no llegaba a correr, el celular quedaba
  // trabado en horizontal para TODA la app hasta reiniciarla — reportado en
  // vivo. Llamarlo dos veces no molesta; no llamarlo nunca sí.
  Future<void> restoreSystemUiOnExit() async {
    if (!Platform.isAndroid) return;
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
    // 如果是平板则不改变
    // Libera el bloqueo nativo que dejó landscapeAutoMode(forceSensor: true)
    // en onInit — pedir portraitUp/portraitDown acá bloqueaba la rotación
    // libre para siempre (hasta reiniciar la app), porque nada más en la app
    // vuelve a pedir "todas las orientaciones". fullAutoMode restaura la
    // auto-rotación real según el sensor/config del sistema.
    if (!LayoutUtils.isTablet) {
      await AutoOrientation.fullAutoMode();
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
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
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
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
