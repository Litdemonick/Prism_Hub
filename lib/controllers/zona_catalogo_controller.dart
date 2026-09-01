import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:prismhub/controllers/catalogo_extensiones_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/prismhub_mas.dart';
import 'package:prismhub/utils/search_text.dart';

/// Una extensión de la zona, con lo que ya trajo y en qué página va.
///
/// No es una `FilaDeExtension` del Home a propósito — ver el comentario
/// largo en `_traerDeVerdad` (catalogo_extensiones_controller.dart): esa
/// clase tiene su propio ciclo de vida (caché en disco, aporte a
/// `destacados`, todo indexado por `package`), pensado para UNA fila en
/// Inicio. Una zona junta contenido de VARIAS extensiones a la vez con
/// timeouts independientes por sitio — el mismo problema que ya resuelve
/// `SearchController` — así que tiene su propia clase, chica y sin nada de
/// eso.
class ZonaFuente {
  ZonaFuente({
    required this.package,
    required this.nombre,
    required this.filtro,
  });

  final String package;
  final String nombre;

  /// El filtro con el que se pide el catálogo — nunca cambia después de
  /// armado. `null` es válido y significa "sin puerta que cerrar" (una
  /// extensión que no es `mixed` no tiene contenido +18 que filtrar); es
  /// distinto del `null` que devuelve `filtroDeFormatoZona` para una
  /// extensión `mixed` sin eje, que en cambio EXCLUYE la extensión de la
  /// zona entera (ver `ZonaCatalogoController._armarFuentes`) — acá ya
  /// llegó resuelto.
  final Map<String, List<String>>? filtro;

  final items = <ExtensionListItem>[];
  int pagina = 1;

  /// La última página vino vacía: no se le vuelve a pedir.
  bool agotada = false;

  bool isFetching = false;
  Future<void>? inFlight;
  Object? error;

  /// Cuándo contestó de verdad por última vez. Null si todavía nunca.
  ///
  /// De acá sale si lo que se está mostrando ya está viejo — ver
  /// `ZonaCatalogoController.pedirFuente`.
  DateTime? traidoEl;

  /// Sus `items` vinieron del caché en disco, no de una respuesta real
  /// todavía — ver `ZonaCatalogoController.cargarInicial`. Sigue contando
  /// como "vacía" para el pool de pedidos: sin esto, mostrar el caché
  /// cancelaba el pedido de verdad y la zona se quedaba con datos viejos
  /// para siempre.
  bool desdeCache = false;
}

/// Un ítem del catálogo de zona, con de qué extensión vino — para poder
/// mostrarlo en la tarjeta (`TarjetaDeCatalogo.encabezado`) y para poder
/// abrir su detalle.
typedef ZonaItem = ({String package, String nombre, ExtensionListItem item});

/// El catálogo de una zona de contenido (Películas/Series/Anime/Mangas):
/// junta lo que cada extensión de la zona tiene, sin tocar en nada el
/// estado compartido y mutable de Inicio (`CatalogoExtensionesController`,
/// ver el hallazgo B del plan de rediseño) — la única lectura que hace de
/// ahí es `filtroDeFormatoZona`, que es puro.
///
/// Una instancia por zona, registrada con `tag: zona.name` (mismo patrón
/// que `SearchPageController.zoneTag`) para que las cuatro convivan sin
/// pisarse y volver a una ya visitada encuentre lo que ya había cargado.
class ZonaCatalogoController extends GetxController {
  ZonaCatalogoController(this.zona);

  /// `null` es la Zona +18: mismo controller y mismo mecanismo de pool/
  /// intercalado que las 4 zonas normales, pero con su propio criterio de
  /// qué extensiones entran (ver `_armarFuentes`) — nunca se mezcla con
  /// ninguna `ZonaPrincipal`.
  final ZonaPrincipal? zona;

  final fuentes = <ZonaFuente>[].obs;

  /// Sube cada vez que se pide "volver arriba" en esta zona — tocar de
  /// nuevo su propio botón en el panel lateral estando ya adentro. Un
  /// `router.go` a la ruta en la que ya se está es un no-op para
  /// go_router (no hay transición, `didUpdateWidget` no se entera), así
  /// que hace falta una señal aparte para que la pantalla sepa que hay que
  /// desplazar la grilla al principio. `ZonaCatalogoPage` escucha esto con
  /// un `ever` y anima su `ScrollController` a 0.
  final volverArriba = 0.obs;

  /// El resultado ya intercalado — se mantiene y se hace CRECER, nunca se
  /// recalcula entero de nuevo.
  ///
  /// ── El bug real que esto corrige ─────────────────────────────────────
  ///
  /// `entrelazados` era un getter que recorría todas las `fuentes` de cero
  /// cada vez, tomando bloques de `porExtension` de cada una según cuánto
  /// tuviera cargado EN ESE MOMENTO. Eso es determinista para una foto fija,
  /// pero con paginación no lo es entre dos fotos: si la fuente B recién
  /// tenía 3 ítems y pasa a tener 8 (llegó una página nueva), el bloque de B
  /// crece de 3 a 8 y TODO lo que venía después en la lista intercalada —los
  /// ítems de A que ya estaban en pantalla— se corre para atrás. Reportado
  /// en vivo: una tarjeta que ya estaba en una posición saltaba a otra
  /// apenas terminaba de cargar más.
  ///
  /// Ahora se guarda hasta dónde de cada fuente ya se repartió
  /// (`_cursores`) y cada vez que hay contenido nuevo se AGREGA el
  /// intercalado que corresponde a lo nuevo — nunca se reordena ni se
  /// vuelve a repartir lo que ya se entregó antes.
  final _entrelazados = <ZonaItem>[];
  final _cursores = <String, int>{};

