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
import 'package:prismhub/utils/bloqueador_anuncios.dart';
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
import 'package:prismhub/utils/sentry_config.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/utils/compartir.dart';
import 'package:prismhub/utils/notificacion_reproductor.dart';
import 'package:prismhub/utils/instancia_unica.dart';
import 'package:screen_retriever/screen_retriever.dart';
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
    // Sentry va ANTES que todo lo demás: los handlers de abajo lo usan, y si
    // el DSN está vacío (SentryConfig.dsn) esto no hace nada — queda
    // apagado hasta que alguien le ponga uno de verdad.
    await SentryConfig.init();

    FlutterError.onError = (FlutterErrorDetails details) {
      // details.exception a secas es solo el resumen ("A RenderFlex
      // overflowed by 13 pixels..."), sin el widget/archivo/línea donde
      // pasó — eso vive en el árbol de diagnóstico que arma
      // details.toString(), y se estaba tirando. Sin esto había que
      // reproducir el error a mano con la consola de flutter run abierta
      // para saber DÓNDE, en vez de leerlo en el log ya guardado.
      logger.severe(details.toString(), details.exception, details.stack);
      // No await, y con try/catch propio: un fallo de Sentry (sin red, DSN
      // vacío, lo que sea) no puede sumarse al error que se está reportando.
      unawaited(_reportarASentry(details.exception, details.stack));
    };

    // Errores del motor nativo/engine que no pasan por el árbol de widgets
    // (y por lo tanto no llegan a FlutterError.onError) — decodificación de
    // video, canales de plataforma, etc. Devuelve true: ya se lo maneja acá,
    // no hace falta que Flutter lo trate como fatal.
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      logger.severe("", error, stack);
      unawaited(_reportarASentry(error, stack));
      return true;
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

    // ── La caché de imágenes, más grande que la de fábrica ────────────────
    //
    // Flutter guarda hasta 100 MB de imágenes YA DECODIFICADAS. Suena mucho y
    // no lo es, porque lo que se guarda son píxeles crudos, no el archivo:
    // cuatro bytes por píxel, sin comprimir.
    //
    // Las cuentas de esta app, en un teléfono de tres píxeles por punto:
    //
    //   · una portada del acordeón, de unos 300 puntos de ancho, ocupa
    //     900 × 1350 × 4 = 4,8 MB. Seis en pantalla son 29 MB.
    //   · una portada de fila, de 150 puntos, ocupa 1,2 MB. Dos filas ya son
    //     otros 20 MB.
    //   · el fondo de una ficha ocupa la pantalla entera: 1080 × 2400 × 4,
    //     casi 10 MB él solo.
    //   · y una página de manga a resolución completa se va a diez o quince.
    //
    // O sea que abrir una ficha —y peor, leer tres páginas— se lleva los 100 MB
    // por delante y echa TODO lo del Inicio. Al volver, las portadas ya no
    // están: cada tarjeta vuelve a mostrar el arte de respaldo y a
    // decodificarse de cero. Eso es lo que se veía como «el Inicio se recarga
    // solo al volver de una ficha», con el acordeón en bloques grises otra vez.
    //
    // Con 220 MB entran el Inicio entero y una ficha encima sin echar nada. No
    // es memoria reservada: es un techo, y se llena solo con lo que de verdad
    // se mostró. Y si el sistema avisa que falta memoria, Flutter vacía la
    // caché él solo, así que el techo alto no deja a la app sin salida.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 220 << 20;

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

    // UNA sola copia del app, y antes de tocar el almacenamiento.
    //
    // Windows resuelve un prismhub://… ejecutando el programa con la dirección
    // al final de la línea de comandos, así que cada enlace que se toca abría
    // un proceso NUEVO aunque el app ya estuviera abierto. Y las dos copias
    // abren la MISMA carpeta de datos: la segunda pisa lo que escribe la
    // primera, y de ahí salen los ajustes que "se resetean solos".
    //
    // Va ANTES de PrismHubDirectory/PrismHubStorage justamente por eso: si esta
    // copia sobra, tiene que irse sin haber abierto nada.
    if (!Platform.isAndroid) {
      final sigo = await InstanciaUnica.tomarElControl(
        args,
        alRecibirEnlace: (uri) {
          // Llega un enlace mientras el app YA está abierto.
          //
          // Antes acá solo se anotaba en enlacePendiente, y ese campo se
          // consume UNA vez al arrancar: con la app ya abierta nadie lo volvía
          // a leer, así que la ventana se traía al frente y no pasaba nada más.
          // entregar() se lo pasa a quien esté navegando en ese momento.
          Compartir.entregar(uri);
          unawaited(() async {
            try {
              if (!await windowManager.isVisible()) await windowManager.show();
              if (await windowManager.isMinimized()) {
                await windowManager.restore();
              }
              await windowManager.focus();
            } catch (e) {
              logger.warning('No se pudo traer la ventana al frente', e);
            }
          }());
        },
      );
      if (!sigo) {
        // Ya hay otra copia abierta y se le pasó el enlace. Nada más que hacer.
        exit(0);
      }
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
      // El modo de color, apenas hay almacenamiento y ANTES de dibujar nada:
      // leerlo después haría que la app apareciera un instante en oscuro y
      // cambiara sola a claro delante del usuario.
      ModoDeColor.notificador.value =
          PrismHubStorage.getSetting(SettingKey.modoClaro) == true;
      // Y se le avisa al sistema de qué color pintar la hora y la batería: la
      // preferencia puede venir en claro desde el primer cuadro.
      ModoDeColor.aplicarBarrasDelSistema();
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

    // Las listas de bloqueo, para cuando se abra el navegador interno.
    //
    // ── SIN await: esto no puede atrasar el primer cuadro ────────────────
    //
    // Estaba esperándose acá, antes de runApp, y son varios archivos de listas
    // que hay que leer y parsear. En Windows no se notaba porque la ventana ni
    // se muestra hasta después de dibujar; en Android la pantalla está a la
    // vista desde el primer instante, así que todo ese rato se veía el fondo
    // oscuro vacío en vez del logo. Reportado en vivo: «una pantalla toda
    // negra al abrir».
    //
    // El bloqueador recién hace falta cuando se abre el navegador interno, que
    // es mucho después. Y el criterio ya estaba escrito unas líneas más
    // arriba: lo pesado se carga DURANTE el splash, con algo en pantalla.
    // Esta llamada se había quedado del lado equivocado.
    unawaited(() async {
      try {
        await BloqueadorAnuncios.cargar();
      } catch (e) {
        logger.warning('No se pudieron cargar las listas de bloqueo: $e');
      }
    }());

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
      // ── Hasta dónde se puede achicar la ventana ─────────────────────────
      //
      // 900×600 es lo mínimo con lo que la app se sigue leyendo bien. Pero era
      // un número FIJO, y ahí está el problema: en una pantalla chica —una
      // laptop de 1366×768 con el escalado de Windows al 125%, que deja menos
      // de 600 de alto útil— ese mínimo es MÁS GRANDE que el escritorio. La
      // ventana no entra y el usuario no la puede achicar hasta que entre.
      //
      // Con laptops y televisores en la lista de destinos eso deja de ser un
      // caso raro. Así que el mínimo se acota a lo que la pantalla de verdad
      // permite: se toma el área visible (sin la barra de tareas) y se deja un
      // respiro. Si la pantalla es grande, no cambia nada.
      final minWindowSize = await _minimoQueEntraEnLaPantalla();
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

    // Las barras del sistema ya se pidieron más arriba, con el modo real
    // (ModoDeColor.aplicarBarrasDelSistema). Acá había una segunda llamada que
    // volvía a pedirlas con `Brightness.dark` FIJO, o sea sin mirar el modo, y
    // se ejecutaba después: pisaba a la buena en cada arranque.

    // Si la app se abrió por un enlace compartido, se anota para navegar
    // cuando el árbol ya exista. No se usa como ruta inicial a propósito: así
    // el arranque es el de siempre y la ficha queda ENCIMA de la pantalla
    // principal, con su botón de volver funcionando como cualquier otra.
    final deArranque = Compartir.enlaceDeArranque(args);
    if (deArranque != null) Compartir.entregar(deArranque);

    runApp(const _AppRoot());
  }, (error, stack) {
    logger.severe("", error, stack);
    unawaited(_reportarASentry(error, stack));
  });
}

