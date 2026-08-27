import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:get/get.dart';
import 'package:prismhub/controllers/zona_catalogo_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/refresh_button.dart';
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

/// El catálogo de una zona de contenido (Películas/Series/Anime/Mangas), o
/// de la Zona +18 con [zona] en `null`: título, un control de orden, y una
/// grilla de todo lo que sus extensiones tienen, que carga más al llegar al
/// final.
///
/// Una sola pantalla parametrizada por [zona] — no cuatro (o cinco, con
/// +18) archivos separados, para que ninguna se desincronice de las demás.
class ZonaCatalogoPage extends StatefulWidget {
  const ZonaCatalogoPage({super.key, required this.zona});

  final ZonaPrincipal? zona;

  @override
  State<ZonaCatalogoPage> createState() => _ZonaCatalogoPageState();
}

class _ZonaCatalogoPageState extends State<ZonaCatalogoPage> {
  _Orden _orden = _Orden.recientes;

  /// Qué tarjetas ya se mostraron con su entrada animada — para no repetirla
  /// cada vez que `GridView.builder` las vuelve a construir al pasar de
  /// nuevo por encima (sale de la ventana de caché y vuelve). Sin esto, ir
  /// y volver con el scroll hacía que las mismas tarjetas parpadearan de
  /// nuevo como si fueran nuevas.
  final _yaAparecio = <String>{};

  /// El tag de GetX para esta zona — `zona.name`, o `'nsfw18'` para la Zona
  /// +18 (`null` no sirve como tag).
  String get _tag => widget.zona?.name ?? 'nsfw18';

  /// Se reusa si ya existe: volver a esta zona no debería perder lo que ya
  /// se había cargado — mismo patrón que `HomePage`/`SearchPage` con sus
  /// controllers.
  late final ZonaCatalogoController c =
      Get.isRegistered<ZonaCatalogoController>(tag: _tag)
          ? Get.find<ZonaCatalogoController>(tag: _tag)
          : Get.put(
              ZonaCatalogoController(widget.zona),
              tag: _tag,
            );

  /// Para poder llevar la grilla al principio a pedido — ver
  /// `ZonaCatalogoController.volverArriba` y `ZonaCatalogoController.
  /// alTocarDeNuevo`.
  final _scroll = ScrollController();
  Worker? _workerVolverArriba;

