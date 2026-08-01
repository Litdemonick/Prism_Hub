import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/watch/video/video_player_cast.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart'
    show isKnownNativeServer, openWebViewPlayer;
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/window_caption_buttons.dart';
import 'package:prismhub/views/widgets/watch/playlist.dart';
import 'package:window_manager/window_manager.dart';

class VideoPlayerDesktopControls extends StatefulWidget {
  const VideoPlayerDesktopControls({
    super.key,
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  State<VideoPlayerDesktopControls> createState() =>
      _VideoPlayerDesktopControlsState();
}

class _VideoPlayerDesktopControlsState
    extends State<VideoPlayerDesktopControls> {
  late final _c = widget.controller;
  final FocusNode _focusNode = FocusNode();
  final _subtitleViewKey = GlobalKey<SubtitleViewState>();
  Worker? _webViewWorker;
  Worker? _resumeWorker;
  // Se ocultan rápido si el mouse no se mueve (mismo patrón que ya usa la
  // versión mobile, con su propio timer de 3s de inactividad).
  bool _showControls = true;
  Timer? _hideTimer;
  DateTime? _lastHideTimerReset;

  void _resetHideTimer() {
    final now = DateTime.now();
    if (_showControls &&
        _lastHideTimerReset != null &&
        now.difference(_lastHideTimerReset!) <
            const Duration(milliseconds: 200)) {
      return;
    }
    _lastHideTimerReset = now;
    _hideTimer?.cancel();
    if (!_showControls && mounted) setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _resetHideTimer();
    // El reproductor nativo no pudo con este servidor (ver play() en
    // video_controller.dart) — abrir el WebView automáticamente en vez de
    // depender de un botón: antes esta señal (webViewFallback) se emitía
    // pero NADA la escuchaba de verdad (este worker tenía el callback
    // vacío), así que el fallback a WebView nunca se disparaba y el
    // usuario se quedaba solo con el cartel de texto sin forma real de ver
    // el video. webViewOpenedOnce evita reabrir una segunda vez si el mapa
    // se vuelve a emitir mientras ya se está mostrando.
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
    _hideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // Reabre el WebView con la misma URL guardada — usado tanto por el
  // auto-open (arriba) como por el botón "Volver al navegador" del cartel
  // de error: antes, al cerrar el WebView (botón atrás) y volver acá, no
  // había forma de reabrirlo salvo tocar el servidor de nuevo en la lista
  // (que ni siquiera reintenta el mismo, según el servidor elegido).
  Future<void> _openWebView() async {
    final fallback = _c.webViewFallback.value;
    if (fallback == null) return;
    _c.webViewOpenedOnce.value = true;
    _c.markWebViewPlayback(fallback);
    // Mismo motivo que en mobile: el reproductor nativo seguía con su
    // textura de video activa de fondo mientras el WebView se abre encima
    // (esta pantalla apila sobre la anterior, no la reemplaza) — dos motores
    // de render nativos pesados compitiendo por GPU en la misma ventana en
    // Windows es la causa confirmada (mismo problema reportado en los repos
    // de flutter_inappwebview y media_kit) del freeze/"No responde" — tan
    // severo que ni un hot restart lo recupera. player.stop() solo no
    // alcanza (para de decodificar, pero no libera la textura nativa) —
    // isWebViewActive saca el widget Video del árbol entero mientras el
    // WebView esté arriba (ver VideoPlayerConten).
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
      builder: (ctx) => FluentTheme(
        // showDialog inserta esto en el Overlay del Navigator raíz, fuera
        // del FluentTheme(dark) local de este widget — sin este wrap
        // quedaba con el tema claro/celeste por defecto de toda la app en
        // vez del oscuro+morado del reproductor.
        data: FluentTheme.of(context).copyWith(
          accentColor:
              AccentColor.swatch(const {'normal': HomeTheme.accentPink}),
        ),
        child: ContentDialog(
          title: const Text('¡Un momento!'),
          content: Text(
            'Parece que anteriormente estabas mirando este vídeo$serverStr. '
            '¿Deseas continuar donde te quedaste? $timeStr',
          ),
          actions: [
            Button(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _c.cancelResume();
              },
            ),
            FilledButton(
              child: const Text('Aceptar'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _c.confirmResume(secs);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _resetHideTimer(),
      // El puntero se esconde junto con los controles: quedaba una flecha
      // flotando sobre el vídeo a pantalla completa.
      cursor: _showControls ? MouseCursor.defer : SystemMouseCursors.none,
      child: FluentTheme(
        data: FluentThemeData(
          brightness: Brightness.dark,
        ),
        // Focus y no KeyboardListener: KeyboardListener NO consume la tecla,
        // solo la escucha. El evento seguia su camino y Flutter aplicaba su
        // accion por defecto para ESC, que es cerrar la ruta — asi que al
        // apretar ESC en pantalla completa pasaban las DOS cosas: se salia de
        // pantalla completa Y se cerraba el reproductor. Devolviendo
        // `handled` el atajo se queda con la tecla y nadie mas la ve.
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (node, value) {
            // _c.disposed: la pantalla puede quedar montada un instante de
            // más durante la transición de salida — sin este guard, un
            // atajo de teclado (space, flechas, medios) tocado justo
            // entonces llamaba directo al Player nativo ya disposed y
            // tumbaba la app entera (mismo bug que los botones de play/
            // pause/seek "crudos", ver safePlay/safePause/seek).
            if (value is! KeyDownEvent || _c.disposed) {
              return KeyEventResult.ignored;
            }
            final atajo = _c.keyboardShortcuts[value.logicalKey];
            if (atajo == null) return KeyEventResult.ignored;
            atajo();
            return KeyEventResult.handled;
          },
          child: Stack(
            children: [
              // Cuánto saltó el último atajo (teclas I/J y flechas). Sin
              // esto no había ninguna devolución: se apretaba una tecla y no
              // se sabía si había hecho algo ni cuánto se movió.
              Positioned.fill(
                child: IgnorePointer(
                  child: Obx(() {
                    final salto = _c.lastSkipSeconds.value;
                    return AnimatedScale(
                      // Ver el mismo cartel en mobile: entra con un rebote
                      // corto para que acompañe al gesto y no llegue tarde.
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutBack,
                      scale: salto == null ? 0.85 : 1,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 90),
                        opacity: salto == null ? 0 : 1,
                        child: Align(
                          alignment: const Alignment(0, -0.55),
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
                                material.Icon(
                                  (salto ?? 0) < 0
                                      ? material.Icons.fast_rewind
                                      : material.Icons.fast_forward,
                                  color: HomeTheme.accentPink,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${(salto ?? 0).abs()} s',
                                  style: const TextStyle(
                                    color: material.Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
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
                                    // Si hay un error en pantalla, ahi hay una
                                    // tarjeta con su boton (reintentar / elegir
                                    // otro servidor) y NO se esta cargando
                                    // nada: la rueda girando detras hacia
                                    // pensar que algo seguia en curso.
                                    _c.error.value.isEmpty &&
                                    // Mismo caso que el error de arriba: el
                                    // aviso de "el servidor fallo, toca para
                                    // reproducir" espera una accion y no hay
                                    // nada cargando. El fallo de servidor no
                                    // se guarda en `error` —tiene su propio
                                    // campo— asi que la comprobacion anterior
                                    // no lo cubria.
                                    _c.serverFailedMessage.value.isEmpty &&
                                    // Mismo caso: el boton de play espera un
                                    // clic, no hay nada cargando.
                                    !_c.awaitingServerChoice.value &&
                                    // Con el reproductor de WebView activo no
                                    // va a pintarse nunca un cuadro nativo, asi
                                    // que esta rueda giraria para siempre.
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
                                child: material.CircularProgressIndicator(
                                  strokeWidth: 3.5,
                                  valueColor: material.AlwaysStoppedAnimation(
                                      HomeTheme.accentPink),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )),
                ),
              ),
              // subtitle
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
              Positioned.fill(
                child: SizedBox.expand(
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
                            Button(
                              child: Text('common.retry'.i18n),
                              onPressed: () {
                                _c.error.value = '';
                                _c.play();
                              },
                            ),
                          ],
                        );
                      }
                      // Si hay un mensaje (de fallo o estado), no mostrar ni el
                      // card de carga ni el spinner: evita que se superpongan al
                      // aviso del centro de la pantalla.
                      if (_c.serverFailedMessage.value.isNotEmpty) {
                        return const SizedBox.shrink();
                      }
                      // Esperando que el usuario elija un servidor — no se
                      // prueba nada solo hasta que lo haga (evita cargar/
                      // resolver todos los servidores de una al entrar).
                      if (_c.awaitingServerChoice.value) {
                        return GestureDetector(
                          onTap: _c.currentServerName.value.isEmpty
                              ? null
                              : () =>
                                  _c.switchServer(_c.currentServerName.value),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Container(
                              // Fondo sólido detrás de todo el bloque: con
                              // escenas claras del anime, el texto quedaba
                              // encima directo del video y era ilegible.
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 22),
                              decoration: BoxDecoration(
                                color: HomeTheme.cardSurface
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: HomeTheme.border),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: HomeTheme.accentPink,
                                    ),
                                    child: const Icon(FluentIcons.play_solid,
                                        color: Colors.white, size: 32),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Tocá para reproducir el servidor elegido arriba',
                                    style: TextStyle(
                                        fontSize: 15, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      if (!_c.isGettingWatchData.value) {
                        // Entre "el servidor abrió" y "ya se pintó el primer
                        // cuadro" media_kit puede tardar sin que el flag de
                        // buffering llegue a avisar nada (sobre todo HLS) —
                        // sin esto quedaba una pantalla negra sin ningún
                        // spinner, como si estuviera trabada de verdad.
                        if (!_c.hasRenderedFrame.value) {
                          // Sin rueda acá: la capa de carga de arriba del
                          // Stack ya la muestra, más grande y con su disco
                          // oscuro. Antes se dibujaban las DOS a la vez, una
                          // encima de otra, porque comparten condiciones.
                          // Aquella además cubre el salto, que este panel no
                          // detectaba.
                          return const SizedBox.shrink();
                        }
                        // Pausado: nunca mostrar el spinner. mpv sigue
                        // llenando el buffer en segundo plano estando en
                        // pausa (que es lo que queremos, y la sombra de la
                        // barra ya lo muestra), pero dejar el spinner
                        // girando ahí hacía parecer que el reproductor se
                        // quedó trabado justo cuando el usuario pausó a
                        // propósito.
                        if (!_c.isPlaying.value) {
                          return const SizedBox.shrink();
                        }
                        // isActuallyBuffering (no el flag crudo de mpv) ya
                        // descuenta los casos en que el video sigue
                        // avanzando de verdad pero el flag quedó pegado en
                        // true — ver VideoPlayerController.
                        if (_c.isActuallyBuffering.value) {
                          // Sin rueda acá: la capa de carga de arriba del
                          // Stack ya la muestra, más grande y con su disco
                          // oscuro. Antes se dibujaban las DOS a la vez, una
                          // encima de otra, porque comparten condiciones.
                          // Aquella además cubre el salto, que este panel no
                          // detectaba.
                          return const SizedBox.shrink();
                        }
                        return const SizedBox.shrink();
                      }
                      return Card(
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
                      );
                    }),
                  ),
                ),
              ),
              Positioned.fill(
                child: Column(
                  children: [
                    // header + selector — se ocultan rápido si el mouse no
                    // se mueve (igual que el footer, más abajo).
                    IgnorePointer(
                      ignoring: !_showControls,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          children: [
                            // Obx acá: _c.index.value se leía suelto en el
                            // build de este State (no reactivo), así que el
                            // título arriba solo se actualizaba cuando algo
                            // más disparaba un rebuild — se sentía "atrasado"
                            // al cambiar de capítulo. Envuelto en Obx, sigue
                            // a index.value al toque.
                            Obx(() => _Header(
                                  title: _c.title,
                                  episode: _c.playList[_c.index.value].name,
                                  onClose: () =>
                                      unawaited(_c.closeRoute(context)),
                                )),
                            // selector de servidores — pestañas arriba, no un
                            // botón escondido abajo (a pedido del usuario, y
                            // para que se vea de una cuál es el
                            // recomendado/nativo).
                            _ServerTabBar(controller: _c),
                          ],
                        ),
                      ),
                    ),
                    // center — click para pausar/reproducir (sin tocar el
                    // footer) + notificación de servidor fallido. Solo se
                    // activa cuando el video ya está listo: mientras hay un
                    // overlay bloqueante abajo (elegir servidor, error,
                    // cargando) ese overlay necesita recibir el toque él
                    // mismo (por ej. "tocá para reproducir"), así que acá no
                    // se agrega el GestureDetector encima y el toque le
                    // llega directo.
                    Expanded(
                      child: Obx(() {
                        final blocked = _c.awaitingServerChoice.value ||
                            _c.error.value.isNotEmpty ||
                            _c.isGettingWatchData.value ||
                            !_c.hasRenderedFrame.value;
                        final content = Center(
                          child: Obx(() {
                            final msg = _c.serverFailedMessage.value;
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: msg.isEmpty
                                  ? const SizedBox.shrink()
                                  : Container(
                                      key: const ValueKey('server-failed'),
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 40),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 18),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.78),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange
                                              .withValues(alpha: 0.8),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                FluentIcons.warning,
                                                color: Colors.orange,
                                                size: 28,
                                              ),
                                              const SizedBox(width: 16),
                                              Flexible(
                                                child: Text(
                                                  msg,
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    color: Colors.white,
                                                    height: 1.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Reabrir el WebView sin tener que
                                          // volver a elegir el servidor de
                                          // la lista — antes, al cerrar el
                                          // WebView (botón atrás) y volver
                                          // acá, no había ninguna forma de
                                          // retomarlo.
                                          if (_c.webViewFallback.value !=
                                              null) ...[
                                            const SizedBox(height: 14),
                                            FilledButton(
                                              onPressed: _openWebView,
                                              child: const Text(
                                                  'Volver al navegador interno'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                            );
                          }),
                        );
                        if (blocked) return content;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _c.playOrPause(),
                          // Arrastrar con el boton apretado mueve la camara del
                          // VR. Un clic suelto sigue pausando como siempre:
                          // GestureDetector distingue solo un toque de un
                          // arrastre, asi que los dos gestos conviven sin
                          // pisarse.
                          //
                          // Solo hace algo con el modo VR puesto; sin el,
                          // arrastrar sobre el video no hacia nada y sigue sin
                          // hacerlo.
                          //
                          // El desplazamiento va en fraccion del ancho de la
                          // ventana, asi el recorrido se siente igual en una
                          // pantalla chica que en uno grande. Negativo porque
                          // arrastrar hacia la izquierda mueve la vista hacia
                          // la derecha, como al empujar una foto.
                          onHorizontalDragUpdate: (d) {
                            if (!_c.vrUnaPantalla.value) return;
                            final ancho = MediaQuery.of(context).size.width;
                            if (ancho <= 0) return;
                            _c.moverVr(-d.delta.dx / ancho);
                          },
                          child: content,
                        );
                      }),
                    ),
                    // footer — se oculta rápido si el mouse no se mueve.
                    IgnorePointer(
                      ignoring: !_showControls,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: _Footer(controller: _c),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({
    required this.title,
    required this.episode,
    required this.onClose,
  });
  final String title;
  final String episode;
  final VoidCallback onClose;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              // Mismo patrón que control_panel_header.dart: DragToMoveArea
              // solo en el bloque de título (texto, sin botones), para poder
              // mover la ventana desde ahí sin arriesgar clicks accidentales
              // sobre los controles de al lado.
              child: DragToMoveArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      widget.episode,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(FluentIcons.chevron_down),
            ),
            const SizedBox(width: 10),
            // Minimizar/maximizar/cerrar — sin esto la ventana del
            // reproductor no tenía forma de minimizarse ni maximizarse (el
            // botón "cerrar" de arriba solo vuelve a la pantalla anterior,
            // no es el control de ventana de Windows).
            // WindowCaption pide altura infinita internamente (SizedBox con
            // height: double.infinity) — sin un alto explícito acá, el Row
            // del header recibía una restricción de alto NO acotada y
            // reventaba el layout en pleno frame (justo el error en cascada
            // de "RenderBox was not laid out" que tumbaba TODO el reproductor,
            // no solo esta esquina). control_panel_header.dart no tiene este
            // problema porque ahí todo el header ya tiene height: 40 fijo.
            const SizedBox(
              width: 138,
              height: 32,
              child: _VideoWindowCaptionButtons(),
            ),
          ],
        ),
      ),
    );
  }
}

// Reemplaza el WindowCaption de window_manager (que usa FutureBuilder +
// windowManager.isMaximized() consultado de NUEVO en cada rebuild) por
// estado propio actualizado solo vía WindowListener. En este header, el
// MouseRegion(onHover: _resetHideTimer) del reproductor entero dispara
// setState seguido — cada rebuild relanzaba isMaximized() y el FutureBuilder
// podía mostrar un snapshot viejo justo al hacer click, así que el botón de
// maximizar (el del medio) parecía no responder aunque la ventana sí
// cambiaba de estado. Confirmado en vivo: minimizar/cerrar (llamadas
// directas, sin estado intermedio) siempre funcionaron bien.
class _VideoWindowCaptionButtons extends StatefulWidget {
  const _VideoWindowCaptionButtons();

  @override
  State<_VideoWindowCaptionButtons> createState() =>
      _VideoWindowCaptionButtonsState();
}

class _VideoWindowCaptionButtonsState
    extends State<_VideoWindowCaptionButtons> {
  // Los tres botones viven ahora en BotonesVentana, compartidos con la ventana
  // principal. Estaban escritos dos veces —casi igual— y cada arreglo entraba
  // en uno solo; el de la guarda de pantalla completa es el ultimo ejemplo.
  @override
  Widget build(BuildContext context) =>
      const BotonesVentana(brightness: Brightness.dark);
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.controller,
  });
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                // 当前进度
                StreamBuilder(
                  stream: controller.player.stream.position,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final position = snapshot.data as Duration;
                      return Text(
                        '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _SeekBar(controller: controller),
                ),
                const SizedBox(width: 20),
                // 总时长
                StreamBuilder(
                  stream: controller.player.stream.duration,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final duration = snapshot.data as Duration;
                      return Text(
                        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, constraints) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (constraints.maxWidth > 500)
                    Expanded(
                      flex: 1,
                      child: // 音量
                          Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Volume(player: controller.player),
                          // 画质
                          Obx(() {
                            if (controller.currentQuality.value.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: _Quality(controller: controller),
                            );
                          }),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 上一集 — bloqueado mientras carga, para no disparar
                        // otro cambio de episodio encima de uno ya en curso.
                        Obx(
                          () => IconButton(
                            onPressed: controller.index.value > 0 &&
                                    !controller.isGettingWatchData.value
                                ? () {
                                    controller.index.value--;
                                  }
                                : null,
                            icon: const Icon(
                              FluentIcons.previous,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Obx(() {
                          // Resolviendo el servidor elegido — bloquear el
                          // botón para no permitir otro toque mientras carga.
                          if (controller.isGettingWatchData.value) {
                            return const SizedBox(
                              width: 30,
                              height: 30,
                              child: Padding(
                                padding: EdgeInsets.all(4),
                                child: ProgressRing(
                                  strokeWidth: 2.5,
                                  activeColor: HomeTheme.accentPink,
                                ),
                              ),
                            );
                          }
                          // Todavía no se eligió/cargó ningún servidor — este
                          // botón elige el marcado arriba y arranca a
                          // resolverlo, en vez de jugar con un player vacío.
                          if (controller.awaitingServerChoice.value) {
                            return IconButton(
                              onPressed:
                                  controller.currentServerName.value.isEmpty
                                      ? null
                                      : () => controller.switchServer(
                                          controller.currentServerName.value),
                              icon: const Icon(FluentIcons.play, size: 30),
                            );
                          }
                          // El servidor falló (no se pudo reproducir nativo) —
                          // no hay nada cargado para pausar/reproducir, así
                          // que se bloquea en vez de dejarlo tocable sin efecto.
                          if (controller.serverFailedMessage.value.isNotEmpty) {
                            return const IconButton(
                              onPressed: null,
                              icon: Icon(FluentIcons.play, size: 30),
                            );
                          }
                          return StreamBuilder(
                            stream: controller.player.stream.playing,
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data! ||
                                  controller.player.state.playing) {
                                return IconButton(
                                  onPressed: controller.safePause,
                                  icon: const Icon(
                                    FluentIcons.pause,
                                    size: 30,
                                  ),
                                );
                              }
                              return IconButton(
                                onPressed: controller.safePlay,
                                icon: const Icon(
                                  FluentIcons.play,
                                  size: 30,
                                ),
                              );
                            },
                          );
                        }),
                        const SizedBox(width: 20),
                        // 下一集 — bloqueado mientras carga.
                        Obx(
                          () => IconButton(
                            onPressed: controller.playList.length - 1 >
                                        controller.index.value &&
                                    !controller.isGettingWatchData.value
                                ? () {
                                    controller.index.value++;
                                  }
                                : null,
                            icon: const Icon(
                              FluentIcons.next,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (constraints.maxWidth > 500)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // playback speed
                            if (constraints.maxWidth > 700)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _Speed(controller: controller),
                              ),
                            // torrent files
                            if (constraints.maxWidth > 700)
                              Obx(() {
                                if (controller.torrentMediaFileList.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _TorrentFiles(
                                    controller: controller,
                                  ),
                                );
                              }),
                            // track
                            _Track(controller: controller),
                            const SizedBox(width: 10),
                            // cast (DLNA) — antes solo en celular
                            _Cast(controller: controller),
                            const SizedBox(width: 10),

                            // 剧集
                            _Episode(controller: controller),

                            const SizedBox(width: 10),
                            // 全屏
                            Obx(
                              () => IconButton(
                                onPressed: () {
                                  controller.toggleFullscreen();
                                },
                                icon: Icon(
                                  controller.isFullScreen.value
                                      ? FluentIcons.back_to_window
                                      : FluentIcons.full_screen,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // 设置
                            IconButton(
                              onPressed: () {
                                final showPlayList =
                                    controller.showSidebar.value;
                                controller.showSidebar.value = !showPlayList;
                              },
                              icon: const Icon(
                                FluentIcons.settings,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            })
          ],
        ),
      ),
    );
  }
}

class _Volume extends StatefulWidget {
  const _Volume({required this.player});
  final Player player;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  final _controller = FlyoutController();
  final _volume = 0.0.obs;
  StreamSubscription<double>? _volumeSub;

  @override
  void initState() {
    super.initState();
    _volume.value = widget.player.state.volume;
    // Antes el valor se leía una sola vez al crear el widget y quedaba
    // pegado — si el volumen cambiaba por otro lado (atajo de teclado, DLNA,
    // etc.) el ícono y el slider del flyout seguían mostrando el valor
    // viejo. Escuchar el stream real lo mantiene siempre sincronizado.
    _volumeSub = widget.player.stream.volume.listen((v) {
      _volume.value = v;
    });
  }

  void _onVolumeChanged(double value) {
    _volume.value = value;
    widget.player.setVolume(value);
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _controller,
      child: IconButton(
        icon: Obx(
          () => Icon(
            _volume.value == 0
                ? FluentIcons.volume0
                : _volume.value < 50
                    ? FluentIcons.volume1
                    : _volume.value < 100
                        ? FluentIcons.volume2
                        : FluentIcons.volume3,
          ),
        ),
        onPressed: () {
          _controller.showFlyout(
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            builder: (context) {
              return FluentTheme(
                data: FluentThemeData.dark().copyWith(
                  accentColor: AccentColor.swatch(
                      const {'normal': HomeTheme.accentPink}),
                ),
                child: FlyoutContent(
                  useAcrylic: true,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Obx(
                          () => Icon(
                            _volume.value == 0
                                ? FluentIcons.volume0
                                : _volume.value < 50
                                    ? FluentIcons.volume1
                                    : _volume.value < 100
                                        ? FluentIcons.volume2
                                        : FluentIcons.volume3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Obx(
                          () => SizedBox(
                            height: 30,
                            child: Slider(
                              value: _volume.value,
                              // Pasa de 100 —el volumen original— para poder
                              // levantar material grabado bajo. Ver
                              // VideoPlayerController.volumenMaximo.
                              max: VideoPlayerController.volumenMaximo,
                              // El 100 marcado: es el punto donde deja de
                              // subirse el volumen y empieza a amplificarse,
                              // asi que conviene verlo.
                              divisions:
                                  VideoPlayerController.volumenMaximo ~/ 5,
                              label: '${_volume.value.round()}%',
                              onChanged: _onVolumeChanged,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Obx(
                          () => Text(
                            _volume.value.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Episode extends StatefulWidget {
  const _Episode({
    required this.controller,
  });

  final VideoPlayerController controller;

  @override
  State<_Episode> createState() => _EpisodeState();
}

class _EpisodeState extends State<_Episode> {
  final controller = FlyoutController();

  @override
  dispose() {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FluentTheme(
      data: FluentThemeData.dark(),
      child: FlyoutTarget(
        controller: controller,
        child: IconButton(
          icon: const Icon(FluentIcons.playlist_music),
          onPressed: () {
            controller.showFlyout(
              // true: clickear afuera de la lista sí la cierra.
              barrierDismissible: true,
              // false: en cambio, mover el mouse hacia abajo dentro de la
              // propia lista de episodios NO la cierra (cortaba el scroll).
              dismissOnPointerMoveAway: false,
              builder: (context) {
                return FluentTheme(
                  data: FluentThemeData.dark().copyWith(
                    accentColor: AccentColor.swatch(
                        const {'normal': HomeTheme.accentPink}),
                  ),
                  child: FlyoutContent(
                    padding: const EdgeInsets.all(0),
                    useAcrylic: true,
                    child: Container(
                      width: 300,
                      constraints: const BoxConstraints(
                        maxHeight: 500,
                      ),
                      child: PlayList(
                        title: widget.controller.title,
                        list: widget.controller.playList
                            .map((e) => e.name)
                            .toList(),
                        selectIndex: widget.controller.index.value,
                        onChange: (value) {
                          // Bloqueado mientras carga — sin esto se podía
                          // elegir otro capítulo encima de uno que todavía
                          // estaba resolviendo.
                          if (widget.controller.isGettingWatchData.value) {
                            return;
                          }
                          widget.controller.index.value = value;
                          Flyout.of(context).close();
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Quality extends StatefulWidget {
  const _Quality({
    required this.controller,
  });

  final VideoPlayerController controller;

  @override
  State<_Quality> createState() => _QualityState();
}

class _QualityState extends State<_Quality> {
  final controller = FlyoutController();

  @override
  dispose() {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: controller,
      child: Button(
        child: Text(widget.controller.currentQuality.value),
        onPressed: () {
          // Ver hayCalidades en el controlador: pueden venir del playlist HLS
          // o de la cabecera X-Servers de la extensión. Mirando solo el
          // primero, este botón decía "no hay calidades" en vídeos que traen
          // siete — Eporner entrega las suyas por ese camino.
          if (!widget.controller.hayCalidades) {
            widget.controller.sendMessage(
              Message(Text("video.no-qualities".i18n)),
            );
            return;
          }
          controller.showFlyout(
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            builder: (context) {
              return FluentTheme(
                data: FluentThemeData.dark(),
                child: FlyoutContent(
                  useAcrylic: true,
                  child: Container(
                    width: 200,
                    constraints: const BoxConstraints(
                      maxHeight: 300,
                    ),
                    // Las dos fuentes en la MISMA lista: el usuario abre
                    // "calidad" y ve calidades, sin tener que saber si el
                    // sitio las entrega como playlist o como una url por
                    // resolución. Cada una se cambia con su propio método,
                    // que es lo único que difiere por detrás.
                    child: ListView(
                      children: [
                        // La que se esta viendo lleva tilde y color: sin eso
                        // la lista no decia cual estaba puesta.
                        if (widget.controller.qualityMap.isNotEmpty)
                          for (final quality
                              in widget.controller.qualityMap.entries)
                            ListTile(
                              title: Text(quality.key),
                              trailing: quality.key ==
                                      widget.controller.currentQuality.value
                                  ? const Icon(FluentIcons.check_mark,
                                      size: 12, color: HomeTheme.accentPink)
                                  : null,
                              onPressed: () {
                                widget.controller.switchQuality(
                                  quality.value,
                                );
                                Flyout.of(context).close();
                              },
                            )
                        else
                          for (final servidor
                              in widget.controller.availableServers.keys)
                            ListTile(
                              title: Text(servidor),
                              trailing: servidor ==
                                      widget.controller.currentServerName.value
                                  ? const Icon(FluentIcons.check_mark,
                                      size: 12, color: HomeTheme.accentPink)
                                  : null,
                              onPressed: () {
                                widget.controller.switchServer(servidor);
                                Flyout.of(context).close();
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Track extends StatefulWidget {
  const _Track({
    required this.controller,
  });

  final VideoPlayerController controller;

  @override
  State<_Track> createState() => _TrackState();
}

class _TrackState extends State<_Track> {
  final controller = FlyoutController();

  @override
  dispose() {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: controller,
      child: IconButton(
        icon: const Icon(FluentIcons.locale_language),
        onPressed: () {
          controller.showFlyout(
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            builder: (context) {
              return FluentTheme(
                data: FluentThemeData.dark().copyWith(
                  accentColor: AccentColor.swatch(
                      const {'normal': HomeTheme.accentPink}),
                ),
                child: FlyoutContent(
                  useAcrylic: true,
                  padding: const EdgeInsets.all(0),
                  child: Container(
                    width: 220,
                    constraints: const BoxConstraints(
                      maxHeight: 300,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            "video.subtitle".i18n,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withAlpha(200),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        ListTile.selectable(
                          selected: SubtitleTrack.no() ==
                              widget.controller.player.state.track.subtitle,
                          title: Text('common.off'.i18n),
                          onPressed: () {
                            widget.controller.setSubtitleTrack(
                              SubtitleTrack.no(),
                            );
                            Flyout.of(context).close();
                          },
                        ),
                        ListTile.selectable(
                          title: Text('video.subtitle-file'.i18n),
                          onPressed: () {
                            widget.controller.addSubtitleFile();
                          },
                        ),
                        // 来自扩展的字幕
                        for (final subtitle in widget.controller.subtitles)
                          ListTile.selectable(
                            selected: subtitle ==
                                widget.controller.player.state.track.subtitle,
                            title: Text(subtitle.title ?? ''),
                            subtitle: Text(subtitle.language ?? ''),
                            onPressed: () {
                              widget.controller.setSubtitleTrack(
                                subtitle,
                              );
                              Flyout.of(context).close();
                            },
                          ),
                        // 来自视频的字幕
                        for (final subtitle
                            in widget.controller.player.state.tracks.subtitle)
                          if (subtitle != SubtitleTrack.no() &&
                              (subtitle.language != null ||
                                  subtitle.title != null))
                            ListTile.selectable(
                              selected: subtitle ==
                                  widget.controller.player.state.track.subtitle,
                              title: Text(subtitle.title ?? ''),
                              subtitle: Text(subtitle.language ?? ''),
                              onPressed: () {
                                widget.controller.setSubtitleTrack(
                                  subtitle,
                                );
                                Flyout.of(context).close();
                              },
                            ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            "video.audio".i18n,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withAlpha(200),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        // 来自视频的音轨
                        for (final audio
                            in widget.controller.player.state.tracks.audio)
                          if (audio.language != null || audio.title != null)
                            ListTile.selectable(
                              selected: audio ==
                                  widget.controller.player.state.track.audio,
                              title: Text(audio.title ?? ''),
                              subtitle: Text(audio.language ?? ''),
                              onPressed: () {
                                widget.controller.player.setAudioTrack(
                                  audio,
                                );
                                Flyout.of(context).close();
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Cast (DLNA) — antes solo estaba en el reproductor de celular; en PC no
// había ninguna forma de abrirlo. Reutiliza VideoPlayerCast (la misma
// búsqueda de dispositivos que ya funciona en Android) envuelto en
// Material — ese widget usa ListTile de Material, que sin un ancestro
// Material tira "No Material widget found" en este árbol, que corre sobre
// fluent_ui (mismo problema ya conocido en este codebase para TextField).
class _Cast extends StatefulWidget {
  const _Cast({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_Cast> createState() => _CastState();
}

class _CastState extends State<_Cast> {
  final _flyoutController = FlyoutController();

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _flyoutController,
      child: Obx(() {
        final connected = widget.controller.dlnaDevice.value != null;
        return IconButton(
          icon: Icon(
            connected
                ? FluentIcons.t_v_monitor_selected
                : FluentIcons.screen_cast,
            color: connected ? HomeTheme.accentPink : null,
          ),
          onPressed: () {
            _flyoutController.showFlyout(
              barrierDismissible: true,
              dismissOnPointerMoveAway: false,
              builder: (context) {
                return FluentTheme(
                  data: FluentThemeData.dark().copyWith(
                    accentColor: AccentColor.swatch(
                        const {'normal': HomeTheme.accentPink}),
                  ),
                  child: FlyoutContent(
                    useAcrylic: true,
                    padding: const EdgeInsets.all(0),
                    child: Container(
                      width: 280,
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: Obx(() {
                        final device = widget.controller.dlnaDevice.value;
                        if (device != null) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'video.cast'.i18n,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withAlpha(200),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  device.info.friendlyName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                FilledButton(
                                  child: Text('video.cast-disconnect'.i18n),
                                  onPressed: () {
                                    widget.controller.disconnectDLNADevice();
                                    Flyout.of(context).close();
                                  },
                                ),
                              ],
                            ),
                          );
                        }
                        return material.Material(
                          type: material.MaterialType.transparency,
                          child: material.Theme(
                            data: material.ThemeData.dark(useMaterial3: true),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: VideoPlayerCast(
                                onDeviceSelected: (selected) {
                                  widget.controller.connectDLNADevice(selected);
                                  Flyout.of(context).close();
                                },
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                );
              },
            );
          },
        );
      }),
    );
  }
}

class _TorrentFiles extends StatefulWidget {
  const _TorrentFiles({
    required this.controller,
  });

  final VideoPlayerController controller;

  @override
  State<_TorrentFiles> createState() => _TorrentFilesState();
}

class _TorrentFilesState extends State<_TorrentFiles> {
  final controller = FlyoutController();

  @override
  dispose() {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: controller,
      child: IconButton(
        icon: const Icon(FluentIcons.folder_open),
        onPressed: () {
          controller.showFlyout(
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            builder: (context) {
              return FluentTheme(
                data: FluentThemeData.dark().copyWith(
                  accentColor: AccentColor.swatch(
                      const {'normal': HomeTheme.accentPink}),
                ),
                child: FlyoutContent(
                  useAcrylic: true,
                  padding: const EdgeInsets.all(0),
                  child: Container(
                    width: 300,
                    constraints: const BoxConstraints(
                      maxHeight: 300,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final file
                            in widget.controller.torrentMediaFileList)
                          ListTile.selectable(
                            title: Text(
                              file,
                              style: const TextStyle(fontSize: 13),
                            ),
                            selected:
                                widget.controller.currentTorrentFile.value ==
                                    file,
                            onPressed: () {
                              widget.controller.playTorrentFile(file);
                              Flyout.of(context).close();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Speed extends StatefulWidget {
  const _Speed({
    required this.controller,
  });

  final VideoPlayerController controller;

  @override
  State<_Speed> createState() => _SpeedState();
}

class _SpeedState extends State<_Speed> {
  final controller = FlyoutController();

  @override
  dispose() {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: controller,
      child: Button(
        child: Obx(() => Text('x${widget.controller.currentSpeed.value}')),
        onPressed: () {
          controller.showFlyout(
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            builder: (context) {
              return FluentTheme(
                data: FluentThemeData.dark().copyWith(
                  accentColor: AccentColor.swatch(
                      const {'normal': HomeTheme.accentPink}),
                ),
                child: FlyoutContent(
                  useAcrylic: true,
                  padding: const EdgeInsets.all(0),
                  child: Container(
                    width: 200,
                    constraints: const BoxConstraints(
                      maxHeight: 300,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final speed in widget.controller.speedList)
                          ListTile.selectable(
                            title: Text(
                              speed.toStringAsFixed(2),
                              style: const TextStyle(fontSize: 13),
                            ),
                            selected:
                                widget.controller.currentSpeed.value == speed,
                            onPressed: () {
                              widget.controller.player.setRate(speed);
                              widget.controller.currentSpeed.value = speed;
                              Flyout.of(context).close();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
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
  Duration position = const Duration();
  Duration duration = const Duration();
  // Cuánto lleva descargado/cacheado el demuxer más allá de la posición
  // actual — mpv sigue llenando este buffer en segundo plano aunque el
  // video esté en pausa (pausar solo detiene decodificación, no la
  // descarga). Se muestra como una "sombra" en la barra, igual que en
  // Android (que ya lo tenía vía Slider.secondaryTrackValue nativo).
  Duration buffer = const Duration();
  bool _isDrag = false;
  StreamSubscription<Duration>? positionSubscription;
  StreamSubscription<Duration>? durationSubscription;
  StreamSubscription<Duration>? bufferSubscription;

  @override
  void initState() {
    super.initState();
    positionSubscription =
        widget.controller.player.stream.position.listen((event) {
      if (!_isDrag && mounted) {
        setState(() => position = event);
      }
    });
    durationSubscription =
        widget.controller.player.stream.duration.listen((event) {
      if (mounted) {
        setState(() => duration = event);
      }
    });
    bufferSubscription = widget.controller.player.stream.buffer.listen((event) {
      if (mounted) {
        setState(() => buffer = event);
      }
    });
  }

  @override
  void dispose() {
    positionSubscription?.cancel();
    durationSubscription?.cancel();
    bufferSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxSeconds = duration.inSeconds < position.inSeconds
        ? position.inSeconds.toDouble()
        : duration.inSeconds.toDouble();
    final currentSeconds = position.inSeconds.toDouble();
    final playedFraction =
        maxSeconds <= 0 ? 0.0 : (currentSeconds / maxSeconds).clamp(0.0, 1.0);
    final bufferFraction =
        maxSeconds <= 0 ? 0.0 : (buffer.inSeconds / maxSeconds).clamp(0.0, 1.0);
    // Solo el tramo entre "ya reproducido" y "ya bufferizado" — si se
    // dibujara desde 0 taparía la parte ya reproducida (rosa) y el thumb.
    final shadowFraction = (bufferFraction - playedFraction).clamp(0.0, 1.0);

    return FluentTheme(
      data: FluentTheme.of(context).copyWith(
        accentColor: AccentColor.swatch(const {'normal': HomeTheme.accentPink}),
      ),
      // Sin altura fija: el Stack se ajusta solo a la altura natural del
      // Slider (el hijo más alto, sin posicionar).
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // El Slider con su track normal (visible, sin tocar) — antes
          // esto quedaba transparente y, si todavía no había buffer
          // reportado, no quedaba NADA visible después del thumb.
          Slider(
            value: currentSeconds.clamp(0, maxSeconds <= 0 ? 0 : maxSeconds),
            max: maxSeconds,
            label:
                '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}',
            onChanged: (value) {
              _isDrag = true;
              setState(() {
                position = Duration(seconds: value.toInt());
              });
            },
            onChangeEnd: (value) {
              _isDrag = false;
              widget.controller.seek(
                Duration(
                  seconds: value.toInt(),
                ),
              );
            },
          ),
          // Sombra del buffer — dibujada ENCIMA del track normal, alineada
          // al track REAL del Slider de fluent_ui (padding horizontal fijo
          // de 10px a cada lado, _trackSidePadding en el paquete).
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  return SizedBox(
                    height: 4,
                    child: Row(
                      children: [
                        SizedBox(width: trackWidth * playedFraction),
                        Container(
                          width: trackWidth * shadowFraction,
                          decoration: BoxDecoration(
                            // Rosa (no gris) — el track base del Slider es
                            // blanco/claro, y un gris quedaba invisible
                            // contra eso. Con esto queda una gradación
                            // clara: rosa sólido (reproducido) → rosa
                            // (bufferizado) → blanco (nada aún).
                            color: HomeTheme.accentPink.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Selector de Servidores — fila de pestañas arriba del video ─────────────

class _ServerTabBar extends StatefulWidget {
  const _ServerTabBar({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_ServerTabBar> createState() => _ServerTabBarState();
}

class _ServerTabBarState extends State<_ServerTabBar> {
  final _scroll = ScrollController();
  bool _desborda = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Cuanto se corre con cada flecha. Casi todo el ancho visible, dejando un
  /// pedacito a la vista para no perder la referencia de donde se estaba.
  void _correr(double signo) {
    if (!_scroll.hasClients) return;
    final salto = _scroll.position.viewportDimension * 0.8;
    _scroll.animateTo(
      (_scroll.offset + salto * signo)
          .clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  /// Anota si hace falta mostrar las flechas.
  ///
  /// Se mira DESPUES de que la fila se midio: durante el build todavia no se
  /// sabe cuanto ocupa, y preguntarlo ahi da siempre cero.
  void _revisarDesborde() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final hay = _scroll.position.maxScrollExtent > 1;
      if (hay != _desborda) setState(() => _desborda = hay);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Ver servidoresSonAparte: esta tira es para elegir FUENTE. Cuando la
      // extension entrega un MP4 por resolucion, lo que hay aca no son
      // servidores sino las mismas calidades que ya ofrece el boton de abajo, y
      // quedaban las dos cosas en pantalla diciendo lo mismo.
      if (!widget.controller.servidoresSonAparte)
        return const SizedBox.shrink();
      final current = widget.controller.currentServerName.value;
      _revisarDesborde();

      // Sin titulo.
      //
      // Decia "Servidores disponibles" arriba de las pastillas y se veia
      // pesado: una linea de texto fija encima del video, siempre, para
      // nombrar algo que las propias pastillas ya dejan claro. El nombre sigue
      // estando donde hace falta —el panel del telefono, que si es una lista
      // dentro de un menu— pero aca sobra.
      //
      // Las flechas aparecen SOLO cuando los servidores no entran. Con tres o
      // cuatro no hace falta nada; con diez, antes habia que arrastrar de
      // costado sobre el video, que ademas peleaba con los gestos del
      // reproductor.
      return Container(
        width: double.infinity,
        color: Colors.black.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            if (_desborda)
              _FlechaTira(
                icono: FluentIcons.chevron_left,
                onTap: () => _correr(-1),
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry
                        in widget.controller.availableServers.entries) ...[
                      _ServerTab(
                        label: entry.key,
                        selected: entry.key == current,
                        isNative: isKnownNativeServer(entry.key, entry.value),
                        onTap: () => widget.controller.selectServer(entry.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            if (_desborda)
              _FlechaTira(
                icono: FluentIcons.chevron_right,
                onTap: () => _correr(1),
              ),
          ],
        ),
      );
    });
  }
}

/// Flecha para correr la tira de servidores cuando no entran todos.
class _FlechaTira extends StatelessWidget {
  const _FlechaTira({required this.icono, required this.onTap});
  final IconData icono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icono, size: 12, color: HomeTheme.textPrimary),
        onPressed: onTap,
      ),
    );
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            // Fondo sólido (no translúcido): con escenas claras del anime
            // detrás, el texto se volvía ilegible. selected pasa a violeta
            // sólido de verdad, así que el texto ahí va blanco (violeta
            // sobre violeta era invisible).
            color: selected ? HomeTheme.accentPink : HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? HomeTheme.accentPink : HomeTheme.border,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: HomeTheme.accentPink.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              if (isNative) ...[
                const SizedBox(width: 6),
                Icon(
                  FluentIcons.lightning_bolt,
                  size: 12,
                  color: selected
                      ? Colors.white
                      : const Color(0xFF69F0AE).withValues(alpha: 0.85),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
