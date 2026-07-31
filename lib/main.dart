import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:prismhub/controllers/application_controller.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/views/pages/debug_page.dart';
import 'package:prismhub/views/pages/main_page.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart';
import 'package:prismhub/views/pages/splash_screen.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
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

    // En release, el ErrorWidget por defecto de Flutter es un rectángulo GRIS
    // SIN TEXTO. Si algo falla al construir el árbol, la pantalla queda gris
    // entera y no dice absolutamente nada — y como el estado que dispara el
    // fallo está guardado en disco, vuelve a pasar en cada arranque y parece
    // que la app "se rompió para siempre" (reportado en vivo en Android).
    // Mostrando el error se puede leer qué pasó en vez de adivinar.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      logger.severe("ErrorWidget", details.exception, details.stack);
      // Se incluye el ORIGEN además del mensaje: "type 'Null' is not a
      // subtype of type 'String'" a secas no dice en qué widget pasó, y sin
      // eso hay que adivinar. Con la librería y las primeras líneas del
      // stack se ubica el archivo exacto de una.
      const nl = '\n';
      final where = details.library ?? '';
      final frames = (details.stack?.toString() ?? '')
          .split(nl)
          .where((l) => l.contains('package:prismhub'))
          .take(4)
          .join(nl);
      final parts = <String>[
        '${details.exception}',
        if (where.isNotEmpty) '[$where]',
        if (frames.isNotEmpty) frames,
      ];
      return _StartupErrorView(message: parts.join('$nl$nl'));
    };

    WidgetsFlutterBinding.ensureInitialized();

    // Instrumentación temporal de frames — para diagnosticar tirones reales.
    // En Windows debug, totalSpan también sube cuando hay huecos entre frames
    // durante hot restart/arranque aunque build+raster hayan costado casi
    // nada (ej. total=10s, build=2ms, raster=1ms). Eso no es jank visible de
    // la UI; reportamos solo cuando el hilo UI o raster sí hicieron trabajo
    // pesado.
    WidgetsBinding.instance.addTimingsCallback((List<ui.FrameTiming> timings) {
      for (final timing in timings) {
        final buildMs = timing.buildDuration.inMilliseconds;
        final rasterMs = timing.rasterDuration.inMilliseconds;
        final totalMs = timing.totalSpan.inMilliseconds;
        final workMs = buildMs + rasterMs;
        if (buildMs > 50 || rasterMs > 50 || workMs > 80) {
          logger.warning(
            'FRAME LENTO: build=${buildMs}ms raster=${rasterMs}ms total=${totalMs}ms',
          );
        }
      }
    });

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

    // 主窗口 — solo lo indispensable para calcular tamaño/posición de la
    // ventana va acá; el resto (log, red, extensiones, media_kit) se hace
    // durante el splash, ya con algo visible en pantalla en vez de una
    // ventana oculta/en blanco mientras carga.
    try {
      await PrismHubDirectory.ensureInitialized();
    } catch (e, st) {
      // Antes esto NO estaba protegido: era el único await sin try del
      // arranque en Android. Si fallaba (permisos, almacenamiento lleno,
      // path_provider devolviendo error), la excepción salía de main() sin
      // que se llamara nunca a runApp, y el motor se quedaba mostrando el
      // fondo vacío de la ventana para siempre, sin un solo mensaje.
      logger.severe("PrismHubDirectory.ensureInitialized falló", e, st);
      runApp(_StartupErrorApp(message: '$e'));
      return;
    }
    try {
      await PrismHubStorage.ensureInitialized();
    } catch (e, st) {
      // Antes esto solo se logueaba y se seguía como si nada. No se puede:
      // con el almacenamiento caído, TODOS los getSetting() devuelven null, y
      // el primero que se usa al construir la app es el idioma —
      // `Locale(getSetting(language))` con null revienta con "type 'Null' is
      // not a subtype of type 'String'". Eso tira el árbol entero, o sea
      // pantalla muerta sin ninguna explicación, en cada arranque mientras el
      // almacenamiento siga roto. Mejor decirlo de frente.
      logger.severe("PrismHubStorage.ensureInitialized falló", e, st);
      runApp(_StartupErrorApp(message: '$e'));
      return;
    }

    // Crea el entorno de WebView2 ya al arrancar, mientras COM del proceso
    // está recién inicializado y sano (ver el comentario largo en
    // webview_player_page.dart). Creado una sola vez acá, el reproductor
    // WebView lo reusa toda la sesión y nunca vuelve a pasar por la llamada
    // nativa que fallaba con CO_E_NOTINITIALIZED a mitad de uso. Sin await:
    // no debe atrasar el arranque, y si falla se resuelve solo más tarde.
    if (Platform.isWindows) {
      unawaited(ensureWebViewEnvironment());
    }

    if (!Platform.isAndroid) {
      await windowManager.ensureInitialized();
      const minWindowSize = Size(900, 600);
      const defaultWindowSize = Size(1280, 720);
      var size = defaultWindowSize;
      final windowSize = PrismHubStorage.getSetting(SettingKey.windowSize);
      if (windowSize is String) {
        try {
          final sizeArr = windowSize.split(",");
          final saved = Size(
            double.parse(sizeArr[0]),
            double.parse(sizeArr[1]),
          );
          if (saved.width.isFinite &&
              saved.height.isFinite &&
              saved.width >= minWindowSize.width &&
              saved.height >= minWindowSize.height) {
            size = saved;
          }
        } catch (_) {}
      }
      WindowOptions windowOptions = WindowOptions(
        size: size,
        center: true,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        // 900×600 is the minimum viable reading size; prevents layout breaks.
        await windowManager.setMinimumSize(minWindowSize);
        final position = PrismHubStorage.getSetting(SettingKey.windowPosition);
        if (position != null) {
          final offsetArr = position.split(",");
          final offset = Offset(
            double.parse(offsetArr[0]),
            double.parse(offsetArr[1]),
          );
          await windowManager.setPosition(offset);
        }
        // NO gatear este show() contra el primer frame de Flutter: el runner
        // nativo de Windows ya lo hace por su cuenta
        // (SetNextFrameCallback -> this->Show() en flutter_window.cpp), así que
        // esperar acá al primer frame hace que los DOS shows disparen en el
        // mismo instante y compitan entre sí y con el setPosition de arriba.
        // Resultado confirmado en vivo: la ventana quedaba con un tamaño y el
        // surface de Flutter pintado con otro — app chica dentro de un marco
        // negro. Mostrar acá cuanto antes es lo correcto; el gate del primer
        // frame ya lo cubre el lado nativo.
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

    runApp(const _AppRoot());
  }, (error, stack) {
    logger.severe("", error, stack);
  });
}

