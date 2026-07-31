import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/resume_history.dart';

class HomePageController extends GetxController {
  // Tag con el que se registra la instancia de la Zona +18 (mismo
  // controller, ver Nsfw18ZonePage) — así ambas instancias conviven sin
  // pisarse: Get.find<HomePageController>() sin tag sigue resolviendo
  // siempre la del Home normal.
  static const zoneTag = 'nsfw18-zone';

  // Refresca la instancia normal Y la de la Zona +18 (si está montada) —
  // usado por los sitios que tocan History/Favorite (detail/video/reader
  // controllers) para que ambas vistas queden al día sin importar desde
  // cuál de las dos se guardó el cambio.
  static Future<void> refreshAll() async {
    await Future.wait(<Future<void>>[
      if (Get.isRegistered<HomePageController>())
        Get.find<HomePageController>().onRefresh(),
      if (Get.isRegistered<HomePageController>(tag: zoneTag))
        Get.find<HomePageController>(tag: zoneTag).onRefresh(),
    ]);
  }

  static Future<void> callRefreshAll() async {
    await Future.wait(<Future<void>>[
      if (Get.isRegistered<HomePageController>())
        Get.find<HomePageController>().callRefresh(),
      if (Get.isRegistered<HomePageController>(tag: zoneTag))
        Get.find<HomePageController>(tag: zoneTag).callRefresh(),
    ]);
  }

  // Zona +18: cuando es true, este controller muestra SOLO lo marcado +18
  // (Continuar/Favoritos/hero rotando con extensiones 100% nsfw) — en vez
  // de duplicar toda la lógica de rotación/pool en una clase aparte.
  final bool nsfwOnly;
  HomePageController({this.nsfwOnly = false});

  final RxList<History> resents = <History>[].obs;
  // All favorited types mixed together (Home shows one "Favoritos" section,
  // not one per type — the History page's Favoritos tab still lets you see
  // where each one came from).
  final RxList<Favorite> favorites = <Favorite>[].obs;

  // Portada real random para el fondo del hero — nunca se fabrica una imagen.
  final Rx<HeroBackground?> heroBackground = Rx(null);

  // Pool de portadas para el hero — lo último (latest(1)) de cada extensión
  // instalada y activa, así el fondo va rotando con contenido real de TUS
  // extensiones (no un catálogo externo).
  List<(String, Map<String, String>?)> _extensionPool = [];
  // Antes de que termine el PRIMER intento de _refreshHeroPool(), el pool
  // está vacío nada más porque todavía no respondió (arranque en frío) — ahí
  // sí conviene mostrar algo temporal (portada de Continuar/Favoritos) en
  // vez de dejar el hero pelado esos primeros segundos. Una vez que el
  // primer intento YA terminó (haya salido bien o mal), un pool vacío
  // significa que de verdad no hay nada disponible (sin internet, todas las
  // extensiones fallaron) — ahí NO hay que caer a ese fallback: esas mismas
  // portadas necesitan la misma red que ya falló, así que se veían pegadas/
  // rotas en vez de "vivas".
  bool _hasLoadedPoolOnce = false;

  // Dos timers con roles distintos:
  // - _poolRefreshTimer: re-descarga lo último de cada extensión (red) — no
  //   hace falta muy seguido, el contenido nuevo no aparece cada segundo.
  // - _rotationTimer: cada 20s elige OTRA imagen del pool YA descargado (sin
  //   red) — esto es lo que hace que el fondo se sienta "vivo" sin esperar
  //   a que termine una descarga.
  Timer? _poolRefreshTimer;
  Timer? _rotationTimer;

