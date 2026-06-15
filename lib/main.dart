import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config/app_config.dart';
import 'core/db/database_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_directory.dart';
import 'core/utils/app_storage.dart';
import 'core/utils/logger.dart';
import 'data/services/extension/extension_loader.dart';
import 'data/services/extension/extension_service.dart';
import 'modules/settings/settings_controller.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.contains('--version') || args.contains('-version')) {
    print('PrismHub ${AppConfig.version}');
    exit(0);
  }

  FlutterError.onError = (details) =>
      log.severe('Flutter error', details.exception, details.stack);

  // Inicialización en orden
  await AppStorage.init();
  await AppDirectory.init();
  await DatabaseService.init();
  ExtensionService.init();
  await ExtensionLoader.loadAll();
  MediaKit.ensureInitialized();
  Get.put(SettingsController());

  if (!Platform.isAndroid && !Platform.isIOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1200, 780),
        minimumSize: Size(1000, 680), // mantiene NavigationRail siempre visible
        center: true,
        titleBarStyle: TitleBarStyle.normal, // botones nativos min/max/close
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  if (Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }

  runApp(const PrismApp());
}

class PrismApp extends StatelessWidget {
  const PrismApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = Get.find<SettingsController>();
      return MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: settings.themeMode.value,
        routerConfig: AppRouter.config,
      );
    });
  }
}
