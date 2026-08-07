import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// El Home nuevo: **catálogo por metadatos**, no lo que el usuario ya tiene.
///
/// ── Por qué se partió en dos ──────────────────────────────────────────────
///
/// Hasta ahora Home era «lo mío»: Continuar viendo y Favoritos. Eso pasó tal
/// cual a [LibraryPage] (`library_page.dart`) — no se rediseñó ni se movió una
/// tarjeta de lugar, solo cambió de puerta.
///
/// Este Home es la otra mitad: **descubrir**. Salen de un proveedor de
/// metadatos, no de las extensiones, y por eso hay contenido desde el primer
/// arranque aunque no haya ninguna extensión instalada. Las extensiones siguen
/// intactas y siguen siendo las que reproducen; acá solo se elige QUÉ ver.
///
/// ── Las fuentes, y por qué no es una sola ─────────────────────────────────
///
///   Anime y Mangas   AniList — su API pública **no pide clave**, así que
///                    funciona de entrada sin que el usuario configure nada. Y
///                    para anime es bastante mejor que TMDB: temporadas,
///                    episodios y relaciones de secuelas.
///   Series y Pelis   TMDB — acá sí hace falta la clave del usuario
///                    (SettingKey.tmdbKey, vacía de fábrica). La zona avisa y
///                    explica cómo conseguirla en vez de quedarse en blanco.
///
/// TMDB no sirve para mangas: es cine y televisión, ahí no hay de dónde
/// sacarlos. Por eso la división no es un capricho.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Las cuatro zonas del catálogo.
enum ZonaDelCatalogo { anime, series, peliculas, mangas }

extension _EtiquetaDeZona on ZonaDelCatalogo {
  String get etiqueta => switch (this) {
        ZonaDelCatalogo.anime => 'home.zona-anime'.i18n,
        ZonaDelCatalogo.series => 'home.zona-series'.i18n,
        ZonaDelCatalogo.peliculas => 'home.zona-peliculas'.i18n,
        ZonaDelCatalogo.mangas => 'home.zona-mangas'.i18n,
      };

  IconData get icono => switch (this) {
        ZonaDelCatalogo.anime => Icons.auto_awesome_outlined,
        ZonaDelCatalogo.series => Icons.live_tv_outlined,
        ZonaDelCatalogo.peliculas => Icons.movie_outlined,
        ZonaDelCatalogo.mangas => Icons.menu_book_outlined,
      };
}

class _HomePageState extends State<HomePage> {
  ZonaDelCatalogo _zona = ZonaDelCatalogo.anime;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          SafeArea(
            child: Column(
              children: [
                _selectorDeZona(),
                Expanded(child: _contenido()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La fila para elegir zona. Va arriba de todo y se desplaza en horizontal:
  /// en un teléfono en vertical las cuatro no entran de una.
  Widget _selectorDeZona() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final z in ZonaDelCatalogo.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ChipDeZona(
                zona: z,
                seleccionada: z == _zona,
                onTap: () => setState(() => _zona = z),
              ),
            ),
        ],
      ),
    );
  }

  /// Todavía sin contenido: las secciones llegan con la capa de metadatos.
  ///
  /// Se deja dicho en pantalla en vez de mostrar un vacío mudo — si alguien
  /// abre esta compilación, tiene que entender que la zona existe y que le
  /// falta el resto, no creer que se rompió.
  Widget _contenido() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_zona.icono, size: 44, color: HomeTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              _zona.etiqueta,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: HomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'home.zona-en-camino'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: HomeTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipDeZona extends StatelessWidget {
  const _ChipDeZona({
    required this.zona,
    required this.seleccionada,
    required this.onTap,
  });

  final ZonaDelCatalogo zona;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = seleccionada ? HomeTheme.accentPink : HomeTheme.textMuted;
    return Material(
      color: seleccionada
          ? HomeTheme.accentPink.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: seleccionada ? HomeTheme.accentPink : HomeTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(zona.icono, size: 17, color: color),
              const SizedBox(width: 7),
              Text(
                zona.etiqueta,
                style: TextStyle(
                  fontSize: 13,
                  color: seleccionada ? HomeTheme.accentPink : HomeTheme.textPrimary,
                  fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