// Muestra el splash animado mientras corre el resto de la inicialización
// (log, red, extensiones, media_kit) — antes esto pasaba antes de runApp(),
// así que la ventana quedaba oculta/en blanco sin ningún indicio de que la
// app estaba cargando.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Duración mínima: en una red rápida esta inicialización termina en
    // milisegundos y la animación del splash ni se alcanza a ver — se fuerza
    // a que el splash quede visible al menos este tiempo, sin importar qué
    // tan rápido termine todo lo demás.
    final minDuration = Future.delayed(const Duration(milliseconds: 1400));
    PrismLog.ensureInitialized();
    try {
      await ApplicationUtils.ensureInitialized();
    } catch (e) {
      debugPrint('ERROR: ApplicationUtils.ensureInitialized falló: $e');
    }
    try {
      await ConnectivityUtils.ensureInitialized();
    } catch (e) {
      debugPrint('ERROR: ConnectivityUtils.ensureInitialized falló: $e');
    }
    try {
      await PrismRequest.ensureInitialized();
    } catch (e) {
      debugPrint('ERROR: PrismRequest.ensureInitialized falló: $e');
    }
    try {
      await ExtensionUtils.ensureInitialized();
    } catch (e) {
      debugPrint('ERROR: ExtensionUtils.ensureInitialized falló: $e');
    }
    try {
      MediaKit.ensureInitialized();
    } catch (e) {
      debugPrint('ERROR: MediaKit.ensureInitialized falló: $e');
    }
    await minDuration;
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashScreen(),
      );
    }
    return const MainApp();
  }
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

  // Morado (HomeTheme.accentPink) + dorado — antes usaba azul. El dorado
  // queda como color secundario/terciario; el sistema de temas actual solo
  // da para esto, personalización de verdad queda para más adelante.
  static const _brandGold = Color(0xFFC9A227);
  static final _fluentAccent = fluent.AccentColor.swatch(const {
    'normal': HomeTheme.accentPink,
  });

  ThemeData _buildTheme(Brightness brightness, List<String> fallback) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: HomeTheme.accentPink,
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
      displayLarge: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      displayMedium: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      displaySmall: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      headlineLarge: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      headlineMedium: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      headlineSmall: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      titleLarge: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      titleMedium: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      titleSmall: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      bodyLarge: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      bodyMedium: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      bodySmall: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      labelLarge: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      labelMedium: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
      labelSmall: TextStyle(
          fontFamily: "Noto Sans CJK SC",
          fontFamilyFallback: fallback,
          color: color),
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
        accentColor: _fluentAccent,
      ),
      theme: fluent.FluentThemeData(
        visualDensity: VisualDensity.standard,
        accentColor: _fluentAccent,
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

// ── Pantallas de fallo ──────────────────────────────────────────────────────
//
// Existen por un motivo concreto: en release el ErrorWidget por defecto de
// Flutter es un rectángulo gris SIN texto, y un fallo antes de runApp no
// muestra nada en absoluto. Las dos cosas se ven igual —pantalla muerta— y no
// dejan ninguna pista de qué pasó, así que un problema puntual parecía "la app
// se rompió para siempre". Mostrar el error no lo arregla, pero lo vuelve
// diagnosticable en vez de invisible.

class _StartupErrorView extends StatelessWidget {
  const _StartupErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    // Sin Scaffold ni Material a propósito: este widget puede terminar
    // insertado en CUALQUIER punto del árbol (es el reemplazo de un widget
    // que falló), incluso donde no hay un MaterialApp arriba. Solo usa cosas
    // que funcionan sueltas: Directionality, Container y Text con estilo
    // explícito (sin DefaultTextStyle heredado no hay fuente ni color).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF14090D),
        padding: const EdgeInsets.all(14),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFEAEBF2),
              fontSize: 12,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF08090D),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: Color(0xFFD777ED), size: 44),
                  const SizedBox(height: 16),
                  const Text(
                    'PrismHub no pudo iniciarse',
                    style: TextStyle(
                      color: Color(0xFFEAEBF2),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No se pudo preparar el almacenamiento de la app. '
                    'Suele ser falta de espacio o de permisos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF7E8087), fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  SelectableText(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF7E8087), fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
