import 'dart:async';
import 'dart:io';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/tracking_page_controller.dart';
import 'package:prismhub/data/providers/anilist_provider.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/forma_portada.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/tv/teclado_tv.dart';
import 'package:prismhub/views/widgets/home/refresh_button.dart';
import 'package:prismhub/views/widgets/infinite_scroller.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_access.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/search_appbar.dart';

class ExtensionSearcherPage extends fluent.StatefulWidget {
  const ExtensionSearcherPage({
    super.key,
    required this.package,
    this.keyWord,
    this.soloAdulto = false,
  });
  final String package;
  final String? keyWord;

  /// Se entró desde la Zona +18.
  ///
  /// ── Qué cambia ──────────────────────────────────────────────────────────
  ///
  /// En una extensión MIXTA —ShadeManga y ManhwaWeb son las dos que hay— el
  /// contenido para adultos vive detrás de un filtro propio del sitio, y ese
  /// filtro viene apagado por defecto. Así que entrando desde la Zona +18 se
  /// veía el catálogo general: exactamente lo que esa zona no es.
  ///
  /// Con esto, al abrirla desde la zona el filtro de adultos arranca ENCENDIDO.
  /// Lo de siempre sigue igual: desde el buscador normal entra apagado.
  ///
  /// Es el espejo de lo que hace el Home, que manda el valor seguro a la fuerza
  /// (ver `_segurosPorExtension` en catalogo_extensiones_controller).
  final bool soloAdulto;

  @override
  fluent.State<ExtensionSearcherPage> createState() =>
      _ExtensionSearcherPageState();
}

class _ExtensionSearcherPageState extends fluent.State<ExtensionSearcherPage> {
  late ExtensionService _runtime;
  late String _keyWord = widget.keyWord ?? '';

  // Android: infinite scroll accumulates pages
  final List<ExtensionListItem> _data = [];
  int _page = 1;

  // Desktop: arrow navigation, shows one "view page" at a time. Some
  // sources return very few items per raw page (e.g. 26) while others
  // return plenty (40+) — a single raw page then leaves a lot of dead
  // space below the grid. _rawPage is the actual next source page to
  // fetch; _virtualPages caches each already-built view page (keyed by
  // _browsePage - 1) so going back is instant and forward navigation
  // keeps pulling from wherever the raw cursor left off.
  int _browsePage = 1;
  List<ExtensionListItem> _browseData = [];
  int _rawPage = 1;
  final List<List<ExtensionListItem>> _virtualPages = [];

  bool _isLoading = true;
  final EasyRefreshController _easyRefreshController = EasyRefreshController();
  Map<String, ExtensionFilter>? _filters;
  Map<String, List<String>> _selectedFilters = {};
  // true cuando el filtro elegido activa una opción marcada como "adultos"
  // (ExtensionFilter.adultOption — ver ShadeManga) Y el switch de NSFW en
  // Ajustes está apagado. En ese caso no se llama a la extensión: se
  // muestra un aviso pidiendo activar el NSFW en vez de dejar la pantalla
  // vacía sin explicación (o, peor, mostrar contenido +18 sin querer).
  bool _nsfwBlocked = false;

  // Bloqueo por actualización pendiente — antes esta pantalla no chequeaba
  // nada (solo Instaladas/Repositorio lo mostraban), así que se podía
  // entrar y buscar normalmente en una extensión desactualizada sin
  // enterarse. null = todavía no se sabe (mientras se resuelve, no se
  // carga nada ni se deja ver la grilla); true = bloqueada de verdad, no
  // solo un aviso arriba.
  bool? _hasUpdate;
  bool _updatingExtension = false;

  /// La pestaña Normal/+18, solo para extensiones MIXTAS (ManhwaWeb,
  /// ShadeManga — `ExtensionUtils.esMixta`). Arranca en `widget.soloAdulto`
  /// para que entrar desde la Zona +18 ya abra ahí, pero a partir de acá es
  /// estado propio de esta pantalla: antes de esto no había ningún camino
  /// para pasar de un catálogo al otro sin salir y volver a entrar por la
  /// otra ruta.
  late bool _pestanaAdulto = widget.soloAdulto;

  /// Cambia de pestaña y recarga con el filtro que corresponde.
  ///
  /// ── Por qué pide PIN para entrar a "+18" pero nunca para volver ────────
  ///
  /// Si esto solo mirara el switch general de NSFW, cualquiera podría abrir
  /// esta pantalla desde el buscador NORMAL —sin PIN, sin confirmación— y
  /// tocar "+18" para ver contenido adulto sin fricción, saltándose la
  /// protección que hoy exige la Zona +18. `confirmNsfw18Access` es la
  /// misma puerta reusable que ya usa esa zona (confirmación + PIN, no una
  /// segunda construida a mano acá). Volver a "Normal" nunca pide nada:
  /// volver a lo seguro no necesita permiso.
  ///
  /// ── Por qué solo se toca la puerta, no todo `_selectedFilters` ─────────
  ///
  /// `ExtensionUtils.adultosDe`/`segurosDe` solo cubren el/los filtros que
  /// tienen una puerta a adultos (ver `detectarMixtas`) — nunca género,
  /// orden ni el resto. Reemplazar `_selectedFilters` entero tiraría
  /// cualquier otro filtro que el usuario ya hubiera elegido; con
  /// `addAll` se pisa SOLO la puerta y el resto queda como estaba.
  Future<void> _cambiarPestana(bool adulto) async {
    if (adulto == _pestanaAdulto) return;
    if (adulto) {
      final permitido = await confirmNsfw18Access(context);
      if (!permitido || !mounted) return;
      setState(() {
        _pestanaAdulto = true;
        _selectedFilters
            .addAll(ExtensionUtils.adultosDe(widget.package) ?? const {});
      });
    } else {
      setState(() {
        _pestanaAdulto = false;
        _selectedFilters
            .addAll(ExtensionUtils.segurosDe(widget.package) ?? const {});
      });
    }
    if (Platform.isAndroid) {
      _easyRefreshController.callRefresh();
    } else {
      _goToPage(1);
    }
  }

  bool get _adultOptionSelected {
    if (_filters == null) return false;
    for (final entry in _filters!.entries) {
      final adultOpt = entry.value.adultOption;
      if (adultOpt == null) continue;
      if (_selectedFilters[entry.key]?.contains(adultOpt) ?? false) return true;
    }
    return false;
  }

  // Cada llamada a _goToPage/_onLoad se marca con un número que sube. Si el
  // usuario cambia de filtro o de página mientras una búsqueda anterior
  // todavía está en vuelo, la respuesta vieja (de otro filtro/página) ya no
  // coincide con el número vigente y se descarta en vez de pisar el estado
  // más nuevo — esto es lo que rompía "volver atrás" cuando se cambiaba de
  // filtro justo antes de que terminara de cargar la página anterior.
  int _requestGen = 0;

  // Sin esto, filtrar SIN escribir nada en el buscador no hacía nada: con
  // palabra clave vacía siempre se llamaba a latest() (que no recibe
  // filtro), ignorando por completo lo que el usuario eligió en el diálogo.
  // Se considera "activo" cualquier filtro cuya selección actual sea
  // distinta de su propio valor por defecto.
  bool get _hasActiveFilters {
    if (_filters == null) return false;
    for (final entry in _filters!.entries) {
      final selected = _selectedFilters[entry.key];
      if (selected == null) continue;
      if (selected.length != 1 || selected.first != entry.value.defaultOption) {
        return true;
      }
    }
    return false;
  }

