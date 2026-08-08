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
  // Acento de la Zona +18 — mismo rol que accentPink (hover, progreso,
  // brillo ambiental) pero rojo, para que esa pantalla se sienta claramente
  // distinta del Home normal. Ver AnimatedBackgroundGlow/HomeSection/
  // HomeMediaCard, que aceptan `accent` en vez de tener este color fijo.
  static const accentRed = Color(0xFFE5484D);
  static const cardSurface = Color(0xFF15151C);

  /// El título de una zona: «Inicio», «Biblioteca», «Buscar», «Historial».
  ///
  /// ── Por qué está acá y no escrito en cada pantalla ──────────────────────
  ///
  /// Estaba repetido a mano en cada una, y con el tiempo se separaron: 25 en
  /// Biblioteca, 22 en Buscar y en Historial, 20 y 24 en Ajustes. Cinco
  /// pantallas hermanas con cuatro tamaños distintos, y solo la de Inicio en
  /// blanco puro — el resto caía en textPrimary, que es gris clarito. Se
  /// notaba al pasar de una a otra: el título cambiaba de peso y de color sin
  /// que nada lo justificara.
  ///
  /// El de Inicio es el bueno y el que manda, porque es el que lleva el nombre
  /// de la app: 25, bien grueso, con el interletrado cerrado y en BLANCO. Los
  /// demás lo copian desde acá.
  ///
  /// [bajo] es para pantalla baja —un teléfono acostado— donde 25 se come una
  /// franja que le hace falta al contenido.
  static TextStyle tituloDeZona({bool bajo = false}) => TextStyle(
        fontSize: bajo ? 21 : 25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: Colors.white,
      );

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF573160), Color(0xFF0C1A32), Color(0xFF0B0C16)],
    stops: [0.0, 0.65, 1.0],
  );

  // Variante roja del hero, mismo patrón de 3 paradas — Zona +18.
  static const heroGradientRed = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5C1B22), Color(0xFF2A0C10), Color(0xFF0B0C16)],
    stops: [0.0, 0.65, 1.0],
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

  static List<Color> gradientFor(int index) =>
      cardGradients[index % cardGradients.length];
}
