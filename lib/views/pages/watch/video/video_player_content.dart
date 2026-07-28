import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/watch/video/video_player_desktop_controls.dart';
import 'package:prismhub/views/pages/watch/video/video_player_mobile_controls.dart';

class VideoPlayerConten extends StatefulWidget {
  const VideoPlayerConten({
    super.key,
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  State<VideoPlayerConten> createState() => _VideoPlayerContenState();
}

class _VideoPlayerContenState extends State<VideoPlayerConten> {
  // Un GlobalKey estable (campo de State, no recreado en cada build) para
  // los controles: cuando isWebViewActive cambia, Flutter reutiliza el
  // MISMO Element/State de los controles (mueve el widget de padre en vez
  // de destruirlo y crear uno nuevo) — así el worker que escucha
  // webViewFallback (y la propia llamada a _openWebView, que sigue
  // corriendo en ese mismo State mientras se espera a que el WebView se
  // cierre) no se pierde a mitad de camino. Si este key se recreara en
  // cada build (ej. declarado adentro de build()), este mecanismo no
  // funcionaría — Flutter lo trataría como una identidad nueva cada vez.
  final _controlsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    Widget controls() {
      if (Platform.isAndroid) {
        return VideoPlayerMobileControls(key: _controlsKey, controller: c);
      }
      return VideoPlayerDesktopControls(key: _controlsKey, controller: c);
    }

    return Obx(() {
      // El reproductor nativo (media_kit/mpv) mantiene su textura de video
      // registrada mientras el widget Video siga montado, aunque player.stop()
      // ya haya parado la decodificación — confirmado en vivo (y con
      // reportes idénticos en los repos de flutter_inappwebview y media_kit)
      // que esa textura sigue compitiendo por GPU con WebView2 en Windows,
      // al punto de congelar la app entera ("No responde", ni con hot
      // restart) mientras el WebView de respaldo está abierto encima. Sacar
      // Video del árbol por completo mientras tanto libera esa textura.
      if (c.isWebViewActive.value || !c.isVideoSurfaceMounted.value) {
        return Container(color: Colors.black, child: controls());
      }
      return Video(
        controller: c.videoController,
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          visible: false,
        ),
        controls: (state) => controls(),
      );
    });
  }
}
