import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

/// Estado de conectividad global de la app — antes cada pantalla (Home,
/// Buscar, Repositorio de extensiones) solo se enteraba de que no hay
/// internet cuando una petición YA fallaba (reactivo, y cada una con su
/// propio timing/mensaje), así que sin wifi la experiencia era inconsistente
/// entre pantallas y a veces no avisaba nada (ej. Home tragaba el error de
/// cada extensión en silencio). Esto detecta la interfaz de red de entrada
/// (rápido, sin esperar a que una petición HTTP agote su timeout) para poder
/// mostrar un aviso único y consistente en toda la app.
///
/// Nota: esto es "hay una interfaz de red" (wifi/datos conectados), no
/// "hay internet real" (ej. wifi sin salida a internet) — para eso sigue
/// haciendo falta el chequeo reactivo existente (isConnectionError) como
/// respaldo en cada pantalla.
class ConnectivityUtils {
  static final RxBool isOnline = true.obs;
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  static Future<void> ensureInitialized() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      isOnline.value = _hasConnection(initial);
    } catch (_) {
      // Si el plugin falla en esta plataforma, no bloquear el arranque —
      // el chequeo reactivo por pantalla sigue funcionando igual.
    }
    _subscription = Connectivity().onConnectivityChanged.listen(
      (result) {
        isOnline.value = _hasConnection(result);
      },
      // Un error en el stream del plugin nativo NO es "no hay internet" —
      // sin este onError, la excepción se propagaba como error no manejado y
      // el estado quedaba en lo último que se hubiera leído. Ante una falla
      // del plugin se asume online: el chequeo reactivo por pantalla
      // (isConnectionError) ya cubre el caso de estar realmente sin red, y
      // es mucho menos dañino dejar pasar una petición que fallará sola que
      // bloquear TODA la app con el cartel de "sin internet".
      onError: (_) => isOnline.value = true,
    );
  }

  static bool _hasConnection(List<ConnectivityResult> results) {
    // Lista vacía = el plugin no supo decir nada (visto al reiniciar en
    // caliente tras cambiar dependencias: el lado nativo queda a medio
    // registrar y emite una lista vacía). Con el .any() pelado eso daba
    // false, o sea "sin internet", y dejaba TODA la app bloqueada con el
    // cartel de sin conexión aunque la red estuviera perfecta. "No sé" se
    // trata como online: si de verdad no hay red, la petición falla sola y
    // ahí sí se avisa.
    if (results.isEmpty) return true;
    return results.any((r) => r != ConnectivityResult.none);
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