  /// Título normalizado de cada ítem que YA entró a `_entrelazados` —
  /// pedido explícito: "que no haya duplicaciones, hay muchas extensiones
  /// que pueden tener el mismo anime". Varias extensiones de la misma zona
  /// suelen traer el mismo título (JKAnime y TioAnime publican el mismo
  /// anime, por ejemplo) — sin esto se veía dos, tres, cuatro veces la
  /// misma portada, una por cada extensión que la tiene.
  ///
  /// `SearchText.normalize` (minúsculas, sin tildes, espacios colapsados)
  /// y no una comparación literal: dos sitios rara vez escriben el título
  /// EXACTO igual (mayúsculas, un espacio de más). Es una heurística —dos
  /// obras distintas que por casualidad compartan título quedarían
  /// fundidas en una— pero es el mismo riesgo que ya acepta el resto de la
  /// app en casos parecidos, y preferible a mostrar la misma portada
  /// repetida cuatro veces seguidas.
  final _titulosVistos = <String>{};

  List<ZonaItem> get entrelazados => _entrelazados;

  /// Reparte en `_entrelazados` lo que haya de nuevo desde la última vez,
  /// respetando el mismo orden de fuentes y el mismo tamaño de bloque de
  /// siempre — solo que agregando, nunca recalculando desde cero.
  void _actualizarEntrelazados() {
    var progreso = true;
    while (progreso) {
      progreso = false;
      for (final f in fuentes) {
        final desde = _cursores[f.package] ?? 0;
        final hasta = (desde + CatalogoExtensionesController.porExtension)
            .clamp(0, f.items.length);
        if (hasta <= desde) continue;
        for (var i = desde; i < hasta; i++) {
          final item = f.items[i];
          final titulo = SearchText.normalize(item.title);
          // Un título vacío no cuenta como duplicado de otro vacío — sin
          // esto, dos ítems sin título (raro, pero pasa) se tapaban entre
          // sí. `Set.add` devuelve false si ya estaba: se avanza el cursor
          // igual la haya agregado o no, si no la próxima vuelta la vuelve
          // a mirar y nunca progresa.
          if (titulo.isNotEmpty && !_titulosVistos.add(titulo)) continue;
          _entrelazados.add((package: f.package, nombre: f.nombre, item: item));
        }
        _cursores[f.package] = hasta;
        progreso = true;
      }
    }
  }

  /// Cargando la primera tanda (la lista de fuentes + su primera página).
  final cargando = false.obs;

  /// Pidiendo más páginas de las que ya estaban.
  final cargandoMas = false.obs;

  /// Ya se terminó de armar la lista de fuentes al menos una vez — hasta
  /// entonces, una lista vacía significa "todavía no se sabe", no "no hay
  /// nada" (mismo criterio que `armado` en el Home).
  final armado = false.obs;

  /// Cuántas veces se volvió a intentar armar por no haber motores todavía.
  ///
  /// Mismo problema que ya resolvió el Home
  /// (`CatalogoExtensionesController._armarDeVerdad`, mismo comentario ahí):
  /// esta zona arma sus fuentes apenas se entra a ella (`onInit`), y en ese
  /// momento las extensiones pueden seguir cargando —`ExtensionUtils.runtimes`
  /// todavía vacío—, así que `_armarFuentes()` da una lista vacía que no
  /// significa "ninguna la declara", sino "todavía no se sabe". Reportado en
  /// vivo en PC/Windows: la zona mostraba "ninguna de tus extensiones activas
  /// declara contenido para esta zona" mientras en realidad seguía cargando.
  /// Mismo remedio: reintentar unas pocas veces antes de dar el aviso por
  /// bueno.
  int _reintentosDeArmado = 0;

  /// Cuántas extensiones se piden a la vez al entrar a una zona.
  ///
  /// Era un `4` fijo. Cada pedido corre el motor JS de su extensión entero
  /// (`CryptoJS`, `jsencrypt`, `md5` incluidos) — cuatro a la vez es lo que
  /// ya usa el Home (`CatalogoExtensionesController._aLaVez`) para SUS
  /// filas, pero una zona entra de GOLPE (`cargarInicial` pide todas las
  /// fuentes juntas) mientras el Home reparte la carga: cada fila pide la
  /// suya recién cuando entra en pantalla (`pedirSiHaceFalta`). Reportado
  /// en vivo, en el televisor de 893 MB: "al entrar a las zonas se cierra
  /// la app". Menos motores vivos a la vez en un aparato modesto — más
  /// lento para terminar de traer todo, pero sin la ráfaga que lo tira
  /// abajo.
  static int get _maxConcurrent =>
      PrismHubMas.nivel == NivelDeAparato.bajo ? 2 : 4;

  /// Junta varios `fuentes.refresh()` seguidos en uno solo.
  ///
  /// ── Por qué hacía falta ──────────────────────────────────────────────
  ///
  /// Con `_maxConcurrent=4`, cada una de las N extensiones de la zona
  /// terminaba su pedido por separado y llamaba a `fuentes.refresh()` —o
  /// sea, hasta N reconstrucciones de la grilla entera en la misma ráfaga de
  /// un segundo. La grilla en sí no perdía la posición del scroll (el
  /// `Element` del `GridView` es el mismo entre una reconstrucción y la
  /// siguiente), pero la barra de scroll que Flutter agrega sola en
  /// escritorio SÍ reinicia su animación de aparición/desvanecido con cada
  /// reconstrucción — reportado en vivo como "la barra parpadea y va muy
  /// rápido" al bajar justo mientras las extensiones están respondiendo.
  ///
  /// Se junta en una sola actualización por tanda en vez de tocar cómo
  /// Flutter dibuja su propia barra.
  Timer? _debounceRefresco;
  void _refrescarDebounced() {
    _debounceRefresco?.cancel();
    _debounceRefresco = Timer(
      const Duration(milliseconds: 200),
      fuentes.refresh,
    );
  }

  @override
  void onClose() {
    _debounceRefresco?.cancel();
    _debounceGuardado?.cancel();
    super.onClose();
  }

