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
import 'package:prismhub/views/widgets/progress.dart';
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
  bool _isAdjusting = false;
  bool _isLongPress = false;
  // Cuenta de dedos apoyados en la pantalla — sin esto, pellizcar con 2 dedos
  // (que el usuario espera que no haga nada, no hay zoom por pellizco, solo
  // doble tap) igual disparaba onVerticalDragUpdate con el movimiento de uno
  // de los 2 dedos, subiendo/bajando el volumen sin querer.
  int _activePointers = 0;
  Timer? _timer;
  Worker? _webViewWorker;
  Worker? _resumeWorker;
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
      _showResumeDialog(secs);
    });
  }

  @override
  void dispose() {
    _webViewWorker?.dispose();
    _resumeWorker?.dispose();
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
                      opacity: ((!_c.isGettingWatchData.value &&
                                  !_c.hasRenderedFrame.value &&
                                  // Ver el comentario equivalente en los
                                  // controles de escritorio.
                                  _c.error.value.isEmpty &&
                                  !_c.isWebViewActive.value) ||
                              (_c.hasRenderedFrame.value &&
                                  (_c.isSeeking.value ||
                                      (_c.isPlaying.value &&
                                          _c.isActuallyBuffering.value))))
                          ? 1
                          : 0,
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
                                    HomeTheme.accentPink),
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
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('Playing at 3x speed'),
                        ),
                      if (_isAdjusting)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.volume_up),
                              const SizedBox(width: 5),
                              Text(
                                (_currentVolume * 100).toStringAsFixed(0),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Devolución visual del doble toque: cuántos segundos se
            // saltó y hacia dónde. Va sobre la capa de gestos para que no la
            // tape, y con IgnorePointer para no robar toques.
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                    // Arriba del centro, no en el centro: ahí está la rueda de
                    // carga, y al saltar a un tramo sin cargar aparecen las dos
                    // cosas a la vez y se pisaban. Misma posición que en PC.
                    alignment: const Alignment(0, -0.55),
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
                            border: Border.all(color: HomeTheme.accentPink),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (_saltoVisible ?? 0) < 0
                                    ? Icons.fast_rewind
                                    : Icons.fast_forward,
                                color: HomeTheme.accentPink,
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
            // 手势层
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) => _activePointers++,
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
                    final width = LayoutUtils.width / 3;
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
                    if (dx < width) {
                      _c.seek(_c.position.value - atras);
                      _mostrarSalto(-atras.inSeconds);
                    } else if (dx > width * 2) {
                      _c.seek(_c.position.value + adelante);
                      _mostrarSalto(adelante.inSeconds);
                    } else {
                      _c.playOrPause();
                    }
                  },
                  // Deslizar vertical = volumen, en cualquier parte de la
                  // pantalla — a pedido explícito, el reproductor ya no toca
                  // el brillo del sistema (antes la mitad izquierda lo hacía).
                  // Se ignora con más de un dedo apoyado (pellizcar) — sin
                  // esto, un pellizco (que no debe hacer nada, no hay zoom por
                  // pellizco) igual subía/bajaba el volumen con el movimiento
                  // de uno de los 2 dedos.
                  onVerticalDragUpdate: (details) {
                    if (_activePointers > 1) return;
                    final add = details.delta.dy / 500;
                    _currentVolume = (_currentVolume - add).clamp(0, 1);
                    VolumeController().setVolume(_currentVolume);
                    _isAdjusting = true;
                    setState(() {});
                  },
                  onVerticalDragEnd: (details) {
                    _isAdjusting = false;
                    setState(() {});
                  },
                  onLongPressStart: (details) {
                    _isLongPress = true;
                    _c.player.setRate(3.0);
                    setState(() {});
                  },
                  onLongPressEnd: (details) {
                    _c.player.setRate(_c.currentSpeed.value);
                    _isLongPress = false;
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
                              color:
                                  HomeTheme.accentPink.withValues(alpha: 0.18),
                              border: Border.all(color: HomeTheme.accentPink),
                            ),
                            child: const Icon(Icons.play_arrow,
                                color: HomeTheme.accentPink, size: 36),
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
                        if (_c.dlnaDevice.value != null) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                FlutterI18n.translate(
                                  context,
                                  'video.cast-device',
                                  translationParams: {
                                    'device':
                                        _c.dlnaDevice.value!.info.friendlyName,
                                  },
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton(
                                onPressed: () {
                                  _c.disconnectDLNADevice();
                                },
                                child: Text(
                                  'common.disconnect'.i18n,
                                ),
                              ),
                            ],
                          );
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
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _Footer(controller: _c),
                ),
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => unawaited(controller.closeRoute(context)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Obx(() {
              final data = controller.playList[controller.index.value];
              final episode = data.name;
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
          IconButton(
            icon: const Icon(Icons.cast),
            onPressed: () {
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
                    return const IconButton(
                      onPressed: null,
                      icon: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: HomeTheme.accentPink,
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
                      if (controller.qualityMap.isEmpty) {
                        controller.sendMessage(
                          Message(
                            Text(
                              'video.no-qualities'.i18n,
                            ),
                          ),
                        );
                        return;
                      }
                      controller.toggleSideBar(SidebarTab.qualitys);
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
                  if (controller.availableServers.isEmpty) {
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

  StreamSubscription? _bufferSubscription;

  @override
  void initState() {
    super.initState();
    _buffer = widget.controller.player.state.buffer;

    _bufferSubscription =
        widget.controller.player.stream.buffer.listen((event) {
      if (!mounted) return;
      setState(() {
        _buffer = event;
      });
    });
  }

  @override
  dispose() {
    _bufferSubscription?.cancel();
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
