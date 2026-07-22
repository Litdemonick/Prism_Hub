import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:prismhub/controllers/application_controller.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/views/pages/debug_page.dart';
import 'package:prismhub/views/pages/main_page.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:window_manager/window_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main(List<String> args) async {
  if (args.contains('-version') || args.contains('--version')) {
    WidgetsFlutterBinding.ensureInitialized();
    final info = await PackageInfo.fromPlatform();
    debugPrint('PrismHub v${info.version}');
    exit(0);
  }

  runZonedGuarded(() async {
    FlutterError.onError = (FlutterErrorDetails details) {
      logger.severe("", details.exception, details.stack);
    };

    WidgetsFlutterBinding.ensureInitialized();

    // 多窗口
    if (args.firstOrNull == 'multi_window') {
      final windowId = int.parse(args[1]);
      final arguments = args[2].isEmpty
          ? const {}
          : jsonDecode(args[2]) as Map<String, dynamic>;

      Map windows = {
        "debug": ExtensionDebugWindow(
          windowController: WindowController.fromWindowId(windowId),
        ),
      };
      runApp(windows[arguments["name"]]);
      return;
    }

    // 主窗口
    await PrismHubDirectory.ensureInitialized();
    await PrismHubStorage.ensureInitialized();
    PrismLog.ensureInitialized();
    await ApplicationUtils.ensureInitialized();
    await PrismRequest.ensureInitialized();
    await ExtensionUtils.ensureInitialized();
    MediaKit.ensureInitialized();

    if (!Platform.isAndroid) {
      await windowManager.ensureInitialized();
      final sizeArr = PrismHubStorage.getSetting(SettingKey.windowSize).split(",");
      final size = Size(double.parse(sizeArr[0]), double.parse(sizeArr[1]));
      WindowOptions windowOptions = WindowOptions(
        size: size,
        center: true,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        // 900×600 is the minimum viable reading size; prevents layout breaks.
        await windowManager.setMinimumSize(const Size(900, 600));
        final position = PrismHubStorage.getSetting(SettingKey.windowPosition);
        if (position != null) {
          final offsetArr = position.split(",");
          final offset = Offset(
            double.parse(offsetArr[0]),
            double.parse(offsetArr[1]),
          );
          await windowManager.setPosition(offset);
        }
        await windowManager.show();
        await windowManager.focus();
      });
    }

    if (Platform.isAndroid) {
      SystemUiOverlayStyle style = const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      );
      SystemChrome.setSystemUIOverlayStyle(style);
    }

    runApp(const MainApp());
  }, (error, stack) {
    logger.severe("", error, stack);
  });
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late ApplicationController c;

  @override
  void initState() {
    c = Get.put(ApplicationController());
    super.initState();
  }

  Widget _buildMobileMain(BuildContext context) {
    const cjkFontFallback = [
      "Noto Sans CJK JP",
      "Noto Sans CJK KR",
      "Noto Sans CJK TC",
      "Noto Sans CJK HK",
      "Microsoft Yahei",
      "SimSun",
      "Arial Unicode MS",
    ];
    return GetMaterialApp(
      title: "PrismHub",
      debugShowCheckedModeBanner: false,
      themeMode: c.theme,
      theme: _buildTheme(Brightness.light, cjkFontFallback),
      darkTheme: _buildTheme(Brightness.dark, cjkFontFallback),
      home: const AndroidMainPage(),
      localizationsDelegates: [
        I18nUtils.flutterI18nDelegate,
      ],
    );
  }

  // Azul + dorado — antes usaba el morado por default de Material 3 (sin
  // seed explícito). El dorado queda como color secundario/terciario; el
  // sistema de temas actual solo da para esto, personalización de verdad
  // queda para más adelante.
  static const _brandGold = Color(0xFFC9A227);

  ThemeData _buildTheme(Brightness brightness, List<String> fallback) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    ).copyWith(
      secondary: _brandGold,
      tertiary: _brandGold,
    );
    return base.copyWith(
      colorScheme: scheme,
      textTheme: _buildTextTheme(brightness, fallback),
    );
  }

  TextTheme _buildTextTheme(Brightness brightness, List<String> fallback) {
    final color = brightness == Brightness.dark ? Colors.white : Colors.black;
    return TextTheme(
      displayLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      displayMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      displaySmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      headlineLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      headlineMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      headlineSmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      titleLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      titleMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      titleSmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      bodyLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      bodyMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      bodySmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      labelLarge: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      labelMedium: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
      labelSmall: TextStyle(fontFamily: "Noto Sans CJK SC", fontFamilyFallback: fallback, color: color),
    );
  }

  Widget _buildDesktopMain(BuildContext context) {
    return fluent.FluentApp.router(
      title: 'PrismHub',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: c.theme,
      darkTheme: fluent.FluentThemeData(
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
        accentColor: fluent.Colors.blue,
      ),
      theme: fluent.FluentThemeData(
        visualDensity: VisualDensity.standard,
        accentColor: fluent.Colors.blue,
      ),
      localizationsDelegates: [
        I18nUtils.flutterI18nDelegate,
      ],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: "Noto Sans CJK SC",
                fontFamilyFallback: [
                  "Noto Sans CJK JP",
                  "Noto Sans CJK KR",
                  "Noto Sans CJK TC",
                  "Noto Sans CJK HK",
                  "Microsoft Yahei",
                  "SimSun",
                  "Arial Unicode MS",
                ],
              ),
              // El embedder de Windows spamea "Failed to update ui::AXTree"
              // en cualquier página con rebuilds frecuentes (Obx, streams de
              // posición/progreso, listas reactivas) — es ruido del engine,
              // no un bug de la app. Se excluye semántica en toda la app de
              // escritorio (ya se hacía puntualmente en el reproductor).
              child: ExcludeSemantics(
                child: child ?? const SizedBox(),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildMobileMain,
      desktopBuilder: _buildDesktopMain,
    );
  }
}
