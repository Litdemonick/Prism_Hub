import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart'
    show openWebViewPlayer;
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/views/pages/watch/video/video_player_cast.dart';
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/watch/aviso_extension_caida.dart';
import 'package:volume_controller/volume_controller.dart';

class VideoPlayerMobileControls extends StatefulWidget {
  const VideoPlayerMobileControls({super.key, required this.controller});
  final VideoPlayerController controller;

  @override
  State<VideoPlayerMobileControls> createState() =>
      _VideoPlayerMobileControlsState();
}

class _VideoPlayerMobileControlsState extends State<VideoPlayerMobileControls> {
  late final VideoPlayerController _c = widget.controller;
  final _subtitleViewKey = GlobalKey<SubtitleViewState>();
  bool _showControls = true;
  double _currentVolume = 0;
  // Amplificación por ENCIMA del volumen del sistema, en por ciento.
  //
  // Deslizar hacia arriba sube el volumen del teléfono, y ahí se terminaba:
  // con el sistema al máximo y una pista grabada baja no quedaba nada por
  // hacer. Pasado ese punto, seguir deslizando amplifica desde el reproductor
  // —que es lo único que puede dar más de lo que se grabó—, hasta el techo de
  // VideoPlayerController.volumenMaximo.
  //
  // 100 = sin amplificar, o sea el comportamiento de siempre.
  double _boost = 100;
  bool _isAdjusting = false;
  bool _isLongPress = false;
  // Velocidad del adelantado con el dedo apoyado.
  //
  // Estaba en 3x y se veia a tirones. No era un problema del gesto sino de
  // trabajo: a 3x el decodificador tiene que sacar el triple de cuadros por
  // segundo y ademas hay que reajustar el tono del audio sobre la marcha. En
  // el telefono eso no entra, asi que empieza a saltear cuadros y se ve peor
  // que el video normal — justo lo contrario de lo que uno espera al adelantar.
  //
  // A 2x el trabajo extra es la mitad y es la velocidad que usan los
  // reproductores conocidos para este mismo gesto. Se deja con nombre para que
  // cambiarla sea tocar un solo numero.
  static const double _velocidadSostenida = 2.0;
  // Cuenta de dedos apoyados en la pantalla — sin esto, pellizcar con 2 dedos
  // (que el usuario espera que no haga nada, no hay zoom por pellizco, solo
  // doble tap) igual disparaba onVerticalDragUpdate con el movimiento de uno
  // de los 2 dedos, subiendo/bajando el volumen sin querer.
  int _activePointers = 0;
  Timer? _timer;
  Worker? _webViewWorker;
  Worker? _resumeWorker;
  Worker? _tutorialWorker;
  // Debounce: ignores taps within 600 ms to prevent double-trigger on fast touch.
  DateTime? _lastTap;
  bool _debounce([Duration d = const Duration(milliseconds: 600)]) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < d) return false;
    _lastTap = now;
    return true;
  }

  _updateTimer() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _showControls = true;
    });
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      },
    );
  }

  // Valor del ajuste, en segundos y siempre positivo: el sentido del salto lo
  // decide el lado de la pantalla, no el signo guardado.
  double _saltoConfigurado(String key) {
    final v = PrismHubStorage.getSetting(key);
    final d = v is num ? v.toDouble() : 10.0;
    final abs = d.abs();
    return abs == 0 ? 10.0 : abs;
  }

  // Cartel breve con cuántos segundos se saltó — sin esto el doble toque no
  // daba ninguna devolución y no se notaba si había hecho algo.
  int? _saltoVisible;
  Timer? _saltoTimer;

  /// Aviso corto en el centro-arriba, aparte del cartel de segundos.
  ///
  /// Sirve para decir "el video esta pausado": adelantando con doble toque con
  /// el video en pausa, la barra se movia pero la imagen no, y parecia que el
  /// salto no habia funcionado.
  String? _avisoCentro;
  Timer? _avisoTimer;

  void _mostrarAviso(String texto) {
    if (!mounted) return;
    // Transmitiendo, el aviso va DENTRO del panel del centro, en el renglon del
    // estado. Como caja aparte quedaba una segunda caja oscura encima de la
    // primera; adentro es una sola cosa que cambia de texto.
    if (_c.dlnaDevice.value != null) {
      _c.castAviso.value = texto;
      _avisoTimer?.cancel();
      _avisoTimer = Timer(const Duration(milliseconds: 1600), () {
        _c.castAviso.value = null;
      });
      return;
    }
    setState(() => _avisoCentro = texto);
    _avisoTimer?.cancel();
    _avisoTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _avisoCentro = null);
    });
  }

  void _mostrarSalto(int segundos) {
    setState(() => _saltoVisible = segundos);
    _saltoTimer?.cancel();
    _saltoTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _saltoVisible = null);
    });
  }

  _init() async {
    _updateTimer();
    VolumeController().showSystemUI = false;
    _currentVolume = await VolumeController().getVolume();
    // Se sigue el volumen real del telefono mientras el reproductor este
    // abierto.
    //
    // Antes se leia una sola vez aca y nunca mas: si el usuario tocaba los
    // botones fisicos, el numero que mostraba el gesto quedaba viejo y decia
    // un volumen que no era el que sonaba.
    VolumeController().listener((volumen) {
      if (!mounted) return;
      if (_currentVolume == volumen) return;
      _currentVolume = volumen;
      // Solo se repinta si el cartel esta a la vista; si no, alcanza con
      // guardarlo para cuando se muestre.
      if (_isAdjusting) setState(() {});
    });
  }

  @override
  void initState() {
    _init();
    super.initState();
    // El reproductor nativo no pudo con este servidor — abrir el WebView
    // automáticamente (ver mismo comentario en video_player_desktop_controls.dart:
    // este worker tenía el callback vacío, así que el fallback nunca se
    // disparaba de verdad).
    _webViewWorker = ever(_c.webViewFallback, (fallback) {
      if (fallback == null || !mounted || _c.webViewOpenedOnce.value) return;
      // Directo, sin pausa: mostrar el mensaje acá y recién después navegar
      // se veía como un flash raro (reportado en vivo) — el navegador interno
      // tiene que abrir/cargar primero, y el aviso de por qué se cambió se
      // muestra DENTRO de esa pantalla (ver _WebViewPlayerPageState en
      // webview_player_page.dart), no antes de llegar a ella.
      _openWebView();
    });
    // Mostrar diálogo de continuación cuando el controlador emite la señal.
    _resumeWorker = ever(_c.resumePrompt, (secs) {
      if (secs == null || !mounted) return;
      // Con el tutorial puesto NO se muestra: salia encima y aceptarlo mandaba
      // a reproducir con el tutorial todavia tapando la pantalla. No se
      // descarta, se espera — el worker de abajo lo saca al cerrarse.
      if (_c.tutorialArriba.value) return;
      _showResumeDialog(secs);
    });
    // Al cerrarse el tutorial, si habia quedado un aviso pendiente, ahora si.
    _tutorialWorker = ever(_c.tutorialArriba, (arriba) {
      if (arriba == true || !mounted) return;
      final secs = _c.resumePrompt.value;
      if (secs != null) _showResumeDialog(secs);
    });
  }

  @override
  void dispose() {
    _webViewWorker?.dispose();
    _resumeWorker?.dispose();
    _tutorialWorker?.dispose();
    _avisoTimer?.cancel();
    _saltoTimer?.cancel();
    _timer?.cancel();
    // Sin esto queda escuchando el volumen del sistema despues de cerrar el
    // reproductor, sobre un State que ya no existe.
    VolumeController().removeListener();
    super.dispose();
  }

  // Reabre el WebView con la misma URL guardada (mismo botón que en
  // desktop) — sin esto, cerrar el WebView (atrás) y volver acá no dejaba
  // ninguna forma de retomarlo salvo tocar el servidor de nuevo.
  Future<void> _openWebView() async {
    final fallback = _c.webViewFallback.value;
    if (fallback == null) return;
    _c.webViewOpenedOnce.value = true;
    _c.markWebViewPlayback(fallback);
    // El reproductor nativo (media_kit/mpv) seguía con su textura de video
    // activa de fondo mientras el WebView se abre ENCIMA (esta pantalla no
    // reemplaza la ruta anterior, la apila) — dos motores de render nativos
    // pesados (mpv/ANGLE y WebView2/Chromium) compitiendo por GPU en la
    // misma ventana en Windows es la causa confirmada (mismo problema
    // reportado en los repos de flutter_inappwebview y media_kit) del
    // freeze/"No responde" — tan severo que ni un hot restart lo recupera,
    // hay que matar el proceso. player.stop() solo no alcanza (para de
    // decodificar, pero no libera la textura nativa) — isWebViewActive saca
    // el widget Video del árbol entero mientras el WebView esté arriba (ver
    // VideoPlayerConten).
    unawaited(_c.player.stop());
    _c.isWebViewActive.value = true;
    final referer = fallback['referer'];
    await openWebViewPlayer(
      context,
      fallback['url']!,
      referer: (referer == null || referer.isEmpty) ? null : referer,
      title: _c.title,
      onProgress: _c.saveWebViewProgress,
    );
    await Future.delayed(const Duration(milliseconds: 180));
    if (mounted) _c.isWebViewActive.value = false;
  }

  void _showResumeDialog(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    final timeStr = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final server = _c.rememberedServerName;
    final serverStr = (server != null && server.isNotEmpty)
        ? ' en el servidor "$server"'
        : '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        // El reproductor fuerza orientación horizontal, así que este diálogo
        // SIEMPRE se muestra con poco alto útil — scrollable + margen chico
        // para que no desborde con títulos/tiempos largos.
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        title: const Text('¡Un momento!'),
        content: Text(
          'Parece que anteriormente estabas mirando este vídeo$serverStr. '
          '¿Deseas continuar donde te quedaste? $timeStr',
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.cancelResume();
            },
          ),
          TextButton(
            child: const Text('Aceptar'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.confirmResume(secs);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
      ),
      child: Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: Stack(
          children: [
            // Rueda de carga mientras el reproductor bufferiza (al
            // adelantar, al cambiar de servidor o si la red se pone lenta).
            // El controller ya calculaba isActuallyBuffering —con la
            // corrección de los eventos desfasados de mpv— pero NADIE lo
            // mostraba: adelantar un minuto dejaba la imagen congelada sin
            // ninguna señal de que estaba cargando.
            Positioned.fill(
              child: IgnorePointer(
                child: Obx(() => AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      // Mismas condiciones que el panel de estado de más
                      // abajo, si no esta rueda se montaba encima del cartel
                      // de "Obteniendo enlace...": ahí todavía no hay vídeo
                      // que bufferizar, así que girar no significa nada.
                      // Tampoco con el vídeo pausado (mpv sigue llenando el
                      // buffer a propósito) ni antes del primer frame.
                      // isSeeking aparte del buffering: al buscar en la
                      // barra, el flag de buffering se apaga solo (la
                      // posición cambia y eso se lee como "hay frames
                      // nuevos"), así que sin esto la imagen se congelaba
                      // sin ninguna señal. isPlaying tampoco sirve durante
                      // la búsqueda, porque mpv se pausa mientras resuelve.
                      // Tres momentos distintos en los que hay que
                      // esperar, y ninguno se pisa con el cartel de
                      // "Obteniendo enlace" (isGettingWatchData), que tiene
                      // su propia tarjeta:
                      //  1. Enlace ya resuelto pero primer cuadro sin
                      //     pintar. Acá solo había un anillo chico y la
                      //     pantalla se veía negra y trabada, sobre todo
                      //     con HLS.
                      //  2. Salto en curso (barra, teclas o flechas).
                      //  3. Buffer vacío durante la reproducción.
                      // Casteando no se muestra NINGUNA rueda: el reproductor
                      // de aca esta parado a proposito, asi que "cargando" y
                      // "sin buffer" no describen nada de lo que pasa en el
                      // televisor. Era esto lo que aparecia al adelantar.
                      opacity: (_c.dlnaDevice.value == null &&
                              ((!_c.isGettingWatchData.value &&
                                      !_c.hasRenderedFrame.value &&
                                      // Ver el comentario equivalente en los
                                      // controles de escritorio.
                                      _c.error.value.isEmpty &&
                                      // El aviso de "el servidor falló, tocá para
                                      // reproducir" espera una acción del usuario:
                                      // nada está cargando y la rueda no tiene por
                                      // qué girar. Faltaba esta condición y se veía
                                      // dando vueltas DETRÁS del aviso, que encima
                                      // hace parecer que si uno espera se arregla
                                      // solo. El fallo de servidor no se guarda en
                                      // `error` —tiene su propio campo— así que la
                                      // comprobación de arriba no lo cubría.
                                      _c.serverFailedMessage.value.isEmpty &&
                                      // Esperando que se elija/confirme servidor:
                                      // el boton de play esta ahi pidiendo un
                                      // toque y no hay nada cargando. La rueda
                                      // girando detras hacia parecer que si uno
                                      // espera arranca solo.
                                      !_c.awaitingServerChoice.value &&
                                      !_c.isWebViewActive.value) ||
                                  (_c.hasRenderedFrame.value &&
                                      (_c.isSeeking.value ||
                                          // imagenCongelada: con la red mal, mpv
                                          // deja de avisar que esta cargando, asi
                                          // que la rueda no salia y la pantalla
                                          // quedaba quieta sin explicacion. Esto
                                          // mira que la posicion no avance, que es
                                          // lo unico que siempre se puede saber.
                                          _c.imagenCongelada.value ||
                                          (_c.isPlaying.value &&
                                              _c.isActuallyBuffering.value)))))
                          ? 1
                          : 0,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            // Disco oscuro detrás: sobre un fotograma claro
                            // el círculo morado solo se perdía.
                            shape: BoxShape.circle,
                            color: Color(0xB3000000),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.5,
                                valueColor: AlwaysStoppedAnimation(
                                    HomeTheme.oscuroAcento),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )),
              ),
            ),
            // 字幕
            Positioned.fill(
              child: Obx(
                () {
                  final textStyle = TextStyle(
                    height: 1.4,
                    fontSize: _c.subtitleFontSize.value,
                    letterSpacing: 0.0,
                    wordSpacing: 0.0,
                    color: _c.subtitleFontColor.value,
                    fontWeight: _c.subtitleFontWeight.value,
                    backgroundColor:
                        _c.subtitleBackgroundColor.value.withValues(
                      alpha: _c.subtitleBackgroundOpacity.value,
                    ),
                  );
                  return SubtitleView(
                    controller: _c.videoController,
                    configuration: SubtitleViewConfiguration(
                      style: textStyle,
                      textAlign: _c.subtitleTextAlign.value,
                    ),
                    key: _subtitleViewKey,
                  );
                },
              ),
            ),
            // 顶部提示
            Positioned(
              top: 30,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(5)),
                    color: Colors.black45,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLongPress)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          // El texto estaba escrito a mano y en ingles, con el
                          // "3x" clavado adentro: cambiar la velocidad dejaba
                          // el cartel mintiendo. Ahora sale la de verdad y en
                          // el idioma del usuario.
                          child: Text(
                            FlutterI18n.translate(
                              context,
                              'video.holding-fast-forward',
                              translationParams: {
                                'x': _velocidadSostenida.toStringAsFixed(
                                    _velocidadSostenida % 1 == 0 ? 0 : 1)
                              },
                            ),
                          ),
                        ),
                      if (_isAdjusting)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.volume_up),
                              const SizedBox(width: 5),
                              // Con amplificación se muestra ESA, que es lo
                              // que está cambiando el gesto en ese tramo. Sin
                              // el signo, 150 y 100 se leerían igual de
                              // "normales" y no se entendería que una está
                              // amplificada.
                              Text(
                                _boost > 100
                                    ? '+${(_boost - 100).toStringAsFixed(0)}%'
                                    // Con % y redondeado al entero: "47" solo
                                    // no se lee como un volumen, y sin
                                    // redondear el numero temblaba en cada
                                    // pixel de arrastre.
                                    : '${(_currentVolume * 100).round()}%',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // 手势层
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) {
                  _activePointers++;
                  // Un dedo mas apoyado MIENTRAS se mantiene apretado sube la
                  // velocidad: x2, x4, x8, x16. Es el gesto que ya se usa en
                  // otras apps para adelantar rapido sin soltar.
                  //
                  // Solo transmitiendo: aca el sostenido usa la velocidad fija
                  // que el usuario configuro, y cambiarla a mitad de gesto seria
                  // otra cosa distinta de la que ya conoce.
                  if (_isLongPress &&
                      _activePointers > 1 &&
                      _c.dlnaDevice.value != null) {
                    final actual = _c.castVelocidadPedida.value;
                    // Techo en 16: mas rapido que eso ningun aparato lo hace
                    // util, y varios directamente lo rechazan.
                    final siguiente = actual >= 16 ? 2 : actual * 2;
                    unawaited(_c.pedirVelocidadCast(siguiente));
                  }
                },
                onPointerUp: (_) {
                  if (_activePointers > 0) _activePointers--;
                },
                onPointerCancel: (_) {
                  if (_activePointers > 0) _activePointers--;
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_showControls) {
                      _showControls = false;
                      setState(() {});
                      return;
                    }
                    _updateTimer();
                  },
                  onDoubleTapDown: (details) {
                    if (!_debounce(const Duration(milliseconds: 400))) return;
                    final dx = details.localPosition.dx;
                    // Un tercio del ancho REAL de esta zona, no del de la
                    // pantalla.
                    //
                    // localPosition viene medido contra esta zona, pero el
                    // tercio se calculaba con el ancho de la pantalla entera.
                    // Con la barra lateral abierta la zona es mas angosta, asi
                    // que los limites quedaban corridos a la derecha: el centro
                    // visual caia dentro del tercio "izquierdo" y en vez de
                    // pausar retrocedia, y el tercio derecho no se alcanzaba
                    // nunca.
                    final ancho = (context.size?.width ?? LayoutUtils.width);
                    final width = ancho / 3;
                    // Los 10 segundos estaban fijos en el código, así que el
                    // ajuste "Saltar intervalo" no tenía ningún efecto en
                    // celular. En el teléfono el doble toque es el ÚNICO
                    // atajo de salto (no hay teclado), así que es el que debe
                    // respetar ese ajuste: arrowLeft para el lado izquierdo y
                    // arrowRight para el derecho, los mismos que en PC usan
                    // las flechas. Se toma el valor absoluto porque el signo
                    // ya lo decide el lado que se tocó.
                    final atras = Duration(
                        milliseconds:
                            (_saltoConfigurado(SettingKey.arrowLeft) * 1000)
                                .round());
                    final adelante = Duration(
                        milliseconds:
                            (_saltoConfigurado(SettingKey.arrowRight) * 1000)
                                .round());
                    final enPausa = !_c.isPlaying.value;
                    final casteando = _c.dlnaDevice.value != null;
                    // Transmitiendo y en pausa, saltar no va a ningun lado: el
                    // televisor no se mueve hasta que se reanude. Se dice corto
                    // y no se intenta el salto, en vez de mandar una orden que
                    // el aparato va a ignorar.
                    final noSePuedeSaltar = casteando && enPausa;
                    if (noSePuedeSaltar && dx < width * 2 && dx >= width) {
                      // El centro sigue pausando/reanudando aunque este pausado.
                      _c.playOrPause();
                      return;
                    }
                    if (noSePuedeSaltar) {
                      _mostrarAviso('video.paused-cant-skip'.i18n);
                      return;
                    }
                    if (dx < width) {
                      _c.seek(_c.position.value - atras);
                      _mostrarSalto(-atras.inSeconds);
                      // En pausa (mirando aca) la barra se mueve pero la imagen
                      // no, y sin decir nada parece que el salto no hizo efecto.
                      if (enPausa) _mostrarAviso('video.paused'.i18n);
                    } else if (dx > width * 2) {
                      _c.seek(_c.position.value + adelante);
                      _mostrarSalto(adelante.inSeconds);
                      if (enPausa) _mostrarAviso('video.paused'.i18n);
                    } else {
                      _c.playOrPause();
                      // Casteando no hace falta: el panel del centro ya dice si
                      // esta andando o en pausa, y repetirlo encima solo tapa.
                      // Estaba andando, asi que este toque lo pausa.
                      if (!enPausa && !casteando) {
                        _mostrarAviso('video.paused'.i18n);
                      }
                    }
                  },
                  // Deslizar vertical = volumen, en cualquier parte de la
                  // pantalla — a pedido explícito, el reproductor ya no toca
                  // el brillo del sistema (antes la mitad izquierda lo hacía).
                  // Se ignora con más de un dedo apoyado (pellizcar) — sin
                  // esto, un pellizco (que no debe hacer nada, no hay zoom por
                  // pellizco) igual subía/bajaba el volumen con el movimiento
                  // de uno de los 2 dedos.
                  // Arrastrar de lado mueve la camara del VR.
                  //
                  // No pisa nada de lo que ya habia: el vertical es el volumen
                  // y el toque suelto pausa. Este gesto solo existe con el modo
                  // VR puesto; sin el, arrastrar de lado no hacia nada y sigue
                  // sin hacerlo.
                  //
                  // El desplazamiento va en fraccion del ancho de la pantalla,
                  // asi el recorrido se siente igual en un telefono chico que
                  // en una tablet. Negativo porque arrastrar hacia la izquierda
                  // tiene que mover la vista hacia la derecha, como al empujar
                  // una foto.
                  onHorizontalDragUpdate: (details) {
                    if (_activePointers > 1) return;
                    if (!_c.vrUnaPantalla.value) return;
                    final ancho = MediaQuery.of(context).size.width;
                    if (ancho <= 0) return;
                    _c.moverVr(-details.delta.dx / ancho);
                  },
                  // El numero sale APENAS se apoya el dedo, con el volumen que
                  // hay en ese momento.
                  //
                  // Antes se prendia en el primer onVerticalDragUpdate, y ese
                  // no llega hasta que el dedo recorrio el umbral de arrastre
                  // de Flutter (~18 px): para cuando aparecia el cartel el
                  // volumen YA se habia movido, asi que nunca se llegaba a ver
                  // de cuanto se partia ni se entendia cuanto estaba subiendo.
                  onVerticalDragStart: (details) {
                    if (_activePointers > 1) return;
                    // Transmitiendo manda el aviso del aparato, que es otro.
                    if (_c.dlnaDevice.value != null) return;
                    _isAdjusting = true;
                    setState(() {});
                  },
                  onVerticalDragUpdate: (details) {
                    if (_activePointers > 1) return;
                    final add = details.delta.dy / 500;
                    // Transmitiendo, el volumen que importa es el del APARATO.
                    // El del telefono no sale por ningun lado, porque el sonido
                    // lo esta haciendo el televisor.
                    if (_c.dlnaDevice.value != null) {
                      _c.ajustarVolumenCast(-add);
                      return;
                    }
                    // Dos tramos con un solo gesto: primero el volumen del
                    // teléfono y, una vez al tope, la amplificación del
                    // reproductor. Al bajar se recorren al revés — se baja
                    // primero la amplificación y recién después el sistema,
                    // porque si no bajar el volumen no haría nada audible
                    // hasta soltar todo el aumento.
                    if (add < 0 && _currentVolume >= 1) {
                      // Subiendo con el sistema ya al máximo: amplificar.
                      _boost = (_boost - add * 200)
                          .clamp(100.0, VideoPlayerController.volumenMaximo);
                      _c.player.setVolume(_boost);
                    } else if (add > 0 && _boost > 100) {
                      // Bajando y todavía amplificado: soltar el aumento.
                      _boost = (_boost - add * 200)
                          .clamp(100.0, VideoPlayerController.volumenMaximo);
                      _c.player.setVolume(_boost);
                    } else {
                      _currentVolume = (_currentVolume - add).clamp(0, 1);
                      VolumeController().setVolume(_currentVolume);
                    }
                    _isAdjusting = true;
                    setState(() {});
                  },
                  onVerticalDragEnd: (details) {
                    _isAdjusting = false;
                    setState(() {});
                  },
                  onLongPressStart: (details) {
                    _isLongPress = true;
                    // Transmitiendo se le pide al APARATO, que es quien esta
                    // reproduciendo. Arranca en x2 y sube tocando con otro dedo
                    // sin soltar (ver onPointerDown del Listener de arriba).
                    if (_c.dlnaDevice.value != null) {
                      unawaited(_c.pedirVelocidadCast(2));
                      setState(() {});
                      return;
                    }
                    _c.player.setRate(_velocidadSostenida);
                    setState(() {});
                  },
                  onLongPressEnd: (details) {
                    _isLongPress = false;
                    if (_c.dlnaDevice.value != null) {
                      // Al soltar vuelve a la normal, como el sostenido de aca.
                      unawaited(_c.pedirVelocidadCast(1));
                      setState(() {});
                      return;
                    }
                    _c.player.setRate(_c.currentSpeed.value);
                    setState(() {});
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // 中间显示
            Positioned.fill(
              child: Center(
                child: Obx(() {
                  // Casteando: esto va ANTES que todo lo demas.
                  //
                  // Mientras el video corre en el televisor, el reproductor de
                  // aca esta parado a proposito, asi que los avisos de carga y
                  // de buffer no describen nada real — y era justo eso lo que
                  // hacia aparecer la rueda girando al adelantar. En su lugar
                  // se muestra donde se esta viendo, y nada mas: los botones de
                  // reintentar y desconectar viven arriba, fuera del video.
                  if (_c.dlnaDevice.value != null) {
                    return _PanelCasteando(controller: _c);
                  }
                  if (_c.error.value.isNotEmpty) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Servidor no accesible.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          child: Text('common.retry'.i18n),
                          onPressed: () {
                            _c.error.value = '';
                            _c.play();
                          },
                        ),
                      ],
                    );
                  }
                  // Esperando que el usuario elija un servidor — no se
                  // prueba nada solo hasta que lo haga.
                  if (_c.awaitingServerChoice.value) {
                    return GestureDetector(
                      onTap: _c.currentServerName.value.isEmpty
                          ? null
                          : () => _c.switchServer(_c.currentServerName.value),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: HomeTheme.oscuroAcento
                                  .withValues(alpha: 0.18),
                              border: Border.all(color: HomeTheme.oscuroAcento),
                            ),
                            child: Icon(Icons.play_arrow,
                                color: HomeTheme.oscuroAcento, size: 36),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Tocá para reproducir el servidor elegido arriba',
                            style:
                                TextStyle(fontSize: 14, color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  // La extensión se cayó: no hay nada que reintentar.
                  //
                  // Va ANTES del aviso de servidor y del de carga, porque manda
                  // sobre los dos: el de servidor diría "probá otro", y los
                  // otros salen de la misma extensión que ya no está. Lo único
                  // útil acá es salir.
                  final caida = _c.extensionCaida.value;
                  if (caida != null) {
                    return AvisoExtensionCaida(
                      motivo: caida.i18n,
                      onSalir: () => unawaited(_c.closeRoute(context)),
                    );
                  }
                  if (!_c.isGettingWatchData.value) {
                    // Aviso estable de fallo de servidor (sin parpadeo): se
                    // muestra con fade y sin spinner encima.
                    final failMsg = _c.serverFailedMessage.value;
                    if (failMsg.isNotEmpty) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          key: const ValueKey('server-failed-mobile'),
                          margin: const EdgeInsets.symmetric(horizontal: 32),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.8),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Colors.orange, size: 26),
                                  const SizedBox(width: 14),
                                  Flexible(
                                    child: Text(
                                      failMsg,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_c.webViewFallback.value != null) ...[
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _openWebView,
                                  child:
                                      const Text('Volver al navegador interno'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                    // Mismo caso que en desktop: entre que el servidor abre y
                    // se pinta el primer cuadro, buffering puede no avisar
                    // nada (sobre todo HLS) y quedaba una pantalla negra sin
                    // spinner, como si estuviera trabada de verdad.
                    if (!_c.hasRenderedFrame.value) {
                      // Ver el mismo cambio en desktop: la capa de
                      // carga de arriba ya la muestra.
                      return const SizedBox.shrink();
                    }
                    return Builder(
                      builder: (context) {
                        // Pausado: nunca mostrar el spinner (mismo criterio
                        // que en desktop). mpv sigue llenando el buffer en
                        // pausa — eso está bien y la barra ya lo muestra —
                        // pero el spinner girando hacía parecer que el
                        // reproductor se trabó justo al pausar.
                        // isActuallyBuffering (no el flag crudo de mpv) ya
                        // descuenta los casos en que el video sigue avanzando
                        // de verdad pero el flag quedó pegado en true — ver
                        // VideoPlayerController.
                        if (_c.isActuallyBuffering.value &&
                            _c.isPlaying.value) {
                          return const SizedBox.shrink();
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  }

                  return Card(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: LayoutUtils.width * 0.8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_c.runtime.extension.icon != null)
                              Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                ),
                                clipBehavior: Clip.antiAlias,
                                margin: const EdgeInsets.only(right: 10),
                                child: CacheNetWorkImagePic(
                                  _c.runtime.extension.icon!,
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _c.runtime.extension.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'video.getting-streamlink'.i18n,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Devolución visual del doble toque: cuántos segundos se saltó y
            // hacia dónde.
            //
            // Va DESPUÉS del bloque del centro a propósito. Estaba antes, así
            // que al transmitir el panel de casteo —que ocupa el centro— se
            // dibujaba encima y el cartel quedaba tapado justo cuando más hacía
            // falta: al hacer doble toque mientras se castea, no se veía nada y
            // parecía que el gesto no había hecho efecto.
            //
            // IgnorePointer para no robar toques a la capa de gestos.
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                    // Del LADO que se toco, no en el medio.
                    //
                    // En el medio no dice nada de por si: el gesto es a un lado
                    // y la respuesta aparecia en el otro extremo de la pantalla,
                    // ademas de pelearse con lo que haya en el centro. Puesto
                    // donde cayo el dedo, se entiende sin leer.
                    alignment: Alignment(
                      (_saltoVisible ?? 0) < 0 ? -0.62 : 0.62,
                      0,
                    ),
                    child: AnimatedScale(
                      // Rebote corto: aparece de golpe y se asienta. Con solo la
                      // opacidad a 150ms el cartel se sentia lento justo cuando
                      // el gesto ya paso.
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutBack,
                      scale: _saltoVisible == null ? 0.85 : 1,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 90),
                        opacity: _saltoVisible == null ? 0 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xB3000000),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: HomeTheme.oscuroAcento),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (_saltoVisible ?? 0) < 0
                                    ? Icons.fast_rewind
                                    : Icons.fast_forward,
                                color: HomeTheme.oscuroAcento,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(_saltoVisible ?? 0).abs()} s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
              ),
            ),
            // Aviso corto arriba del centro ("Vídeo pausado"). Va aparte del
            // cartel de segundos porque los dos pueden salir a la vez: se
            // adelanta con el vídeo pausado y hacen falta las dos cosas.
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: const Alignment(0, -0.62),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _avisoCentro == null ? 0 : 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.pause_rounded,
                              size: 17, color: Colors.white),
                          const SizedBox(width: 7),
                          Text(
                            _avisoCentro ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Header y footer — se ocultan al tocar la pantalla y vuelven a
            // aparecer con otro toque (o solos a los 3s si estaban visibles).
            // IgnorePointer cuando están ocultos: evita que un botón invisible
            // siga siendo tocable.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Con "llenar pantalla" lo que se estira es el VIDEO,
                      // no los controles — a propósito. Se probó que el
                      // encabezado también subiera hasta arriba y quedaba
                      // mal: en un teléfono con cámara al medio, el título y
                      // la flecha de volver terminaban tapados/cortados por
                      // la propia cámara en vez de por un hueco vacío.
                      // SafeArea de siempre (sin condición ninguna) evita
                      // justo eso: reserva lo que haga falta para no chocar
                      // con la cámara, sea cual sea el modo del video.
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.zero,
                          child: Row(
                            children: [
                              // Volver, a pedido explícito ahora se oculta
                              // junto con el resto del header (antes estaba
                              // marcada como "siempre visible" a pedido
                              // anterior — se revirtió ese criterio).
                              SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ),
                      _Header(
                        controller: _c,
                      ),
                      // La tira de servidores ya no queda siempre visible
                      // tapando el video — a pedido explícito, ahora se abre
                      // bajo demanda desde el botón de servidor en el footer
                      // (ver SidebarTab.servers).
                    ],
                  ),
                ),
              ),
            ),
            // ── La flecha de volver SÍ se esconde, con el resto ────────────
            //
            // Este criterio ya fue y vino: estaba siempre visible, se pidió
            // ocultarla, se pidió que se quedara, y ahora que se oculte de
            // nuevo. Se anota para que nadie lo lea como un descuido.
            //
            // Lo que cambió NO es el gusto, es la condición. El motivo para que
            // se quedara era sólido: con los controles ocultos —se ocultan
            // solos a los pocos segundos— y **sin barra del sistema**, era la
            // única salida visible de la pantalla.
            //
            // Ahora las barras del sistema ya no se esconden nunca (ver
            // `pantallaSegunOrientacion`), así que el gesto de atrás está
            // siempre disponible y la pantalla nunca queda sin salida. Recién
            // con esa condición cumplida la flecha puede desvanecerse.
            //
            // **Las dos cosas van juntas.** Si algún día se vuelve a esconder
            // las barras del sistema, esta flecha tiene que volver a quedarse
            // fija o el reproductor queda sin salida visible.
            Positioned(
              top: 0,
              left: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  // El mismo desvanecido que el resto de los controles, para
                  // que se vayan juntos en vez de irse los demás y quedar la
                  // flecha sola un instante.
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  // Misma idea que el encabezado: sin condición, para que
                  // la flecha nunca quede tapada por la cámara.
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: DecoratedBox(
                        // Un fondo redondo detrás: la flecha sola, blanca, se
                        // pierde sobre una escena clara, y ahora que se queda
                        // encima del vídeo todo el tiempo tiene que leerse sobre
                        // cualquier cosa.
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          iconSize: 22,
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => unawaited(_c.closeRoute(context)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  // Con "llenar pantalla" de pie el video pasa a edgeToEdge
                  // (ver pantallaSegunOrientacion) y este pie, que vive a
                  // bottom:0, pasó a caer FÍSICAMENTE atrás de los botones
                  // de navegación del teléfono en vez de arriba de ellos —
                  // reportado en vivo con captura, la barra de progreso
                  // quedaba tapada. bottom:true reserva ese alto solo
                  // cuando de verdad hace falta (viewPadding.bottom vale 0
                  // en el modo reservado de siempre, así que acá no cambia
                  // nada).
                  child: SafeArea(
                    top: false,
                    child: _Footer(controller: _c),
                  ),
                ),
              ),
            ),
            // ── Botón grande de pausa/play, en el centro ────────────────────
            //
            // Antes la única forma de pausar era doble toque en el tercio
            // del medio — funciona, pero no hay ningún botón que lo diga: a
            // pedido explícito, un solo toque (el mismo que muestra el resto
            // de los controles) también deja un botón grande y visible que
            // pausa/reanuda al tocarlo, y se esconde junto con todo lo demás.
            // El doble toque para pausar/saltar SIGUE andando igual — esto
            // se suma, no lo reemplaza.
            //
            // Nada de esto transmitiendo: casteando el centro ya lo ocupa
            // _PanelCasteando con su propio estado de play/pausa (ver más
            // arriba, "中间显示"), y este botón encima solo taparía eso.
            Positioned.fill(
              child: Obx(() {
                if (_c.dlnaDevice.value != null) return const SizedBox.shrink();
                return IgnorePointer(
                  ignoring: !_showControls,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _BotonCentralDePausa(controller: _c),
                    ),
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: Obx(
                () {
                  if (!_c.showSidebar.value) {
                    return const SizedBox.shrink();
                  }
                  return GestureDetector(
                    child: Container(
                      color: Colors.black54,
                    ),
                    onTap: () {
                      _c.showSidebar.value = false;
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

/// Lo que se ve en el medio mientras el video corre en otro aparato.
///
/// No lleva botones a proposito: reintentar y desconectar viven en la barra de
/// arriba. Antes estaban aca en el medio, tapando el centro de la pantalla, que
/// es justo donde uno toca para pausar.
class _PanelCasteando extends StatefulWidget {
  const _PanelCasteando({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_PanelCasteando> createState() => _PanelCasteandoState();
}

class _PanelCasteandoState extends State<_PanelCasteando>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    // 2,7 s para tres pistas: ~900 ms en cada una, igual que en PC.
    duration: const Duration(milliseconds: 2700),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  VideoPlayerController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    // IgnorePointer: el panel esta ENCIMA del detector de gestos, asi que su
    // caja se comia los toques justo en el centro de la pantalla — que es donde
    // el propio panel dice que hay que tocar para pausar.
    return IgnorePointer(child: _contenido());
  }

  Widget _contenido() {
    return Obx(() {
      final device = controller.dlnaDevice.value;
      if (device == null) return const SizedBox.shrink();
      // Enganchando: mandarle el video al aparato y que arranque puede tardar
      // varios segundos, y en ese rato no se veia nada — parecia que el toque
      // no habia hecho efecto.
      final cambiandoEpisodio = controller.castCambiandoEpisodio.value;
      final buscando = controller.castBuscando.value;
      // "conectando" tambien enciende la rueda: buscar un momento del video en
      // el aparato es otra espera, y se muestra igual.
      // castEsperandoPlay: el aparato ya acepto pero todavia no se ve nada.
      // Aceptar y empezar a reproducir son dos cosas distintas.
      final conectando = controller.castConectando.value ||
          controller.castEsperandoPlay.value ||
          cambiandoEpisodio ||
          buscando;
      final reproduciendo = controller.isPlaying.value;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conectando)
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(HomeTheme.oscuroAcento),
                ),
              )
            else
              Icon(
                reproduciendo
                    ? Icons.cast_connected
                    : Icons.pause_circle_outline,
                size: 44,
                color: HomeTheme.oscuroAcento,
              ),
            const SizedBox(height: 14),
            Text(
              device.nombre,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            // Un aviso puntual (por ejemplo, que no se puede saltar porque
            // esta pausado) reemplaza al estado por un momento, resaltado. Asi
            // todo lo que el usuario necesita leer esta en el mismo lugar.
            Builder(builder: (context) {
              final aviso = controller.castAviso.value;
              // Acelerado DESDE el aparato: la barra corre distinto y sin
              // decirlo no se entiende por que.
              final velocidad = controller.castVelocidad.value;
              final estado = cambiandoEpisodio
                  ? 'video.cast-changing-episode'.i18n
                  : buscando
                      ? 'video.cast-seeking'.i18n
                      : conectando
                          ? 'video.cast-connecting'.i18n
                          : !reproduciendo
                              ? 'video.cast-paused-here'.i18n
                              : velocidad != null
                                  ? FlutterI18n.translate(
                                      context,
                                      'video.cast-speed',
                                      translationParams: {'speed': velocidad},
                                    )
                                  : 'video.cast-on-device'.i18n;
              return Text(
                aviso ?? estado,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight:
                      aviso == null ? FontWeight.normal : FontWeight.w700,
                  color: aviso == null
                      ? Colors.white.withValues(alpha: 0.75)
                      : HomeTheme.oscuroAcento,
                ),
              );
            }),
            // La ayuda de gestos, dibujada y animada en vez de explicada en un
            // parrafo. Un renglon largo diciendo "toca el centro para pausar y
            // los costados para adelantar" se lee una vez y estorba siempre;
            // tres iconos que laten se entienden de un vistazo.
            //
            // Solo cuando ya esta transmitiendo: mientras engancha no hay nada
            // que controlar todavia.
            if (!conectando) ...[
              const SizedBox(height: 18),
              _AyudaGestosCast(anim: _anim),
              const SizedBox(height: 8),
              // Sin esto los tres iconos no dicen COMO se activan, y un toque
              // solo no hace nada de eso: muestra los controles.
              Text(
                'video.cast-hint-doubletap'.i18n,
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Tres pistas que laten por turno: retroceder, pausar, adelantar.
class _AyudaGestosCast extends StatelessWidget {
  const _AyudaGestosCast({required this.anim});
  final AnimationController anim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        // Cada pista se ilumina en su tercio del ciclo, de izquierda a derecha,
        // que es el orden en que estan en la pantalla.
        // La luz se DESLIZA, no salta: una sola posicion que avanza de forma
        // continua, y cada pista se ilumina segun lo cerca que este de ella.
        final aguja = anim.value * 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pista(Icons.replay_10_rounded, 'video.cast-hint-back'.i18n,
                _cerca(aguja, 0, 3)),
            const SizedBox(width: 14),
            _pista(Icons.touch_app_rounded, 'video.cast-hint-pause'.i18n,
                _cerca(aguja, 1, 3)),
            const SizedBox(width: 14),
            _pista(Icons.forward_10_rounded, 'video.cast-hint-forward'.i18n,
                _cerca(aguja, 2, 3)),
          ],
        );
      },
    );
  }

  /// Que tan iluminada va una pista, de 0 a 1, segun la distancia a la aguja.
  ///
  /// El ciclo da la vuelta, asi que la ultima y la primera tambien son
  /// vecinas: sin eso, al cerrar la vuelta la luz pegaba un salto de un
  /// extremo al otro.
  static double _cerca(double aguja, int indice, int total) {
    var d = (aguja - indice).abs();
    if (d > total / 2) d = total - d;
    return (1 - d).clamp(0.0, 1.0);
  }

  Widget _pista(IconData icono, String texto, double luz) {
    // Sin AnimatedScale ni AnimatedOpacity: animan por su cuenta hacia un valor
    // nuevo, y encima de una animacion continua se pisaban y tironeaban.
    return Transform.scale(
      scale: 0.9 + 0.1 * luz,
      child: Opacity(
        opacity: 0.45 + 0.55 * luz,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.06),
                  HomeTheme.oscuroAcento.withValues(alpha: 0.22),
                  luz,
                ),
                border: Border.all(
                  color: Color.lerp(
                    Colors.white.withValues(alpha: 0.16),
                    HomeTheme.oscuroAcento,
                    luz,
                  )!,
                ),
              ),
              child: Icon(icono, size: 19, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              texto,
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final VideoPlayerController controller;

  Future<void> _confirmarDesconectar(BuildContext context) async {
    final aparato = controller.dlnaDevice.value;
    if (aparato == null) return;
    final corta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('video.cast-disconnect-title'.i18n),
        content: Text(
          FlutterI18n.translate(
            context,
            'video.cast-disconnect-confirm',
            translationParams: {'device': aparato.nombre},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.i18n),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.disconnect'.i18n),
          ),
        ],
      ),
    );
    if (corta == true) controller.disconnectDLNADevice();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // 0.85 (antes black54, ~33%) — contra un video claro se leían mal el
      // título/episodio y los íconos; con esto se ven bien sea cual sea el
      // contenido de fondo.
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // La flecha de volver NO va acá.
          //
          // Vive aparte, fuera del desvanecido del encabezado, para que no se
          // esconda con los controles (ver el Positioned de siempre-visible en
          // _VideoPlayerMobileControls). Al agregarla allá quedó duplicada: dos
          // flechas pegadas, una que se desvanecía y otra que no.
          //
          // Se deja el hueco que ocupaba para que el título no arranque contra
          // el borde y siga alineado con la flecha de al lado.
          const SizedBox(width: 52),
          Expanded(
            child: Obx(() {
              // Sin comprobar el índice, esto reventaba con un
              // "RangeError (length): Valid value range is empty: 0" ENCIMA del
              // vídeo, tapando el aviso de qué había pasado de verdad.
              //
              // Pasa cuando la ficha no tiene episodios: una entrada del
              // historial cuya página ya no existe abre el reproductor con la
              // lista vacía. El error real —"no se pudo cargar el episodio"— ya
              // se muestra abajo; este solo lo tapaba y encima parecía un fallo
              // del reproductor.
              final lista = controller.playList;
              final i = controller.index.value;
              final episode = (i >= 0 && i < lista.length) ? lista[i].name : '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    episode,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            }),
          ),
          // DLNA
          // Apagado mientras el reproductor nativo no este andando: el
          // televisor pide el mismo video por su cuenta y se topa con lo mismo,
          // asi que ofrecerlo igual solo termina en pantalla negra alla. Se
          // avisa el motivo al tocarlo. Ver puedeCastear en el controlador.
          Obx(() {
            // Todavia abriendo el video: el boton NO se dibuja. Antes se
            // dibujaba apagado y cada toque escupia un aviso, asi que tocarlo
            // tres veces mientras cargaba dejaba tres encimados. Ver
            // mostrarBotonDeCast en el controlador.
            if (!controller.mostrarBotonDeCast) {
              return const SizedBox.shrink();
            }
            // Casteando: reintentar y desconectar, arriba y fuera del video.
            // Antes estaban en el medio de la pantalla, encima de la imagen y
            // justo donde se toca para pausar.
            if (controller.dlnaDevice.value != null) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bloqueado mientras reintenta: tocarlo de nuevo no encola
                  // otro intento, y sin apagarlo no se notaba que ya estaba
                  // trabajando.
                  IconButton(
                    tooltip: 'common.retry'.i18n,
                    icon: Icon(
                      Icons.refresh,
                      color: controller.castConectando.value
                          ? Colors.white.withAlpha(90)
                          : Colors.white,
                    ),
                    onPressed: controller.castConectando.value
                        ? null
                        : () => controller.reintentarCast(),
                  ),
                  // Pregunta antes de cortar: es un icono chico al lado de
                  // otros, y tocarlo por error dejaba la pantalla grande sin
                  // nada en el medio de un episodio.
                  IconButton(
                    tooltip: 'common.disconnect'.i18n,
                    icon: Icon(Icons.cast_connected,
                        color: HomeTheme.oscuroAcento),
                    onPressed: () => _confirmarDesconectar(context),
                  ),
                ],
              );
            }
            if (!controller.puedeCastear) {
              return IconButton(
                icon: Icon(Icons.cast, color: Colors.white.withAlpha(90)),
                onPressed: () => controller.sendMessage(
                  Message(Text(controller.motivoSinCast)),
                ),
              );
            }
            return IconButton(
              icon: const Icon(Icons.cast),
              onPressed: () {
                // Se pausa al abrir la lista: elegir aparato lleva unos
                // segundos y el episodio seguia corriendo detras, asi que uno
                // volvia habiendose perdido un pedazo. Al elegir, el casteo
                // para el reproductor de aca igual; si se cierra sin elegir,
                // queda pausado y con un toque sigue.
                controller.safePause();
                showModalBottomSheet(
                  context: context,
                  useSafeArea: true,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (context) {
                    return DraggableScrollableSheet(
                      expand: false,
                      builder: (context, scrollController) {
                        return SingleChildScrollView(
                          controller: scrollController,
                          child: VideoPlayerCast(
                            onDeviceSelected: (device) {
                              controller.connectDLNADevice(device);
                              Get.back();
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          }),
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              controller.toggleSideBar(SidebarTab.settings);
            },
          ),
        ],
      ),
    );
  }
}

/// El botón grande de pausa/play del centro. Ver dónde se usa para el porqué.
class _BotonCentralDePausa extends StatelessWidget {
  const _BotonCentralDePausa({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final reproduciendo = controller.isPlaying.value;
      return DecoratedBox(
        // Mismo criterio que la flecha de volver: un fondo redondo detrás
        // para que se lea sobre cualquier escena, clara u oscura.
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
        ),
        child: IconButton(
          iconSize: 44,
          icon: Icon(
            reproduciendo ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
          ),
          onPressed: controller.playOrPause,
        ),
      );
    });
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 0.85 (antes black54, ~33%) — los minutos/botones se leían mal
      // contra un video claro; con esto quedan legibles siempre.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SeekBar(controller: controller),
          const SizedBox(height: 10),
          // Scrolleable horizontal: cuando el sidebar (ajustes/calidad/etc.)
          // está abierto, le saca 300px de ancho al video — sin esto, esta
          // fila (que no tiene ningún hijo flexible salvo el Spacer) podía
          // desbordar por unos pixeles en vez de simplemente dejar scrollear
          // hasta los botones de la derecha.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bloqueado mientras carga, para no disparar otro cambio de
                // episodio encima de uno ya en curso.
                Obx(
                  () => IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: controller.index.value > 0 &&
                            !controller.isGettingWatchData.value
                        ? () {
                            if (controller.index.value > 0) {
                              controller.index.value--;
                            }
                          }
                        : null,
                  ),
                ),
                Obx(() {
                  // Resolviendo el servidor elegido — bloquear el botón para
                  // no permitir otro toque/doble intento mientras carga.
                  if (controller.isGettingWatchData.value) {
                    return IconButton(
                      onPressed: null,
                      icon: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: HomeTheme.oscuroAcento,
                        ),
                      ),
                    );
                  }
                  if (controller.awaitingServerChoice.value) {
                    return IconButton(
                      onPressed: controller.currentServerName.value.isEmpty
                          ? null
                          : () => controller
                              .switchServer(controller.currentServerName.value),
                      icon: const Icon(Icons.play_arrow, size: 30),
                    );
                  }
                  // El servidor falló (no se pudo reproducir nativo) — no hay
                  // nada cargado para pausar/reproducir, se bloquea en vez de
                  // dejarlo tocable sin efecto.
                  if (controller.serverFailedMessage.value.isNotEmpty) {
                    return const IconButton(
                      onPressed: null,
                      icon: Icon(Icons.play_arrow, size: 30),
                    );
                  }
                  // Mientras engancha con el aparato no hay a quien mandarle
                  // nada todavia.
                  if (controller.castConectando.value) {
                    return const IconButton(
                      onPressed: null,
                      icon: Icon(Icons.play_arrow, size: 30),
                    );
                  }
                  if (controller.isPlaying.value) {
                    return IconButton(
                      onPressed: controller.playOrPause,
                      icon: const Icon(Icons.pause, size: 30),
                    );
                  }
                  return IconButton(
                    onPressed: controller.playOrPause,
                    icon: const Icon(Icons.play_arrow, size: 30),
                  );
                }),
                // Bloqueado mientras carga.
                Obx(
                  () => IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: controller.playList.length - 1 >
                                controller.index.value &&
                            !controller.isGettingWatchData.value
                        ? () {
                            if (controller.index.value <
                                controller.playList.length - 1) {
                              controller.index.value++;
                            }
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                // 播放进度
                Obx(() {
                  final position = controller.position.value;
                  return Text(
                    '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  );
                }),
                const Text('/'),
                Obx(() {
                  final duration = controller.duration.value;
                  return Text(
                    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  );
                }),
                // Spacer (antes) necesita ancho acotado — no funciona dentro
                // de un SingleChildScrollView horizontal (ancho no acotado a
                // propósito, para que esta fila nunca desborde). Un hueco fijo
                // en su lugar; se pierde que el grupo de la derecha quede
                // siempre pegado al borde, pero elimina el overflow de raíz.
                const SizedBox(width: 24),
                Obx(() {
                  if (controller.currentQuality.value.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return FilledButton.tonal(
                    onPressed: () {
                      // Ver hayCalidades: las calidades pueden venir del
                      // playlist HLS o de la cabecera X-Servers de la
                      // extensión. Mirando solo el primero, este botón decía
                      // "no hay calidades" en vídeos que traen siete, y en el
                      // teléfono es la única forma de cambiarla.
                      if (!controller.hayCalidades) {
                        controller.sendMessage(
                          Message(
                            Text(
                              'video.no-qualities'.i18n,
                            ),
                          ),
                        );
                        return;
                      }
                      controller.toggleSideBar(controller.pestanaDeCalidad);
                    },
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                      ),
                    ),
                    child: Text(
                      controller.currentQuality.value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 10),
                // Speed selector — chip with visible background for tap affordance
                Obx(
                  () => PopupMenuButton<double>(
                    initialValue: controller.currentSpeed.value,
                    onSelected: (value) {
                      controller.currentSpeed.value = value;
                    },
                    itemBuilder: (context) => [
                      for (final speed in controller.speedList)
                        PopupMenuItem(
                          value: speed,
                          child: Text('${speed}x'),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${controller.currentSpeed.value}x',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                // torrent files
                const SizedBox(width: 10),
                Obx(() {
                  if (controller.torrentMediaFileList.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    onPressed: () {
                      controller.toggleSideBar(SidebarTab.torrentFiles);
                    },
                    icon: const Icon(Icons.video_file),
                  );
                }),
                // Servidores — antes era una tira de pestañas siempre
                // visible tapando el video; a pedido explícito ahora se
                // esconde detrás de este botón, igual que calidad/pistas.
                Obx(() {
                  // Ver servidoresSonAparte: con las extensiones que entregan
                  // un MP4 por resolución, este botón y el de calidad abrían la
                  // MISMA lista. Quedaban dos botones pegados haciendo lo
                  // mismo, uno de ellos sin decir de qué era.
                  if (!controller.servidoresSonAparte) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    onPressed: () {
                      controller.toggleSideBar(SidebarTab.servers);
                    },
                    icon: const Icon(Icons.dns),
                  );
                }),
                IconButton(
                  onPressed: () {
                    controller.toggleSideBar(SidebarTab.tracks);
                  },
                  icon: const Icon(
                    Icons.subtitles,
                  ),
                ),
                // 播放列表
                IconButton(
                  icon: const Icon(Icons.playlist_play),
                  onPressed: () {
                    controller.toggleSideBar(SidebarTab.episodes);
                  },
                ),
                // ── Pantalla completa manual ─────────────────────────────
                //
                // Las barras del sistema se dejan siempre visibles por
                // defecto (ver pantallaSegunOrientacion). Este botón es la
                // excepción a propósito: quien quiere inmersión total —sin
                // hora ni batería— la pide tocando acá, en vez de que la app
                // se la imponga.
                Obx(
                  () => IconButton(
                    tooltip: controller.pantallaCompletaAndroid.value
                        ? 'video.exit-fullscreen'.i18n
                        : 'video.fullscreen'.i18n,
                    icon: Icon(
                      controller.pantallaCompletaAndroid.value
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                    onPressed: controller.alternarPantallaCompletaAndroid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  bool _isSliderDraging = false;
  Duration _position = Duration.zero;
  Duration _buffer = Duration.zero;

  Worker? _vigiaDelBuffer;

  @override
  void initState() {
    super.initState();
    // Del CONTROLADOR y no de mpv directo: casteando, el reproductor de acá está
    // parado y su buffer es cero, así que la sombra de descarga desaparecía de
    // la barra aunque el televisor estuviera cargando. Mismo criterio que en la
    // barra de escritorio.
    _buffer = widget.controller.buffer.value;
    _vigiaDelBuffer = ever(widget.controller.buffer, (Duration valor) {
      if (!mounted) return;
      setState(() {
        _buffer = valor;
      });
    });
  }

  @override
  dispose() {
    _vigiaDelBuffer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 40 dp tall so the thumb sits in a comfortable 40×full-width touch zone;
    // visually the track is still slim (3 dp) to match the player aesthetic.
    return SizedBox(
      height: 40,
      child: SliderTheme(
        data: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: Obx(
          () {
            final duration = widget.controller.duration.value.inMilliseconds;
            int position = widget.controller.position.value.inMilliseconds;
            if (_isSliderDraging) {
              position = _position.inMilliseconds;
            }

            return Slider(
              min: 0,
              max: duration.toDouble(),
              value: clampDouble(
                position.toDouble(),
                0,
                duration.toDouble(),
              ),
              secondaryTrackValue: clampDouble(
                _buffer.inMilliseconds.toDouble(),
                0,
                duration.toDouble(),
              ),
              onChanged: (value) {
                if (_isSliderDraging) {
                  setState(() {
                    _position = Duration(milliseconds: value.toInt());
                  });
                }
              },
              onChangeStart: (value) {
                _position = Duration(milliseconds: value.toInt());
                _isSliderDraging = true;
              },
              onChangeEnd: (value) {
                if (_isSliderDraging) {
                  widget.controller.seek(
                    Duration(milliseconds: value.toInt()),
                  );
                  _isSliderDraging = false;
                }
              },
            );
          },
        ),
      ),
    );
  }
}
