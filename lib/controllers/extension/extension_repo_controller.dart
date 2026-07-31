import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';

class ExtensionRepoPageController extends GetxController {
  List<dynamic> extensions = <dynamic>[].obs;
  List<dynamic> extensionsTemp = <dynamic>[];

  final isLoading = false.obs;
  final isError = false.obs;
  final search = ''.obs;
  // Set en vez de un tipo único — "Lectura" agrupa manga+novela.
  final Rx<Set<ExtensionType>?> searchType = Rx(null);
  final RxString searchLang = 'all'.obs;
  // 'all' | 'stable' | 'unstable' — filtra por el flag `unstable` del
  // catálogo (ver ExtensionCard.unstable), no por si está instalada.
  final RxString searchLevel = 'all'.obs;

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
      // El repositorio nunca oculta nada, instalada o no, tenga NSFW o no:
      // el catálogo completo siempre se ve. El filtro del switch de
      // Ajustes solo bloquea la instalación/activación (con aviso, ver
      // ExtensionUtils.installWithNsfwGuard) y saca el contenido +18 de
      // Home/Búsqueda — nunca esconde la existencia de la extensión acá.
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
