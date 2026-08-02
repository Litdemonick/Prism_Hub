import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:prismhub/utils/compartir.dart';
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
      // La posición guardada se lee ANTES de armar las opciones: si hay una,
      // no se centra. Centrar y después mover son dos órdenes que se pisan
      // durante el arranque.
      final offsetGuardado = _leerPosicionGuardada();
      WindowOptions windowOptions = WindowOptions(
        size: size,
        center: offsetGuardado == null,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        try {
          // 900×600 is the minimum viable reading size; prevents layout breaks.
          await windowManager.setMinimumSize(minWindowSize);
          await _restaurarGeometria(size, offsetGuardado);
        } catch (e, st) {
          logger.warning(
              'No se pudo restaurar la geometría de la ventana', e, st);
        } finally {
          // La ventana se muestra recién cuando Flutter YA pintó algo.
          //
          // Antes se mostraba acá mismo, y eso deja un hueco: en este punto la
          // geometría ya está puesta pero runApp todavía no corrió, así que el
          // motor no tiene ni un fotograma dibujado al tamaño nuevo. Lo que se
          // ve en ese hueco es la superficie vieja —del tamaño con el que se
          // creó la ventana— estirada o encogida dentro del marco nuevo: el
          // contenido chico en una esquina con franjas negras alrededor.
          //
          // En release el hueco son milisegundos y casi no se nota. Con
          // `flutter run` la compilación en caliente lo estira muchísimo, que
          // es por qué ahí se ve siempre.
          //
          // Ver _mostrarVentanaCuandoHayaFotograma: se muestra en el primer
          // post-frame, con red de seguridad por si ese fotograma nunca llega.
          // El tamaño REAL que quedó, no el pedido: si Windows lo ajustó (otro
          // monitor, otra escala), esperar a que la superficie mida el pedido
          // sería esperar algo que nunca va a pasar.
          var medida = size;
          try {
            final real = await windowManager.getSize();
            if (real.width > 0 && real.height > 0) medida = real;
          } catch (_) {
            // Con el tamaño pedido alcanza; para eso está la tolerancia.
          }
          _mostrarVentanaCuandoHayaFotograma(medida);
        }
      });
    }

    if (Platform.isAndroid) {
      SystemUiOverlayStyle style = const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      );
      SystemChrome.setSystemUIOverlayStyle(style);
    }

    // Si la app se abrió por un enlace compartido, se anota para navegar
    // cuando el árbol ya exista. No se usa como ruta inicial a propósito: así
    // el arranque es el de siempre y la ficha queda ENCIMA de la pantalla
    // principal, con su botón de volver funcionando como cualquier otra.
    Compartir.enlacePendiente = Compartir.enlaceDeArranque(args);

    runApp(const _AppRoot());
  }, (error, stack) {
    logger.severe("", error, stack);
  });
}

/// Muestra la ventana en cuanto Flutter haya pintado su primer fotograma.
///
/// Mostrarla antes deja ver la superficie vieja dentro del marco nuevo (ver
/// dónde se llama). Esperando al primer fotograma, lo primero que se ve ya está
/// dibujado al tamaño correcto.
///
/// La red de seguridad NO es opcional: el runner nativo ya no muestra la
/// ventana por su cuenta (ver windows/runner/flutter_window.cpp), así que si el
/// primer fotograma no llegara —un fallo al construir el árbol, por ejemplo— la
/// app quedaría corriendo sin ninguna ventana visible, solo en el administrador
/// de tareas. Pasado el plazo se muestra igual, aunque se vea mal: es mejor una
/// ventana fea que ninguna.
void _mostrarVentanaCuandoHayaFotograma(Size esperada) {
  var mostrada = false;
  Future<void> mostrar() async {
    if (mostrada) return;
    mostrada = true;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      logger.warning('No se pudo mostrar la ventana', e, st);
    }
  }

  // Esperar UN fotograma no alcanzaba.
  //
  // La ventana la crea el runner nativo con un tamaño, y recién después se le
  // pide el guardado. Ese cambio de tamaño llega al motor como un WM_SIZE, que
  // es asincrónico: si Flutter alcanza a pintar su primer cuadro antes de que
  // llegue, ese cuadro está dibujado al tamaño VIEJO. Mostrando ahí se ve
  // exactamente lo que se veía — el contenido chico arrinconado dentro de un
  // marco más grande, con franjas negras arriba y a la derecha.
  //
  // Así que además de que haya cuadro, se espera a que la superficie mida lo
  // que mide el marco y se quede quieta unos cuadros seguidos. La tolerancia
  // absorbe el grosor del borde de la ventana, que no es parte del área que
  // Flutter dibuja.
  Size? anterior;
  var estables = 0;
  var cuadros = 0;
  void comprobar(Duration _) {
    if (mostrada) return;
    cuadros++;
    final vista = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (vista != null && vista.devicePixelRatio > 0) {
      final actual = vista.physicalSize / vista.devicePixelRatio;
      estables = (anterior != null && actual == anterior) ? estables + 1 : 0;
      anterior = actual;
      final coincide = (actual.width - esperada.width).abs() <= 24 &&
          (actual.height - esperada.height).abs() <= 24;
      if (coincide && estables >= 2) {
        mostrar();
        return;
      }
    }
    // ~1,3 s a 60 cuadros: si en ese rato nunca coincidió, mostrarla igual es
    // mejor que dejar al usuario mirando la nada.
    if (cuadros > 80) {
      mostrar();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(comprobar);
    // Sin esto no habría más cuadros que mirar: con la pantalla quieta, Flutter
    // no dibuja de nuevo y el callback no se volvería a llamar nunca.
    WidgetsBinding.instance.scheduleFrame();
  }

  WidgetsBinding.instance.addPostFrameCallback(comprobar);
  // Dos segundos: de sobra para el primer fotograma incluso arrancando en
  // frío, y poco como para que un arranque roto no parezca un cuelgue.
  Timer(const Duration(seconds: 2), mostrar);
}