  /// Evita pedir para siempre a una extensión con un catálogo enorme.
  ///
  /// Bajado de 25 a 20, pedido explícito: con muchas extensiones activas en
  /// una zona, cada página de más es una ronda completa de peticiones a
  /// TODAS —el mismo costo que ya obligó al respiro de `cargarMas` entre
  /// una carga y la siguiente—. Sin necesidad real de bajar tanto: son
  /// varios cientos de tarjetas por extensión antes de llegar al tope.
  static const _maxPaginas = 20;

  // ── De vuelta a pedir el catálogo apenas se crea el controller ────────
  //
  // Hubo un intento de sacar esto de acá: un `IndexedStack` en escritorio
  // (main_page.dart) montaba las 4 zonas JUNTAS al abrir la app, así que las
  // 4 pedían su catálogo A LA VEZ y una extensión que sirve más de una zona
  // (LaMovie en Películas Y Series, MangaDex en Mangas Y en la fila de
  // Inicio) recibía pedidos simultáneos sobre el MISMO motor — reportado en
  // vivo como "MangaDex no responde" con la web andando bien.
  //
  // Ese `IndexedStack` se revirtió del todo (rompía la navegación a la
  // ficha: reemplazaba el Navigator anidado de la ShellRoute, así que
  // `router.push('/detail')` cambiaba la URL pero no mostraba nada). Sin él,
  // cada zona vuelve a construirse recién cuando el usuario entra de
  // verdad — una sola a la vez, como siempre — así que el problema que
  // motivó sacar esto de acá ya no existe. Dejarlo afuera SÍ rompía algo
  // nuevo: `_alVolverA` (main_page.dart) solo pide de nuevo si el
  // controller YA está registrado, y en la primera visita a una zona
  // `didUpdateWidget` corre ANTES de que `ZonaCatalogoPage` llegue a crear
  // su controller — la zona se quedaba con el esqueleto de carga para
  // siempre, sin pedir nada nunca.
  @override
  void onInit() {
    super.onInit();
    unawaited(cargarInicial());
  }

  /// A qué formato le pide esta zona, si la extensión es `mixed`.
  Set<String> get _formatosCandidatos => zona == ZonaPrincipal.mangas
      ? ExtensionUtils.formatosDeLectura
      : ExtensionUtils.formatosDeVideo;

  /// Selector manual de Formato — hoy solo en la zona Anime: sin esto, una
  /// película de anime (un solo capítulo) se mezclaba con series de
  /// decenas, sin forma de pedir solo una de las dos. `''` es "Todos", el
  /// comportamiento de siempre.
  static const _formatosAnimeManual = {'pelicula', 'serie', 'ova', 'especial'};
  final formato = ''.obs;

  /// Las opciones reales de ese selector — vacío si la zona no tiene uno.
  /// Se arma mirando qué extensiones ACTIVAS de la zona declaran cada eje
  /// en su propio filtro, así que nunca ofrece una opción que ningún sitio
  /// instalado puede cumplir.
  Set<String> get opcionesDeFormato {
    if (zona != ZonaPrincipal.anime) return const {};
    final catalogo = Get.isRegistered<CatalogoExtensionesController>()
        ? Get.find<CatalogoExtensionesController>()
        : null;
    if (catalogo == null) return const {};
    final disponibles = <String>{};
    for (final entrada in ExtensionUtils.enabledRuntimes.entries) {
      final package = entrada.key;
      if (entrada.value.extension.nsfw) continue;
      if (!ExtensionUtils.zonasDe(package).contains(zona)) continue;
      disponibles.addAll(
        catalogo.formatosDisponiblesDe(package, _formatosAnimeManual),
      );
    }
    return disponibles;
  }

  /// Cambia el Formato elegido y vuelve a armar la zona con el filtro
  /// nuevo — un cambio de eje no es un dato que se pueda recortar del lado
  /// del cliente (`ExtensionListItem` no trae el formato por ítem, ver
  /// hallazgo D del plan), así que hace falta pedirlo de nuevo a cada
  /// fuente.
  void cambiarFormato(String nuevo) {
    if (formato.value == nuevo) return;
    formato.value = nuevo;
    unawaited(cargarInicial());
  }

