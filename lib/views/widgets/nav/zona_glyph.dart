import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Qué forma dibuja el glifo — una por destino del panel lateral.
enum Forma {
  inicio,
  peliculas,
  series,
  anime,
  mangas,
  biblioteca,
  extensiones,
  repositorio,
  ajustes,
}

/// Un ícono PROPIO por destino, no un glifo de Material/Fluent.
///
/// ── Por qué esto y no `Icon(FluentIcons.xxx)` ───────────────────────────
///
/// Pedido explícito: nada de librería genérica, algo dibujado para la app,
/// simple y ESTABLE — sin ninguna animación al tocar o pasar el mouse (eso
/// ya lo maneja `fluent.PaneItem` con el resaltado de fondo, que no se toca
/// acá). No hay ninguna herramienta de generación de imágenes disponible
/// —no puede fabricarse arte real (fotos, ilustraciones)—, así que esto es
/// lo más parecido con lo que sí hay: un trazo vectorial propio, de línea
/// simple, un color solo (el que ya usa `fluent.PaneItem` para el
/// seleccionado/no seleccionado vía `IconTheme`) — nada de degradados ni
/// capas superpuestas, que a este tamaño (20px) se emborronan y encima
/// arriesgan verse rotas sin poder probarlas en pantalla antes de mandarlas.
class ZonaGlyph extends StatelessWidget {
  const ZonaGlyph(this.forma, {super.key, this.size});

  final Forma forma;

  /// `null` = el tamaño que ya venga puesto por `IconTheme` (el mismo que
  /// heredaría un `Icon()` común). Sin esto, el ícono ignoraba el ancho
  /// ajustado que `fluent.PaneItem` reserva para el suyo (16px) y se
  /// dibujaba más grande — desbordaba la fila por un par de píxeles,
  /// reportado en vivo apenas se lo probó.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final trazo = iconTheme.color ?? HomeTheme.textPrimary;
    final lado = size ?? iconTheme.size ?? 20;
    return SizedBox(
      width: lado,
      height: lado,
      child: CustomPaint(
        painter: _GlyphPainter(forma: forma, trazo: trazo),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.forma, required this.trazo});

  final Forma forma;
  final Color trazo;

  @override
  void paint(Canvas canvas, Size size) {
    // Todo se dibuja sobre una caja lógica de 20x20 y se escala al tamaño
    // real — así cada forma se define una sola vez, sin cuentas repetidas.
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);

    final linea = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = trazo;
    final relleno = Paint()
      ..style = PaintingStyle.fill
      ..color = trazo;

