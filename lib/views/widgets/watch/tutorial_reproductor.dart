import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:prismhub/views/widgets/window_caption_buttons.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Aviso breve, centrado, que aparece y se va solo.
///
/// Se usa al pedir "ver el tutorial de nuevo": el mensaje de la barra inferior
/// quedaba pegado a un borde, tapado por los controles del reproductor y con el
/// fondo del video atrás, así que se leía mal justo cuando hay que leerlo.
///
/// Va por Overlay y no dentro de la pantalla: así no depende de que el panel de
/// ajustes siga abierto —de hecho se cierra al tocar el botón— ni de que nadie
/// reconstruya nada.
Future<void> mostrarAvisoCentrado(BuildContext context, String texto) async {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  // El estado va afuera del widget para poder animar la entrada y la salida
  // sin reconstruir la entrada del overlay.
  final controlador = _AvisoControlador(texto);
  final entrada = OverlayEntry(
    builder: (_) => _AvisoCentrado(controlador: controlador),
  );
  overlay.insert(entrada);

  await Future<void>.delayed(const Duration(milliseconds: 40));
  controlador.visible.value = true;
  // Lo suficiente para leer una línea corta sin quedarse en el medio.
  await Future<void>.delayed(const Duration(milliseconds: 2200));
  controlador.visible.value = false;
  // Se espera a que termine el desvanecido antes de sacarlo, si no desaparece
  // de golpe.
  await Future<void>.delayed(const Duration(milliseconds: 260));
  entrada.remove();
}

class _AvisoControlador {
  _AvisoControlador(this.texto);
  final String texto;
  final ValueNotifier<bool> visible = ValueNotifier(false);
}

class _AvisoCentrado extends StatelessWidget {
  const _AvisoCentrado({required this.controlador});
  final _AvisoControlador controlador;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: controlador.visible,
          builder: (context, visible, child) => AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: visible ? 1 : 0.94,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              child: child,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                // Sólido: sobre un fotograma claro, un fondo traslúcido dejaba
                // el texto ilegible.
                color: const Color(0xFF15151C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: HomeTheme.oscuroAcento, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 18),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.school_outlined,
                      color: HomeTheme.oscuroAcento, size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      controlador.texto,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: HomeTheme.oscuroTexto,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un paso del tutorial: qué se hace y qué pasa.
class _Paso {
  const _Paso({
    required this.titulo,
    required this.detalle,
    required this.icono,
    this.gesto = _Gesto.ninguno,
  });

  final String titulo;
  final String detalle;
  final IconData icono;

  /// Qué dibuja la animación de al lado. Sin esto el tutorial sería una lista
  /// de texto, y lo que cuesta explicar de un gesto es justamente el gesto.
  final _Gesto gesto;
}

enum _Gesto {
  ninguno,
  tocarCentro,
  tocarLados,
  arrastrarLateral,
  tecla,
}

/// Explica cómo se usa el reproductor, una sola vez y con la mano.
///
/// Se muestra la PRIMERA vez que alguien abre un vídeo, porque los gestos del
/// reproductor no se ven: tocar a los lados salta, deslizar cambia el volumen,
/// y sin que nadie lo diga eso no se descubre — o peor, se descubre sin querer
/// y parece que la app hace cosas raras sola.
///
/// El contenido cambia según el dispositivo y según el vídeo:
///
///  - En el teléfono se explican los gestos; en escritorio, las teclas.
///  - Los segundos que salta cada tecla salen de Ajustes, no de un número
///    inventado: si alguien los cambió, el tutorial dice los suyos.
///  - Con un vídeo VR se agregan los pasos que solo aplican ahí (mover la
///    cámara, y dónde está la opción de ver una sola imagen).
///
/// La opción de llenar la pantalla se explica SOLO en el teléfono: en
/// escritorio, la pantalla completa ya hace eso.
class TutorialReproductor extends StatefulWidget {
  const TutorialReproductor({
    super.key,
    required this.esVr,
    required this.onCerrar,
  });

