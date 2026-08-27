import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/pages/watch/video/video_player_desktop_controls.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

// ─── Los controles del reproductor en Android TV ────────────────────────
//
// ── Lo que NO se toca ───────────────────────────────────────────────────
//
// Debajo de esta barra sigue montado `VideoPlayerDesktopControls` en modo
// `soloLogica`: invisible, pero haciendo su trabajo. Ahí viven los
// vigilantes que abren el navegador interno cuando un servidor no se puede
// reproducir de forma nativa, el aviso de "seguí donde quedaste" y la espera
// del tutorial.
//
// Se aprendió por las malas: la primera versión de esta pantalla los
// reemplazaba por completo y el vídeo quedaba en negro, porque nadie
// escuchaba esas señales. El reproductor es la zona más delicada de la app
// y su lógica no se reescribe — solo se le cambia la cara.
//
// ── Lo que sí cambia ────────────────────────────────────────────────────
//
//   · Con el vídeo corriendo la pantalla está limpia; cualquier tecla trae
//     la barra, que se va sola a los segundos.
//   · La barra dice QUÉ HACE CADA TECLA. En un mando no hay nada que
//     descubrir tocando: si no está escrito, no se sabe.
//   · Bajando aparecen las opciones (servidores) en la misma barra, sin
//     abrir otra pantalla; subiendo, se vuelven a esconder.

/// Cuánto salta cada pulsación de ◀ ▶.
const _salto = Duration(seconds: 10);

/// Cuánto tarda la barra en irse sola cuando nadie toca nada.
const _esperaParaOcultar = Duration(seconds: 5);