  @override
  void initState() {
    super.initState();
    _workerVolverArriba = ever(c.volverArriba, (_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _workerVolverArriba?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _titulo => switch (widget.zona) {
        null => 'nsfw18.title'.i18n,
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
  ///
  /// La Zona +18 usa el acento rojo fijo (`accentRed`, el mismo que ya
  /// identifica esa zona en toda la app) y un ícono de advertencia — nunca
  /// alterna con el rosa, para que no se confunda con una zona normal.
  ({IconData icono, Color acento}) get _decoracion => switch (widget.zona) {
        null => (
            icono: Icons.warning_amber_rounded,
            acento: HomeTheme.accentRed,
          ),
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

  /// Cuántas columnas entran y qué ancho tiene la CELDA de cada una.
  ///
  /// Este ancho sigue siendo el de la celda estirada (no el de la tarjeta
  /// — ver `_celdaConTarjeta` en el itemBuilder): `GridView` reparte el
  /// ancho disponible en partes iguales entre las columnas sí o sí,
  /// estire o no la tarjeta de adentro, así que esta cuenta sigue haciendo
  /// falta para que la celda tenga la forma correcta y no desborde.
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
    // El inset real del sistema (notch/cámara/barra de estado) ya lo separa
    // el `SafeArea` que envuelve todo esto en `build()` — acá solo va el
    // aire visual de siempre, sin sumarlo de nuevo.
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
            final opciones = c.opcionesDeFormato;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Solo en Anime, y solo si al menos una extensión activa
                // declara el eje — pedido explícito: una película de anime
                // (un capítulo) se mezclaba con series de decenas sin
                // forma de pedir solo una de las dos.
                if (opciones.isNotEmpty) ...[
                  _BotonDeFormato(
                    opciones: opciones,
                    elegido: c.formato.value,
                    onChanged: c.cambiarFormato,
                  ),
                  const SizedBox(width: 8),
                ],
                _BotonDeOrden(
                  orden: _orden,
                  onChanged: (o) => setState(() => _orden = o),
                ),
                // Pedido explícito: en PC no hay gesto de deslizar para
                // refrescar como en Android, así que hace falta un botón —
                // mismo patrón que ya usa Inicio (RefreshButton).
                if (!Platform.isAndroid) ...[
                  const SizedBox(width: 8),
                  RefreshButton(onTap: () async => c.alTocarDeNuevo()),
                ],
              ],
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
          Positioned.fill(
            child: AnimatedBackgroundGlow(
              // Rojo en la Zona +18 (`widget.zona == null`) — mismo acento
              // que ya usa el resto de esa zona (Nsfw18ZonePage), para que
              // no se sienta como si el fondo "se olvidó" de dónde está
              // parado el usuario.
              accent: widget.zona == null ? HomeTheme.accentRed : null,
            ),
          ),
          // El fondo animado de arriba SÍ va de borde a borde (es puro
          // decorado); el contenido de acá adentro no puede — sin esto, en
          // horizontal (celular/tablet girado) el encabezado y la grilla se
          // dibujaban debajo de la cámara frontal o de la franja de
          // notificaciones, del lado que hubiera quedado el corte según
          // hacia dónde se giró el aparato. Reportado en vivo con captura,
          // en las dos orientaciones.
          //
          // `bottom: false` — mismo criterio que ya usa Inicio
          // (`home_page_android.dart`, `_HomeAndroid`): la barra flotante de
          // abajo tiene que dejar ver las portadas corriendo por atrás, no
          // un fondo sólido. Reservando el inset de abajo acá, la grilla se
          // quedaba corta antes de llegar al borde y detrás de la barra solo
          // se veía el fondo liso de la pantalla — mismo aspecto en las 4
          // zonas, distinto del de Inicio. El espacio que hace falta para
          // que la última fila no quede tapada por la barra se agrega en el
          // padding de la propia grilla (ver `_contenido`), no acá.
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _encabezado(context),
                Expanded(child: _contenido(context)),
              ],
            ),
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
        //
        // Envuelto en InfiniteScroller igual que la grilla de abajo — sin
        // esto, este estado no tenía NINGÚN gesto de refrescar (ni el
        // `RefreshButton` ni el deslizar hacia abajo llegan hasta acá).
        // Recién instalada una extensión, era imposible pedirle a la zona
        // que la mire sin salir y volver a entrar. Reportado en vivo: "no
        // deja deslizar, no está la función".
        return _conRefresco(context, const ZonaSinClasificar());
      }
      final items = _ordenados();
      if (items.isEmpty && !c.fuentes.any((f) => f.isFetching)) {
        // Hay extensiones clasificadas en la zona, pero su catálogo
        // vino vacío de todas — distinto de "ninguna la declara"
        // (eso es ZonaSinClasificar, arriba). Mismo motivo, mismo arreglo.
        return _conRefresco(context, const _SinResultados());
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
              // Más margen de precarga que el default (250px): con tarjetas
              // altas, el default apenas cubre una fila de sobra. Haciendo
              // scroll rápido (arrastre fuerte o rueda del mouse a fondo) se
              // veían huecos en gris un instante antes de que la portada
              // llegara a decodificarse. El doble de alto de tarjeta para
              // arriba y para abajo le da tiempo a la imagen sin pedir
              // tarjetas de más que nunca se llegan a ver.
              scrollCacheExtent: ScrollCacheExtent.pixels(alto * 2),
              controller: _scroll,
              // El de abajo suma el inset real de la barra flotante — con
              // `SafeArea(bottom: false)` en el build() de arriba, nada más
              // se encarga de que la última fila no quede tapada detrás de
              // ella. Mismo cálculo que ya usa Inicio.
              padding: EdgeInsets.fromLTRB(
                  margen, 8, margen, MediaQuery.paddingOf(context).bottom + 24),
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
                final clave = '${zi.package}|${zi.item.url}';
                // La primera vez que esta tarjeta se dibuja, entra con un
                // fundido — la tanda entera de golpe, sin avisar, hacía
                // perder de vista dónde estaba parado el ojo justo cuando
                // llegan muchas juntas (pedido explícito, estilo
                // Crunchyroll: "que vayan poniendo poco a poco pero
                // rápido"). Si ya se vio antes, aparece directo — no hay
                // que repetirle la animación cada vez que vuelve a entrar
                // en pantalla con el scroll.
                final yaVista = !_yaAparecio.add(clave);
                final tarjeta = TarjetaDeCatalogo(
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
                    // ── Sin esto, el Historial/Favoritos de acá se colaba
                    // en la Biblioteca normal ────────────────────────────
                    //
                    // `DetailController.isNsfw` (lo que de verdad decide
                    // dónde queda guardado un ítem) es
                    // `isAdultOption || extension.nsfw` — una extensión
                    // ENTERA +18 (HentaiLA) ya da `true` sola, pero una
                    // MIXTA (ShadeManga, ManhwaWeb) declara `nsfw: false`
                    // en su manifiesto: su parte de adultos SOLO se marca
                    // bien si se manda `isAdultOption` explícito. Sin esto,
                    // ver o marcar favorito algo de una mixta desde ACÁ
                    // (la Zona +18) se guardaba como contenido normal y
                    // aparecía en la Biblioteca de siempre — justo lo que
                    // esta zona promete que nunca pasa.
                    isAdultOption: widget.zona == null,
                  ),
                );
                if (yaVista) {
                  return KeyedSubtree(key: ValueKey(clave), child: tarjeta);
                }
                return _EntradaSuave(
                  key: ValueKey(clave),
                  // Un escalón chico por columna: la fila entera termina de
                  // entrar rápido (no más de unos 200ms de punta a punta),
                  // pero se nota que van "poniéndose" una detrás de otra en
                  // vez de aparecer todas en el mismo instante.
                  retraso: Duration(milliseconds: (i % rejilla.columnas) * 35),
                  child: tarjeta,
                );
              },
            );
          },
        ),
      );
    });
  }

  /// Envuelve un estado vacío/vacío-por-ahora con el mismo gesto de
  /// refrescar que ya tiene la grilla — `SingleChildScrollView` con
  /// `AlwaysScrollableScrollPhysics` para que el tirón hacia abajo se
  /// pueda hacer aunque el contenido no llene la pantalla (sin
  /// `AlwaysScrollable`, un `Center` solo no deja lugar para arrastrar).
  /// Sin "cargar más": acá no hay nada que paginar.
  Widget _conRefresco(BuildContext context, Widget child) {
    return InfiniteScroller(
      onRefresh: c.cargarInicial,
      onLoad: () async {},
      enableInfiniteScroll: false,
      child: LayoutBuilder(
        builder: (context, restricciones) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: restricciones.maxHeight),
            child: child,
          ),
        ),
      ),
    );
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

