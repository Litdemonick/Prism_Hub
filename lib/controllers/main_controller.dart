import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

// 全局 Controller
class MainController extends GetxController {
  // ─── Las pestañas de abajo del teléfono, con nombre ─────────────────────
  //
  // Estaban escritas a mano y repartidas por cinco archivos: `changeTab(2)`,
  // `selectedTab.value = 2`, `changeTab(3)`. Agregar una pestaña al medio las
  // corría TODAS en silencio y sin que nada dejara de compilar — pasó al
  // sumar Biblioteca, donde `changeTab(2)` dejó de ser Extensiones.
  //
  // El orden de acá tiene que ser el MISMO que el de `pages` y el de
  // `destinations` en main_page.dart. Es un solo lugar y se ve de un vistazo.
  static const tabHome = 0;
  static const tabPeliculas = 1;
  static const tabSeries = 2;
  static const tabAnime = 3;
  static const tabMangas = 4;
  static const tabBiblioteca = 5;
  static const tabExtensiones = 6;
  static const tabAjustes = 7;

  final selectedTab = 0.obs;

  /// De qué pestaña se venía.
  ///
  /// Hace falta para Ajustes: es la única zona que NO tiene su botón en la
  /// barra de abajo —entra por los tres puntos— así que una vez adentro no hay
  /// nada marcado y no se sabe con qué volver. Con esto, la barra puede
  /// ofrecer una flecha que devuelve exactamente a donde estabas.
  int tabAnterior = tabHome;

  void changeTab(int i) {
    if (i != selectedTab.value) tabAnterior = selectedTab.value;
    selectedTab.value = i;
  }

  /// Vuelve de una pantalla que puede haber llegado empujada (`Get.to`,
  /// `Navigator.push`) O como pestaña de este mismo shell (`changeTab`).
  ///
  /// ── Por qué hace falta esto y no alcanza con `Navigator.pop` ──────────
  ///
  /// Extensiones y Ajustes, en televisor, se abren de las DOS formas según
  /// desde dónde se entra: desde la barra de arriba del Inicio son una
  /// pestaña de este `IndexedStack` (no hay ninguna ruta que desapilar); desde
  /// dentro de Ajustes, Extensiones se abre empujada con `Get.to` (ahí sí hay
  /// una ruta). Un botón de «volver» escrito para un solo caso queda roto en
  /// el otro — reportado en vivo: «en la zona de extensiones no me deja
  /// regresar al inicio, le doy a volver y no hace nada».
  ///
  /// Mismo criterio que ya usa el botón atrás del sistema en `main_page.dart`
  /// (`PopScope`): si hay una ruta empujada, se desapila; si no, es una
  /// pestaña, y desde Ajustes se vuelve a `tabAnterior` —de dónde se vino—,
  /// desde cualquier otra a Inicio.
  static void volver(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (!Get.isRegistered<MainController>()) return;
    final c = Get.find<MainController>();
    c.changeTab(c.selectedTab.value == tabAjustes ? c.tabAnterior : tabHome);
  }

  List<Widget> actions = <Widget>[].obs;

  setAcitons(List<Widget> list) async {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      actions.clear();
      actions.addAll(list);
    });
  }


  final btServerVersion = "".obs;
  final btServerisRunning = false.obs;
}