class VideoPlayerTvControls extends StatefulWidget {
  const VideoPlayerTvControls({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<VideoPlayerTvControls> createState() => _VideoPlayerTvControlsState();
}

class _VideoPlayerTvControlsState extends State<VideoPlayerTvControls> {
  VideoPlayerController get _c => widget.controller;

  final _foco = FocusNode(debugLabel: 'reproductor-tv');

  // ── Por qué la lista de servidores necesita SU PROPIO FocusNode ─────────
  //
  // Reportado en vivo: al desplegar servidores con ▼, el mando no dejaba
  // elegir ninguno -ni con las flechas ni con OK. `_Servidores` le pedía
  // `autofocus: true` a la tarjeta del servidor sonando, pero autofocus en
  // Flutter solo hace algo si el FocusScope todavía no tiene NADA enfocado
  // — y acá siempre había algo: `_foco` (el de esta barra, más arriba en el
  // MISMO scope) ya se había quedado con el foco desde que se montó la
  // pantalla, mucho antes de que las opciones se abrieran. La tarjeta del
  // servidor se dibujaba, pedía foco, y no se lo daban: el mando seguía
  // "parado" en `_foco`, que con las opciones abiertas solo entiende
  // ◀ subir/escape/atrás para CERRARLAS — cualquier otra tecla (flechas
  // para moverse entre servidores, OK para elegir uno) no tenía a quién
  // llegarle.
  //
  // Con este nodo pedido a mano (ver dónde se llama `.requestFocus()` más
  // abajo) el foco se mueve de verdad al abrir las opciones, y desde ahí
  // las flechas SÍ encuentran las otras tarjetas (recorrido geométrico de
  // Flutter, igual que en el resto de la app) y OK dispara el `onTap` de la
  // tarjeta enfocada — que es exactamente lo que `FocusableCard` ya sabe
  // hacer.
  final _focoServidorElegido = FocusNode(debugLabel: 'servidor-elegido-tv');

  bool _barraVisible = true;

  /// Las opciones (servidores) están desplegadas.
  bool _opciones = false;

  Timer? _paraOcultar;

  /// Vigila cuándo el reproductor se queda esperando que se elija servidor.
  Worker? _vigiaDeLaEleccion;

  @override
  void initState() {
    super.initState();
    _reiniciarEspera();
    // ── Con varios servidores, el vídeo NO arranca solo ─────────────────
    //
    // Es a propósito (ver play() en el controlador): probar los cinco o seis
    // servidores al abrir cada episodio gasta red de más. La app espera a
    // que el usuario elija uno.
    //
    // Pero acá los servidores viven escondidos detrás de ▼, así que la
    // pantalla quedaba en negro con 00:00 y nada explicaba por qué —
    // reportado en un televisor real. Al levantarse esa bandera, las
    // opciones se abren solas: es justo el momento en que hay que elegir.
    if (_c.awaitingServerChoice.value) {
      _opciones = true;
      _pedirFocoServidor();
    }
    _vigiaDeLaEleccion = ever(_c.awaitingServerChoice, (bool esperando) {
      if (!mounted || !esperando) return;
      setState(() {
        _opciones = true;
        _barraVisible = true;
      });
      _paraOcultar?.cancel();
      _pedirFocoServidor();
    });
  }

  @override
  void dispose() {
    _vigiaDeLaEleccion?.dispose();
    _paraOcultar?.cancel();
    _foco.dispose();
    _focoServidorElegido.dispose();
    super.dispose();
  }

  /// Mueve el foco de verdad a la lista de servidores — ver el porqué en el
  /// comentario de [_focoServidorElegido].
  ///
  /// Después del frame: la tarjeta recién se dibuja en este mismo build (o
  /// en el que dispara `setState`), así que pedirle foco antes de que su
  /// `RenderObject`/`FocusNode` esté de verdad adjunto al árbol no hace
  /// nada.
  void _pedirFocoServidor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoServidorElegido.requestFocus();
    });
  }

  void _reiniciarEspera() {
    _paraOcultar?.cancel();
    if (!_barraVisible && mounted) setState(() => _barraVisible = true);
    // Con las opciones desplegadas no se esconde nada: el usuario está
    // eligiendo algo y que se le desvanezca la pantalla sería absurdo.
    if (_opciones) return;
    _paraOcultar = Timer(_esperaParaOcultar, () {
      if (mounted) setState(() => _barraVisible = false);
    });
  }

  KeyEventResult _tecla(FocusNode node, KeyEvent evento) {
    if (evento is! KeyDownEvent) return KeyEventResult.ignored;
    // El guard de siempre: la pantalla puede quedar montada un instante de
    // más al salir, y hablarle al reproductor ya cerrado tumba la app.
    if (_c.disposed) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;

    // Con las opciones abiertas, las flechas son para moverse entre los
    // servidores: no se tocan acá. Solo se atiende cerrar.
    if (_opciones) {
      if (tecla == LogicalKeyboardKey.arrowUp ||
          tecla == LogicalKeyboardKey.escape ||
          tecla == LogicalKeyboardKey.goBack) {
        setState(() => _opciones = false);
        _foco.requestFocus();
        _reiniciarEspera();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    _reiniciarEspera();

    if (tecla == LogicalKeyboardKey.select ||
        tecla == LogicalKeyboardKey.enter ||
        tecla == LogicalKeyboardKey.numpadEnter ||
        tecla == LogicalKeyboardKey.space ||
        tecla == LogicalKeyboardKey.mediaPlayPause) {
      _c.playOrPause();
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowRight) {
      _c.seek(_c.position.value + _salto);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowLeft) {
      final destino = _c.position.value - _salto;
      _c.seek(destino < Duration.zero ? Duration.zero : destino);
      return KeyEventResult.handled;
    }
    // Bajar despliega las opciones dentro de la misma barra.
    if (tecla == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _opciones = true;
        _barraVisible = true;
      });
      _paraOcultar?.cancel();
      _pedirFocoServidor();
      return KeyEventResult.handled;
    }
    // Subir: volumen. Llega hasta el doble del original porque hay material
    // grabado muy bajo (ver volumenMaximo en el controlador).
    if (tecla == LogicalKeyboardKey.arrowUp) {
      final v = _c.player.state.volume + 5;
      _c.player.setVolume(v.clamp(0, VideoPlayerController.volumenMaximo));
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.escape ||
        tecla == LogicalKeyboardKey.goBack) {
      unawaited(_c.closeRoute(context));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // El motor: invisible, pero es lo que hace andar el reproductor.
        VideoPlayerDesktopControls(controller: _c, soloLogica: true),
        // ── "Elegí un servidor" ─────────────────────────────────────────
        //
        // Con varios servidores el vídeo NO arranca solo — es a propósito
        // (ver play() en el controlador): probar los cinco o seis de una
        // gasta red de más, así que espera a que el usuario elija.
        //
        // En PC eso se dice con un cartel en el medio de la pantalla. Acá
        // faltaba: quedaba todo negro con 00:00 y nada explicaba que había
        // que hacer algo. Reportado en un televisor real.
        // ── Fallo del servidor ──────────────────────────────────────────
        //
        // Mismo criterio que en PC: se dice qué pasó y se ofrece reintentar,
        // en vez de dejar la pantalla en negro. Es de lo más común acá — un
        // servidor que se cae — y sin aviso parece que la app se colgó.
        Obx(() {
          if (_c.error.value.isEmpty) return const SizedBox.shrink();
          return Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 34, vertical: 26),
              decoration: BoxDecoration(
                color: HomeTheme.oscuroSuperficie.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: HomeTheme.oscuroBorde),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 40, color: HomeTheme.accentRed),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      _c.error.value,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FocusableCard(
                    borderRadius: 10,
                    autofocus: true,
                    onTap: () {
                      _c.error.value = '';
                      // Se vuelve a la eleccion de servidor: reintentar el
                      // mismo que acaba de fallar rara vez sirve, y la lista
                      // es justo lo que hace falta ver.
                      _c.awaitingServerChoice.value = true;
                      setState(() => _opciones = true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 13),
                      decoration: BoxDecoration(
                        color: HomeTheme.accentPink,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'common.retry'.i18n,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        // ── Cargando ────────────────────────────────────────────────────
        //
        // Entre que el servidor abre y que se pinta el primer cuadro puede
        // pasar un rato largo (sobre todo en HLS) sin que nada avise. En una
        // pantalla grande eso se lee como que se colgó.
        Obx(() {
          final cargando = _c.isGettingWatchData.value ||
              (!_c.hasRenderedFrame.value &&
                  !_c.awaitingServerChoice.value &&
                  _c.error.value.isEmpty);
          if (!cargando) return const SizedBox.shrink();
          return Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 120),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(HomeTheme.accentPink),
                ),
              ),
            ),
          );
        }),
        Obx(() {
          if (!_c.awaitingServerChoice.value) return const SizedBox.shrink();
          return Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 34, vertical: 26),
              decoration: BoxDecoration(
                color: HomeTheme.oscuroSuperficie.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: HomeTheme.oscuroBorde),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined,
                      size: 40, color: HomeTheme.accentPink),
                  const SizedBox(height: 14),
                  Text(
                    'video.tv-elegi-servidor'.i18n,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }),
        Focus(
          focusNode: _foco,
          autofocus: true,
          onKeyEvent: _tecla,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _barraVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_barraVisible,
                child: _Barra(
                  c: _c,
                  opciones: _opciones,
                  focoServidorElegido: _focoServidorElegido,
                  onElegirServidor: (nombre) {
                    _c.selectServer(nombre);
                    setState(() => _opciones = false);
                    _foco.requestFocus();
                    _reiniciarEspera();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La barra de abajo: título, progreso, ayuda de teclas y —desplegadas— las
/// opciones.
class _Barra extends StatelessWidget {
  const _Barra({
    required this.c,
    required this.opciones,
    required this.focoServidorElegido,
    required this.onElegirServidor,
  });

  final VideoPlayerController c;
  final bool opciones;
  final FocusNode focoServidorElegido;
  final void Function(String) onElegirServidor;

  static String _tiempo(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(48, 56, 48, 34),
      decoration: const BoxDecoration(
        // Degradado: la barra no tiene un borde duro contra el vídeo, se va
        // apagando hacia arriba.
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF5000000), Color(0xB3000000), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Las opciones van ARRIBA del progreso y solo cuando se piden:
          // así al desplegarlas la barra crece hacia arriba y el progreso
          // —lo que uno estaba mirando— no se mueve de lugar.
          if (opciones) ...[
            _Servidores(
              c: c,
              onElegir: onElegirServidor,
              focoElegido: focoServidorElegido,
            ),
            const SizedBox(height: 22),
          ],
          Text(
            c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Obx(() {
            final pos = c.position.value;
            final total = c.duration.value;
            final avance = total.inMilliseconds == 0
                ? 0.0
                : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
            return Row(
              children: [
                Text(_tiempo(pos),
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(width: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: avance,
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(HomeTheme.accentPink),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(_tiempo(total),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 15)),
              ],
            );
          }),
          const SizedBox(height: 14),
          Wrap(
            spacing: 22,
            runSpacing: 8,
            children: [
              _Ayuda(tecla: 'OK', que: 'video.tv-ok'.i18n),
              _Ayuda(tecla: '◀ ▶', que: 'video.tv-mover'.i18n),
              _Ayuda(
                tecla: opciones ? '▲' : '▼',
                que: 'video.tv-opciones'.i18n,
              ),
              if (!opciones) _Ayuda(tecla: '▲', que: 'video.tv-volumen'.i18n),
              _Ayuda(tecla: 'EXIT', que: 'video.tv-salir'.i18n),
            ],
          ),
        ],
      ),
    );
  }
}

/// Los servidores, en una fila que se recorre con el mando.
class _Servidores extends StatelessWidget {
  const _Servidores({
    required this.c,
    required this.onElegir,
    required this.focoElegido,
  });

  final VideoPlayerController c;
  final void Function(String) onElegir;

  /// El nodo del servidor actualmente elegido — ver por qué hace falta
  /// pedirlo a mano en el comentario de
  /// [_VideoPlayerTvControlsState._focoServidorElegido].
  final FocusNode focoElegido;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Los nombres los llena la extensión (cabecera X-Servers) — ver
      // `availableServers` en el controlador.
      final nombres = c.availableServers.keys.toList();
      if (nombres.isEmpty) {
        return Text(
          'common.no-data'.i18n,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        );
      }
      final actual = c.currentServerName.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'video.tv-servidores'.i18n,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: nombres.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final nombre = nombres[i];
                final elegido = nombre == actual;
                return FocusableCard(
                  borderRadius: 10,
                  // El del servidor sonando recibe el FocusNode que
                  // VideoPlayerTvControls pide a mano al abrir las opciones
                  // (autofocus solo no alcanzaba acá — ver el porqué en
                  // _focoServidorElegido). Los demás siguen sin nodo propio:
                  // se llega a ellos moviéndose con las flechas desde este.
                  focusNode: elegido ? focoElegido : null,
                  autofocus: elegido,
                  onTap: () => onElegir(nombre),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    decoration: BoxDecoration(
                      color: elegido
                          ? HomeTheme.accentPink
                          : Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      nombre,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight:
                            elegido ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

/// Una pastilla "TECLA — qué hace".
class _Ayuda extends StatelessWidget {
  const _Ayuda({required this.tecla, required this.que});

  final String tecla;
  final String que;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tecla,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(que,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
      ],
    );
  }
}
