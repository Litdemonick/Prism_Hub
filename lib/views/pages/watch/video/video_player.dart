import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/pages/watch/video/video_player_content.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';

class VideoPlayer extends StatefulWidget {
  const VideoPlayer({
    super.key,
    required this.playList,
    required this.runtime,
    required this.episodeGroupId,
    required this.playerIndex,
    required this.title,
    required this.detailUrl,
    required this.anilistID,
    this.autoResume = false,
  });

  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playerIndex;
  final int episodeGroupId;
  final ExtensionService runtime;
  final String anilistID;
  final bool autoResume;

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  VideoPlayerController? _c;
  bool _contentReady = false;

  // Contador global de sesiones: el tag lleva un sufijo único por CADA
  // pantalla de reproductor creada. Antes el tag era solo título+url+grupo,
  // así que dos pantallas del mismo episodio lo compartían — y como Flutter
  // construye la pantalla nueva ANTES de destruir la vieja, el dispose() de
  // la vieja borraba del tag el controller de la NUEVA, que quedaba muerta
  // apenas nacía (se veía bien pero no respondía nada). Con un tag propio
  // por sesión ese cruce es imposible por construcción.
  static int _sessionSeq = 0;
  late final String _tag =
      '${VideoPlayerController.buildTag(widget.title, widget.detailUrl, widget.episodeGroupId)}#${++_sessionSeq}';

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    // Esperar a que el reproductor ANTERIOR termine de apagarse (dos
    // instancias de mpv vivas a la vez pelean por la GPU en Windows), pero
    // nunca para siempre: si ese apagado se cuelga —el bug de threading de
    // media_kit_video 1.2.5 lo hace posible— sin este límite la pantalla
    // nueva se quedaba en negro con el spinner eternamente, sin cargar nada
    // ni responder (confirmado en vivo). Mejor arrancar igual que no
    // arrancar nunca.
    try {
      await VideoPlayerController.waitForPreviousShutdown()
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (!mounted) return;
    // Sin lógica de "borrar el controller anterior de este tag": el tag ahora
    // es único por sesión (ver _tag), así que nunca hay uno previo que pisar.
    _c = Get.put(
      VideoPlayerController(
        title: widget.title,
        playList: widget.playList,
        detailUrl: widget.detailUrl,
        playIndex: widget.playerIndex,
        episodeGroupId: widget.episodeGroupId,
        runtime: widget.runtime,
        anilistID: widget.anilistID,
        autoResume: widget.autoResume,
      ),
      tag: _tag,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _contentReady = true);
    });
  }

  @override
  void dispose() {
    // El tag es único por sesión, así que lo registrado acá solo puede ser
    // nuestro propio controller — no hay riesgo de borrar el de otra
    // pantalla. El identical() queda igual como red de seguridad barata.
    final c = _c;
    if (c != null &&
        Get.isRegistered<VideoPlayerController>(tag: _tag) &&
        identical(Get.find<VideoPlayerController>(tag: _tag), c)) {
      Get.delete<VideoPlayerController>(tag: _tag);
    }
    super.dispose();
  }

  _buildContent() {
    final c = _c;
    if (c == null || !_contentReady) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: ProgressRing()),
      );
    }
    return Obx(() {
      final maxWidth = MediaQuery.of(context).size.width;
      // El área del video SIEMPRE usa Expanded (nunca un ancho fijo en
      // píxeles): un ancho calculado a partir de MediaQuery queda un
      // instante desincronizado del tamaño real de la ventana durante un
      // resize (ej. entrar/salir de pantalla completa), y como esta Row
      // tiene un segundo hijo (el sidebar), eso desborda la Row. Solo el
      // sidebar anima con un ancho fijo (0↔300), un rango acotado que no
      // depende del tamaño de la ventana.
      return Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                VideoPlayerConten(controller: c),
                // 消息弹出
                if (c.cuurentMessageWidget.value != null)
                  Positioned(
                    left: 0,
                    bottom: 100,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                      constraints: BoxConstraints(
                        maxHeight: 200,
                        maxWidth: maxWidth,
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                        child: c.cuurentMessageWidget.value!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          AnimatedContainer(
            onEnd: () {
              c.isOpenSidebar.value = c.showSidebar.value;
            },
            width: c.showSidebar.value ? 300 : 0,
            duration: const Duration(milliseconds: 120),
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: c.isOpenSidebar.value || c.showSidebar.value
                ? OverflowBox(
                    minWidth: 300,
                    maxWidth: 300,
                    alignment: Alignment.centerRight,
                    child: VideoPlayerSidebar(
                      controller: c,
                    ),
                  )
                : null,
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // ExcludeSemantics: el reproductor reconstruye sus controles cada frame
    // (posición, barra de progreso, buffering). En Windows eso satura el árbol
    // de accesibilidad del engine y genera el spam continuo en consola:
    //   "Failed to update ui::AXTree, error: NNN will not be in the tree..."
    // El video no necesita semántica de lector de pantalla, así que se excluye
    // toda la página: elimina el spam sin afectar la funcionalidad.
    return ExcludeSemantics(
      child: PlatformBuildWidget(
        androidBuilder: (context) => Theme(
          data: ThemeData.dark(useMaterial3: true),
          child: Scaffold(body: _buildContent()),
        ),
        desktopBuilder: ((context) => _buildContent()),
      ),
    );
  }
}
