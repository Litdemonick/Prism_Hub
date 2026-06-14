import 'package:shared_preferences/shared_preferences.dart';

abstract final class StorageKey {
  static const String themeMode = 'theme_mode';
  static const String locale = 'locale';
  static const String extensionRepos = 'extension_repos';
  static const String windowSize = 'window_size';
  static const String windowPosition = 'window_position';
}

class AppStorage {
  AppStorage._();

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String? getString(String key) => _prefs.getString(key);
  static Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  static bool? getBool(String key) => _prefs.getBool(key);
  static Future<void> setBool(String key, bool value) =>
      _prefs.setBool(key, value);

  static List<String> getStringList(String key) =>
      _prefs.getStringList(key) ?? [];
  static Future<void> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);
}
