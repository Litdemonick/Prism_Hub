import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/catalogo_controller.dart';
import 'package:prismhub/data/metadata/metadata_item.dart';
import 'package:prismhub/data/metadata/metadata_source.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_section.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/progress.dart';

/// El Home: **descubrir**.
///
/// ── Por qué está partido de la Biblioteca ─────────────────────────────────
///
/// Antes Home era «lo mío»: Continuar viendo y Favoritos. Eso pasó tal cual a
/// `library_page.dart`, sin rediseñar nada. Lo que cambió es que ahora cada
/// pantalla tiene una regla clara sobre estar vacía:
///
///   Biblioteca vacía  →  está bien. Todavía no viste nada.
///   Home vacío        →  está mal. Es la pantalla de descubrir.
///
/// Antes eso no se podía distinguir: había una sola pantalla, y vacía parecía
/// una app rota.
///
/// ── De dónde sale el contenido ────────────────────────────────────────────
///
/// De metadatos, **no de las extensiones**. Por eso hay algo que ver desde el
/// primer arranque aunque no haya una sola extensión instalada, y por eso una
/// fila no se cae cuando un sitio se cae.
///
/// Las extensiones siguen intactas y siguen siendo las que reproducen: acá
/// solo se elige QUÉ ver. Las dos cosas se juntan recién en la ficha.
///
/// ── Un solo desplazamiento, sin botones de zona ───────────────────────────
///
/// A pedido explícito: nada de pestañas arriba para cambiar entre anime,
/// series, películas y mangas. Va todo junto y las filas se intercalan, así lo
/// primero que se ve ya tiene de cada cosa. Ver [CatalogoController].
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Se reusa el controller si ya existe: en Android, cambiar de pestaña
  // reconstruye la página entera, y volver a crearlo tiraría el catálogo ya
  // cargado y lo pediría de nuevo. Mismo criterio que la Biblioteca.
  late final CatalogoController c = Get.isRegistered<CatalogoController>()
      ? Get.find<CatalogoController>()
      : Get.put(CatalogoController());

  static final bool _esAndroid = Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          SafeArea(
            child: Obx(() {
              if (c.cargando.value && c.filas.isEmpty) {
                return const Center(child: ProgressRing());
              }
              if (c.vacioDelTodo) return _nadaQueMostrar();
              return RefreshIndicator(
                onRefresh: () => c.cargar(forzar: true),
                child: ListView.builder(
                  // AlwaysScrollable para poder tirar a refrescar aunque el
                  // contenido no llene la pantalla.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(top: _esAndroid ? 8 : 16, bottom: 32),
                  // +1 por el aviso de arriba, cuando hay algo que avisar.
                  itemCount: c.filas.length + 1,
                  itemBuilder: (context, i) =>
                      i == 0 ? _avisoDeZonas() : _fila(c.filas[i - 1]),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _fila(FilaDelHome fila) {
    final color = _colorDeZona(fila.tipo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: HomeSection(
        // El nombre de la zona va PEGADO al de la fila porque acá está todo
        // mezclado en un solo desplazamiento: «Populares» a secas no dice si
        // son series o mangas.
        title: '${fila.titulo.i18n}  ·  ${_nombreDeZona(fila.tipo)}',
        accent: color,
        // Todavía no hay pantalla de «ver todo» del catálogo. El botón queda
        // sin acción antes que mandar a un lugar que no existe.
        onClickMore: () {},
        showNavButtons: !_esAndroid,
        itemCount: fila.obras.length,
        itemBuilder: (context, i) {
          final obra = fila.obras[i];
          return HomeMediaCard(
            key: ValueKey(obra.clave),
            title: obra.titulo,
            subtitle: _subtitulo(obra),
            cover: obra.portada,
            accent: color,
            // Semilla estable para el degradado de respaldo: sin portada, dos
            // tarjetas distintas no pueden quedar del mismo color.
            gradientSeed: obra.clave.hashCode,
            onTap: () => _abrirFicha(obra),
          );
        },
      ),
    );
  }

  /// Año, puntaje y si está saliendo — lo que ayuda a decidir de un vistazo.
  String? _subtitulo(ObraDelCatalogo obra) {
    final partes = <String>[
      if (obra.anio != null) '${obra.anio}',
      // El puntaje se guarda de 0 a 100 venga de donde venga; se muestra sobre
      // 10, que es como la gente lo lee.
      if (obra.puntaje != null) '★ ${(obra.puntaje! / 10).toStringAsFixed(1)}',
      if (obra.enEmision) 'catalogo.saliendo'.i18n,
    ];
    return partes.isEmpty ? null : partes.join('  ·  ');
  }

  void _abrirFicha(ObraDelCatalogo obra) {
    // La ficha del catálogo es lo próximo que se hace.
    //
    // Hasta que exista NO se navega a ningún lado: mandar a la ficha de las
    // extensiones sería mentir, porque esta obra todavía no está asociada a
    // ninguna. Ese puente —buscar el título en las extensiones instaladas y
    // mostrar en cuáles está— es justamente lo que va a hacer la ficha nueva.
  }

  /// Avisa qué zona no pudo cargar y por qué.
  ///
  /// Sobre todo por TMDB: sin su clave, series y películas no salen, y eso se
  /// arregla en Ajustes. Un hueco silencioso deja al usuario creyendo que la
  /// app está rota cuando en realidad le falta un dato.
  Widget _avisoDeZonas() {
    if (c.problemas.isEmpty) return const SizedBox.shrink();

    String zonas(MotivoSinCatalogo m) => c.problemas.entries
        .where((e) => e.value == m)
        .map((e) => _nombreDeZona(e.key))
        .join(', ');

    final sinClave = zonas(MotivoSinCatalogo.faltaLaClave);
    final caidas = zonas(MotivoSinCatalogo.fuenteCaida);
    final mensajes = <String>[
      if (sinClave.isNotEmpty) '$sinClave: ${'catalogo.falta-clave'.i18n}',
      if (caidas.isNotEmpty) '$caidas: ${'catalogo.zona-caida'.i18n}',
    ];
    if (mensajes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HomeTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline,
                size: 18, color: HomeTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensajes.join('\n'),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nadaQueMostrar() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined,
                size: 42, color: HomeTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              'catalogo.sin-catalogo'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: HomeTheme.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: () => c.cargar(forzar: true),
              child: Text('common.retry'.i18n),
            ),
          ],
        ),
      ),
    );
  }

  static String _nombreDeZona(TipoDeObra t) => switch (t) {
        TipoDeObra.anime => 'home.zona-anime'.i18n,
        TipoDeObra.serie => 'home.zona-series'.i18n,
        TipoDeObra.pelicula => 'home.zona-peliculas'.i18n,
        TipoDeObra.manga => 'home.zona-mangas'.i18n,
      };

  /// Un color por zona.
  ///
  /// Con todo mezclado en un solo desplazamiento, el color es lo que deja
  /// ubicarse sin leer: se reconoce «esto es anime» antes de llegar al título.
  static Color _colorDeZona(TipoDeObra t) => switch (t) {
        TipoDeObra.anime => HomeTheme.accentPink,
        TipoDeObra.serie => const Color(0xFF5AA9E6),
        TipoDeObra.pelicula => const Color(0xFFE6A85A),
        TipoDeObra.manga => const Color(0xFF7BD88F),
      };
}