/// Deja la ventana en la posición y el tamaño de la sesión anterior, y
/// comprueba que haya quedado ahí de verdad.
///
/// La comprobación no sobra. El tamaño guardado está en píxeles lógicos, y
/// Windows lo convierte a físicos con el DPI del monitor donde esté la ventana
/// en ese momento. Al arrancar, la ventana nace SIEMPRE en el monitor primario
/// (ver windows/runner/main.cpp, que la crea en 10,10); si la posición guardada
/// la manda a otro monitor con distinta escala —100% y 150%, lo normal con un
/// portátil y una pantalla externa—, Windows dispara WM_DPICHANGED y reescala
/// el marco. Y si el monitor de la sesión anterior ya no está conectado, la
/// posición apunta a un lugar que no existe y Windows la reubica por su cuenta.
///
/// En vez de suponer que salió bien, se relee la geometría real: si la ventana
/// terminó lejos de donde se pidió, o con otro tamaño, se cae a centrarla con
/// el tamaño correcto. Así el peor caso es una ventana centrada, nunca una
/// mitad fuera de pantalla o con el contenido a otra escala.
Future<void> _restaurarGeometria(Size size, Offset? posicion) async {
  if (posicion == null) {
    await windowManager.setSize(size);
    await windowManager.center();
    return;
  }
  // setBounds y no setPosition + setSize: una sola orden, sin un estado
  // intermedio en el que la ventana ya se movió pero todavía mide otra cosa.
  await windowManager.setBounds(
    Rect.fromLTWH(posicion.dx, posicion.dy, size.width, size.height),
  );

  final real = await windowManager.getBounds();
  final seMovio = (real.left - posicion.dx).abs() > 100 ||
      (real.top - posicion.dy).abs() > 100;
  final cambioDeTamano = (real.width - size.width).abs() > 40 ||
      (real.height - size.height).abs() > 40;
  if (seMovio || cambioDeTamano) {
    logger.warning(
      'La ventana no quedó donde se pidió (pedido: '
      '${posicion.dx}x${posicion.dy} ${size.width}x${size.height}, real: '
      '${real.left}x${real.top} ${real.width}x${real.height}). Se centra.',
    );
    await windowManager.setSize(size);
    await windowManager.center();
  }
}

/// Posición de la ventana de la sesión anterior, o null si no hay una usable.
///
/// Descarta valores rotos (texto mal formado, NaN, infinito) y también los
/// absurdos: un monitor que se desconectó deja guardada una posición que ya no
/// existe, y restaurarla abre la ventana fuera de la pantalla. El límite de
/// ±32000 es el rango de coordenadas que maneja Windows; cualquier cosa afuera
/// de eso es basura, no una pantalla.
Offset? _leerPosicionGuardada() {
  final crudo = PrismHubStorage.getSetting(SettingKey.windowPosition);
  if (crudo is! String || crudo.isEmpty) return null;
  try {
    final partes = crudo.split(',');
    if (partes.length != 2) return null;
    final x = double.parse(partes[0]);
    final y = double.parse(partes[1]);
    if (!x.isFinite || !y.isFinite) return null;
    if (x.abs() > 32000 || y.abs() > 32000) return null;
    return Offset(x, y);
  } catch (_) {
    return null;
  }
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
    _abrirEnlacePendiente();
    // Android entrega los enlaces por su propio canal, no por argumentos: el
    // que abrio la app y tambien los que llegan con la app ya abierta.
    unawaited(Compartir.escucharAndroid(_irAlEnlace));
  }

  /// Abre la ficha del enlace con el que se arrancó, si hubo uno.
  ///
  /// Va DESPUÉS de que todo lo de arriba terminó, y no antes: sin las
  /// extensiones cargadas la ficha no tendría con qué resolverse y se abriría
  /// directo en "extensión no encontrada" aunque estuviera instalada.
  ///
  /// Se navega a la ruta interna de siempre —la misma que usa un toque en una
  /// tarjeta— así el enlace pasa por las mismas comprobaciones: extensión
  /// instalada, activada, sin actualización pendiente, y la pregunta de +18. No
  /// hay una entrada paralela que se saltee nada de eso.
  void _abrirEnlacePendiente() {
    final uri = Compartir.enlacePendiente;
    if (uri == null) return;
    // Se limpia ANTES de navegar: si algo reconstruye esta pantalla, el enlace
    // ya no está y no se vuelve a abrir la misma ficha encima.
    Compartir.enlacePendiente = null;
    _irAlEnlace(uri);
  }

  /// Navega a la ficha de un enlace ya validado.
  void _irAlEnlace(Uri uri) {
    final ruta = Compartir.rutaInterna(uri);
    if (ruta == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        router.go(ruta);
      } catch (e, st) {
        logger.warning('No se pudo abrir el enlace compartido', e, st);
      }
    });
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
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Sin supportedLocales, el resolvedor cae a inglés aunque los delegados
      // estén puestos — por eso el selector de fecha salía en inglés con la
      // app en español.
      supportedLocales: const [Locale('es'), Locale('en')],
      locale: Locale(I18nUtils.currentLanguageCode),
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
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en')],
      locale: Locale(I18nUtils.currentLanguageCode),
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
