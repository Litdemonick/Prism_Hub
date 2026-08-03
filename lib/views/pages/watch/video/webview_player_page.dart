import 'dart:async';
import 'dart:io';

import 'package:auto_orientation/auto_orientation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/utils/bloqueador_anuncios.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

// ---------------------------------------------------------------------------
// Entorno de WebView2 (solo Windows) — creado UNA vez para todo el proceso.
//
// Sin pasarle un entorno explícito, el plugin llama
// CreateCoreWebView2EnvironmentWithOptions(nullptr, nullptr, nullptr, ...) en
// CADA InAppWebView que se crea (visto en su código nativo,
// in_app_webview.cpp:167). Eso trae dos problemas reales:
//
//  1. Usa la carpeta de datos por defecto: una al lado del .exe. En la app
//     instalada eso cae en Program Files (solo lectura), así que la creación
//     del entorno falla siempre.
//  2. Es justo la llamada que falla con CO_E_NOTINITIALIZED ("No se ha
//     llamado a CoInitialize" — confirmado en vivo, in_app_webview.cpp:67)
//     cuando COM del proceso quedó en mal estado a mitad de la sesión, que es
//     el "deja de funcionar de la nada".
//
// Con un entorno propio ya creado, el plugin toma el atajo de reusarlo y no
// vuelve a llamar a esa función nativa nunca más — así un solo éxito temprano
// (al arrancar, cuando COM está sano) sirve para toda la vida del proceso.
WebViewEnvironment? _sharedEnvironment;
Future<WebViewEnvironment?>? _sharedEnvironmentFuture;

/// Devuelve el entorno compartido de WebView2, creándolo la primera vez.
/// En plataformas que no son Windows no aplica (devuelve null y el plugin usa
/// el WebView del sistema como siempre).
Future<WebViewEnvironment?> ensureWebViewEnvironment() {
  if (!Platform.isWindows) return Future.value(null);
  if (_sharedEnvironment != null) return Future.value(_sharedEnvironment);
  return _sharedEnvironmentFuture ??= _createWebViewEnvironment();
}

Future<WebViewEnvironment?> _createWebViewEnvironment() async {
  try {
    final dir = Directory(p.join(PrismHubDirectory.getDirectory, 'webview2'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final env = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: dir.path),
    );
    _sharedEnvironment = env;
    return env;
  } catch (e) {
    // Si falla, se sigue con el camino de antes (entorno por defecto) — no
    // conviene romper el WebView por no poder crear el entorno propio.
    logger.warning('No se pudo crear el entorno de WebView2: $e');
    _sharedEnvironmentFuture = null;
    return null;
  }
}

/// True when a URL is a direct media stream that media_kit can play natively.
/// Anything else (an embed/player page like mega.nz/embed, voe.sx/e, ...) is not
/// directly playable.
bool isDirectStream(String url) {
  final u = url.toLowerCase();
  return u.contains('.m3u8') ||
      u.contains('.mp4') ||
      u.contains('.mkv') ||
      u.contains('.webm') ||
      u.contains('.ts') ||
      u.contains('mime=video') ||
      u.contains('/api/file/'); // pixeldrain direct
}

// Servidores que se resuelven perezosamente (recién al elegirlos, no al
// entrar al capítulo) — su URL en la lista sigue siendo la del embed crudo
// (ej. voe.sx/e/xxx), así que isDirectStream() nunca les da el rayito aunque
// verificamos en vivo que sí terminan en un stream nativo confiable. A
// diferencia de Desu/Magi (se resuelven de entrada, su URL en la lista YA es
// la real), estos no tienen otra forma de mostrarlo sin resolver los 5-6
// servidores de una — el problema que esta sesión resolvió justamente para
// no repetir.
// La lista tenía SOLO voe y doodstream y se quedó vieja: mientras tanto el SDK
// aprendió a resolver muchos más, así que servidores que reproducen perfecto en
// nativo aparecían sin rayito, como si fueran los peores de la lista.
//
// Cada nombre de acá se comprobó pidiendo un rango real y mirando que llegara
// vídeo (content-type y bytes), no por si el resolver devolvía una URL.
//
// Aplica a TODAS las extensiones porque se compara por nombre de servidor, no
// por sitio. Se usa `contains` en minúsculas a propósito: cada extensión
// etiqueta distinto ("Streamtape LAT", "byse", "Voex"), y el nombre corto del
// host es lo único estable entre todas.
const _knownReliableServerNames = {
  'voe',
  'doodstream',
  'dsvplay',
  'playmogo',
  'streamtape',
  'stape',
  'streamwish',
  'sfastwish',
  'wishfast',
  'vidhide',
  'mixdrop',
  'mediafire',
  'mp4upload',
  'hexload',
  'savefiles',
  'byse',
  'desu',
  'magi',
};