  // Los filtros del panel quedan puestos de una búsqueda a la otra, así que uno
  // que sobró de antes puede dejar sin resultados algo que la extensión SÍ
  // tiene. Cuando la búsqueda se salva repitiéndola sin filtros (ver
  // searchFirstPageWithBroadening), hay que decirlo: si no, la lista muestra
  // cosas que no cumplen los filtros marcados y parece que el filtro no anda.
  void _avisarFiltrosIgnorados() {
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      content: 'common.search-filters-ignored'.i18n,
      severity: fluent.InfoBarSeverity.info,
    );
  }

  // Cuántos títulos hay cargados ahora mismo en esta pantalla.
  //
  // Es lo CARGADO, no el total del sitio: ninguna extensión sabe cuántas obras
  // tiene su catálogo —los sitios no lo publican— y no vale la pena inventar un
  // número. Sirve igual para lo que hace falta: ver de un vistazo si una página
  // vino corta o si un filtro dejó afuera casi todo, sin tener que contar
  // tarjetas a ojo.
  //
  // En escritorio se cuenta la página que se está viendo, que es lo que la
  // pantalla muestra; en móvil, donde el scroll va agregando tandas a la misma
  // lista, se cuenta el acumulado. Es el mismo criterio que usa el
  // autocompletado más abajo para saber qué lista se está dibujando.
  int get _cargados => (Platform.isAndroid ? _data : _browseData).length;

  // "1.234" y no "1234": son números que se leen de reojo.
  String get _cargadosTexto {
    final n = _cargados.toString();
    final buf = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) buf.write('.');
      buf.write(n[i]);
    }
    return buf.toString();
  }

  late final _textEditingController = TextEditingController(text: _keyWord);

  // Autocompletado (texto sugerido ADENTRO del mismo campo, seleccionado —
  // no un panel de opciones aparte) + placeholder rotativo. Usa los
  // títulos que ESTA extensión ya trajo (modo "latest"/explorar, _data en
  // Android o _browseData en desktop), sin pedir nada nuevo.
  String _typedText = '';
  // Prefijo que YA tiene una sugerencia puesta (seleccionada) en el campo
  // — si el próximo cambio vuelve a ser exactamente este valor (el usuario
  // borró la selección con Backspace, rechazando la sugerencia), no se
  // vuelve a autocompletar en el mismo golpe. Sin esto, Backspace sobre la
  // sugerencia quedaba "pegado" (borra la sugerencia → se vuelve a poner
  // sola de inmediato).
  String? _ghostBase;
  // true mientras estamos nosotros mismos poniendo el texto completado en
  // el controller — evita reprocesar ESE cambio como si fuera una tecla
  // real del usuario.
  bool _isProgrammaticTextChange = false;
  // Cuánto hay que dejar de escribir para que aparezca la sugerencia. Ver
  // _onSearchFieldChanged. Corto: es una pausa entre teclas, no una espera.
  static const Duration _pausaAutocompletar = Duration(milliseconds: 500);
  Timer? _autocompletarTimer;
  Timer? _placeholderTimer;
  int _placeholderIndex = 0;

  // Hasta 20 títulos, sin duplicados y sin vacíos — alcanza para
  // sugerencias/rotación sin guardar listas gigantes en memoria.
  List<String> get _sampleTitles {
    final source = Platform.isAndroid ? _data : _browseData;
    final seen = <String>{};
    final titles = <String>[];
    for (final item in source) {
      final title = item.title.trim();
      if (title.isEmpty || !seen.add(title)) continue;
      titles.add(title);
      if (titles.length >= 20) break;
    }
    return titles;
  }

  String _placeholderText(BuildContext context) {
    final titles = _sampleTitles;
    if (titles.isEmpty) return 'search.hint-text'.i18n;
    final title = titles[_placeholderIndex % titles.length];
    return FlutterI18n.translate(
      context,
      'extension-searcher.placeholder-example',
      translationParams: {'title': title},
    );
  }

  // Handler único para el campo de búsqueda en las dos plataformas — pone
  // el resto del título sugerido directo en el mismo controller, con esa
  // parte seleccionada (mismo truco que usaba el explorador de Windows
  // viejo): seguir escribiendo la reemplaza, Enter/Tab la acepta tal cual
  // porque el campo YA tiene el texto completo.
  //
  // La sugerencia espera a que dejes de escribir. Antes saltaba en CADA tecla,
  // y ahí es donde molestaba de verdad: cada pulsación reescribía el campo
  // entero y movía el cursor, así que escribir algo que no fuera el título que
  // la extensión adivinó era pelear contra el campo tecla por tecla. Peor en
  // el teléfono, donde el teclado predictivo va corrigiendo sobre un texto que
  // le cambia abajo de los pies.
  //
  // Con la pausa, mientras escribís el campo tiene EXACTAMENTE lo que
  // escribiste y nada más. La sugerencia aparece recién cuando parás, que es
  // cuando sirve y cuando no estorba.
  void _onSearchFieldChanged(String value) {
    if (_isProgrammaticTextChange) {
      _isProgrammaticTextChange = false;
      if (value.isEmpty) _onSearch(value);
      return;
    }
    // Cualquier tecla cancela una sugerencia que estuviera por aparecer: si
    // seguís escribiendo, la de hace un momento ya no corresponde.
    _autocompletarTimer?.cancel();

    if (value.isEmpty) {
      _typedText = '';
      _ghostBase = null;
      _onSearch(value);
      return;
    }
    final wasLonger = value.length < _typedText.length;
    final backedOutOfGhost = value == _ghostBase;
    _typedText = value;
    _ghostBase = null;
    // Borrando, o Backspace justo sobre la sugerencia (la está rechazando)
    // — no autocompletar de nuevo en este mismo golpe.
    if (wasLonger || backedOutOfGhost) return;

    _autocompletarTimer = Timer(_pausaAutocompletar, () {
      // El campo pudo cambiar entre medio (o la pantalla irse): solo se sugiere
      // sobre el texto exacto que disparó esta espera.
      if (!mounted || _textEditingController.text != value) return;
      // Y solo con el cursor al final: si volviste a meter mano en el medio de
      // lo escrito, completar el final no es lo que estás pidiendo.
      final sel = _textEditingController.selection;
      if (!sel.isCollapsed || sel.baseOffset != value.length) return;

      final lower = value.toLowerCase();
      final match = _sampleTitles.firstWhere(
        (title) =>
            title.length > value.length &&
            title.toLowerCase().startsWith(lower),
        orElse: () => '',
      );
      if (match.isEmpty) return;
      _ghostBase = value;
      _isProgrammaticTextChange = true;
      _textEditingController.value = TextEditingValue(
        text: match,
        selection:
            TextSelection(baseOffset: value.length, extentOffset: match.length),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // El chequeo de actualización va ANTES que todo lo demás — con
    // _hasUpdate en null todavía no se llama a _initFilters() ni se pide
    // nada a la extensión, así una desactualizada nunca llega a mostrar
    // sus cards (antes el bloqueo real solo vivía en Instaladas/
    // ExtensionTile, así que entrar desde Búsqueda general, Continuar o un
    // "ver más" pasaba por completo esa validación).
    ExtensionUtils.hasExtensionUpdate(widget.package).then((value) {
      if (!mounted) return;
      setState(() => _hasUpdate = value);
      if (!value) {
        SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
          _initFilters();
        });
      }
    });
    // Cada 10s, mientras el campo esté vacío no se ve nada distinto (el
    // placeholder solo se muestra sin texto), así que no hace falta pausar
    // el timer según foco/contenido.
    _placeholderTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() => _placeholderIndex++);
    });
  }

  Future<void> _performExtensionUpdate() async {
    setState(() => _updatingExtension = true);
    try {
      await ExtensionUtils.updateInstalledFromRepo(widget.package, context);
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'extension.install-success'.i18n,
          severity: fluent.InfoBarSeverity.success,
        );
      }
      final stillNeeded =
          await ExtensionUtils.hasExtensionUpdate(widget.package);
      if (mounted) setState(() => _hasUpdate = stillNeeded);
      // Ya actualizada: recién ahora se deja cargar la grilla — antes de
      // esto, _initFilters() nunca había corrido porque _hasUpdate seguía
      // en true desde el initState.
      if (!stillNeeded && mounted) _initFilters();
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _updatingExtension = false);
    }
  }

  @override
  void dispose() {
    _placeholderTimer?.cancel();
    // Si no, una sugerencia pendiente se dispara con la pantalla ya cerrada y
    // toca un controller que acaba de liberarse.
    _autocompletarTimer?.cancel();
    _textEditingController.dispose();
    super.dispose();
  }

  _initFilters() async {
    try {
      _filters = await _runtime.createFilter();
      _filters!.forEach((key, value) {
        // Desde la Zona +18, el filtro de adultos arranca encendido. Ver
        // `soloAdulto`.
        final adulto = value.adultOption;
        if (widget.soloAdulto && adulto != null && adulto.isNotEmpty) {
          _selectedFilters[key] = [adulto];
          return;
        }
        _selectedFilters[key] = [value.defaultOption];
      });
    } catch (e, st) {
      // Antes esto se tragaba el error en silencio — el diálogo de filtro
      // quedaba vacío (título+botones, sin ninguna opción) sin ninguna
      // pista de por qué. Con esto al menos se ve la excepción real en la
      // consola de `flutter run`.
      debugPrint('createFilter() falló para ${widget.package}: $e\n$st');
      _filters = {};
    }
    if (!mounted) return;
    if (Platform.isAndroid) {
      setState(() {});
    } else {
      _goToPage(1);
    }
  }

  // ── Desktop: page-based navigation ──────────────────────────────────────

  // Minimum items to gather before treating a view page as "full enough"
  // to stop pulling more raw pages — a few rows' worth on a typical window.
  static const _minItemsPerViewPage = 40;

  Future<void> _goToPage(int page) async {
    if (!mounted || page < 1) return;
    if (_adultOptionSelected &&
        !PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
      setState(() {
        _nsfwBlocked = true;
        _browseData = [];
        _isLoading = false;
      });
      return;
    }
    if (_nsfwBlocked) setState(() => _nsfwBlocked = false);
    final myGen = ++_requestGen;
    // Page 1 always means "start over" (fresh search/filter) — reset the
    // raw cursor and cache so nothing stale from a previous query lingers.
    if (page == 1) {
      _rawPage = 1;
      _virtualPages.clear();
    }
    final oldPage = _browsePage;

    // Already built this view page before (e.g. navigating back) — show
    // the cached result instantly instead of refetching.
    if (page - 1 < _virtualPages.length) {
      setState(() {
        _browsePage = page;
        _browseData = _virtualPages[page - 1];
      });
      return;
    }

    setState(() {
      _browsePage = page;
      _browseData = [];
      _isLoading = true;
    });
    try {
      final collected = <ExtensionListItem>[];
      final seenUrls = <String>{};
      var gotAny = false;
      // Cuántos intentos seguidos no sumaron NADA nuevo (todo ya visto en
      // este mismo llamado) — algunas fuentes (confirmado en vivo con
      // AnimeFenix buscando) no paginan de verdad: cada pedido devuelve un
      // subconjunto medio mezclado del mismo puñado chico de resultados en
      // vez de contenido nuevo, así que sin deduplicar por url la misma
      // portada aparecía repetida varias veces seguidas en la grilla. Cortar
      // después de 2 intentos sin nada nuevo evita seguir insistiendo contra
      // una fuente que ya mostró todo lo que tiene.
      var noNewInARow = 0;
      for (var attempts = 0;
          attempts < 4 &&
              collected.length < _minItemsPerViewPage &&
              noNewInARow < 2;
          attempts++) {
        List<ExtensionListItem> batch;
        try {
          batch = _keyWord.isEmpty && !_hasActiveFilters
              ? await _runtime.latest(_rawPage)
              : (_rawPage == 1
                  ? await _runtime.searchFirstPageWithBroadening(
                      SearchText.sanitizeForRemoteQuery(_keyWord),
                      filter: _selectedFilters,
                      onFiltrosIgnorados: _avisarFiltrosIgnorados)
                  : await _runtime.search(
                      SearchText.sanitizeForRemoteQuery(_keyWord), _rawPage,
                      filter: _selectedFilters));
        } catch (e) {
          // Pedir de más para "rellenar" la página de vista es best-effort:
          // muchas fuentes (confirmado en vivo con animeytx, sitio WordPress)
          // tiran 404 real al pasarse de su última página válida en vez de
          // devolver una lista vacía. Si ya se consiguió algo en un intento
          // anterior (gotAny) O ya habíamos cargado alguna página con éxito
          // antes en esta navegación (_virtualPages no vacío), tratar esto
          // igual que "sin más datos" — no tirar todo lo ya conseguido.
          // Antes esto solo miraba "gotAny" (que se reinicia en CADA página
          // nueva), así que si el primer pedido de una página posterior caía
          // justo en el límite real del sitio, se mostraba como error en vez
          // de "no hay más datos" — aunque la página anterior sí había
          // cargado bien. Si esta es realmente la primera página de toda la
          // navegación y el primer intento falla, ahí sí es un error real
          // (no hay nada que mostrar).
          if (gotAny || _virtualPages.isNotEmpty) break;
          rethrow;
        }
        // Una navegación o cambio de filtro más nuevo ya arrancó mientras
        // esperábamos esta respuesta — descartarla, no pisar el estado actual.
        if (myGen != _requestGen) return;
        if (batch.isEmpty) break;
        gotAny = true;
        var addedNew = false;
        for (final item in batch) {
          if (seenUrls.add(item.url)) {
            collected.add(item);
            addedNew = true;
          }
        }
        noNewInARow = addedNew ? 0 : noNewInARow + 1;
        _rawPage++;
      }
      if (!mounted || myGen != _requestGen) return;
      if (!gotAny) {
        setState(() => _browsePage = oldPage);
        showPlatformSnackbar(
          context: context,
          content: (_hasActiveFilters
                  ? 'common.no-more-data-filtered'
                  : 'common.no-more-data')
              .i18n,
          severity: fluent.InfoBarSeverity.warning,
        );
      } else {
        // "Inteligente hasta el alcance de la extensión": no controlamos
        // el motor de búsqueda del sitio remoto, pero sí podemos priorizar
        // LOCALMENTE los ítems cuyo título matchea la palabra buscada —
        // una sola vez, cuando esta página YA llegó completa (no reordena
        // nada mientras todavía está cargando). No oculta nada, solo
        // prioriza. Sin palabra clave (modo "latest") no se toca el orden
        // que manda el sitio.
        if (_keyWord.trim().isNotEmpty) {
          // Tokeniza UNA vez afuera del comparator — sort() llama al
          // comparator O(n log n) veces, así que renormalizar _keyWord dos
          // veces POR COMPARACIÓN sería trabajo repetido de sobra.
          final tokens = SearchText.queryTokens(_keyWord);
          collected.sort((a, b) {
            final aMatches = SearchText.matchesTokens(a.title, tokens);
            final bMatches = SearchText.matchesTokens(b.title, tokens);
            if (aMatches == bMatches) return 0;
            return aMatches ? -1 : 1;
          });
        }
        _virtualPages.add(collected);
        setState(() => _browseData = collected);
      }
    } catch (e) {
      if (!mounted || myGen != _requestGen) return;
      setState(() => _browsePage = oldPage);
      showPlatformSnackbar(
        context: context,
        content: friendlyError(e),
        severity: fluent.InfoBarSeverity.error,
      );
    } finally {
      if (mounted && myGen == _requestGen) setState(() => _isLoading = false);
    }
  }

  // ── Android: infinite scroll ─────────────────────────────────────────────

  Future<void> _onRefresh() async {
    setState(() {
      _page = 1;
      _data.clear();
    });
    await _onLoad();
  }

  Future<void> _onLoad() async {
    if (_adultOptionSelected &&
        !PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
      setState(() {
        _nsfwBlocked = true;
        _data.clear();
        _isLoading = false;
      });
      return;
    }
    final myGen = ++_requestGen;
    try {
      _isLoading = true;
      if (_nsfwBlocked) _nsfwBlocked = false;
      setState(() {});
      // Algunas fuentes (ej. jk) tienen páginas que se solapan con la
      // anterior — una sola página toda duplicada NO significa que no haya
      // más contenido, solo que esa página puntual no trajo nada nuevo.
      // Se insiste unas páginas más antes de recién ahí avisar "sin más datos".
      final existingUrls = _data.map((e) => e.url).toSet();
      final fresh = <ExtensionListItem>[];
      var gotAnyThisCall = false;
      for (var attempts = 0; attempts < 4 && fresh.isEmpty; attempts++) {
        List<ExtensionListItem> data;
        try {
          data = _keyWord.isEmpty && !_hasActiveFilters
              ? await _runtime.latest(_page)
              : (_page == 1
                  ? await _runtime.searchFirstPageWithBroadening(
                      SearchText.sanitizeForRemoteQuery(_keyWord),
                      filter: _selectedFilters,
                      onFiltrosIgnorados: _avisarFiltrosIgnorados)
                  : await _runtime.search(
                      SearchText.sanitizeForRemoteQuery(_keyWord), _page,
                      filter: _selectedFilters));
        } catch (e) {
          // Mismo caso que en desktop: pasarse de la última página real
          // suele tirar 404 en vez de una lista vacía. Si esta llamada ya
          // había conseguido algo (gotAnyThisCall) O ya había contenido
          // cargado de antes (_data no vacío — scroll infinito, esta es la
          // Nva. tanda), tratarlo como "sin más datos" en vez de reventar
          // con un error. Antes solo miraba gotAnyThisCall (se reinicia en
          // cada tanda nueva), así que la primera petición de una tanda
          // posterior que cae justo en el límite real del sitio se mostraba
          // como error aunque ya hubiera contenido bueno en pantalla. Si
          // esto es realmente la primera carga y falla, sí es un error real.
          if (gotAnyThisCall || _data.isNotEmpty) break;
          rethrow;
        }
        // Un refresh/cambio de filtro más nuevo ya reinició _data mientras
        // esperábamos esta respuesta — descartarla, no mezclar resultados
        // de un filtro viejo con la lista ya reiniciada.
        if (myGen != _requestGen) return;
        if (data.isEmpty) break; // la fuente sí se quedó sin páginas
        gotAnyThisCall = true;
        _page++;
        for (final e in data) {
          if (existingUrls.add(e.url)) fresh.add(e);
        }
      }
      if (myGen != _requestGen) return;
      if (fresh.isEmpty && mounted) {
        showPlatformSnackbar(
          context: context,
          content: (_hasActiveFilters
                  ? "common.no-more-data-filtered"
                  : "common.no-more-data")
              .i18n,
          severity: fluent.InfoBarSeverity.warning,
        );
      }
      // Mismo criterio que en desktop, pero solo dentro del lote NUEVO que
      // se está por agregar — reordenar TODO `_data` en cada tanda movería
      // ítems que el usuario ya está viendo/scrolleando (peor que el salto
      // que se quiere evitar). Cada lote nuevo llega con sus propios
      // matches primero, sin tocar lo que ya estaba en pantalla.
      if (_keyWord.trim().isNotEmpty) {
        // Tokeniza UNA vez afuera del comparator, mismo motivo que en
        // desktop (ver _goToPage).
        final tokens = SearchText.queryTokens(_keyWord);
        fresh.sort((a, b) {
          final aMatches = SearchText.matchesTokens(a.title, tokens);
          final bMatches = SearchText.matchesTokens(b.title, tokens);
          if (aMatches == bMatches) return 0;
          return aMatches ? -1 : 1;
        });
      }
      _data.addAll(fresh);
    } catch (e) {
      if (myGen != _requestGen) return;
      if (!mounted) rethrow;
      showPlatformSnackbar(
          // ignore: use_build_context_synchronously
          context: context,
          content: friendlyError(e),
          severity: fluent.InfoBarSeverity.error);
      rethrow;
    } finally {
      _isLoading = false;
      if (mounted) setState(() {});
    }
  }

  // ── Shared ───────────────────────────────────────────────────────────────

  _onSearch(String keyWord) {
    // Bloqueada por actualización pendiente (o todavía sin confirmar): ni
    // el InfiniteScroller/EasyRefresh están montados en ese estado (ver
    // build), así que dispararlo desde acá no tendría a dónde ir.
    if (_hasUpdate != false) return;
    _keyWord = keyWord;
    if (Platform.isAndroid) {
      _easyRefreshController.callRefresh();
    } else {
      _goToPage(1);
    }
  }

  /// ¿Hay algún filtro cambiado respecto de como viene?
  ///
  /// Para el puntito del botón: metido dentro de la hoja, uno se olvida de que
  /// filtró y una lista corta parece un error. Se compara contra la opción por
  /// defecto de cada filtro, no contra «vacío»: `_initFilters` los deja a todos
  /// con la suya puesta, así que vacío no existe nunca.
  bool get _hayFiltroPuesto {
    final filtros = _filters;
    if (filtros == null) return false;
    for (final entrada in filtros.entries) {
      final elegido = _selectedFilters[entrada.key];
      if (elegido == null) continue;
      if (elegido.length != 1 || elegido.first != entrada.value.defaultOption) {
        return true;
      }
    }
    return false;
  }

  _onFilter(BuildContext context) {
    final fiterWidget = _ExtensionFilterWidget(
      runtime: _runtime,
      filters: _filters!,
      // Fuera de la Zona +18 la puerta a adultos ni se ofrece.
      // La pestaña ACTUAL, no la ruta de entrada — antes de la Fase 8 eran
      // lo mismo (`soloAdulto` era fijo para toda la pantalla), pero ahora
      // se puede cambiar de pestaña sin volver a entrar.
      desdeLaZona18: _pestanaAdulto,
      selectedFilters: _selectedFilters,
      onSelectFilter: (selectedFilters, filters) {
        _selectedFilters = selectedFilters;
        _filters = filters;
      },
    );

    // ── En TV: un panel a la derecha, no una hoja desde abajo ───────────
    //
    // La hoja de Android sube desde el borde inferior y se cierra
    // arrastrándola: dos cosas que en un televisor no existen. Y ocupa el
    // alto entero, así que se pierde de vista lo que se está filtrando.
    //
    // Un panel lateral respeta el mismo reparto que el resto de la interfaz
    // de TV (algo fijo a un costado, el contenido al lado) y se cierra con
    // el botón de atrás del mando, que es lo que uno aprieta.
    if (PlatformTv.esTelevisionSync) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'search.filter'.i18n,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: HomeTheme.cardSurface,
            child: SizedBox(
              width: (MediaQuery.sizeOf(context).width * 0.42)
                  .clamp(380.0, 620.0),
              height: double.infinity,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'search.filter'.i18n,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: HomeTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Aire de verdad antes de los botones: el último chip
                      // crece al enfocarse y quedaba montado sobre
                      // "Confirmar".
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: FocusableCard(
                              borderRadius: 10,
                              autofocus: true,
                              onTap: () {
                                Get.back();
                                _easyRefreshController.callRefresh();
                              },
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: HomeTheme.accentPink,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'common.confirm'.i18n,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FocusableCard(
                            borderRadius: 10,
                            onTap: () => Get.back(),
                            child: Container(
                              height: 48,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 22),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: HomeTheme.border),
                              ),
                              child: Text(
                                'common.cancel'.i18n,
                                style: TextStyle(
                                  color: HomeTheme.textMuted,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // ── Recorrido en ORDEN, no direccional ────────────
                      //
                      // Los chips se acomodan en un `Wrap`, o sea filas que
                      // se arman según el ancho. Con la navegación
                      // direccional de Flutter, apretar izquierda en el
                      // primer chip de una fila no encuentra nada a su
                      // izquierda y salta al enfocable más cercano en esa
                      // dirección — que termina siendo uno de la fila de
                      // ABAJO. Eso es el "me baja solo sin que yo marque
                      // abajo".
                      //
                      // Acá derecha/izquierda recorren la lista en orden
                      // (siguiente/anterior), como se leería: al llegar al
                      // final de una fila sigue en la próxima, y nunca
                      // salta a un lugar que no se esperaba.
                      Expanded(
                        child: Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: (node, evento) {
                            if (evento is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final tecla = evento.logicalKey;
                            if (tecla == LogicalKeyboardKey.arrowRight) {
                              node.nextFocus();
                              return KeyEventResult.handled;
                            }
                            if (tecla == LogicalKeyboardKey.arrowLeft) {
                              node.previousFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: fiterWidget,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Entra deslizándose desde el borde derecho: deja claro de dónde
        // salió y hacia dónde se va al cerrarlo.
        transitionBuilder: (_, anim, __, hijo) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: hijo,
        ),
      );
      return;
    }

    if (Platform.isAndroid) {
      showModalBottomSheet(
        context: context,
        // Como el resto de las hojas de la app: la superficie de tarjeta y las
        // esquinas redondeadas. Esta era la única que salía con el fondo de la
        // pantalla y en escuadra, así que se leía como otra pantalla en vez de
        // como una hoja.
        backgroundColor: HomeTheme.cardSurface,
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        // Sin isScrollControlled/DraggableScrollableSheet, el sheet quedaba
        // con una altura fija chica (no la real disponible) — en horizontal
        // (poca altura vertical) apenas entraban 1-2 filas de chips.
        // Mismo patrón ya usado en video_player_mobile_controls.dart para
        // el selector de dispositivo DLNA.
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: Text(
                        "common.cancel".i18n,
                        style: TextStyle(color: HomeTheme.textMuted),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: ButtonStyle(
                        backgroundColor:
                            WidgetStateProperty.all(HomeTheme.accentPink),
                      ),
                      onPressed: () {
                        Get.back();
                        _easyRefreshController.callRefresh();
                      },
                      child: Text("common.confirm".i18n),
                    )
                  ],
                ),
              ),
              Divider(color: HomeTheme.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                  child: fiterWidget,
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    fluent.showDialog(
      context: context,
      builder: (context) {
        return fluent.ContentDialog(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
          style: fluent.ContentDialogThemeData(
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
            ),
          ),
          title: Text(
            'search.filter'.i18n,
            style: TextStyle(
                color: HomeTheme.textPrimary, fontWeight: FontWeight.w800),
          ),
          content: fiterWidget,
          actions: [
            fluent.Button(
              style: fluent.ButtonStyle(
                backgroundColor: fluent.WidgetStateProperty.all(HomeTheme.bg),
                foregroundColor:
                    fluent.WidgetStateProperty.all(HomeTheme.textMuted),
                shape: fluent.WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: HomeTheme.border),
                  ),
                ),
              ),
              child: Text('common.cancel'.i18n),
              onPressed: () => router.pop(),
            ),
            fluent.FilledButton(
              style: fluent.ButtonStyle(
                backgroundColor:
                    fluent.WidgetStateProperty.all(HomeTheme.accentPink),
                foregroundColor: fluent.WidgetStateProperty.all(HomeTheme.bg),
                shape: fluent.WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
              ),
              child: Text('common.confirm'.i18n),
              onPressed: () {
                router.pop();
                _goToPage(1);
              },
            ),
          ],
        );
      },
    );
  }

  // ── Builders ─────────────────────────────────────────────────────────────

  // Se muestra en vez de la grilla cuando el filtro elegido activa contenido
  // +18 (ExtensionFilter.adultOption) y el switch de NSFW en Ajustes está
  // apagado — sin esto, elegir esa opción dejaba la pantalla vacía sin
  // ninguna pista de por qué no aparece nada.
  Widget _buildNsfwBlockedMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_adult_content,
                color: HomeTheme.accentPink, size: 40),
            const SizedBox(height: 12),
            Text(
              'extension-searcher.nsfw-blocked'.i18n,
              textAlign: TextAlign.center,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // Bloqueo COMPLETO por actualización pendiente (no un banner arriba de la
  // grilla — eso dejaba las cards visibles y la búsqueda funcionando
  // igual, confirmado en vivo que se podía seguir usando la extensión
  // vieja). Mismo tamaño que el área de contenido normal, para que no
  // "salte" al pasar de bloqueada a cargada tras actualizar.
  Widget _buildUpdateBlockedMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.system_update, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              'extension-searcher.update-available'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _updatingExtension
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.redAccent,
                    ),
                  )
                // PlatformFilledButton (no el FilledButton de Material
                // directo) — este método se comparte entre Android y
                // desktop; un widget de Material sin ancestro Material
                // (desktop corre sobre fluent_ui/FluentApp) es justo el
                // tipo de cosa que ya crasheó antes en este archivo con
                // TextField ("No Material widget found").
                : PlatformFilledButton(
                    onPressed: _performExtensionUpdate,
                    child: Text('extension-repo.upgrade'.i18n),
                  ),
          ],
        ),
      ),
    );
  }

  // Container persistente de "sin resultados" — antes solo había un
  // snackbar transitorio ("no-more-data"/"no-more-data-filtered") que el
  // usuario se podía perder fácil; esto se queda visible mientras la
  // búsqueda/filtro siga sin traer nada.
  // ANIME si el tipo de la extensión cae en videoTypes, MANGA si cae en
  // readingTypes (mismos grupos que ya usan los chips de filtro) — null si
  // no aplica ninguno. "mixed" cae en los dos grupos; ANIME gana ahí por
  // default, no hay forma de saber cuál es sin un detalle puntual.
  AnilistType? get _anilistTypeForExtension {
    final type = _runtime.extension.type;
    if (ExtensionUtils.videoTypes.contains(type)) return AnilistType.anime;
    if (ExtensionUtils.readingTypes.contains(type)) return AnilistType.manga;
    return null;
  }

  bool _tryingAlternateTitle = false;

  // Un solo intento manual (no reintentos en cadena) — sin sesión de
  // AniList esto ni se ofrece (ver _buildNoResultsMessage), así que acá ya
  // se sabe que hay token. No fuerza tolerancia de orden de palabras en el
  // motor de la extensión (no lo controlamos); solo prueba con el título
  // que AniList tiene en otro idioma, por si la extensión lo tiene así.
  Future<void> _tryAlternateTitle() async {
    final type = _anilistTypeForExtension;
    if (type == null || _keyWord.trim().isEmpty) return;
    setState(() => _tryingAlternateTitle = true);
    try {
      final alternates = await AniListProvider.searchAlternateTitles(
        SearchText.sanitizeForRemoteQuery(_keyWord),
        type,
      );
      if (!mounted) return;
      if (alternates.isEmpty) {
        showPlatformSnackbar(
          context: context,
          content: 'extension-searcher.no-alternate-title'.i18n,
          severity: fluent.InfoBarSeverity.warning,
        );
        return;
      }
      _textEditingController.text = alternates.first;
      _onSearch(alternates.first);
    } catch (e) {
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: friendlyError(e),
          severity: fluent.InfoBarSeverity.error,
        );
      }
    } finally {
      if (mounted) setState(() => _tryingAlternateTitle = false);
    }
  }

  Widget _buildNoResultsMessage() {
    // Sin sesión de AniList (o extensión ni anime ni manga) esta parte
    // simplemente no se ofrece — no tiene sentido empujar un login solo
    // para esto, y sin token la llamada fallaría igual.
    final anilistType = _anilistTypeForExtension;
    final showAlternateButton = anilistType != null &&
        _keyWord.trim().isNotEmpty &&
        Get.put(TrackingPageController()).anilistIsLogin.value;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: HomeTheme.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(
              'extension-searcher.no-results'.i18n,
              textAlign: TextAlign.center,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
            ),
            if (showAlternateButton) ...[
              const SizedBox(height: 16),
              _tryingAlternateTitle
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : PlatformFilledButton(
                      onPressed: _tryAlternateTitle,
                      child:
                          Text('extension-searcher.try-alternate-title'.i18n),
                    ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      // Buscador en la AppBar (arriba): el teclado se superpone en vez de
      // encoger el body, si no en horizontal la grilla se queda sin alto y
      // desborda.
      resizeToAvoidBottomInset: false,
      appBar: SearchAppBar(
        // El contador va pegado al nombre porque SearchAppBar recibe un texto,
        // no un widget. Ver _cargados.
        title: _cargados == 0
            ? _runtime.extension.name
            : '${_runtime.extension.name}  ·  $_cargadosTexto',
        // Más alto que el default (kToolbarHeight=56) — pedido explícito
        // de agrandar el buscador. AppBar ya suma el padding de status
        // bar/notch aparte de esto, así que no hay riesgo de SafeArea acá.
        toolbarHeight: 64,
        hintText: _placeholderText(context),
        textEditingController: _textEditingController,
        onChanged: _onSearchFieldChanged,
        onSubmitted: (value) {
          _typedText = '';
          _ghostBase = null;
          _onSearch(value);
        },
        actions: [
          if (_filters != null)
            IconButton(
              tooltip: 'search.filter'.i18n,
              // tune_rounded y no filter_alt: es el que usan Buscar,
              // Extensiones, el repositorio y el Historial. Dos íconos para lo
              // mismo hacen dudar de si hacen lo mismo.
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.tune_rounded),
                  if (_hayFiltroPuesto)
                    const Positioned(
                      right: -1,
                      top: -1,
                      child: _PuntoDeFiltro(),
                    ),
                ],
              ),
              onPressed: () => _onFilter(context),
            ),
        ],
        // Solo si la extensión es mixta (ManhwaWeb, ShadeManga) — una
        // normal no gana UI de más.
        bottom: ExtensionUtils.esMixta(widget.package)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _PestanasNormalAdulto(
                    adulto: _pestanaAdulto,
                    onChanged: _cambiarPestana,
                  ),
                ),
              )
            : null,
      ),
      body: Container(
        color: HomeTheme.bg,
        child: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            // Mientras no se sepa si hace falta actualizar (null) o si SÍ
            // hace falta (true), ni se pide ni se muestra ninguna card —
            // antes esto era solo un banner arriba con la grilla
            // funcionando debajo igual, así que se podía seguir buscando
            // en una extensión desactualizada sin problema.
            if (_hasUpdate == null)
              Center(
                child: CircularProgressIndicator(color: HomeTheme.accentPink),
              )
            else if (_hasUpdate == true)
              _buildUpdateBlockedMessage()
            else ...[
              InfiniteScroller(
                onRefresh: _onRefresh,
                onLoad: _onLoad,
                easyRefreshController: _easyRefreshController,
                child: _nsfwBlocked
                    ? _buildNsfwBlockedMessage()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // El aviso llega cuando se descubre qué forma tienen
                          // las portadas de esta extensión, para rearmar la
                          // grilla con la que corresponde.
                          return ValueListenableBuilder<int>(
                            valueListenable: FormaPortada.revision,
                            builder: (context, _, __) {
                              final rejilla = _rejilla(
                                constraints.maxWidth,
                                relleno: 32,
                                separacion: 16,
                                // En el teléfono el título va encima de la
                                // imagen, así que no ocupa alto propio.
                                altoDelTexto: 0,
                              );
                              return ExcludeSemantics(
                                child: GridView.builder(
                                  // En TV, más aire: la tarjeta enfocada
                                  // crece y le sale su marco, y con 16 justos
                                  // la primera fila y las columnas de los
                                  // extremos quedaban cortadas contra el
                                  // borde del panel.
                                  padding: PlatformTv.esTelevisionSync
                                      ? const EdgeInsets.fromLTRB(
                                          26, 14, 26, 14)
                                      : const EdgeInsets.symmetric(
                                          horizontal: 16),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: rejilla.columnas,
                                    childAspectRatio: rejilla.proporcion,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: _data.length,
                                  itemBuilder: (context, index) {
                                    final item = _data[index];
                                    return ExtensionItemCard(
                                      title: item.title,
                                      url: item.url,
                                      package: widget.package,
                                      cover: item.cover,
                                      update: item.update,
                                      headers: item.headers,
                                      isAdultOption: _adultOptionSelected,
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              if (!_isLoading && !_nsfwBlocked && _data.isEmpty)
                _buildNoResultsMessage(),
            ],
          ],
        ),
      ),
    );
  }

  /// La grilla de tarjetas del escritorio.
  ///
  /// Aparte y no en medio del árbol de widgets: ahí vive a doce niveles de
  /// sangrado y cualquier cambio queda ilegible.
  Widget _grillaEscritorio() {
    const separacion = 12.0;
    const relleno = 8.0;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // El aviso llega cuando se descubre qué forma tienen las portadas de
        // esta extensión, para rearmar la grilla con la que corresponde.
        return ValueListenableBuilder<int>(
          valueListenable: FormaPortada.revision,
          builder: (ctx, _, __) {
            final rejilla = _rejilla(
              constraints.maxWidth,
              relleno: relleno * 2,
              separacion: separacion,
              // Debajo de la portada van el título y, si lo hay, el subtítulo
              // (ver GridItemTile): 8 de separación + 20 + 16.
              altoDelTexto: 44,
            );
            return ExcludeSemantics(
              child: GridView.builder(
                // Ver el mismo caso arriba: en TV la tarjeta enfocada crece
                // y necesita aire para no quedar cortada.
                padding: PlatformTv.esTelevisionSync
                    ? const EdgeInsets.all(relleno + 10)
                    : const EdgeInsets.all(relleno),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: rejilla.columnas,
                  childAspectRatio: rejilla.proporcion,
                  crossAxisSpacing: separacion,
                  mainAxisSpacing: separacion,
                ),
                itemCount: _browseData.length,
                itemBuilder: (ctx, i) {
                  final item = _browseData[i];
                  return ExtensionItemCard(
                    title: item.title,
                    url: item.url,
                    package: widget.package,
                    cover: item.cover,
                    update: item.update,
                    headers: item.headers,
                    isAdultOption: _adultOptionSelected,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Si esta extensión es de vídeo.
  bool get _esDeVideo =>
      ExtensionUtils.videoTypes.contains(_runtime.extension.type);

  /// Cuántas columnas entran y qué proporción tiene cada tarjeta.
  ///
  /// Todas las tarjetas van más grandes que antes: en una pantalla ancha se
  /// veían muchas y diminutas. La forma depende de lo que publique el sitio.
  ///
  /// Un manga o una novela llevan tapa de libro, así que las de lectura son
  /// verticales siempre, sin mirar nada. Las de vídeo, en cambio, dependen del
  /// sitio: unas publican pósters verticales y otras fotogramas apaisados, y
  /// un fotograma 16:9 metido en una tarjeta vertical pierde los costados, que
  /// es justo donde suele estar lo que se quiere ver. Cuál es cuál se averigua
  /// mirando sus propias portadas, sin listas escritas a mano (ver
  /// FormaPortada).
  ///
  /// [altoDelTexto] es lo que ocupa el título debajo de la portada: en el
  /// escritorio va debajo, y en el teléfono va ENCIMA de la imagen, así que
  /// ahí no resta nada.
  ({int columnas, double proporcion}) _rejilla(
    double anchoTotal, {
    required double relleno,
    required double separacion,
    required double altoDelTexto,
  }) {
    final enTelefono = Platform.isAndroid;
    // Se descuenta el relleno: hace falta el ancho REAL de una tarjeta para
    // poder calcular su alto.
    final anchoDisponible = anchoTotal - relleno;

    // La proporción EXACTA de las portadas de este sitio, no una de dos formas
    // fijas. Con dos formas fijas, una portada un poco más angosta que la caja
    // dejaba franjas a los costados, y ahí no hay relleno que quede bien.
    // Midiendo la de verdad, la imagen llena la tarjeta y no sobra nada.
    final proporcionPortada = FormaPortada.paraDibujar(
      widget.package,
      esDeLectura: !_esDeVideo,
    );
    final apaisada = proporcionPortada > 1;
    // Mientras no se sepa qué publica, se usa la vertical: es la de siempre, y
    // si al llegar la primera portada resulta ser otra, se rearma sola.
    //
    // El del teléfono apaisado es 160 y no 180 por un motivo concreto: con 180
    // quedaba UNA tarjeta por fila en un móvil de 392dp y dos en uno de 412,
    // así que la pantalla se veía distinta según el aparato. Con 160 son dos
    // en los dos casos.
    final anchoMinimo =
        apaisada ? (enTelefono ? 160.0 : 300.0) : (enTelefono ? 150.0 : 200.0);

    final columnas =
        ((anchoDisponible + separacion) / (anchoMinimo + separacion))
            .floor()
            .clamp(1, 20);
    final anchoTarjeta =
        (anchoDisponible - separacion * (columnas - 1)) / columnas;
    final altoPortada = anchoTarjeta / proporcionPortada;
    return (
      columnas: columnas,
      proporcion: anchoTarjeta / (altoPortada + altoDelTexto),
    );
  }

  Widget _navButton({required IconData icon, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor:
            onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: HomeTheme.cardSurface.withValues(alpha: 0.9),
            border: Border.all(
              color: onTap == null ? HomeTheme.border : HomeTheme.accentPink,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? HomeTheme.textMuted : HomeTheme.accentPink,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final suffix = Row(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 2.0),
        child: fluent.IconButton(
          icon: const Icon(fluent.FluentIcons.chrome_close, size: 9.0),
          onPressed: () {
            _textEditingController.clear();
            _typedText = '';
            _ghostBase = null;
            _onSearch("");
          },
        ),
      ),
    ]);

    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 3,
                    width: double.infinity,
                    child: LinearProgressIndicator(
                      backgroundColor: HomeTheme.border,
                      valueColor: AlwaysStoppedAnimation(HomeTheme.accentPink),
                    ),
                  ),
                )
              else
                const SizedBox(height: 3),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: HomeTheme.cardSurface,
                  border: Border.all(color: HomeTheme.border),
                  // Sin borderRadius — a propósito, una barra "cuadrada" (bordes
                  // rectos) en vez de la esquina redondeada que se usa en el
                  // resto de las tarjetas.
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              _runtime.extension.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: HomeTheme.textPrimary,
                              ),
                            ),
                          ),
                          // Cuántos títulos hay cargados — ver _cargados. Más
                          // chico y apagado: acompaña al nombre, no compite
                          // con él.
                          if (_cargados > 0) ...[
                            const SizedBox(width: 10),
                            Text(
                              _cargadosTexto,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: HomeTheme.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Buscador/filtro/refrescar solo tienen sentido si de
                    // verdad se puede buscar — mientras haya una
                    // actualización pendiente (o no se sepa todavía) no se
                    // muestran, para que no parezca que se puede seguir
                    // usando la extensión desactualizada.
                    if (_hasUpdate == false) ...[
                      RefreshButton(onTap: () => _goToPage(1)),
                      const SizedBox(width: 8),
                      if (_filters != null) ...[
                        GestureDetector(
                          onTap: () => _onFilter(context),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: HomeTheme.cardSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: HomeTheme.border),
                              ),
                              child: Icon(Icons.filter_alt_rounded,
                                  size: 18, color: HomeTheme.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        // Agrandado (antes 300x40) — pedido explícito.
                        width: 340,
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: HomeTheme.cardSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: HomeTheme.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search,
                                size: 18, color: HomeTheme.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: fluent.TextBox(
                                controller: _textEditingController,
                                decoration: const WidgetStatePropertyAll(
                                    BoxDecoration()),
                                style: TextStyle(
                                    color: HomeTheme.textPrimary, fontSize: 14),
                                placeholderStyle:
                                    TextStyle(color: HomeTheme.textMuted),
                                onChanged: _onSearchFieldChanged,
                                suffix: suffix,
                                suffixMode:
                                    fluent.OverlayVisibilityMode.editing,
                                onSubmitted: (value) {
                                  _typedText = '';
                                  _ghostBase = null;
                                  _onSearch(value);
                                },
                                placeholder: _placeholderText(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Solo si la extensión es mixta (ManhwaWeb, ShadeManga) — una
              // normal no gana UI de más. Separada del ícono de filtros del
              // sitio (arriba, en el mismo header) a propósito: mezclar las
              // dos cosas en un solo diálogo es la queja que motivó esto.
              if (ExtensionUtils.esMixta(widget.package))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: SizedBox(
                    width: 260,
                    child: _PestanasNormalAdulto(
                      adulto: _pestanaAdulto,
                      onChanged: _cambiarPestana,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Grid + flechas prev/next EN SU PROPIA COLUMNA (Row), no
              // flotando encima de la grilla — así nunca se superponen a una
              // tarjeta, sea cual sea el ancho de la ventana.
              Expanded(
                child: _hasUpdate == null
                    ? Center(
                        child: CircularProgressIndicator(
                            color: HomeTheme.accentPink),
                      )
                    : _hasUpdate == true
                        ? _buildUpdateBlockedMessage()
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 44,
                                child: Center(
                                  child: _browsePage > 1
                                      ? _navButton(
                                          icon: Icons.chevron_left,
                                          onTap: _isLoading
                                              ? null
                                              : () =>
                                                  _goToPage(_browsePage - 1),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                              Expanded(
                                child: _nsfwBlocked
                                    ? _buildNsfwBlockedMessage()
                                    // Bloques con la forma de la grilla, no
                                    // una rueda: al llegar las portadas no se
                                    // corre nada. Los mismos números que
                                    // _grillaEscritorio.
                                    : _isLoading && _browseData.isEmpty
                                        ? LayoutBuilder(
                                            builder: (ctx, restricciones) {
                                              final rejilla = _rejilla(
                                                restricciones.maxWidth,
                                                relleno: 32,
                                                separacion: 16,
                                                altoDelTexto: 44,
                                              );
                                              return EsqueletoDeGrilla(
                                                columnas: rejilla.columnas,
                                                proporcion: rejilla.proporcion,
                                                padding:
                                                    const EdgeInsets.all(16),
                                              );
                                            },
                                          )
                                        : (!_isLoading && _browseData.isEmpty)
                                            ? _buildNoResultsMessage()
                                            : _grillaEscritorio(),
                              ),
                              SizedBox(
                                width: 44,
                                child: Center(
                                  child: _navButton(
                                    icon: Icons.chevron_right,
                                    onTap: _isLoading
                                        ? null
                                        : () => _goToPage(_browsePage + 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ExtensionUtils.runtimes[widget.package];
    // Deshabilitada (pero instalada) se trata como inaccesible acá también —
    // antes solo se chequeaba "no instalada", así que buscar dentro de una
    // extensión desactivada desde el toggle igual funcionaba.
    final disabled =
        runtime != null && !ExtensionUtils.isEnabled(widget.package);
    if (runtime == null || disabled) {
      final message = Text(
        FlutterI18n.translate(
          context,
          disabled ? 'common.extension-disabled' : 'common.extension-missing',
          translationParams: {'package': ExtensionUtils.nombreDe(widget.package)},
        ),
      );
      return PlatformWidget(
        androidWidget: Scaffold(body: Center(child: message)),
        desktopWidget: Center(child: message),
      );
    }
    _runtime = runtime;
    // En TV, el teclado en pantalla a la izquierda y el catálogo de la
    // extensión a la derecha — el mismo reparto que el buscador general.
    //
    // El campo de texto de la barra de arriba sigue existiendo y muestra lo
    // que se va escribiendo, pero ya no hace falta enfocarlo: con el mando
    // se escribe acá, sin que el teclado del sistema tape la grilla.
    if (PlatformTv.esTelevisionSync) {
      return Scaffold(
        backgroundColor: HomeTheme.bg,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 0, 16),
                child: TecladoTv(
                  // Sin cartel propio: el texto ya se ve en la barra de
                  // arriba de esta pantalla.
                  mostrarCampo: false,
                  texto: _keyWord,
                  onCambio: (texto) {
                    _typedText = '';
                    _ghostBase = null;
                    _textEditingController.text = texto;
                    _onSearch(texto);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildAndroid(context)),
            ],
          ),
        ),
      );
    }
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}

class _ExtensionFilterWidget extends StatefulWidget {
  const _ExtensionFilterWidget({
    required this.runtime,
    required this.selectedFilters,
    required this.onSelectFilter,
    required this.filters,
    required this.desdeLaZona18,
  });

  /// Si esta pantalla se abrió desde la Zona +18.
  ///
  /// ── Para qué ────────────────────────────────────────────────────────────
  ///
  /// La puerta a contenido para adultos de una extensión es un filtro más del
  /// sitio, así que salía en el panel como cualquier otro: dos opciones y a
  /// elegir. O sea que desde el buscador normal alcanzaba con tocar una para
  /// traer justo lo que esa zona no muestra.
  ///
  /// Que arranque cerrado no basta: lo que hace falta es que ahí no se pueda
  /// abrir. Fuera de la zona, ese filtro no se dibuja y su valor se queda en el
  /// seguro, que es el que la propia extensión declara por defecto.
  ///
  /// Dentro de la zona sí aparece, porque ahí es justamente lo que se fue a
  /// buscar — y esa puerta ya tiene la suya: el PIN y el ajuste general.
  final bool desdeLaZona18;

  final ExtensionService runtime;
  final Map<String, ExtensionFilter> filters;
  final Map<String, List<String>> selectedFilters;
  final Function(
    Map<String, List<String>> selectedFilters,
    Map<String, ExtensionFilter> filters,
  ) onSelectFilter;

  @override
  State<_ExtensionFilterWidget> createState() => _ExtensionFilterWidgetState();
}

class _ExtensionFilterWidgetState extends State<_ExtensionFilterWidget> {
  late final ExtensionService _runtime = widget.runtime;
  late Map<String, ExtensionFilter> _filters = widget.filters;

  /// Los filtros que se dibujan. Ver [_ExtensionFilterWidget.desdeLaZona18].
  ///
  /// Se saca el que abre la puerta a contenido para adultos cuando no se entró
  /// por la Zona +18. Su valor no se toca: queda con el que trae puesto, que es
  /// el seguro.
  /// Una extensión que YA es de adultos de punta a punta.
  ///
  /// Ahí el filtro no es ninguna puerta: todo su catálogo lo es, y esconderlo
  /// solo le saca al usuario una opción legítima —el de censura de HentaiLA,
  /// por ejemplo— sin proteger nada. A esta pantalla no se llega sin haber
  /// pasado antes por la confirmación y el PIN.
  bool get _extensionDeAdultos => _runtime.extension.nsfw;

  List<MapEntry<String, ExtensionFilter>> get _visibles => _filters.entries
      .where((e) =>
          widget.desdeLaZona18 ||
          _extensionDeAdultos ||
          e.value.adultOption == null ||
          e.value.adultOption!.isEmpty)
      .toList();

  /// Si esta OPCIÓN suelta de un filtro es una puerta a contenido adulto.
  ///
  /// ── Por qué no alcanza con esconder el filtro entero ────────────────────
  ///
  /// Porque no todos los sitios tienen un interruptor dedicado. Varios lo
  /// marcan con GÉNEROS: en la lista de TuMangaOnline conviven «Romance» y
  /// «Acción» con «+18», «Adulto», «Erotica» y «Smut», todos como opciones del
  /// mismo filtro. Esconder ese filtro dejaría a la extensión sin géneros; no
  /// esconder nada deja la puerta abierta a un toque de distancia.
  ///
  /// Así que se mira opción por opción, por su ETIQUETA, en español y en
  /// inglés — que es lo que se puede hacer de forma general, sin una lista por
  /// extensión que habría que mantener cada vez que se agrega una.
  ///
  /// Ecchi queda afuera a propósito: es sugerente y no explícito. Es el techo
  /// de lo que puede aparecer fuera de la zona.
  static bool _esOpcionDeAdultos(String etiqueta) {
    final n = etiqueta.toLowerCase().trim();
    const marcas = [
      '+18',
      '18+',
      'adulto',
      'adult',
      'erotic',
      'erótic',
      'smut',
      'hentai',
      'porn',
      'nsfw',
      'explicit',
      'explícit',
      'pornogr',
    ];
    return marcas.any(n.contains);
  }

  /// Las opciones de un filtro que se pueden mostrar acá.
  Map<String, String> _opcionesDe(ExtensionFilter f) {
    if (widget.desdeLaZona18 || _extensionDeAdultos) return f.options;
    return {
      for (final o in f.options.entries)
        if (!_esOpcionDeAdultos(o.value)) o.key: o.value,
    };
  }
  late Map<String, List<String>> _selectedFilters = widget.selectedFilters;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  _onSelectFilter(key, value) async {
    final selectedFilters = Map<String, List<String>>.from(_selectedFilters);
    if (selectedFilters[key]!.contains(value)) {
      if (selectedFilters[key]!.length > _filters[key]!.min) {
        selectedFilters[key]!.remove(value);
      }
    } else {
      if (selectedFilters[key]!.length >= _filters[key]!.max) {
        selectedFilters[key]!.removeAt(0);
      }
      selectedFilters[key]!.add(value);
    }
    final filters = Map<String, ExtensionFilter>.from(
      await _runtime.createFilter(filter: selectedFilters),
    );
    selectedFilters.forEach((key, value) {
      if (!filters.containsKey(key)) {
        selectedFilters.remove(key);
      }
    });
    setState(() {
      _selectedFilters = selectedFilters;
      _filters = filters;
    });
    widget.onSelectFilter(_selectedFilters, _filters);
  }

  // Vuelve cada filtro a su propio valor por defecto — antes había que
  // destildar cada chip a mano (con géneros de sobra, tedioso).
  Future<void> _onReset() async {
    final selectedFilters = <String, List<String>>{
      for (final entry in _filters.entries)
        entry.key: [entry.value.defaultOption],
    };
    final filters = Map<String, ExtensionFilter>.from(
      await _runtime.createFilter(filter: selectedFilters),
    );
    setState(() {
      _selectedFilters = selectedFilters;
      _filters = filters;
    });
    widget.onSelectFilter(_selectedFilters, _filters);
  }

  // Orden alfabético por etiqueta visible — con géneros de sobra (Olympus
  // tiene ~50) quedaban en el orden que devuelve la extensión, medio al
  // azar. "Todos"/"Ver todo" (la opción vacía) siempre va primero.
  List<MapEntry<String, String>> _sortedOptions(Map<String, String> options) {
    final entries = options.entries.toList();
    entries.sort((a, b) {
      if (a.key.isEmpty) return -1;
      if (b.key.isEmpty) return 1;
      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });
    return entries;
  }

  // Píldora propia (no PlatformToggleButton) — mismo lenguaje visual que el
  // resto de la app (chips de tipo en Búsqueda, tabs de Historial): fondo
  // oscuro, borde rosa cuando está seleccionado. PlatformToggleButton usaba
  // el azul por defecto de fluent_ui, que no combinaba con nada más.
  Widget _chip(
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    // En TV el chip tiene que poder enfocarse: con GestureDetector a secas
    // el mando no tenía dónde pararse y los filtros quedaban a la vista pero
    // intocables.
    if (PlatformTv.esTelevisionSync) {
      // Radio 10, el mismo que la pastilla de TV (ver _pastillaChip): con
      // 999 el marco de foco salía redondo alrededor de un bloque de
      // esquinas rectas.
      return FocusableCard(
        borderRadius: 10,
        onTap: onTap,
        child: _pastillaChip(label: label, selected: selected),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: _pastillaChip(label: label, selected: selected),
      ),
    );
  }

  Widget _pastillaChip({required String label, required bool selected}) {
    // ── El chip de TV es otro, no el mismo más grande ───────────────────
    //
    // El de teléfono/escritorio es una cápsula fina con borde: se lee bien
    // de cerca, donde el borde de 1px se distingue. A tres metros ese borde
    // desaparece y lo elegido no se diferencia de lo no elegido.
    //
    // El de TV es un bloque sólido: lo elegido va RELLENO con el acento y
    // texto blanco, lo demás en la superficie de tarjeta. Se distingue de
    // un vistazo, sin depender de una línea de un píxel — y las esquinas
    // menos redondeadas lo separan visualmente de los chips redondos del
    // teléfono, que era el pedido: que en TV se vea distinto, no calcado.
    final tv = PlatformTv.esTelevisionSync;
    if (tv) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? HomeTheme.accentPink : HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : HomeTheme.textPrimary,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? HomeTheme.accentPink.withValues(alpha: 0.18)
            : HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? HomeTheme.accentPink : HomeTheme.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? HomeTheme.accentPink : HomeTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          // En TV es un botón enfocable, no un texto subrayado: con el mando
          // no hay dónde pararse sobre un texto suelto, así que restablecer
          // los filtros era una opción visible pero imposible de usar.
          child: PlatformTv.esTelevisionSync
              ? FocusableCard(
                  borderRadius: 10,
                  onTap: _onReset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: HomeTheme.border),
                    ),
                    child: Text(
                      'search.reset-filters'.i18n,
                      style: TextStyle(
                        color: HomeTheme.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : GestureDetector(
            onTap: _onReset,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                'search.reset-filters'.i18n,
                style: TextStyle(
                  color: HomeTheme.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          // Scrollbar propio con padding a la derecha — sin esto, el thumb
          // por defecto quedaba flotando encima del texto de los chips en
          // vez de al costado (se notaba mucho con géneros de sobra).
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final filter in _visibles) ...[
                    Text(
                      filter.value.title,
                      style: TextStyle(
                        color: HomeTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        // _opcionesDe y no las opciones crudas: fuera de la
                        // Zona +18 se sacan las que abren contenido para
                        // adultos, aunque vivan mezcladas entre los géneros.
                        for (final entry
                            in _sortedOptions(_opcionesDe(filter.value))) ...[
                          _chip(
                            label: entry.value,
                            // _selectedFilters (el estado local, que sí se
                            // actualiza) — no widget.selectedFilters (la
                            // copia congelada de cuando se abrió el
                            // diálogo). Con esa venía el bug real: tocar
                            // un chip o "Restablecer" cambiaba los datos
                            // pero nunca se veía reflejado en pantalla.
                            selected: _selectedFilters[filter.key]!
                                .contains(entry.key),
                            onTap: () async {
                              await _onSelectFilter(filter.key, entry.key);
                            },
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (filter.key != _visibles.last.key)
                      Divider(color: HomeTheme.border, height: 1),
                    const SizedBox(height: 16),
                  ],
                  // Al pie y no arriba: es contexto util, no algo que haga
                  // falta leer antes de elegir. Los filtros salen de
                  // createFilter() de cada extension, asi que una extension
                  // actualizada puede traer opciones nuevas sin que cambie
                  // nada del app — conviene decirlo para que no parezca que
                  // los filtros "cambiaron solos".
                  const _NotaDeFiltros(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Aclaracion al pie del panel de filtros.
class _NotaDeFiltros extends StatelessWidget {
  const _NotaDeFiltros();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: HomeTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'search.filters-note'.i18n,
              style: TextStyle(
                color: HomeTheme.textMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El puntito que avisa que hay un filtro puesto.
///
/// Con nombre y acá porque es el mismo en todas las zonas: nueve puntos, del
/// color de acento, en la esquina del botón.
class _PuntoDeFiltro extends StatelessWidget {
  const _PuntoDeFiltro();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: HomeTheme.accentPink,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// La pestaña Normal/+18 de una extensión mixta.
///
/// Separada a propósito del ícono de filtros del sitio (`tune_rounded`) y
/// nunca mezclada en el mismo diálogo — mezclar las dos cosas es
/// literalmente la queja que motivó esta fase: hoy la puerta a adultos de
/// una extensión mixta vive escondida DENTRO del diálogo de filtros
/// genérico, junto con género y orden.
class _PestanasNormalAdulto extends StatelessWidget {
  const _PestanasNormalAdulto({required this.adulto, required this.onChanged});

  final bool adulto;
  final ValueChanged<bool> onChanged;

  Widget _segmento(String texto, bool valor) {
    final elegido = adulto == valor;
    final acento = valor ? HomeTheme.accentRed : HomeTheme.accentPink;
    return Expanded(
      // FocusableCard y no un GestureDetector a secas: en TV, con
      // GestureDetector no hay nada que el D-pad pueda enfocar, y este
      // control quedaría visible pero intocable con el mando — mismo
      // motivo por el que los chips de filtro del Home lo usan.
      child: FocusableCard(
        borderRadius: 8,
        accent: acento,
        onTap: () => onChanged(valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: elegido ? acento.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(8),
            border: elegido ? Border.all(color: acento) : null,
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: elegido ? acento : HomeTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        children: [
          _segmento('extension-searcher.tab-normal'.i18n, false),
          const SizedBox(width: 4),
          _segmento('extension-searcher.tab-adulto'.i18n, true),
        ],
      ),
    );
  }
}