  /// Cambia los pasos, no solo un texto: en un vídeo normal no tiene sentido
  /// hablar de mover una cámara que no existe.
  final bool esVr;
  final VoidCallback onCerrar;

  /// ¿Ya se mostró alguna vez?
  ///
  /// En TV devuelve siempre `true`, o sea que NUNCA se muestra: todos sus
  /// pasos enseñan gestos que ahí no existen —"tocá la pantalla", "dos
  /// toques en el centro", arrastrar para el volumen— porque el reproductor
  /// de televisor se maneja con las teclas del mando, no con el dedo (ver
  /// video_player_content.dart, que en TV usa los controles de teclado).
  ///
  /// Además tapaba la pantalla con un diálogo que el mando no podía cerrar.
  static bool get yaVisto =>
      PlatformTv.esTelevisionSync ||
      PrismHubStorage.getSetting(SettingKey.tutorialReproductorVisto) == true;

  static Future<void> marcarVisto() =>
      PrismHubStorage.setSetting(SettingKey.tutorialReproductorVisto, true);

  /// Vuelve a habilitarlo, para poder verlo de nuevo desde Ajustes.
  static Future<void> reiniciar() =>
      PrismHubStorage.setSetting(SettingKey.tutorialReproductorVisto, false);

  @override
  State<TutorialReproductor> createState() => _TutorialReproductorState();
}

class _TutorialReproductorState extends State<TutorialReproductor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  int _indice = 0;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Los segundos configurados de un atajo, con su signo.
  ///
  /// Se leen de Ajustes en vez de escribir un número fijo: son configurables, y
  /// un tutorial que dice "10 segundos" cuando el usuario los puso en 30 enseña
  /// mal.
  String _segundos(String clave, double porDefecto) {
    final v = PrismHubStorage.getSetting(clave);
    final n = v is num ? v.toDouble() : porDefecto;
    final abs = n.abs();
    // Sin decimales cuando es redondo: "10 s" se lee mejor que "10.0 s".
    final texto = abs == abs.roundToDouble()
        ? abs.round().toString()
        : abs.toStringAsFixed(1);
    return '$texto s';
  }

