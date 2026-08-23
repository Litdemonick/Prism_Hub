import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Reporte de errores (Sentry).
///
/// Apagado por defecto, opt-in: la app también se usa para ver contenido
/// +18, y un reporte de error puede arrastrar la URL o el nombre de la
/// extensión que estaba abierta en ese momento —los mensajes de las
/// excepciones de las extensiones a veces la incluyen directamente, ver
/// ixxx.com respondió con una verificación de Cloudflare...). Es la misma
/// discreción que ya rige para el repositorio (ver CLAUDE.md), aplicada acá
/// a un tercero en vez de a git: nada sale salvo que el usuario prenda el
/// ajuste a mano, y lo que sale se recorta antes de mandarse.
class SentryConfig {
  SentryConfig._();

  /// El DSN del proyecto de Sentry (sentry.io → Settings → Client Keys).
  /// Vacío = no se manda nada, así el usuario prenda el ajuste o no.
  static const String dsn = 'https://7306bbb551b137fe8f9231dc32d2a6fe@o4511962280689664.ingest.us.sentry.io/4511962289340416';

  static Future<void> init() async {
    if (dsn.isEmpty) return;
    await SentryFlutter.init((options) {
      options.dsn = dsn;
      // Nunca datos identificatorios del usuario (IP, etc.) más allá de lo
      // mínimo que Sentry necesita para agrupar eventos. Ya es el default
      // del SDK; se deja explícito para que no dependa de que no cambie.
      options.sendDefaultPii = false;
      // Se filtra en cada evento, no solo una vez al mandar: así el ajuste
      // de Settings hace efecto al toque, sin reiniciar la app.
      options.beforeSend = (event, hint) async {
        if (PrismHubStorage.getSetting(SettingKey.errorTelemetry) != true) {
          return null;
        }
        return _sinUrls(event);
      };
      // Los breadcrumbs de red (fetch/http) traen la URL completa de lo que
      // se estaba pidiendo — justo lo que hay que no mandar. El resto
      // (navegación entre pantallas, taps) no dice de qué extensión ni qué
      // título se trataba, así que esos sí quedan: ayudan a entender qué
      // hacía el usuario justo antes del error.
      options.beforeBreadcrumb = (breadcrumb, hint) {
        final categoria = breadcrumb?.category ?? breadcrumb?.type ?? '';
        if (categoria == 'http' || categoria.contains('http')) return null;
        return breadcrumb;
      };
    });
  }

  /// Saca cualquier URL del texto de las excepciones antes de mandarlas.
  ///
  /// No hay forma de saber en general qué excepción trae una URL adentro del
  /// mensaje y cuál no —varias de las que tira este mismo código, como el
  /// aviso de Cloudflare de ixxx, la incluyen a propósito para poder
  /// diagnosticar—, así que se recorta cualquier http(s):// del texto en vez
  /// de tratar de adivinar caso por caso.
  static SentryEvent _sinUrls(SentryEvent event) {
    final exceptions = event.exceptions;
    if (exceptions == null || exceptions.isEmpty) return event;
    final limpias = exceptions.map((ex) {
      final valor = ex.value;
      if (valor == null || !valor.contains('http')) return ex;
      return ex.copyWith(
        value: valor.replaceAll(RegExp(r'https?://\S+'), '[url omitida]'),
      );
    }).toList();
    return event.copyWith(exceptions: limpias);
  }
}
