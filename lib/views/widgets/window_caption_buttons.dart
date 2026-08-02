import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Los tres botones de la ventana: minimizar, maximizar/restaurar y cerrar.
///
/// Existe para que haya UNA sola implementación. Había tres: la del paquete
/// (`WindowCaption`) en la pantalla principal, otra escrita a mano en los
/// controles del reproductor, y una tercera en la cabecera del lector. Cada
/// arreglo entraba en una y las otras seguían como estaban.
///
/// El maximizar de la principal dejaba de responder después de achicar la
/// ventana, y la del reproductor —escrita a mano— no daba ese problema. Por eso
/// se toma esa como base y se le agrega la guarda de pantalla completa.
class BotonesVentana extends StatefulWidget {
  const BotonesVentana({super.key, this.brightness = Brightness.dark});

  final Brightness brightness;

  @override
  State<BotonesVentana> createState() => _BotonesVentanaState();
}

class _BotonesVentanaState extends State<BotonesVentana> with WindowListener {
  bool _maximizada = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximizada = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximizada = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximizada = false);
  }

  /// Maximiza, sacando antes la pantalla completa si quedó puesta.
  ///
  /// Windows ignora la orden de maximizar mientras la ventana está en pantalla
  /// completa: ahí el estilo de la ventana es otro y no hay nada que maximizar.
  /// El reproductor entra y sale de pantalla completa por su cuenta, así que
  /// alcanza con que una salida quede a medias —al cerrar el reproductor de
  /// golpe, por ejemplo— para que a partir de ahí el botón de la ventana
  /// principal no responda más. Se sale y recién después se maximiza.
  ///
  /// También se vuelve a preguntar el estado real en vez de confiar en el que
  /// se venía guardando: si se desincronizó, el botón podía estar llamando a
  /// restaurar cuando lo que hacía falta era maximizar, y al usuario le parecía
  /// que no hacía nada.
  Future<void> _alternarMaximizado() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    final maximizada = await windowManager.isMaximized();
    if (maximizada) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    if (mounted) setState(() => _maximizada = !maximizada);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton.minimize(
          brightness: widget.brightness,
          onPressed: () async {
            if (await windowManager.isMinimized()) {
              await windowManager.restore();
            } else {
              await windowManager.minimize();
            }
          },
        ),
        _maximizada
            ? WindowCaptionButton.unmaximize(
                brightness: widget.brightness,
                onPressed: _alternarMaximizado,
              )
            : WindowCaptionButton.maximize(
                brightness: widget.brightness,
                onPressed: _alternarMaximizado,
              ),
        WindowCaptionButton.close(
          brightness: widget.brightness,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}
