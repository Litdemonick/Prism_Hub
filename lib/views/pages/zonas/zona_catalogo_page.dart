import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/zona_catalogo_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/tarjeta_de_catalogo.dart';
import 'package:prismhub/views/widgets/infinite_scroller.dart';
import 'package:prismhub/views/widgets/home/zona_sin_clasificar.dart';

/// Por qué orden se ve el catálogo de la zona.
///
/// No hay "Popularidad": ninguna extensión de terceros comparte una métrica
/// real de vistas/valoración entre sí (`ExtensionListItem` no trae ni un
/// contador), así que ese botón sería decorativo. Se ofrecen los dos
/// criterios que sí son reales: el orden que cada sitio ya devuelve, y
/// alfabético — un `sort` de verdad, sobre lo ya cargado.
enum _Orden { recientes, alfabetico }

/// El catálogo de una zona de contenido (Películas/Series/Anime/Mangas):
/// título, un control de orden, y una grilla de todo lo que sus extensiones
/// tienen, que carga más al llegar al final.
///
/// Una sola pantalla parametrizada por [zona] — no cuatro archivos
/// separados, para que las cuatro zonas no se desincronicen entre sí.
class ZonaCatalogoPage extends StatefulWidget {
  const ZonaCatalogoPage({super.key, required this.zona});

  final ZonaPrincipal zona;

  @override
  State<ZonaCatalogoPage> createState() => _ZonaCatalogoPageState();
}

class _ZonaCatalogoPageState extends State<ZonaCatalogoPage> {
  _Orden _orden = _Orden.recientes;

  /// Se reusa si ya existe: volver a esta zona no debería perder lo que ya
  /// se había cargado — mismo patrón que `HomePage`/`SearchPage` con sus
  /// controllers.
  late final ZonaCatalogoController c =
      Get.isRegistered<ZonaCatalogoController>(tag: widget.zona.name)
          ? Get.find<ZonaCatalogoController>(tag: widget.zona.name)
          : Get.put(
              ZonaCatalogoController(widget.zona),
              tag: widget.zona.name,
            );

  String get _titulo => switch (widget.zona) {
        ZonaPrincipal.peliculas => 'home.zona-peliculas'.i18n,
        ZonaPrincipal.series => 'home.zona-series'.i18n,
        ZonaPrincipal.anime => 'home.zona-anime'.i18n,
        ZonaPrincipal.mangas => 'home.zona-mangas'.i18n,
      };

  /// El ícono y el color de cada zona — mismos íconos que ya eligió Android
  /// TV para estas categorías (`_CategoriaTV`, home_page_tv.dart), para
  /// reconocimiento cruzado entre plataformas. Alternar entre los dos
  /// acentos del tema es suficiente para distinguirlas a simple vista, sin
  /// inventar una paleta nueva.
  ({IconData icono, Color acento}) get _decoracion => switch (widget.zona) {
        ZonaPrincipal.peliculas => (
            icono: Icons.movie_rounded,
            acento: HomeTheme.accentPink
          ),
        ZonaPrincipal.series => (
            icono: Icons.tv_rounded,
            acento: HomeTheme.accentRed
          ),
        ZonaPrincipal.anime => (
            icono: Icons.animation_rounded,
            acento: HomeTheme.accentPink
          ),
        ZonaPrincipal.mangas => (
            icono: Icons.auto_stories_rounded,
            acento: HomeTheme.accentRed
          ),
      };

  /// Cuántas columnas entran y qué ancho tiene cada una — mismo cálculo que
  /// ya usa `ultimas_actualizaciones_mangadex_page.dart`: se parte del
  /// mismo ancho de tarjeta que el Home, así que una portada mide igual acá
  /// que en las filas de Inicio.
  ({int columnas, double ancho}) _rejilla(
      BuildContext context, double disponible) {
    final ideal = TarjetaDeCatalogo.anchoPara(Ancho.de(context));
    const separacion = 16.0;
    final columnas =
        ((disponible + separacion) / (ideal + separacion)).floor().clamp(2, 10);
    final ancho = (disponible - separacion * (columnas - 1)) / columnas;
    return (columnas: columnas, ancho: ancho);
  }

