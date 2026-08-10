import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/controllers/extension/extension_repo_controller.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/controllers/settings_controller.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/extension_signature.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/portada_adelantada.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/router/router.dart' show router;
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:path/path.dart' as path;

class ExtensionUtils {
  static Map<String, ExtensionService> runtimes = {};
  static Map<String, String> extensionErrorMap = {};

  // Runtime failures: the extension loaded fine but failed when used (site down,
  // extraction failed, etc.). Surfaced in the UI so the user sees a source is
  // currently not working.
  static Map<String, String> runtimeErrors = {};

  static void reportRuntimeError(String package, String reason) {
    if (package.isEmpty) return;
    runtimeErrors[package] = reason;
    _safeReloadPage();
  }

  static void clearRuntimeError(String package) {
    if (runtimeErrors.remove(package) != null) _safeReloadPage();
  }

  // True if this extension is currently failing (loaded but unusable).
  static bool isFailing(String package) => runtimeErrors.containsKey(package);

  // Caché de versiones publicadas en el índice del repo (package -> version),
  // usada para bloquear el uso de una extensión desactualizada (ver
  // ExtensionTile). TTL corto: evita golpear el repo en cada tile, pero no
  // deja quedar una versión vieja cacheada por toda la sesión.
  static Map<String, String>? _remoteVersionsCache;
  // Packages que el índice remoto marca `unstable` (string "true" en el
  // manifest, igual convención que nsfw) — se llena en el MISMO fetch que
  // _remoteVersionsCache, sin pedir el índice dos veces. Ver hasExtensionUpdate.
  static Map<String, bool>? _remoteUnstableCache;
  // Motivo por el que el índice la marcó inestable — lo setea solo el chequeo
  // de salud de prism-plus (scripts/health-check.mjs) o se pone a mano al
  // subir un arreglo en curso. Valores conocidos: 'site-down' (la página está
  // caída), 'broken' (responde pero no entrega contenido), 'outdated'
  // (necesita actualizarse). Un valor desconocido o ausente cae al aviso
  // genérico de siempre, así que un índice más nuevo nunca rompe un app viejo.
  static Map<String, String>? _remoteUnstableReasonCache;
  static List<dynamic>? _repoIndexCache;
  static DateTime? _repoIndexFetchedAt;
  static Future<List<dynamic>>? _repoIndexInFlight;
  static const _repoIndexTtl = Duration(minutes: 2);
  static StreamSubscription<FileSystemEvent>? _extensionDirWatcher;
  // Dedup de llamadas EN VUELO — el cache de arriba solo evita refetches
  // una vez que YA hay un resultado completo, pero con N extensiones
  // instaladas, sus ExtensionTile montan en el mismo frame y todas llaman
  // hasExtensionUpdate() antes de que la primera termine: sin esto, cada
  // una disparaba su PROPIO dio.get(index.json) en paralelo (confirmado en
  // vivo: 8 pedidos idénticos en menos de 1s con 8 extensiones instaladas).
  static Future<Map<String, String>>? _remoteVersionsInFlight;

  // Invalida el cache de versiones remotas para forzar una consulta fresca.
  // Lo usa el "deslizar para actualizar" de Extensiones instaladas: sin
  // esto, una extensión recién actualizada seguía apareciendo como
  // "actualización requerida" hasta que venciera el TTL de 10 minutos o se
  // reiniciara la app (reportado en vivo con Olympus).
  static void clearRemoteVersionsCache() {
    _remoteVersionsCache = null;
    _remoteUnstableCache = null;
    _repoIndexCache = null;
    _repoIndexFetchedAt = null;
  }

  /// Vuelve a leer el catalogo IGNORANDO la cache, y actualiza de paso las
  /// versiones disponibles y las marcas de inestable.
  ///
  /// Existe porque "Extensiones instaladas" no tenia forma de hacerlo: su
  /// refresco solo releia los mapas que ya estaban en memoria, asi que tocar
  /// Actualizar ahi no cambiaba absolutamente nada en pantalla. Si una
  /// extension dejaba de estar marcada inestable en el repositorio, esa
  /// pantalla lo seguia mostrando hasta que venciera el TTL de 2 minutos por
  /// su cuenta o se reabriera la app.
  static Future<void> refrescarCatalogo() async {
    // cacheBust ademas de forceRefresh: raw.githubusercontent sirve el archivo
    // por CDN y lo cachea unos minutos, asi que sin romper la URL se puede
    // recibir la version vieja aunque el repositorio ya este actualizado.
    await fetchRepoIndex(forceRefresh: true, cacheBust: true);
    await _fetchRemoteVersions();
  }

  static Future<Map<String, String>> _fetchRemoteVersions() async {
    final inFlight = _remoteVersionsInFlight;
    if (inFlight != null) return inFlight;
    final future = _doFetchRemoteVersions();
    _remoteVersionsInFlight = future;
    try {
      return await future;
    } finally {
      _remoteVersionsInFlight = null;
    }
  }

  // Sin TTL propio a propósito — antes tenía uno independiente de 10
  // minutos, separado del TTL de 2 minutos de fetchRepoIndex(). Esto
  // desincronizaba Instaladas vs Repositorio: refrescar el catálogo desde
  // una de las dos páginas no se reflejaba en la otra hasta que venciera
  // por separado (confirmado: "actualización requerida" tardaba hasta 10
  // min en aparecer aunque el repositorio ya mostrara la versión nueva).
  // Ahora reusa el MISMO caché/TTL de fetchRepoIndex, así que ambas
  // pantallas siempre están mirando el mismo índice.
  static Future<Map<String, String>> _doFetchRemoteVersions() async {
    final cached = _remoteVersionsCache;
    try {
      final list = await fetchRepoIndex();
      final map = <String, String>{};
      final unstableMap = <String, bool>{};
      final reasonMap = <String, String>{};
      for (final e in list) {
        final pkg = e['package'] as String?;
        final ver = e['version'] as String?;
        if (pkg != null && ver != null) map[pkg] = ver;
        if (pkg != null) {
          unstableMap[pkg] = e['unstable'] == 'true' || e['unstable'] == true;
          final reason = e['unstableReason'];
          if (reason is String && reason.isNotEmpty) reasonMap[pkg] = reason;
        }
      }
      _remoteVersionsCache = map;
      _remoteUnstableCache = unstableMap;
      _remoteUnstableReasonCache = reasonMap;
      return map;
    } catch (e) {
      // Sin conexión / repo caído: no bloquear extensiones por no poder
      // chequear — devolver la última caché conocida (o vacío).
      return cached ?? {};
    }
  }

  static Future<List<dynamic>> fetchRepoIndex({
    bool forceRefresh = false,
    bool cacheBust = false,
  }) async {
    final cached = _repoIndexCache;
    final fetchedAt = _repoIndexFetchedAt;
    if (!forceRefresh &&
        cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _repoIndexTtl) {
      return cached;
    }
    final inFlight = _repoIndexInFlight;
    if (inFlight != null) return inFlight;

    final future = _doFetchRepoIndex(cacheBust: cacheBust || forceRefresh);
    _repoIndexInFlight = future;
    try {
      return await future;
    } finally {
      _repoIndexInFlight = null;
    }
  }

