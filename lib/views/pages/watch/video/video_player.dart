import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:prismhub/views/pages/watch/video/video_player_content.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
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
    this.isNsfw = false,
  });

  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playerIndex;
  final int episodeGroupId;
  final ExtensionService runtime;
  final String anilistID;
  final bool autoResume;
  final bool isNsfw;

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
    // Y se espera a que TERMINE de entrar la pantalla. Ver _esperarLaEntrada.
    await _esperarLaEntrada();
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
        isNsfw: widget.isNsfw,
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

  /// Espera a que la animación de entrada de esta pantalla termine.
  ///
  /// ── Por qué, y qué se veía ──────────────────────────────────────────────
  ///
  /// Crear el controlador arranca mpv: abrir el motor, montar la textura,
  /// resolver el servidor. Es lo más caro que hace la app, y estaba corriendo
  /// EN MEDIO de la animación con la que esta pantalla entra. Los dos se pelean
  /// el mismo hilo, así que la transición perdía cuadros justo al abrir — se
  /// sentía como un tirón, y en la primera apertura de la app, cuando además
  /// hay que cargar las bibliotecas nativas, mucho peor.
  ///
  /// Esperando a que la entrada termine, la animación corre sola y limpia, y el
  /// arranque del reproductor empieza cuando ya no compite con nadie. No se
  /// pierde tiempo real: lo que se demora es el arranque unos 250 ms, que es
  /// exactamente lo que la animación tapa con la rueda que ya se muestra.
  ///
  /// Con tope, y no es de adorno: si algo deja la animación a medio camino —o
  /// si la ruta no tiene animación, como puede pasar en escritorio— sin el tope
  /// el reproductor no arrancaría nunca.
  Future<void> _esperarLaEntrada() async {
    final animacion = ModalRoute.of(context)?.animation;
    if (animacion == null || animacion.status == AnimationStatus.completed) {
      return;
    }
    final listo = Completer<void>();
    void alCambiar(AnimationStatus estado) {
      if (estado == AnimationStatus.completed ||
          estado == AnimationStatus.dismissed) {
        if (!listo.isCompleted) listo.complete();
      }
    }

    animacion.addStatusListener(alCambiar);
    try {
      await listo.future.timeout(const Duration(milliseconds: 700));
    } catch (_) {
      // Se agotó el tope: se sigue igual, que es mejor que no abrir.
    } finally {
      animacion.removeStatusListener(alCambiar);
    }
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
                // Los avisos van CENTRADOS y con fondo solido.
                //
                // Estaban pegados al borde izquierdo, a media altura, con la
                // caja recortada contra el borde y un negro al 50% que sobre
                // una escena clara dejaba el texto ilegible. Ahi no los mira
                // nadie: el ojo esta en el centro de la imagen.
                if (c.cuurentMessageWidget.value != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    // Transmitiendo, el aviso se va ARRIBA.
                    //
                    // El panel del casteo ocupa el centro y es alto, asi que un
                    // aviso a 90 del piso le quedaba encima: dos cajas oscuras
                    // pisandose, ilegibles las dos. Arriba, debajo del titulo,
                    // no se cruza con nada.
                    top: c.dlnaDevice.value != null ? 74 : null,
                    bottom: c.dlnaDevice.value != null ? null : 90,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 28),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xF01A1420),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          // ── El aviso no se achica de pie ──────────────
                          //
                          // El ancho salía de una fracción del ancho de la
                          // pantalla, y de pie ese ancho es la mitad: el aviso
                          // —«no se pudo reproducir», el panel de ajustes—
                          // quedaba en una columna angosta con las palabras
                          // partidas, mientras que acostado se veía bien. El
                          // texto no cambia de largo porque el teléfono gire.
                          //
                          // Ahora usa casi todo el ancho que hay, con un techo
                          // para que en una tablet o acostado no se estire de
                          // lado a lado, que ahí sí se lee peor.
                          constraints: BoxConstraints(
                            maxHeight: 260,
                            maxWidth: math.min(maxWidth - 48, 420),
                          ),
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.35,
                            ),
                            textAlign: TextAlign.center,
                            child: c.cuurentMessageWidget.value!,
                          ),
                        ),
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

  /// El reproductor de pie, estilo YouTube: el vídeo arriba y el resto debajo.
  ///
  /// ── Por qué existe esta rama ────────────────────────────────────────────
  ///
  /// Hasta ahora el reproductor BLOQUEABA la pantalla en horizontal: girar el
  /// teléfono no hacía nada. Está bien para mirar, pero deja afuera lo que uno
  /// hace la mitad del tiempo — dejar algo sonando y seguir con otra cosa, o
  /// simplemente sostener el teléfono de una mano.
  ///
  /// Acostado NO CAMBIA NADA: se devuelve exactamente lo mismo que antes, el
  /// contenido ocupando la pantalla entera. Esta rama es aditiva a propósito,
  /// porque el reproductor es la parte más delicada de la app y no vale la pena
  /// tocar el camino que ya funciona para agregar uno nuevo.
  ///
  /// De pie, el vídeo va en una caja 16:9 arriba de todo —la forma real del
  /// contenido, así que no se recorta ni deja franjas— con sus controles
  /// adentro, y debajo queda el resto de la pantalla. Las barras del sistema
  /// vuelven a verse: acá el vídeo no es todo, y esconder la de navegación
  /// dejaría sin salida.
  Widget _androidSegunOrientacion(BuildContext context) {
    final acostado = MediaQuery.orientationOf(context) == Orientation.landscape;

    // Se pide en cada construcción y no una sola vez: la orientación cambia
    // sin avisar por ningún otro lado, y esto es idempotente.
    //
    // Instancia y no estático: necesita mirar `pantallaCompletaAndroid`, que es
    // por-reproductor (el botón manual de pantalla completa).
    _c?.pantallaSegunOrientacion(acostado: acostado);

    if (acostado) return Scaffold(body: _buildContent());

    // De pie el contenido usa la pantalla ENTERA igual que acostado.
    //
    // El primer intento fue encerrar el vídeo en una caja 16:9 arriba y dejar
    // negro debajo. Se veía mal y por un motivo claro: los controles viven
    // DENTRO del reproductor, así que encogiendo la caja se encogían con él —
    // los botones quedaban apretados sobre la imagen, pisándola, y los de la
    // derecha directamente cortados.
    //
    // Ahora la caja es toda la pantalla y lo que se mueve es la IMAGEN: se
    // ancla arriba (ver VideoPlayerConten). El resultado es el que se buscaba
    // —vídeo arriba, espacio libre debajo— y los controles se reparten en esa
    // pantalla entera, con la barra de abajo en el hueco en vez de encima del
    // vídeo. Y sin tocar una línea de los controles, que es lo más delicado.
    return Scaffold(
      // Un fondo con algo de color en vez de negro puro. El hueco de abajo es
      // media pantalla: en negro plano se lee como que la app se colgó, y con
      // el mismo fondo del resto de la app se lee como parte del reproductor.
      backgroundColor: HomeTheme.oscuroFondo,
      body: _buildContent(),
    );
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
          child: _androidSegunOrientacion(context),
        ),
        desktopBuilder: ((context) => _buildContent()),
      ),
    );
  }
}
