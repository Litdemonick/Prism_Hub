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
  static const tabBiblioteca = 1;
  static const tabBuscar = 2;
  static const tabExtensiones = 3;
  static const tabAjustes = 4;

  final selectedTab = 0.obs;

  void changeTab(int i) {
    selectedTab.value = i;
  }

  List<Widget> actions = <Widget>[].obs;

  setAcitons(List<Widget> list) async {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      actions.clear();
      actions.addAll(list);
    });
  }

  @override
  void onReady() {
    super.onReady();
    // Servidor BT desactivado a pedido explícito: ya no se chequea ni se
    // arranca al abrir la app. Antes, además, este chequeo vivía dentro de
    // addPersistentFrameCallback — que ejecuta el callback en TODOS los
    // frames, para siempre — y BTServerUtils.isInstalled() hace un
    // File(...).existsSync() SÍNCRONO y bloqueante, así que cada frame
    // dibujado pagaba un acceso a disco de más en el hilo de UI. Eso
    // explicaba gran parte de los tirones "en toda la app, todo el tiempo".
    // Se deja el estado abajo (btServerisRunning) porque otras partes
    // todavía lo leen; simplemente nunca se enciende.
  }

  final btServerVersion = "".obs;
  final btServerisRunning = false.obs;
}
