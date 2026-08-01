import 'package:get/get.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/data/services/extension_service.dart';

class ExtensionPageController extends GetxController {
  RxMap<String, ExtensionService> runtimes = <String, ExtensionService>{}.obs;
  RxMap<String, String> errors = <String, String>{}.obs;
  RxBool isInstallloading = false.obs;
  bool needRefresh = true;
  bool isPageOpen = false;

  @override
  void onInit() {
    onRefresh();
    super.onInit();
  }

  /// True mientras se esta releyendo el catalogo — la pantalla lo usa para
  /// mostrar que el boton hizo algo.
  final RxBool isRefreshing = false.obs;

  onRefresh({bool desdeElBoton = false}) async {
    runtimes.clear();
    errors.clear();
    runtimes.addAll(ExtensionUtils.runtimes);
    errors.addAll(ExtensionUtils.extensionErrorMap);
    // Ya quedo al dia: la bandera existe para que la pagina sepa si tiene que
    // refrescar al abrirse, y sin apagarla aca no significaba nada.
    needRefresh = false;
    if (!desdeElBoton) return;
    // Releer los mapas locales no alcanza: lo que decide si una extension sale
    // como "inestable" o "actualizacion requerida" viene del CATALOGO, y esto
    // no lo volvia a pedir nunca. Tocar Actualizar no cambiaba nada en
    // pantalla, que es justo lo que se reportaba.
    //
    // Solo cuando lo pide el usuario: el refresco automatico (cambios de
    // extensiones, abrir la pagina) se sigue apoyando en la cache compartida,
    // porque si no cada evento dispararia una peticion de red.
    isRefreshing.value = true;
    try {
      await ExtensionUtils.refrescarCatalogo();
      runtimes.refresh();
    } catch (_) {
      // Sin conexion no se puede hacer nada mas; se deja lo que ya habia.
    } finally {
      isRefreshing.value = false;
    }
  }

  callRefresh() {
    if (isPageOpen) {
      onRefresh();
    } else {
      needRefresh = true;
    }
  }
}