/// El selector de Formato de una zona (hoy, solo Anime): "Todos" + un
/// ítem por cada id que al menos una extensión activa declara.
class _BotonDeFormato extends StatelessWidget {
  const _BotonDeFormato({
    required this.opciones,
    required this.elegido,
    required this.onChanged,
  });

  /// Los ids con eje real (`_formatos`, ej. 'pelicula'/'serie'/'ova'), sin
  /// el "Todos" — ese se agrega siempre, acá adentro.
  final Set<String> opciones;

  /// '' es "Todos".
  final String elegido;
  final ValueChanged<String> onChanged;

  static const _orden = ['', 'pelicula', 'serie', 'ova', 'especial'];

  String _etiqueta(String id) =>
      id.isEmpty ? 'search.all'.i18n : 'home.formato.$id'.i18n;

  @override
  Widget build(BuildContext context) {
    final items = _orden.where((id) => id.isEmpty || opciones.contains(id));
    // El mismo `Theme` local que en `_BotonDeOrden`: sin esto, el ítem que
    // matchea `initialValue` sale envuelto por Flutter en un rectángulo sin
    // esquinas (`ColoredBox` con `Theme.of(context).highlightColor`) que se
    // clava contra la esquina redondeada del menú. Acá alcanza con
    // apagarlo — la selección ya se ve clara con el ícono de radio, sin
    // hacer falta un resaltado de fondo propio como en Orden.
    return Theme(
      data: Theme.of(context).copyWith(highlightColor: Colors.transparent),
      child: PopupMenuButton<String>(
        initialValue: elegido,
        onSelected: onChanged,
        color: HomeTheme.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        // `PopupMenuButton.clipBehavior` viene en `Clip.none` por defecto —
        // con el borde redondeado puesto pero sin recortar, el fondo
        // cuadrado de cada ítem (su resaltado al pasar el mouse) se salía
        // por las esquinas del borde curvo. Se veía justo en las puntas,
        // que es lo que se reportó como "abre feo, los bordes".
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: HomeTheme.border),
        ),
        itemBuilder: (context) => [
          for (final id in items)
            PopupMenuItem(
              value: id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    id == elegido
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 18,
                    color: id == elegido
                        ? HomeTheme.accentPink
                        : HomeTheme.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _etiqueta(id),
                    style: TextStyle(
                      color: id == elegido
                          ? HomeTheme.accentPink
                          : HomeTheme.textPrimary,
                      fontWeight:
                          id == elegido ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            // Un punto de acento cuando hay algo elegido que no es "Todos" —
            // mismo lenguaje que `_PuntoDeFiltro` en el buscador por
            // extensión, para que se note de un vistazo que hay un filtro
            // puesto sin tener que abrir el menú.
            color: elegido.isEmpty
                ? HomeTheme.cardSurface
                : HomeTheme.accentPink.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: elegido.isEmpty ? HomeTheme.border : HomeTheme.accentPink,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded,
                  size: 16,
                  color: elegido.isEmpty
                      ? HomeTheme.textMuted
                      : HomeTheme.accentPink),
              const SizedBox(width: 6),
              Text(
                elegido.isEmpty ? 'search.filter'.i18n : _etiqueta(elegido),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: elegido.isEmpty
                      ? HomeTheme.textPrimary
                      : HomeTheme.accentPink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    // ── Sin el resaltado cuadrado que trae Flutter de fábrica ────────────
    //
    // `PopupMenuButton` con `initialValue` puesto envuelve SOLO ese ítem en
    // un `ColoredBox` propio (Theme.of(context).highlightColor) — un
    // rectángulo sin ninguna esquina redondeada, pegado contra el borde
    // curvo del menú. Con `clipBehavior: Clip.antiAlias` el menú entero
    // queda bien recortado por afuera, pero ESTE rectángulo vive por
    // ADENTRO del recorte, así que sus esquinas cuadradas se veían
    // clavadas contra la esquina redondeada del contenedor — "el filtro
    // taparlo pero en su borde no pasarse", reportado con captura.
    //
    // Apagando `highlightColor` acá (con un `Theme` local, sin tocar el
    // resto de la app) ese rectángulo queda transparente, y el ítem
    // elegido se marca en cambio con el propio `Container` de abajo — con
    // su propio radio, así que nunca puede pasarse del borde del menú.
    return Theme(
      data: Theme.of(context).copyWith(highlightColor: Colors.transparent),
      child: PopupMenuButton<_Orden>(
        initialValue: orden,
        onSelected: onChanged,
        color: HomeTheme.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: HomeTheme.border),
        ),
        // Sin esto el menú se achica al ancho del texto más corto ("Recientes"/
        // "Alfabético", dos palabras sueltas) y queda una cajita angosta que
        // no tapa bien el fondo detrás — reportado en vivo comparándolo con el
        // de Formato, que al tener más opciones ya se ve ancho y prolijo. Un
        // mínimo fijo le da el mismo porte a los dos, sin depender de cuántas
        // letras tenga la opción más larga.
        constraints: const BoxConstraints(minWidth: 170),
        itemBuilder: (context) => _Orden.values
            .map((o) => PopupMenuItem(
                  value: o,
                  // Sin relleno propio: el Container de adentro pone el
                  // suyo, así el resaltado rosa queda inset del borde del
                  // menú por los mismos 4px en las cuatro direcciones.
                  padding: EdgeInsets.zero,
                  child: Container(
                    width: double.infinity,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: o == orden
                          ? HomeTheme.accentPink.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _etiqueta(o),
                      style: TextStyle(
                        color: o == orden
                            ? HomeTheme.accentPink
                            : HomeTheme.textPrimary,
                        fontWeight:
                            o == orden ? FontWeight.w700 : FontWeight.w500,
                      ),
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
      ),
    );
  }
}

/// La entrada de una tarjeta nueva: fundido + un empujón chico hacia
/// arriba, con un [retraso] opcional para escalonarla contra las de al
/// lado.
///
/// Por qué no `AnimatedList`/`AnimatedSwitcher`: acá no hace falta animar
/// una salida ni reordenar nada, solo la aparición única de cada tarjeta
/// nueva — un controller propio, chico y sin dependencias es más simple
/// que adaptar un widget pensado para otra cosa.
class _EntradaSuave extends StatefulWidget {
  const _EntradaSuave({
    super.key,
    required this.child,
    this.retraso = Duration.zero,
  });

  final Widget child;
  final Duration retraso;

  @override
  State<_EntradaSuave> createState() => _EntradaSuaveState();
}

class _EntradaSuaveState extends State<_EntradaSuave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Rápido a propósito: el pedido fue "que vayan poniendo poco a poco
    // pero rápido" — esto es lo que tarda UNA tarjeta desde que arranca,
    // no la tanda entera (eso lo pone el escalón por columna en `retraso`).
    duration: const Duration(milliseconds: 220),
  );
  late final _opacidad = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.retraso == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.retraso, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacidad,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _opacidad.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _opacidad.value) * 14),
          child: child,
        ),
      ),
    );
  }
}