  List<ZonaItem> _ordenados() {
    final lista = c.entrelazados;
    if (_orden == _Orden.recientes) return lista;
    final copia = List<ZonaItem>.from(lista);
    copia.sort((a, b) =>
        a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase()));
    return copia;
  }

  /// El encabezado: ícono decorativo + título, con el control de orden al
  /// otro extremo — todo centrado entre sí en la misma fila.
  ///
  /// Sin `AppBar`: dibuja su propia superficie con elevación, y sobre el
  /// fondo animado eso se ve como una franja despareja cruzando la
  /// pantalla (mismo motivo por el que `library_page.dart` tampoco usa
  /// una) — acá el título va suelto, con su propio aire, y se desplaza con
  /// el resto en vez de quedar fijo para siempre.
  Widget _encabezado(BuildContext context) {
    final decoracion = _decoracion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: decoracion.acento.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: decoracion.acento.withValues(alpha: 0.28),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(decoracion.icono, color: decoracion.acento, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _titulo,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: HomeTheme.textPrimary,
              ),
            ),
          ),
          Obx(() {
            // Sin nada cargado todavía no tiene sentido ofrecer orden — se
            // ve al terminar de armar la lista de fuentes.
            if (!c.armado.value || c.fuentes.isEmpty) {
              return const SizedBox.shrink();
            }
            return _BotonDeOrden(
              orden: _orden,
              onChanged: (o) => setState(() => _orden = o),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Column(
            children: [
              _encabezado(context),
              Expanded(child: _contenido(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    return Obx(() {
      // ── Todavía no se sabe qué extensiones hay ──────────────────
      //
      // Antes de que `armado` diga que de verdad terminó de mirar,
      // una lista vacía no significa "no hay nada" — mismo criterio
      // que ya usa el Home con su propio `armado`.
      if (!c.armado.value) {
        return _cargando(context);
      }
      if (c.fuentes.isEmpty) {
        // Ninguna extensión activa entra en esta zona — puede ser
        // que no haya ninguna instalada, o que ninguna la declare
        // todavía (contentKind). El mensaje de la Fase 5 cubre los
        // dos casos sin mentir en ninguno.
        return const ZonaSinClasificar();
      }
      final items = _ordenados();
      if (items.isEmpty && !c.fuentes.any((f) => f.isFetching)) {
        // Hay extensiones clasificadas en la zona, pero su catálogo
        // vino vacío de todas — distinto de "ninguna la declara"
        // (eso es ZonaSinClasificar, arriba).
        return const _SinResultados();
      }
      return InfiniteScroller(
        onRefresh: c.cargarInicial,
        onLoad: c.cargarMas,
        enableInfiniteScroll: c.puedeTraerMas,
        child: LayoutBuilder(
          builder: (context, restricciones) {
            const margen = 16.0;
            final disponible = restricciones.maxWidth - margen * 2;
            if (disponible <= 0) return const SizedBox.shrink();
            final rejilla = _rejilla(context, disponible);
            final alto = TarjetaDeCatalogo.altoTotalDeAncho(rejilla.ancho);
            // Una fila más de esqueletos al pie mientras se pide la próxima
            // página — mismo lenguaje visual que la carga inicial (Esqueleto),
            // para que "cargando más" se vea igual de claro que "cargando".
            // Sin esto, pedir más página no mostraba ningún indicio: la
            // grilla se quedaba quieta hasta que llegaba el contenido nuevo,
            // así que un pedido lento se sentía como que no había pasado
            // nada y invitaba a hacer scroll de nuevo sobre lo mismo.
            final cargandoMas = c.cargandoMas.value;
            final extra = cargandoMas ? rejilla.columnas : 0;
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(margen, 8, margen, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: rejilla.columnas,
                childAspectRatio: rejilla.ancho / alto,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: items.length + extra,
              itemBuilder: (context, i) {
                if (i >= items.length) {
                  return EsqueletoTarjeta(ancho: rejilla.ancho);
                }
                final zi = items[i];
                return TarjetaDeCatalogo(
                  key: ValueKey('${zi.package}|${zi.item.url}'),
                  titulo: zi.item.title,
                  subtitulo: zi.item.update,
                  // De qué extensión viene — imprescindible acá: a
                  // diferencia de una fila del Home (donde el
                  // encabezado ya lo dice una sola vez), esta grilla
                  // mezcla varias fuentes en la misma pantalla.
                  encabezado: zi.nombre,
                  portada: zi.item.cover,
                  cabeceras: zi.item.headers,
                  ancho: rejilla.ancho,
                  onTap: () => ExtensionUtils.openExtensionDetail(
                    context,
                    package: zi.package,
                    url: zi.item.url,
                    cover: zi.item.cover,
                    coverHeaders: zi.item.headers,
                  ),
                );
              },
            );
          },
        ),
      );
    });
  }

  Widget _cargando(BuildContext context) {
    return LayoutBuilder(builder: (context, restricciones) {
      const margen = 16.0;
      final disponible = restricciones.maxWidth - margen * 2;
      final rejilla = disponible > 0
          ? _rejilla(context, disponible)
          : (columnas: 2, ancho: 150.0);
      final alto = TarjetaDeCatalogo.altoTotalDeAncho(rejilla.ancho);
      return EsqueletoDeGrilla(
        columnas: rejilla.columnas,
        proporcion: rejilla.ancho / alto,
        padding: const EdgeInsets.fromLTRB(margen, 8, margen, 8),
      );
    });
  }
}

/// Hay extensiones clasificadas en esta zona, pero ninguna trajo nada — a
/// diferencia de `ZonaSinClasificar` (ninguna extensión la declara), acá el
/// catálogo mismo vino vacío de todas las fuentes.
class _SinResultados extends StatelessWidget {
  const _SinResultados();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 44, color: HomeTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              'home.zona-sin-resultados'.i18n,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: HomeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonDeOrden extends StatelessWidget {
  const _BotonDeOrden({required this.orden, required this.onChanged});

  final _Orden orden;
  final ValueChanged<_Orden> onChanged;

  String _etiqueta(_Orden o) => switch (o) {
        _Orden.recientes => 'home.orden-recientes'.i18n,
        _Orden.alfabetico => 'home.orden-alfabetico'.i18n,
      };

  @override
  Widget build(BuildContext context) {
    // PopupMenuButton a secas salía con el tema de Material por defecto —
    // fondo claro y casi transparente, que contra el resto de la app (fondo
    // oscuro con tarjetas bien opacas) se leía como roto. Se le pone la
    // misma superficie y el mismo borde que usa cualquier otra tarjeta de la
    // app (HomeTheme.cardSurface/border), y el ítem elegido en el acento
    // rosa en vez del azul de Material que no combina con nada más acá.
    return PopupMenuButton<_Orden>(
      initialValue: orden,
      onSelected: onChanged,
      color: HomeTheme.cardSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HomeTheme.border),
      ),
      itemBuilder: (context) => _Orden.values
          .map((o) => PopupMenuItem(
                value: o,
                child: Text(
                  _etiqueta(o),
                  style: TextStyle(
                    color: o == orden
                        ? HomeTheme.accentPink
                        : HomeTheme.textPrimary,
                    fontWeight: o == orden ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HomeTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 16, color: HomeTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              _etiqueta(orden),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HomeTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded,
                size: 16, color: HomeTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
