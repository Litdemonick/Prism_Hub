import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

class ExtensionRepoPageController extends GetxController {
  List<dynamic> extensions = <dynamic>[].obs;
  List<dynamic> extensionsTemp = <dynamic>[];

  final isLoading = false.obs;
  final isError = false.obs;
  final search = ''.obs;
  // Set en vez de un tipo único — "Lectura" agrupa manga+novela.
  final Rx<Set<ExtensionType>?> searchType = Rx(null);
  final RxString searchLang = 'all'.obs;

  static const List<String> availableLangs = [
    'all',
    'en',
    'es',
    'zh',
    'ja',
    'ko',
    'hi',
    'ru',
    'ar',
    'id',
    'vi',
    'tr',
    'th',
    'it'
  ];

  @override
  void onInit() {
    onRefresh(forceRefresh: false);
    super.onInit();
  }

  onRefresh({bool forceRefresh = true}) async {
    isLoading.value = true;
    isError.value = false;

    // Sin conexión detectada de entrada (ver ConnectivityUtils) — evita
    // esperar el timeout de 20s (peor todavía en el radio de Android) solo
    // para terminar mostrando el mismo error de "sin conexión" que ya
    // podíamos saber sin intentar la petición.
    if (!ConnectivityUtils.isOnline.value) {
      isError.value = true;
      isLoading.value = false;
      return;
    }

    try {
      extensions = List<dynamic>.from(
        await ExtensionUtils.fetchRepoIndex(forceRefresh: forceRefresh),
      );
      // Con el ajuste apagado se oculta el nsfw solo de lo que TODAVÍA no
      // está instalado (no se puede instalar de nuevo sin prenderlo) — una
      // que el usuario ya tenía instalada (ej. ShadeManga/ManhwaWeb) sigue
      // viéndose en "Instaladas" para poder gestionarla/desinstalarla; antes
      // desaparecía de la lista por completo, como si se hubiera borrado.
      if (!PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
        extensions.removeWhere((element) =>
            element['nsfw'] == "true" &&
            !ExtensionUtils.runtimes.containsKey(element['package']));
      }
      extensionsTemp.clear();
      extensionsTemp.addAll(extensions);
    } catch (e) {
      isError.value = true;
      debugPrint('❌ Extension repo error: ${e.toString()}');
    } finally {
      isLoading.value = false;
    }
  }
}
