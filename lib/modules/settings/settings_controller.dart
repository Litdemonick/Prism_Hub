import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/utils/app_storage.dart';

class SettingsController extends GetxController {
  final themeMode = ThemeMode.system.obs;

  @override
  void onInit() {
    super.onInit();
    final saved = AppStorage.getString(StorageKey.themeMode);
    themeMode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark'  => ThemeMode.dark,
      _       => ThemeMode.system,
    };
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode.value = mode;
    final key = switch (mode) {
      ThemeMode.light  => 'light',
      ThemeMode.dark   => 'dark',
      ThemeMode.system => 'system',
    };
    await AppStorage.setString(StorageKey.themeMode, key);
  }
}