  /// Arma la lista de extensiones de la zona y resuelve el filtro de cada
  /// una — de solo lectura sobre `ExtensionUtils`/`CatalogoExtensionesController`,
  /// nunca escribe nada compartido.
  List<ZonaFuente> _armarFuentes() {
    final catalogo = Get.isRegistered<CatalogoExtensionesController>()
        ? Get.find<CatalogoExtensionesController>()
        : null;
    final nuevas = <ZonaFuente>[];
    for (final entrada in ExtensionUtils.enabledRuntimes.entries) {
      final package = entrada.key;
      final extension = entrada.value.extension;
      // ── Zona +18: criterio propio, separado del de las zonas normales ──
      //
      // Mismo criterio que ya usa `SearchPageController.getRuntime` en modo
      // `nsfwOnly` — entera +18 (HentaiLA, VeoHentai), o mixta (ShadeManga,
      // ManhwaWeb) aportando SOLO su parte de adultos. Una entera +18 no
      // tiene puerta que cerrar: todo lo suyo ya es adulto, así que sin
      // filtro alcanza — pedirle con `null` la deja usar su propio
      // catálogo completo. Una mixta SÍ necesita el filtro explícito de
      // `adultosDe`: sin él, cada una aplica su propio default —que es el
      // seguro, a propósito— y la Zona +18 mostraría catálogo normal.
      if (zona == null) {
        if (!extension.nsfw && !ExtensionUtils.esMixta(package)) continue;
        final filtroAdulto =
            extension.nsfw ? null : ExtensionUtils.adultosDe(package);
        // Una mixta sin filtro de adultos detectado todavía (recién
        // instalada, `detectarMixtas` no la vio) se excluye por ahora —
        // mismo criterio de "mejor una fuente de menos" que ya usan las
        // zonas normales con una extensión `mixed` sin eje resuelto.
        if (!extension.nsfw && filtroAdulto == null) continue;
        nuevas.add(ZonaFuente(
          package: package,
          nombre: extension.name,
          filtro: filtroAdulto,
        ));
        continue;
      }
      // Una extensión marcada +18 de punta a punta (HentaiLA, VeoHentai)
      // NUNCA entra a una zona normal, sea cual sea su `contentKind` —
      // mismo criterio que ya aplica `SearchController` para el buscador
      // general. Una MIXTA (ShadeManga, ManhwaWeb) no cae acá: esas
      // declaran `nsfw: false` en su manifiesto — su contenido +18 vive
      // detrás del filtro propio del sitio, ya resuelto más abajo
      // (`filtroDeFormatoZona`/`segurosDe`), no de esta marca global.
      if (extension.nsfw) continue;
      if (!ExtensionUtils.zonasDe(package).contains(zona)) continue;
      Map<String, List<String>>? filtro;
      if (extension.type == ExtensionType.mixed) {
        // Sin el controller todavía registrado no hay de dónde leer el eje
        // — se excluye por ahora en vez de arriesgar mezclar vídeo con
        // lectura; la próxima vez que se arme la lista (recargar/pull to
        // refresh) ya lo va a encontrar registrado.
        if (catalogo == null) continue;
        // Con el selector manual de Formato puesto (solo existe en Anime),
        // se acota al eje puntual elegido en vez del conjunto entero de
        // formatos de vídeo — mismo criterio que la rama de abajo.
        final candidatos =
            (zona == ZonaPrincipal.anime && formato.value.isNotEmpty)
                ? {formato.value}
                : _formatosCandidatos;
        final resuelto = catalogo.filtroDeFormatoZona(package, candidatos);
        // Sin ningún eje que separe vídeo de lectura (o que cumpla el
        // formato elegido a mano): se excluye la extensión ENTERA de esta
        // zona (mismo criterio fijado en la Fase 3) — nunca se muestra sin
        // filtrar.
        if (resuelto == null) continue;
        filtro = resuelto;
      } else if (zona == ZonaPrincipal.anime && formato.value.isNotEmpty) {
        // Selector manual de Formato: sin elegir nada ("Todos") no cambia
        // nada de lo que ya había. Con una opción puesta, mismo mecanismo
        // que arriba para pedir el eje puntual — y mismo criterio de
        // excluir la fuente si el sitio no lo declara, en vez de mostrarla
        // sin filtrar contradiciendo lo que el usuario pidió ver.
        if (catalogo == null) continue;
        final resuelto = catalogo.filtroDeFormatoZona(package, {formato.value});
        if (resuelto == null) continue;
        filtro = resuelto;
      } else if ((zona == ZonaPrincipal.peliculas ||
              zona == ZonaPrincipal.series) &&
          ExtensionUtils.zonasDe(package).containsAll(const {
            ZonaPrincipal.peliculas,
            ZonaPrincipal.series,
          })) {
        // Una extensión `accion-real`/`mixto` (LaMovie, FuegoCine) entra a
        // las DOS zonas a la vez — sin partir por formato, Películas y
        // Series mostraban el mismo catálogo completo sin filtrar: medido en
        // vivo, la zona Películas traía series de veinte capítulos. Mismo
        // mecanismo que ya separa vídeo de lectura en una extensión `mixed`
        // (arriba), pidiendo el eje puntual de esta zona (`pelicula`/`serie`
        // de `_formatos`) en vez del conjunto entero de formatos de vídeo.
        if (catalogo == null) continue;
        final candidato = zona == ZonaPrincipal.peliculas
            ? const {'pelicula'}
            : const {'serie'};
        final resuelto = catalogo.filtroDeFormatoZona(package, candidato);
        // Sin ningún eje que distinga película de serie en este sitio: se
        // excluye la extensión de esta zona — mejor una fuente de menos que
        // arriesgarse a mezclar series y películas en una zona que promete
        // solo una de las dos.
        if (resuelto == null) continue;
        filtro = resuelto;
      } else {
        // No hay ambigüedad que resolver: o es una zona de un solo formato
        // para esta extensión (anime puro, o accion-real que por algún
        // motivo no entrara a la zona hermana), o es la zona Mangas. Todo su
        // catálogo ya es del tipo que corresponde. `segurosDe` puede seguir
        // devolviendo null acá — no todas tienen una puerta a adultos que
        // cerrar, y no tenerla no es un problema.
        filtro = ExtensionUtils.segurosDe(package);
      }
      nuevas.add(ZonaFuente(
        package: package,
        nombre: extension.name,
        filtro: filtro,
      ));
    }
    return nuevas;
  }

  /// Tocar de nuevo el botón de esta zona estando ya adentro — pedido
  /// explícito: "deja que al tocarlos, refresca, me devuelve arriba al
  /// principio para actualizar por si hay contenido nuevo". Sube la señal
  /// de scroll (`ZonaCatalogoPage` la escucha) y pide `cargarInicial()`
  /// como cualquier otro refresco — reusa filas existentes cuyo filtro no
  /// cambió, no tira nada a la basura de entrada.
  void alTocarDeNuevo() {
    volverArriba.value++;
    unawaited(cargarInicial());
  }

