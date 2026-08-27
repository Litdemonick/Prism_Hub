import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_search_page.dart';
import 'package:prismhub/views/pages/search/extension_searcher_page.dart';
import 'package:prismhub/views/pages/search/search_page_tv.dart';
import 'package:prismhub/views/widgets/franja_de_zona.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/search/search_por_categoria.dart';
import 'package:prismhub/views/widgets/tv/pantalla_tv.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

// Mismo lenguaje visual que Home/Historial (HomeTheme: fondo oscuro, chips
// redondeados en vez de tabs/toggle buttons por defecto, caja de búsqueda
// oscura). HorizontalList/ExtensionItemCard/SearchAllTile NO se tocan acá —
// son compartidos con otras páginas (ver comentario histórico en
// home_section.dart), esto solo restila el marco propio de esta página.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.nsfwOnly = false});

  // true = zona +18 del buscador (solo extensiones marcadas +18, acento rojo).
  // Se llega únicamente pasando por Nsfw18SearchGate, que pide confirmación y
  // PIN cada vez.
  final bool nsfwOnly;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late SearchPageController c;
  final _searchController = TextEditingController();

  /// Buscar en vivo, sin esperar Enter — pedido explícito. Sin este
  /// debounce, cada letra dispararía el pool entero (una petición real por
  /// extensión) — el mismo mecanismo que ya cancela una búsqueda vieja
  /// cuando llega una nueva (`_randomKey` en SearchPageController) hace que
  /// eso sea seguro pero no gratis: con 20 extensiones instaladas son 20
  /// pedidos de red por letra tecleada. 350ms de silencio alcanza para que
  /// escribir una palabra entera dispare UNA sola búsqueda, no una por
  /// letra.
  Timer? _debounceEscritura;

  void _alEscribirEnVivo(String value) {
    _debounceEscritura?.cancel();
    if (value.isEmpty) {
      // Vaciar el campo es instantáneo: no hay nada que esperar para volver
      // a la zona vacía.
      c.search.value = '';
      return;
    }
    _debounceEscritura = Timer(const Duration(milliseconds: 350), () {
      c.submitSearch(value);
    });
  }

  // Todo lo que en el buscador normal es rosa, en la zona +18 va en rojo —
  // mismo criterio que la Zona +18 del Home (ver HomeTheme.accentRed).
  Color get _accent =>
      widget.nsfwOnly ? HomeTheme.accentRed : HomeTheme.accentPink;

  // "Lectura" agrupa manga+novela — de cara al usuario es una sola
  // categoría (ambos son texto para leer), aunque internamente sigan
  // siendo tipos distintos (el lector usa una UI distinta para cada uno).
  // videoTypes/readingTypes viven en ExtensionUtils (único lugar) — antes
  // este mismo set estaba duplicado acá y en extension_repo_page.dart.

  @override
  void initState() {
    // Reusa el controller si ya existe (mismo patrón que HomePageController)
    // — antes Get.put() creaba uno NUEVO cada vez que se reentraba a esta
    // pestaña, tirando a la basura todos los resultados ya cargados: volver
    // a Buscar (o, en Android, cambiar de pestaña y volver) hacía que TODAS
    // las extensiones parpadearan de nuevo a "cargando" sin importar los
    // fixes de getRuntime()/getResult() — esos solo evitan el parpadeo
    // DENTRO de la misma instancia del controller, no entre instancias.
    // La zona +18 usa su propia instancia bajo tag (igual que la Zona +18 del
    // Home con HomePageController.zoneTag) — si compartieran instancia, entrar
    // a la zona +18 pisaría los resultados del buscador normal y al volver
    // habría que recargar todo.
    final tag = widget.nsfwOnly ? SearchPageController.zoneTag : null;
    c = Get.isRegistered<SearchPageController>(tag: tag)
        ? Get.find<SearchPageController>(tag: tag)
        : Get.put(SearchPageController(nsfwOnly: widget.nsfwOnly), tag: tag);
    c.isPageOpen = true;
    if (c.needRefresh) {
      c.getRuntime();
    }
    _searchController.text = c.search.value;
    super.initState();
  }

  @override
  void dispose() {
    c.isPageOpen = false;
    _debounceEscritura?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// El filtro de tipo, en la barra de arriba. Solo Android.
  ///
  // ── Sin botón de filtro en Android ────────────────────────────────────
  //
  // Pedido explícito: "quitá el botón de filtros". Acá antes vivía TAMBIÉN
  // la única puerta de Android a la Zona +18 (metida adentro de la hoja de
  // filtros, separada por una línea — "no es un filtro, es otra
  // pantalla"). Sacando el botón entero se perdía esa puerta, así que
  // queda su propio ícono chico en la franja — ver `_botonZona18`.
  //
  // El filtro por tipo (Todo/Vídeo/Lectura) que vivía en esa hoja se va
  // con ella: `_types`/`_typeLabels`/`_chipDeHoja` no tenían otro llamador.

  /// Ícono de entrada a la Zona +18 — reemplaza al viejo botón de filtro,
  /// que era lo único que lo mostraba en Android. Mismas condiciones que
  /// tenía ahí: nunca dentro de la propia Zona +18, y nunca con el switch
  /// de NSFW apagado.
  Widget _botonZona18(BuildContext context) {
    if (widget.nsfwOnly) return const SizedBox.shrink();
    // Obx y no una lectura suelta: ver PrismHubStorage.nsfwEnabled — en
    // Android esta página no se reconstruye al volver de Ajustes, así que
    // con la lectura directa el botón quedaba visible con el switch apagado.
    return Obx(() {
      if (!PrismHubStorage.nsfwEnabled.value) return const SizedBox.shrink();
      return AccionDeFranja(
        ayuda: 'nsfw18.search-zone-title'.i18n,
        alTocar: () => openNsfw18Search(context),
        icono: Icon(Icons.warning_amber_rounded, color: HomeTheme.accentRed),
      );
    });
  }

  Widget _buildProgress() {
    return Obx(() {
      // Altura reservada SIEMPRE (barra 3px + padding 8px), incluso oculta
      // (antes SizedBox.shrink, altura 0) — sin esto, al tocar un chip de
      // tipo la lista se reinicia, la barra aparece de golpe y empuja los
      // chips/resultados hacia abajo; al terminar de cargar desaparece y
      // todo "rebota" de nuevo a su posición original. Con la altura fija,
      // solo cambia la opacidad, nunca el layout de abajo.
      final total = c.searchResultList.length;
      final loading = c.finishCount != total;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 3,
          child: Opacity(
            opacity: loading ? 1 : 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: total == 0 ? null : c.finishCount / total,
                minHeight: 3,
                backgroundColor: HomeTheme.border,
                valueColor: AlwaysStoppedAnimation(_accent),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildResults(void Function(int) onClickMore) {
    return Obx(() {
      if (c.search.value.trim().isEmpty) {
        return _SearchVacio(nsfwOnly: widget.nsfwOnly);
      }
      // ignore: invalid_use_of_protected_member
      final list = c.searchResultList.value;
      // Antes tenía un ValueKey(search + tipo) — cambiar de chip o
      // escribir/borrar en el buscador generaba una key distinta, y eso
      // fuerza a Flutter a DESTRUIR y RECONSTRUIR desde cero todo el árbol
      // de SearchAllExtSearch (cada SearchAllTile, su HorizontalList con su
      // propio ScrollController, cada imagen). SearchAllExtSearch no tiene
      // ningún estado propio que dependa de esa key (todo sale de
      // runtimeList) — clickear los chips varias veces seguido apilaba
      // reconstrucciones completas más rápido de lo que el hilo de UI podía
      // procesarlas, sintiéndose como tirones/traba. Sin key, Flutter solo
      // actualiza las props del mismo widget en vez de recrearlo entero.
      return SearchPorCategoria(
        kw: c.search.value,
        runtimeList: list,
        onClickMore: onClickMore,
      );
    });
  }

  /// Los resultados, con la franja del título como primer elemento.
  ///
  /// ── `cabecera` FUERA del `Obx`, a propósito ─────────────────────────────
  ///
  /// Antes el `Obx` de acá devolvía DOS TIPOS DE WIDGET distintos según si
  /// había texto escrito o no —un `Column` con `_SearchVacio`, o un
  /// `SearchPorCategoria` entero— y en los dos, `cabecera` (que adentro
  /// tiene el campo de texto) iba metido como parámetro/hijo de ese widget
  /// que cambiaba de tipo. Apenas se escribía la PRIMERA letra (vacío →
  /// algo), Flutter no puede reusar el `Element` de `cabecera` a través de
  /// un cambio de tipo del padre: lo destruye y lo vuelve a crear entero,
  /// campo de texto incluido. Eso es exactamente lo reportado en vivo: el
  /// teclado se cierra, la pantalla se ve vacía un instante y vuelve a
  /// aparecer con lo que ya se había escrito (el texto sobrevive porque
  /// vive en `_searchController`, un `TextEditingController` aparte — pero
  /// el `Element` del campo, y con él el foco/teclado, no).
  ///
  /// Con `cabecera` siempre en el MISMO lugar (primer hijo de un `Column`
  /// que ya no cambia de tipo nunca), su `Element` nunca se destruye —solo
  /// cambia lo de ABAJO, en su propio `Obx`. El costo: la franja deja de
  /// esconderse al bajar en los resultados (ya no vive DENTRO del
  /// `SingleChildScrollView` de `SearchPorCategoria`) — mismo compromiso
  /// que la pantalla vacía ya tenía de por sí, ahora parejo en los dos
  /// estados.
  Widget _buildResultados(Widget cabecera, void Function(int) onClickMore) {
    return Column(
      children: [
        cabecera,
        Expanded(
          child: Obx(() {
            if (c.search.value.trim().isEmpty) {
              return _SearchVacio(nsfwOnly: widget.nsfwOnly);
            }
            // ignore: invalid_use_of_protected_member
            final list = c.searchResultList.value;
            return SearchPorCategoria(
              kw: c.search.value,
              runtimeList: list,
              onClickMore: onClickMore,
            );
          }),
        ),
      ],
    );
  }

  Widget _buildAndroidSearch(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      // El teclado se superpone en vez de encoger el body: el campo de
      // búsqueda vive en la AppBar (arriba), así que sigue visible igual, y
      // sin esto en horizontal el body se achicaba tanto que las partes
      // fijas (progreso + chips) ya no entraban y desbordaban.
      resizeToAvoidBottomInset: false,
      // Sin AppBar: el título va en la franja fina, dentro del cuerpo (ver
      // FranjaDeZona). Una AppBar mide 56 y dibuja su propia superficie; acá
      // el contenido pasa justo debajo del título, como en Inicio y en la
      // Biblioteca, y acostado eso es media fila de portadas de diferencia.
      body: RefreshIndicator(
        onRefresh: () async =>
            c.getRuntime(types: c.cuurentExtensionType.value),
        color: _accent,
        backgroundColor: HomeTheme.cardSurface,
        child: Container(
          color: HomeTheme.bg,
          child: Stack(
            children: [
              const Positioned.fill(child: AnimatedBackgroundGlow()),
              // El fondo animado sí va de borde a borde (puro decorado);
              // el contenido de acá adentro no puede — sin esto, en
              // horizontal (celular/tablet girado) la franja de arriba y
              // la fila de chips de "buscar en extensión" se dibujaban
              // debajo de la cámara frontal, del lado que hubiera quedado
              // el corte. Mismo criterio que ya se aplicó en las 4 zonas
              // de contenido. Reportado en vivo con captura, apuntando
              // justo a la flechita de la fila de chips.
              SafeArea(
                // La franja va DENTRO del área desplazable, como primer
                // elemento: se va con los resultados al bajar y vuelve al
                // subir, igual que el nombre de la app en el Inicio. Ver
                // la nota en franja_de_zona.dart.
                child: _buildResultados(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Antes la flecha solo iba en la Zona +18 —"el buscador
                      // normal es una pestaña del shell, no tiene a dónde
                      // volver"—, cierto mientras el único camino de entrada
                      // era Inicio empujándolo con Get.to. Ahora también se
                      // llega desde los tres puntitos del riel, así que
                      // siempre hay un "atrás" real al que volver. Reportado
                      // en vivo: "buscar no tiene flechita para hechar atrás".
                      FranjaDeZona(
                        titulo: widget.nsfwOnly
                            ? "nsfw18.search-zone-title".i18n
                            : "common.search".i18n,
                        controlador: _searchController,
                        ayuda: "search.hint-text".i18n,
                        alEscribir: _alEscribirEnVivo,
                        alEnviar: c.submitSearch,
                        alVolver: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                        // Sin el botón de filtro — pedido explícito. Lo único
                        // que vivía ahí de verdad importante era la puerta a
                        // la Zona +18 (ver _botonZona18), que se queda sola.
                        acciones: [_botonZona18(context)],
                      ),
                      // Son 3 puntos de alto y dice si todavía están buscando.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                        child: _buildProgress(),
                      ),
                    ],
                  ),
                  (index) {
                    Get.to(ExtensionSearcherPage(
                      package: c.getPackgeByIndex(index),
                      keyWord: c.search.value,
                      // Desde la Zona +18 la extensión mixta se abre con su
                      // filtro de adultos ya puesto: si no, mostraba su catálogo
                      // general, que es justo lo que esa zona no es.
                      soloAdulto: widget.nsfwOnly,
                    ));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSearch(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Solo la barra de búsqueda, sin nada alrededor ───────────
              //
              // Pedido explícito con una referencia (una caja de texto sola,
              // sobre fondo liso): sin título, sin chips de Vídeo/Lectura,
              // sin botón de Actualizar — todo eso competía con lo único que
              // esta pantalla necesita mostrar de entrada, que es dónde
              // escribir. El filtro por tipo y el refresco manual siguen
              // existiendo en el controller (getRuntime(types:...)) para
              // quien los necesite después; lo que se saca es la barra que
              // los mostraba siempre, incluso con la pantalla vacía.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: HomeTheme.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HomeTheme.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: HomeTheme.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: fluent.TextBox(
                          controller: _searchController,
                          placeholder: "search.hint-text".i18n,
                          decoration:
                              const WidgetStatePropertyAll(BoxDecoration()),
                          style: TextStyle(
                              color: HomeTheme.textPrimary, fontSize: 15),
                          placeholderStyle:
                              TextStyle(color: HomeTheme.textMuted),
                          // Buscar en vivo, sin esperar Enter — ver
                          // _alEscribirEnVivo.
                          onChanged: _alEscribirEnVivo,
                          onSubmitted: c.submitSearch,
                          suffix: fluent.IconButton(
                            icon: const Icon(fluent.FluentIcons.chrome_close,
                                size: 9.0),
                            onPressed: () {
                              _searchController.clear();
                              c.search.value = '';
                            },
                          ),
                          suffixMode: fluent.OverlayVisibilityMode.editing,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildProgress(),
              ),
              Expanded(
                child: _buildResults((index) {
                  router.push(Uri(
                    path: "/search_extension",
                    queryParameters: {
                      "package": c.getPackgeByIndex(index),
                      "keyWord": c.search.value,
                      // ── La marca de la zona viaja en la ruta ────────────
                      //
                      // En Android la extensión se abre con Get.to y el dato
                      // se pasa como parámetro; acá manda go_router, y la ruta
                      // no lo llevaba. Resultado: entrando desde la Zona +18
                      // en escritorio, la extensión se abría como si viniera
                      // del buscador normal — con su filtro de adultos
                      // escondido, o sea sin poder buscar lo que se fue a
                      // buscar ahí. En el teléfono no pasaba, de ahí que se
                      // viera solo en PC.
                      if (widget.nsfwOnly) "soloAdulto": "1",
                    },
                  ).toString());
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// El buscador de TV: teclado en pantalla a la izquierda, resultados a la
  /// derecha. Ver `search_page_tv.dart`.
  Widget _buildTvSearch(BuildContext context) {
    // Antes iba con un margen fijo de 28 en vez del overscan real — en un
    // televisor que recorta el borde, el teclado en pantalla quedaba pegado
    // al filo. `PantallaTv` es lo que ahora lo aplica bien, en un solo lugar.
    return PantallaTv(
      fondo: const AnimatedBackgroundGlow(),
      child: SearchTV(
        c: c,
        accent: _accent,
        onClickMore: (index) {
          Get.to(ExtensionSearcherPage(
            package: c.getPackgeByIndex(index),
            keyWord: c.search.value,
            soloAdulto: widget.nsfwOnly,
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // TV primero: un Android TV sigue siendo `Platform.isAndroid`, así que
    // sin este chequeo antes, PlatformBuildWidget lo manda al buscador de
    // teléfono — con su teclado del sistema tapando media pantalla.
    if (PlatformTv.esTelevisionSync) return _buildTvSearch(context);
    return PlatformBuildWidget(
      androidBuilder: _buildAndroidSearch,
      desktopBuilder: _buildDesktopSearch,
    );
  }
}

/// El cuerpo de Buscar antes de escribir nada — pedido explícito: esta
/// pantalla ANTES pedía el catálogo completo de cada extensión activa
/// apenas se abría (o al tocar un chip de tipo), así que se sentía como un
/// Inicio más, con filas de portadas, en vez de un buscador. Ahora no se
/// pide ni se muestra nada hasta que el usuario escribe algo de verdad —
/// ver el mismo criterio en `SearchPageController.getRuntime()`.
///
/// Pedido explícito, aparte: un atajo para buscar DENTRO de una sola
/// extensión (ej. "buscar en JKAnime") sin tener que escribir algo primero
/// y esperar a que respondan las demás — un botón por extensión elegible,
/// que abre `ExtensionSearcherPage` directo.
class _SearchVacio extends StatefulWidget {
  const _SearchVacio({required this.nsfwOnly});

  /// true en la Zona +18 del buscador — mismo criterio de qué extensiones
  /// entran que ya usa `SearchPageController.getRuntime()`.
  final bool nsfwOnly;

  @override
  State<_SearchVacio> createState() => _SearchVacioState();
}

class _SearchVacioState extends State<_SearchVacio> {
  // Fila con scroll horizontal y no `Wrap` — pedido explícito: con muchas
  // extensiones instaladas, `Wrap` las apilaba en varias filas cortas que
  // en una ventana angosta se veían amontonadas. Un scroll horizontal
  // escala igual de bien con 3 que con 30, sin cambiar de forma según el
  // ancho — mismo patrón que ya usa el resto de la app para listas de
  // extensiones.
  final _scroll = ScrollController();

  // ── Flechita en su propio espacio, no encima de los chips ──────────────
  //
  // `HorizontalScrollFade` (lo que se usaba antes) dibuja la flecha
  // FLOTANDO sobre el contenido, con un degradado detrás — pensado para
  // portadas, donde un chip/tarjeta parcialmente tapado no molesta. Acá el
  // texto de un chip quedaba literalmente atrás del círculo negro.
  // Reportado en vivo con captura: "la flechita no debe ponerse al frente,
  // debe estar en su espacio". Con `Expanded` + un botón aparte, la lista
  // nunca ocupa el lugar de la flecha ni al revés.
  bool _puedeAvanzar = false;
  // La de la izquierda — se me había pasado la primera vez: sin ella, una
  // vez que se scrolleaba para el costado no había forma de volver salvo
  // arrastrando a mano. Reportado en vivo: "te faltó poner flecha a la
  // izquierda".
  bool _puedeRetroceder = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_actualizarFlechas);
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarFlechas());
  }

  void _actualizarFlechas() {
    if (!mounted || !_scroll.hasClients) return;
    final puedeAvanzar =
        _scroll.position.pixels < _scroll.position.maxScrollExtent - 1;
    final puedeRetroceder =
        _scroll.position.pixels > _scroll.position.minScrollExtent + 1;
    if (puedeAvanzar != _puedeAvanzar || puedeRetroceder != _puedeRetroceder) {
      setState(() {
        _puedeAvanzar = puedeAvanzar;
        _puedeRetroceder = puedeRetroceder;
      });
    }
  }

  void _mover(double dir) {
    if (!_scroll.hasClients) return;
    final destino = (_scroll.offset + 220 * dir)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(destino,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _scroll.removeListener(_actualizarFlechas);
    _scroll.dispose();
    super.dispose();
  }

  /// Mismo filtro que `getRuntime()`: en la Zona +18, entera +18 o mixta
  /// (aportando su parte de adultos); fuera de la zona, ninguna entera +18
  /// (una mixta sí, con su catálogo normal). No se REUSA `getRuntime()`
  /// porque esa función además dispara el pool de búsqueda — acá no hay
  /// nada que buscar todavía, solo la lista de nombres para los botones.
  List<MapEntry<String, String>> _extensionesElegibles() {
    final entradas = ExtensionUtils.enabledRuntimes.entries
        .where((e) {
          final esNsfw = e.value.extension.nsfw;
          final esMixta = ExtensionUtils.esMixta(e.key);
          return widget.nsfwOnly ? (esNsfw || esMixta) : !esNsfw;
        })
        .map((e) => MapEntry(e.key, e.value.extension.name))
        .toList();
    entradas.sort((a, b) => a.value.compareTo(b.value));
    return entradas;
  }

  void _abrirExtension(BuildContext context, String package) {
    if (Platform.isAndroid) {
      Get.to(
          ExtensionSearcherPage(package: package, soloAdulto: widget.nsfwOnly));
      return;
    }
    router.push(Uri(
      path: '/search_extension',
      queryParameters: {
        'package': package,
        if (widget.nsfwOnly) 'soloAdulto': '1',
      },
    ).toString());
  }

  @override
  Widget build(BuildContext context) {
    final extensiones = _extensionesElegibles();
    // ── Arriba, pegado a la barra de búsqueda — no centrado ────────────────
    //
    // Antes todo esto vivía en un `Center`, así que con pocas extensiones
    // (los botones ocupan una o dos líneas) el bloque entero flotaba a
    // mitad de pantalla, lejos de la barra donde el usuario tiene puesta la
    // atención. Pedido explícito: "ponlos arriba, no en la mitad".
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extensiones.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'search.search-in-extension'.i18n,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Pedido explícito, con dibujo: un solo contenedor redondeado
            // con las extensiones espaciadas ADENTRO, y las flechas
            // sueltas a los costados de ESE contenedor — no cada chip
            // suelto sobre el fondo de la pantalla.
            // ── Las flechas se re-evalúan solas si el ancho cambia ────────
            //
            // Antes solo se recalculaban al scrollear (`_scroll.addListener`)
            // y una vez al montar. Angostar la ventana en PC, o rotar el
            // celular, cambia cuánto entra sin que nadie arrastre nada: el
            // `maxScrollExtent` pasa a ser mayor que cero, pero como ningún
            // scroll disparó el oyente, `_puedeAvanzar` se quedaba en su
            // valor viejo (`false`) y la fila quedaba cortada en seco, sin
            // ninguna flecha que avisara que hay más para el costado.
            // Reportado en vivo con captura, achicando la ventana.
            //
            // `ScrollMetricsNotification` es justo la señal de Flutter para
            // "las métricas del scroll cambiaron sin que nadie scrolleara"
            // —se dispara sola con cualquier resize del viewport—, así que
            // no hace falta inventar un LayoutBuilder propio para esto.
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _actualizarFlechas());
                return false;
              },
              // ── Alto real encontrado, no el que "se veía bien" a ojo ──
              //
              // Esta fila fuerza un alto FIJO a cada chip de adentro (así
              // funciona un ListView: el eje cruzado siempre les llega
              // ajustado al alto del viewport, sea cual sea su contenido).
              // Con 44 acá, después de restar el relleno vertical del ítem
              // (6+6) y el propio de cada _ChipExtension (9+9), al ícono y
              // al texto de adentro les quedaban apenas 14px de alto —justo
              // lo que mide el ícono, CERO de sobra para el propio alto de
              // línea del texto (fontSize 12.5 con su interlineado ronda
              // los 15px). El texto terminaba tocando/pisando el borde
              // redondeado de su propio chip -reportado en vivo con
              // captura: "el contorno de cada botón corta el nombre".
              // Con 54 queda holgura de sobra para cualquier fuente.
              child: SizedBox(
                height: 54,
                child: Row(
                  children: [
                    // Con su propio lugar reservado — solo aparece cuando de
                    // verdad hay para dónde volver, así que no le quita ancho
                    // a los chips si ya se está en el principio.
                    if (_puedeRetroceder) ...[
                      _FlechaDeChips(
                        onTap: () => _mover(-1),
                        izquierda: true,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: HomeTheme.cardSurface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: HomeTheme.border),
                        ),
                        // ── Se difumina, no se corta en seco ────────────
                        //
                        // Mirando la mitad de la fila (que es lo normal:
                        // ni al principio ni al final), el chip de cada
                        // punta queda A LA MITAD por diseño — es lo que
                        // dice "hay más para este lado", igual que
                        // cualquier fila horizontal de por acá. El
                        // problema reportado en vivo con captura no era
                        // ESO: era que ese chip a la mitad se veía cortado
                        // en seco, con su propio texto y su propia
                        // cápsula redondeada terminando de golpe contra
                        // el borde recto del contenedor — dos formas
                        // redondas distintas (la del chip y la de este
                        // contenedor) chocando en un límite duro.
                        //
                        // El `ShaderMask` (mismo mecanismo que ya usa
                        // `_HeroCover` en `home_hero_banner.dart` para
                        // desvanecer una portada) difumina esos bordes a
                        // transparente: el chip de la punta se apaga de a
                        // poco en vez de cortarse de golpe.
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.08, 0.92, 1.0],
                          ).createShader(rect),
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            controller: _scroll,
                            // Además del difuminado: espacio de sobra para
                            // que, cuando SÍ se está al principio o al
                            // final de la fila (ahí no hay nada que
                            // difuminar, el primer/último chip está
                            // completo), no quede pegado contra la curva
                            // de la cápsula —~21px de radio, con menos
                            // relleno el fondo redondo terminaba antes que
                            // el texto.
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: extensiones.length,
                            itemBuilder: (context, i) {
                              final ext = extensiones[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 4),
                                child: _ChipExtension(
                                  nombre: ext.value,
                                  onTap: () =>
                                      _abrirExtension(context, ext.key),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    // Ídem, del otro lado: solo cuando de verdad hay más para
                    // el costado.
                    if (_puedeAvanzar) ...[
                      const SizedBox(width: 8),
                      _FlechaDeChips(onTap: () => _mover(1)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  Icon(Icons.search_rounded,
                      size: 36, color: HomeTheme.textMuted),
                  const SizedBox(height: 10),
                  Text(
                    'search.empty-hint'.i18n,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: HomeTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un botón chico, redondeado — "buscar en <nombre>".
class _ChipExtension extends StatelessWidget {
  const _ChipExtension({required this.nombre, required this.onTap});

  final String nombre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: HomeTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: 14, color: HomeTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                nombre,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: HomeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El botón de "hay más para el costado" de la fila de chips — con sus
/// propios colores del tema (no el círculo negro fijo que traía
/// `HorizontalScrollFade` por defecto, que en modo claro se veía como una
/// mancha oscura sin ninguna relación con el resto de la pantalla).
class _FlechaDeChips extends StatelessWidget {
  const _FlechaDeChips({required this.onTap, this.izquierda = false});

  final VoidCallback onTap;
  final bool izquierda;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: HomeTheme.cardSurface,
            border: Border.all(color: HomeTheme.border),
          ),
          child: Icon(
            izquierda
                ? Icons.chevron_left_rounded
                : Icons.chevron_right_rounded,
            size: 18,
            color: HomeTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}
