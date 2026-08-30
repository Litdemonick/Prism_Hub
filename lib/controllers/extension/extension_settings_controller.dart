import 'package:get/get.dart';
import 'package:prismhub/models/extension_setting.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/data/services/extension_service.dart';

class ExtensionSettingsPageController extends GetxController {
  ExtensionSettingsPageController(this.package);
  final String package;

  final Rx<ExtensionService?> runtime = Rx(null);

  final List<ExtensionSetting> settings = <ExtensionSetting>[].obs;

  @override
  void onInit() {
    onRefresh();
    super.onInit();
  }

  onRefresh() async {
    final servicio = ExtensionUtils.runtimes[package];
    runtime.value = servicio;
    // El motor se levanta acá, aunque esta pantalla lea los ajustes de la base.
    //
    // Los ajustes que una extensión declara se guardan cuando su JavaScript
    // corre, así que los de una versión anterior ya están y se verían igual.
    // Pero si la extensión se actualizó y declara ajustes NUEVOS, esos todavía
    // no existen en la base: sin esto, la pantalla mostraría la lista vieja y
    // parecería que la actualización no trajo nada.
    //
    // Es el único sitio donde vale la pena pagarlo sin que nadie lo pida: quien
    // abre los ajustes de una extensión quiere ver los de ahora.
    try {
      await servicio?.asegurarMotor();
    } catch (e) {
      // Que el motor no levante no puede dejar la pantalla en blanco: los
      // ajustes que ya estaban guardados se muestran igual.
      logger.info('[extensiones] no se pudo levantar $package: $e');
    }
    settings.clear();
    settings.addAll(await DatabaseService.getExtensionSettings(package));
  }
}
