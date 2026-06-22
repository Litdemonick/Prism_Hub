import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart'
    show openWebViewPlayer;
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/pages/watch/video/video_player_cast.dart';
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
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

class _VideoPlayerMobileControlsState extends State<VideoPlayerMobileControls> {
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
    // No abrir WebView automáticamente — el usuario lo abre con el botón en la UI.
    _webViewWorker = ever(_c.webViewFallback, (_) {});
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
    _timer?.cancel();
    super.dispose();
  }

  void _showResumeDialog(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    final timeStr = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¡Un momento!'),
        content: Text(
          'Parece que anteriormente estabas mirando este vídeo '
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
                        _c.subtitleBackgroundColor.value.withValues(alpha:
                      _c.subtitleBackgroundOpacity.value,
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
                    _c.seek(
                        _c.position.value - const Duration(seconds: 10));
                  } else if (dx > width * 2) {
                    _c.seek(
                        _c.position.value + const Duration(seconds: 10));
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
                          child: Row(
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
                              const SizedBox(width: 10),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white70, size: 18),
                                onPressed: () {
                                  _c.serverFailedMessage.value = '';
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return StreamBuilder(
                      stream: _c.player.stream.buffering,
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data! ||
                            _c.player.state.buffering) {
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
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
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _c.runtime.extension.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'video.getting-streamlink'.i18n,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            // 头部控制栏 — siempre visible (a pedido del usuario): el botón de
            // servidores y demás controles no se ocultan en ningún dispositivo.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _Header(
                controller: _c,
              ),
            ),
            // 底部控制栏 — siempre visible.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _Footer(controller: _c),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              RouterUtils.pop();
            },
          ),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black54,
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
          Row(
            children: [
              Obx(
                () => IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: controller.index.value > 0
                      ? () {
                          if (controller.index.value > 0) {
                            controller.index.value--;
                          }
                        }
                      : null,
                ),
              ),
              Obx(() {
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
              Obx(
                () => IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed:
                      controller.playList.length - 1 > controller.index.value
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
              const Spacer(),
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
              // 选择服务器 (server selector)
              Obx(() {
                if (controller.availableServers.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  onPressed: () => showServerSheet(context, controller),
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

// Server selector bottom sheet for the mobile player (parity with desktop).
void showServerSheet(BuildContext context, VideoPlayerController controller) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.dns, size: 18),
                const SizedBox(width: 8),
                Text(
                  'video.servers'.i18n,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: Obx(
              () => ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in controller.availableServers.entries)
                    Builder(builder: (_) {
                      final isCurrent =
                          controller.currentServerName.value == entry.key;
                      return ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle
                              : Icons.dns_outlined,
                          color: isCurrent
                              ? Colors.greenAccent
                              : Colors.white,
                        ),
                        title: Text(
                          entry.key,
                          style: const TextStyle(color: Colors.white),
                        ),
                        selected: isCurrent,
                        onTap: () {
                          Navigator.of(context).pop();
                          if (!isCurrent) {
                            final eu = controller.availableServers[entry.key]!;
                            if (eu.contains('mega.nz') ||
                                eu.contains('mega.co.nz')) {
                              controller.player.pause();
                              openWebViewPlayer(
                                context, eu,
                                referer: controller.serverReferers[entry.key],
                                title: entry.key,
                              );
                            } else {
                              controller.switchServer(entry.key);
                            }
                          }
                        },
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
