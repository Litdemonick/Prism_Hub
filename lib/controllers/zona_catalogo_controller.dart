import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/catalogo_extensiones_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';

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

  final ZonaPrincipal zona;

  final fuentes = <ZonaFuente>[].obs;

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
          _entrelazados
              .add((package: f.package, nombre: f.nombre, item: f.items[i]));
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

  static const _maxConcurrent = 4;

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
    super.onClose();
  }

  /// Mismo tope que ya usa el Home para su carrusel — evita pedir para
  /// siempre a una extensión con un catálogo enorme.
  static const _maxPaginas = 25;

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
        final candidatos = (zona == ZonaPrincipal.anime &&
                formato.value.isNotEmpty)
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
    _actualizarEntrelazados();
    fuentes.refresh();
  }

  Future<void> cargarInicial() async {
    if (cargando.value) return;
    cargando.value = true;
    try {
      final nuevas = _armarFuentes();
      // Se reusan las fuentes viejas que sigan correspondiendo, para no
      // tirar a la basura lo ya cargado si esto se vuelve a llamar (pull
      // to refresh) — mismo criterio que ya usa el Home con sus filas.
      final porPackage = {for (final f in fuentes) f.package: f};
      for (final f in nuevas) {
        final vieja = porPackage[f.package];
        if (vieja == null) continue;
        // Solo si el filtro es el mismo: si cambió (una extensión mixta
        // que ahora sí/no declara su eje) el contenido viejo puede no
        // corresponder más.
        if (_mismoFiltro(vieja.filtro, f.filtro)) {
          f.items.addAll(vieja.items);
          f.pagina = vieja.pagina;
          f.agotada = vieja.agotada;
        }
      }
      fuentes.assignAll(nuevas);
      // Arranque de cero: acá SÍ corresponde reordenar todo (armado nuevo,
      // filtro que cambió, o pull-to-refresh) — es la única vez que
      // `_entrelazados` se descarta entero. De acá en más (paginación) solo
      // se agrega, nunca se vuelve a repartir lo que ya se entregó.
      _entrelazados.clear();
      _cursores.clear();
      _actualizarEntrelazados();
      await _pedir(fuentes.where((f) => f.items.isEmpty).toList());
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

  /// Si queda alguna fuente con más para traer.
  bool get puedeTraerMas =>
      fuentes.any((f) => !f.agotada && f.pagina < _maxPaginas);

  Future<void> cargarMas() async {
    if (cargando.value || cargandoMas.value) return;
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
    }
  }

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
