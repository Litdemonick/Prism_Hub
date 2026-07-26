import 'package:get/get.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

// "Ocultar" una tarjeta de Continuar/Favoritos/Historial — reemplaza su
// portada real por el arte genérico de PRISM_HUB (carddefaultoffline.png), para que
// alguien mirando de reojo la pantalla no vea de qué es. No borra el
// historial/favorito, solo lo tapa visualmente. Guardado en Hive (sin
// necesitar migración de esquema de Isar) y espejado en un RxSet para que
// los Obx que ya envuelven Home/Historial se refresquen solos al togglear.
class HiddenCards {
  HiddenCards._();

  static final RxSet<String> _hidden = <String>{}.obs;
  static bool _loaded = false;

  static String keyFor(String package, String url) => '$package|$url';

  static void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = PrismHubStorage.getSetting(SettingKey.hiddenCards);
    if (raw is List) {
      _hidden.addAll(raw.cast<String>());
    }
  }

  static bool isHidden(String package, String url) {
    ensureLoaded();
    return _hidden.contains(keyFor(package, url));
  }

  static Future<void> toggle(String package, String url) async {
    ensureLoaded();
    final key = keyFor(package, url);
    if (_hidden.contains(key)) {
      _hidden.remove(key);
    } else {
      _hidden.add(key);
    }
    await PrismHubStorage.setSetting(SettingKey.hiddenCards, _hidden.toList());
  }
}
