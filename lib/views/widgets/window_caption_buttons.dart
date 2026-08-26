import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
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
///
/// ── Por qué el dibujo es propio, no `WindowCaptionButton` del paquete ──────
///
/// Pedido explícito: nada de estética genérica de Windows acá — la app tiene
/// la suya (fondo casi negro, acentos rosa/rojo) y el widget del paquete trae
/// su propio resaltado al pasar el mouse (un gris plano de fábrica) que no
/// combina con nada del resto. Y sin ninguna animación de movimiento: el
/// único cambio al pasar el mouse es el color de fondo, nada que crezca,
/// se mueva o rebote.
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

  bool get _claro => widget.brightness == Brightness.light;

  @override
  Widget build(BuildContext context) {
    // El reproductor y el lector fuerzan brightness: dark siempre (ver
    // HomeTheme.oscuroFondo/oscuroSuperficie) — acá no hace falta distinguir
    // más que eso: el color base del trazo y el gris de hover que usa cada
    // caso, tomados de la misma paleta que ya usa toda la app.
    final trazo = _claro ? HomeTheme.textPrimary : HomeTheme.oscuroTexto;
    final hover = _claro ? HomeTheme.border : HomeTheme.oscuroBorde;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BotonCaption(
          trazo: trazo,
          colorHover: hover,
          onPressed: () async {
            if (await windowManager.isMinimized()) {
              await windowManager.restore();
            } else {
              await windowManager.minimize();
            }
          },
          dibujar: (canvas, centro, color) {
            final p = Paint()
              ..color = color
              ..strokeWidth = 1
              ..style = PaintingStyle.stroke;
            canvas.drawLine(
              Offset(centro.dx - 5, centro.dy),
              Offset(centro.dx + 5, centro.dy),
              p,
            );
          },
        ),
        _BotonCaption(
          trazo: trazo,
          colorHover: hover,
          onPressed: _alternarMaximizado,
          dibujar: (canvas, centro, color) {
            final p = Paint()
              ..color = color
              ..strokeWidth = 1
              ..style = PaintingStyle.stroke;
            if (!_maximizada) {
              canvas.drawRect(
                Rect.fromCenter(center: centro, width: 9, height: 9),
                p,
              );
            } else {
              // Restaurar: dos cuadrados superpuestos, el de atrás recortado
              // donde lo tapa el de adelante — la misma metáfora que ya usa
              // Windows, dibujada con las mismas dos líneas de siempre.
              canvas.drawRect(
                Rect.fromCenter(
                    center: centro.translate(-1.5, -1.5), width: 7, height: 7),
                p,
              );
              final frente = Path()
                ..moveTo(centro.dx - 3, centro.dy - 1)
                ..lineTo(centro.dx - 3, centro.dy + 4)
                ..lineTo(centro.dx + 4, centro.dy + 4)
                ..lineTo(centro.dx + 4, centro.dy - 3)
                ..lineTo(centro.dx - 1, centro.dy - 3);
              canvas.drawPath(frente, p);
            }
          },
        ),
        _BotonCaption(
          trazo: trazo,
          colorHover: HomeTheme.accentRed,
          // Sobre rojo el trazo se ve mejor en blanco — mismo criterio que
          // ya usa cualquier botón de "peligro" del resto de la app.
          colorTrazoHover: Colors.white,
          onPressed: () => windowManager.close(),
          dibujar: (canvas, centro, color) {
            final p = Paint()
              ..color = color
              ..strokeWidth = 1
              ..style = PaintingStyle.stroke;
            canvas.drawLine(
              Offset(centro.dx - 4.5, centro.dy - 4.5),
              Offset(centro.dx + 4.5, centro.dy + 4.5),
              p,
            );
            canvas.drawLine(
              Offset(centro.dx - 4.5, centro.dy + 4.5),
              Offset(centro.dx + 4.5, centro.dy - 4.5),
              p,
            );
          },
        ),
      ],
    );
  }
}

/// Un botón de la caption: rectángulo fijo (46x32, la medida de Windows),
/// sin ninguna animación de tamaño o posición — solo el fondo cambia,
/// instantáneo, al pasar el mouse.
class _BotonCaption extends StatefulWidget {
  const _BotonCaption({
    required this.dibujar,
    required this.onPressed,
    required this.trazo,
    required this.colorHover,
    this.colorTrazoHover,
  });

  final void Function(Canvas canvas, Offset centro, Color color) dibujar;
  final VoidCallback onPressed;
  final Color trazo;
  final Color colorHover;

  /// Si el trazo cambia de color con el fondo de hover (el de cerrar, sobre
  /// rojo, se ve mejor en blanco que en el color de trazo normal).
  final Color? colorTrazoHover;

  @override
  State<_BotonCaption> createState() => _BotonCaptionState();
}

class _BotonCaptionState extends State<_BotonCaption> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final color = _encima
        ? (widget.colorTrazoHover ?? widget.trazo)
        : widget.trazo;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          color: _encima ? widget.colorHover : Colors.transparent,
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size(10, 10),
            painter: _CaptionIconPainter(
              dibujar: widget.dibujar,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionIconPainter extends CustomPainter {
  _CaptionIconPainter({required this.dibujar, required this.color});

  final void Function(Canvas canvas, Offset centro, Color color) dibujar;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    dibujar(canvas, Offset(size.width / 2, size.height / 2), color);
  }

  @override
  bool shouldRepaint(covariant _CaptionIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
