import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_i18n/loaders/decoders/json_decode_strategy.dart';
import 'package:get/get.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

final _context =
    Platform.isAndroid ? Get.context! : rootNavigatorKey.currentContext!;

class I18nUtils {
  // Los únicos idiomas que la app trae traducidos. Tener archivos a medio
  // traducir era una fuente silenciosa de fallos: una clave que falta en un
  // idioma no se nota hasta que alguien abre esa pantalla en ese idioma.
  static const supportedLanguages = {'en', 'es'};
  static const fallbackLanguage = 'es';

  // getSetting devuelve null si el almacenamiento no llegó a inicializar, y
  // Locale() pide un String NO nulable: pasarle null tira "type 'Null' is not
  // a subtype of type 'String'" mientras se construye la app, o sea pantalla
  // muerta sin explicación. También se valida contra la lista: un idioma
  // guardado que ya no existe (ej. de una versión anterior con más idiomas)
  // dejaría al cargador buscando un archivo que no está.
  static String get currentLanguageCode {
    final saved = PrismHubStorage.getSetting(SettingKey.language);
    if (saved is String && supportedLanguages.contains(saved)) return saved;
    return fallbackLanguage;
  }

  static final flutterI18nDelegate = FlutterI18nDelegate(
    translationLoader: FileTranslationLoader(
      useCountryCode: false,
      fallbackFile: 'en',
      basePath: 'assets/i18n',
      forcedLocale: Locale(currentLanguageCode),
      decodeStrategies: [JsonDecodeStrategy()],
    ),
  );

// 获取当前语言
  static Locale? get currentLanguage => FlutterI18n.currentLocale(_context);

// 切换语言
  static Future changeLanguage(String locale) async {
    await FlutterI18n.refresh(_context, Locale(locale));
    await Get.forceAppUpdate();
  }
}

extension I18nString on String {
  String get i18n => FlutterI18n.translate(_context, this);
}