  List<_Paso> get _pasos {
    String t(String k) => 'video.tutorial.$k'.i18n;

    if (Platform.isAndroid) {
      return [
        _Paso(
          titulo: t('tap-title'),
          detalle: t('tap-body'),
          icono: Icons.touch_app_outlined,
          gesto: _Gesto.tocarCentro,
        ),
        _Paso(
          titulo: t('sides-title'),
          detalle: '${t('sides-body')} '
              '${_segundos(SettingKey.arrowRight, 2.0)}.',
          icono: Icons.fast_forward_rounded,
          gesto: _Gesto.tocarLados,
        ),
        _Paso(
          titulo: t('volume-title'),
          detalle: t('volume-body'),
          icono: Icons.volume_up_rounded,
        ),
        if (widget.esVr)
          _Paso(
            titulo: t('vr-drag-title'),
            detalle: t('vr-drag-body'),
            icono: Icons.threed_rotation,
            gesto: _Gesto.arrastrarLateral,
          ),
        if (widget.esVr)
          _Paso(
            titulo: t('vr-single-title'),
            detalle: t('vr-single-body'),
            icono: Icons.settings_outlined,
          ),
        // El llenar pantalla se explica solo en el telefono: en escritorio la
        // pantalla completa ya lo hace.
        _Paso(
          titulo: t('fill-title'),
          detalle: t('fill-body'),
          icono: Icons.fullscreen_rounded,
        ),
        // Comunes a las dos plataformas: no son gestos sino donde encontrar
        // las cosas. Van al final, despues de lo que hace falta para mirar un
        // video, que es lo urgente.
        _Paso(
          titulo: t('servers-title'),
          detalle: t('servers-body'),
          icono: Icons.dns_outlined,
        ),
        _Paso(
          titulo: t('quality-title'),
          detalle: t('quality-body'),
          icono: Icons.hd_outlined,
        ),
        _Paso(
          titulo: t('settings-title'),
          detalle: t('settings-body'),
          icono: Icons.tune_rounded,
        ),
      ];
    }

    return [
      _Paso(
        titulo: t('space-title'),
        detalle: t('space-body'),
        icono: Icons.space_bar_rounded,
        gesto: _Gesto.tecla,
      ),
      _Paso(
        titulo: t('keys-title'),
        detalle: '${t('keys-body')} '
            '${_segundos(SettingKey.keyJ, 10.0)} / '
            '${_segundos(SettingKey.keyI, 10.0)}.',
        icono: Icons.keyboard_rounded,
        gesto: _Gesto.tecla,
      ),
      _Paso(
        titulo: t('arrows-title'),
        detalle: '${t('arrows-body')} '
            '${_segundos(SettingKey.arrowRight, 2.0)}.',
        icono: Icons.swap_horiz_rounded,
        gesto: _Gesto.tecla,
      ),
      _Paso(
        titulo: t('fullscreen-title'),
        detalle: t('fullscreen-body'),
        icono: Icons.fullscreen_rounded,
        gesto: _Gesto.tecla,
      ),
      if (widget.esVr)
        _Paso(
          titulo: t('vr-drag-pc-title'),
          detalle: t('vr-drag-pc-body'),
          icono: Icons.threed_rotation,
          gesto: _Gesto.arrastrarLateral,
        ),
      if (widget.esVr)
        _Paso(
          titulo: t('vr-single-title'),
          detalle: t('vr-single-body'),
          icono: Icons.settings_outlined,
        ),
      // Comunes a las dos plataformas: no son gestos sino donde encontrar
      // las cosas. Van al final, despues de lo que hace falta para mirar un
      // video, que es lo urgente.
      _Paso(
        titulo: t('servers-title'),
        detalle: t('servers-body'),
        icono: Icons.dns_outlined,
      ),
      _Paso(
        titulo: t('quality-title'),
        detalle: t('quality-body'),
        icono: Icons.hd_outlined,
      ),
      _Paso(
        titulo: t('settings-title'),
        detalle: t('settings-body'),
        icono: Icons.tune_rounded,
      ),
    ];
  }

  Future<void> _terminar() async {
    await TutorialReproductor.marcarVisto();
    widget.onCerrar();
  }

