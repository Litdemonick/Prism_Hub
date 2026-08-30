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
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/watch/aviso_extension_caida.dart';

class VideoPlayerMobileControls extends StatefulWidget {
  const VideoPlayerMobileControls({super.key, required this.controller});
  final VideoPlayerController controller;

  @override
  State<VideoPlayerMobileControls> createState() =>
      _VideoPlayerMobileControlsState();
}

class _VideoPlayerMobileControlsState extends State<VideoPlayerMobileControls> {
  late final VideoPlayerController _c = widget.controller;
  bool _showControls = true;
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
  // (que el usuario espera que no haga nada, no hay zoom por pellizco) igual
  // disparaba los gestos de un solo dedo (mover la cámara VR, etc.) con el
  // movimiento de uno de los 2.
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
    ).then((_) {
      // Tocar fuera del cartel —o el botón atrás— también cuenta como
      // cancelar.
      //
      // Sin esto el diálogo se cerraba y nadie contestaba: `resumePrompt`
      // quedaba con valor, el vídeo pausado a propósito esperando una
      // respuesta que ya no iba a llegar, y el reproductor sin forma de salir
      // de ahí salvo cerrar y volver a entrar.
      //
      // Se comprueba que siga pendiente para no pisar la respuesta de los
      // botones: los dos hacen `pop()`, así que este `then` corre igual
      // después de ellos.
      if (!mounted) return;
      if (_c.resumePrompt.value != null) _c.cancelResume();
    });
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
                      opacity: _c.ruedaGirando ? 1 : 0,
                      child: const Center(
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
                    }
                    // El tercio del CENTRO ya no pausa con doble toque.
                    //
                    // Para eso está el botón grande de pausa, que cae justo
                    // ahí: quedaban dos formas de pausar en el mismo sitio y la
                    // del doble toque se disparaba sin querer al intentar
                    // saltar cerca del medio. Los tercios de los costados
                    // siguen igual — ahí el doble toque es el único atajo de
                    // salto que hay en el teléfono.
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
                    final ancho = MediaQuery.sizeOf(context).width;
                    if (ancho <= 0) return;
                    _c.moverVr(-details.delta.dx / ancho);
                  },
                  // Deslizar arriba/abajo para el volumen se saca — a pedido
                  // explícito, ahora hay un control de volumen propio (ver
                  // _VolumeButtonMobile en el pie) que además se ve, en vez
                  // de un gesto invisible que había que descubrir.
                  onLongPressStart: (details) {
                    _isLongPress = true;
                    _c.player.setRate(_velocidadSostenida);
                    setState(() {});
                  },
                  onLongPressEnd: (details) {
                    _isLongPress = false;
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
                            child: const Icon(Icons.play_arrow,
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
            // Va DESPUÉS del bloque del centro a propósito: lo que se dibuja
            // ahí ocupa el mismo sitio y taparía este cartel.
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
                      // Acá había un SafeArea vacío haciendo de separador, que
                      // empujaba TODO el encabezado hacia abajo: con "llenar
                      // pantalla" el vídeo pasaba a dibujarse hasta el borde
                      // pero la barra no, y quedaba una franja de vídeo suelta
                      // por encima de ella (reportado en vivo con captura).
                      //
                      // Ahora el hueco lo reserva el propio _Header como
                      // relleno de arriba, no un separador aparte. Es la misma
                      // distancia, pero del lado de adentro: el degradado
                      // arranca en el borde de la pantalla —así no queda esa
                      // franja— y el título y los íconos siguen cayendo por
                      // debajo de la cámara, que es lo que este SafeArea
                      // cuidaba y sigue cuidado.
                      // Listener transparente (deferToChild por defecto: no
                      // compite por el gesto, solo escucha) — mientras se
                      // toca o arrastra algo del header, se reinicia el
                      // temporizador de auto-ocultado en cada evento, para
                      // que no se esconda a mitad de una interacción.
                      Listener(
                        onPointerDown: (_) => _updateTimer(),
                        onPointerMove: (_) => _updateTimer(),
                        child: _Header(
                          controller: _c,
                        ),
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
                  //
                  // left:false, right:false EXPLÍCITO: sin esto, SafeArea
                  // los deja en true por defecto y en horizontal —donde la
                  // cámara mete un relleno de MediaQuery.padding a un
                  // costado— el pie quedaba angosto por ese lado, con la
                  // barra de progreso y su sombra cortadas antes de llegar
                  // al borde de verdad. Este Positioned ya está en
                  // left:0/right:0 a propósito (ver arriba): es el ancho
                  // completo que se busca, sin que SafeArea se lo achique.
                  child: SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    // Mismo Listener transparente que el header, para que
                    // arrastrar la barra de progreso o la de volumen no se
                    // corte por el auto-ocultado a mitad de camino.
                    child: Listener(
                      onPointerDown: (_) => _updateTimer(),
                      onPointerMove: (_) => _updateTimer(),
                      child: _Footer(controller: _c),
                    ),
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
            // No mientras se está resolviendo el servidor
            // (isGettingWatchData, el cartel "Obteniendo enlace..." con su
            // rueda) — ahí todavía no hay nada que pausar, y el botón
            // aparecía flotando encima de esa rueda sin hacer nada útil.
            Positioned.fill(
              child: Obx(() {
                if (_c.isGettingWatchData.value ||
                    // Ni mientras gira la rueda: los dos se dibujan en el
                    // centro exacto, así que se veían encimados. Un
                    // reproductor de verdad muestra una cosa o la otra.
                    _c.ruedaGirando ||
                    // Ni cuando el centro ya tiene su propio cartel con su
                    // botón: el de «Tocá para reproducir el servidor elegido»,
                    // el de un servidor que falló y el de error. Los tres
                    // dibujan un botón en el mismo sitio, así que este quedaba
                    // ENCIMA del de ellos —se veían los dos superpuestos— y
                    // encima no hay nada que pausar todavía.
                    _c.awaitingServerChoice.value ||
                    _c.serverFailedMessage.value.isNotEmpty ||
                    _c.error.value.isNotEmpty ||
                    _c.extensionCaida.value != null) {
                  return const SizedBox.shrink();
                }
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

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final VideoPlayerController controller;

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
      // El relleno de arriba se suma al alto que reserva el sistema (barra de
      // estado o cámara). El degradado, que es el fondo de este Container,
      // arranca igual en el borde de la pantalla — ver el comentario del
      // separador que se sacó en _VideoPlayerMobileControls.
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 10,
        top: 10 + MediaQuery.paddingOf(context).top,
      ),
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

/// El control de volumen del pie en Android — reemplaza al gesto de
/// deslizar arriba/abajo en cualquier parte de la pantalla (invisible, sin
/// ninguna pista de que existía).
///
/// SIEMPRE visible, no escondida atrás de un botón — a pedido explícito:
/// con el menú de antes había que abrirlo para ver o cambiar el volumen, y
/// ADEMÁS no se actualizaba mientras estaba abierto (PopupMenuButton arma
/// su contenido una sola vez al abrirse; volver a pedirle que se repinte
/// no alcanza porque el valor que usaba había quedado fijo en una variable
/// capturada en ese momento — para ver el cambio de verdad había que
/// cerrarlo y abrirlo de nuevo). Puesta siempre en el pie, como el resto
/// de los controles, se repinta con Obx igual que cualquier otra cosa acá.
///
/// Mismo tope que en escritorio (VideoPlayerController.volumenMaximo, no
/// 100): pasado el volumen original de la pista, sigue subiendo
/// amplificando desde el reproductor.
class _VolumeButtonMobile extends StatefulWidget {
  const _VolumeButtonMobile({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_VolumeButtonMobile> createState() => _VolumeButtonMobileState();
}

class _VolumeButtonMobileState extends State<_VolumeButtonMobile> {
  late double _volumen = widget.controller.player.state.volume;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    // Sincronizado con el volumen real: si cambia por otro lado (calidad
    // nueva que reinicia el player, etc.) el ícono no se queda mostrando
    // un valor viejo.
    _sub = widget.controller.player.stream.volume.listen((v) {
      if (mounted) setState(() => _volumen = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  IconData _iconoPara(double valor, double tope) {
    if (valor <= 0) return Icons.volume_off_rounded;
    if (valor < tope * 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  /// A cuánto volver al des-silenciar. Se guarda al silenciar en vez de
  /// mirar el valor actual —que ya es 0— para devolver exactamente el que
  /// había, incluso si estaba amplificado por encima de 100.
  double _volumenAntesDeSilenciar = 100;

  @override
  Widget build(BuildContext context) {
    // ── Sin Obx: acá no hay nada observable que mirar ──────────────────
    //
    // Este bloque leía `_volumen`, que es un campo normal de este widget y se
    // actualiza con setState. Un Obx que no lee ninguna variable observable no
    // tiene a qué suscribirse, y GetX lo detecta y lanza — Flutter reemplaza
    // el trozo por su pantalla de error y lo vuelve a intentar en cada cuadro,
    // así que salía un recuadro rojo encima del reproductor y el registro se
    // llenaba de la misma línea decenas de veces por segundo.
    //
    // Visto en el registro de un teléfono: «[Get] the improper use of a GetX
    // has been detected», repetida cada 8 ms desde el momento en que se abre
    // el reproductor.
    final valor = _volumen;
    const tope = VideoPlayerController.volumenMaximo;

    void cambiar(double nuevo) {
      widget.controller.player.setVolume(nuevo);
      setState(() => _volumen = nuevo);
    }

    // Silencia y des-silencia con un toque en la bocina, a pedido
    // explícito: antes el ícono era decorativo y bajar a cero obligaba a
    // arrastrar la barra hasta el fondo y después volver a buscar el punto
    // donde estaba.
    void alternarSilencio() {
      if (valor > 0) {
        _volumenAntesDeSilenciar = valor;
        cambiar(0);
        return;
      }
      // Clamp al tope de ESTE momento: se puede haber silenciado con el
      // volumen local amplificado (hasta 200) y des-silenciar ya
      // transmitiendo, donde el máximo del aparato es 100.
      final volver =
          _volumenAntesDeSilenciar > 0 ? _volumenAntesDeSilenciar : 100.0;
      cambiar(volver.clamp(0, tope));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // InkWell y no IconButton: el botón de Material reserva 48px de
        // ancho mínimo y esta fila ya venía justa de espacio (ver el
        // comentario del orden de los botones en _Footer). Con este
        // relleno el objetivo queda en 34px, cómodo de tocar, sin sumar
        // los 26 extra que empujarían de nuevo a pantalla completa.
        InkWell(
          onTap: alternarSilencio,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(_iconoPara(valor, tope), size: 22),
          ),
        ),
        // Más ancha y con más área de agarre que un slider de Material
        // por defecto — a pedido explícito: en un teléfono, con el dedo
        // encima del video, el thumb chico era difícil de acertar y de
        // arrastrar con precisión.
        SizedBox(
          width: 150,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: valor.clamp(0, tope),
              max: tope,
              label: '${valor.round()}%',
              onChanged: cambiar,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${valor.round()}%',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      ],
    );
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
          // Mismo criterio que en escritorio: la barra no se toca mientras el
          // reproductor está ocupado. Ver `barraBloqueada` en el controller —
          // es el único sitio donde se decide, así que las dos plataformas se
          // comportan igual.
          Obx(() => IgnorePointer(
                ignoring: controller.barraBloqueada,
                child: Opacity(
                  opacity: controller.barraBloqueada ? 0.5 : 1,
                  child: _SeekBar(controller: controller),
                ),
              )),
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
                  // Resolviendo el servidor elegido — el botón se apaga para
                  // no permitir otro toque mientras carga.
                  //
                  // Apagado, no dando vueltas. En el centro de la pantalla ya
                  // está el cartel «Obteniendo enlace…», que dice exactamente
                  // eso; una rueda acá abajo es la misma noticia dos veces, y
                  // encima con dos cosas girando a destiempo. Un reproductor de
                  // verdad avisa una sola vez.
                  if (controller.isGettingWatchData.value) {
                    return const IconButton(
                      onPressed: null,
                      icon: Icon(Icons.play_arrow, size: 30),
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
                // El volumen va ÚLTIMO, después de pantalla completa — a
                // pedido explícito: mide unos 200px (ícono + barra + el
                // porcentaje) y, puesto antes, empujaba a pantalla completa
                // tan a la derecha que costaba acertarle con el dedo. Al
                // final no molesta a nadie: es una barra ancha que se
                // arrastra, no un ícono chico al que haya que apuntar.
                _VolumeButtonMobile(controller: controller),
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
    // Del CONTROLADOR y no de mpv directo, igual que la barra de escritorio.
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
