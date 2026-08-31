import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/hidden_cards.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/franja_de_zona.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/tv/columna_de_acciones.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/tv/pantalla_tv.dart';
import 'package:prismhub/views/widgets/tv/teclado_tv.dart';

// "Ver todo" destination for Home's Continuar section — one place with
// every history/favorite item, filterable by tab, searchable by title, and
// deletable one-by-one (visible trash icon) or all at once (no right-click
// needed for either). Mismo estilo visual que Home (HomeTheme + HomeMediaCard)
// para que se sienta parte de la misma app, no una pantalla aparte.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.initialTab = 0,
    this.zone = false,
    this.soloFavoritos = false,
  });
  final int initialTab;
  // true: instancia de la Zona +18 (HomePageController.zoneTag, tema rojo).
  // Es la misma pantalla, apuntando a la OTRA instancia del controller.
  final bool zone;

  /// Abre como FAVORITOS y no como Historial.
  ///
  /// ── Por qué no son dos pantallas ────────────────────────────────────────
  ///
  /// Porque hacen exactamente lo mismo: una grilla de tarjetas, con buscador,
  /// orden, borrado y menú de tres puntos. Duplicar el archivo garantiza que en
  /// dos semanas una tenga un arreglo que la otra no.
  ///
  /// Lo que sí eran dos cosas y estaban mezcladas es lo que ve el usuario: las
  /// cinco pestañas en una sola tira, con el título «Historial» arriba. Entrar
  /// a Favoritos y que la pantalla dijera «Historial» no tiene defensa.
  ///
  /// Con esta bandera cada entrada abre SU zona: su título, y solo las
  /// pestañas que le corresponden. Vale igual para la zona normal y la +18.
  final bool soloFavoritos;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HomePageController _c = Get.find<HomePageController>(
    tag: widget.zone ? HomePageController.zoneTag : null,
  );
  late final Color _accent =
      widget.zone ? HomeTheme.accentRed : HomeTheme.accentPink;

  /// Los índices de [_tabs] que esta zona muestra.
  ///
  /// Historial: todo, vídeo y lectura. Favoritos: sus dos. Se trabaja con el
  /// índice GLOBAL y no con la posición dentro de la tira, para que
  /// `_onFavoritesTab` y todo lo que ya mira `_tabIndex` siga valiendo igual.
  /// El índice de la pestaña «Todo» de Favoritos. Ver [_tabs].
  static const _favTodo = 5;

  // En Android TV, sin pestaña de Lectura -mismo criterio que Inicio/Buscar/
  // Biblioteca: nada de manga/novela en TV, en ningún lado. El índice 0/
  // _favTodo ("Todo") tampoco puede colar lectura mezclada — ver
  // _sinLecturaEnTv más abajo, que filtra eso independientemente de la
  // pestaña.
  List<int> get _pestanas {
    if (PlatformTv.esTelevisionSync) {
      return widget.soloFavoritos ? const [_favTodo, 3] : const [0, 1];
    }
    return widget.soloFavoritos ? const [_favTodo, 3, 4] : const [0, 1, 2];
  }

  /// Saca la lectura de una lista en Android TV — se aplica en TODAS las
  /// pestañas, incluida "Todo", para que no quede colando ahí aunque la
  /// pestaña de Lectura ya no exista.
  List<T> _sinLecturaEnTv<T>(List<T> items, ExtensionType Function(T) tipoDe) {
    if (!PlatformTv.esTelevisionSync) return items;
    return items
        .where((e) =>
            !ExtensionUtils.readingTypes.contains(tipoDe(e)) ||
            ExtensionUtils.videoTypes.contains(tipoDe(e)))
        .toList();
  }

  late int _tabIndex = _pestanas.contains(widget.initialTab)
      ? widget.initialTab
      : _pestanas.first;
  final _searchController = TextEditingController();
  String _query = '';

  // "Lectura" agrupa manga+novela — de cara al usuario es una sola
  // categoría (ambos son texto para leer).
  // Favoritos se parte en dos por el mismo motivo que se partió "Continuar"
  // en el Home: vídeo y lectura no comparten forma de tarjeta, y mezclados
  // uno de los dos siempre queda mal.
  static const _tabs = [
    'search.all',
    'extension-type.video',
    'extension-type.reading',
    'history.favorites-video',
    'history.favorites-reading',
    // La quinta es «Todo» de Favoritos. Va al final y no al principio para no
    // correr los índices de las otras cuatro, que están escritos en las
    // pantallas que abren esta —Biblioteca, la Zona +18, el router— y en
    // `_onFavoritesTab`.
    'search.all',
  ];

  @override
  void initState() {
    super.initState();
    // ── Se relee la base al abrir ──────────────────────────────────────────
    //
    // No estaba, y por eso «marco un favorito, entro a Favoritos y no hay
    // nada». Las listas del controlador se llenan cuando el controlador
    // arranca, y de ahí en más solo cambian si algo las vuelve a pedir. Marcar
    // un favorito desde la ficha escribe en la base pero no le avisa a esta
    // pantalla, así que se abría con la lista de hace un rato — vacía si es la
    // primera vez.
    //
    // Es una lectura local, no red: cuesta nada y garantiza que lo que se ve
    // es lo que hay. Sin await ni bloqueo: mientras llega se muestran los
    // bloques, y cuando llega se dibuja sola.
    unawaited(_c.onRefresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Los tipos salen de ExtensionUtils, no de una lista propia ──────────
  //
  // Acá había dos conjuntos escritos a mano: vídeo era solo `bangumi` y lectura
  // solo `manga` y `fikushon`. Pero el enum tiene además `mixed` y
  // `mixedReading` —las extensiones que sirven para las dos cosas, como
  // ManhwaWeb— y esos dos no caían en NINGUNA de las dos pestañas.
  //
  // O sea que un favorito o un capítulo de una extensión mixta era invisible:
  // no salía en «Vídeo» ni en «Lectura», y en «Todo» sí. Reportado en vivo:
  // «voy a lectura y no se ve nada y en el Inicio tengo favoritos de lectura».
  //
  // ExtensionUtils ya tiene los conjuntos buenos y los usa el resto de la app.
  // Con una copia local estaban condenados a separarse, y se separaron.
  static Set<ExtensionType> get _video => ExtensionUtils.videoTypes;
  static Set<ExtensionType> get _lectura => ExtensionUtils.readingTypes;

  Set<ExtensionType>? get _typeFilter {
    switch (_tabIndex) {
      case 1:
      case 3:
        return _video;
      case 2:
      case 4:
        return _lectura;
      // 0 (Todo del historial) y _favTodo (Todo de favoritos): sin filtro.
      default:
        return null;
    }
  }

  bool get _onFavoritesTab => _tabIndex >= 3;

  /// La pestaña actual muestra vídeo (tarjeta ancha) o lectura (vertical).
  /// `null` en "Todo", donde conviven los dos.
  bool? get _tabEsVideo {
    if (_tabIndex == 1 || _tabIndex == 3) return true;
    if (_tabIndex == 2 || _tabIndex == 4) return false;
    // En «Todo» conviven los dos, así que manda la vertical: es la que sirve
    // para ambos sin recortar.
    return null;
  }

  // ── Filtros de estado y orden ─────────────────────────────────────────────
  _EstadoFiltro _estado = _EstadoFiltro.todos;
  _Orden _orden = _Orden.recientes;
  _Rango _rango = _Rango.siempre;

  /// Desde qué momento entra algo en la lista. `null` = sin corte.
  DateTime? get _desde {
    final ahora = DateTime.now();
    switch (_rango) {
      case _Rango.siempre:
        return null;
      case _Rango.dia:
        return ahora.subtract(const Duration(hours: 24));
      case _Rango.semana:
        return ahora.subtract(const Duration(days: 7));
      case _Rango.mes:
        return ahora.subtract(const Duration(days: 30));
      case _Rango.ano:
        return ahora.subtract(const Duration(days: 365));
    }
  }

  List<History> _aplicarEstado(List<History> list) {
    switch (_estado) {
      case _EstadoFiltro.todos:
        return list;
      case _EstadoFiltro.pendiente:
        return list.where((h) => h.watchState == WatchState.pending).toList();
      case _EstadoFiltro.completado:
        return list.where((h) => h.watchState == WatchState.completed).toList();
      case _EstadoFiltro.finalizado:
        // Eje distinto de los dos anteriores: acá se pregunta por la OBRA, no
        // por el avance del usuario. Ver WatchState en history.dart.
        return list.where((h) => h.seriesFinished).toList();
    }
  }

  List<T> _aplicarOrden<T>(
    List<T> list,
    String Function(T) tituloDe,
    DateTime Function(T) fechaDe,
  ) {
    final copia = [...list];
    switch (_orden) {
      case _Orden.recientes:
        copia.sort((a, b) => fechaDe(b).compareTo(fechaDe(a)));
      case _Orden.antiguos:
        copia.sort((a, b) => fechaDe(a).compareTo(fechaDe(b)));
      case _Orden.az:
        copia.sort((a, b) =>
            tituloDe(a).toLowerCase().compareTo(tituloDe(b).toLowerCase()));
      case _Orden.za:
        copia.sort((a, b) =>
            tituloDe(b).toLowerCase().compareTo(tituloDe(a).toLowerCase()));
    }
    return copia;
  }

  List<History> _filteredHistory() {
    final type = _typeFilter;
    // allHistory y no resents: el Historial muestra TODO, incluido lo
    // completado. resents es la lista de "Continuar", que sí lo excluye.
    final base = _c.allHistory.where((h) {
      if (type != null && !type.contains(h.type)) return false;
      if (!SearchText.matchesQuery(h.title, _query)) return false;
      final desde = _desde;
      if (desde != null && h.date.isBefore(desde)) return false;
      return true;
    }).toList();
    return _sinLecturaEnTv(
      _aplicarOrden(
        _aplicarEstado(base),
        (h) => h.title,
        (h) => h.date,
      ),
      (h) => h.type,
    );
  }

  List<Favorite> _filteredFavorites() {
    final type = _typeFilter;
    final base = _c.favorites.where((f) {
      if (type != null && !type.contains(f.type)) return false;
      if (!SearchText.matchesQuery(f.title, _query)) return false;
      return true;
    }).toList();
    // Los favoritos no llevan estado de avance (eso vive en el historial), así
    // que el filtro de estado no aplica — solo el orden.
    return _sinLecturaEnTv(
      _aplicarOrden(base, (f) => f.title, (f) => f.date),
      (f) => f.type,
    );
  }

  /// Alterna entre "en curso" y "visto". No toca la fecha: mover un título
  /// entre estados no es haberlo visto de nuevo, y actualizarla lo mandaría al
  /// principio del Historial sin motivo.
  Future<void> _cambiarEstado(History h) async {
    h.watchState = h.watchState == WatchState.completed
        ? WatchState.pending
        : WatchState.completed;
    h.newEpisodeLabel = null;
    await DatabaseService.putHistoryRaw(h);
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  // cover/headers: la portada que la tarjeta ya está mostrando, para que la
  // ficha abra con imagen. Ver PortadaAdelantada.
  void _openDetail(String url, String package,
      {String? cover, Map<String, String>? headers}) {
    ExtensionUtils.openExtensionDetail(
      context,
      package: package,
      url: url,
      cover: cover,
      coverHeaders: headers,
    );
  }

  // Si hay un DetailPageController vivo para este título (la página de
  // detalle sigue abierta en otra pestaña/ventana), le avisa que se olvide
  // la decisión de +18 que tenía guardada — sin esto, borrar acá no
  // afectaba esa instancia ya cargada, y volver a favoritear/mirar desde
  // ahí mismo NO volvía a preguntar (arrastraba la respuesta vieja).
  void _forgetNsfwDecisionIfOpen(String package, String url) {
    final tag = '$package|$url';
    if (Get.isRegistered<DetailPageController>(tag: tag)) {
      Get.find<DetailPageController>(tag: tag).forgetNsfwDecision();
    }
  }

  Future<void> _deleteHistory(History h) async {
    await DatabaseService.deleteHistoryByPackageAndUrl(h.package, h.url);
    _forgetNsfwDecisionIfOpen(h.package, h.url);
    await _c.refreshHistory();
    if (mounted) setState(() {});
  }

  /// ¿Este título ya está en favoritos?
  ///
  /// Se mira en la lista que el controlador YA tiene en memoria y no con una
  /// consulta a la base: esto se llama al dibujar cada tarjeta, y una consulta
  /// por tarjeta en una grilla llena es una tormenta de lecturas por cada
  /// cuadro. La lista se refresca sola al cambiar un favorito.
  bool _esFavorito(String package, String url) =>
      _c.favorites.any((f) => f.package == package && f.url == url);

  Future<void> _alternarFavorito({
    required String package,
    required String url,
    required String titulo,
    String? portada,
  }) async {
    try {
      await DatabaseService.toggleFavorite(
        package: package,
        url: url,
        name: titulo,
        cover: portada,
        isNsfw: widget.zone,
      );
    } catch (e) {
      // toggleFavorite exige que la extensión esté instalada: saca de ahí el
      // paquete y el tipo. Con una desinstalada, en el historial todavía queda
      // el título pero no hay de dónde sacar esos datos.
      if (!mounted) return;
      showPlatformSnackbar(
        context: context,
        content: friendlyError(e),
        severity: fluent.InfoBarSeverity.error,
      );
      return;
    }
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  Future<void> _deleteFavorite(Favorite f) async {
    await DatabaseService.deleteFavorite(f.package, f.url);
    _forgetNsfwDecisionIfOpen(f.package, f.url);
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HomeTheme.cardSurface,
        content: Text(
          'home.clear-history-confirm'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.i18n),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'common.delete-all'.i18n,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_onFavoritesTab) {
      for (final f in _c.favorites) {
        _forgetNsfwDecisionIfOpen(f.package, f.url);
      }
      // Solo la zona en la que estamos parados.
      //
      // Antes se borraba TODO sin mirar: desde el Historial +18, "borrar todo"
      // se llevaba puesto también lo del inicio normal, y al revés. La pantalla
      // ya sabía en qué zona estaba (widget.zone), pero el borrado no.
      await DatabaseService.deleteFavoritesByType(null, soloNsfw: widget.zone);
    } else {
      for (final h in _c.resents) {
        _forgetNsfwDecisionIfOpen(h.package, h.url);
      }
      final types = _typeFilter;
      if (types == null) {
        // Mismo motivo que arriba: solo la zona en la que estamos.
        await DatabaseService.deleteHistoryByType(null, soloNsfw: widget.zone);
      } else {
        // La pestaña "Lectura" agrupa manga+novela — hay que borrar cada
        // tipo por separado, deleteHistoryByType solo acepta uno a la vez.
        for (final t in types) {
          await DatabaseService.deleteHistoryByType(t, soloNsfw: widget.zone);
        }
      }
    }
    await _c.onRefresh();
    if (mounted) setState(() {});
  }

  Widget _buildGrid() {
    final favorites = _onFavoritesTab ? _filteredFavorites() : null;
    final history = _onFavoritesTab ? null : _filteredHistory();
    final itemCount = favorites?.length ?? history!.length;

    final isAndroidLandscape = Platform.isAndroid &&
        MediaQuery.orientationOf(context) == Orientation.landscape;

    // Tarjeta ancha 16:9 solo cuando la pestaña muestra SOLO vídeo y hay ancho
    // para ella. En "Todo" conviven los dos tipos y la grilla reserva un único
    // alto y una única forma, así que ahí manda la vertical: es la que sirve
    // para ambos sin recortar. Es el mismo motivo por el que en el Home hubo
    // que partir "Continuar" en dos filas.
    // También en Android: es un marco 16:9 para una captura 16:9, y con la
    // vertical la miniatura entraba recortada. Ver HomeMediaCard.anchoAncha.
    final usarAncha = _tabEsVideo == true;

    final cardWidth = usarAncha
        ? HomeMediaCard.anchoAncha
        : isAndroidLandscape
            ? HomeMediaCard.androidLandscapeWidth
            : Platform.isAndroid
                ? HomeMediaCard.androidWidth
                : HomeMediaCard.desktopWidth;
    // La ancha ya trae su alto TOTAL (imagen + textos); la vertical solo el de
    // la portada, así que a esa hay que sumarle lo que va debajo.
    final cardExtent = usarAncha
        ? HomeMediaCard.altoTotalAncha + 18
        : (isAndroidLandscape
                ? HomeMediaCard.androidLandscapeHeight
                : Platform.isAndroid
                    ? HomeMediaCard.androidHeight
                    : HomeMediaCard.desktopHeight) +
            70;

    // ── Todavía no se leyó la base: bloques, no un aviso ──────────────
    //
    // Las listas arrancan vacías, y vacío por «todavía no pregunté» se ve
    // igual que vacío por «no hay nada». Sin distinguirlos, acá salía «no
    // tenés nada todavía» en el parpadeo previo a la primera lectura, con la
    // biblioteca llena. Los bloques además dejan la grilla ya con su forma, así
    // que al llegar las portadas no salta nada — igual que en el Inicio.
    if (itemCount == 0 && !_c.primeraCargaLista.value) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: EsqueletoDeGrilla(
            columnas: math.max(
              1,
              ((MediaQuery.sizeOf(context).width - 32 + 16) / (cardWidth + 16))
                  .floor(),
            ),
            proporcion: cardWidth / cardExtent,
          ),
        ),
      );
    }

    if (itemCount == 0) {
      final nothingAtAll = _c.resents.isEmpty && _c.favorites.isEmpty;
      return SliverPadding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        sliver: SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              nothingAtAll
                  ? (widget.zone
                      ? 'nsfw18.no-record'.i18n
                      : 'home.no-record'.i18n)
                  : 'common.no-result'.i18n,
              style: TextStyle(color: HomeTheme.textMuted),
            ),
          ),
        ),
      );
    }

    // ── Las tarjetas LLENAN su celda ──────────────────────────────────
    //
    // Antes la grilla repartía el ancho entre las columnas que entraban y la
    // tarjeta se quedaba en su ancho fijo dentro de la celda: en un teléfono,
    // 150 dentro de 164. Con un Align centrándola, sobraba aire a los dos
    // costados de cada una y las portadas se veían chicas sin motivo, más
    // chicas que las del mismo tamaño en el Inicio, que van en fila y ahí el
    // ancho fijo sí es lo correcto.
    //
    // Ahora se cuentan las columnas primero, se reparte el ancho que hay y ese
    // es el que se le pasa a la tarjeta. El alto sale de la misma proporción,
    // así que la portada no se deforma.
    return SliverLayoutBuilder(
      builder: (context, cons) {
        const margen = 16.0;
        const entre = 16.0;
        final disponible = cons.crossAxisExtent - margen * 2;
        final columnas =
            math.max(1, ((disponible + entre) / (cardWidth + entre)).floor());
        final ancho = (disponible - entre * (columnas - 1)) / columnas;
        // La proporción de la tarjeta elegida, aplicada al ancho real.
        final alto = ancho * (cardExtent / cardWidth);

        return SliverPadding(
          padding: const EdgeInsets.all(margen),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columnas,
              mainAxisExtent: alto,
              mainAxisSpacing: 20,
              crossAxisSpacing: entre,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _onFavoritesTab
                  ? _buildFavoriteCard(favorites![index],
                      ancha: usarAncha, ancho: ancho)
                  : _buildHistoryCard(history![index],
                      ancha: usarAncha, ancho: ancho),
              childCount: itemCount,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavoriteCard(Favorite f, {bool ancha = false, double? ancho}) {
    // Obx: igual que en library_page.dart — sin esto, togglear "ocultar" no
    // refrescaba la tarjeta acá (el RxSet de HiddenCards cambia, pero nada
    // en esta pantalla estaba suscripto a él) hasta reconstruir toda la
    // página (cambiar de pestaña y volver).
    return Obx(() => HomeMediaCard(
          horizontal: ancha,
          // Solo la vertical: la apaisada ya trae su propio tamaño.
          ancho: ancha ? null : ancho,
          key: ValueKey('fav-${f.package}-${f.url}'),
          title: f.title,
          subtitle: 'home.favorite'.i18n,
          type: f.type,
          cover: f.cover,
          headers: _c.headersForPackage(f.package),
          onTap: () => _openDetail(f.url, f.package,
              cover: f.cover, headers: _c.headersForPackage(f.package)),
          onDelete: () => _deleteFavorite(f),
          onVerDetalle: () => _openDetail(f.url, f.package,
              cover: f.cover, headers: _c.headersForPackage(f.package)),
          hidden: HiddenCards.isHidden(f.package, f.url),
          onToggleHide: () => HiddenCards.toggle(f.package, f.url),
          accent: _accent,
        ));
  }

  Widget _buildHistoryCard(History h, {bool ancha = false, double? ancho}) {
    // La portada de vídeo puede ser una captura local O el póster de red (ver
    // PortadaHistorial). Antes acá se asumía siempre archivo local, así que un
    // ítem con póster de red hacía File("https://...") y la tarjeta quedaba
    // sin imagen — se notaba sobre todo en la Zona +18, y parecía que el botón
    // de mostrar/ocultar imagen se rompía.
    final portada = PortadaHistorial.de(h);
    // Obx: ver comentario en _buildFavoriteCard.
    return Obx(() => HomeMediaCard(
          horizontal: ancha,
          // Solo la vertical: la apaisada ya trae su propio tamaño.
          ancho: ancha ? null : ancho,
          key: ValueKey('hist-${h.package}-${h.url}'),
          title: h.title,
          subtitle: FlutterI18n.translate(
            context,
            h.type == ExtensionType.bangumi
                ? 'home.watched-episode'
                : 'home.watched-chapter',
            translationParams: {
              'ep': ExtensionUtils.episodeNumberLabel(
                  h.episodeTitle, h.episodeId),
            },
          ),
          type: h.type,
          cover: portada.url,
          coverFile: portada.archivo,
          headers:
              portada.necesitaHeaders ? _c.headersForPackage(h.package) : null,
          // Solo si la portada es de red: el historial de vídeo guarda una
          // captura en disco, y eso no se puede pedir por URL.
          onTap: () => _openDetail(h.url, h.package,
              cover: portada.archivo == null ? portada.url : null,
              headers: portada.necesitaHeaders
                  ? _c.headersForPackage(h.package)
                  : null),
          onDelete: () => _deleteHistory(h),
          // Mover entre "en curso" y "visto" sin abrir el título. Hasta ahora
          // la única forma de devolver algo a Continuar era abrirlo y leer un
          // capítulo, y la única de sacarlo era quitarlo desde el Home.
          extraActionLabel: h.watchState == WatchState.completed
              ? 'history.back-to-continue'.i18n
              : 'history.mark-seen'.i18n,
          extraActionIcon: h.watchState == WatchState.completed
              ? Icons.replay_rounded
              : Icons.check_rounded,
          onExtraAction: () => _cambiarEstado(h),
          onVerDetalle: () => _openDetail(h.url, h.package,
              cover: portada.archivo == null ? portada.url : null,
              headers: portada.necesitaHeaders
                  ? _c.headersForPackage(h.package)
                  : null),
          // Marcar favorito sin abrir la ficha. Desde el Historial es donde
          // más falta hace: uno acaba de leer un capítulo, vuelve, y hasta
          // ahora tenía que entrar al título solo para tocar la estrella.
          esFavorito: _esFavorito(h.package, h.url),
          onAlternarFavorito: () => _alternarFavorito(
            package: h.package,
            url: h.url,
            titulo: h.title,
            portada: portada.archivo == null ? portada.url : null,
          ),
          hidden: HiddenCards.isHidden(h.package, h.url),
          onToggleHide: () => HiddenCards.toggle(h.package, h.url),
          accent: _accent,
        ));
  }

  // Un solo chip para pestañas, estado y orden — antes el de pestañas estaba
  // escrito inline y copiarlo dos veces más era garantizar que se separaran.
  Widget _chip(String texto, bool seleccionado, VoidCallback onTap,
      {double fontSize = 13}) {
    // En TV el chip se envuelve para que el mando pueda enfocarlo: con
    // GestureDetector a secas no hay dónde pararse y las pestañas quedan
    // visibles pero intocables.
    if (PlatformTv.esTelevisionSync) {
      return FocusableCard(
        borderRadius: 999,
        accent: _accent,
        onTap: onTap,
        child: _pastillaChip(texto, seleccionado, fontSize),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: _pastillaChip(texto, seleccionado, fontSize),
      ),
    );
  }

  Widget _pastillaChip(String texto, bool seleccionado, double fontSize) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(
          horizontal: fontSize > 12 ? 16 : 12, vertical: fontSize > 12 ? 9 : 6),
      decoration: BoxDecoration(
        color: seleccionado
            ? _accent.withValues(alpha: 0.18)
            : HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: seleccionado ? _accent : HomeTheme.border,
        ),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: seleccionado ? _accent : HomeTheme.textPrimary,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// El nombre de una pestaña.
  ///
  /// En Favoritos se acortan: la zona ya se llama «Favoritos», así que decir
  /// «Favoritos vídeo» y «Favoritos lectura» repite la palabra en cada
  /// pastilla. Con «Vídeo» y «Lectura» alcanza y entran las dos holgadas.
  String _etiqueta(int global) {
    if (!widget.soloFavoritos) return _tabs[global].i18n;
    if (global == _favTodo) return 'search.all'.i18n;
    return global == 3
        ? 'extension-type.video'.i18n
        : 'extension-type.reading'.i18n;
  }

  Widget _buildTabs() {
    // ── En el teléfono, una sola fila que se desliza ─────────────────────
    //
    // Cinco pastillas no entran a lo ancho, así que el Wrap las partía en dos
    // renglones. Deslizando entran las cinco en uno solo, y el renglón que se
    // ahorra es una fila de portadas que se ve.
    if (Platform.isAndroid) {
      return SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _pestanas.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final global = _pestanas[i];
            return Center(
              child: _chip(
                _etiqueta(global),
                global == _tabIndex,
                () => setState(() => _tabIndex = global),
              ),
            );
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        // Centrados en celular: las pestañas ocupan dos líneas en pantalla
        // angosta y alineadas a la izquierda la segunda quedaba colgando sola
        // en un costado. En escritorio entran en una línea y ahí el alineado a
        // la izquierda es lo correcto.
        alignment:
            Platform.isAndroid ? WrapAlignment.center : WrapAlignment.start,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final global in _pestanas)
            _chip(
              _etiqueta(global),
              global == _tabIndex,
              () => setState(() => _tabIndex = global),
            ),
        ],
      ),
    );
  }

  // Estado y orden en una sola fila. El estado se oculta en Favoritos: ahí no
  // hay avance del usuario que filtrar (eso vive en el historial), y dejar
  // chips que no hacen nada confunde más que ayudar.
  Widget _buildFiltrosYOrden() {
    final etiquetasEstado = {
      _EstadoFiltro.todos: 'history.state-all'.i18n,
      _EstadoFiltro.pendiente: 'history.state-pending'.i18n,
      _EstadoFiltro.completado: 'history.state-completed'.i18n,
      _EstadoFiltro.finalizado: 'history.state-finished'.i18n,
    };
    final etiquetasOrden = {
      _Orden.recientes: 'history.sort-recent'.i18n,
      _Orden.antiguos: 'history.sort-oldest'.i18n,
      _Orden.az: 'history.sort-az'.i18n,
      _Orden.za: 'history.sort-za'.i18n,
    };
    final etiquetasRango = {
      _Rango.siempre: 'history.range-all'.i18n,
      _Rango.dia: 'history.range-day'.i18n,
      _Rango.semana: 'history.range-week'.i18n,
      _Rango.mes: 'history.range-month'.i18n,
      _Rango.ano: 'history.range-year'.i18n,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Wrap(
        alignment:
            Platform.isAndroid ? WrapAlignment.center : WrapAlignment.start,
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!_onFavoritesTab)
            for (final e in _EstadoFiltro.values)
              _chip(
                etiquetasEstado[e]!,
                _estado == e,
                () => setState(() => _estado = e),
                fontSize: 12,
              ),
          if (!_onFavoritesTab) const SizedBox(width: 12),
          // ── «Cuándo», que en escritorio faltaba ──────────────────────────
          //
          // El filtro se agregó pensando en la hoja del teléfono y acá quedó
          // sin poner: en el mismo Historial, el teléfono podía acotar a las
          // últimas 24 horas y el escritorio no. Lo que es lógica va en las dos
          // plataformas; lo que cambia es cómo se muestra, y acá hay ancho para
          // tenerlo a la vista en vez de detrás de un botón.
          //
          // En Favoritos no, mismo motivo que en la hoja: ahí la fecha es la de
          // guardado y filtrar por ella no contesta nada.
          if (!_onFavoritesTab) ...[
            Icon(Icons.schedule_rounded, size: 16, color: HomeTheme.textMuted),
            for (final r in _Rango.values)
              _chip(
                etiquetasRango[r]!,
                _rango == r,
                () => setState(() => _rango = r),
                fontSize: 12,
              ),
            const SizedBox(width: 12),
          ],
          Icon(Icons.sort, size: 16, color: HomeTheme.textMuted),
          for (final o in _Orden.values)
            _chip(
              etiquetasOrden[o]!,
              _orden == o,
              () => setState(() => _orden = o),
              fontSize: 12,
            ),
        ],
      ),
    );
  }

  /// ¿Hay algún filtro puesto? Para el puntito del botón.
  ///
  /// El orden por defecto NO cuenta como filtro: es el que tiene siempre, y un
  /// puntito encendido desde el arranque no avisa de nada.
  bool get _hayFiltroPuesto =>
      _estado != _EstadoFiltro.todos ||
      _orden != _Orden.recientes ||
      _rango != _Rango.siempre;

  /// Estado y orden, en una hoja.
  ///
  /// La misma hoja que ya usan Extensiones, el repositorio y Buscar: un botón
  /// en la franja de arriba que la abre. Antes eran ocho pastillas en dos
  /// renglones fijos encima de la primera tarjeta.
  void _abrirFiltros() {
    final etiquetasEstado = {
      _EstadoFiltro.todos: 'history.state-all'.i18n,
      _EstadoFiltro.pendiente: 'history.state-pending'.i18n,
      _EstadoFiltro.completado: 'history.state-completed'.i18n,
      _EstadoFiltro.finalizado: 'history.state-finished'.i18n,
    };
    final etiquetasOrden = {
      _Orden.recientes: 'history.sort-recent'.i18n,
      _Orden.antiguos: 'history.sort-oldest'.i18n,
      _Orden.az: 'history.sort-az'.i18n,
      _Orden.za: 'history.sort-za'.i18n,
    };
    final etiquetasRango = {
      _Rango.siempre: 'history.range-all'.i18n,
      _Rango.dia: 'history.range-day'.i18n,
      _Rango.semana: 'history.range-week'.i18n,
      _Rango.mes: 'history.range-month'.i18n,
      _Rango.ano: 'history.range-year'.i18n,
    };

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: HomeTheme.cardSurface,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (hojaContext) {
        // StatefulBuilder para que al tocar una pastilla se repinte la hoja: el
        // setState de la página no llega acá, que es otro árbol. Y el de la
        // página se llama igual, para que la lista de atrás se filtre en el
        // momento y se vea el efecto sin cerrar.
        return StatefulBuilder(
          builder: (hojaContext, setHoja) {
            Widget titulo(String texto) => Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
                  child: Text(
                    texto,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: HomeTheme.textPrimary,
                    ),
                  ),
                );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // El estado no se ofrece en Favoritos: ahí no hay avance del
                  // usuario que filtrar —eso vive en el historial— y dejar
                  // pastillas que no hacen nada confunde más que ayudar.
                  if (!_onFavoritesTab) ...[
                    titulo('history.state'.i18n),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in _EstadoFiltro.values)
                          _chip(
                            etiquetasEstado[e]!,
                            _estado == e,
                            () {
                              setState(() => _estado = e);
                              setHoja(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                  // Cuándo: solo en el Historial. En Favoritos la fecha es
                  // la de guardado, y filtrar por ella no contesta ninguna
                  // pregunta que uno se haga — ahí se guarda justamente para
                  // que no importe cuándo fue.
                  if (!_onFavoritesTab) ...[
                    titulo('history.when'.i18n),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in _Rango.values)
                          _chip(
                            etiquetasRango[r]!,
                            _rango == r,
                            () {
                              setState(() => _rango = r);
                              setHoja(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                  titulo('history.sort'.i18n),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in _Orden.values)
                        _chip(
                          etiquetasOrden[o]!,
                          _orden == o,
                          () {
                            setState(() => _orden = o);
                            setHoja(() {});
                          },
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchBox() {
    // Desktop corre sobre fluent_ui, no Material — un TextField de Material
    // no encuentra el ancestro que necesita ahí (crashea con "No Material
    // widget found"). fluent.TextBox es el equivalente correcto para ese
    // árbol; Android sí tiene Material disponible (Scaffold en la raíz).
    if (Platform.isAndroid) {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HomeTheme.border),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: HomeTheme.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: HomeTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'common.search'.i18n,
                  hintStyle: TextStyle(color: HomeTheme.textMuted),
                  // Solo visible con texto — antes no había forma de
                  // limpiar la búsqueda salvo borrar a mano.
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close,
                              size: 18, color: HomeTheme.textMuted),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: fluent.TextBox(
        controller: _searchController,
        placeholder: 'common.search'.i18n,
        prefix: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(fluent.FluentIcons.search, size: 16),
        ),
        // Solo visible con texto — antes no había forma de limpiar la
        // búsqueda en desktop sin borrar a mano.
        suffix: _query.isEmpty
            ? null
            : fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.chrome_close, size: 9.0),
                onPressed: () => setState(() {
                  _searchController.clear();
                  _query = '';
                }),
              ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildSearchAndActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(child: _buildSearchBox()),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _confirmClearAll,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: HomeTheme.cardSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HomeTheme.border),
                ),
                child: Text(
                  'common.delete-all'.i18n,
                  style: TextStyle(
                    color: HomeTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [cabecera] es la franja del título, que va como primer trozo del
  /// desplazamiento. En escritorio no hay franja y va en null.
  Widget _buildBody([Widget? cabecera]) {
    return Obx(
      () {
        // Se leen ACÁ, síncrono, dentro del Obx. Las tarjetas se arman
        // dentro de un LayoutBuilder más abajo, y LayoutBuilder.builder
        // corre en la fase de LAYOUT, no de build — o sea que los Rx que
        // lee _buildGrid() ahí quedan FUERA de lo que Obx rastrea. Sin esta
        // lectura previa, Obx no encontraba ninguna variable observable en
        // su alcance y tiraba "improper use of a GetX has been detected"
        // (confirmado en vivo). Mismo motivo documentado en library_page.dart.
        // ignore: unused_local_variable
        // allHistory también, no solo las otras dos.
        //
        // Faltaba, y es lo que lee el Historial: `resents` es la lista de
        // «Continuar», que excluye lo terminado. O sea que al Historial le
        // llegaba el aviso solo si además cambiaba «Continuar» — cualquier
        // cambio que tocara únicamente allHistory pasaba de largo y la pantalla
        // se quedaba con lo de antes.
        final _ =
            _c.resents.length + _c.favorites.length + _c.allHistory.length;

        return Container(
          color: HomeTheme.bg,
          child: Stack(
            children: [
              Positioned.fill(child: AnimatedBackgroundGlow(accent: _accent)),
              // Todo (pestañas + buscador + tarjetas) en UN solo scroll: con
              // el encabezado fijo y el grid en un Expanded, en horizontal al
              // grid le quedaban ~150px y las tarjetas se cortaban sin poder
              // llegar a verlas enteras. Así el encabezado se desplaza y las
              // tarjetas usan toda la pantalla.
              Positioned.fill(
                child: CustomScrollView(
                  slivers: [
                    if (cabecera != null) SliverToBoxAdapter(child: cabecera),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(child: _buildTabs()),
                    // En el teléfono, estado y orden viven en la hoja del
                    // botón de filtros, y el buscador y «borrar todo» en la
                    // franja de arriba. En escritorio hay ancho de sobra y se
                    // quedan a la vista, que es más rápido de usar con ratón.
                    if (!Platform.isAndroid) ...[
                      SliverToBoxAdapter(child: _buildFiltrosYOrden()),
                      SliverToBoxAdapter(child: _buildSearchAndActions()),
                    ],
                    _buildGrid(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Televisor ──────────────────────────────────────

  /// El teclado ocupa el sitio de la columna mientras se escribe.
  bool _escribiendoTv = false;

  /// Historial, Favoritos y la Zona +18, con el molde de televisor.
  ///
  /// Las tres son ESTA pantalla con banderas distintas, así que las tres se
  /// arreglan de una. Hasta ahora las tres caían en `_buildAndroid` —un
  /// Android TV es Android— y se veían con la franja fina de teléfono, su
  /// flecha de volver corrida hacia adentro y trece pastillas de filtro
  /// escondidas detrás de un botón. Reportado en vivo: «la zona de favoritos
  /// sigue siendo la misma vaina, la flecha no está centrada arriba a la
  /// izquierda».
  ///
  /// El molde es el mismo que el resto del televisor: título arriba a la
  /// izquierda con su flecha, las funciones en la columna de la izquierda, y
  /// las tarjetas a la derecha con todo el ancho. Los filtros dejan de estar
  /// detrás de un botón: en la columna se ven todos a la vez y se cambian con
  /// una pulsación, que es lo que un mando puede hacer bien.
  ///
  /// La grilla es la MISMA `_buildGrid()` de las otras plataformas. Lo que
  /// cambia en televisor es cómo se llega a las cosas, no cómo se ven las
  /// tarjetas — y esa grilla ya sabe medirse sola.
  Widget _buildTv(BuildContext context) {
    return Obx(() {
      // Igual que en `_buildBody`: los Rx se leen acá, síncrono, porque
      // `_buildGrid` los lee dentro de un LayoutBuilder y eso corre en la fase
      // de layout, fuera de lo que Obx rastrea. Sin esta lectura previa, Obx
      // no encuentra ninguna observable y tira «improper use of a GetX».
      // ignore: unused_local_variable
      final _ = _c.resents.length + _c.favorites.length + _c.allHistory.length;
      return PantallaTv(
        fondo: AnimatedBackgroundGlow(accent: _accent),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_escribiendoTv) _tecladoTv() else _columnaTv(),
            const SizedBox(width: 24),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 4)),
                  _buildGrid(),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _columnaTv() {
    final etiquetasEstado = {
      _EstadoFiltro.todos: 'history.state-all'.i18n,
      _EstadoFiltro.pendiente: 'history.state-pending'.i18n,
      _EstadoFiltro.completado: 'history.state-completed'.i18n,
      _EstadoFiltro.finalizado: 'history.state-finished'.i18n,
    };
    final etiquetasOrden = {
      _Orden.recientes: 'history.sort-recent'.i18n,
      _Orden.antiguos: 'history.sort-oldest'.i18n,
      _Orden.az: 'history.sort-az'.i18n,
      _Orden.za: 'history.sort-za'.i18n,
    };
    final etiquetasRango = {
      _Rango.siempre: 'history.range-all'.i18n,
      _Rango.dia: 'history.range-day'.i18n,
      _Rango.semana: 'history.range-week'.i18n,
      _Rango.mes: 'history.range-month'.i18n,
      _Rango.ano: 'history.range-year'.i18n,
    };
    return ColumnaDeAcciones(
      titulo: widget.soloFavoritos
          ? 'home.favorite'.i18n
          : widget.zone
              ? 'nsfw18.title'.i18n
              : 'home.history'.i18n,
      grupos: [
        GrupoDeColumna(opciones: [
          OpcionDeColumna(
            icono: Icons.arrow_back_rounded,
            texto: 'extension.tv-volver'.i18n,
            onTap: () {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            },
          ),
          OpcionDeColumna(
            id: 'buscar',
            icono: Icons.search_rounded,
            texto: _query.isEmpty ? 'common.search'.i18n : '«$_query»',
            elegido: _query.isNotEmpty,
            onTap: () => setState(() => _escribiendoTv = true),
          ),
        ]),
        // Las pestañas, solo si hay más de una. Con una sola, un grupo entero
        // con una única opción que no se puede cambiar es una fila de ruido.
        if (_pestanas.length > 1)
          GrupoDeColumna(
            titulo: 'history.tv-grupo-pestanas'.i18n,
            opciones: [
              for (final global in _pestanas)
                OpcionDeColumna(
                  id: 'tab-$global',
                  texto: _etiqueta(global),
                  elegido: global == _tabIndex,
                  onTap: () => setState(() => _tabIndex = global),
                ),
            ],
          ),
        // Estado y «desde cuándo» no van en Favoritos, mismo motivo que en las
        // otras plataformas: ahí la fecha es la de guardado y el estado de
        // visto no aplica.
        if (!_onFavoritesTab)
          GrupoDeColumna(
            titulo: 'history.tv-grupo-estado'.i18n,
            opciones: [
              for (final e in _EstadoFiltro.values)
                OpcionDeColumna(
                  id: 'estado-${e.name}',
                  texto: etiquetasEstado[e]!,
                  elegido: _estado == e,
                  onTap: () => setState(() => _estado = e),
                ),
            ],
          ),
        if (!_onFavoritesTab)
          GrupoDeColumna(
            titulo: 'history.tv-grupo-cuando'.i18n,
            opciones: [
              for (final r in _Rango.values)
                OpcionDeColumna(
                  id: 'rango-${r.name}',
                  texto: etiquetasRango[r]!,
                  elegido: _rango == r,
                  onTap: () => setState(() => _rango = r),
                ),
            ],
          ),
        GrupoDeColumna(
          titulo: 'history.sort'.i18n,
          opciones: [
            for (final o in _Orden.values)
              OpcionDeColumna(
                id: 'orden-${o.name}',
                texto: etiquetasOrden[o]!,
                elegido: _orden == o,
                onTap: () => setState(() => _orden = o),
              ),
          ],
        ),
        GrupoDeColumna(
          opciones: [
            OpcionDeColumna(
              icono: Icons.delete_sweep_outlined,
              texto: 'common.delete-all'.i18n,
              onTap: _confirmClearAll,
            ),
          ],
        ),
      ],
    );
  }

  Widget _tecladoTv() {
    return SizedBox(
      width: ColumnaDeAcciones.ancho + 130,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OpcionDeColumna(
                icono: Icons.arrow_back_rounded,
                texto: 'extension.tv-volver-a-filtros'.i18n,
                onTap: () => setState(() => _escribiendoTv = false),
              ),
            ),
            TecladoTv(
              texto: _query,
              ancho: ColumnaDeAcciones.ancho + 130,
              accent: _accent,
              onCambio: (t) {
                // El controlador de texto se mantiene al día igual que en las
                // otras plataformas: es el mismo estado, y si se quedara
                // atrás, salir del televisor y volver mostraría una búsqueda
                // que ya no está puesta.
                _searchController.text = t;
                setState(() => _query = t);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      // El teclado se superpone en vez de encoger el body: en horizontal, al
      // enfocar el buscador quedaban ~100px de alto y las partes fijas
      // (pestañas + buscador) ya se los comían, así que al grid no le
      // quedaba nada y desbordaba (confirmado en vivo). El buscador está
      // ARRIBA, así que sigue visible con el teclado abierto.
      resizeToAvoidBottomInset: false,
      // Sin AppBar: la franja fina, como Inicio, Biblioteca, Buscar y
      // Extensiones. Ver FranjaDeZona.
      // La franja se va al bajar y vuelve al llegar arriba, como el nombre de
      // la app en el Inicio: acostado, clavada era una fila de portadas menos.
      // La franja va DENTRO del desplazamiento, como primer trozo: se va con
      // las tarjetas al bajar y vuelve al subir, igual que el nombre de la app
      // en el Inicio. Ver la nota en franja_de_zona.dart.
      body: _buildBody(
        FranjaDeZona(
          titulo: widget.soloFavoritos
              ? 'home.favorite'.i18n
              : widget.zone
                  ? 'nsfw18.title'.i18n
                  : 'home.history'.i18n,
          // El Historial se abre ENCIMA del shell —desde el botón del Inicio—
          // así que necesita su propia salida. Al quitarle la AppBar se fue
          // con ella la flecha que Material ponía sola, y quedaba solo el atrás
          // del sistema. En las pestañas del shell esto va en null: ahí no hay
          // a dónde volver.
          alVolver: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          ayuda: 'common.search'.i18n,
          controlador: _searchController,
          alEscribir: (value) => setState(() => _query = value),
          alEnviar: (value) => setState(() => _query = value),
          acciones: [
            // ── Los filtros, en un botón ────────────────────────────────
            //
            // Eran trece pastillas en cuatro renglones —cinco de pestaña,
            // cuatro de estado, cuatro de orden— arriba de todo, antes de la
            // primera tarjeta. Acostado eso era la pantalla entera.
            //
            // El puntito avisa que hay algo puesto: metido dentro de la hoja,
            // uno se olvida de que filtró y la lista corta parece un error.
            AccionDeFranja(
              ayuda: 'search.filter'.i18n,
              alTocar: _abrirFiltros,
              icono: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.tune_rounded),
                  if (_hayFiltroPuesto)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            AccionDeFranja(
              ayuda: 'common.delete-all'.i18n,
              alTocar: _confirmClearAll,
              icono: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.soloFavoritos
                    ? 'home.favorite'.i18n
                    : widget.zone
                        ? 'nsfw18.title'.i18n
                        : 'home.history'.i18n,
                // Mismo estilo que el título de Inicio, desde un solo lugar.
                style: HomeTheme.tituloDeZona(
                  // Acostado en un teléfono, 25 se come una franja que le
                  // hace falta a la lista.
                  bajo: Platform.isAndroid &&
                      MediaQuery.orientationOf(context) ==
                          Orientation.landscape,
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No hacer early-return acá con un Center+Text suelto: eso saltea el
    // Scaffold/AppBar (sin Material ancestor, Flutter dibuja el texto con su
    // estilo de fallback feo — rojo con subrayado amarillo) y deja la página
    // sin botón para volver. El estado vacío se maneja dentro de _buildGrid,
    // que ya corre dentro del Scaffold normal.
    // El televisor se pregunta ANTES que Android: un Android TV es Android,
    // asi que sin esto cae en `_buildAndroid` -- que es exactamente lo que
    // pasaba, y por eso esta pantalla se veia con la franja fina y los chips
    // de telefono en un televisor.
    if (PlatformTv.esTelevisionSync) return _buildTv(context);
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}

/// Filtro por estado del Historial. `finalizado` mira un eje distinto de los
/// otros dos: si la OBRA terminó, no si el usuario está al día.
enum _EstadoFiltro { todos, pendiente, completado, finalizado }

enum _Orden { recientes, antiguos, az, za }

/// Desde cuándo se muestra. Solo en el Historial: en Favoritos la fecha es la
/// de guardado y filtrar por ella no responde ninguna pregunta que uno se haga
/// —ahí se guarda justamente para que no importe cuándo fue—.
enum _Rango { siempre, dia, semana, mes, ano }
