import 'dart:io';

import 'package:get/get.dart';
import 'package:prismhub/router/router.dart';

class RouterUtils {
  // result: para diálogos de confirmación (ej. aviso +18 al activar una
  // extensión nsfw) que necesitan devolver true/false a quien los abrió.
  // Usar SIEMPRE esto (no Navigator.of(context).pop directo) para cerrar
  // diálogos/páginas — en desktop la navegación la maneja go_router, y un
  // pop crudo sobre el Navigator de Flutter puede terminar sacando la
  // página equivocada en vez del diálogo.
  static pop<T extends Object?>([T? result]) {
    if (Platform.isAndroid) {
      return Get.back<T>(result: result);
    }
    return router.pop<T>(result);
  }
}