  static Future<List<dynamic>> _doFetchRepoIndex({
    required bool cacheBust,
  }) async {
    // Con el ajuste en null esto construía "null/index.json" y dio fallaba
    // con "No host specified in URI" — que en pantalla se ve igual que estar
    // sin internet, así que el síntoma no tenía nada que ver con la causa.
    final savedRepoUrl = PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl);
    final repoUrl = savedRepoUrl is String && savedRepoUrl.isNotEmpty
        ? savedRepoUrl
        : PrismHubStorage.defaultRepoUrl;
    final bust = DateTime.now().millisecondsSinceEpoch;
    final url =
        cacheBust ? '$repoUrl/index.json?t=$bust' : '$repoUrl/index.json';
    final res = await dio.get<String>(
      url,
      options: Options(receiveTimeout: const Duration(seconds: 20)),
    );
    // El índice es contenido EXTERNO: viene de un repo público que el usuario
    // puede incluso cambiar por otro en Ajustes. No se asume nada de su forma.
    // Antes, `res.data!` reventaba con una respuesta vacía, y
    // List.from() con un `extensions` que no fuera lista (ej. un número o un
    // objeto) tiraba una excepción que salía de acá — y este método lo llaman
    // varias pantallas sin try, así que un índice roto o manipulado podía
    // dejar el catálogo inusable en vez de simplemente vacío.
    final body = res.data;
    if (body == null || body.isEmpty) return const [];
    final dynamic decoded;
    try {
      decoded = await compute(jsonDecode, body);
    } catch (e) {
      logger.warning('index.json no es JSON válido: $e');
      return const [];
    }
    final list = decoded is Map ? (decoded['extensions'] ?? const []) : decoded;
    if (list is! Iterable) {
      logger.warning('index.json: "extensions" no es una lista');
      return const [];
    }
    final normalized = List<dynamic>.from(list);
    // Contrato app <-> repo. El índice ya publicaba `protocolVersion` desde
    // siempre, pero el app nunca lo miraba: hoy funciona porque nada rompió el
    // contrato todavía, y el día que se rompa habría fallado de forma confusa
    // (extensiones que se instalan y se comportan raro) en vez de decirlo. Esto
    // es lo que hace SEGURO publicar extensiones sin actualizar el app.
    _repoProtocolVersion =
        decoded is Map ? _parseProtocolVersion(decoded['protocolVersion']) : 1;
    _rememberOfficialCatalogEntries(normalized);
    _repoIndexCache = normalized;
    _repoIndexFetchedAt = DateTime.now();
    return normalized;
  }

  // El repo lo escribe como string ("1"), pero se acepta número por si cambia.
  // Si no se entiende, se asume la versión soportada: un índice raro no debería
  // dejar al usuario sin extensiones.
  static int _parseProtocolVersion(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? supportedProtocolVersion;
    return supportedProtocolVersion;
  }

  // Máxima versión del contrato que este app entiende. Se sube a mano cuando se
  // agregue algo al contrato (un tipo de filtro nuevo, un campo nuevo que el
  // app tenga que interpretar), junto con el `protocolVersion` de prism-plus.
  static const int supportedProtocolVersion = 1;
  static int? _repoProtocolVersion;

  // true cuando el repo habla un contrato más nuevo que este app. En ese caso
  // no se rompe nada ni se bloquea el catálogo entero: las extensiones que ya
  // andan siguen andando, pero quien muestre el repositorio puede avisar que
  // conviene actualizar PrismHub para tener todo.
  static bool get repoNeedsNewerApp =>
      (_repoProtocolVersion ?? supportedProtocolVersion) >
      supportedProtocolVersion;

  // Una extensión puede declarar `minProtocol` en su manifest si usa algo que
  // solo entiende un app más nuevo. Se chequea antes de instalar, para decirlo
  // claro en vez de instalarla y que falle raro después.
  static bool entryNeedsNewerApp(Map entry) {
    final raw = entry['minProtocol'];
    final min = raw == null ? 1 : _parseProtocolVersion(raw);
    return min > supportedProtocolVersion;
  }

  static void _rememberOfficialCatalogEntries(List<dynamic> list) {
    for (final e in list) {
      if (e is! Map) continue;
      final pkg = e['package']?.toString();
      if (pkg != null && pkg.isNotEmpty) officialPackages.add(pkg);
      final officialName = e['name']?.toString().toLowerCase().trim();
      if (officialName != null && officialName.isNotEmpty) {
        officialNames.add(officialName);
      }
    }
  }

  // True si el package instalado tiene una versión más nueva en el índice
  // remoto del repo, O si el catálogo remoto la marca `unstable` (ver
  // build.mjs/disabled-extensions) — reutiliza el mismo badge/diálogo
  // bloqueante de "actualización requerida" para una extensión que quedó
  // rota y en espera de que se arregle, sin necesitar UI nueva. Comparación
  // de versión por desigualdad de string (igual que ExtensionCard en el
  // repositorio) — no hay parsing semver hoy.
  /// SOLO compara versiones. Antes devolvía true también cuando el catálogo
  /// marcaba la extensión `unstable`, y eso mezclaba dos cosas que se arreglan
  /// distinto:
  ///
  /// - versión nueva → se soluciona actualizando;
  /// - inestable → NO se soluciona actualizando, porque el problema está del
  ///   otro lado (la página caída, la extensión sin entregar contenido).
  ///
  /// Mezcladas, una extensión marcada inestable con la versión YA al día
  /// mostraba "Actualización requerida" para siempre: al tocar Actualizar se
  /// reinstalaba lo mismo, el motivo real seguía ahí y el botón no se iba
  /// nunca. Pasó en vivo con ShadeManga, TuMangaOnline y VeoHentai, marcadas
  /// por un falso positivo del chequeo de salud.
  ///
  /// El estado inestable se muestra aparte, con su propio aviso y su motivo
  /// (ver [isRemoteUnstable] y [remoteUnstableReason]).
  static Future<bool> hasExtensionUpdate(String package) async {
    final installed = runtimes[package]?.extension.version;
    if (installed == null) return false;
    final remote = await _fetchRemoteVersions();
    final remoteVersion = remote[package];
    return remoteVersion != null && remoteVersion != installed;
  }

  // Igual que hasExtensionUpdate pero devuelve SOLO el motivo "inestable"
  // (no versión) — usado para el badge naranja "Inestable" en ExtensionTile,
  // separado del badge rojo genérico de "actualización requerida". Comparte
  // el mismo caché/TTL, no pega de nuevo al índice.
  /// Igual que [isRemoteUnstable] pero SIN esperar: usa lo que ya haya en
  /// caché. Sirve para filtrar una lista mientras se construye, donde no se
  /// puede await. Si el índice todavía no se descargó devuelve false, y el
  /// filtro se corrige solo en cuanto llega (la página se reconstruye).
  /// Cómo se llama una extensión, para mostrarlo.
  ///
  /// Si está instalada, su nombre. Si no —que es justo cuando hace falta
  /// nombrarla, para decir que falta— se arma uno legible del identificador:
  /// "io.prismhub.shademanga" no le dice nada a nadie, y era lo que salía en
  /// los avisos.
  static String nombreVisible(String package) {
    final puesto = runtimes[package]?.extension.name;
    if (puesto != null && puesto.isNotEmpty) return puesto;
    final ultimo = package.split('.').last;
    if (ultimo.isEmpty) return package;
    return ultimo[0].toUpperCase() + ultimo.substring(1);
  }

  /// Con qué texto abrir la lista de extensiones la próxima vez.
  ///
  /// Sirve para mandar a alguien a UNA extensión concreta: al avisar que falta
  /// instalarla o activarla, el atajo lleva a la pantalla que corresponde y
  /// además la deja buscada, en vez de soltar al usuario en una lista de
  /// decenas para que encuentre a mano la que le nombraron.
  ///
  /// Lo consume la pantalla al abrirse y lo borra, así que vale una sola vez:
  /// entrar después por tu cuenta no tiene por qué venir con un filtro puesto
  /// que nadie pidió.
  static String? filtroPendiente;

  /// Devuelve el filtro pedido y lo borra. Null si no había.
  static String? tomarFiltroPendiente() {
    final f = filtroPendiente;
    filtroPendiente = null;
    return f;
  }

  /// Por qué esta extensión no se puede usar AHORA, o null si se puede.
  ///
  /// Existe porque una extensión puede dejar de estar disponible **en medio de
  /// una sesión**: el usuario la desactiva o la borra desde otra pantalla, o el
  /// catálogo la marca inestable mientras está viendo algo. Hasta ahora eso se
  /// notaba recién al pedir el capítulo siguiente, y salía como un error de red
  /// cualquiera — el usuario reintentaba una y otra vez contra algo que ya no
  /// estaba.
  ///
  /// Devuelve la clave del texto a mostrar, para que el reproductor y el lector
  /// digan exactamente lo mismo.
  static String? motivoNoDisponible(String package) {
    if (!runtimes.containsKey(package)) {
      return 'extension.gone-uninstalled';
    }
    if (!isEnabled(package)) return 'extension.gone-disabled';
    if (isRemoteUnstableCached(package)) return 'extension.gone-unstable';
    return null;
  }

  static bool isRemoteUnstableCached(String package) =>
      _remoteUnstableCache?[package] == true;

  static Future<bool> isRemoteUnstable(String package) async {
    await _fetchRemoteVersions();
    return _remoteUnstableCache?[package] == true;
  }

  // Motivo del "inestable" tal como lo publica el índice, o null si no vino
  // ninguno. Comparte el caché de arriba, no pega de nuevo al índice.
  static Future<String?> remoteUnstableReason(String package) async {
    await _fetchRemoteVersions();
    if (_remoteUnstableCache?[package] != true) return null;
    return _remoteUnstableReasonCache?[package];
  }

  /// Clave i18n del texto LARGO segun el motivo — la misma que resuelve
  /// unstableReasonLabel, pero devuelta sin traducir para los widgets que
  /// reciben una clave en vez de un texto (ver ExtensionCard.blockedReasonKey).
  static String claveMotivoInestable(dynamic reason) {
    switch (reason) {
      case 'site-down':
        return 'extension.unstable-site-down';
      case 'broken':
        return 'extension.unstable-broken';
      case 'outdated':
        return 'extension.unstable-outdated';
      default:
        return 'extension.unstable-blocked';
    }
  }

  /// Texto CORTO para la etiqueta de la tarjeta.
  ///
  /// Antes decia siempre "Inestable", que no distingue un sitio en
  /// mantenimiento —donde no hay nada que hacer salvo esperar— de una
  /// extension rota o de uma que necesita actualizarse. El catalogo ya publica
  /// el motivo, solo faltaba mostrarlo.
  static String etiquetaCortaInestable(String? reason) {
    switch (reason) {
      case 'site-down':
        return 'extension.unstable-short-site-down'.i18n;
      case 'broken':
        return 'extension.unstable-short-broken'.i18n;
      case 'outdated':
        return 'extension.unstable-short-outdated'.i18n;
      default:
        return 'extension.unstable'.i18n;
    }
  }

  /// Motivo publicado por el indice, leido de la cache ya cargada.
  static String? unstableReasonCached(String package) {
    if (_remoteUnstableCache?[package] != true) return null;
    return _remoteUnstableReasonCache?[package];
  }

  // Texto para mostrarle al usuario según el motivo. Un motivo desconocido
  // (índice más nuevo que este app) cae al genérico en vez de mostrar la clave
  // cruda o quedar en blanco.
  static String unstableReasonLabel(String? reason) {
    switch (reason) {
      case 'site-down':
        return 'extension.unstable-site-down'.i18n;
      case 'broken':
        return 'extension.unstable-broken'.i18n;
      case 'outdated':
        return 'extension.unstable-outdated'.i18n;
      default:
        return 'extension.unstable-generic'.i18n;
    }
  }

  // Chequeo compartido de "esta extensión necesita actualizarse" antes de
  // dejar entrar a su contenido — antes este aviso solo vivía en
  // ExtensionTile (Instaladas) y en ExtensionSearcherPage (buscar dentro de
  // una extensión), cada uno con su propia copia del diálogo. Tocar una
  // card desde Home, Zona +18, Favoritos (standalone o dentro de
  // Historial) o la búsqueda general no pasaba por NINGÚN chequeo y
  // entraba directo aunque la extensión estuviera desactualizada.
  // Devuelve true si BLOQUEÓ (ya mostró el aviso, no hay que seguir),
  // false si está todo bien y se puede continuar.
  static Future<bool> blockedByPendingUpdate(
    BuildContext context,
    String package,
  ) async {
    // 1. No instalada / 2. desactivada — se chequean ANTES que la versión,
    // porque en esos casos no tiene sentido hablar de actualizar. Antes esto
    // no estaba acá: tocar una card de una extensión desactivada ABRÍA
    // DetailPage y recién adentro fallaba (detail_controller deja el runtime
    // en null y tira 'common.extension-disabled'), así que el usuario veía la
    // pantalla abrirse y romperse en vez de un aviso claro. Ahora se corta
    // antes de entrar, y como todos los caminos a contenido pasan por esta
    // función, vale igual desde Home, Zona +18, Historial, Favoritos, la
    // búsqueda, "Continuar" y "Ver detalle" del reproductor.
    final installed = runtimes[package];
    if (installed == null) {
      if (!context.mounted) return true;
      showPlatformSnackbar(
        context: context,
        content: FlutterI18n.translate(
          context,
          'common.extension-missing',
          translationParams: {'package': ExtensionUtils.nombreDe(package)},
        ),
        severity: InfoBarSeverity.error,
      );
      return true;
    }
    if (!isEnabled(package)) {
      if (!context.mounted) return true;
      await _showDisabledDialog(context, package);
      return true;
    }

    // 3. Inestable o desactualizada. Se consultan por SEPARADO: desde que
    // hasExtensionUpdate mira solo la versión, el estado inestable hay que
    // pedirlo aparte o una extensión marcada rota dejaría de avisar acá. Las
    // dos siguen bloqueando el contenido, pero el aviso que se muestra —y si
    // se ofrece actualizar— depende de cuál sea.
    final needsUpdate = await hasExtensionUpdate(package);
    if (!context.mounted) return true;
    final reason = await remoteUnstableReason(package);
    if (!context.mounted) return true;
    final isUnstable = reason != null || await isRemoteUnstable(package);
    if (!context.mounted) return true;

    // Inestable YA NO bloquea. Antes cortaba la entrada con un diálogo, y eso
    // dejaba al usuario sin poder ni mirar la ficha de algo que ya tenía en su
    // historial — encima por un motivo que muchas veces es temporal (un sitio
    // caído un rato) o directamente un falso positivo del chequeo de salud,
    // como pasó con ShadeManga, TuMangaOnline y VeoHentai.
    //
    // Ahora se entra normalmente y el aviso se muestra DENTRO del detalle (ver
    // DetailExtensionTile). Si la extensión vuelve a andar, la ficha carga sola
    // sin que el usuario tenga que hacer nada.
    //
    // La versión desactualizada sí sigue cortando: ahí el código instalado
    // puede no entenderse con lo que devuelve el sitio, y actualizar lo
    // arregla de verdad.
    if (!needsUpdate) return false;

    // Actualizar solo se ofrece cuando de verdad puede arreglar algo: si la
    // página está caída o la extensión está rota esperando corrección,
    // reinstalar la misma versión no cambia nada, así que se ofrece solo
    // cerrar en vez de prometer un arreglo que no va a pasar.
    final canFixByUpdating = !isUnstable || reason == 'outdated';

    final update = await showPlatformDialog(
      context: context,
      title: isUnstable
          ? 'extension.unstable-title'.i18n
          : 'extension.update-required'.i18n,
      content: Text(
        isUnstable
            ? unstableReasonLabel(reason)
            : 'extension.update-required-dialog'.i18n,
      ),
      actions: [
        if (canFixByUpdating)
          PlatformTextButton(
            onPressed: () => RouterUtils.pop(false),
            child: Text('common.cancel'.i18n),
          ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(canFixByUpdating),
          child: Text(
            canFixByUpdating
                ? 'extension.update-now'.i18n
                : 'common.understood'.i18n,
          ),
        ),
      ],
    );
    if (update != true || !context.mounted) return true;
    // El botón actualiza ACÁ MISMO en vez de navegar al repositorio. Antes
    // hacía `router.push('/extension_repo')`, que en Android no hace nada
    // (router es go_router, solo se usa en escritorio; en Android el
    // repositorio es una pestaña del shell y además el usuario suele estar
    // YA en la pantalla de extensiones cuando toca esto) — reportado en
    // vivo: "ir a actualizar... pero ya estoy ahí, no hace nada".
    try {
      await updateInstalledFromRepo(package, context);
    } catch (e) {
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          content: friendlyError(e),
          severity: InfoBarSeverity.error,
        );
      }
    }
    return true;
  }

  // Aviso de "extensión desactivada" con acción para ir a activarla. La
  // navegación se ramifica por plataforma porque en Android Extensiones es una
  // pestaña del shell principal (router/go_router solo se usa en escritorio) —
  // mismo criterio que el botón "Ir a Ajustes" de la Zona +18.
  static Future<void> _showDisabledDialog(
    BuildContext context,
    String package,
  ) async {
    final go = await showPlatformDialog(
      context: context,
      title: 'extension.disabled-title'.i18n,
      content: Text('extension.disabled-dialog'.i18n),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('extension.go-to-installed'.i18n),
        ),
      ],
    );
    if (go != true) return;
    if (Platform.isAndroid) {
      Get.find<MainController>().changeTab(MainController.tabExtensiones);
      return;
    }
    router.go('/extension');
  }

  // Momento de la ultima apertura de detalle, para descartar el doble toque.
  static DateTime? _ultimaAperturaDetalle;
  static const _esperaEntreAperturas = Duration(milliseconds: 700);

  // Navegación compartida a DetailPage — antes duplicada (con pequeñas
  // variaciones de copy/paste) en ExtensionItemCard, library_page.dart,
  // nsfw18_zone_page.dart y history_page.dart, ninguna con chequeo de
  // actualización. Ahora todas pasan por acá: si hace falta actualizar,
  // corta con el aviso de blockedByPendingUpdate en vez de entrar.
  static Future<void> openExtensionDetail(
    BuildContext context, {
    required String package,
    required String url,
    bool isAdultOption = false,
    // La portada que la tarjeta tocada ya estaba mostrando, para que la ficha
    // abra con imagen en vez de con un hueco. Opcional: quien no la tenga a
    // mano (una entrada del historial, un enlace compartido) simplemente no la
    // pasa y todo funciona como antes. Ver PortadaAdelantada.
    String? cover,
    Map<String, String>? coverHeaders,
  }) async {
    // Anti doble toque. blockedByPendingUpdate puede tardar (consulta el
    // catalogo), asi que entre el toque y la navegacion hay una ventana en la
    // que un segundo toque entraba igual: se apilaban DOS DetailPage del mismo
    // titulo, cada una con su controller y sus peticiones. Tocar rapido o
    // insistir cuando tarda dejaba la navegacion hecha un desastre.
    //
    // Se usa una marca de tiempo y no un booleano: un booleano que no se
    // libere por una excepcion en el medio dejaria la app sin poder abrir
    // NINGUN detalle hasta reiniciarla.
    final ahora = DateTime.now();
    if (_ultimaAperturaDetalle != null &&
        ahora.difference(_ultimaAperturaDetalle!) < _esperaEntreAperturas) {
      return;
    }
    _ultimaAperturaDetalle = ahora;

    if (await blockedByPendingUpdate(context, package)) return;
    if (!context.mounted) return;
    // Se anota DESPUÉS de las comprobaciones y antes de navegar: si la
    // apertura se corta por una actualización pendiente, no queda nada suelto.
    PortadaAdelantada.anotar(package, url,
        portada: cover, cabeceras: coverHeaders);
    if (Platform.isAndroid) {
      Get.to(DetailPage(
        key: ValueKey('$package|$url'),
        url: url,
        package: package,
        tag: '$package|$url',
        isAdultOption: isAdultOption,
      ));
      return;
    }
    router.push(
      Uri(
        path: '/detail',
        queryParameters: {
          'url': url,
          'package': package,
          if (isAdultOption) 'adult': '1',
        },
      ).toString(),
    );
  }

  // Actualiza una extensión YA instalada bajando la versión del catálogo
  // remoto y reinstalándola — usado por el botón "Actualizar" de
  // ExtensionTile (Extensiones instaladas), para no obligar a navegar al
  // repositorio solo para eso. Misma verificación de firma que ExtensionCard.
  static Future<void> updateInstalledFromRepo(
    String package,
    BuildContext context,
  ) async {
    final bust = DateTime.now().millisecondsSinceEpoch;
    final smallFetch = Options(receiveTimeout: const Duration(seconds: 20));
    final list = await fetchRepoIndex(forceRefresh: true);
    final entry = list.cast<Map>().firstWhere(
          (e) => e['package'] == package,
          orElse: () => {},
        );
    final scriptUrl = (entry['script'] ?? entry['url'])?.toString();
    if (scriptUrl == null) throw Exception('extension.invalid'.i18n);
    final sep = scriptUrl.contains('?') ? '&' : '?';
    final js =
        await dio.get<String>('$scriptUrl${sep}t=$bust', options: smallFetch);
    if (js.data == null || js.data!.isEmpty) {
      throw Exception('extension.invalid'.i18n);
    }
    final signature = entry['signature']?.toString();
    var officialVerified = false;
    if (signature != null && signature.isNotEmpty) {
      if (!ExtensionSignature.isOfficial(js.data!, signature)) {
        throw Exception('extension.invalid-signature'.i18n);
      }
      officialVerified = true;
    }
    // ignore: use_build_context_synchronously
    await installByScript(js.data!, context,
        officialVerified: officialVerified);
  }

  // ─── Extensiones MIXTAS ───────────────────────────────────────────────────
  //
  // Una extensión mixta tiene contenido normal Y contenido +18, separados por
  // un filtro propio del sitio. Hoy son dos: ShadeManga y ManhwaWeb.
  //
  // ── Por qué la marca `nsfw` no alcanza ──────────────────────────────────
  //
  // Porque es binaria, y con ella una extensión solo puede vivir en UNA zona:
  // el buscador normal descarta las `nsfw`, y el de la Zona +18 descarta las
  // que no lo son. Una mixta tiene que estar en las dos — con su contenido
  // normal en una y el de adultos en la otra.
  //
  // ── Por qué no basta con mirar `adultOption` ─────────────────────────────
  //
  // Porque HentaiLA también tiene uno: su filtro de «Censura» usa
  // `adultOption` para marcar la opción sin censurar. Pero HentaiLA es +18 de
  // punta a punta — no tiene nada «normal» que mostrar. Tomar `adultOption`
  // como señal de mixta la habría metido en la zona normal, que es exactamente
  // el error que no se puede cometer.
  //
  // Así que la regla mira las dos cosas: **mixta = el manifiesto dice que NO es
  // +18 entera, Y además tiene un filtro con puerta a adultos**. Una extensión
  // marcada `nsfw: true` no se consulta nunca, así que no hay forma de que se
  // filtre a la zona normal por un `adultOption` usado para otra cosa.
  static final Set<String> _mixtas = {};

  /// Qué paquetes ya se consultaron, y con qué VERSIÓN.
  ///
  /// ── Por qué la versión y no un simple «ya se hizo» ──────────────────────
  ///
  /// Era un booleano de una sola vez por sesión, y nunca se invalidaba. Con eso,
  /// instalar o actualizar una extensión con la app abierta la dejaba sin
  /// clasificar hasta reiniciar — y «sin clasificar» es el peor de los estados
  /// para una que trae las dos cosas: no entra a la zona normal por no estar
  /// reconocida, y tampoco a la Zona +18 por no ser de adultos entera. Se cae de
  /// las dos, y desde afuera parece que la extensión desapareció.
  ///
  /// Pasó en vivo con ManhwaWeb al corregir su manifiesto: la versión nueva ya
  /// venía bien declarada y el app seguía con la respuesta de la anterior.
  ///
  /// Guardando la versión, cada actualización se vuelve a mirar sola y una que
  /// no cambió no cuesta nada: se saltea sin tocar su motor.
  static final Map<String, String> _mixtasVistas = {};

  /// Las que tienen contenido normal y +18 a la vez.
  ///
  /// Vacío hasta que alguien llame a [detectarMixtas]. Devolver vacío es el
  /// lado seguro: la Zona +18 muestra una extensión mixta de menos, que es
  /// mucho mejor que la zona normal mostrando una de más.
  static Set<String> get mixtas => _mixtas;

  static bool esMixta(String package) => _mixtas.contains(package);

  /// El filtro que hay que mandarle a una extensión para pedirle SOLO su
  /// contenido normal.
  ///
  /// ── Por qué vive acá y no en cada pantalla ──────────────────────────────
  ///
  /// Porque son varias las que piden catálogo —el Inicio, el buscador, la
  /// grilla de cada extensión— y la regla tiene que ser una sola. Cada una
  /// armando la suya es cómo se cuela una portada donde no va: alcanza con que
  /// una sola se olvide.
  ///
  /// Sale de la propia extensión: el valor que declara como defecto en el
  /// filtro que abre la puerta a adultos. Y se manda EXPLÍCITO aunque ya sea
  /// su defecto, porque «viene apagado» es una promesa de la extensión y no
  /// una garantía del app: una actualización distraída bastaría para que el
  /// Inicio empiece a mostrar lo que no debe.
  ///
  /// Se llena en [detectarMixtas], que ya le pregunta sus filtros a cada una,
  /// así que no cuesta ninguna llamada de más.
  static Map<String, List<String>>? segurosDe(String package) =>
      _seguros[package];

  /// Lo contrario: el filtro para pedirle su contenido para ADULTOS.
  ///
  /// Es el espejo de [segurosDe] y existe por el mismo motivo. La Zona +18
  /// mostraba el catálogo normal de estas extensiones: al no mandarles nada,
  /// cada una aplicaba su propio defecto —que es el seguro, a propósito— y la
  /// zona terminaba enseñando One Piece y Dragon Ball. Justo lo que esa zona
  /// no es.
  ///
  /// Solo tiene entrada para las que declaran una puerta. Una extensión que ya
  /// es de adultos entera no necesita ninguna: todo lo suyo lo es.
  static Map<String, List<String>>? adultosDe(String package) =>
      _adultos[package];

  static final Map<String, Map<String, List<String>>> _seguros = {};
  static final Map<String, Map<String, List<String>>> _adultos = {};

  /// Averigua cuáles son mixtas. Una sola vez por sesión.
  ///
  /// `createFilter()` corre JavaScript en el motor de cada extensión y ese
  /// motor no es reentrante, así que esto NO se llama al arrancar: lo llama la
  /// pantalla que lo necesita, cuando ya no hay nada más pidiéndole cosas.
  static Future<void> detectarMixtas() async {
    // Una desinstalada no puede seguir contando como nada.
    _mixtas.removeWhere((p) => !runtimes.containsKey(p));
    _mixtasVistas.removeWhere((p, _) => !runtimes.containsKey(p));
    _seguros.removeWhere((p, _) => !runtimes.containsKey(p));
    _adultos.removeWhere((p, _) => !runtimes.containsKey(p));
    for (final e in runtimes.entries) {
      final version = e.value.extension.version;
      // Ya se miró ESTA versión: no se le vuelve a pedir nada al motor.
      if (_mixtasVistas[e.key] == version) continue;
      _mixtasVistas[e.key] = version;
      // Se borra lo que se supiera de la versión anterior: una actualización
      // puede sacar o agregar la puerta, y arrastrar la respuesta vieja sería
      // exactamente el error que esto viene a corregir.
      _mixtas.remove(e.key);
      // Las +18 enteras no se consultan: ver el comentario de arriba.
      if (e.value.extension.nsfw) continue;
      try {
        final filtros =
            await e.value.createFilter().timeout(const Duration(seconds: 8));
        // De paso se anota el valor SEGURO de cada puerta. Ver segurosDe: es
        // el mismo recorrido, así que sale gratis, y deja el dato en un solo
        // lugar para todas las pantallas que piden catálogo.
        final seguros = <String, List<String>>{};
        final adultos = <String, List<String>>{};
        for (final f in filtros.entries) {
          final adulto = f.value.adultOption;
          if (adulto == null || adulto.isEmpty) continue;
          seguros[f.key] = [f.value.defaultOption];
          adultos[f.key] = [adulto];
        }
        if (seguros.isEmpty) {
          _seguros.remove(e.key);
          _adultos.remove(e.key);
        } else {
          _seguros[e.key] = seguros;
          _adultos[e.key] = adultos;
          _mixtas.add(e.key);
        }
      } catch (err) {
        // Si no se pudo saber, se la deja fuera. Una mixta que no aparece en
        // la Zona +18 es un contenido menos; una +18 que aparece en la zona
        // normal es un problema.
        //
        // Y se olvida que se la miró, así que el próximo intento la vuelve a
        // consultar: si falló por un tropiezo puntual —el motor ocupado, un
        // tiempo agotado— no queda mal clasificada para toda la sesión.
        _mixtasVistas.remove(e.key);
        logger.info('[mixtas] ${e.value.extension.name}: $err');
      }
    }
  }

  static String get extensionsDir => path.join(
        PrismHubDirectory.getDirectory,
        'extensions',
      );

  // ─── Vista previa del Home ────────────────────────────────────────────────
  //
  // ── Qué es ──────────────────────────────────────────────────────────────
  //
  // Unas pocas extensiones del catálogo que el usuario NO instaló, cargadas
  // solo para que el Home tenga contenido desde el primer arranque. Con una
  // sola extensión instalada de fábrica, el Home mostraba una fila y nada más.
  //
  // ── Qué NO es ───────────────────────────────────────────────────────────
  //
  // No es instalar. Su guion vive en OTRA carpeta a propósito: cualquier `.js`
  // dentro de `extensionsDir` se considera instalado —hay un escaneo al
  // arrancar y un vigilante de esa carpeta— así que ponerlas ahí las metería
  // en la lista del usuario sin que él lo pidiera.
  //
  // Tampoco aparecen en Extensiones, ni en Buscar, ni resuelven vídeo. Solo
  // llenan filas del Home. Al tocar una tarjeta se ofrece instalarla de
  // verdad, y ahí sí pasa por el camino normal.
  //
  // ── La firma se verifica igual ──────────────────────────────────────────
  //
  // Y sin excepción: acá se ejecuta código que el usuario no eligió, así que
  // es JUSTO donde menos se puede aflojar. Una entrada sin firma, o con firma
  // que no valida, no se previsualiza y punto.
  //
  // ── Cuántas ─────────────────────────────────────────────────────────────
  //
  // Cuatro. Cada una es un motor QuickJS más y un sitio más al que se le pide
  // contenido cada vez que se abre el Home: con las diecisiete sería tráfico y
  // memoria que nadie pidió. Cuatro alcanza para que el Home se vea vivo.
  static const maxVistaPrevia = 4;

  static String get vistaPreviaDir => path.join(
        PrismHubDirectory.getDirectory,
        'vista_previa',
      );

  /// Las que están cargadas como vista previa, por paquete.
  static final Map<String, ExtensionService> vistaPrevia = {};

  static bool esVistaPrevia(String package) => vistaPrevia.containsKey(package);

  static bool _vistaPreviaLista = false;

  /// Baja, verifica y levanta unas pocas extensiones del catálogo.
  ///
  /// Silenciosa por diseño: si no hay red, o el catálogo no contesta, o una
  /// firma no valida, el Home simplemente muestra lo que el usuario tenga.
  /// Nada de esto es un error que valga interrumpir a nadie.
  static Future<void> prepararVistaPrevia() async {
    if (_vistaPreviaLista) return;
    _vistaPreviaLista = true;
    try {
      // ── Lo que importa es cuántas ANDAN, no cuántas hay ────────────────
      //
      // La primera versión miraba si estaba instalada, y eso dejaba fuera el
      // caso más común: el usuario que tiene todo instalado y casi todo
      // APAGADO. Ahí el Home quedaba con una fila y la vista previa no se
      // activaba nunca, porque para ella «ya las tenía».
      //
      // Se cuenta lo que de verdad trae contenido: instalada Y encendida.
      final activas = runtimes.entries
          .where((e) => !e.value.extension.nsfw && isEnabled(e.key))
          .length;
      if (activas >= maxVistaPrevia) return;
      var faltan = maxVistaPrevia - activas;

      // ── Primero las apagadas, que salen gratis ─────────────────────────
      //
      // Están instaladas: su motor YA está cargado en memoria. Mostrar lo que
      // tienen no cuesta ni una descarga ni un motor más — solo pedirles
      // contenido, igual que a cualquier otra.
      for (final e in runtimes.entries) {
        if (faltan <= 0) break;
        if (e.value.extension.nsfw || isEnabled(e.key)) continue;
        vistaPrevia[e.key] = e.value;
        faltan--;
      }
      if (faltan <= 0) return;

      // ── Y si todavía faltan, se bajan del catálogo ─────────────────────
      final catalogo = await fetchRepoIndex();
      final elegidas = <Map>[];
      for (final e in catalogo.cast<Map>()) {
        if (elegidas.length >= faltan) break;
        final pkg = e['package']?.toString();
        if (pkg == null || pkg.isEmpty) continue;
        // Ya la tiene instalada (encendida o apagada): no hay nada que bajar.
        if (runtimes.containsKey(pkg)) continue;
        // Las +18 no entran al Home ni por esta puerta.
        if (e['nsfw'] == true) continue;
        // Sin firma no se ejecuta. Ver el comentario de arriba.
        final firma = e['signature']?.toString();
        if (firma == null || firma.isEmpty) continue;
        elegidas.add(e);
      }
      if (elegidas.isEmpty) return;

      Directory(vistaPreviaDir).createSync(recursive: true);
      for (final e in elegidas) {
        try {
          await _levantarVistaPrevia(e);
        } catch (err) {
          logger.info('[vista previa] ${e['package']} no se pudo cargar: $err');
        }
      }
    } catch (e) {
      logger.info('[vista previa] no se pudo preparar: $e');
    }
  }

  static Future<void> _levantarVistaPrevia(Map entrada) async {
    final pkg = entrada['package'].toString();
    final url = (entrada['script'] ?? entrada['url'])?.toString();
    if (url == null || url.isEmpty) return;

    final js = await dio.get<String>(
      url,
      options: Options(receiveTimeout: const Duration(seconds: 20)),
    );
    final guion = js.data;
    if (guion == null || guion.isEmpty) return;

    // La misma verificación que usa la instalación de verdad.
    if (!ExtensionSignature.isOfficial(
        guion, entrada['signature'].toString())) {
      logger.warning(
          '[vista previa] firma inválida para $pkg — no se carga (posible manipulación).');
      return;
    }

    final archivo = File(path.join(vistaPreviaDir, '$pkg.js'));
    await archivo.writeAsString(guion);

    final ext = parseExtension(guion);
    final servicio = ExtensionService();
    await servicio.initRuntime(ext, rutaGuion: archivo.path);
    vistaPrevia[pkg] = servicio;
  }

  // 已禁用的扩展 (enable/disable). Disabled extensions stay installed but are
  // excluded from search/discovery.
  static List<String> get disabledExtensions =>
      ((PrismHubStorage.getSetting(SettingKey.disabledExtensions) as List?)
          ?.cast<String>()) ??
      <String>[];

  /// El nombre legible de una extensión, a partir de su paquete.
  ///
  /// ── Por qué hace falta ──────────────────────────────────────────────────
  ///
  /// Los avisos de «falta la extensión» y «está deshabilitada» mostraban el
  /// identificador tal cual: «Falta la extensión io.prismhub.tioanime». Eso no
  /// le dice nada a nadie — el usuario conoce «TioAnime», no su paquete.
  ///
  /// Se busca entre las instaladas y, si no está, entre las de vista previa.
  ///
  /// ── Y si tampoco está, en el CATÁLOGO ───────────────────────────────────
  ///
  /// Faltaba justo el caso en el que este método más se usa. El aviso que lo
  /// llama es «falta la extensión», o sea que NO está instalada: los dos
  /// primeros lugares donde se buscaba están vacíos por definición, y salía el
  /// identificador crudo — «Falta la extensión io.prismhub.tioanime».
  /// Reportado en vivo, con captura.
  ///
  /// El catálogo ya está leído en memoria (se usa para el Repositorio y para
  /// las filas del Home), así que buscar ahí no cuesta una petición.
  ///
  /// ── Y si ni el catálogo la conoce ───────────────────────────────────────
  ///
  /// Se arma un nombre a partir del propio paquete —la última parte, con la
  /// primera en mayúscula— en vez de mostrarlo entero. «Tioanime» no es
  /// exactamente su nombre, pero se lee y se entiende de qué habla; el
  /// identificador con puntos no le dice nada a nadie.
  static String nombreDe(String package) {
    final ext = runtimes[package]?.extension ?? vistaPrevia[package]?.extension;
    final nombre = ext?.name.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;

    // Sin forzar red: se mira lo que ya esté leído. Si nunca se bajó el
    // catálogo, se cae al nombre armado, que igual se lee bien.
    for (final e in _repoIndexCache ?? const []) {
      if (e is! Map) continue;
      if (e['package']?.toString() != package) continue;
      final delCatalogo = e['name']?.toString().trim();
      if (delCatalogo != null && delCatalogo.isNotEmpty) return delCatalogo;
    }

    return _nombreDelPaquete(package);
  }

  /// Un nombre presentable sacado del identificador.
  ///
  /// «io.prismhub.tioanime» → «Tioanime». Es lo último que se prueba.
  static String _nombreDelPaquete(String package) {
    final partes = package.split('.').where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return package;
    final ultima = partes.last;
    if (ultima.isEmpty) return package;
    return ultima[0].toUpperCase() + ultima.substring(1);
  }

  static bool isEnabled(String package) =>
      !disabledExtensions.contains(package);

  // Único punto de verdad para "¿se puede ver esta extensión NSFW fuera de
  // la Zona +18?" — antes esta misma condición estaba reimplementada por
  // separado en home_controller, search_controller y
  // extension_repo_controller, cada una con matices ligeramente distintos.
  static bool isNsfwVisibleOutsideZone(bool extensionIsNsfw) =>
      !extensionIsNsfw || PrismHubStorage.getSetting(SettingKey.enableNSFW);

  // Join an extension's webSite with a possibly-relative url, guaranteeing
  // exactly one slash. Extensions are inconsistent: some return '/path', some
  // a bare slug ('foo-bar'), some an absolute URL. Naive `webSite + url`
  // produces broken hosts like 'https://site.comfoo-bar'.
  static String joinWebUrl(String webSite, String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = webSite.endsWith('/')
        ? webSite.substring(0, webSite.length - 1)
        : webSite;
    final path = url.startsWith('/') ? url : '/$url';
    return '$base$path';
  }

  /// Las que quedaron apagadas POR el ajuste de +18, no por decisión del
  /// usuario.
  ///
  /// La diferencia importa: al volver a encender el +18 solo se devuelven
  /// estas. Las que el usuario apagó a mano se quedan como las dejó.
  static List<String> get apagadasPorNsfw {
    final crudo = PrismHubStorage.getSetting(SettingKey.nsfw18AutoDisabled);
    if (crudo is! String || crudo.isEmpty) return <String>[];
    return crudo.split(',').where((p) => p.isNotEmpty).toList();
  }

  static Future<void> setApagadasPorNsfw(List<String> paquetes) =>
      PrismHubStorage.setSetting(
          SettingKey.nsfw18AutoDisabled, paquetes.join(','));

  /// Anota UNA como apagada por el ajuste de +18.
  ///
  /// Hace falta al instalar una extensión +18 con el ajuste apagado: antes se
  /// la desactivaba pero no se la anotaba, así que al encender el +18 no
  /// volvía sola y había que buscarla a mano en Extensiones instaladas, sin
  /// ninguna pista de por qué estaba apagada.
  static Future<void> anotarApagadaPorNsfw(String package) async {
    final lista = apagadasPorNsfw;
    if (lista.contains(package)) return;
    lista.add(package);
    await setApagadasPorNsfw(lista);
  }

  static Future<void> setExtensionEnabled(String package, bool enabled) async {
    final list = disabledExtensions;
    if (enabled) {
      list.remove(package);
    } else if (!list.contains(package)) {
      list.add(package);
    }
    await PrismHubStorage.setSetting(SettingKey.disabledExtensions, list);
    // _pedirReload y no _reloadPage: esto se llama UNA VEZ POR EXTENSIÓN desde
    // «activar todas», y recargar el app entero diecisiete veces seguidas lo
    // dejaba sin responder.
    _pedirReload();
  }

  /// Prende o apaga VARIAS de una sola vez.
  ///
  /// [setExtensionEnabled] lee la lista entera de desactivadas, la modifica y
  /// la vuelve a escribir. Llamarlo en un bucle son diecisiete lecturas y
  /// diecisiete escrituras del mismo dato, más diecisiete pedidos de recarga.
  /// Acá se arma la lista final una vez, se escribe una vez y se recarga una
  /// vez.
  ///
  /// Devuelve cuántas cambiaron de verdad: las que ya estaban como se pedía no
  /// cuentan.
  static Future<int> setExtensionsEnabled(
    Iterable<String> packages,
    bool enabled,
  ) async {
    // Copia y no la lista que devuelve el getter: esa viene de un `cast`, que
    // es una VISTA sobre la guardada. Modificarla en el lugar cambia el dato
    // antes de escribirlo, y si algo falla en el medio queda a mitad de camino
    // sin haberse guardado nunca.
    final lista = List<String>.from(disabledExtensions);
    var cambiadas = 0;
    for (final package in packages) {
      if (enabled) {
        if (lista.remove(package)) cambiadas++;
      } else if (!lista.contains(package)) {
        lista.add(package);
        cambiadas++;
      }
    }
    if (cambiadas == 0) return 0;
    await PrismHubStorage.setSetting(SettingKey.disabledExtensions, lista);
    _pedirReload();
    return cambiadas;
  }

  // Only enabled runtimes — used for search/discovery so disabled sources hide.
  static Map<String, ExtensionService> get enabledRuntimes =>
      Map.fromEntries(runtimes.entries.where(
        // Tambien se excluyen las INESTABLES, no solo las desactivadas.
        //
        // Este getter es el unico punto por el que pasan Buscar, Inicio y el
        // descubrimiento en general, asi que filtrar aca las saca de todas las
        // zonas de una. Antes una inestable que ya estuviera activada seguia
        // consultandose: devolvia listas vacias o a medias, y el usuario solo
        // se enteraba al tocar un item y ver el aviso.
        //
        // Se usa la version CACHEADA (no la async) porque esto se lee dentro de
        // builds. Si el catalogo todavia no se leyo, no excluye a nadie — el
        // aviso por item sigue estando como red de seguridad.
        (e) => isEnabled(e.key) && !isRemoteUnstableCached(e.key),
      ));

  // Extensiones que se auto-instalan en el primer launch.
  // Solo las publicadas en prism+ index.json; añadir aquí solo cuando ya
  // exista la entrada firmada en el catálogo.
  static const Set<String> defaultPackages = {
    'io.prismhub.jkanime', // anime ES — múltiples servidores confiables
    // Las demás extensiones oficiales (manhwaweb, shademanga, etc.) ya NO se
    // auto-instalan: el usuario debe instalarlas y activarlas a mano desde
    // el repositorio (varias tienen contenido +18, ver nsfw gating en
    // ExtensionCard/ExtensionTile).
  };

  // Todos los paquetes oficiales de prism+. Bloqueados de instalar externamente
  // si colisionan con el nombre — se prefiere siempre la build oficial.
  static const Set<String> nativePackages = {
    ...defaultPackages,
    // Nuevas extensiones se agregan aquí una vez publicadas y firmadas en prism+.
  };

  // Extensiones que se eliminaron del catálogo y deben borrarse del dispositivo
  // incluso sin conexión. Añadir aquí cualquier package que se retire de prism+.
  //
  // ── Y sacar de acá el que VUELVA ────────────────────────────────────────
  //
  // Esta lista borra el archivo en CADA arranque, así que un paquete que
  // vuelva al catálogo se sigue borrando aunque se instale bien. Pasó con
  // MangaDex: hubo un intento viejo que se retiró por no estar firmado, quedó
  // anotado acá, y al publicarla de nuevo —firmada y en el catálogo— el
  // usuario la instalaba, funcionaba, cerraba la app y al volver ya no estaba.
  //
  // Desde afuera se ve como que «se desinstala sola», que es de los fallos más
  // desconcertantes que puede haber: no hay error, no hay aviso, y volver a
  // instalarla parece funcionar hasta el siguiente arranque.
  //
  // Vacía a propósito. Si mañana se retira alguna, se agrega — y si vuelve, lo
  // primero es sacarla de acá.
  static const Set<String> _removedPackages = <String>{};

  // Catálogo oficial vivo: se llena desde el index.json de prism+ en cada
  // arranque. Permite bloquear el sideload de CUALQUIER extensión oficial
  // (por package o por nombre), no solo las 3 hardcodeadas, a medida que prism+
  // crece. Una oficial solo se instala por el canal firmado del catálogo.
  static final Set<String> officialPackages = {};
  static final Set<String> officialNames = {};

  static bool isNativePackage(String package) =>
      nativePackages.contains(package) || officialPackages.contains(package);

  // Único lugar con esta validación — antes solo corría dentro de
  // _saveAndInit (instalación vía UI/URL). installByPath() (usado al
  // arrancar y por el file watcher cuando aparece/cambia un .js en la
  // carpeta) tomaba ext.package sin este chequeo y lo usaba tal cual para
  // construir rutas de archivo (extension_service.dart, request.dart) — un
  // .js puesto ahí por cualquier vía que no sea el instalador (arrastrar y
  // soltar, carpeta sincronizada, ZIP extraído) con un @package
  // "../../../algo" evadía el traversal check.
  static final RegExp _validPackagePattern = RegExp(r'^[a-zA-Z0-9._-]+$');
  static bool isValidPackage(String pkg) =>
      pkg.isNotEmpty && _validPackagePattern.hasMatch(pkg);

  static final RegExp _versionHeader = RegExp(r'@version\s+([^\s\r\n]+)');

  static String? _scriptVersion(String script) =>
      _versionHeader.firstMatch(script)?.group(1)?.replaceFirst('v', '').trim();

  // Sync prism+ native default extensions from the repo on every launch:
  //  - first run: install the curated natives so they appear ready to use
  //  - later: re-download a native if the repo has a newer version (so fixes
  //    to resolvers/scrapers reach the app without reinstalling by hand)
  //  - respects user removals: a native the user deleted is not re-added
  // prism+ stays the single source of truth (no bundled copies). Offline-safe.
  static Future<void> _installDefaultsFromRepo() async {
    try {
      // Cache-bust: GitHub raw caches index.json/dist for minutes, which would
      // hide a freshly pushed extension/resolver fix.
      final bust = DateTime.now().millisecondsSinceEpoch;
      // receiveTimeout acá (no global en dio): esto es JSON/JS chico, así que
      // en una red restrictiva (universidad, etc.) preferimos fallar rápido
      // y reintentar en el próximo arranque, en vez de quedar colgados.
      final smallFetch = Options(receiveTimeout: const Duration(seconds: 20));
      final list = await fetchRepoIndex(forceRefresh: true);
      for (final e in list) {
        final pkg = e['package']?.toString();
        if (pkg == null) continue;
        // Registrar TODA extensión del catálogo oficial (no solo las default,
        // e incluso una marcada `unstable` sin script real todavía — ej.
        // LaMovie en disabled-extensions/) para bloquear sideloads que
        // dupliquen su nombre/package.
        officialPackages.add(pkg);
        final officialName = e['name']?.toString().toLowerCase().trim();
        if (officialName != null && officialName.isNotEmpty) {
          officialNames.add(officialName);
        }
        final scriptUrl = (e['script'] ?? e['url'])?.toString();
        // Solo los paquetes por defecto se auto-instalan en primer launch, y
        // solo si de verdad traen un bundle (una unstable sin script no se
        // auto-instala nunca). Los demás nativos están disponibles en el
        // catálogo del repo para instalar a mano.
        if (scriptUrl == null || !defaultPackages.contains(pkg)) continue;

        final dest = File(path.join(extensionsDir, '$pkg.js'));
        final exists = await dest.exists();
        // Los 3 defaults se garantizan siempre presentes: si falta uno (p.ej.
        // cambió el set de defaults tras el primer arranque), se instala. Así el
        // equipo siempre tiene exactamente las 3 oficiales por defecto.
        // Already installed: only re-download when the repo version is different.
        if (exists) {
          final repoVersion = e['version']?.toString().replaceFirst('v', '');
          final localVersion = _scriptVersion(await dest.readAsString());
          if (repoVersion == null || repoVersion == localVersion) continue;
        }
        final sep = scriptUrl.contains('?') ? '&' : '?';
        final js = await dio.get<String>('$scriptUrl${sep}t=$bust',
            options: smallFetch);
        if (js.data != null && js.data!.isNotEmpty) {
          // Seguridad: los defaults son oficiales y DEBEN traer firma válida de
          // prism+. Si falta o no valida, es manipulación → no se instala.
          final signature = e['signature']?.toString();
          if (!ExtensionSignature.isOfficial(js.data!, signature)) {
            debugPrint(
                'Firma inválida o ausente para $pkg — no se instala (posible manipulación).');
            continue;
          }
          await dest.writeAsString(js.data!);
        }
      }
      await PrismHubStorage.setSetting(
          SettingKey.defaultExtensionsInstalled, true);

      // Purga de oficiales huérfanas: una extensión del namespace oficial
      // `io.prismhub.*` que ya NO está en el catálogo de prism+ (la quitamos del
      // repo, p.ej. animeflv) se elimina del equipo. NO toca extensiones externas
      // de terceros (otro namespace) — prism_hub permite sideload. Solo corre si
      // el catálogo se descargó bien (officialPackages no vacío), para no borrar
      // nada estando offline.
      if (officialPackages.isNotEmpty) {
        await for (final f in Directory(extensionsDir).list()) {
          if (path.extension(f.path) != '.js') continue;
          final pkg = path.basenameWithoutExtension(f.path);
          if (pkg.startsWith('io.prismhub.') &&
              !officialPackages.contains(pkg) &&
              !nativePackages.contains(pkg)) {
            try {
              await File(f.path).delete();
              runtimes.remove(pkg);
              debugPrint('Extensión oficial huérfana eliminada: $pkg');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      // Offline / repo unreachable — keep working with what's installed and
      // retry next launch (the first-run flag stays unset until it succeeds).
      debugPrint('No se pudieron sincronizar las extensiones por defecto: $e');
    }
  }

  // 初始化扩展
  static ensureInitialized() async {
    // 创建目录
    Directory(extensionsDir).createSync(recursive: true);
    // Purga offline de paquetes retirados: se elimina el JS aunque no haya red,
    // así el usuario no ve extensiones obsoletas al abrir la app.
    await _purgeRemovedPackages();
    // Descarga defaults (I/O, no bloquea el isolate).
    await _installDefaultsFromRepo();
    // Limpia el Hive disabled-list de entradas muertas (paquetes sin JS).
    await _cleanStaleDisabledList();
    // 监听目录变化
    await _extensionDirWatcher?.cancel();
    _extensionDirWatcher =
        Directory(extensionsDir).watch().listen((event) async {
      if (path.extension(event.path) == '.js') {
        final package = path.basenameWithoutExtension(event.path);
        debugPrint('extension event: ${event.path} ${event.type}');
        switch (event.type) {
          case FileSystemEvent.delete:
            runtimes.remove(package);
            extensionErrorMap.remove(event.path);
            _recargarConCalma();
            break;
          case FileSystemEvent.create:
          case FileSystemEvent.modify:
            if (_loading.contains(package)) break;
            _reinstalarConCalma(package, event.path);
            break;
        }
      }
    });
    // Carga secuencial con yields: se espera a que terminen para que el
    // splash oculte la carga de extensiones (en vez de que jankeen la UI
    // después). El yield entre cada una permite que la animación del splash
    // se renderice sin congelarse 800ms seguidos.
    await _loadExtensions();
    // Recién ahora runtimes está poblado — necesario para saber qué
    // packages son nsfw:true.
    await _migrateNsfwHistoryFavorites();
  }

  /// Relojes por paquete, para no reinstalar la misma extensión cinco veces.
  static final Map<String, Timer> _relojesDeArchivo = {};

  /// Reinstala una extensión que cambió en disco, agrupando los avisos.
  ///
  /// ── El problema medido ──────────────────────────────────────────────────
  ///
  /// El sistema de archivos no manda UN aviso por escritura: manda varios. En
  /// el registro de Android se ven **tres `modify` por extensión**, uno detrás
  /// del otro. Y cada uno hacía el trabajo completo: sacar el motor, volver a
  /// instalar el guion —que arranca un intérprete de JavaScript nuevo— y
  /// recargar la pantalla.
  ///
  /// Con una extensión no se nota. Al tocar «Activar todas» son diecisiete, o
  /// sea unas cincuenta reinstalaciones y cincuenta recargas de pantalla
  /// encimadas. Eso es lo que se sintió como que la app se trababa al volver al
  /// Home y desplazarse: no era el Home, era el intérprete arrancando cincuenta
  /// veces mientras se dibujaba.
  ///
  /// Con un reloj corto por paquete, los tres avisos de la misma extensión se
  /// vuelven uno. Trescientos milisegundos alcanzan de sobra —los tres llegan
  /// en el mismo instante— y no se siente como demora: instalar ya tardaba más
  /// que eso.
  static void _reinstalarConCalma(String package, String ruta) {
    _relojesDeArchivo[package]?.cancel();
    _relojesDeArchivo[package] =
        Timer(const Duration(milliseconds: 300), () async {
      _relojesDeArchivo.remove(package);
      if (_loading.contains(package)) return;
      runtimes.remove(package);
      extensionErrorMap.remove(ruta);
      try {
        await installByPath(ruta);
      } catch (e) {
        // Una que falle no puede dejar el vigilante roto para las demás.
        logger.info('[extensiones] no se pudo reinstalar $package: $e');
      }
      _recargarConCalma();
    });
  }

  /// Un solo reloj para la recarga de pantalla.
  static Timer? _relojDeRecarga;

  /// Recarga la pantalla UNA vez, aunque cambien diecisiete extensiones.
  ///
  /// Cada `_safeReloadPage` rearma el Home entero. Diecisiete seguidas es
  /// diecisiete veces el mismo trabajo, y solo la última sirve.
  static void _recargarConCalma() {
    _relojDeRecarga?.cancel();
    _relojDeRecarga = Timer(const Duration(milliseconds: 400), () {
      _relojDeRecarga = null;
      _safeReloadPage();
    });
  }

  // Ver DatabaseService.markNsfwByPackages: marca retroactivamente el
  // History/Favorite ya guardado de una extensión 100% nsfw SIN partición
  // segura/+18 (osea, TODO lo que devuelve es +18 — no hay filtro
  // adultOption que separe algo "normal" dentro de ella). Para una
  // extensión MIXTA (ShadeManga, ManhwaWeb: tienen contenido normal Y +18,
  // separados por un filtro con adultOption) no se puede migrar en bloque:
  // el History/Favorite guardado ANTES de este campo no registró si vino
  // de la sección +18 o de la normal, así que no hay forma de saber cuál
  // ítem viejo es cuál — se deja tal cual (sigue en Continuar/Favoritos
  // normal) en vez de arriesgarse a mover contenido normal a la Zona +18
  // por error. Solo lo NUEVO (a partir de esta versión) separa bien.
  // Corre una sola vez por instalación (flag en Hive).
  static Future<void> _migrateNsfwHistoryFavorites() async {
    if (PrismHubStorage.getSetting(SettingKey.nsfw18RetroactiveMigrationDone) ==
        true) {
      return;
    }
    try {
      final fullyAdultPackages = <String>{};
      for (final entry in runtimes.entries) {
        if (!entry.value.extension.nsfw) continue;
        var hasAdultPartition = false;
        try {
          final filters = await entry.value.createFilter();
          hasAdultPartition = filters.values.any((f) => f.adultOption != null);
        } catch (_) {
          // No se pudo determinar (createFilter falló) — más seguro asumir
          // que SÍ podría tener partición y no migrarla en bloque.
          hasAdultPartition = true;
        }
        if (!hasAdultPartition) fullyAdultPackages.add(entry.key);
      }
      await DatabaseService.markNsfwByPackages(fullyAdultPackages);
    } catch (e) {
      debugPrint('ERROR: migración retroactiva de NSFW falló: $e');
    }
    await PrismHubStorage.setSetting(
        SettingKey.nsfw18RetroactiveMigrationDone, true);
  }

  static _loadExtensions() async {
    final d = Directory(extensionsDir);
    if (!await d.exists()) return;
    final extensionsList =
        await d.list().where((e) => path.extension(e.path) == '.js').toList();
    extensionsList.sort((a, b) => a.path.compareTo(b.path));
    // Secuencial con yield entre cada una: Future.wait no acelera porque
    // initRuntime es CPU-bound (QuickJS) — bloquea el isolate entero.
    // El yield permite al UI renderizar frames entre extensiones.
    // Se salta archivos que no son .js (cachés, temporales, etc.).
    for (final e in extensionsList) {
      await installByPath(e.path);
      await cederElCuadro();
    }
    _pedirReload();
  }

  /// Le deja un cuadro al dibujado antes de seguir.
  ///
  /// `initRuntime` es trabajo de CPU (QuickJS) y bloquea el isolate ENTERO
  /// mientras corre. Encadenando extensiones sin soltar, la pantalla no dibuja
  /// un solo cuadro de punta a punta: no se mueve la rueda, no responden los
  /// botones y parece que el app se colgó. Reportado en vivo con las acciones
  /// masivas.
  ///
  /// Público a propósito: lo necesita cualquier bucle que instale, actualice o
  /// desinstale de a varias, no solo la carga inicial.
  static Future<void> cederElCuadro() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }

  /// Instala una extensión a partir de su entrada del catálogo.
  ///
  /// ── Por qué existe aparte de la tarjeta ─────────────────────────────────
  ///
  /// Instalar era algo que solo sabía hacer `ExtensionCard`, y solo de a una:
  /// la lógica —bajar, verificar la firma, reintentar con el catálogo fresco,
  /// ponerle el encabezado si le falta— vivía dentro del estado del widget.
  /// «Instalar todas» necesita eso mismo sin una tarjeta que lo envuelva.
  ///
  /// La tarjeta sigue con su propio camino, que además pregunta por el +18 y
  /// pinta la rueda. Acá no se pregunta nada: en una acción masiva un diálogo
  /// por extensión sería insoportable, así que las +18 se instalan APAGADAS si
  /// el interruptor general está apagado — el mismo criterio que ya usaba la
  /// tarjeta cuando no podía preguntar.
  ///
  /// Devuelve true si quedó instalada. Los errores se registran y se devuelven
  /// como false: en una tanda, una que falle no puede cortar a las demás.
  static Future<bool> instalarDesdeCatalogo(
    Map entrada,
    BuildContext context,
  ) async {
    final package = entrada['package']?.toString();
    if (package == null || package.isEmpty) return false;
    try {
      final baseUrl = (entrada['script'] ?? entrada['url'])?.toString() ??
          '${PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl)}'
              '/repo/$package.js';
      // Igual que en la tarjeta: GitHub cachea el .js unos minutos y sin esto
      // se podría instalar la versión anterior recién publicada.
      final sep = baseUrl.contains('?') ? '&' : '?';
      final res = await dio.get<String>(
        '$baseUrl${sep}t=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      var script = res.data;
      if (script == null || script.isEmpty) return false;

      final firma = entrada['signature']?.toString();
      var oficial = false;
      if (firma != null && firma.isNotEmpty) {
        if (!ExtensionSignature.isOfficial(script, firma)) {
          // Puede ser el caché del catálogo, no manipulación: se baja de nuevo
          // forzado y se reintenta una vez. Ver el detalle en ExtensionCard.
          final frescos = await _scriptConCatalogoFresco(package);
          if (frescos == null) {
            logger.warning('[extensiones] $package: firma inválida, no se '
                'instala en la tanda');
            return false;
          }
          script = frescos;
        }
        oficial = true;
      }

      if (!script.contains('==PrismHubExtension==') &&
          !script.contains('==MiruExtension==') &&
          !script.contains('@package')) {
        final tipo = (entrada['type'] ?? 'bangumi').toString();
        final cabecera = '// ==PrismHubExtension==\n'
            '// @name         ${entrada['name'] ?? package}\n'
            '// @version      ${entrada['version'] ?? '1.0.0'}\n'
            '// @author       PrismPlus\n'
            '// @lang         ${entrada['lang'] ?? 'all'}\n'
            '// @license      ${entrada['license'] ?? 'MIT'}\n'
            '// @icon         ${entrada['icon'] ?? ''}\n'
            '// @package      $package\n'
            '// @type         $tipo\n'
            '// @nsfw         ${entrada['nsfw'] ?? false}\n'
            '// @webSite      ${entrada['webSite'] ?? ''}\n'
            '// @description  ${entrada['description'] ?? entrada['name'] ?? package}\n'
            '// ==/PrismHubExtension==\n\n';
        script = '$cabecera$script';
      }

      if (!context.mounted) return false;
      await installByScript(script, context, officialVerified: oficial);
      if (runtimes[package] == null) return false;

      final esNsfw = entrada['nsfw'] == true || entrada['nsfw'] == 'true';
      if (esNsfw && !isNsfwVisibleOutsideZone(true)) {
        await setExtensionEnabled(package, false);
        // Se anota para que vuelva sola al encender el interruptor de +18.
        await anotarApagadaPorNsfw(package);
      }
      return true;
    } catch (e) {
      logger.warning('[extensiones] no se pudo instalar $package: $e');
      return false;
    }
  }

  /// El script de un paquete, bajando el catálogo de nuevo y forzado.
  ///
  /// Devuelve null si tampoco valida con el catálogo fresco: ahí sí hay que
  /// rechazarlo. Es la versión sin widget de lo que hace ExtensionCard.
  static Future<String?> _scriptConCatalogoFresco(String package) async {
    try {
      final lista = await fetchRepoIndex(forceRefresh: true, cacheBust: true);
      final entrada = lista.firstWhere(
        (e) => e is Map && e['package']?.toString() == package,
        orElse: () => null,
      );
      if (entrada is! Map) return null;
      final firma = entrada['signature']?.toString();
      final direccion = (entrada['script'] ?? entrada['url'])?.toString();
      if (firma == null || firma.isEmpty || direccion == null) return null;

      final sep = direccion.contains('?') ? '&' : '?';
      final res = await dio.get<String>(
        '$direccion${sep}t=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      final script = res.data;
      if (script == null || script.isEmpty) return null;
      if (!ExtensionSignature.isOfficial(script, firma)) return null;
      return script;
    } catch (e) {
      logger.warning('[extensiones] no se pudo reintentar con el catálogo '
          'fresco para $package: $e');
      return null;
    }
  }

  static uninstall(String package) async {
    final file = File(path.join(extensionsDir, '$package.js'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Borra sin necesidad de red los .js de paquetes retirados del catálogo.
  static Future<void> _purgeRemovedPackages() async {
    for (final pkg in _removedPackages) {
      try {
        final f = File(path.join(extensionsDir, '$pkg.js'));
        if (await f.exists()) {
          await f.delete();
          debugPrint('Paquete retirado eliminado del dispositivo: $pkg');
        }
      } catch (_) {}
    }
  }

  // Elimina del Hive disabled-list los package IDs que ya no tienen JS en disco,
  // evitando datos muertos que confundan el estado de la UI.
  static Future<void> _cleanStaleDisabledList() async {
    final raw = PrismHubStorage.getSetting(SettingKey.disabledExtensions);
    if (raw == null) return;
    final List<String> list = raw is List ? List<String>.from(raw) : <String>[];
    final existingPkgs = <String>{};
    await for (final e in Directory(extensionsDir).list()) {
      if (path.extension(e.path) == '.js') {
        existingPkgs.add(path.basenameWithoutExtension(e.path));
      }
    }
    final cleaned = list.where(existingPkgs.contains).toList();
    if (cleaned.length != list.length) {
      PrismHubStorage.setSetting(SettingKey.disabledExtensions, cleaned);
    }
  }

  // True if an external extension collides with a native/official prism+ one
  // (by package id or by name) — those are blocked from external/sideload
  // install. Una oficial solo entra por el canal firmado del catálogo.
  static bool isDuplicateOfNative(Extension ext) {
    if (isNativePackage(ext.package)) return true;
    final name = ext.name.toLowerCase().trim();
    if (name.isEmpty) return false;
    // Mismo nombre que una oficial del catálogo de prism+.
    if (officialNames.contains(name)) return true;
    return runtimes.values.any((r) =>
        isNativePackage(r.extension.package) &&
        r.extension.name.toLowerCase().trim() == name);
  }

  static Future<void> _saveAndInit(
    String script,
    BuildContext context, {
    bool safeReload = false,
    bool officialVerified = false,
  }) async {
    // Parse defensively: a .js without a valid @package header otherwise throws
    // an ugly "Null is not a subtype of String" instead of a clean notice.
    Extension ext;
    try {
      ext = ExtensionUtils.parseExtension(script);
    } catch (_) {
      throw Exception('extension.invalid'.i18n);
    }
    // Validate: reject garbage so a malformed paste can't write junk files,
    // and reject unsafe package ids (path traversal) so a malicious extension
    // can't escape the extensions directory.
    final pkg = ext.package.trim();
    if (!isValidPackage(pkg)) {
      throw Exception('extension.invalid'.i18n);
    }
    // Black-box filter: an extension already shipped natively by prism+ must
    // not be installed externally — the native build is preferred. La instalación
    // oficial firmada (officialVerified) sí pasa: es la legítima del catálogo.
    if (!officialVerified && isDuplicateOfNative(ext)) {
      throw Exception('extension.already-native'.i18n);
    }
    final savePath = path.join(extensionsDir, '$pkg.js');
    _loading.add(pkg);
    await File(savePath).writeAsString(script);
    try {
      runtimes[pkg] = await ExtensionService().initRuntime(ext);
    } catch (e) {
      // Init failed — remove the bad runtime and file so it doesn't persist
      // and break loading on the next launch.
      runtimes.remove(pkg);
      try {
        await File(savePath).delete();
      } catch (_) {}
      rethrow;
    } finally {
      _loading.remove(pkg);
    }
    // Las dos ramas terminan en lo mismo desde que la recarga se junta y se
    // difiere: al correr fuera de esta pila, una excepción suya ya no podía
    // llegarle al instalador de todos modos, así que se registra y no se
    // propaga (ver _correrReload). `safeReload` se deja por los llamadores.
    _pedirReload();
  }

  static void _showInstallError(BuildContext context, Object e) {
    if (!context.mounted) return;
    showPlatformDialog(
      context: context,
      title: 'extension-install-error'.i18n,
      content: Text(e.toString()),
      actions: [
        PlatformButton(
          onPressed: RouterUtils.pop,
          child: Text('common.close'.i18n),
        )
      ],
    );
  }

  static install(String url, BuildContext context) async {
    try {
      final res = await dio.get<String>(url);
      if (res.data == null) throw Exception("Does not seem to be an extension");
      // ignore: use_build_context_synchronously
      await _saveAndInit(res.data!, context, safeReload: true);
    } catch (e) {
      // ignore: use_build_context_synchronously
      _showInstallError(context, e);
      rethrow;
    }
  }

  // officialVerified=true cuando la firma oficial del catálogo ya fue validada
  // (extension_card): en ese caso se permite instalar la oficial aunque coincida
  // con una nativa — ES la oficial. El sideload externo nunca pasa este flag.
  static installByScript(String script, BuildContext context,
      {bool officialVerified = false}) async {
    try {
      await _saveAndInit(script, context, officialVerified: officialVerified);
    } catch (e) {
      // ignore: use_build_context_synchronously
      _showInstallError(context, e);
      rethrow;
    }
  }

  static final Set<String> _loading = {};

  static installByPath(String p) async {
    if (path.extension(p) == '.js') {
      try {
        final file = File(p);
        final content = await file.readAsString();
        final ext = ExtensionUtils.parseExtension(content);
        // Mismo chequeo que _saveAndInit — acá el .js pudo llegar por
        // cualquier vía (arrastrar y soltar, carpeta sincronizada, ZIP
        // extraído), no solo por el instalador de la app.
        if (!isValidPackage(ext.package.trim())) return;
        // Skip if already loaded with same version (prevents Isar unique index violation
        // when file watcher fires multiple events during install)
        if (runtimes.containsKey(ext.package) &&
            runtimes[ext.package]!.extension.version == ext.version) {
          return;
        }
        // Prevent concurrent loads of the same package
        if (_loading.contains(ext.package)) return;
        _loading.add(ext.package);
        try {
          runtimes[ext.package] = await ExtensionService().initRuntime(ext);
        } finally {
          _loading.remove(ext.package);
        }
      } catch (e) {
        extensionErrorMap[p] = e.toString();
      }
    }
  }

  static _safeReloadPage() => _pedirReload();

  /// Espera antes de recargar, para juntar toda una ráfaga en una sola vez.
  ///
  /// 250 ms: no se nota al usar la app y alcanza de sobra para que una acción
  /// masiva termine de recorrer sus extensiones.
  static Timer? _reloadEnEspera;

  /// Hay una recarga corriendo AHORA.
  static bool _recargando = false;

  /// Llegó un cambio mientras se recargaba y hay que volver a hacerlo al
  /// terminar — una sola vez, no una por cambio.
  static bool _reloadPedidoDeNuevo = false;

  /// Pide recargar las pantallas, juntando los pedidos de una misma ráfaga.
  ///
  /// ── Por qué esto existe ─────────────────────────────────────────────────
  ///
  /// [_reloadPage] rehace Inicio (sus dos zonas), Buscar (sus dos instancias),
  /// Instaladas y el Repositorio: consultas a la base y pedidos de red. Y se
  /// llamaba UNA VEZ POR EXTENSIÓN, porque cuelga de setExtensionEnabled.
  ///
  /// O sea que «activar todas» con diecisiete instaladas lanzaba diecisiete
  /// cascadas, ninguna esperando a la anterior, todas peleando por el mismo
  /// hilo. Reportado en vivo: el app se quedaba sin responder y no se podía
  /// tocar ningún botón. Y tocando el botón de nuevo se sumaban otras
  /// diecisiete, así que empeoraba solo.
  ///
  /// El candado de la pantalla (`_masivoEnCurso`) no alcanzaba para esto: se
  /// suelta cuando el bucle termina, pero las recargas que largó siguen
  /// corriendo por su cuenta.
  ///
  /// Con esto, diecisiete cambios seguidos cuestan UNA recarga. Y como la
  /// espera se reinicia con cada pedido, machacar el botón tampoco encadena
  /// nada: se recarga una sola vez, cuando la ráfaga para.
  static void _pedirReload() {
    _reloadEnEspera?.cancel();
    _reloadEnEspera = Timer(
      const Duration(milliseconds: 250),
      _correrReload,
    );
  }

  static Future<void> _correrReload() async {
    _reloadEnEspera = null;
    // Ya hay una corriendo: se anota y se repite al final. Sin esto, una
    // ráfaga más larga que la propia recarga volvía a encimarlas.
    if (_recargando) {
      _reloadPedidoDeNuevo = true;
      return;
    }
    _recargando = true;
    try {
      await _reloadPage();
    } catch (e) {
      // Una pantalla que falle al refrescarse no puede dejar la marca puesta:
      // eso bloquearía TODAS las recargas siguientes hasta reiniciar el app.
      logger.info('[extensiones] fallo al recargar las pantallas: $e');
    } finally {
      _recargando = false;
    }
    if (_reloadPedidoDeNuevo) {
      _reloadPedidoDeNuevo = false;
      _pedirReload();
    }
  }

  /// Rehace las pantallas que dependen de qué extensiones hay activas.
  ///
  /// No se llama derecho desde ningún lado: se pide por [_pedirReload], que
  /// junta las ráfagas. Y ahora ESPERA a que terminen — antes largaba los
  /// refrescos y volvía enseguida, así que nadie sabía cuántos había en vuelo.
  static Future<void> _reloadPage() async {
    // 重载扩展页面
    if (Get.isRegistered<ExtensionPageController>()) {
      Get.find<ExtensionPageController>().callRefresh();
    }
    // 重载搜索页面 — las DOS instancias, no solo la normal.
    //
    // La búsqueda de la Zona +18 se registra con SearchPageController.zoneTag
    // (ver search_page.dart: comparten clase pero no instancia, igual que los
    // dos Home). Refrescando solo la instancia sin tag, instalar o activar una
    // extensión +18 no llegaba nunca a esa pantalla: seguía mostrando "Sin
    // extensiones instaladas" hasta que el usuario tocaba "Actualizar" a mano.
    for (final tag in <String?>[null, SearchPageController.zoneTag]) {
      if (Get.isRegistered<SearchPageController>(tag: tag)) {
        Get.find<SearchPageController>(tag: tag).callRefresh();
      }
    }
    // Repositorio de extensiones. Faltaba, y era el unico de los cuatro que
    // no se enteraba: instalar, desinstalar o activar algo desde Instaladas
    // dejaba al Repositorio mostrando el estado viejo —una extension recien
    // desinstalada seguia figurando como instalada— hasta reabrir la pagina
    // o esperar a que venciera la cache.
    if (Get.isRegistered<ExtensionRepoPageController>()) {
      await Get.find<ExtensionRepoPageController>()
          .onRefresh(forceRefresh: false);
    }

    // Home (Continuar/Favoritos/fondo del hero) — sin esto, desactivar o
    // desinstalar una extensión dejaba su contenido visible en Home hasta
    // el próximo refresco manual o hasta reabrir la página. Es la más cara de
    // las cuatro: consulta el historial de las dos zonas y rearma el fondo.
    await HomePageController.callRefreshAll();
  }


  static final RegExp _episodeNumberPattern = RegExp(r'\d+(?:\.\d+)?');

  // El número real de episodio/capítulo, extraído del título guardado —
  // NO la posición en la lista (episodeId+1). La posición asume que el
  // índice local coincide 1:1 con la numeración real de la fuente, y eso
  // se rompe apenas hay un special/capítulo no secuencial o un offset
  // distinto por extensión (confirmado: mostraba "Episodio 4" para lo que
  // en verdad era el episodio 3). Si el título guardado no tiene ningún
  // número (algunas fuentes ahí guardan el título de la serie repetido en
  // vez del episodio puntual), se cae a la posición como última opción.
  static String episodeNumberLabel(String? episodeTitle, int episodeId) {
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      final matches = _episodeNumberPattern.allMatches(episodeTitle).toList();
      if (matches.isNotEmpty) return matches.last.group(0)!;
    }
    return (episodeId + 1).toString();
  }

  // Manga y novela (fikushon) se muestran igual — "Lectura" — de cara al
  // usuario: ambos son texto para leer, y manga en particular es muy
  // versátil (manhwa/manhua/cómic caen ahí también). El ExtensionType
  // interno sigue distinguiendo los dos (el lector usa una UI distinta
  // para cada uno); esto solo unifica la ETIQUETA visible.
  static String typeToString(ExtensionType type) {
    switch (type) {
      case ExtensionType.bangumi:
        return 'extension-type.video'.i18n;
      case ExtensionType.fikushon:
      case ExtensionType.manga:
        return 'extension-type.reading'.i18n;
      case ExtensionType.mixed:
        return 'extension-type.mixed'.i18n;
      case ExtensionType.mixedReading:
        return 'extension-type.reading'.i18n;
    }
  }

  // Extensiones normales declaran un ExtensionType fijo (manga/bangumi/
  // fikushon) que alcanza para decidir lector-vs-reproductor. Una extensión
  // "mixed" (ej. ShadeManga: manga Y anime reales en el mismo sitio) no
  // puede hacerlo — necesita el tipo de CADA título puntual, que la
  // extensión manda en ExtensionDetail.type (ver detail() en el SDK). Este
  // helper es el único lugar que resuelve esa ambigüedad, para no repetir
  // la misma lógica en DetailPageController, resumeHistoryItem, etc.
  static ExtensionType resolveType(
      Extension extension, ExtensionDetail? detail) {
    // mixedReading tambien resuelve por obra, pero su respaldo es LECTURA:
    // una extension sin video no puede caer en el reproductor solo porque el
    // detalle no haya declarado su tipo.
    if (extension.type == ExtensionType.mixedReading) {
      return detail?.type ?? ExtensionType.manga;
    }
    if (extension.type != ExtensionType.mixed) return extension.type;
    return detail?.type ?? ExtensionType.bangumi;
  }

  // Único lugar con esta regla — antes estaba duplicada palabra por palabra
  // en search_page.dart y extension_repo_page.dart ("mixed entra en las
  // dos"), con el riesgo de que se actualizara en un lado y no en el otro.
  // mixedReading NO entra en video a proposito: es lectura y nada mas.
  static const videoTypes = {ExtensionType.bangumi, ExtensionType.mixed};
  static const readingTypes = {
    ExtensionType.manga,
    ExtensionType.fikushon,
    ExtensionType.mixed,
    ExtensionType.mixedReading,
  };

  static addLog(
    Extension ext,
    ExtensionLogLevel level,
    String logContent,
  ) async {
    if (!Get.isRegistered<SettingsController>()) {
      return;
    }
    final windowId = Get.find<SettingsController>().extensionLogWindowId.value;
    if (windowId == -1) {
      return;
    }
    try {
      DesktopMultiWindow.invokeMethod(
        windowId,
        "addLog",
        jsonEncode(
          ExtensionLog(
            extension: ext,
            content: logContent,
            time: DateTime.now(),
            level: level,
          ).toJson(),
        ),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  static addNetworkLog(
    String key,
    ExtensionNetworkLog log,
  ) {
    if (!Get.isRegistered<SettingsController>()) {
      return;
    }
    final windowId = Get.find<SettingsController>().extensionLogWindowId.value;
    if (windowId == -1) {
      return;
    }
    try {
      DesktopMultiWindow.invokeMethod(
        windowId,
        "addNetworkLog",
        jsonEncode({
          'key': key,
          'log': log.toJson(),
        }),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // 解析扩展为元数据
  static Extension parseExtension(String extension) {
    Map<String, dynamic> result = {};
    RegExp exp = RegExp(r'@(\w+)\s+(.*)');
    Iterable<RegExpMatch> matches = exp.allMatches(extension);
    for (RegExpMatch match in matches) {
      result[match.group(1)!] = match.group(2);
    }
    result['nsfw'] = result['nsfw'] == "true";
    return Extension.fromJson(result);
  }
}
