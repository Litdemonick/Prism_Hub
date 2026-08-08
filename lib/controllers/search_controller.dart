import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/data/services/extension_service.dart';

class SearchPageController extends GetxController {
  // Mismo esquema que HomePageController: la búsqueda normal usa la instancia
  // por defecto y la zona +18 registra la suya aparte bajo este tag, con
  // nsfwOnly en true. Así las dos conviven sin pisarse los resultados.
  static const zoneTag = 'nsfw18-search';

  // true = SOLO extensiones marcadas +18 (la zona +18 del buscador).
  // false = NUNCA extensiones +18, ni siquiera con el switch de NSFW prendido:
  // el contenido para adultos vive únicamente detrás del botón +18, que pide
  // confirmación y PIN.
  final bool nsfwOnly;
  SearchPageController({this.nsfwOnly = false});

  // Set en vez de un tipo único — el filtro "Lectura" agrupa manga+novela
  // (ambos son texto para leer, de cara al usuario es una sola categoría).
  Rx<Set<ExtensionType>?> cuurentExtensionType = Rx(null);
  final search = ''.obs;
  final searchResultList = <SearchResult>[].obs;
  String _randomKey = "";
  int get finishCount =>
      searchResultList.where((element) => element.completed).length;
  bool needRefresh = true;
  bool isPageOpen = false;
  // Paquetes cuyo NOMBRE coincide con lo tecleado. A esos se les muestra su
  // catalogo en vez de buscarles un titulo con ese texto.
  final Set<String> _coincidenPorNombre = <String>{};

  Worker? _searchWorker;
  // 是否打开了这个页面

  @override
  void onInit() {
    _searchWorker = ever(search, (callback) {
      // getRuntime y no getResult a secas: la lista de extensiones a consultar
      // ahora depende TAMBIEN de lo que se escribio (ver el filtro por nombre
      // ahi adentro), asi que hay que rearmarla en cada cambio. getRuntime
      // reusa los SearchResult ya cargados por paquete, o sea que esto no tira
      // a la basura lo que ya estaba en pantalla.
      getRuntime(types: cuurentExtensionType.value);
    });
    super.onInit();
  }

  @override
  void onClose() {
    _searchWorker?.dispose();
    super.onClose();
  }

