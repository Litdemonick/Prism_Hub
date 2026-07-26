import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

// 全局 Controller
class MainController extends GetxController {
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