  /// Suelta lo acumulado por paginación, sin perder la zona del todo.
  ///
  /// Pedido explícito: con el refresco automático al re-entrar (ver
  /// `main_page.dart`) y el scroll infinito, una zona visitada varias veces
  /// y con mucho scroll puede terminar con cientos de ítems por extensión
  /// guardados en memoria, la mayoría ya invisibles hace rato. Se llama al
  /// SALIR de la zona (no mientras se la está mirando, para no borrar nada
  /// de lo que el usuario tiene en pantalla): cada fuente vuelve a su
  /// primera tanda, como recién llegado. Al volver a entrar,
  /// `cargarInicial()` la pide de nuevo — un poco de red de más a cambio de
  /// no acumular memoria para siempre en una zona que ya no se está viendo.
  void liberarMemoria() {
    if (fuentes.isEmpty) return;
    for (final f in fuentes) {
      if (f.items.length <= CatalogoExtensionesController.porExtension) {
        continue;
      }
      f.items.removeRange(
        CatalogoExtensionesController.porExtension,
        f.items.length,
      );
      f.pagina = 1;
      f.agotada = false;
    }
    _entrelazados.clear();
    _cursores.clear();
    _titulosVistos.clear();
    _actualizarEntrelazados();
    fuentes.refresh();
  }

  // ─── Caché en disco ───────────────────────────────────────────────────
  //
  // Sin esto, entrar a una zona por primera vez en la sesión mostraba los
  // bloques grises hasta que TODAS sus extensiones respondían — reportado
  // en vivo como "demora en cargar las cards". El Home ya resuelve
  // exactamente este mismo problema con su propio archivo
  // (`CatalogoExtensionesController._archivo`); acá va la misma idea, un
  // archivo por zona, para que lo último que se vio se muestre YA mientras
  // el pedido de verdad refresca por detrás.
  File get _archivoCache => File(p.join(
        PrismHubDirectory.getDirectory,
        'zona_${zona?.name ?? 'nsfw18'}.json',
      ));

  Map<String, dynamic>? _cacheDisco;
  bool _cacheLeido = false;

  Future<Map<String, dynamic>> _leerCacheDisco() async {
    if (_cacheLeido) return _cacheDisco ?? const {};
    _cacheLeido = true;
    try {
      final f = _archivoCache;
      if (!await f.exists()) return const {};
      final crudo = jsonDecode(await f.readAsString());
      if (crudo is Map<String, dynamic>) _cacheDisco = crudo;
    } catch (e) {
      logger.info('[zona] caché ilegible, se ignora: $e');
    }
    return _cacheDisco ?? const {};
  }

  /// Junta varios guardados seguidos en uno solo — mismo motivo que
  /// `_refrescarDebounced`: varias fuentes de la misma zona pueden terminar
  /// su primer pedido casi juntas, y escribir el archivo una vez por cada
  /// una es trabajo de disco de sobra por nada que valga la pena.
  Timer? _debounceGuardado;
  void _guardarCacheDebounced() {
    _debounceGuardado?.cancel();
    _debounceGuardado = Timer(const Duration(milliseconds: 400), () {
      unawaited(_guardarCacheDisco());
    });
  }

  Future<void> _guardarCacheDisco() async {
    try {
      final copia = <String, dynamic>{};
      for (final f in fuentes) {
        // Nunca lo que vino DEL caché sin haberse refrescado — guardar de
        // vuelta lo mismo que se leyó no aporta nada y adelanta su fecha
        // como si fuera contenido nuevo.
        if (f.desdeCache || f.items.isEmpty) continue;
        copia[f.package] = {
          'fecha': DateTime.now().toIso8601String(),
          // Solo lo que se llega a mostrar de esta fuente en un bloque —
          // mismo recorte que ya usa el Home, para no engordar el archivo
          // con páginas que el usuario nunca llegó a ver.
          'items': f.items
              .take(CatalogoExtensionesController.porExtension)
              .map((i) => {'title': i.title, 'url': i.url, 'cover': i.cover})
              .toList(),
        };
      }
      await _archivoCache.writeAsString(jsonEncode(copia));
    } catch (e) {
      logger.info('[zona] no se pudo guardar el caché: $e');
    }
  }

  static List<ExtensionListItem> _itemsDesdeCache(dynamic crudo) {
    if (crudo is! List) return const [];
    final salida = <ExtensionListItem>[];
    for (final e in crudo) {
      if (e is! Map) continue;
      final titulo = e['title']?.toString();
      final url = e['url']?.toString();
      if (titulo == null || url == null) continue;
      salida.add(ExtensionListItem(
        title: titulo,
        url: url,
        cover: e['cover']?.toString(),
      ));
    }
    return salida;
  }

