import 'dart:async';
import 'dart:io';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/tracking_page_controller.dart';
import 'package:prismhub/data/providers/anilist_provider.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/refresh_button.dart';
import 'package:prismhub/views/widgets/infinite_scroller.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/search_appbar.dart';

class ExtensionSearcherPage extends fluent.StatefulWidget {
  const ExtensionSearcherPage({
    super.key,
    required this.package,
    this.keyWord,
  });
  final String package;
  final String? keyWord;

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
  void _onSearchFieldChanged(String value) {
    if (_isProgrammaticTextChange) {
      _isProgrammaticTextChange = false;
      if (value.isEmpty) _onSearch(value);
      return;
    }
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
    final lower = value.toLowerCase();
    final match = _sampleTitles.firstWhere(
      (title) =>
          title.length > value.length && title.toLowerCase().startsWith(lower),
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
    _textEditingController.dispose();
    super.dispose();
  }

  _initFilters() async {
    try {
      _filters = await _runtime.createFilter();
      _filters!.forEach((key, value) {
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
                      filter: _selectedFilters)
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
                      filter: _selectedFilters)
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

  _onFilter(BuildContext context) {
    final fiterWidget = _ExtensionFilterWidget(
      runtime: _runtime,
      filters: _filters!,
      selectedFilters: _selectedFilters,
      onSelectFilter: (selectedFilters, filters) {
        _selectedFilters = selectedFilters;
        _filters = filters;
      },
    );

    if (Platform.isAndroid) {
      showModalBottomSheet(
        context: context,
        backgroundColor: HomeTheme.bg,
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
                        style: const TextStyle(color: HomeTheme.textMuted),
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
              const Divider(color: HomeTheme.border),
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
          style: const fluent.ContentDialogThemeData(
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
          title: Text(
            'search.filter'.i18n,
            style: const TextStyle(
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
                    side: const BorderSide(color: HomeTheme.border),
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
            const Icon(Icons.no_adult_content,
                color: HomeTheme.accentPink, size: 40),
            const SizedBox(height: 12),
            Text(
              'extension-searcher.nsfw-blocked'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(color: HomeTheme.textMuted, fontSize: 14),
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
            const Icon(Icons.search_off, color: HomeTheme.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(
              'extension-searcher.no-results'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(color: HomeTheme.textMuted, fontSize: 14),
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
        title: _runtime.extension.name,
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
              icon: const Icon(Icons.filter_alt_rounded),
              onPressed: () => _onFilter(context),
            ),
        ],
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
              const Center(
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
                        builder: (context, constraints) => ExcludeSemantics(
                          child: GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: constraints.maxWidth ~/ 120,
                              childAspectRatio: 0.7,
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
                        ),
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
                  child: const SizedBox(
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
                      child: Text(
                        _runtime.extension.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: HomeTheme.textPrimary,
                        ),
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
                              child: const Icon(Icons.filter_alt_rounded,
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
                            const Icon(Icons.search,
                                size: 18, color: HomeTheme.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: fluent.TextBox(
                                controller: _textEditingController,
                                decoration: const WidgetStatePropertyAll(
                                    BoxDecoration()),
                                style: const TextStyle(
                                    color: HomeTheme.textPrimary, fontSize: 14),
                                placeholderStyle:
                                    const TextStyle(color: HomeTheme.textMuted),
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
              const SizedBox(height: 8),
              // Grid + flechas prev/next EN SU PROPIA COLUMNA (Row), no
              // flotando encima de la grilla — así nunca se superponen a una
              // tarjeta, sea cual sea el ancho de la ventana.
              Expanded(
                child: _hasUpdate == null
                    ? const Center(
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
                                    : _isLoading && _browseData.isEmpty
                                        ? const Center(
                                            child: CircularProgressIndicator(
                                                color: HomeTheme.accentPink),
                                          )
                                        : (!_isLoading && _browseData.isEmpty)
                                            ? _buildNoResultsMessage()
                                            : LayoutBuilder(
                                                builder: (ctx, constraints) =>
                                                    ExcludeSemantics(
                                                  child: GridView.builder(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 8),
                                                    gridDelegate:
                                                        SliverGridDelegateWithFixedCrossAxisCount(
                                                      crossAxisCount:
                                                          (constraints.maxWidth ~/
                                                                  160)
                                                              .clamp(1, 20),
                                                      childAspectRatio: 0.6,
                                                      crossAxisSpacing: 12,
                                                      mainAxisSpacing: 12,
                                                    ),
                                                    itemCount:
                                                        _browseData.length,
                                                    itemBuilder: (ctx, i) {
                                                      final item =
                                                          _browseData[i];
                                                      return ExtensionItemCard(
                                                        title: item.title,
                                                        url: item.url,
                                                        package: widget.package,
                                                        cover: item.cover,
                                                        update: item.update,
                                                        headers: item.headers,
                                                        isAdultOption:
                                                            _adultOptionSelected,
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
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
          translationParams: {'package': widget.package},
        ),
      );
      return PlatformWidget(
        androidWidget: Scaffold(body: Center(child: message)),
        desktopWidget: Center(child: message),
      );
    }
    _runtime = runtime;
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
  });
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
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
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
          child: GestureDetector(
            onTap: _onReset,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                'search.reset-filters'.i18n,
                style: const TextStyle(
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
                  for (final filter in _filters.entries) ...[
                    Text(
                      filter.value.title,
                      style: const TextStyle(
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
                        for (final entry
                            in _sortedOptions(filter.value.options)) ...[
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
                    if (filter.key != _filters.keys.last)
                      const Divider(color: HomeTheme.border, height: 1),
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
          const Icon(Icons.info_outline_rounded,
              size: 16, color: HomeTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'search.filters-note'.i18n,
              style: const TextStyle(
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
