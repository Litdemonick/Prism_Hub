import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

class ExtensionRepoPageController extends GetxController {
  List<dynamic> extensions = <dynamic>[].obs;
  List<dynamic> extensionsTemp = <dynamic>[];

  final isLoading = false.obs;
  final isError = false.obs;

  /// Motivo del último fallo, para poder decirlo en pantalla.
  final errorDetalle = ''.obs;
  final search = ''.obs;
  // Set en vez de un tipo único — "Lectura" agrupa manga+novela.
  final Rx<Set<ExtensionType>?> searchType = Rx(null);
  final RxString searchLang = 'all'.obs;
  // 'all' | 'stable' | 'unstable' — filtra por el flag `unstable` del
  // catálogo (ver ExtensionCard.unstable), no por si está instalada.
  final RxString searchLevel = 'all'.obs;
  // 'all' | 'sfw' | 'nsfw' — por el flag `nsfw` del catálogo. El repositorio
  // sigue mostrando todo por defecto (ver el comentario de onRefresh): esto es
  // una ayuda para encontrar, no una censura.
  final RxString searchNsfw = 'all'.obs;
  // 'all' | 'installed' | 'available' | 'new'
  final RxString searchInstalled = 'all'.obs;
  // null = todas las zonas. Más fino que `searchType` (vídeo/lectura en
  // general): esto es "aporta a ESTA zona en particular" — misma
  // clasificación que ya usan las zonas de Inicio/PC/Android
  // (ExtensionUtils.zonasDe, según lo que declare @contentKind). Pedido
  // explícito: que el usuario sepa que tocando acá solo ve extensiones
  // enfocadas a ese contenido puntual, no todo lo que sea vídeo en general.
  final Rx<ZonaPrincipal?> searchZona = Rx(null);

  /// Paquetes que este dispositivo ya vio en el catálogo. Sirve para saber
  /// cuáles son NUEVOS: el índice no trae fecha de publicación, así que no hay
  /// forma de deducirlo de los datos.
  final RxSet<String> _vistos = <String>{}.obs;

  bool esNueva(String package) =>
      _vistos.isNotEmpty && !_vistos.contains(package);

  /// Marca todo el catálogo actual como visto.
  ///
  /// La PRIMERA vez se guarda en silencio, sin marcar nada como nuevo: si no,
  /// al estrenar la función las 12 extensiones aparecerían como novedad, que es
  /// exactamente lo contrario de lo que sirve. A partir de ahí, lo que aparezca
  /// después se destaca hasta que se vuelva a abrir el repositorio.
  Future<void> _registrarVistas(Iterable<String> paquetes) async {
    final guardado = PrismHubStorage.getSetting(SettingKey.seenRepoPackages);
    if (guardado is List) {
      _vistos
        ..clear()
        ..addAll(guardado.cast<String>());
    }
    final todos = paquetes.toSet();
    // Se guarda SIEMPRE el catálogo completo: lo que hoy es nuevo deja de
    // serlo la próxima vez que se abra esta pantalla.
    if (!setEquals(_vistos.toSet(), todos)) {
      await PrismHubStorage.setSetting(
        SettingKey.seenRepoPackages,
        todos.toList(),
      );
    }
  }

  // Ver _langLabels en extension_repo_page: solo los dos idiomas de la app.
  static const List<String> availableLangs = ['all', 'es', 'en'];

  @override
  void onInit() {
    onRefresh(forceRefresh: false);
    super.onInit();
  }

  onRefresh({bool forceRefresh = true}) async {
    isLoading.value = true;
    isError.value = false;
    errorDetalle.value = '';

    // Sin conexión detectada de entrada (ver ConnectivityUtils) — evita
    // esperar el timeout de 20s (peor todavía en el radio de Android) solo
    // para terminar mostrando el mismo error de "sin conexión" que ya
    // podíamos saber sin intentar la petición.
    if (!ConnectivityUtils.isOnline.value) {
      isError.value = true;
      errorDetalle.value = 'common.no-connection'.i18n;
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
      // OJO: esto deja _vistos con el catálogo ANTERIOR y guarda el actual. Es
      // a propósito — durante esta sesión se puede decir qué apareció desde la
      // última vez, y la próxima vez ya no serán novedad.
      await _registrarVistas(
        extensions
            .map((e) => e['package'])
            .whereType<String>()
            .where((p) => p.isNotEmpty),
      );
    } catch (e, st) {
      isError.value = true;
      // Se guarda el motivo REAL, no solo un booleano: la pantalla mostraba
      // siempre el mismo error genérico y no había forma de distinguir "sin
      // internet" de "el repositorio devolvió algo que no se entiende".
      errorDetalle.value = friendlyError(e);
      logger.warning('No se pudo leer el catálogo de extensiones', e, st);
    } finally {
      isLoading.value = false;
    }
  }
}
