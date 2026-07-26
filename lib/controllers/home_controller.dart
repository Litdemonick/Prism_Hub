import 'dart:async';
import 'dart:math';

import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

class HomePageController extends GetxController {
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

  refreshHistory() async {
    // Fetch first, THEN swap — clearing before the await let the "no
    // history" empty state flash on screen for every refresh (including
    // the one that fires on every visit to Home), even when there was
    // data the whole time.
    final data = await DatabaseService.getHistorysByType();
    resents.value = _onlyEnabled(data, (h) => h.package);
  }

  // Refresco manual (deslizar en Android / botón "Actualizar" en PC) — trae
  // Continuar/Favoritos al día. A propósito NO toca heroBackground: la
  // imagen del banner no debe cambiar solo porque el usuario refrescó, eso
  // es trabajo exclusivo de la rotación cada 20s.
  onRefresh() async {
    // Kick off all independent reads before awaiting any — corre todo en
    // paralelo en vez de uno atrás del otro.
    final historyFuture = DatabaseService.getHistorysByType();
    final favoritesFuture = DatabaseService.getFavoritesByType(limit: 20);

    // "Continuar viendo" mezcla todos los tipos (video + lectura) — un solo
    // lugar para retomar donde quedaste, sin separar por tipo.
    final resentsData = _onlyEnabled(await historyFuture, (h) => h.package);
    final favoritesData = _onlyEnabled(await favoritesFuture, (f) => f.package);
    resents.value = resentsData;
    favorites.value = favoritesData;
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
  List<T> _onlyEnabled<T>(List<T> list, String Function(T) packageOf) {
    return list
        .where((e) => ExtensionUtils.enabledRuntimes.containsKey(packageOf(e)))
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
    if (!PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
      exts.removeWhere((element) => element.extension.nsfw);
    }
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

    final results = await Future.wait(exts.map((runtime) async {
      try {
        final items = await runtime.latest(1).timeout(
              const Duration(seconds: 15),
              onTimeout: () =>
                  throw TimeoutException('Tiempo de espera agotado'),
            );
        return items
            .take(3)
            .where((i) => i.cover?.isNotEmpty == true)
            .map((i) => (i.cover!, i.headers))
            .toList();
      } catch (_) {
        return <(String, Map<String, String>?)>[];
      }
    }));
    _extensionPool = results.expand((e) => e).toList();
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