/// True si el rayito de "nativo confiable" debería mostrarse para esta
/// pestaña — por URL (isDirectStream) o por nombre de servidor verificado.
bool isKnownNativeServer(String serverName, String url) {
  if (isDirectStream(url)) return true;
  final n = serverName.toLowerCase();
  return _knownReliableServerNames.any((known) => n.contains(known));
}

/// Opens an embed/player page in the fullscreen in-app WebView — the last
/// resort for a server that couldn't be resolved/played natively (switchServer
/// already tried that before falling back here).
///
/// [onProgress], if given, is called periodically with a screenshot of the
/// WebView — used to keep "Continuar viendo" updated for this fallback (which
/// bypasses the native player entirely, so it has no other way to report
/// progress). The elapsed-time counter itself lives on the caller's side
/// (survives across a server switch, unlike this page).
// Devuelve el Future del push (en vez de "fire and forget") para que el
// caller pueda saber cuándo esta pantalla se cerró — VideoPlayerConten lo usa
// para reponer el widget Video recién ahí (ver isWebViewActive en
// video_controller.dart).
Future<void> openWebViewPlayer(
  BuildContext context,
  String url, {
  String? referer,
  String title = '',
  void Function(Uint8List? screenshot, {bool isFinal})? onProgress,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WebViewPlayerPage(
        url: url,
        referer: referer,
        title: title,
        onProgress: onProgress,
      ),
    ),
  );
}

/// Fullscreen WebView player. Loads an embed/player page (mega, voe, mixdrop,
/// etc.) in a real browser engine so it runs the host's own player + JS — the
/// fallback for servers that can't be resolved to a direct stream URL.
class WebViewPlayerPage extends StatefulWidget {
  const WebViewPlayerPage({
    super.key,
    required this.url,
    this.title = '',
    this.referer,
    this.onProgress,
    this.autoReloadAttempt = 0,
  });

  final String url;
  final String title;
  final String? referer;
  // isFinal=true solo en la captura final (al salir/pasar a segundo plano)
  // — el caller (saveWebViewProgress en video_controller.dart) usa esto
  // para decidir si actualiza la portada guardada: las llamadas periódicas
  // (isFinal=false) solo actualizan el progreso en segundos, no la imagen.
  final void Function(Uint8List? screenshot, {bool isFinal})? onProgress;
  // Cuántos reintentos automáticos ya se hicieron ante un crash (ver
  // _checkAlive/_reloadAfterCrash) — acotado para no quedar reconstruyendo
  // solo en bucle infinito si el sitio está roto de fondo (no un hipo
  // puntual del proceso de render). Al llegar al tope, se deja de
  // reconstruir solo y se muestra el botón manual de "Recargar".
  final int autoReloadAttempt;

  @override
  State<WebViewPlayerPage> createState() => _WebViewPlayerPageState();
}

/// Puerta publica para pausar el reproductor por WebView desde afuera.
///
/// El estado de la pantalla es privado —como corresponde— pero el aviso de
/// actualizacion necesita poder callarlo antes de taparla. Esto expone SOLO esa
/// accion, sin abrir el resto.
class WebViewPlayerPause {
  WebViewPlayerPause._();

  static Future<void> pausarLoQueSuene() =>
      _WebViewPlayerPageState.pausarLoQueSuene();
}

