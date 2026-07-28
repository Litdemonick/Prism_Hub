import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

class SearchPageController extends GetxController {
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
  Worker? _searchWorker;
  // 是否打开了这个页面

  @override
  void onInit() {
    _searchWorker = ever(search, (callback) {
      _randomKey = DateTime.now().millisecondsSinceEpoch.toString();
      getResult(_randomKey);
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
    if (!PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
      exts.removeWhere((element) => element.extension.nsfw);
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
    searchResultList.value = exts
        .map((element) =>
            byPackage[element.extension.package] ??
            SearchResult(runitme: element))
        .toList();
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
    // 最后一个有结果的搜索结果索引
    var lastResultIndex = -1;
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
      if (element.isFetching) continue;
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

    const batchSize = 2;
    for (var i = 0; i < pending.length; i += batchSize) {
      if (_randomKey != key) {
        for (var j = i; j < pending.length; j++) {
          pending[j].isFetching = false;
          pending[j].completed = true;
        }
        searchResultList.refresh();
        break;
      }
      final batch = pending.skip(i).take(batchSize);
      await Future.wait(batch.map((element) {
        element.isFetching = true;
        Future<List<ExtensionListItem>> resultFuture;
        try {
          if (search.value.isEmpty) {
            resultFuture = element.runitme.latest(1);
          } else {
            resultFuture = element.runitme.search(search.value, 1);
          }
        } catch (e) {
          element.error = e;
          element.completed = true;
          element.isFetching = false;
          searchResultList.refresh();
          return Future<void>.value();
        }

        return resultFuture
            .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Tiempo de espera agotado'),
        )
            .then((result) {
          if (_randomKey != key) {
            return;
          }
          element.result = result;
          element.error = null;
          // 如果搜索结果不为空,
          if (result.isNotEmpty) {
            searchResultList.remove(element);
            // 判断是否是第一个,将第一个放到最前面
            if (lastResultIndex == -1) {
              searchResultList.insert(0, element);
              lastResultIndex = 0;
            } else {
              searchResultList.insert(lastResultIndex + 1, element);
              lastResultIndex++;
            }
          } else {
            searchResultList.refresh();
          }
        }).catchError((e) {
          // Mismo chequeo que en el éxito: sin esto, un fetch VIEJO (de un
          // filtro/búsqueda anterior, todavía en vuelo por su timeout de
          // 15s) podía marcar error en un elemento reusado que ya se estaba
          // mostrando bajo el filtro nuevo — se veía como que la extensión
          // aparecía bien un instante y de golpe caía al banner de sin
          // conexión, sin que el usuario hubiera hecho nada en el filtro
          // actual.
          if (_randomKey != key) return;
          element.error = e;
          searchResultList.refresh();
        }).whenComplete(() {
          // isFetching/completed SIEMPRE se actualizan, sin importar el key
          // — pase lo que pase, este fetch puntual ya terminó, y si se
          // dejara colgado en true por un chequeo de key ningún llamador
          // futuro podría volver a intentar esta extensión (quedaría
          // "cargando" para siempre en la barra de progreso).
          element.isFetching = false;
          element.completed = true;
        });
      }));
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 8));
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
    }
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
  SearchResult({
    required this.runitme,
    this.error,
    this.result,
    this.completed = false,
  });
}