/// Manda un error a Sentry si el reporte está habilitado (ver
/// SentryConfig — apagado por defecto, y sin efecto si el DSN está vacío).
/// Nunca deja que un fallo DE Sentry tumbe nada: es diagnóstico, no puede
/// ser parte del problema.
Future<void> _reportarASentry(Object error, StackTrace? stack) async {
  try {
    await Sentry.captureException(error, stackTrace: stack);
  } catch (_) {
    // Sin red, sin DSN configurado, lo que sea: se ignora en silencio.
  }
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
    // Y si aun así quedó desajustada, se corrige. Ver _corregirSuperficie.
    unawaited(_corregirSuperficie(esperada));
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

/// Si la superficie quedó de otro tamaño que la ventana, la desatasca.
///
/// La espera de antes tiene una red de seguridad por tiempo, y esa red se
/// dispara de verdad: con `flutter run` el arranque puede tardar más que el
/// plazo, así que la ventana se muestra igual con la superficie vieja. Se ve el
/// contenido chico arrinconado arriba a la izquierda, con franjas negras a la
/// derecha y abajo.
///
/// Y ahí se queda. Flutter redibuja cuando el sistema le avisa que la ventana
/// cambió de tamaño (WM_SIZE), pero si la ventana YA está en su tamaño final
/// ese aviso no vuelve a llegar nunca y nada corrige la superficie: hay que
/// mover la ventana a mano para que se acomode.
///
/// Así que se le da un empujón: un píxel más de ancho y vuelta al tamaño real.
/// Eso provoca el aviso que faltaba. Es un píxel durante un cuadro, no se ve.
///
/// Solo actúa si de verdad hay desajuste, y se rinde a los tres intentos: si el
/// empujón no alcanzó, insistir tampoco va a alcanzar y sería una ventana
/// temblando sola.
Future<void> _corregirSuperficie(Size esperada) async {
  for (var intento = 0; intento < 3; intento++) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final vista = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (vista == null || vista.devicePixelRatio <= 0) return;
    final actual = vista.physicalSize / vista.devicePixelRatio;
    // Misma tolerancia que la espera: absorbe el grosor del borde, que no es
    // parte de lo que Flutter dibuja.
    if ((actual.width - esperada.width).abs() <= 24 &&
        (actual.height - esperada.height).abs() <= 24) {
      return;
    }
    try {
      final real = await windowManager.getSize();
      if (real.width <= 0 || real.height <= 0) return;
      logger.info('La superficie quedó en $actual con la ventana en $real: '
          'se fuerza un reajuste');
      await windowManager.setSize(Size(real.width + 1, real.height));
      await Future<void>.delayed(const Duration(milliseconds: 32));
      await windowManager.setSize(real);
    } catch (e) {
      // Que no se pueda empujar no vale colgar el arranque: peor es una ventana
      // mal dibujada que se arregla al moverla, que ninguna ventana.
      logger.warning('No se pudo reajustar la ventana: $e');
      return;
    }
  }
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
/// El tamaño mínimo al que se puede achicar la ventana, acotado a la pantalla.
///
/// Devuelve 900×600 —lo mínimo con lo que la app se lee bien— salvo que la
/// pantalla no dé para tanto. En ese caso baja hasta lo que entre, dejando un
/// respiro para el marco y la barra de tareas: más vale una ventana chica y
/// apretada que una que el usuario no puede achicar.
///
/// Nunca baja de 480×360: por debajo de eso no hay diseño que aguante, y una
/// pantalla así de chica no existe en las plataformas de escritorio.
///
/// Si no se puede averiguar el tamaño de la pantalla —el complemento falla, o
/// es un entorno raro— se devuelve el de siempre. Es exactamente lo que había
/// antes, así que el peor caso es no mejorar nada.
Future<Size> _minimoQueEntraEnLaPantalla() async {
  const deseado = Size(900, 600);
  const piso = Size(480, 360);
  try {
    final pantalla = await screenRetriever.getPrimaryDisplay();
    // `visibleSize` es el área SIN la barra de tareas; `size` es la pantalla
    // entera. Se prefiere la primera porque es donde la ventana puede vivir.
    final util = pantalla.visibleSize ?? pantalla.size;
    if (!util.width.isFinite || !util.height.isFinite) return deseado;
    return Size(
      util.width.clamp(piso.width, deseado.width).toDouble(),
      util.height.clamp(piso.height, deseado.height).toDouble(),
    );
  } catch (e) {
    logger.info('No se pudo leer el tamaño de la pantalla, se usa el mínimo '
        'de siempre: $e');
    return deseado;
  }
}

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

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  bool _ready = false;

  /// Si este arranque viene de una app que estaba en segundo plano hace nada.
  ///
  /// ── El problema ───────────────────────────────────────────────────────
  ///
  /// Mientras el proceso vive, volver a la app no pasa por acá y no hay
  /// animación de arranque. Pero Android MATA procesos en segundo plano
  /// cuando le falta memoria, y también cuando el usuario sale con el botón
  /// de atrás. Entonces «volver» es en realidad un arranque en frío completo,
  /// con su animación y su espera mínima — y desde afuera se ve como que la
  /// app se reinicia sola cada vez que la dejás un rato.
  ///
  /// ── Qué se puede y qué no ─────────────────────────────────────────────
  ///
  /// La inicialización de verdad —base de datos, extensiones, media_kit— hay
  /// que hacerla igual: el proceso murió y no hay nada cargado. Eso no se
  /// puede saltear sin romper la app.
  ///
  /// Lo que SÍ se saltea es la espera **artificial** de 1,4 segundos, que está
  /// para que la animación se alcance a ver. Si el usuario estuvo acá hace un
  /// minuto, esa animación no le dice nada nuevo: solo le cuesta un segundo y
  /// medio. Sin ella, un arranque con todo cacheado es casi instantáneo.
  bool _volviendo = false;

  /// Cuándo se fue la app a segundo plano por última vez, en milisegundos.
  static const _claveUltimoUso = 'ultimo-uso-ms';

  /// Cuánto vale considerar que «se estaba usando». Cinco minutos: más que eso
  /// y volver ya se siente como abrir la app, no como retomarla.
  static const _ventanaEnCaliente = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    super.didChangeAppLifecycleState(estado);
    // Se anota al IRSE, no al volver: cuando Android decide matar el proceso ya
    // no corre nada nuestro, así que la última marca tiene que estar puesta de
    // antes. `paused` es el último aviso garantizado.
    if (estado != AppLifecycleState.paused) return;
    unawaited(
      PrismHubStorage.setSetting(
        _claveUltimoUso,
        DateTime.now().millisecondsSinceEpoch,
      ).catchError((Object e) {
        // Que no se pueda anotar solo significa un arranque con animación de
        // más. No vale tumbar nada por eso.
        logger.info('No se pudo anotar el último uso: $e');
      }),
    );
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
    // Recién acá se puede preguntar: el almacenamiento lo abre la línea de
    // arriba. Para entonces la animación ya empezó, y está bien — lo que se
    // gana es no ESPERARLA.
    _mirarSiVolvemos();
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
    // Las listas que vienen puestas se bajan ACÁ, y no más arriba junto con
    // `cargar()`.
    //
    // Bajar necesita `dio`, y `dio` lo crea PrismRequest justo en la línea de
    // arriba. Lanzado antes, cada intento moría con "Field 'dio' has not been
    // initialized" y se gastaban los tres que tiene cada lista: la app decía
    // que traía cuatro protecciones y no bajaba ninguna.
    //
    // Va sin esperarlo: son varios megas y la app tiene que estar usable ya.
    // Mientras tanto la base de fábrica del código ya está protegiendo, así que
    // no hay un rato sin protección — hay un rato con menos.
    unawaited(BloqueadorAnuncios.asegurarDeFabrica().catchError((Object e) {
      logger.warning('No se pudieron poner las listas de fábrica: $e');
    }));
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
    // La notificación del reproductor, solo en Android.
    //
    // Se enciende UNA vez al arrancar y no al abrir cada vídeo: Android no deja
    // levantar y bajar este servicio a repetición. Después solo se le cambia lo
    // que muestra. Si falla, se sigue sin ella: no poder dibujar una
    // notificación no puede impedir ver un vídeo.
    if (Platform.isAndroid) {
      await NotificacionReproductor.encender();
    }
    // Solo se espera la duración mínima en un arranque de verdad. Volviendo,
    // se entra en cuanto lo de arriba terminó.
    if (!_volviendo) await minDuration;
    if (mounted) setState(() => _ready = true);
    _abrirEnlacePendiente();
    // Android entrega los enlaces por su propio canal, no por argumentos: el
    // que abrio la app y tambien los que llegan con la app ya abierta.
    unawaited(Compartir.escucharAndroid(_irAlEnlace));
  }

  /// Decide si este arranque es «volver» o «abrir».
  void _mirarSiVolvemos() {
    try {
      final ultimo = PrismHubStorage.getSetting(_claveUltimoUso);
      if (ultimo is! int) return;
      final pasado = DateTime.now().millisecondsSinceEpoch - ultimo;
      // El negativo cubre un reloj movido hacia atrás: ahí no se sabe cuánto
      // pasó, y ante la duda se trata como arranque normal.
      if (pasado < 0 || pasado > _ventanaEnCaliente.inMilliseconds) return;
      _volviendo = true;
      // Se corta la animación en el acto, sin esperar a que termine de
      // cargar: si igual quedan unos cuadros de espera, que sean sobre el
      // fondo y no sobre un logo latiendo que ya se vio hace un minuto.
      if (mounted) setState(() {});
    } catch (e) {
      logger.info('No se pudo leer el último uso: $e');
    }
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
  /// Avisa que ya se puede navegar, y abre lo que hubiera quedado esperando.
  ///
  /// Queda registrado, no es una consulta de una sola vez: así los enlaces que
  /// lleguen DESPUÉS —otra copia del programa reenviando uno, o el canal de
  /// Android— también encuentran a alguien que los abra. Antes eso solo
  /// funcionaba en Android, porque su canal navegaba por su cuenta.
  void _abrirEnlacePendiente() {
    Compartir.alEstarLista(_irAlEnlace);
  }

  /// Navega a la ficha de un enlace ya validado.
  ///
  /// Se abre por la MISMA puerta que un toque en una tarjeta
  /// (ExtensionUtils.openExtensionDetail) y no navegando a la ruta a mano.
  ///
  /// Antes se iba directo a `/detail?…`, que se saltea todo lo que esa función
  /// hace: comprobar que la extensión esté instalada, que no esté desactivada,
  /// que no tenga una actualización pendiente, y la protección contra abrir dos
  /// fichas encima. El comentario de rutaInterna decía que el enlace pasaba por
  /// esas comprobaciones, pero no era cierto — nadie las llamaba.
  ///
  /// Además usa `push` y no `go`: `go` REEMPLAZA la pila de navegación, así que
  /// la ficha quedaba sin nada atrás y el botón de volver no tenía a dónde ir.
  void _irAlEnlace(Uri uri) {
    final datos = Compartir.leerEnlace(uri);
    if (datos == null) return;
    unawaited(_abrirCuandoSePueda(datos));
  }

  /// Abre la ficha, esperando a que haya dónde navegar.
  ///
  /// Con la app RECIÉN abierta por un enlace, el árbol de widgets puede no estar
  /// todavía: `currentContext` sale de un GlobalKey que se llena cuando la
  /// pantalla se construye. Antes se intentaba una sola vez, un cuadro después;
  /// si en ese momento no había contexto, la excepción se anotaba en el registro
  /// y ahí terminaba todo — la app quedaba abierta en el inicio, que es
  /// exactamente el síntoma que se veía.
  ///
  /// Diez intentos de 200 ms: dos segundos de margen, de sobra para un arranque
  /// en frío, y no se nota cuando el contexto ya estaba —el primer intento
  /// acierta—.
  Future<void> _abrirCuandoSePueda(
      ({String package, String url, bool adulto}) datos) async {
    for (var intento = 0; intento < 10; intento++) {
      // Al primero se le deja pasar un cuadro: si esto se llamó desde el mismo
      // setState que muestra la app, el árbol se está construyendo ahora.
      await Future<void>.delayed(
          intento == 0 ? Duration.zero : const Duration(milliseconds: 200));
      if (!mounted) return;
      try {
        final ctx = currentContext;
        if (!ctx.mounted) continue;
        await ExtensionUtils.openExtensionDetail(
          ctx,
          package: datos.package,
          url: datos.url,
          isAdultOption: datos.adulto,
        );
        return;
      } catch (e) {
        // Todavía no hay a dónde navegar. Se reintenta; solo se registra el
        // último, para no llenar el archivo con diez líneas de lo mismo.
        if (intento == 9) {
          logger.warning('No se pudo abrir el enlace compartido: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        // Volviendo, el MISMO logo que acaba de mostrar el sistema — sin la
        // presentación, pero sin hueco.
        //
        // Acá había un rectángulo del color de fondo y nada más. La idea era
        // no presentarse dos veces, pero el efecto era el contrario: el
        // sistema dibuja su splash con el logo, Flutter entraba con el
        // rectángulo, y el logo se APAGABA dejando la pantalla en negro
        // mientras terminaba de cargar. Reportado en vivo: «sale el logo,
        // luego pantalla negra, luego carga».
        //
        // Con el logo puesto el relevo es continuo, que es lo que hacen las
        // demás apps. Y no cuesta tiempo: la espera artificial se saltea igual
        // (ver `_volviendo`), así que dura lo que tarde la carga real.
        home: SplashScreen(soloLogo: _volviendo),
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
    // ── Redibuja al cambiar de modo claro/oscuro ────────────────────────
    //
    // Los colores de la app son getters estáticos (ver HomeTheme), no un
    // InheritedWidget: cambiar el modo NO avisa a nadie por su cuenta. Este
    // oyente es el que le dice al árbol que se rehaga, y como envuelve la raíz,
    // el cambio llega a todas las pantallas de una.
    //
    // El cambio es INSTANTÁNEO y no un fundido, a propósito. Se probó envolver
    // esto en un AnimatedSwitcher: para cruzar dos imágenes necesita que el
    // hijo sea «otro» widget, y con la raíz eso significa destruir y recrear la
    // app entera — se pierde dónde estabas y se tiran todos los controladores.
    // Un cambio de color no puede costar eso.
    return ValueListenableBuilder<bool>(
      valueListenable: ModoDeColor.notificador,
      builder: (context, _, __) => GetMaterialApp(
        title: "PrismHub",
        // Le avisa a la barra flotante cuándo hay una pantalla encima, para que
        // se esconda deslizándose en vez de desaparecer de golpe. Ver
        // ObservadorDePila en main_page.dart.
        navigatorObservers: [ObservadorDePila()],
        debugShowCheckedModeBanner: false,
        // ── El tema de Material/Fluent sigue al modo ──────────────────────
        //
        // Esto era `c.theme`, o sea el ajuste viejo, y se quedaba en oscuro. Es
        // la causa de fondo de casi todo lo que «no se veía» en modo claro: la
        // paleta propia de la app (HomeTheme) cambiaba, pero TODO lo que no
        // fija un color a mano —el texto de un Text sin estilo, la etiqueta de
        // un botón, un ListTile, los widgets de Fluent en escritorio— cae en el
        // tema, y el tema seguía diciendo «fondo oscuro, texto claro». De ahí
        // el texto blanco sobre blanco en Buscar, en el repositorio y en los
        // botones de las tarjetas de extensión.
        //
        // Atándolo al modo se arreglan todos de una, sin tocarlos uno por uno.
        themeMode: ModoDeColor.claro ? ThemeMode.light : ThemeMode.dark,
        theme: _buildTheme(Brightness.light, cjkFontFallback),
        darkTheme: _buildTheme(Brightness.dark, cjkFontFallback),
        // ── Sin `const`, y NO es un descuido ──────────────────────────────
        //
        // Un widget const es siempre LA MISMA instancia. Cuando el oyente de
        // arriba rehace el árbol por un cambio de modo, Flutter compara el
        // widget viejo con el nuevo, ve que son idénticos y se saltea todo su
        // subárbol: o sea la app entera de Android.
        //
        // Ese era el bug: en escritorio el modo cambiaba al instante —ahí la
        // raíz arma sus pantallas por rutas, que sí se rehacen— y en Android
        // había que salir de la pestaña y volver para verlo. No era lentitud ni
        // un problema del interruptor: la pantalla directamente no se enteraba.
        //
        // Sin const se crea una instancia nueva en cada reconstrucción de la
        // raíz, que pasa solo al cambiar el modo. El estado no se pierde: es el
        // mismo tipo de widget en la misma posición, así que Flutter reusa su
        // Element y su State.
        // ignore: prefer_const_constructors
        home: AndroidMainPage(),
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
      ),
    );
  }

  // Morado (HomeTheme.accentPink) + dorado — antes usaba azul. El dorado
  // queda como color secundario/terciario; el sistema de temas actual solo
  // da para esto, personalización de verdad queda para más adelante.
  static const _brandGold = Color(0xFFC9A227);
  static final _fluentAccent = fluent.AccentColor.swatch({
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
      // ── La franja gris que aparecía al desplazarse ────────────────────
      //
      // Es de Material 3: cuando el contenido pasa POR DEBAJO de una AppBar,
      // Flutter le pinta encima un tinte del color primario y le sube la
      // elevación, para despegarla. Sobre nuestro fondo —negro con un brillo
      // animado— eso se ve como una barra clara y sucia cruzando la pantalla,
      // que aparece y desaparece según cuánto se desplazó.
      //
      // Se apaga acá y no zona por zona: son cinco pantallas más las que se
      // abren encima, y cualquiera que se agregue después heredaría el mismo
      // problema.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        // ── Y de acá salen los iconos del sistema ──────────────────────────
        //
        // La hora, la batería y la señal las dibuja Android del color que la
        // app le pida, y quien tiene la última palabra NO es la llamada suelta
        // a SystemChrome: cada AppBar de Material anota su propio estilo en
        // cada cuadro, y esa anotación pisa lo que se haya pedido antes.
        //
        // Sin decírselo, ese estilo lo DEDUCE del fondo de la barra. Y el fondo
        // acá arriba es transparente, que al medirle el brillo da «oscuro» —así
        // que todas las AppBar de la app venían pidiendo iconos CLAROS, siempre.
        // En modo oscuro acertaba de casualidad; en claro dejaba la hora y la
        // señal blancas sobre fondo casi blanco: la barra de arriba se veía
        // vacía, y lo único que se distinguía era la batería por su contorno.
        //
        // Puesto acá vale para las cinco zonas y para todo lo que se abra
        // encima, sin tener que acordarse pantalla por pantalla.
        systemOverlayStyle: SystemUiOverlayStyle(
          // Con color propio y no transparente: transparente deja el fondo de
          // la barra a merced de lo que haya pintado abajo, y con el modo
          // claro puesto arriba seguía asomando algo oscuro — con los iconos
          // ya en oscuro encima, la barra de estado se veía vacía (reportado
          // en vivo con captura). Mismo criterio que en
          // ModoDeColor.aplicarBarrasDelSistema.
          statusBarColor: HomeTheme.bg,
          // Brightness.dark = iconos OSCUROS. El nombre confunde: habla del
          // contenido que hay DETRÁS, no del color de los iconos.
          statusBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: brightness == Brightness.dark
              ? Brightness.dark
              : Brightness.light,
          systemNavigationBarColor: HomeTheme.bg,
          systemNavigationBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      // Mismo motivo, para las hojas y tarjetas que también se tiñen solas.
      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      // El fondo de todas las zonas, uno solo. Cada Scaffold que no diga otra
      // cosa arranca del mismo fondo que usa el Home, así que al cambiar de
      // zona no hay un salto de tono.
      //
      // ── Y en claro TAMBIÉN ────────────────────────────────────────────────
      //
      // Estaba solo para el modo oscuro; en claro quedaba en null y caía en el
      // ColorScheme, que se siembra con el rosa de la marca
      // (ColorScheme.fromSeed más arriba) y devuelve un blanco TEÑIDO DE ROSA.
      // Donde se veía era acostado: el riel de la izquierda es hermano de las
      // páginas, no va por encima, así que no lo tapa el fondo propio de cada
      // zona y esa franja salía rosada al lado del contenido. Reportado en
      // vivo con captura.
      scaffoldBackgroundColor: HomeTheme.bg,
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
    // Ver el comentario del mismo envoltorio en la raíz de Android.
    return ValueListenableBuilder<bool>(
      valueListenable: ModoDeColor.notificador,
      builder: (context, _, __) => fluent.FluentApp.router(
        title: 'PrismHub',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        // Ver el comentario del mismo cambio en la raíz de Android.
        themeMode:
            ModoDeColor.claro ? fluent.ThemeMode.light : fluent.ThemeMode.dark,
        darkTheme: fluent.FluentThemeData(
          brightness: Brightness.dark,
          visualDensity: VisualDensity.standard,
          accentColor: _fluentAccent,
        ),
        // ── El claro de Fluent, atado a la paleta de la app ─────────────────
        //
        // Estaba con los valores de fábrica: blanco puro de fondo y el gris
        // clarito de Fluent para lo que no está seleccionado. Dos problemas
        // juntos —el modo claro se veía «muy fuerte», y en el riel de la
        // izquierda los iconos y sus etiquetas quedaban casi invisibles sobre
        // ese blanco—.
        //
        // El resto de la app no usa blanco puro: su fondo claro es un gris muy
        // suave a propósito, para que las tarjetas blancas se lean como una
        // superficie POR ENCIMA. Con Fluent en blanco puro, el riel y el fondo
        // se fundían y encima deslumbraba.
        //
        // `inactiveColor` es la clave del riel: de ahí salen el icono y el
        // texto de cada opción NO seleccionada, que era justo lo que no se
        // veía. Con el texto principal de la app, contrasta igual que el resto.
        theme: fluent.FluentThemeData(
          visualDensity: VisualDensity.standard,
          accentColor: _fluentAccent,
          scaffoldBackgroundColor: HomeTheme.bg,
          micaBackgroundColor: HomeTheme.bg,
          cardColor: HomeTheme.cardSurface,
          menuColor: HomeTheme.cardSurface,
          inactiveColor: HomeTheme.textPrimary,
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
      ),
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
