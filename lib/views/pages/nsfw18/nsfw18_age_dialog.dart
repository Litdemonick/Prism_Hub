import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';

/// Confirmación de mayoría de edad al ACTIVAR el contenido +18. Una sola vez:
/// una vez declarada, no se vuelve a preguntar.
///
/// Se pide la fecha de nacimiento y no un "¿sos mayor?" con Sí/No. Ninguna de
/// las dos verifica nada de verdad —el mismo dispositivo pregunta y responde—
/// pero una fecha cuesta más de responder a la ligera que un botón, y deja
/// constancia con día y hora de lo que el usuario declaró. Eso es lo que se
/// mira si alguna vez hay que demostrar diligencia.
///
/// Verificación real necesitaría un proveedor externo con documento, servidor y
/// manejo de datos personales sensibles. Y esa obligación, hoy, recae sobre
/// quien aloja el contenido, no sobre un cliente local.
class Nsfw18AgeDialog {
  Nsfw18AgeDialog._();

  static const int _edadMinima = 18;

  /// true si ya declaró la edad antes.
  static bool get yaDeclarada {
    final v = PrismHubStorage.getSetting(SettingKey.adultDeclaredAt);
    return v is String && v.isNotEmpty;
  }

  /// Devuelve true si puede activarse el contenido +18.
  static Future<bool> confirmar(BuildContext context) async {
    if (yaDeclarada) return true;

    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      helpText: 'nsfw18.age-help'.i18n,
      // Se abre en un año plausible para un adulto en vez de en hoy: partir de
      // la fecha actual obliga a retroceder décadas con el selector.
      initialDate: DateTime(hoy.year - 25, hoy.month, hoy.day),
      firstDate: DateTime(hoy.year - 100),
      lastDate: hoy,
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) => Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: HomeTheme.accentRed,
            brightness: Brightness.dark,
          ),
        ),
        child: child!,
      ),
    );

    if (elegida == null) return false;

    final edad = _edad(elegida, hoy);
    if (edad < _edadMinima) {
      if (context.mounted) {
        await showPlatformDialog(
          context: context,
          title: 'nsfw18.age-denied-title'.i18n,
          content: Text(
            'nsfw18.age-denied'.i18n,
            style: TextStyle(color: HomeTheme.textMuted, height: 1.45),
          ),
          actions: [
            Builder(
              builder: (ctx) => PlatformFilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('common.confirm'.i18n),
              ),
            ),
          ],
        );
      }
      return false;
    }

    // Se guarda CUÁNDO lo declaró, no la fecha de nacimiento: para el app
    // alcanza con saber que declaró ser mayor y cuándo. Guardar la fecha de
    // nacimiento sería conservar un dato personal que no hace falta para nada.
    await PrismHubStorage.setSetting(
      SettingKey.adultDeclaredAt,
      DateTime.now().toIso8601String(),
    );
    return true;
  }

  static int _edad(DateTime nacimiento, DateTime hoy) {
    var edad = hoy.year - nacimiento.year;
    final cumplioEsteAno = (hoy.month > nacimiento.month) ||
        (hoy.month == nacimiento.month && hoy.day >= nacimiento.day);
    if (!cumplioEsteAno) edad--;
    return edad;
  }
}