  getRuntime({Set<ExtensionType>? types}) {
    _randomKey = DateTime.now().millisecondsSinceEpoch.toString();
    final exts = ExtensionUtils.enabledRuntimes.values.toList();
    if (types != null) {
      exts.removeWhere((element) => !types.contains(element.extension.type));
    }
    // Zona +18 del buscador: solo extensiones marcadas +18. Buscador normal:
    // ninguna, sin excepción — antes bastaba con tener el switch de NSFW
    // prendido para que apareciesen acá mezcladas con el resto.
    if (nsfwOnly) {
      // Las +18 enteras, MÁS las mixtas: ShadeManga y ManhwaWeb tienen una
      // sección de adultos detrás de un filtro propio, y sin esto quedaban
      // fuera de su propia zona. Al abrirlas desde acá, el buscador por
      // extensión les pone ese filtro puesto de entrada (ver `soloAdulto` en
      // ExtensionSearcherPage).
      exts.removeWhere((element) =>
          !element.extension.nsfw &&
          !ExtensionUtils.esMixta(element.extension.package));
    } else {
      // Y acá al revés: fuera las +18 enteras. Una mixta SÍ se queda, con su
      // contenido normal — el filtro de adultos va cerrado por defecto y el
      // app lo manda explícito.
      exts.removeWhere((element) => element.extension.nsfw);
    }
    // Escribir el NOMBRE de una extension la encuentra.
    //
    // Antes lo tecleado se le pasaba tal cual a search() de CADA extension, asi
    // que buscar "jkanime" preguntaba por un titulo llamado "jkanime" en las
    // ocho y no devolvia nada util. Si lo escrito coincide con el nombre de
    // alguna extension, se consultan SOLO esas — que es lo que uno quiere
    // cuando escribe el nombre de una fuente.
    //
    // Se aplica DESPUES de los filtros de tipo y de zona, asi que respeta
    // Todo/Video/Lectura y no mezcla +18 con lo normal. Si no coincide con
    // ninguna, no se descarta nada y la busqueda sigue como siempre.
    final consulta = search.value.trim();
    _coincidenPorNombre.clear();
    if (consulta.isNotEmpty) {
      final porNombre = exts
          .where((e) => SearchText.matchesQuery(e.extension.name, consulta))
          .toList();
      if (porNombre.isNotEmpty) {
        exts
          ..clear()
          ..addAll(porNombre);
        // Se anotan para que a ESTAS no se les pida un titulo con ese texto,
        // sino su catalogo. Ver runOne(): sin esto, escribir "Ikigai" reducia
        // bien la lista a esa extension y acto seguido le preguntaba por una
        // obra llamada "Ikigai" — que no existe — asi que la pantalla
        // terminaba diciendo "sin resultados" igual.
        for (final e in porNombre) {
          _coincidenPorNombre.add(e.extension.package);
        }
      }
    }

    // Reusa el SearchResult existente por package en vez de crear todos
    // nuevos: antes cada refresh/cambio de filtro tiraba a la basura los
    // resultados YA cargados (result -> null de golpe en todas), así que
    // se veían las 8 extensiones "queriendo cargar" (ProgressRing) y, si
    // justo no había internet, desapareciendo una por una a medida que
    // fallaban (filtradas por el banner de sin conexión) en vez de quedarse
    // quietas mostrando lo que ya tenían.
    final byPackage = {
      for (final r in searchResultList) r.runitme.extension.package: r,
    };
    searchResultList.value = exts.map((element) {
      final cached = byPackage[element.extension.package];
      // Solo se reusa si es EXACTAMENTE el mismo runtime. Al actualizar o
      // reinstalar una extensión, ExtensionUtils crea un ExtensionService
      // nuevo (con el JS nuevo cargado en su propio QuickJS), pero
      // SearchResult.runitme es final — así que reusar el SearchResult viejo
      // dejaba a esta página llamando para siempre al runtime ANTERIOR, con
      // el código viejo, hasta reiniciar la app. Confirmado en vivo: después
      // de actualizar AnimeFenix, buscar dentro de la extensión devolvía 4
      // resultados (runtime nuevo) y la búsqueda general seguía mostrando 3
      // (runtime viejo) con la misma palabra.
      if (cached != null && identical(cached.runitme, element)) return cached;
      return SearchResult(runitme: element);
    }).toList();
    // Se asigna DESPUÉS de la lista: cuurentExtensionType compone la key que
    // fuerza remount de SearchAllExtSearch (ver search_page.dart) — si
    // cambiara primero, ese remount alcanzaba a ver la lista VIEJA por un
    // instante (filtro ya nuevo, datos de la búsqueda anterior).
    cuurentExtensionType.value = types;
    getResult(_randomKey);
    needRefresh = false;
  }

