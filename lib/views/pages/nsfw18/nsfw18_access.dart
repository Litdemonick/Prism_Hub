import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_lock_page.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';

// Compuerta reutilizable de acceso a algo +18 desde CUALQUIER punto de la app:
// confirmación ("¿querés entrar?") y después PIN, las dos veces, siempre.
// Devuelve true solo si el usuario pasó ambos pasos.
//
// Existe aparte de Nsfw18SearchGate/Nsfw18ZoneGate porque esos son PÁGINAS (la
// zona entera vive detrás de ellas) y acá hace falta preguntar y seguir en el
// mismo lugar — por ejemplo al tocar una extensión +18 en Extensiones
// instaladas, donde después hay que navegar a su buscador.
//
// Usa Navigator y no Get.to a propósito: Get.to NO navega en escritorio (el
// navegador de GetX solo está activo en Android, ver main.dart), y esta función
// tiene que funcionar igual en Windows, Linux y Android.
Future<bool> confirmNsfw18Access(
  BuildContext context, {
  // El texto por defecto habla de "esta extensión" (pensado para el toque
  // sobre una tarjeta puntual). Filtrar una LISTA para revelar varias +18 de
  // golpe (Instaladas, Repositorio) es otra situación y pide su propio
  // texto — quien llama pasa el que corresponda.
  String? contentText,
}) async {
  if (PrismHubStorage.getSetting(SettingKey.enableNSFW) != true) {
    showPlatformSnackbar(
      context: context,
      title: 'nsfw18.disabled-title'.i18n,
      content: 'nsfw18.disabled-subtitle'.i18n,
    );
    return false;
  }

  // OJO con el tipo: showPlatformDialog no declara retorno, así que hay que
  // await-ear y comparar contra true en vez de asignarlo a un Future<bool?>
  // (eso explota en runtime con "Future<dynamic> is not a subtype of").
  final confirmed = await showPlatformDialog(
    context: context,
    title: 'nsfw18.confirm-enter-title'.i18n,
    content: Text(contentText ?? 'nsfw18.extension-enter-content'.i18n),
    actions: [
      PlatformTextButton(
        onPressed: () => RouterUtils.pop(false),
        child: Text('nsfw18.search-enter-no'.i18n),
      ),
      PlatformFilledButton(
        onPressed: () => RouterUtils.pop(true),
        child: Text('nsfw18.search-enter-yes'.i18n),
      ),
    ],
  );
  if (confirmed != true || !context.mounted) return false;

  // El PIN se pide SIEMPRE (no hay caché de "ya desbloqueado", ver Nsfw18Zone).
  // Si el usuario se vuelve atrás, la ruta popea con null y eso cuenta como no
  // autorizado.
  final unlocked = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (ctx) => Nsfw18LockPage(
        onUnlocked: () => Navigator.of(ctx).pop(true),
      ),
    ),
  );
  return unlocked == true;
}
