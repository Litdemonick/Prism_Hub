import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart'
    show isKnownNativeServer, openWebViewPlayer;
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/pages/watch/video/video_player_cast.dart';
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/progress.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

class VideoPlayerMobileControls extends StatefulWidget {
  const VideoPlayerMobileControls({super.key, required this.controller});
  final VideoPlayerController controller;

  @override
  State<VideoPlayerMobileControls> createState() =>
      _VideoPlayerMobileControlsState();
}

class _VideoPlayerMobileControlsState extends State<VideoPlayerMobileControls>
    with WidgetsBindingObserver {
  late final VideoPlayerController _c = widget.controller;
  final _subtitleViewKey = GlobalKey<SubtitleViewState>();
  bool _showControls = true;
  double _currentBrightness = 0;
  double _currentVolume = 0;
  bool _isBrightness = false;
  bool _isAdjusting = false;
  Duration _position = Duration.zero;
  bool _isSeeking = false;
  bool _isLongPress = false;
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

  _init() async {
    _updateTimer();
    VolumeController().showSystemUI = false;
    _currentBrightness = await ScreenBrightness().current;
    _currentVolume = await VolumeController().getVolume();
  }

  @override
  void initState() {
    _init();
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _webViewWorker?.dispose();
    _resumeWorker?.dispose();
    _timer?.cancel();
    // El gesto de deslizar para ajustar brillo (onVerticalDragUpdate más
    // abajo) usa setScreenBrightness, que pisa el brillo de la ventana de la
    // app hasta que algo lo revierta explícitamente — sin este reset, al
    // salir del reproductor quedaba "pegado" en el último valor ajustado en
    // vez de volver al que controla el sistema (reportado en vivo).
    ScreenBrightness().resetScreenBrightness();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // dispose() no alcanza si la app pasa a segundo plano (botón Inicio,
    // cambiar de app) sin volver atrás desde el reproductor — el widget
    // sigue montado, solo oculto, así que el override de brillo seguía
    // activo (esto es justo lo que el usuario reportó: Android seguía
    // mostrando "PrismHub controla el brillo" aun sin estar mirando el
    // video). Se suelta también acá, no solo al salir de la pantalla.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ScreenBrightness().resetScreenBrightness();
    }
  }

  // Reabre el WebView con la misma URL guardada (mismo botón que en
  // desktop) — sin esto, cerrar el WebView (atrás) y volver acá no dejaba
  // ninguna forma de retomarlo salvo tocar el servidor de nuevo.
  void _openWebView() {
    final fallback = _c.webViewFallback.value;
    if (fallback == null) return;
    _c.webViewOpenedOnce.value = true;
    final referer = fallback['referer'];
    openWebViewPlayer(
      context,
      fallback['url']!,
      referer: (referer == null || referer.isEmpty) ? null : referer,
      title: _c.title,
      onProgress: _c.saveWebViewProgress,
    );
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
                      if (_isSeeking)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')}',
                              ),
                              const Text('/'),
                              Text(
                                '${_c.duration.value.inMinutes}:${(_c.duration.value.inSeconds % 60).toString().padLeft(2, '0')}',
                              ),
                            ],
                          ),
                        ),
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
                              if (_isBrightness) ...[
                                const Icon(Icons.brightness_5),
                                const SizedBox(width: 5),
                                Text(
                                  (_currentBrightness * 100).toStringAsFixed(0),
                                )
                              ],
                              if (!_isBrightness) ...[
                                const Icon(Icons.volume_up),
                                const SizedBox(width: 5),
                                Text(
                                  (_currentVolume * 100).toStringAsFixed(0),
                                )
                              ],
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
                  if (dx < width) {
                    _c.seek(_c.position.value - const Duration(seconds: 10));
                  } else if (dx > width * 2) {
                    _c.seek(_c.position.value + const Duration(seconds: 10));
                  } else {
                    _c.playOrPause();
                  }
                },
                onVerticalDragStart: (details) {
                  _isBrightness =
                      details.localPosition.dx < LayoutUtils.width / 2;
                },
                // 左右两边上下滑动
                onVerticalDragUpdate: (details) {
                  final add = details.delta.dy / 500;
                  // 如果是左边调节亮度
                  if (_isBrightness) {
                    _currentBrightness = (_currentBrightness - add).clamp(0, 1);
                    ScreenBrightness().setScreenBrightness(_currentBrightness);
                  }
                  // 如果是右边调节音量
                  else {
                    _currentVolume = (_currentVolume - add).clamp(0, 1);
                    VolumeController().setVolume(_currentVolume);
                  }
                  _isAdjusting = true;
                  setState(() {});
                },
                onHorizontalDragStart: (details) {
                  _position = _c.position.value;
                },
                onVerticalDragEnd: (details) {
                  _isAdjusting = false;
                  setState(() {});
                },
                // 左右滑动
                onHorizontalDragUpdate: (details) {
                  double scale = 200000 / LayoutUtils.width;
                  Duration pos = _position +
                      Duration(
                        milliseconds: (details.delta.dx * scale).round(),
                      );
                  _position = Duration(
                    milliseconds: pos.inMilliseconds.clamp(
                      0,
                      _c.duration.value.inMilliseconds,
                    ),
                  );
                  _isSeeking = true;
                  setState(() {});
                },
                onHorizontalDragEnd: (details) {
                  _c.seek(_position);
                  _isSeeking = false;
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
                      return const ProgressRing();
                    }
                    return StreamBuilder(
                      stream: _c.player.stream.buffering,
                      builder: (context, snapshot) {
                        // Pausado: nunca mostrar el spinner (mismo criterio
                        // que en desktop). mpv sigue llenando el buffer en
                        // pausa — eso está bien y la barra ya lo muestra —
                        // pero el spinner girando hacía parecer que el
                        // reproductor se trabó justo al pausar.
                        final isBuffering =
                            (snapshot.hasData && snapshot.data!) ||
                                _c.player.state.buffering;
                        if (isBuffering && _c.isPlaying.value) {
                          return const ProgressRing();
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
                      _Header(
                        controller: _c,
                      ),
                      // selector de servidores — pestañas arriba, no un botón
                      // escondido en un bottom sheet.
                      _ServerTabBar(controller: _c),
                    ],
                  ),
                ),
              ),
            ),
            // Volver, siempre visible — a pedido explícito: no debe ocultarse
            // junto con el resto del header ni siquiera en pantalla completa
            // (antes compartía el auto-hide con título/tabs/footer). Va
            // ENCIMA del header (que sí se oculta) para no quedar tapado.
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      RouterUtils.pop();
                    },
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
          // El botón real vive en un overlay aparte, siempre visible (ver
          // _AlwaysVisibleBackButton más abajo) — este espacio solo reserva
          // el ancho para que el título no se corra al ocultarse el resto
          // del header.
          const SizedBox(width: 48),
          const SizedBox(width: 10),
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