  Future<void> getResult(String key) async {
    // Sin conexión detectada de entrada (rápido y confiable vía
    // ConnectivityUtils) — evita que cada extensión intente igual la
    // petición de red y quede "intentando cargar" hasta agotar su propio
    // timeout de 15s. En Android el radio a veces tarda mucho más que
    // Windows en darse por vencido solo (reportado en vivo: al cambiar de
    // filtro/buscar/refrescar sin wifi, las extensiones quedaban así hasta
    // reiniciar la app) — cortar acá, antes de intentar, es instantáneo y
    // consistente en ambas plataformas. El error sintético usa el mismo
    // texto que isConnectionError() reconoce, para que el banner agrupado
    // de "sin conexión" (SearchAllExtSearch) se muestre igual que si cada
    // extensión hubiera fallado de verdad.
    if (!ConnectivityUtils.isOnline.value) {
      for (final element in searchResultList) {
        element.error = Exception('Connection error: sin conexión a internet');
        element.completed = true;
      }
      searchResultList.refresh();
      return;
    }
    final pending = <SearchResult>[];
    // Extensiones salteadas por tener un fetch de un ciclo anterior todavía
    // en vuelo. Antes se descartaban y listo: ese fetch viejo terminaba,
    // veía que la key ya no era la suya y se iba SIN escribir resultado, así
    // que la extensión quedaba marcada como terminada pero con la card
    // vacía — nunca cargaba, justo lo que pasaba al cambiar de filtro
    // rápido entre Todo/Lectura/Vídeo. Ahora se las espera y se las vuelve
    // a pedir para el ciclo actual.
    final deferred = <SearchResult>[];
    for (var i = 0; i < searchResultList.length; i++) {
      final element = searchResultList[i];
      // Ya hay un fetch en vuelo para esta extensión (de un click anterior
      // que todavía no resolvió/timeouteó, ej. spamear Actualizar o los
      // chips de filtro) — no arrancar OTRO en paralelo. Sin este chequeo,
      // cada click nuevo sumaba una petición más (con su propio timeout de
      // 15s) sin cancelar la anterior — el bridge JS de cada extensión las
      // va a procesar todas igual, una atrás de otra, así que a los pocos
      // minutos de clickear seguido quedaba una cola larga de peticiones
      // ya inútiles pero todavía corriendo, y el app se sentía cada vez más
      // pesado/trabado cuanto más rato pasaba.
      if (element.isFetching) {
        deferred.add(element);
        continue;
      }
      element.completed = false;
      // OJO: ni result NI error se resetean acá. Se actualizan recién
      // cuando el intento nuevo resuelve de verdad (éxito limpia error más
      // abajo, catchError lo setea) — si se limpiara error de entrada, una
      // extensión que ya estaba agrupada en el banner de "sin conexión"
      // (sin resultado previo) reaparecía como spinner individual apenas se
      // apretaba Actualizar, aunque la extensión siguiera sin internet un
      // instante después. Mismo criterio que no resetear result: evitar
      // cualquier cambio visual antes de tener un resultado real nuevo.
      pending.add(element);
    }

    // Pool de tareas en vez de tandas rígidas. Antes esto iba en batches de
    // 2 con `Future.wait`, y eso esperaba a la MÁS LENTA de cada tanda antes
    // de arrancar la siguiente: una sola extensión lenta (o que se va a su
    // timeout de 15s) dejaba a su compañera terminada esperando al aire y
    // frenaba todas las tandas que venían atrás — con 8 extensiones, la
    // barra de carga se quedaba colgada un buen rato aunque casi todas
    // hubieran respondido enseguida (confirmado en vivo buscando "one
    // piece"). Con el pool, apenas una termina su hueco se lo queda la
    // siguiente pendiente, así que SIEMPRE hay `maxConcurrent` pedidos en
    // vuelo y una lenta solo se demora a sí misma.
    //
    // 4 en paralelo (antes 2 efectivos): el trabajo real es esperar red, no
    // CPU, y cada respuesta sigue cediendo el frame antes de seguir para no
    // trabar la UI al pintar las tarjetas nuevas.
    const maxConcurrent = 4;
    var nextIndex = 0;

    Future<void> runOne(SearchResult element) async {
      element.isFetching = true;
      final done = Completer<void>();
      element.inFlight = done.future;
      try {
        final Future<List<ExtensionListItem>> resultFuture;
        // Se pide el CATALOGO cuando no hay texto, y tambien cuando lo tecleado
        // es el nombre de esta extension: quien escribe "Ikigai" quiere ver lo
        // que tiene Ikigai, no una obra que se llame asi.
        final esNombreDeLaExtension =
            _coincidenPorNombre.contains(element.runitme.extension.package);
        if (search.value.isEmpty || esNombreDeLaExtension) {
          resultFuture = element.runitme.latest(1);
        } else {
          resultFuture = element.runitme.searchFirstPageWithBroadening(
              SearchText.sanitizeForRemoteQuery(search.value));
        }
        final result = await resultFuture.timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Tiempo de espera agotado'),
        );
        // Un fetch VIEJO (de un filtro/búsqueda anterior, todavía en vuelo
        // por su timeout de 15s) no debe pisar el estado del ciclo actual —
        // sin esto se veía a una extensión aparecer bien un instante y de
        // golpe caer al banner de sin conexión sin que el usuario tocara
        // nada.
        if (_randomKey != key) return;
        element.result = result;
        element.error = null;
        // Ya NO se reordena acá extensión por extensión — antes cada una que
        // respondía con resultados se movía al frente de una (remove+insert),
        // lo que hacía "saltar" la lista entera fila por fila mientras
        // cargaba (confirmado en vivo). El orden se queda estable durante
        // toda la carga; el único reordenamiento por relevancia pasa UNA vez
        // al final (ver el sort al cierre de este método).
        searchResultList.refresh();
      } catch (e) {
        if (_randomKey != key) return;
        element.error = e;
        searchResultList.refresh();
      } finally {
        // isFetching/completed SIEMPRE se actualizan, sin importar el key —
        // pase lo que pase, este fetch puntual ya terminó, y si se dejara
        // colgado en true por un chequeo de key ningún llamador futuro
        // podría volver a intentar esta extensión (quedaría "cargando" para
        // siempre en la barra de progreso).
        element.isFetching = false;
        element.completed = true;
        element.inFlight = null;
        if (!done.isCompleted) done.complete();
      }
    }