  @override
  Widget build(BuildContext context) {
    // Fondo SÓLIDO y que se come todos los toques.
    //
    // Antes era negro traslúcido dentro de un Material, y eso dejaba pasar los
    // gestos: un Material con color pinta, pero no consume eventos. El toque
    // atravesaba el tutorial y llegaba a los controles del reproductor, así que
    // leyendo "tocá el centro para pausar" se pausaba el vídeo de atrás sin
    // querer, o se abría un panel debajo del tutorial.
    //
    // El GestureDetector opaco de abajo absorbe lo que no toque un botón del
    // tutorial. Va DENTRO y no envolviendo todo, para que los botones propios
    // —siguiente, saltar— sigan recibiendo lo suyo: están más arriba en el
    // Stack y se quedan con el evento primero.
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Sin acciones: el único trabajo de esta capa es que nada de lo
              // que hay detrás se entere de que la tocaron.
              onTap: () {},
              onDoubleTap: () {},
              onLongPress: () {},
              onVerticalDragUpdate: (_) {},
              onHorizontalDragUpdate: (_) {},
            ),
          ),
          _contenido(context),
          // En Windows y Linux la ventana no tiene barra propia: la dibuja la
          // app. Con el tutorial tapando todo, esa barra quedaba debajo y la
          // ventana no se podia mover ni cerrar sin salir del tutorial primero.
          //
          // Se repone aca arriba: una franja para arrastrar y los tres botones
          // de siempre. Va por encima del absorbedor de toques, asi que es lo
          // unico de atras que sigue respondiendo — y tiene que serlo, porque
          // si no la ventana queda atrapada.
          if (!Platform.isAndroid)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Row(
                children: [
                  Expanded(
                    child: DragToMoveArea(child: SizedBox(height: 40)),
                  ),
                  BotonesVentana(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    final pasos = _pasos;
    // Un paso que ya no existe (se cambio de video VR a normal) dejaria el
    // indice fuera de rango.
    final i = _indice.clamp(0, pasos.length - 1);
    final paso = pasos[i];
    final ultimo = i == pasos.length - 1;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DemoGesto(gesto: paso.gesto, anim: _anim, icono: paso.icono),
                const SizedBox(height: 22),
                Text(
                  paso.titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomeTheme.oscuroTexto,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  paso.detalle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomeTheme.oscuroTextoTenue,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var k = 0; k < pasos.length; k++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: k == i ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: k == i
                              ? HomeTheme.oscuroAcento
                              : Colors.white.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _terminar,
                      child: Text(
                        'video.tutorial.skip'.i18n,
                        style: const TextStyle(color: HomeTheme.oscuroTextoTenue),
                      ),
                    ),
                    // Volver atras: los pasos traen el numero de segundos que
                    // cada uno tiene configurado, y sin esto un paso que se
                    // pasó de largo no se podia releer sin repetir el tutorial
                    // entero desde los ajustes.
                    if (i > 0) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() => _indice = i - 1),
                        child: Text(
                          'video.tutorial.back'.i18n,
                          style: const TextStyle(color: HomeTheme.oscuroTexto),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: HomeTheme.oscuroAcento,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 12),
                      ),
                      onPressed: () {
                        if (ultimo) {
                          _terminar();
                        } else {
                          setState(() => _indice = i + 1);
                        }
                      },
                      child: Text(
                        ultimo
                            ? 'video.tutorial.done'.i18n
                            : 'video.tutorial.next'.i18n,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La animación que muestra el gesto.
///
/// Es un rectángulo que representa la pantalla del reproductor y un punto que
/// hace el movimiento, en bucle. Dibujar el gesto explica en un segundo lo que
/// un párrafo no termina de aclarar.
class _DemoGesto extends StatelessWidget {
  const _DemoGesto({
    required this.gesto,
    required this.anim,
    required this.icono,
  });

  final _Gesto gesto;
  final Animation<double> anim;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 124,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          // Va y vuelve, en vez de saltar del final al principio: un bucle que
          // corta de golpe se lee como un parpadeo y no como un movimiento.
          final t = anim.value;
          final vaiven = t < 0.5 ? t * 2 : (1 - t) * 2;

          switch (gesto) {
            case _Gesto.tocarCentro:
              return _punto(
                  x: 0.5, y: 0.5, escala: 1 + vaiven * 0.5, opacidad: 1);
            case _Gesto.tocarLados:
              // Un lado y despues el otro, que es lo que hace el gesto real.
              final derecha = t > 0.5;
              return _punto(
                x: derecha ? 0.8 : 0.2,
                y: 0.5,
                escala: 1 + vaiven * 0.4,
                opacidad: 1,
                icono: derecha
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
              );
            case _Gesto.arrastrarLateral:
              return _punto(x: 0.22 + vaiven * 0.56, y: 0.5, escala: 1);
            case _Gesto.tecla:
            case _Gesto.ninguno:
              return Center(
                child: Opacity(
                  opacity: 0.55 + vaiven * 0.45,
                  child: Icon(icono, size: 44, color: HomeTheme.oscuroAcento),
                ),
              );
          }
        },
      ),
    );
  }

  Widget _punto({
    required double x,
    required double y,
    required double escala,
    double opacidad = 1,
    IconData? icono,
  }) {
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Positioned(
            left: c.maxWidth * x - 22,
            top: c.maxHeight * y - 22,
            child: Opacity(
              opacity: opacidad,
              child: Transform.scale(
                scale: escala,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HomeTheme.oscuroAcento.withValues(alpha: 0.28),
                    border: Border.all(color: HomeTheme.oscuroAcento, width: 2),
                  ),
                  child: icono == null
                      ? null
                      : Icon(icono, size: 20, color: HomeTheme.oscuroTexto),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
