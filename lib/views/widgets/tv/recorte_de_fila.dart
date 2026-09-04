import 'package:flutter/widgets.dart';

/// Recorta una fila horizontal a izquierda y derecha, y la deja abierta
/// arriba y abajo.
///
/// ── Para qué ────────────────────────────────────────────────────────────
///
/// Una fila de tarjetas necesita dos cosas contradictorias:
///
///   · Que NO se corte arriba y abajo, porque por ahí sale el resplandor del
///     foco y el marco de selección, que sobresalen de la tarjeta a propósito.
///   · Que SÍ se corte a los costados, porque las tarjetas que se van
///     desplazando fuera de la fila se siguen dibujando: sin recorte se
///     pintan sobre el margen y, en televisor, encima del rail de categorías.
///
/// `clipBehavior: Clip.none` a secas resuelve lo primero y rompe lo segundo —
/// no distingue ejes. Reportado con foto: «las cards se comen la zona del
/// panel izquierdo» y «los botones están atrás del card».
///
/// Este recortador devuelve un rectángulo más alto que la fila y apenas más
/// ancho: corta donde molesta y deja pasar donde hace falta.
class RecorteDeFila extends CustomClipper<Rect> {
  const RecorteDeFila({this.aireLateral = 0});

  /// Cuánto se deja escapar arriba y abajo. Con el resplandor actual sobra.
  static const _aire = 60.0;

  /// Y cuánto a los costados.
  ///
  /// Cero en teléfono y escritorio: ahí el recorte lateral existe justamente
  /// para que una tarjeta que sale de la fila no se dibuje sobre el margen.
  ///
  /// En televisor no puede ser cero: la tarjeta enfocada lleva un marco que
  /// sobresale por fuera de ella, y con el corte al ras quedaba mordido por
  /// los dos lados — reportado en vivo: «se corta el borde de selección de la
  /// card». El aire tiene que ser mayor que ese marco y menor que la
  /// distancia hasta el rail, así que cualquier valor holgado en el medio
  /// sirve; se usa 24.
  final double aireLateral;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        -aireLateral,
        -_aire,
        size.width + aireLateral,
        size.height + _aire,
      );

  @override
  bool shouldReclip(covariant RecorteDeFila oldClipper) =>
      oldClipper.aireLateral != aireLateral;
}