    Future<void> worker() async {
      while (true) {
        // Dart es single-threaded: leer e incrementar acá es atómico (no hay
        // await en el medio), así que dos workers nunca se llevan el mismo
        // índice.
        if (_randomKey != key || nextIndex >= pending.length) return;
        final element = pending[nextIndex++];
        await runOne(element);
        // Cede el frame para que la UI pinte las tarjetas que acaban de
        // llegar antes de arrancar el próximo pedido.
        await SchedulerBinding.instance.endOfFrame;
      }
    }

    await Future.wait([
      for (var i = 0; i < maxConcurrent && i < pending.length; i++) worker(),
    ]);

    // Segunda pasada por las salteadas: se espera a que su pedido viejo
    // termine (como mucho su timeout de 15s) y recién ahí se las pide para
    // el ciclo actual. Se reintentan siempre, no solo si están vacías: el
    // resultado que puedan tener es de otra búsqueda o de otro filtro.
    if (deferred.isNotEmpty && _randomKey == key) {
      // La espera va en PARALELO: una por una, tres extensiones colgadas
      // hasta su timeout eran 45 segundos antes de siquiera empezar a
      // pedirlas de nuevo.
      await Future.wait(deferred.map((element) async {
        final inFlight = element.inFlight;
        if (inFlight == null) return;
        try {
          await inFlight;
        } catch (_) {
          // runOne ya maneja sus propios errores; acá solo interesa que
          // haya terminado.
        }
      }));
      if (_randomKey == key) {
        for (final element in deferred) {
          element.completed = false;
        }
        // Se reusa el MISMO pool (mismo límite de concurrencia, misma cesión
        // de frame) en vez de duplicar la lógica.
        pending
          ..clear()
          ..addAll(deferred);
        nextIndex = 0;
        await Future.wait([
          for (var i = 0; i < maxConcurrent && i < pending.length; i++)
            worker(),
        ]);
      }
    }

    // Cancelado a mitad de camino: lo que nunca llegó a arrancar queda
    // marcado como terminado para que la barra de progreso no se cuelgue
    // esperando fetches que ya no van a pasar.
    if (_randomKey != key) {
      for (var j = nextIndex; j < pending.length; j++) {
        pending[j].isFetching = false;
        pending[j].completed = true;
      }
      searchResultList.refresh();
    }

