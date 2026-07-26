import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';

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
    onRefresh();
    super.onInit();
  }

  onRefresh() async {
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
      // Cache-bust: GitHub raw cachea index.json unos minutos, lo que ocultaría
      // una extensión recién publicada aunque el usuario refresque a mano.
      final bust = DateTime.now().millisecondsSinceEpoch;
      final url =
          '${PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl)}/index.json?t=$bust';
      debugPrint('🔍 Extension repo URL: $url');
      final res = await dio.get<String>(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      final decoded = jsonDecode(res.data!);
      // El catálogo de prism+ es {name, extensions:[...]}; repos antiguos eran
      // una lista pelada. Soportar ambos.
      extensions = decoded is Map ? (decoded['extensions'] ?? []) : decoded;
      if (!PrismHubStorage.getSetting(SettingKey.enableNSFW)) {
        extensions.removeWhere((element) => element['nsfw'] == "true");
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