    switch (forma) {
      case Forma.inicio:
        _inicio(canvas, linea);
      case Forma.peliculas:
        _peliculas(canvas, linea, relleno);
      case Forma.series:
        _series(canvas, linea);
      case Forma.anime:
        _anime(canvas, relleno);
      case Forma.mangas:
        _mangas(canvas, linea);
      case Forma.biblioteca:
        _biblioteca(canvas, linea);
      case Forma.extensiones:
        _extensiones(canvas, linea);
      case Forma.repositorio:
        _repositorio(canvas, linea);
      case Forma.ajustes:
        _ajustes(canvas, linea, relleno);
    }
    canvas.restore();
  }

  void _inicio(Canvas canvas, Paint linea) {
    final techo = Path()
      ..moveTo(2, 9.5)
      ..lineTo(10, 2.5)
      ..lineTo(18, 9.5);
    canvas.drawPath(techo, linea);
    canvas.drawRect(const Rect.fromLTWH(4.5, 9.5, 11, 8), linea);
    canvas.drawRect(const Rect.fromLTWH(8, 13.5, 4, 4), linea);
  }

  void _peliculas(Canvas canvas, Paint linea, Paint relleno) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 3, 16, 14),
        const Radius.circular(3),
      ),
      linea,
    );
    final play = Path()
      ..moveTo(8, 7.5)
      ..lineTo(14, 10)
      ..lineTo(8, 12.5)
      ..close();
    canvas.drawPath(play, relleno);
  }

  void _series(Canvas canvas, Paint linea) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 3, 16, 11),
        const Radius.circular(2),
      ),
      linea,
    );
    canvas.drawLine(const Offset(7, 17.5), const Offset(13, 17.5), linea);
    canvas.drawLine(const Offset(10, 14), const Offset(10, 17.5), linea);
  }

  void _anime(Canvas canvas, Paint relleno) {
    // Un destello de cuatro puntas — mismo símbolo que ya usa la zona Anime
    // en el resto de la app.
    Offset punta(double angulo, double r) =>
        const Offset(10, 10) + Offset.fromDirection(angulo, r);
    final p = Path()
      ..moveTo(punta(-1.5708, 8).dx, punta(-1.5708, 8).dy)
      ..quadraticBezierTo(10, 10, punta(0, 8).dx, punta(0, 8).dy)
      ..quadraticBezierTo(10, 10, punta(1.5708, 8).dx, punta(1.5708, 8).dy)
      ..quadraticBezierTo(10, 10, punta(3.14159, 8).dx, punta(3.14159, 8).dy)
      ..quadraticBezierTo(10, 10, punta(-1.5708, 8).dx, punta(-1.5708, 8).dy)
      ..close();
    canvas.drawPath(p, relleno);
    canvas.drawCircle(const Offset(15.5, 4.5), 1.3, relleno);
  }

  void _mangas(Canvas canvas, Paint linea) {
    final izquierda = Path()
      ..moveTo(10, 5)
      ..cubicTo(7, 3.6, 4, 4, 2, 5)
      ..lineTo(2, 15.5)
      ..cubicTo(4, 14.5, 7, 14.1, 10, 15.5);
    final derecha = Path()
      ..moveTo(10, 5)
      ..cubicTo(13, 3.6, 16, 4, 18, 5)
      ..lineTo(18, 15.5)
      ..cubicTo(16, 14.5, 13, 14.1, 10, 15.5);
    canvas.drawPath(izquierda, linea);
    canvas.drawPath(derecha, linea);
    canvas.drawLine(const Offset(10, 5), const Offset(10, 15.5), linea);
  }

  void _biblioteca(Canvas canvas, Paint linea) {
    canvas.drawLine(const Offset(2.5, 17), const Offset(2.5, 4), linea);
    canvas.drawLine(const Offset(4.5, 16), const Offset(4.5, 6), linea);
    canvas.drawLine(const Offset(6.5, 17), const Offset(6.5, 3), linea);
    canvas.drawLine(const Offset(8.5, 16), const Offset(8.5, 7), linea);
    canvas.drawLine(const Offset(2.5, 17), const Offset(9.5, 17), linea);
    // Un libro inclinado apoyado al lado — distingue el estante de tres
    // rayas solas, que a este tamaño podían leerse como un ecualizador.
    canvas.save();
    canvas.translate(14.5, 12);
    canvas.rotate(0.5);
    canvas.drawRect(const Rect.fromLTWH(-3.5, -6, 7, 9), linea);
    canvas.restore();
  }

  void _extensiones(Canvas canvas, Paint linea) {
    // Un enchufe: cuerpo + dos clavijas — "algo que se conecta a la app".
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 7, 10, 7),
        const Radius.circular(3.5),
      ),
      linea,
    );
    canvas.drawLine(const Offset(6, 7), const Offset(6, 2.5), linea);
    canvas.drawLine(const Offset(10, 7), const Offset(10, 2.5), linea);
    canvas.drawLine(const Offset(8, 14), const Offset(8, 18), linea);
  }

  void _repositorio(Canvas canvas, Paint linea) {
    // Grilla 2x2 — "explorar/catálogo", distinto del enchufe de arriba
    // (lo ya instalado) a propósito.
    void cuadro(double x, double y) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 6, 6),
          const Radius.circular(1.6),
        ),
        linea,
      );
    }

    cuadro(2, 2);
    cuadro(11, 2);
    cuadro(2, 11);
    cuadro(11, 11);
  }

  void _ajustes(Canvas canvas, Paint linea, Paint relleno) {
    // Un engranaje simplificado: seis dientes cortos sobre un aro, con un
    // agujero al medio — se lee como "ajustes" sin dientes finos que a
    // este tamaño se emborronan.
    canvas.drawCircle(const Offset(10, 10), 5, linea);
    for (var i = 0; i < 6; i++) {
      final angulo = i * 3.14159 / 3;
      final desde = const Offset(10, 10) + Offset.fromDirection(angulo, 6.4);
      final hasta = const Offset(10, 10) + Offset.fromDirection(angulo, 8.6);
      canvas.drawLine(desde, hasta, linea);
    }
    canvas.drawCircle(const Offset(10, 10), 1.8, relleno);
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) =>
      oldDelegate.forma != forma || oldDelegate.trazo != trazo;
}
