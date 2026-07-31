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
  }

  // Quita el PIN configurado — la próxima vez que se intente entrar a la
  // zona, se pide configurar uno nuevo antes de dejar pasar.
  static Future<void> clearPin() async {
    await PrismHubStorage.setSetting(_pinHashKey, null);
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
