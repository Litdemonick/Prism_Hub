import 'package:flutter/material.dart';

enum ScreenSize { mobile, tablet, desktop }

/// Fuente única de verdad para breakpoints, gaps y paddings responsivos.
///
/// Breakpoints (ancho lógico):
///   mobile  <  600 px  → smartphones portrait/landscape
///   tablet  600-1199   → tablets, laptops compactas
///   desktop ≥  1200 px → escritorio
///
/// Todos los valores de espaciado se expresan como porcentaje del viewport
/// para garantizar proporcionalidad en cualquier tamaño/orientación.
abstract final class Responsive {
  // ── Breakpoints ─────────────────────────────────────────────────────────────

  static const double _kTablet = 600;
  static const double _kDesktop = 1200;

  static ScreenSize sizeOf(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= _kDesktop) return ScreenSize.desktop;
    if (w >= _kTablet) return ScreenSize.tablet;
    return ScreenSize.mobile;
  }

  static bool isMobile(BuildContext context) =>
      sizeOf(context) == ScreenSize.mobile;
  static bool isTablet(BuildContext context) =>
      sizeOf(context) == ScreenSize.tablet;
  static bool isDesktop(BuildContext context) =>
      sizeOf(context) == ScreenSize.desktop;

  // ── Espaciados (% del viewport) ─────────────────────────────────────────────

  /// Padding horizontal de página: 3 % / 5 % / 10 % según tamaño.
  static double hPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return switch (sizeOf(context)) {
      ScreenSize.mobile => w * 0.03,
      ScreenSize.tablet => w * 0.05,
      ScreenSize.desktop => w * 0.10,
    };
  }

  /// Padding vertical de página: 2 % / 2 % / 3 % según tamaño.
  static double vPadding(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return switch (sizeOf(context)) {
      ScreenSize.mobile => h * 0.02,
      ScreenSize.tablet => h * 0.02,
      ScreenSize.desktop => h * 0.03,
    };
  }

  /// Gap genérico entre elementos (10 / 14 / 20 px).
  static double gap(BuildContext context) => switch (sizeOf(context)) {
    ScreenSize.mobile => 10,
    ScreenSize.tablet => 14,
    ScreenSize.desktop => 20,
  };

  // ── Grids y cards ───────────────────────────────────────────────────────────

  /// Columnas para grids de contenido (2 / 3 / 4).
  static int gridColumns(BuildContext context) => switch (sizeOf(context)) {
    ScreenSize.mobile => 2,
    ScreenSize.tablet => 3,
    ScreenSize.desktop => 4,
  };

  /// Ancho de ContentCard en listas horizontales (110 / 130 / 150 px).
  static double cardWidth(BuildContext context) => switch (sizeOf(context)) {
    ScreenSize.mobile => 110,
    ScreenSize.tablet => 130,
    ScreenSize.desktop => 150,
  };

  /// Ancho máximo del área de contenido; null = sin límite (móvil/tablet).
  /// En desktop centra el contenido en pantallas muy anchas.
  static double? maxContentWidth(BuildContext context) =>
      isDesktop(context) ? 1280 : null;

  // ── Helpers de layout ───────────────────────────────────────────────────────

  /// Envuelve [child] centrando y limitando el ancho en desktop.
  static Widget constrain(BuildContext context, Widget child) {
    final max = maxContentWidth(context);
    if (max == null) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}