  @override
  void onInit() {
    // onRefresh() ya dispara _refreshHeroPool() sola apenas heroBackground
    // esté en null (ver su propio self-heal) — no hace falta duplicar la
    // llamada acá, evita dos fetches de red corriendo en paralelo al abrir.
    onRefresh();
    _poolRefreshTimer = Timer.periodic(
      const Duration(minutes: 20),
      (_) => _refreshHeroPool(),
    );
    _rotationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _pickHeroBackground(),
    );
    super.onInit();
  }

  @override
  void onClose() {
    _poolRefreshTimer?.cancel();
    _rotationTimer?.cancel();
    _coldStartRetry?.cancel();
    super.onClose();
  }

  // Borrar desde el Home, sin tener que entrar al Historial. Viven acá y no en
  // cada página porque el Home normal y la Zona +18 usan ESTE mismo controller
  // (con tag distinto), así que una sola implementación sirve para los dos.
  Future<void> deleteHistory(History h) async {
    await DatabaseService.deleteHistoryByPackageAndUrl(h.package, h.url);
    await refreshHistory();
  }

  Future<void> deleteFavorite(Favorite f) async {
    await DatabaseService.deleteFavorite(f.package, f.url);
    // onRefresh y no refreshHistory: favoritos e historial se releen juntos.
    await onRefresh();
  }

  refreshHistory() async {
    // Fetch first, THEN swap — clearing before the await let the "no
    // history" empty state flash on screen for every refresh (including
    // the one that fires on every visit to Home), even when there was
    // data the whole time.
    final data = await DatabaseService.getHistorysByType();
    resents.value = _onlyEnabled(data, (h) => h.package, (h) => h.isNsfw);
  }

  // Refresco manual (deslizar en Android / botón "Actualizar" en PC) — trae
  // Continuar/Favoritos al día. A propósito NO toca heroBackground: la
  // imagen del banner no debe cambiar solo porque el usuario refrescó, eso
  // es trabajo exclusivo de la rotación cada 20s.
  onRefresh() async {
    // Kick off all independent reads before awaiting any — corre todo en
    // paralelo en vez de uno atrás del otro.
    final historyFuture = DatabaseService.getHistorysByType();
    final favoritesFuture = DatabaseService.getFavoritesByType();

    // "Continuar viendo" mezcla todos los tipos (video + lectura) — un solo
    // lugar para retomar donde quedaste, sin separar por tipo.
    final resentsData =
        _onlyEnabled(await historyFuture, (h) => h.package, (h) => h.isNsfw);
    final favoritesData =
        _onlyEnabled(await favoritesFuture, (f) => f.package, (f) => f.isNsfw);
    resents.value = resentsData;
    favorites.value = favoritesData;
    unawaited(prewarmResumeHistoryTargets(resentsData));
    // Si por lo que sea el hero todavía no tiene nada (primera vez real,
    // el fetch inicial falló, tardó más de la cuenta) lo reintenta acá —
    // pero solo cuando está vacío: si ya hay una imagen puesta, refrescar
    // no la toca (ver comentario de arriba).
    if (heroBackground.value == null) {
      unawaited(_refreshHeroPool());
    }
  }

  // Se llama cuando cambia el set de extensiones habilitadas (activar,
  // desactivar, instalar, desinstalar — ver ExtensionUtils._reloadPage). A
  // diferencia de onRefresh(), acá SÍ hace falta limpiar el hero: si la
  // imagen que se está mostrando justo venía de la extensión que se
  // desactivó, tiene que desaparecer YA, no esperar a la próxima rotación
  // o a que el usuario reabra Home.
  Future<void> callRefresh() async {
    await onRefresh();
    await _refreshHeroPool();
  }

  // Oculta (no borra) historial/favoritos de extensiones desinstaladas o
  // desactivadas — si el usuario la vuelve a activar, vuelven a aparecer
  // solos porque el dato sigue intacto en la base, solo se filtra acá.
  // También separa +18 del resto (isNsfwOf): la instancia normal de Home
  // solo muestra lo NO marcado +18; la instancia de la Zona +18 (nsfwOnly)
  // es exactamente al revés.
  List<T> _onlyEnabled<T>(
    List<T> list,
    String Function(T) packageOf,
    bool Function(T) isNsfwOf,
  ) {
    return list
        .where((e) =>
            ExtensionUtils.enabledRuntimes.containsKey(packageOf(e)) &&
            isNsfwOf(e) == nsfwOnly)
        .toList();
  }

  // History/Favorite solo guardan la URL de la portada, no los headers con
  // los que se cargó la primera vez (esos solo existen en la respuesta viva
  // de latest()/search()/detail(), no se persisten en la base). Algunos
  // sitios (ej. ManhwaWeb) exigen SIEMPRE un Referer = su propio dominio
  // para servir imágenes — sin eso, la portada falla al mostrarla de nuevo
  // en Continuar/Favoritos aunque en el Detalle (que sí pide headers
  // frescos) se vea bien. El sitio de la extensión (webSite del manifest)
  // es un Referer razonable y está disponible al toque, sin red.
  Map<String, String>? headersForPackage(String package) {
    final site = ExtensionUtils.enabledRuntimes[package]?.extension.webSite;
    if (site == null || site.isEmpty) return null;
    return {'Referer': site};
  }

  Future<void> _refreshHeroPool() async {
    final exts = ExtensionUtils.enabledRuntimes.values.toList();
    // Zona +18: el pool del hero sale SOLO de extensiones 100% nsfw — una
    // extensión "mixta" (ej. ShadeManga) no sirve acá porque latest(1)
    // ignora el filtro adulto, así que no hay forma de garantizar que lo
    // que devuelve sea +18.
    //
    // Home normal: SOLO extensiones no-nsfw, sin excepción. Antes esto usaba
    // isNsfwVisibleOutsideZone, que deja pasar las +18 cuando el switch de NSFW
    // está prendido — y así la portada del hero del Home normal podía salir de
    // una extensión +18 (reportado en vivo). El mismo criterio exacto que ya
    // usan las secciones de contenido de más arriba (isNsfwOf(e) == nsfwOnly).
    exts.removeWhere((element) => element.extension.nsfw != nsfwOnly);
    if (exts.isEmpty) {
      _extensionPool = [];
      _hasLoadedPoolOnce = true;
      _pickHeroBackground();
      return;
    }
    // Sin conexión detectada de entrada — evita esperar el timeout de 15s
    // de cada extensión (todas fallarían igual) solo para terminar con el
    // pool vacío de todas formas.
    if (!ConnectivityUtils.isOnline.value) {
      _hasLoadedPoolOnce = true;
      _pickHeroBackground();
      return;
    }

    final results = <(String, Map<String, String>?)>[];
    const batchSize = 2;
    for (var i = 0; i < exts.length; i += batchSize) {
      final batch = exts.skip(i).take(batchSize);
      final batchResults = await Future.wait(batch.map(_fetchHeroItems));
      results.addAll(batchResults.expand((e) => e));
      if (heroBackground.value == null && results.isNotEmpty) {
        _extensionPool = results;
        _pickHeroBackground();
      }
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    _extensionPool = results;
    _hasLoadedPoolOnce = true;
    _pickHeroBackground();
    // Si after todo esto el hero sigue vacío (arranque en frío — DNS/TLS
    // recién calentando, primera request de la sesión más lenta de lo
    // normal — hizo que TODAS las extensiones fallaran/tardaran de más) y
    // no hay retry ya en camino, reintenta una vez solo a los 8s en vez de
    // esperar el próximo ciclo de 20 min o depender de que el usuario
    // refresque a mano.
    if (heroBackground.value == null && _coldStartRetry == null) {
      _coldStartRetry = Timer(const Duration(seconds: 8), () {
        _coldStartRetry = null;
        _refreshHeroPool();
      });
    }
  }

  Timer? _coldStartRetry;

  Future<List<(String, Map<String, String>?)>> _fetchHeroItems(
    ExtensionService runtime,
  ) async {
    try {
      final items = await runtime.latest(1).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('Tiempo de espera agotado'),
          );
      return items
          .take(3)
          .where((i) => i.cover?.isNotEmpty == true)
          .map((i) => (i.cover!, i.headers))
          .toList();
    } catch (_) {
      return <(String, Map<String, String>?)>[];
    }
  }

  void _pickHeroBackground() {
    // Prioriza el pool de tus extensiones (contenido real, elegido al azar
    // entre lo último de cada una). Solo ANTES del primer intento real (ver
    // _hasLoadedPoolOnce) se cae a tus propias portadas (continuar viendo/
    // favoritos) para no dejar el hero pelado esos primeros segundos.
    final pool = _extensionPool.isNotEmpty
        ? _extensionPool
        : (_hasLoadedPoolOnce
            ? const <(String, Map<String, String>?)>[]
            : <(String, Map<String, String>?)>[
                ...resents
                    .where((h) => h.cover?.isNotEmpty == true)
                    .map((h) => (h.cover!, headersForPackage(h.package))),
                ...favorites
                    .where((f) => f.cover?.isNotEmpty == true)
                    .map((f) => (f.cover!, headersForPackage(f.package))),
              ]);
    if (pool.isEmpty) {
      // Ya se intentó de verdad (o no hay extensiones habilitadas) y no hay
      // nada disponible — limpiar en vez de dejar pegada la última imagen:
      // esa portada vieja necesita la misma red que ya falló para volver a
      // cargar, así que quedaba mostrada rota/sin cambiar en vez de "viva".
      heroBackground.value = null;
      return;
    }
    // Excluye la portada actual del sorteo (si hay más de una opción) —
    // sin esto, con pools chicos (2-4 extensiones) el azar repetía la misma
    // imagen seguido y la rotación de 20s parecía no hacer nada.
    var candidates = pool;
    final current = heroBackground.value?.cover;
    if (current != null && pool.length > 1) {
      final filtered = pool.where((p) => p.$1 != current).toList();
      if (filtered.isNotEmpty) candidates = filtered;
    }
    final pick = candidates[Random().nextInt(candidates.length)];
    heroBackground.value = HeroBackground(cover: pick.$1, headers: pick.$2);
  }
}

// Portada elegida al azar para el fondo del hero.
class HeroBackground {
  final String cover;
  final Map<String, String>? headers;
  HeroBackground({required this.cover, required this.headers});
}
