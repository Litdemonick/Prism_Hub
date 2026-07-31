import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

// PIN de acceso a la Zona +18. Se guarda hasheado (SHA-256 con sal fija de
// app, nunca el PIN en texto plano) en el mismo Hive box que el resto de
// Ajustes (ver PrismHubStorage).
class Nsfw18Zone {
  Nsfw18Zone._();

  static const _pinHashKey = 'Nsfw18PinHash';

  static bool get isPinConfigured =>
      PrismHubStorage.getSetting(_pinHashKey) is String;

  static String _hash(String pin) =>
      sha256.convert(utf8.encode('prismhub-nsfw18-zone:$pin')).toString();

  static Future<void> setPin(String pin) async {
    await PrismHubStorage.setSetting(_pinHashKey, _hash(pin));
    await _limpiarFallos();
  }

  // Quita el PIN configurado — la próxima vez que se intente entrar a la
  // zona, se pide configurar uno nuevo antes de dejar pasar.
  static Future<void> clearPin() async {
    await PrismHubStorage.setSetting(_pinHashKey, null);
  }

  // ── Freno a la fuerza bruta ──────────────────────────────────────────────
  //
  // Un PIN de cuatro dígitos son 10.000 combinaciones: sin freno se prueban
  // todas en un rato con paciencia. Tras 5 fallos se bloquea 30 segundos, y
  // cada tanda siguiente duplica la espera hasta 15 minutos. Con eso el
  // recorrido completo pasa de minutos a semanas, sin molestar a quien
  // simplemente se equivocó una o dos veces.
  static const _failsKey = 'Nsfw18PinFails';
  static const _lockUntilKey = 'Nsfw18PinLockUntil';
  static const _fallosAntesDeBloquear = 5;

  /// Segundos que faltan para poder volver a intentar. 0 = se puede probar.
  static int get lockedSeconds {
    final hasta = PrismHubStorage.getSetting(_lockUntilKey);
    if (hasta is! int) return 0;
    final faltan = (hasta - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
    return faltan > 0 ? faltan : 0;
  }

  static int get _fails {
    final v = PrismHubStorage.getSetting(_failsKey);
    return v is int ? v : 0;
  }

  static Future<void> _registrarFallo() async {
    final fallos = _fails + 1;
    await PrismHubStorage.setSetting(_failsKey, fallos);
    if (fallos < _fallosAntesDeBloquear) return;
    // Tandas de 5: la primera espera 30s, la segunda 60s, después 120s… con
    // techo en 15 minutos para que un olvido no deje la zona inutilizable.
    final tandas = fallos ~/ _fallosAntesDeBloquear;
    final segundos = (30 * (1 << (tandas - 1))).clamp(30, 900);
    await PrismHubStorage.setSetting(
      _lockUntilKey,
      DateTime.now().millisecondsSinceEpoch + segundos * 1000,
    );
  }

  static Future<void> _limpiarFallos() async {
    if (_fails == 0 && lockedSeconds == 0) return;
    await PrismHubStorage.setSetting(_failsKey, 0);
    await PrismHubStorage.setSetting(_lockUntilKey, 0);
  }

  /// Verifica el PIN respetando el bloqueo. Devuelve false mientras esté
  /// bloqueado, sin siquiera comparar: si no, cada intento reiniciaría la
  /// cuenta y el freno no serviría de nada.
  static Future<bool> verifyPinChecked(String pin) async {
    if (lockedSeconds > 0) return false;
    if (!verifyPin(pin)) {
      await _registrarFallo();
      return false;
    }
    await _limpiarFallos();
    return true;
  }

  static bool verifyPin(String pin) {
    final stored = PrismHubStorage.getSetting(_pinHashKey);
    if (stored is! String) return false;
    return stored == _hash(pin);
  }

  // A propósito NO hay caché de "desbloqueado en esta sesión": el PIN se pide
  // CADA vez que se entra a la Zona +18 o a la lista de extensiones +18. Antes
  // se recordaba el desbloqueo mientras la app siguiera abierta, lo que dejaba
  // la zona accesible sin PIN a quien agarrara el dispositivo después — que es
  // justo de lo que protege el PIN.
}