  /// Arma la lista de fuentes y, salvo que se pida lo contrario, les pide a
  /// todas su primera página.
  ///
  /// [pedirTodas] en `false` deja las fuentes armadas pero SIN pedir nada:
  /// cada fila se encarga de pedir lo suyo cuando de verdad aparece en
  /// pantalla (ver [pedirFuente]). Es lo que usa el televisor, donde una
  /// zona son filas por extensión: pedirle a las diez de golpe al entrar
  /// levanta diez motores de JavaScript para mostrar dos filas.
  Future<void> cargarInicial({bool pedirTodas = true}) async {
    if (cargando.value) return;
    cargando.value = true;
    final nuevas = _armarFuentes();
    // ── Puede ser que los motores todavía no estén ────────────────────────
    //
    // Ver el comentario largo de `_reintentosDeArmado`. Tres intentos cortos
    // (600ms) antes de dar por bueno el aviso de "ninguna extensión declara
    // esto": si a los casi dos segundos sigue sin haber ninguna, es que de
    // verdad no hay, y ahí manda el aviso.
    //
    // Fuera del try/finally de abajo a propósito: ese `finally` es el que
    // pone `armado.value = true`, y un `return` desde adentro lo hubiera
    // disparado igual — justo lo que este reintento tiene que evitar.
    if (nuevas.isEmpty && _reintentosDeArmado < 3) {
      _reintentosDeArmado++;
      cargando.value = false;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (fuentes.isEmpty) unawaited(cargarInicial());
      });
      return;
    }
    _reintentosDeArmado = 0;
    try {
      // Se reusan las fuentes viejas que sigan correspondiendo, para no
      // tirar a la basura lo ya cargado si esto se vuelve a llamar (pull
      // to refresh) — mismo criterio que ya usa el Home con sus filas.
      final porPackage = {for (final f in fuentes) f.package: f};
      final cache = await _leerCacheDisco();
      for (final f in nuevas) {
        final vieja = porPackage[f.package];
        if (vieja != null && _mismoFiltro(vieja.filtro, f.filtro)) {
          // Solo si el filtro es el mismo: si cambió (una extensión mixta
          // que ahora sí/no declara su eje) el contenido viejo puede no
          // corresponder más.
          f.items.addAll(vieja.items);
          f.pagina = vieja.pagina;
          f.agotada = vieja.agotada;
          f.desdeCache = vieja.desdeCache;
          continue;
        }
        // Sin NADA en memoria todavía (primera vez en la sesión, `vieja ==
        // null`): lo guardado en disco se muestra YA, sin esperar la red —
        // se sigue pidiendo igual (`desdeCache` no cuenta como "ya tiene",
        // ver `_pedir` más abajo), esto es solo para no abrir en blanco.
        //
        // Si en cambio `vieja` existe pero con OTRO filtro (el selector de
        // Formato cambió), no se toca el disco: ese caché puede ser del
        // filtro viejo, y mostrarlo sería mentir sobre qué se está viendo
        // ahora. Se deja como estaba — el esqueleto de carga de siempre
        // hasta que conteste el filtro nuevo.
        if (vieja != null) continue;
        final guardado = cache[f.package];
        if (guardado is! Map) continue;
        final items = _itemsDesdeCache(guardado['items']);
        if (items.isEmpty) continue;
        f.items.assignAll(items);
        f.desdeCache = true;
      }
      fuentes.assignAll(nuevas);
      // Con qué extensiones activas se armó esta lista — ver
      // [hayExtensionesNuevas].
      _firmaAlArmar = _firmaDeExtensiones();
      // Arranque de cero: acá SÍ corresponde reordenar todo (armado nuevo,
      // filtro que cambió, o pull-to-refresh) — es la única vez que
      // `_entrelazados` se descarta entero. De acá en más (paginación) solo
      // se agrega, nunca se vuelve a repartir lo que ya se entregó.
      _entrelazados.clear();
      _cursores.clear();
      _titulosVistos.clear();
      _actualizarEntrelazados();
      if (pedirTodas) {
        await _pedir(
          fuentes.where((f) => f.items.isEmpty || f.desdeCache).toList(),
        );
      }
    } finally {
      cargando.value = false;
      armado.value = true;
    }
  }

  static bool _mismoFiltro(
    Map<String, List<String>>? a,
    Map<String, List<String>>? b,
  ) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final otro = b[entry.key];
      if (otro == null || otro.join(',') != entry.value.join(',')) {
        return false;
      }
    }
    return true;
  }

  /// Le pide su primera página a UNA fuente, si le hace falta.
  ///
  /// Para las filas del televisor: cada una llama a esto al construirse, o
  /// sea cuando de verdad está por verse. Lo que no se mira, no se pide —
  /// mismo criterio que ya usa el Inicio con sus filas
  /// (`CatalogoExtensionesController.pedirSiHaceFalta`).
  ///
  /// Barato de llamar de más: si ya tiene contenido propio, o si justo está
  /// pidiendo, no hace nada.
  Future<void> pedirFuente(ZonaFuente f) async {
    if (f.isFetching) return;
    // Sin nada todavía (o con lo que quedó del disco): se pide y listo.
    if (f.items.isEmpty || f.desdeCache) {
      if (f.agotada) return;
      await _pedir([f]);
      return;
    }
    // ── Y si lo que se ve ya está viejo, se refresca solo ──────────────
    //
    // En un televisor no hay «deslizar para actualizar» ni tiene sentido
    // un botón de refrescar: nadie va a buscar eso con el mando. Pero el
    // contenido de una zona sí envejece — una extensión publica capítulos
    // nuevos todo el tiempo.
    //
    // Así que se refresca en el momento natural: al ENTRAR a la zona. Cada
    // fila, al construirse, mira cuándo fue la última vez que su extensión
    // contestó de verdad; si pasó [_vigenciaDeLaZona], vuelve a pedir la
    // primera página en segundo plano. Lo que ya está en pantalla se sigue
    // viendo mientras tanto —no se vacía nada— y lo nuevo entra cuando
    // llega.
    //
    // Moverse entre zonas sigue siendo instantáneo: lo recién visto no
    // cumple la antigüedad, así que no se pide nada.
    final traido = f.traidoEl;
    if (traido == null) return;
    if (DateTime.now().difference(traido) < _vigenciaDeLaZona) return;
    // Se pide la PRIMERA página —donde publica lo nuevo— sin perder por
    // dónde iba el usuario: la posición se devuelve apenas termina. Y lo
    // que llega se agrega descartando lo repetido (`traerUna` filtra por
    // url), así que nada de lo que ya se veía se mueve de sitio.
    final paginaQueIba = f.pagina;
    f.pagina = 1;
    try {
      await _pedir([f]);
    } finally {
      f.pagina = paginaQueIba;
    }
  }

  /// Cuánto vale lo que ya se trajo antes de volver a pedirlo.
  ///
  /// Quince minutos: más corto sería pedir de nuevo por pasear entre zonas,
  /// y más largo dejaría el catálogo viejo toda una tarde.
  static const _vigenciaDeLaZona = Duration(minutes: 15);

  /// Si queda alguna fuente con más para traer.
  bool get puedeTraerMas =>
      fuentes.any((f) => !f.agotada && f.pagina < _maxPaginas);

  /// La firma de extensiones con la que se armó la lista de fuentes. Ver
  /// [hayExtensionesNuevas].
  String _firmaAlArmar = '';

  /// Qué extensiones hay y en qué estado, en una cadena comparable.
  ///
  /// Mismo criterio que `CatalogoExtensionesController._firmaDeExtensiones`
  /// (el del Inicio), y por los mismos motivos ya medidos allá: no alcanza
  /// con los paquetes —prender o apagar una no los cambia— ni con la
  /// cantidad —instalar una y sacar otra da el mismo número—. Y la VERSIÓN
  /// hace falta porque una actualización puede cambiar si la extensión
  /// corresponde a esta zona (pasó en vivo con ManhwaWeb, que al
  /// actualizarse empezó a declararse distinto).
  static String _firmaDeExtensiones() {
    final partes = <String>[
      for (final e in ExtensionUtils.runtimes.entries)
        '${e.key}:${ExtensionUtils.isEnabled(e.key) ? 1 : 0}'
            ':${e.value.extension.version}',
    ]..sort();
    return partes.join(',');
  }

  /// Se instaló, activó o desactivó alguna extensión desde la última vez
  /// que esta zona armó su lista.
  ///
  /// ── El hueco que esto cubre ──────────────────────────────────────────
  ///
  /// La lista de fuentes se arma UNA vez (`cargarInicial`) y de ahí en más
  /// la zona se queda viva con lo que trajo. Eso es a propósito —volver a
  /// una zona la encuentra tal cual se dejó, sin recargar nada— pero deja
  /// afuera un caso muy real: el usuario entra a Series, ve que no tiene
  /// nada, va a instalar una extensión de series, y vuelve. La zona sigue
  /// mostrando lo de antes, porque nadie le avisó que el conjunto de
  /// extensiones cambió.
  ///
  /// Preguntado en vivo: "si el usuario no tenía extensiones en series,
  /// ¿cómo refresca? ¿lo hace automático?".
  ///
  /// Se compara contra TODAS las instaladas y su estado, no solo contra las
  /// que entran a esta zona: activar o desactivar una extensión desde
  /// Ajustes también tiene que notarse acá, y una que hoy no clasifica para
  /// la zona puede pasar a hacerlo al actualizarse. Es una comparación de
  /// dos cadenas, así que preguntarlo al entrar a una zona no cuesta nada.
  bool get hayExtensionesNuevas => _firmaDeExtensiones() != _firmaAlArmar;

  /// Se dejó de pedir porque TODAS las fuentes dijeron que no tienen más
  /// (devolvieron una página vacía), no porque se haya llegado al tope
  /// propio de `_maxPaginas`.
  ///
  /// ── Por qué hace falta distinguir ────────────────────────────────────
  ///
  /// Los dos casos dejan `puedeTraerMas` en false, pero significan cosas
  /// muy distintas de cara al usuario: uno es "esto es todo lo que hay" y
  /// el otro es "hay más, pero la app deja de pedir acá". Tratarlos igual
  /// llevaba a decirle "no hay más datos" a alguien que en realidad tiene
  /// contenido esperando del otro lado — una afirmación que la app no
  /// puede sostener.
  ///
  /// Con `_maxPaginas` en 25 y unas decenas de ítems por página, llegar al
  /// tope pide bajar por miles de tarjetas: es un caso rarísimo, pero
  /// afirmar algo falso cuando pasa sigue siendo afirmar algo falso.
  bool get seAgotoDeVerdad =>
      fuentes.isNotEmpty && fuentes.every((f) => f.agotada);

  /// Cuándo terminó el último `cargarMas()`, para el respiro de abajo.
  DateTime? _ultimaCargaMas;

  /// Cuánto tiene que pasar entre el final de un `cargarMas()` y el
  /// principio del siguiente.
  ///
  /// ── El bug que esto cierra ───────────────────────────────────────────
  ///
  /// `cargando.value || cargandoMas.value` evita que DOS pedidos corran a
  /// la vez, pero no pone ningún piso entre uno y el siguiente. Bajando
  /// rápido y sin soltar el mando, cada `cargarMas()` termina, la lista
  /// sigue sin llenar la pantalla que falta, y el próximo arranca en el
  /// MISMO cuadro — sin que la interfaz llegue a respirar entre uno y otro.
  ///
  /// Cada `cargarMas()` reparte el pedido entre varias extensiones a la vez
  /// (`_pedir`), y evaluar el guion de cada una es trabajo de CPU en el
  /// mismo isolate que dibuja la pantalla. Encadenados sin respiro, eso es
  /// varios segundos seguidos sin que la interfaz responda — reportado en
  /// vivo en un televisor de cuatro núcleos: «empezó a moverse, salirse
  /// todo raro, se fue la zona, el panel regresa, un montón de frames
  /// lentos» y, en el aparato más débil, el cierre de la app. En un
  /// televisor más potente el mismo encadenado se nota como tirones; en uno
  /// de gama baja, como un cuelgue que el sistema termina matando.
  ///
  /// Nunca se nota como demora real: mientras dura, la grilla ya muestra
  /// las tarjetas en esqueleto (`cargandoMas`), así que se ve como que
  /// sigue cargando, no como que se congeló.
  static const _respiroEntreCargas = Duration(milliseconds: 700);

  Future<void> cargarMas() async {
    if (cargando.value || cargandoMas.value) return;
    final ultima = _ultimaCargaMas;
    if (ultima != null &&
        DateTime.now().difference(ultima) < _respiroEntreCargas) {
      return;
    }
    final candidatas =
        fuentes.where((f) => !f.agotada && f.pagina < _maxPaginas).toList();
    if (candidatas.isEmpty) return;
    cargandoMas.value = true;
    try {
      for (final f in candidatas) {
        f.pagina++;
      }
      await _pedir(candidatas);
    } finally {
      cargandoMas.value = false;
      _ultimaCargaMas = DateTime.now();
    }
  }

  /// Trae la página siguiente de UNA sola fuente.
  ///
  /// ── Por qué hace falta aparte de `cargarMas` ──────────────────────────
  ///
  /// `cargarMas` le pide la página siguiente a TODAS las fuentes de la zona
  /// a la vez. Eso tiene sentido cuando la zona es una grilla intercalada:
  /// bajar pide más de todo y el contenido nuevo se reparte hacia abajo.
  ///
  /// Pero en televisor la zona son FILAS, una por extensión. Ahí bajar no
  /// puede traer nada: la cantidad de filas es la cantidad de extensiones y
  /// no cambia. Lo que crece es cada fila hacia la DERECHA, así que la
  /// página siguiente se pide cuando el usuario llega al final de esa fila
  /// —y solo de esa—.
  ///
  /// Reportado en vivo: «estoy en la zona película y bajo, me dice seguí
  /// bajando para ver más, y no me da más contenido».
  Future<void> paginarFuente(ZonaFuente f) async {
    if (f.isFetching || f.agotada || f.pagina >= _maxPaginas) return;
    // El mismo respiro que `cargarMas`: con el mando uno mantiene apretada
    // la flecha, y sin esto cada tarjeta que pasa dispara otra página.
    final ultima = _ultimoPaginado[f.package];
    if (ultima != null &&
        DateTime.now().difference(ultima) < _respiroEntreCargas) {
      return;
    }
    _ultimoPaginado[f.package] = DateTime.now();
    f.pagina++;
    await _pedir([f]);
    _ultimoPaginado[f.package] = DateTime.now();
  }

  /// Cuándo se pidió por última vez la página siguiente de cada fuente.
  final _ultimoPaginado = <String, DateTime>{};

  /// Si a esta fuente todavía le queda algo por traer.
  bool leQuedaMas(ZonaFuente f) => !f.agotada && f.pagina < _maxPaginas;

  /// Pool de tareas concurrentes — mismo patrón que ya prueba
  /// `SearchController.getResult()`: con `maxConcurrent` fijo, una
  /// extensión lenta o colgada solo se demora a sí misma, nunca frena a
  /// las demás.
  Future<void> _pedir(List<ZonaFuente> lista) async {
    if (lista.isEmpty) return;
    if (!ConnectivityUtils.isOnline.value) {
      for (final f in lista) {
        f.error = Exception('Connection error: sin conexión a internet');
      }
      fuentes.refresh();
      return;
    }

    var nextIndex = 0;

    Future<void> traerUna(ZonaFuente f) async {
      f.isFetching = true;
      final listo = Completer<void>();
      f.inFlight = listo.future;
      try {
        final runtime = ExtensionUtils.enabledRuntimes[f.package];
        if (runtime == null) {
          f.agotada = true;
          return;
        }
        // ── "Recientes" de verdad, no "lo que el sitio devuelva" ──────────
        //
        // Sin filtro que mandar, se pide por latest() — la MISMA regla que
        // ya usa el Home (_traerDeVerdad, catalogo_extensiones_controller.
        // dart) y por el mismo motivo: latest() es la API dedicada de la
        // extensión para "lo último que publicó", garantizado por su propio
        // contrato. search('', pagina) en cambio devuelve el catálogo del
        // sitio en el orden que EL SITIO elija por defecto — que puede
        // coincidir con lo más reciente (varias extensiones sí lo hacen) o
        // no, y acá no hay forma de saberlo sin medir sitio por sitio.
        //
        // Solo se puede tomar este camino cuando no hace falta filtrar nada
        // (una extensión sin puerta de adultos ni eje de formato que
        // resolver): latest() no acepta filtros, así que con puerta cerrada
        // o formato elegido no queda otra que search().
        final items = await (f.filtro == null
                ? runtime.latest(f.pagina)
                : runtime.search('', f.pagina, filter: f.filtro))
            .timeout(const Duration(seconds: 20));
        if (items.isEmpty) {
          f.agotada = true;
        } else {
          final vistas = f.items.map((e) => e.url).toSet();
          f.items.addAll(items.where((e) => !vistas.contains(e.url)));
          // Se reparte lo nuevo YA, no recién cuando se refresca la UI: son
          // dos cosas separadas — esto es barato (solo agregar a una lista)
          // y tiene que pasar apenas hay datos nuevos, sin esperar los
          // 200ms del debounce de abajo (ese es solo para no reconstruir la
          // grilla de más, no para esto).
          _actualizarEntrelazados();
        }
        f.error = null;
        // Ya contestó de verdad — lo que haya en pantalla ahora es real, no
        // el eco de una sesión anterior. Se guarda para la PRÓXIMA vez que
        // se abra esta zona (ver `cargarInicial`/`_leerCacheDisco`).
        f.desdeCache = false;
        f.traidoEl = DateTime.now();
        _guardarCacheDebounced();
        _refrescarDebounced();
      } catch (e) {
        f.error = e;
        // Se devuelve la página: un fallo no puede saltearse contenido
        // para siempre — mismo criterio que ya usa el Home
        // (_traerDeVerdad) para sus propias filas.
        if (f.pagina > 1) f.pagina--;
        _refrescarDebounced();
      } finally {
        f.isFetching = false;
        f.inFlight = null;
        if (!listo.isCompleted) listo.complete();
      }
    }

    Future<void> worker() async {
      while (nextIndex < lista.length) {
        final f = lista[nextIndex++];
        await traerUna(f);
        // Cede el frame para que la UI pinte lo que acaba de llegar antes
        // de arrancar el próximo pedido.
        await SchedulerBinding.instance.endOfFrame;
      }
    }

    await Future.wait([
      for (var i = 0; i < _maxConcurrent && i < lista.length; i++) worker(),
    ]);
    // La tanda entera terminó: se corta cualquier debounce pendiente y se
    // refresca ya mismo — sin esto, el último tramo (los 200ms del
    // debounce) se sentía como que la pantalla tardaba de más en asentarse.
    _debounceRefresco?.cancel();
    fuentes.refresh();
  }
}
