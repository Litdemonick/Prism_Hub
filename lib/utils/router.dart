import 'dart:io';

import 'package:flutter/widgets.dart';
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

  // Cierra el lector (manga/manhwa/novela) volviendo a donde estaba el
  // usuario. Estaba duplicado como método privado en ControlPanelHeader; se
  // compartió acá para que la tecla Escape use EXACTAMENTE el mismo camino que
  // el botón de atrás, en vez de una segunda implementación que se pueda
  // desincronizar.
  //
  // No alcanza un pop crudo: al entrar por goWatch, ese pop terminaba
  // revelando lo que hubiera quedado antes en la pila de go_router (una página
  // de detalle vieja) en vez de cerrar el lector y volver al Home real. Se va
  // primero al Navigator ANCESTRO de este context puntual (el que de verdad
  // aloja al lector), con fallbacks solo por las dudas. Mismo criterio que
  // VideoPlayerController.closeRoute.
  static void closeReader(BuildContext context) {
    final nav = Navigator.maybeOf(context);
    final route = ModalRoute.of(context);
    if (nav != null && route != null && route.isActive) {
      if (route.isCurrent) {
        nav.pop();
      } else {
        nav.removeRoute(route);
      }
      return;
    }
    if (rootNavigatorKey.currentState?.canPop() == true) {
      rootNavigatorKey.currentState!.pop();
      return;
    }
    if (Get.key.currentState?.canPop() == true) {
      Get.back();
      return;
    }
    if (router.canPop()) {
      router.pop();
    }
  }
}
