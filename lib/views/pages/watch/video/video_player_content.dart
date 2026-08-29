import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/watch/video/video_player_desktop_controls.dart';
import 'package:prismhub/views/pages/watch/video/video_player_mobile_controls.dart';
import 'package:prismhub/views/widgets/watch/tutorial_reproductor.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/pages/watch/video/video_player_tv_controls.dart';

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
      // ── En TV NO van los controles de teléfono ──────────────────────────
      //
      // Los de Android son 100% gestuales: arrastrar para el volumen y el
      // brillo, doble toque para adelantar, deslizar la barra. Con un mando
      // no hay ninguno de esos gestos, así que ahí la pantalla queda sin
      // forma de hacer nada.
      //
      // Los de escritorio ya están hechos alrededor del TECLADO (ver el mapa
      // `keyboardShortcuts` del controlador: flechas, espacio, teclas de
      // medios) — y el D-pad de un televisor llega a Flutter exactamente
      // como esas mismas teclas. O sea que es la variante que ya sirve, sin
      // escribir una tercera.
      // TV tiene su propia barra, pensada para el mando — pero por debajo
      // sigue montado el motor de los controles de escritorio, que es lo
      // que hace andar el reproductor. Ver video_player_tv_controls.dart.
      if (PlatformTv.esTelevisionSync) {
        return VideoPlayerTvControls(key: _controlsKey, controller: c);
      }
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
        // La vista la arma el MOTOR, no esta pantalla.
        //
        // Es el punto donde los dos motores de verdad difieren: mpv dibuja
        // sobre una textura de Flutter y el de Android sobre una superficie
        // nativa. Pidiendosela al motor, esta pantalla se arma igual con
        // cualquiera de los dos. Ver MotorDeVideo.vista.
        c.motor.vista(
          // ── De pie, el hueco NO es negro ──────────────────────────────
          //
          // El video es una franja 16:9 anclada arriba, asi que debajo queda
          // media pantalla libre. En negro plano eso se lee como que la app se
          // rompio o se quedo colgada. Con el fondo de la app se entiende que
          // es la misma pantalla y que ahi es donde caen los controles.
          //
          // Acostado se queda en negro, que es lo correcto: ahi el hueco son
          // las franjas de un video que no llena, y cualquier color que no sea
          // negro compite con la imagen.
          fondo: MediaQuery.orientationOf(context) == Orientation.portrait
              ? HomeTheme.oscuroFondo
              : Colors.black,
          // Recorta para llenar cuando el usuario lo pidio (video normal) o
          // cuando el recorte del VR dejo un cuadro con otra proporcion.
          ajuste: (c.vrUnaPantalla.value || c.llenarPantalla.value)
              ? BoxFit.cover
              : BoxFit.contain,
          // Llenando la pantalla, el recorte se lleva la parte de ARRIBA:
          // abajo van los subtitulos quemados en la imagen, que con el recorte
          // centrado se cortaban a la mitad. De pie va centrada, que es lo que
          // hace YouTube a pantalla completa.
          alineacion: (c.llenarPantalla.value && !c.vrUnaPantalla.value)
              ? Alignment.bottomCenter
              : Alignment.center,
          // El cuadro congelado tapa el hueco de la reapertura al saltar, y va
          // DEBAJO de los botones: por eso los dos entran juntos como lo que
          // va encima de la imagen. Es null salvo durante un salto.
          encima: Stack(
            fit: StackFit.expand,
            children: [
              Obx(() {
                final foto = c.cuadroCongelado.value;
                if (foto == null) return const SizedBox.shrink();
                return Image.memory(foto,
                    fit: BoxFit.contain, gaplessPlayback: true);
              }),
              controls(),
            ],
          ),
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