    // Red de seguridad: si por lo que sea quedó alguna sin marcar (una
    // extensión que se agregó a la lista después de arrancar este ciclo, o
    // una que quedó saltada por isFetching de un ciclo anterior que nunca
    // resolvió), la barra de progreso se quedaría trabada para siempre
    // porque compara finishCount contra el total. Acá ya terminó todo lo
    // que este ciclo iba a hacer, así que nada puede quedar "en curso".
    if (_randomKey == key) {
      var changed = false;
      for (final element in searchResultList) {
        if (!element.completed && !element.isFetching) {
          element.completed = true;
          changed = true;
        }
      }
      if (changed) searchResultList.refresh();

      // Reordenamiento por relevancia — UNA sola vez, ahora que este ciclo
      // ya terminó de verdad (no en cada respuesta individual, ver arriba).
      // Solo tiene sentido con una búsqueda activa: en modo "latest"
      // (explorar sin escribir nada) no hay ninguna palabra contra la cual
      // priorizar, así que se deja el orden de siempre.
      final query = search.value.trim();
      if (query.isNotEmpty) {
        // Se tokeniza UNA sola vez acá afuera — bucket() se llama por cada
        // extensión Y por cada ítem de su resultado, así que renormalizar
        // la misma query adentro del loop sería trabajo repetido de sobra.
        final tokens = SearchText.queryTokens(query);
        // Cuatro grupos, no tres. Antes "sin resultados" y "con resultados
        // pero sin coincidencia en el título" caían los DOS en el 1, así que
        // una extensión que no encontró nada quedaba mezclada entre las que sí
        // — justo lo contrario de lo que este orden busca. Ahora lo vacío baja
        // siempre por debajo de cualquier cosa que haya traído algo.
        int bucket(SearchResult r) {
          final tieneResultados = r.result != null && r.result!.isNotEmpty;
          if (tieneResultados) {
            final coincideTitulo = r.result!
                .any((item) => SearchText.matchesTokens(item.title, tokens));
            return coincideTitulo ? 0 : 1;
          }
          // El error va último: no es que no haya nada, es que no se pudo
          // preguntar, y eso el usuario ya lo ve en el aviso de la tarjeta.
          return r.error != null ? 3 : 2;
        }

        // List.sort de Dart es estable: dentro de cada bucket, el orden
        // relativo que ya tenían se mantiene (no hay un segundo criterio
        // de desempate que pueda "revolver" más de la cuenta).
        searchResultList.sort((a, b) => bucket(a).compareTo(bucket(b)));
        searchResultList.refresh();
      }
    }
  }

  // Buscar de nuevo el MISMO texto tiene que volver a buscar de verdad.
  // Antes las dos plataformas hacían `c.search.value = value` directo, y el
  // setter de Rx en GetX corta si el valor es idéntico
  // (`if (_value == val && !firstRebuild) return;` en rx_impl.dart), así que
  // el worker `ever(search, ...)` no disparaba: apretar Enter dos veces con
  // la misma palabra no hacía absolutamente nada, y los resultados viejos
  // quedaban en pantalla incluso después de actualizar una extensión.
  void submitSearch(String value) {
    if (search.value == value) {
      _randomKey = DateTime.now().millisecondsSinceEpoch.toString();
      getResult(_randomKey);
      return;
    }
    search.value = value;
  }

  getPackgeByIndex(int index) {
    return searchResultList[index].runitme.extension.package;
  }

  callRefresh() {
    if (isPageOpen) {
      getRuntime();
    } else {
      needRefresh = true;
    }
  }
}

class SearchResult {
  final ExtensionService runitme;
  List<ExtensionListItem>? result;
  // Objeto de excepción crudo, no un String — friendlyError()/
  // isConnectionError() necesitan el tipo real (DioException, etc.) para
  // detectar errores de red de forma confiable, no solo matchear texto.
  Object? error;
  bool completed;
  // True mientras hay un fetch en vuelo para esta extensión — evita
  // arrancar pedidos duplicados en paralelo si el usuario clickea
  // refrescar/cambiar de filtro varias veces seguidas (ver getResult()).
  bool isFetching = false;
  // El fetch en vuelo, para poder esperarlo. Con solo el booleano se sabía
  // que había uno corriendo pero no CUÁNDO terminaba, así que lo único que
  // se podía hacer era saltear la extensión — y quedaba sin cargar.
  Future<void>? inFlight;
  SearchResult({
    required this.runitme,
    this.error,
    this.result,
    this.completed = false,
  });
}