class _WebViewPlayerPageState extends State<WebViewPlayerPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  // Evita mostrar el aviso "no se pudo reproducir en el nativo" más de una
  // vez (ej. si onLoadStop vuelve a disparar tras un auto-reload).
  bool _shownNativeFailNotice = false;
  bool _noticeVisible = false;
  Timer? _noticeTimer;
  // Evita capturar/guardar dos veces (ej. pasa a background Y se cierra
  // justo después) — la captura final solo tiene sentido una vez.
  bool _finalCaptureDone = false;
  bool _loadTimedOut = false;
  // En un reintento (autoReloadAttempt > 0), la instancia anterior de
  // InAppWebView recién se acaba de destruir (pushReplacement) — crear la
  // nueva de inmediato es la causa más común confirmada en vivo de
  // "Cannot create the InAppWebView instance!" en Windows (el proceso de
  // WebView2 todavía no terminó de liberar recursos). Un margen chico antes
  // de montar el widget le da tiempo a esa limpieza. Sin retraso en el
  // primer intento (autoReloadAttempt == 0) — ahí no hay nada que liberar.
  bool _readyToMount = false;
  // Entorno compartido de WebView2 (null en Android/otros, y también en
  // Windows si no se pudo crear — ahí el plugin cae al comportamiento de
  // antes).
  WebViewEnvironment? _environment;
  InAppWebViewController? _webViewController;

  /// El reproductor por WebView que esta abierto ahora, si hay alguno.
  ///
  /// Mismo motivo que el registro del reproductor nativo: el aviso de
  /// actualizacion sale encima de cualquier pantalla y bloquea, pero sin esto
  /// el video del WebView seguia sonando detras. Aca el audio no lo maneja
  /// media_kit sino la pagina, asi que hay que pedirselo a ella aparte.
  static _WebViewPlayerPageState? _enUso;

  /// Pausa lo que se este reproduciendo dentro del WebView.
  ///
  /// Se le pide a la propia pagina que pause sus <video> y <audio>. No hay una
  /// forma de "pausar el WebView" que sirva en las tres plataformas: pausar los
  /// temporizadores existe solo en Android, y cerrar la vista seria demasiado
  /// —el usuario podria posponer la actualizacion y querer seguir mirando—.
  ///
  /// Se recorren TODOS los elementos y no solo el primero: muchas paginas de
  /// estos sitios tienen ademas un anuncio en video suelto, que es justamente
  /// el que sigue sonando cuando uno cree que ya pauso.
  static Future<void> pausarLoQueSuene() async {
    final controller = _enUso?._webViewController;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: '''
        (function () {
          var m = document.querySelectorAll('video, audio');
          for (var i = 0; i < m.length; i++) {
            try { m[i].pause(); } catch (e) {}
          }
        })();
      ''').timeout(const Duration(seconds: 2));
    } catch (_) {
      // Pagina cerrandose, sin JavaScript, o el puente caido: no es motivo
      // para no mostrar el aviso.
    }
  }
  Timer? _progressTimer;
  Timer? _loadTimeoutTimer;
  Timer? _heartbeatTimer;
  int _heartbeatFailures = 0;
  bool _webViewCrashed = false;
  // Evita procesar el mismo fallo de creación dos veces (ej. si
  // FlutterError.onError se dispara más de una vez para la misma causa).
  bool _creationFailed = false;
  bool _webViewShuttingDown = false;
  bool _returningToNativePlayer = false;
  // Android: la portada se captura en segundo plano cada tanto y al salir se
  // usa la última guardada, en vez de pedir una nueva. takeScreenshot() se
  // inicia de forma síncrona y ocupa el hilo de plataforma leyendo la
  // superficie del WebView; hacerlo justo en el frame de la animación de salida
  // era lo que dejaba la flecha de atrás ~1s colgada y visualmente pixelada
  // (reportado en vivo en Android). En Windows/Linux esa captura al salir no se
  // nota, así que ahí se mantiene el comportamiento de antes — portada del
  // momento exacto en que se salió, sin capturas de más durante la sesión.
  static bool get _cachesCoverShot => Platform.isAndroid;
  Uint8List? _lastShot;
  bool _shotInFlight = false;
  Timer? _firstShotTimer;
  void Function(FlutterErrorDetails)? _previousOnError;
  // Referencia al wrapper propio — al encadenar reintentos (pushReplacement),
  // la página nueva ya instaló el suyo antes de que esta se destruya, así
  // que dispose() solo debe restaurar si el handler activo sigue siendo el
  // que instaló ESTA instancia (si no, restaurar pisaría el de la más nueva).
  void Function(FlutterErrorDetails)? _myOnError;
  // El bridge onEnterFullscreen/onExitFullscreen (más abajo) no siempre
  // dispara según el sitio — se mantiene el botón propio como forma
  // confiable de entrar/salir de pantalla completa, además del bridge.
  bool _isFullScreen = false;

  // Auto-ocultar volver/pantalla-completa igual que el reproductor nativo —
  // sin esto quedaban tapando la esquina de arriba todo el tiempo encima del
  // contenido del sitio. El WebView nativo (vista de plataforma) se come los
  // eventos de mouse dentro suyo, así que el hover para "revelar" solo
  // reacciona confiablemente si el mouse se mueve fuera de esa área — al
  // menos vuelve a mostrarlos apenas se acerca a los bordes.
  bool _showControls = true;
  Timer? _hideTimer;
  DateTime? _lastHideTimerReset;

  void _resetHideTimer() {
    if (_webViewShuttingDown) return;
    final now = DateTime.now();
    if (_showControls &&
        _lastHideTimerReset != null &&
        now.difference(_lastHideTimerReset!) <
            const Duration(milliseconds: 200)) {
      return;
    }
    _lastHideTimerReset = now;
    _hideTimer?.cancel();
    if (!_showControls && mounted) setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  // "Cannot create the InAppWebView instance!" (falla nativa de WebView2 en
  // Windows, confirmada en vivo) no llega a ningún callback del widget —
  // sale directo por FlutterError.onError. Sin este enganche, la única señal
  // de que algo salió mal era el timeout ciego de 15s (hasta 45s sumando los
  // reintentos), aunque el fallo real ya pasó apenas se intentó crear el
  // WebView. Se envuelve el handler global (delegando siempre al anterior)
  // solo mientras esta página está montada, y se restaura en dispose().
  void _installCreationFailureDetector() {
    _previousOnError = FlutterError.onError;
    _myOnError = (FlutterErrorDetails details) {
      if (!_creationFailed &&
          mounted &&
          _loading &&
          details
              .exceptionAsString()
              .contains('Cannot create the InAppWebView instance')) {
        _creationFailed = true;
        _loadTimeoutTimer?.cancel();
        // FlutterError.onError puede dispararse en medio de un build — se
        // difiere la navegación/setState al próximo microtask para no tocar
        // el árbol de widgets mientras el framework todavía lo está armando.
        scheduleMicrotask(() {
          if (!mounted) return;
          if (widget.autoReloadAttempt < _maxAutoReloads) {
            _reloadAfterCrash();
          } else {
            setState(() => _loadTimedOut = true);
          }
        });
      }
      _previousOnError?.call(details);
    };
    FlutterError.onError = _myOnError;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _installCreationFailureDetector();
    _prepareMount();
    _resetHideTimer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Si se llega acá desde el reproductor nativo ya en pantalla completa,
    // sincronizar el estado real para que el botón no crea que hace falta
    // "entrar" cuando ya está.
    if (Platform.isWindows) {
      WindowManager.instance.isFullScreen().then((value) {
        if (mounted) setState(() => _isFullScreen = value);
      });
    }
    if (widget.onProgress != null) {
      // Estas llamadas periódicas NO tocan la portada guardada (isFinal
      // implícito en false) — solo van sumando el contador de segundos
      // transcurridos para que el progreso mostrado en "Continuar viendo"
      // sea razonable. OJO: saveWebViewProgress suma 15s fijos por llamada, así
      // que la cantidad de llamadas a onProgress no se puede cambiar sin
      // falsear el tiempo visto — la captura de portada de Android va aparte
      // (_refreshCoverShot), sin pasar por onProgress.
      //
      // La portada se guarda UNA sola vez, con isFinal:true al salir (ver
      // _captureFinalProgress/didChangeAppLifecycleState).
      _progressTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        widget.onProgress!(null);
        unawaited(_refreshCoverShot());
      });
      // Una captura temprana para que una sesión más corta que el primer tick
      // igual deje portada (en Android, donde la del momento de salir ya no se
      // pide — ver _cachesCoverShot).
      if (_cachesCoverShot) {
        _firstShotTimer = Timer(
            const Duration(seconds: 6), () => unawaited(_refreshCoverShot()));
      }
    }
    // Sin esto, si el WebView nativo nunca llega a crearse (ej. falla de
    // COM/WebView2 en Windows — confirmado en vivo: "Cannot create the
    // InAppWebView instance!"), la página quedaba con el spinner infinito y
    // ningún indicio de que algo salió mal. Ahora, si todavía quedan
    // reintentos automáticos disponibles, reconstruye solo (igual que un
    // crash post-carga) en vez de esperar a que el usuario toque el botón
    // manual — este fallo puntual (el WebView2 nativo no llegó ni a crearse)
    // suele ser un hipo transitorio del proceso de WebView2, no algo
    // permanente.
    _loadTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || !_loading || _webViewShuttingDown) return;
      if (widget.autoReloadAttempt < _maxAutoReloads) {
        _reloadAfterCrash();
      } else {
        setState(() => _loadTimedOut = true);
      }
    });
    // Heartbeat contra el proceso de render de WebView2 muriendo a mitad de
    // reproducción — confirmado en el código nativo del plugin (0.6.0) que
    // Windows NO implementa el evento ProcessFailed (a diferencia de Android,
    // que sí lo hookea), así que no existe forma de que el plugin nos avise
    // solo. Cuando el proceso muere, el WebView queda con el último frame
    // congelado y deja de responder a cualquier JS — evaluateJavascript nunca
    // vuelve a resolver ni tirar error, se queda colgado, por eso el timeout
    // acá es imprescindible para poder contarlo como fallo.
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _checkAlive());
  }

  // Espera a tener el entorno de WebView2 antes de montar el widget — sin
  // esto el InAppWebView se crearía sin entorno y caería en la llamada nativa
  // que falla (ver comentario del entorno compartido arriba).
  //
  // El margen NO es solo para el reintento de ESTA página: el sniffer
  // (StreamSnifferService.sniff/sniffPage) también crea y destruye su propio
  // HeadlessInAppWebView justo antes de que esta página se abra sola por el
  // fallback automático de WebView (ever(webViewFallback,...) en los
  // controles) — confirmado en vivo: la app se queda "No responde" (freeze
  // total, no un error atajable) al abrir el WebView justo después de que el
  // sniffer falló. Mismo problema de fondo que el reintento (WebView2 en
  // Windows todavía liberando recursos del proceso anterior), pero antes el
  // margen solo se aplicaba con autoReloadAttempt>0, así que la PRIMERA vez
  // que se abre (el caso más común del fallback automático) no tenía nada
  // que lo protegiera.
  Future<void> _prepareMount() async {
    final env = await ensureWebViewEnvironment();
    if (Platform.isWindows) {
      await Future.delayed(const Duration(milliseconds: 700));
    }
    if (!mounted || _webViewShuttingDown) return;
    setState(() {
      _environment = env;
      _readyToMount = true;
    });
  }

  // Tope de reconstrucciones automáticas — si el sitio está roto de fondo
  // (no un hipo puntual del proceso de render de WebView2), reconstruir
  // solo para siempre sería un loop infinito silencioso. Agotado el tope,
  // se deja de reconstruir solo y se muestra el botón manual.
  static const _maxAutoReloads = 2;

  Future<void> _checkAlive() async {
    if (!mounted || _loading || _webViewCrashed || _webViewShuttingDown) {
      return;
    }
    try {
      await _webViewController
          ?.evaluateJavascript(source: '1')
          .timeout(const Duration(seconds: 8));
      _heartbeatFailures = 0;
    } catch (_) {
      _heartbeatFailures++;
      // 2 fallos seguidos (~40s sin responder) — no un solo hipo puntual.
      if (_heartbeatFailures >= 2 && mounted && !_webViewShuttingDown) {
        setState(() => _webViewCrashed = true);
        if (widget.autoReloadAttempt < _maxAutoReloads) {
          _reloadAfterCrash();
        }
      }
    }
  }

  void _reloadAfterCrash() {
    if (_webViewShuttingDown || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WebViewPlayerPage(
          url: widget.url,
          referer: widget.referer,
          title: widget.title,
          onProgress: widget.onProgress,
          autoReloadAttempt: widget.autoReloadAttempt + 1,
        ),
      ),
    );
  }

  // Captura y guarda la portada UNA sola vez — al salir del video (botón
  // atrás / gesto atrás) o al pasar la app a segundo plano/cerrarse. Es la
  // única llamada que pasa isFinal:true, así que es la única que realmente
  // actualiza la imagen guardada (ver saveWebViewProgress en
  // video_controller.dart).
  Future<void> _captureFinalProgress() async {
    if (_finalCaptureDone || widget.onProgress == null) return;
    _finalCaptureDone = true;
    if (_cachesCoverShot) {
      // Android: se usa la última captura de fondo, sin tocar el hilo de
      // plataforma acá — así la salida es instantánea. La portada puede ser de
      // hasta ~15s antes del momento exacto en que se salió. Si todavía no se
      // alcanzó a tomar ninguna (sesión de pocos segundos), va null y
      // saveWebViewProgress deja la portada anterior / el fallback.
      widget.onProgress!(_lastShot, isFinal: true);
      return;
    }
    Uint8List? shot;
    try {
      shot = await _webViewController
          ?.takeScreenshot()
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    widget.onProgress!(shot, isFinal: true);
  }

  // Captura de fondo (solo Android, ver _cachesCoverShot). Corre mientras el
  // usuario mira, nunca durante la salida.
  Future<void> _refreshCoverShot() async {
    if (!_cachesCoverShot || _shotInFlight || _finalCaptureDone) return;
    // Nada que capturar si todavía está el spinner, si ya se está cerrando o si
    // el render murió — en esos casos la captura sale en blanco o falla.
    if (_loading || _webViewShuttingDown || _webViewCrashed) return;
    _shotInFlight = true;
    try {
      final shot = await _webViewController
          ?.takeScreenshot()
          .timeout(const Duration(seconds: 3));
      if (shot != null) _lastShot = shot;
    } catch (_) {
    } finally {
      _shotInFlight = false;
    }
  }

  void _shutdownWebView() {
    if (_webViewShuttingDown) return;
    _webViewShuttingDown = true;
    _progressTimer?.cancel();
    _firstShotTimer?.cancel();
    _loadTimeoutTimer?.cancel();
    _heartbeatTimer?.cancel();
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    final controller = _webViewController;
    if (controller == null) return;
    try {
      unawaited(controller.evaluateJavascript(source: '''
        for (const v of document.querySelectorAll('video, audio')) {
          try {
            v.pause();
            v.removeAttribute('src');
            v.load();
          } catch (_) {}
        }
      '''));
    } catch (_) {}
    try {
      unawaited(controller.stopLoading());
    } catch (_) {}
    Timer(const Duration(milliseconds: 80), () {
      try {
        unawaited(controller.loadUrl(
          urlRequest: URLRequest(url: WebUri('about:blank')),
        ));
      } catch (_) {}
    });
  }

  // No async/await acá a propósito: esperar la captura (hasta 3s de
  // takeScreenshot) antes de volver hacía que el botón atrás se sintiera
  // colgado/lento (reportado en vivo). Se dispara la captura en paralelo y
  // se vuelve al instante — best-effort, igual que el caso de
  // background/cierre en didChangeAppLifecycleState.
  void _exitAndCaptureProgress() {
    _returningToNativePlayer = true;
    if (!mounted) {
      unawaited(_captureFinalProgress());
      return;
    }
    // El pop va PRIMERO y la captura después. En Android la captura de acá ya
    // no toca el hilo de plataforma (usa la última de fondo, ver
    // _cachesCoverShot), pero en escritorio sigue pidiendo una nueva: aunque
    // esté sin await, takeScreenshot() se INICIA de forma síncrona y deja al
    // hilo nativo leyendo la superficie del WebView. Popeando primero, la
    // animación arranca limpia y la captura corre en la ventana en la que la
    // ruta todavía se está yendo pero el WebView sigue vivo (dispose recién
    // corre al terminar la transición), así que la portada se guarda igual.
    Navigator.of(context).pop();
    unawaited(_captureFinalProgress());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused/hidden: la app se va a segundo plano o se está cerrando — mejor
    // esfuerzo, no hay garantía de que el proceso siga vivo el tiempo
    // suficiente para terminar la captura si es un cierre abrupto, pero
    // cubre el caso común (minimizar, cambiar de app, Alt+Tab).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_captureFinalProgress());
      // SOLO se pausa el vídeo — antes acá se llamaba a _shutdownWebView(), que
      // manda el WebView a about:blank y cancela todos los timers. Apagar la
      // pantalla del celular pasa la app a `paused`, así que eso DESTRUÍA el
      // reproductor: al volver a encenderla quedaba todo en negro y sin
      // siquiera el botón de atrás (reportado en vivo).
      //
      // El desmontaje de verdad sigue estando donde corresponde: al salir del
      // reproductor y en dispose. Pausar acá igual es necesario para que el
      // audio no siga sonando con la pantalla apagada.
      _pauseMedia();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Al volver, mostrar los controles y reiniciar el auto-ocultado: si la
      // pantalla se apagó con los controles ya escondidos, al despertar no
      // había nada visible y parecía que el reproductor se había colgado.
      if (mounted) setState(() => _showControls = true);
      _resetHideTimer();
    }
  }

  // Pausa el vídeo/audio del sitio sin tocar nada más: no descarga la fuente, no
  // corta la carga, no cancela timers y no navega a otra página. Sirve para
  // segundo plano, donde el reproductor tiene que seguir vivo para cuando el
  // usuario vuelva.
  void _pauseMedia() {
    final controller = _webViewController;
    if (controller == null) return;
    try {
      unawaited(controller.evaluateJavascript(source: '''
        for (const v of document.querySelectorAll('video, audio')) {
          try { v.pause(); } catch (_) {}
        }
      '''));
    } catch (_) {}
  }

  // Solo Windows: en Android se probó pedirle al <video> del sitio que
  // entre a su propio fullscreen HTML5 vía JS (requestFullscreen) para
  // tener un botón también ahí — revertido, dispara la vista nativa de
  // fullscreen de Android (onShowCustomView), que tapa TODA la pantalla
  // incluyendo nuestros propios controles de Flutter (confirmado en vivo:
  // pantalla negra, botones sin responder). Hacerlo bien en Android
  // necesita un overlay nativo propio, no JS — queda pendiente; por ahora
  // el fullscreen HTML5 del sitio se maneja solo con su propio botón
  // adentro del embed.
  Future<void> _toggleFullScreen() async {
    if (!Platform.isWindows) return;
    _isFullScreen = !_isFullScreen;
    await WindowManager.instance.setFullScreen(_isFullScreen);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Solo si sigo siendo yo: al encadenar episodios puede haberse registrado
    // ya la vista siguiente, y borrarla dejaria el aviso sin a quien pausar.
    if (identical(_enUso, this)) _enUso = null;
    if (!_returningToNativePlayer) {
      _shutdownWebView();
    }
    if (identical(FlutterError.onError, _myOnError)) {
      FlutterError.onError = _previousOnError;
    }
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _firstShotTimer?.cancel();
    _loadTimeoutTimer?.cancel();
    _heartbeatTimer?.cancel();
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    if (Platform.isWindows && _isFullScreen) {
      unawaited(WindowManager.instance.setFullScreen(false));
    }
    // Solo si NO se vuelve al reproductor nativo. Con la flecha de atrás se
    // vuelve a él (ver _exitAndCaptureProgress), y ese sigue abierto queriendo
    // horizontal + pantalla completa: restaurar acá forzaba rotación libre y
    // barras visibles, el nativo las volvía a cambiar enseguida, y esos dos
    // relayouts encadenados hacían que la flecha se sintiera colgada varios
    // segundos en Android (reportado en vivo; en Windows no se nota porque no
    // hay cambio de orientación). Cuando de verdad se sale del reproductor,
    // quien restaura es VideoPlayerController (closeRoute/onClose), que es el
    // dueño real de ese estado.
    if (!_returningToNativePlayer) {
      _restoreSystemUiOnExit();
    }
    super.dispose();
  }

  // Devuelve barras de sistema y rotación al estado normal al salir del
  // reproductor. Es EXACTAMENTE lo mismo que hace VideoPlayerController.onClose
  // — antes acá se hacía distinto y eso provocaba los dos bugs reportados en
  // vivo en Android:
  //
  // 1) `edgeToEdge` dejaba la hora/batería/notificaciones "comidas": el
  //    SafeArea de la pantalla de destino no llegaba a refrescar su padding
  //    superior tras el cambio de modo, así que el contenido se dibujaba
  //    encima del status bar. Pedir `manual` con TODOS los overlays fuerza a
  //    que ambas barras vuelvan reservando su espacio, sin depender de ese
  //    timing.
  //
  // 2) El celular quedaba trabado en horizontal para toda la app. El
  //    reproductor nativo deja un bloqueo NATIVO de orientación
  //    (AutoOrientation.landscapeAutoMode(forceSensor: true) en su onInit) que
  //    solo libera fullAutoMode(). Acá solo se llamaba a
  //    setPreferredOrientations, que NO alcanza para soltar ese bloqueo — y
  //    como a esta pantalla se puede llegar desde el reproductor nativo (ver
  //    el comentario en initState), salir por acá dejaba el bloqueo puesto y
  //    nada más en la app volvía a pedir rotación libre.
  void _restoreSystemUiOnExit() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    if (!Platform.isAndroid) return;
    // Mismo criterio que el reproductor nativo: en tablet no se toca la
    // orientación (nunca se la forzó).
    if (!LayoutUtils.isTablet) {
      unawaited(AutoOrientation.fullAutoMode());
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Cubre el gesto/botón atrás del sistema (Android), no solo los
        // botones propios de esta pantalla — misma captura final antes de
        // salir.
        _exitAndCaptureProgress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _resetHideTimer(),
          onEnter: (_) => _resetHideTimer(),
          // MouseRegion (arriba) solo reacciona a mouse real — en celular no
          // dispara nunca, así que una vez que la barra se auto-ocultaba a
          // los 2s no había NINGUNA forma de volver a mostrarla tocando la
          // pantalla (confirmado en vivo: el botón de volver quedaba
          // invisible e inactivo para siempre). Listener (no GestureDetector)
          // a propósito: solo escucha el evento de puntero crudo, sin entrar
          // en el gesture arena — así no compite por el toque con la vista
          // de plataforma del WebView (que necesita sus propios taps/scroll
          // para el embed del sitio) ni le agrega latencia.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _resetHideTimer(),
            child: Stack(
              children: [
                if (_readyToMount)
                  InAppWebView(
                    webViewEnvironment: _environment,
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.url),
                      headers: widget.referer != null
                          ? {'Referer': widget.referer!}
                          : null,
                    ),
                    initialSettings: InAppWebViewSettings(
                      userAgent: PrismHubStorage.getUASetting(),
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      javaScriptEnabled: true,
                      transparentBackground: true,
                      // Bloquea ventanas/popups de anuncios de los hosts.
                      javaScriptCanOpenWindowsAutomatically: false,
                      supportMultipleWindows: false,
                      // Las listas del usuario, en la vía nativa: el pedido ni
                      // se hace. Soportado en Android (y iOS/macOS); en Windows
                      // llega vacío y el bloqueo lo hacen shouldOverrideUrlLoading
                      // y el guion que se inyecta más abajo.
                      contentBlockers: BloqueadorAnuncios.reglasNativas(),
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                      _enUso = this;
                      // El guion se agrega como UserScript y NO en onLoadStop:
                      // tiene que correr ANTES que el JS del sitio para poder
                      // tapar window.open, que es como se abren las ventanas
                      // emergentes. Puesto al final ya sería tarde.
                      final guion = BloqueadorAnuncios.guionParaInyectar();
                      if (guion.isNotEmpty) {
                        controller.addUserScript(
                          userScript: UserScript(
                            source: guion,
                            injectionTime:
                                UserScriptInjectionTime.AT_DOCUMENT_START,
                          ),
                        );
                      }
                    },
                    // Puentea el fullscreen HTML5 del propio sitio (el botón que se ve
                    // dentro de su reproductor) con el fullscreen real de la ventana
                    // de Windows — sin esto, el sitio entraba en "fullscreen" a nivel
                    // DOM pero la ventana de la app se quedaba igual, así que no se
                    // veía ningún cambio.
                    onEnterFullscreen: (controller) {
                      if (mounted) setState(() => _isFullScreen = true);
                      if (Platform.isWindows) {
                        WindowManager.instance.setFullScreen(true);
                      }
                    },
                    onExitFullscreen: (controller) {
                      if (mounted) setState(() => _isFullScreen = false);
                      if (Platform.isWindows) {
                        WindowManager.instance.setFullScreen(false);
                      }
                    },
                    onLoadStop: (controller, url) {
                      _loadTimeoutTimer?.cancel();
                      if (mounted) setState(() => _loading = false);
                      // El aviso de por qué se llegó acá va DESPUÉS de que
                      // el navegador interno ya cargó y se ve — mostrarlo
                      // antes (en la pantalla del reproductor nativo, previo
                      // a navegar) se veía como un flash raro seguido de un
                      // cambio de pantalla abrupto (reportado en vivo).
                      // Aviso propio dentro del Stack, NO un SnackBar: esta
                      // pantalla vive bajo FluentApp (no MaterialApp), así
                      // que no hay ScaffoldMessenger en el árbol y
                      // ScaffoldMessenger.of(context) tiraba excepción en
                      // cada carga (confirmado en el log en vivo).
                      if (!_shownNativeFailNotice && mounted) {
                        _shownNativeFailNotice = true;
                        setState(() => _noticeVisible = true);
                        _noticeTimer?.cancel();
                        _noticeTimer = Timer(const Duration(seconds: 4), () {
                          if (mounted) setState(() => _noticeVisible = false);
                        });
                      }
                    },
                    // Mantener la navegación dentro del mismo host: bloquea redirecciones
                    // a páginas de otros dominios — en la práctica, casi siempre
                    // anuncios/popunders de los hosts de video, no contenido real.
                    // Antes esto abría el navegador externo del sistema como
                    // "mejor que nada" — a pedido explícito, ya no: el reproductor
                    // nunca debe abrir el navegador externo, solo el WebView interno.
                    // Se cancela la navegación sin más — el usuario sigue viendo el
                    // video/embed original sin interrupciones.
                    shouldOverrideUrlLoading: (controller, action) async {
                      final u = action.request.url;
                      if (u == null) return NavigationActionPolicy.ALLOW;
                      // Listas del usuario. En Android esto casi no se usa
                      // porque el bloqueo nativo ya atajó el pedido antes; en
                      // Windows y Linux, donde ese bloqueo no existe, es la
                      // primera barrera contra las páginas de anuncios.
                      if (BloqueadorAnuncios.bloquea(u.toString())) {
                        logger.info('[bloqueador] navegación cortada: ${u.host}');
                        return NavigationActionPolicy.CANCEL;
                      }
                      final host = Uri.tryParse(widget.url)?.host;
                      if (action.isForMainFrame &&
                          host != null &&
                          u.host.isNotEmpty &&
                          u.host != host) {
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                  ),
                if (_loading && _loadTimedOut)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.orangeAccent, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            'No se pudo abrir el navegador interno.\n'
                            'Probá abrirlo en tu navegador, o cerrá la app '
                            '${Platform.isAndroid ? '' : '(no solo minimizar) '}'
                            'y volvé a intentar.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          // Falla conocida y no siempre evitable de flutter_inappwebview
                          // en Windows/Linux desktop (confirmado: mismo error exacto
                          // reportado en otros proyectos ajenos a PrismHub) — sin esto,
                          // si el WebView interno no llega ni a crearse, no había
                          // ninguna forma de ver el contenido igual.
                          FilledButton(
                            onPressed: () {
                              final uri = Uri.tryParse(widget.url);
                              if (uri != null) {
                                launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            child: const Text('Abrir en tu navegador'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            onPressed: _exitAndCaptureProgress,
                            child: const Text('Volver'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_webViewCrashed)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.orangeAccent, size: 40),
                          const SizedBox(height: 12),
                          const Text(
                            'El navegador interno dejó de responder.\n'
                            'Esto puede pasar en sitios con muchos anuncios.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white, fontSize: 15, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _reloadAfterCrash,
                            child: const Text('Recargar'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            onPressed: _exitAndCaptureProgress,
                            child: const Text('Volver'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                // Barra superior: volver y pantalla completa. Se oculta sola a los
                // 2s sin actividad, igual que los controles del reproductor nativo.
                // Mismo degradado negro→transparente que usa el reproductor nativo
                // (video_player_mobile_controls.dart) en vez de círculos negros
                // planos sueltos — esos se veían fuera de lugar/inconsistentes
                // con el resto de la app (reportado en vivo: "el contorno se ve
                // mal").
                IgnorePointer(
                  ignoring: !_showControls,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.85),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.white),
                                onPressed: _exitAndCaptureProgress,
                              ),
                              const Spacer(),
                              if (Platform.isWindows)
                                IconButton(
                                  icon: Icon(
                                    _isFullScreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                  onPressed: _toggleFullScreen,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Aviso de "por qué estás en el navegador interno" — abajo,
                // sin tapar el video, y se va solo a los 4s. Reemplaza al
                // SnackBar (esta pantalla no tiene ScaffoldMessenger arriba,
                // ver onLoadStop).
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _noticeVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: SafeArea(
                        top: false,
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'No se pudo reproducir en el reproductor nativo. '
                            'Viendo desde el navegador interno.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
