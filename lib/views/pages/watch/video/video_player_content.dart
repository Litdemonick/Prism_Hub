import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/watch/video/video_player_desktop_controls.dart';
import 'package:prismhub/views/pages/watch/video/video_player_mobile_controls.dart';
import 'package:prismhub/views/widgets/watch/tutorial_reproductor.dart';

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

  /// Si toca mostrar el tutorial de gestos en esta sesion del reproductor.
  ///
  /// Se decide UNA vez, al montar, y no en cada build: leerlo en build haria
  /// que el tutorial reapareciera solo con que algo reconstruya la pantalla, y
  /// que desapareciera a mitad de un paso.
  late bool _mostrarTutorial = !TutorialReproductor.yaVisto;

  @override
  void initState() {
    super.initState();
    // Con el tutorial arriba, el video queda PAUSADO.
    //
    // Antes seguia reproduciendo detras: se perdian los primeros minutos
    // mientras se leia, y el audio sonaba sobre una pantalla tapada. Ademas los
    // pasos hablan de pausar y adelantar, y no se entiende leerlos mientras el
    // episodio avanza solo.
    //
    // Se hace en initState y no en build: build corre muchas veces y pausaria
    // de nuevo cada vez, peleando con el usuario si le da play desde los
    // controles.
    if (_mostrarTutorial) {
      // Se avisa al controlador para que nada de afuera se meta encima ni
      // arranque el video: el dialogo de "parece que estabas mirando esto"
      // salia sobre el tutorial y aceptarlo lo mandaba a reproducir.
      widget.controller.tutorialArriba.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // safePause y no player.pause(): si el usuario sale del episodio con el
        // tutorial arriba, el Player nativo ya esta disposed y llamarlo directo
        // tira la asercion de media_kit que tumba la app entera.
        if (mounted) widget.controller.safePause();
      });
      // Y se queda pausado: pausar una sola vez no alcanza.
      //
      // El video puede arrancar SOLO despues, cuando termina de resolverse el
      // servidor o al cambiar de calidad — son caminos que llaman a play() por
      // su cuenta, sin saber que hay un tutorial encima. Sin esto, el episodio
      // empezaba a correr a mitad de la lectura.
      //
      // Se corta apenas el tutorial se cierra (ver onCerrar), asi que no puede
      // quedar peleandole al usuario despues.
      _vigilante =
          widget.controller.player.stream.playing.listen((reproduciendo) {
        if (reproduciendo && _mostrarTutorial && mounted) {
          widget.controller.safePause();
        }
      });
    }
  }

  /// Mantiene el video pausado mientras el tutorial esta arriba.
  StreamSubscription<bool>? _vigilante;

  @override
  void dispose() {
    _vigilante?.cancel();
    // Si se sale del episodio con el tutorial puesto, la bandera tiene que
    // quedar limpia: si no, el proximo video entraria creyendo que todavia hay
    // un tutorial encima y nunca mostraria el dialogo de continuar.
    if (_mostrarTutorial) widget.controller.tutorialArriba.value = false;
    super.dispose();
  }

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
        return _conTutorial(
            c, Container(color: Colors.black, child: controls()));
      }
      return _conTutorial(
        c,
        Video(
          controller: c.videoController,
          // Con el modo VR puesto, la imagen LLENA la pantalla.
          //
          // Al recortar un VR a la mitad izquierda queda un cuadro con otra
          // proporción, y ajustándolo entero (lo de siempre) sobran barras
          // negras a los costados o arriba: en el teléfono se veía una franja
          // chica en el medio de una pantalla casi toda negra.
          //
          // Solo en modo VR. Para un vídeo normal recortar sería peor —se
          // perdería parte de la imagen sin que nadie lo haya pedido— así que
          // ahí se sigue mostrando entero como siempre.
          // Recorta para llenar cuando el usuario lo pidio (video normal) o
          // cuando el recorte del VR dejo un cuadro con otra proporcion.
          fit: (c.vrUnaPantalla.value || c.llenarPantalla.value)
              ? BoxFit.cover
              : BoxFit.contain,
          // Llenando la pantalla, el recorte se lleva la parte de ARRIBA.
          //
          // BoxFit.cover recorta centrado, o sea que saca lo mismo arriba que
          // abajo — y abajo es justo donde van los subtitulos quemados en la
          // imagen (los que vienen dentro del video, que no se pueden mover).
          // Con "llenar pantalla" puesto se cortaban a la mitad o desaparecian.
          //
          // Anclando abajo, todo lo que sobra sale de arriba: la franja de
          // subtitulos se salva entera. Se pierde mas cielo o fondo en la parte
          // superior, que es lo que uno esta dispuesto a ceder cuando pide
          // llenar la pantalla.
          //
          // En VR no: ahi el recorte ya lo hace el propio reproductor con las
          // medidas reales (ver _aplicarRecorteVr), y mover el anclaje
          // descuadraria esa cuenta.
          //
          // ── Y DE PIE se ancla ARRIBA ─────────────────────────────────────
          //
          // De pie el vídeo es una franja 16:9 en una pantalla larga, así que
          // centrado quedaba flotando en el medio con negro arriba y abajo. Va
          // pegado arriba, como en cualquier reproductor de teléfono: la imagen
          // arriba y el espacio libre debajo, que es donde caen los botones.
          alignment: (c.llenarPantalla.value && !c.vrUnaPantalla.value)
              ? Alignment.bottomCenter
              : (MediaQuery.orientationOf(context) == Orientation.portrait
                  ? Alignment.topCenter
                  : Alignment.center),
          subtitleViewConfiguration: const SubtitleViewConfiguration(
            visible: false,
          ),
          controls: (state) => controls(),
        ),
      );
    });
  }

  /// Pone el tutorial ENCIMA del reproductor, sin cambiar nada de abajo.
  ///
  /// Va como una capa aparte y no dentro de los controles a proposito: asi el
  /// reproductor se arma exactamente igual con tutorial o sin el, y quitarlo no
  /// puede romper nada de lo que ya andaba.
  ///
  /// Solo tapa; no pausa ni toca el video. Quien abre un episodio quiere verlo,
  /// y el tutorial se cierra en dos toques.
  Widget _conTutorial(VideoPlayerController c, Widget hijo) {
    if (!_mostrarTutorial) return hijo;
    return Stack(
      children: [
        hijo,
        Positioned.fill(
          child: TutorialReproductor(
            // Ver esVideoVr en el controlador.
            esVr: c.esVideoVr.value,
            onCerrar: () {
              if (!mounted) return;
              setState(() => _mostrarTutorial = false);
              widget.controller.tutorialArriba.value = false;
              _vigilante?.cancel();
              _vigilante = null;
              // Al cerrarlo arranca: quien abrio el episodio lo hizo para
              // verlo, y quedaria pausado sin explicacion.
              widget.controller.safePlay();
            },
          ),
        ),
      ],
    );
  }
}
