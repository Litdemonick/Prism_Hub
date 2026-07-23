import 'package:flutter/material.dart';

// Colores exactos del diseño (Figma → HTML exportado), convertidos de OKLCH
// a hex. No se cambia la tipografía de la app (Plus Jakarta Sans requeriría
// empaquetar fuentes nuevas) — el resto del estilo (color, espaciado, forma)
// sí se replica igual que el diseño.
class HomeTheme {
  HomeTheme._();

  static const bg = Color(0xFF08090D);
  static const textPrimary = Color(0xFFEAEBF2);
  static const textMuted = Color(0xFF7E8087);
  static const textPlaceholder = Color(0xFF676870);
  static const border = Color(0xFF2C2D35);
  static const accentPink = Color(0xFFD777ED);
  static const cardSurface = Color(0xFF15151C);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF573160), Color(0xFF0C1A32), Color(0xFF0B0C16)],
    stops: [0.0, 0.65, 1.0],
  );

  // Cuando el hero tiene una portada real de fondo, se necesita un
  // degradado más oscuro/opaco encima para que el texto siga siendo
  // legible sobre cualquier imagen.
  static const heroOverlayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xB3120A18), Color(0xE60B0714)],
    stops: [0.0, 1.0],
  );

  // Un gradiente por posición — mismo patrón round-robin que usa el diseño
  // para las tarjetas cuando no hay portada real.
  static const cardGradients = [
    [Color(0xFF65396F), Color(0xFF1E142E)], // violeta
    [Color(0xFF294778), Color(0xFF071727)], // azul
    [Color(0xFF853538), Color(0xFF2E0F15)], // rojo
    [Color(0xFF005D39), Color(0xFF001C13)], // verde
    [Color(0xFF654C00), Color(0xFF1F1702)], // dorado
  ];

  static List<Color> gradientFor(int index) => cardGradients[index % cardGradients.length];
}