// ─── Selector de Servidores — fila de pestañas arriba del video ─────────────

class _ServerTabBar extends StatelessWidget {
  const _ServerTabBar({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.availableServers.isEmpty) return const SizedBox.shrink();
      final current = controller.currentServerName.value;
      return Container(
        width: double.infinity,
        // 0.85 (antes 0.35) — contra un fotograma claro del video, los
        // nombres de servidor casi no se leían.
        color: Colors.black.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in controller.availableServers.entries) ...[
                _ServerTab(
                  label: entry.key,
                  selected: entry.key == current,
                  isNative: isKnownNativeServer(entry.key, entry.value),
                  onTap: () => controller.selectServer(entry.key),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _ServerTab extends StatelessWidget {
  const _ServerTab({
    required this.label,
    required this.selected,
    required this.isNative,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final bool isNative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        // Fondo bien opaco en los dos estados (antes 0.22/0.7, contra un
        // video claro se veía transparentado) — la selección ya se nota
        // por el borde y el color del texto, no hace falta un relleno
        // traslúcido que dependa de lo oscuro que esté el video atrás.
        decoration: BoxDecoration(
          color: selected
              ? HomeTheme.accentPink.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? HomeTheme.accentPink : HomeTheme.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? HomeTheme.accentPink : Colors.white,
              ),
            ),
            if (isNative) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.bolt,
                size: 12,
                color: selected
                    ? HomeTheme.accentPink
                    : Colors.greenAccent.withValues(alpha: 0.85),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
