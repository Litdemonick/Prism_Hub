import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Credencial del dispositivo (huella o rostro en Android, Windows Hello en
/// Windows) como primer paso para entrar a la Zona +18, antes del PIN.
///
/// Es la barrera más fuerte que se puede poner sin servidor: el PIN es un
/// secreto que se puede mirar por encima del hombro, mientras que esto está
/// atado a quien configuró el dispositivo.
///
/// Reglas de la casa:
/// - Si el dispositivo NO tiene biometría ni credencial configurada, se deja
///   pasar al PIN. Bloquear ahí dejaría al usuario sin forma de entrar a algo
///   que ya había configurado.
/// - En Linux se omite: local_auth no tiene implementación y siempre fallaría.
/// - En Android TV se omite también, a propósito. `isDeviceSupported()` no
///   solo mira huella/rostro: da por válido CUALQUIER bloqueo de pantalla del
///   sistema (PIN/patrón de Android), y un televisor puede perfectamente
///   tener uno configurado para restricciones parentales de la propia
///   Play Store. Pedirlo acá metía un paso más, ajeno a la app y sin probar
///   con un mando, antes de llegar recién al PIN propio de PrismHub —
///   pedido explícito: "no es huella ni nada de esto, solamente el PIN".
class Nsfw18Biometric {
  Nsfw18Biometric._();

  static final _auth = LocalAuthentication();

  /// true = seguir al PIN. false = el usuario canceló o falló la credencial.
  static Future<bool> authenticate() async {
    if (Platform.isLinux || PlatformTv.esTelevisionSync) return true;
    try {
      // isDeviceSupported cubre también el PIN/patrón del sistema, no solo
      // la biometría — así sirve en un equipo sin lector de huella.
      final soportado = await _auth.isDeviceSupported();
      if (!soportado) return true;
      final disponible = await _auth.canCheckBiometrics ||
          await _auth.getAvailableBiometrics().then((l) => l.isNotEmpty);
      if (!disponible && !soportado) return true;

      return await _auth.authenticate(
        localizedReason: 'nsfw18.biometric-reason'.i18n,
        options: const AuthenticationOptions(
          // Se acepta la credencial del sistema (PIN/patrón/contraseña) además
          // de la biometría: si no, alguien con el lector roto se quedaría
          // afuera para siempre.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e, st) {
      // Un fallo del plugin no puede dejar la zona inaccesible: se registra y
      // se sigue al PIN, que es la barrera de siempre.
      logger.warning('Biometría no disponible para la Zona +18: $e', e, st);
      return true;
    }
  }
}
