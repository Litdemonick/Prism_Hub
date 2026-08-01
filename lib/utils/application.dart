// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/controllers/watch/video_controller.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:window_manager/window_manager.dart';

late PackageInfo packageInfo;
late AndroidDeviceInfo androidDeviceInfo;
late WindowsDeviceInfo windowsDeviceInfo;
late LinuxDeviceInfo linuxDeviceInfo;

class ApplicationUtils {
  static Future ensureInitialized() async {
    packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      androidDeviceInfo = await deviceInfo.androidInfo;
      return packageInfo;
    }
    if (Platform.isLinux) {
      linuxDeviceInfo = await deviceInfo.linuxInfo;
      return packageInfo;
    }
    if (Platform.isWindows) {
      windowsDeviceInfo = await deviceInfo.windowsInfo;
    }
    return packageInfo;
  }

  static String get _platformSuffix =>
      Platform.isWindows ? 'windows-x64.zip' : 'linux-x64.tar.gz';

  static bool _forcedUpdatePageOpen = false;
  static Future<void>? _forcedUpdateCheckInFlight;

  static void scheduleForcedUpdateCheck(BuildContext context) {
    if (kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 250),
        () {
          if (context.mounted) {
            return checkForcedUpdate(context);
          }
        },
      ));
    });
  }

  static List<int>? _versionParts(String version) {
    final clean = version.replaceFirst(RegExp(r'^v'), '').split('+').first;
    final parts = clean.split(RegExp(r'[.-]'));
    if (parts.isEmpty) return null;
    final numbers = <int>[];
    for (final part in parts.take(3)) {
      final value = int.tryParse(part);
      if (value == null) return null;
      numbers.add(value);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }

  static bool _isRemoteVersionNewer(String remoteVersion) {
    final remote = _versionParts(remoteVersion);
    final local = _versionParts(packageInfo.version);
    if (remote == null || local == null) {
      return remoteVersion != packageInfo.version;
    }
    for (var i = 0; i < remote.length; i++) {
      if (remote[i] > local[i]) return true;
      if (remote[i] < local[i]) return false;
    }
    return false;
  }

  static bool get _windowsInstallLooksManaged {
    if (!Platform.isWindows) return false;
    final installDir = Directory(Platform.resolvedExecutable).parent;
    final lower = installDir.path.toLowerCase();
    final hasInnoUninstaller = installDir
        .listSync()
        .whereType<File>()
        .any((f) => f.uri.pathSegments.last.toLowerCase().startsWith('unins'));
    return hasInnoUninstaller || lower.contains(r'\program files');
  }

  /// ¿El release está COMPLETO? Tiene que traer el archivo de las tres
  /// plataformas: Windows, Linux y Android.
  ///
  /// Cada job del workflow sube lo suyo al terminar, así que un release recién
  /// publicado pasa por estados intermedios — visto en vivo: Linux listo a los
  /// 4 minutos, Windows y Android todavía compilando. Si en esa ventana se
  /// anuncia la versión nueva, quien la reciba se encuentra con una descarga
  /// que no existe, o peor, con un release al que después le falta su archivo
  /// porque ese job falló.
  ///
  /// Mientras falte cualquiera de las tres, no se avisa a NADIE. Se vuelve a
  /// mirar en la próxima comprobación y, cuando esté entero, llega solo.
  static bool _releaseCompleto(dynamic assets, String tagName) {
    try {
      final list = (assets as List).cast<Map<String, dynamic>>();
      final nombres = list
          .map((a) => (a['name'] as String?)?.toLowerCase() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (nombres.isEmpty) return false;

      // Un asset a medio subir aparece en la API con state "uploaded" recién
      // cuando terminó; cualquier otro estado significa que sigue en curso.
      final subiendo = list.any((a) {
        final estado = (a['state'] as String?)?.toLowerCase();
        return estado != null && estado != 'uploaded';
      });
      if (subiendo) return false;

      final hayAndroid = nombres.any((n) => n.endsWith('.apk'));
      final hayLinux = nombres.any((n) => n.contains('linux'));
      // En Windows puede venir el instalador, el comprimido, o los dos.
      final hayWindows = nombres.any(
        (n) => n.endsWith('.exe') || n.contains('windows'),
      );
      return hayAndroid && hayLinux && hayWindows;
    } catch (_) {
      // Ante un formato inesperado se asume incompleto: no avisar de más es
      // preferible a mandar a alguien a una descarga rota.
      return false;
    }
  }

  /// ¿Las notas de la versión ya están escritas?
  ///
  /// Mismo razonamiento que _releaseCompleto, pero para el texto en vez de los
  /// archivos. Un release se puede publicar con el cuerpo vacío y editarse
  /// después: en esa ventana el aviso llegaba igual y aparecía la pantalla que
  /// TAPA la app entera, con el título de la versión y debajo un hueco. Y como
  /// el aviso es bloqueante, lo único que quedaba era actualizar a ciegas o
  /// posponer, sin ninguna forma de saber qué traía.
  ///
  /// Faltando las notas no se avisa a nadie y se vuelve a mirar en la próxima
  /// comprobación, igual que cuando falta un instalador. La actualización no se
  /// pierde: llega sola apenas el release está entero.
  ///
  /// No alcanza con que el cuerpo no sea nulo. Los marcadores que la propia app
  /// lee —hoy min-update-from— van como comentarios HTML, así que un cuerpo que
  /// solo tenga eso se ve vacío en pantalla aunque no lo esté. Se miden los
  /// caracteres que QUEDAN después de sacarlos.
  /// Lo que GitHub agrega SOLO al publicar, sin que nadie lo escriba.
  ///
  /// Al crear un release, GitHub puede sumar por su cuenta un enlace de
  /// comparación entre versiones ("Changelog completo: …/compare/v1.0.17...").
  /// Esa línea aparece antes de que nadie escriba una palabra, y sola pasaba el
  /// umbral de caracteres: un release publicado con las notas todavía vacías
  /// contaba como "notas listas" y disparaba el aviso antes de tiempo.
  ///
  /// Lo mismo con la lista de descargas y el enlace al historial completo, que
  /// son plantilla fija de cada release y no dicen nada de ESTA versión.
  ///
  /// No se saca del aviso —ahí se sigue viendo todo, changelog incluido—, solo
  /// se descuenta al DECIDIR si hay notas de verdad.
  static final _lineasAutomaticas = RegExp(
    r'^\s*(\*\*)?(Changelog|Full Changelog|Changelog completo)(\*\*)?\s*:?.*$'
    r'|^\s*https?://\S+/compare/\S+$'
    r'|^\s*\|.*\|\s*$'
    r'|^\s*#{1,6}\s*(📦\s*)?Descargas?\s*$',
    multiLine: true,
    caseSensitive: false,
  );

  static bool _notasPublicadas(dynamic body) {
    if (body is! String) return false;
    final visible = body
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        // Ver _lineasAutomaticas: lo que pone GitHub solo, o la plantilla de
        // descargas, no cuenta como haber escrito las notas.
        .replaceAll(_lineasAutomaticas, '')
        .trim();
    // Un puñado de caracteres sueltos no son notas: con un título de sección o
    // una línea a medio escribir, la pantalla se sigue viendo vacía.
    return visible.length >= 40;
  }

  /// ¿La versión instalada es demasiado vieja para instalarle ESTE release
  /// encima?
  ///
  /// El piso se declara en el cuerpo del release con un comentario HTML:
  ///
  ///     <!-- min-update-from: 1.0.10 -->
  ///
  /// No se ve en la página de GitHub pero sí se puede leer desde acá. Va en el
  /// release y NO en el código a propósito: así el bloqueo se puede activar en
  /// una publicación futura sin que nadie tenga que actualizar el app primero.
  ///
  /// Para qué sirve: hay cambios que impiden instalar encima —el más claro fue
  /// la firma de Android en la 1.0.10, donde había que desinstalar primero—. En
  /// esos casos, ofrecer la actualización automática es mandar al usuario a un
  /// error de instalación sin explicación. Mejor decirle de una que la baje a
  /// mano.
  ///
  /// OJO con lo que esto NO puede hacer: la comprobación corre en el app
  /// INSTALADO, así que solo la respetan las versiones que ya traen este
  /// código. Una versión anterior va a seguir ofreciendo la actualización pase
  /// lo que pase; eso no se puede arreglar desde acá.
  ///
  /// Ante cualquier duda (sin marca, marca ilegible, versión local rara) se
  /// devuelve false y todo sigue como siempre: este freno solo se activa cuando
  /// está declarado explícitamente.
  static bool _demasiadoViejoParaActualizar(dynamic body) {
    if (body is! String) return false;
    final marca = RegExp(r'min-update-from:\s*v?(\d+(?:\.\d+){0,2})')
        .firstMatch(body);
    if (marca == null) return false;
    final piso = _versionParts(marca.group(1)!);
    final local = _versionParts(packageInfo.version);
    if (piso == null || local == null) return false;
    for (var i = 0; i < piso.length; i++) {
      if (local[i] > piso[i]) return false;
      if (local[i] < piso[i]) return true;
    }
    return false;
  }

  static Map<String, dynamic>? _findAsset(dynamic assets, String tagName) {
    final expectedName = 'PrismHub-$tagName-$_platformSuffix';
    final expectedSetupName = 'PrismHub-setup-$tagName.exe';
    try {
      final list = assets as List;
      if (Platform.isWindows && _windowsInstallLooksManaged) {
        final setup = list.firstWhereOrNull(
          (a) => (a['name'] as String?) == expectedSetupName,
        );
        if (setup != null) return setup as Map<String, dynamic>;
      }
      final archive = list.firstWhere(
        (a) => (a['name'] as String) == expectedName,
      );
      return archive as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _findAndroidAsset(dynamic assets) {
    if (!Platform.isAndroid) return null;
    try {
      final list = (assets as List).cast<Map<String, dynamic>>();
      final supportedAbis = androidDeviceInfo.supportedAbis;
      for (final abi in supportedAbis) {
        final match = list.firstWhereOrNull((a) {
          final name = (a['name'] as String?)?.toLowerCase() ?? '';
          return name.endsWith('-$abi.apk');
        });
        if (match != null) return match;
      }
      return list.firstWhereOrNull((a) {
        final name = (a['name'] as String?)?.toLowerCase() ?? '';
        return name.endsWith('.apk');
      });
    } catch (_) {
      return null;
    }
  }

  // Chequeo obligatorio de versión: a diferencia de checkUpdate() (dialog
  // descartable, disparado manualmente o al inicio si autoCheckUpdate está
  // activado), esta variante bloquea el uso de la app con una página de
  // pantalla completa sin forma de cerrarla salvo actualizando. Solo tiene
  // sentido en Android/Windows/Linux — la Web siempre sirve la última
  // versión desplegada, no hay un "instalable" que forzar.
  static Future<void> checkForcedUpdate(BuildContext context) async {
    if (kIsWeb) return;
    if (_forcedUpdatePageOpen) return;
    final activeCheck = _forcedUpdateCheckInFlight;
    if (activeCheck != null) return activeCheck;

    _forcedUpdateCheckInFlight = _checkForcedUpdate(context);
    try {
      await _forcedUpdateCheckInFlight;
    } finally {
      _forcedUpdateCheckInFlight = null;
    }
  }

  static Future<void> _checkForcedUpdate(BuildContext context) async {
    try {
      const url =
          "https://api.github.com/repos/Litdemonick/Prism_Hub/releases/latest";
      final res = await dio.get(url);
      final tagName = res.data["tag_name"] as String;
      final remoteVersion = tagName.replaceFirst('v', '');
      if (!_isRemoteVersionNewer(remoteVersion)) {
        // Nada nuevo: si venia esperando un release a medio publicar, ya no
        // hay por que seguir mirando seguido.
        _esperandoReleaseIncompleto = false;
        _rafagasRapidas = 0;
        return;
      }
      if (!context.mounted) return;

      // Un release se publica ANTES de que todas las plataformas terminen de
      // subir lo suyo: cada job del workflow sube su archivo cuando acaba. O
      // sea que hay una ventana en la que el release ya existe pero el
      // instalador de ESTA plataforma todavía no está — por ejemplo Linux
      // termina primero y un usuario de Android vería "hay 1.0.9" con nada
      // que descargar.
      //
      // Así que la versión nueva no se anuncia hasta que el archivo que le
      // toca a este dispositivo esté realmente publicado. Si falta, se sale en
      // silencio y se vuelve a mirar en la próxima comprobación.
      // Release incompleto: todavía se están subiendo archivos, o alguno de
      // los jobs falló. En cualquiera de los dos casos no se avisa.
      if (!_releaseCompleto(res.data['assets'], tagName)) {
        // Hay version nueva pero le faltan archivos: se mira seguido hasta que
        // termine de publicarse (ver _cadaCuantoEsperando).
        _esperandoReleaseIncompleto = true;
        return;
      }

      // Y tampoco se avisa con las notas todavía sin escribir: esta pantalla
      // tapa la app entera, así que salir sin explicar qué trae la versión deja
      // al usuario eligiendo a ciegas. Ver _notasPublicadas.
      if (!_notasPublicadas(res.data['body'])) {
        // Mismo caso: estan los archivos pero falta el texto.
        _esperandoReleaseIncompleto = true;
        return;
      }

      final asset = Platform.isAndroid
          ? _findAndroidAsset(res.data['assets'])
          : _findAsset(res.data['assets'], tagName);
      if (asset == null) {
        _esperandoReleaseIncompleto = true;
        return;
      }
      // Release entero y a punto de avisar: se vuelve al ritmo normal.
      _esperandoReleaseIncompleto = false;
      _rafagasRapidas = 0;

      // Se calla lo que se esté reproduciendo ANTES de tapar la pantalla.
      //
      // El aviso sale encima de cualquier cosa y bloquea, que es a propósito.
      // Pero sin esto el vídeo seguía sonando detrás: quedaba el audio de algo
      // que ya no se ve, y había que adivinar de dónde salía.
      //
      // Son dos motores distintos y hay que pedírselo a los dos: el
      // reproductor nativo maneja su audio con media_kit, y el de WebView lo
      // maneja la propia página. Pausar uno no toca al otro.
      //
      // Pausar y no cerrar: se puede posponer la actualización, y en ese caso
      // el episodio tiene que seguir donde estaba. Las dos llamadas tienen su
      // propio tope de tiempo, así que un reproductor colgado no puede impedir
      // que el aviso aparezca.
      await VideoPlayerController.pausarLoQueSuene();
      await WebViewPlayerPause.pausarLoQueSuene();
      if (!context.mounted) return;

      _forcedUpdatePageOpen = true;
      try {
        await Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, animation, secondaryAnimation) =>
                _ForcedUpdatePage(
              remoteVersion: remoteVersion,
              changelog: (res.data['body'] as String?) ?? '',
              htmlUrl: res.data['html_url'] as String,
              asset: asset,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
          ),
        );
      } finally {
        _forcedUpdatePageOpen = false;
      }
    } catch (e) {
      // Silencioso: si no se puede chequear (sin internet, GitHub caído), no
      // hay que bloquear el uso de la app por un error de red — el gate solo
      // se muestra cuando SÍ se confirma una versión nueva.
      debugPrint('checkForcedUpdate error: $e');
    }
  }

  static checkUpdate(BuildContext context, {bool showSnackbar = false}) async {
    try {
      const url =
          "https://api.github.com/repos/Litdemonick/Prism_Hub/releases/latest";
      final res = await dio.get(url);
      final tagName = res.data["tag_name"] as String;
      final remoteVersion = tagName.replaceFirst('v', '');
      debugPrint('remoteVersion: $remoteVersion');
      if (_isRemoteVersionNewer(remoteVersion)) {
        // Esta versión es demasiado vieja para instalar la nueva encima: no se
        // ofrece la actualización automática, se manda a la página de
        // versiones. Ver _demasiadoViejoParaActualizar.
        if (_demasiadoViejoParaActualizar(res.data['body'])) {
          // Diálogo y no un aviso pasajero: esto no es "che, hay novedades",
          // es "esta actualización NO se va a poder instalar sola". Si se va
          // solo a los dos segundos, el usuario se queda sin saber qué hacer.
          if (context.mounted) {
            await showPlatformDialog(
              context: context,
              title: FlutterI18n.translate(
                context,
                'upgrade.new-version',
                translationParams: {'version': remoteVersion},
              ),
              content: Text('upgrade.too-old-to-update'.i18n),
              actions: [
                PlatformTextButton(
                  onPressed: () => RouterUtils.pop(),
                  child: Text('upgrade.not-now'.i18n),
                ),
                PlatformFilledButton(
                  onPressed: () {
                    RouterUtils.pop();
                    launchUrl(
                      Uri.parse(res.data['html_url'] as String),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: Text('upgrade.download'.i18n),
                ),
              ],
            );
          }
          return;
        }
        // Ver el comentario largo de la comprobación al arrancar: mientras el
        // archivo de esta plataforma no esté subido, no se ofrece nada.
        final completo = _releaseCompleto(res.data['assets'], tagName);
        final asset = completo
            ? (Platform.isAndroid
                ? _findAndroidAsset(res.data['assets'])
                : _findAsset(res.data['assets'], tagName))
            : null;
        // Las notas se tratan igual que los archivos: un release se puede
        // publicar con el cuerpo vacío y editarse después, y ofrecer la
        // actualización en esa ventana es pedirle al usuario que decida sin
        // saber qué trae. Ver _notasPublicadas.
        final notasListas = _notasPublicadas(res.data['body']);
        if (asset == null || !notasListas) {
          // Acá SÍ se avisa, a diferencia del arranque: el usuario apretó
          // "Comprobar" y dejarlo sin respuesta parecería que el botón no
          // hace nada. Y se dice QUÉ falta, que no es lo mismo esperar a que
          // termine de compilar que esperar a que escriban las notas.
          if (showSnackbar && context.mounted) {
            showPlatformSnackbar(
              context: context,
              content: asset == null
                  ? 'upgrade.assets-not-ready'.i18n
                  : 'upgrade.notes-not-ready'.i18n,
            );
          }
          // El aviso promete que la actualización "aparece sola" — y hasta
          // ahora era mentira: no se volvía a mirar nunca, así que había que
          // reabrir la app o tocar el botón de nuevo. Se programa el reintento
          // para que lo prometido se cumpla de verdad.
          _programarReintento(context);
          return;
        }
        _cancelarReintentos();
        if (Platform.isAndroid) {
          await showPlatformDialog(
            context: context,
            title: FlutterI18n.translate(
              context,
              'upgrade.new-version',
              translationParams: {
                'version': remoteVersion,
              },
            ),
            content: _notasDeVersion(res.data['body']),
            // El contenido ya desplaza solo: ver el comentario de `scrollable`
            // en showPlatformDialog.
            scrollable: false,
            actions: [
              PlatformTextButton(
                onPressed: () {
                  RouterUtils.pop();
                },
                child: Text('upgrade.not-now'.i18n),
              ),
              // Sin la rama de "abrir GitHub": para llegar hasta acá el archivo
              // de esta plataforma ya tiene que estar publicado — si falta, se
              // sale bastante más arriba con el aviso de que todavía se está
              // publicando. Antes se comprobaba igual, y el resultado era una
              // rama muerta que hacía parecer que el botón podía terminar
              // llevando al navegador.
              PlatformFilledButton(
                onPressed: () {
                  RouterUtils.pop();
                  _downloadAndInstall(context, asset, remoteVersion);
                },
                child: Text('upgrade.download-install'.i18n),
              )
            ],
          );
          return;
        }

        showPlatformDialog(
          context: context,
          title: FlutterI18n.translate(
            context,
            'upgrade.new-version',
            translationParams: {
              'version': remoteVersion,
            },
          ),
          content: _notasDeVersion(res.data['body']),
          maxWidth: _anchoDialogoNotas,
          actions: [
            PlatformTextButton(
              onPressed: () {
                RouterUtils.pop();
              },
              child: Text('upgrade.not-now'.i18n),
            ),
            // Ver el comentario del botón equivalente en la rama de Android:
            // acá el archivo ya está publicado sí o sí.
            PlatformFilledButton(
              onPressed: () {
                RouterUtils.pop();
                _downloadAndInstall(context, asset, remoteVersion);
              },
              child: Text('upgrade.download-install'.i18n),
            )
          ],
        );
      } else {
        if (!showSnackbar) {
          return;
        }
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.check-update'.i18n,
          content: "upgrade.no-update".i18n,
        );
      }
    } catch (e) {
      if (!showSnackbar) {
        return;
      }
      showPlatformSnackbar(
        context: context,
        title: 'upgrade.check-update'.i18n,
        content: 'upgrade.error'.i18n,
      );
    }
  }

  /// Ancho del diálogo de "hay versión nueva" en escritorio. El valor por
  /// defecto de showPlatformDialog (368) es para avisos de una línea: las notas
  /// de versión, que son varios párrafos con listas y enlaces, quedaban
  /// partidas en una columna angosta y altísima.
  static const double _anchoDialogoNotas = 560;

  /// Notas de la versión, listas para meter en un diálogo.
  static Widget _notasDeVersion(dynamic body) =>
      _NotasDeVersion(body is String ? body : '');

  // Comprobación periódica mientras la app está abierta.
  //
  // Antes solo se miraba al ARRANCAR. Si el release terminaba de publicarse
  // con la app ya abierta —lo normal, porque los tres jobs tardan unos minutos
  // en subir lo suyo— no había forma de enterarse hasta cerrarla y volver a
  // abrirla.
  //
  // El aviso aparece encima de lo que sea que esté en pantalla —reproductor
  // nativo, WebView, lector o cualquier página— y BLOQUEA hasta actualizar, la
  // misma pantalla que sale al arrancar. Es a propósito: una version vieja se
  // queda sin correcciones y sus extensiones empiezan a fallar cuando los
  // sitios cambian, sin que se entienda por qué.
  //
  // La contra, dicha claramente: puede interrumpir a alguien a mitad de un
  // episodio. Se acepta a cambio de que nadie se quede atras sin enterarse.
  static Timer? _chequeoPeriodico;

  // Cada cuánto se pregunta si hay versión nueva.
  //
  // Estaba en 30 minutos y era demasiado: un release puede estar listo y el
  // usuario enterarse media hora después.
  //
  // No se baja a "cada un minuto" porque la consulta va a la API de GitHub, que
  // sin credenciales corta a 60 llamadas por hora y por IP. A un minuto se
  // consume el cupo entero solo con esto, y una casa con dos dispositivos
  // empezaría a recibir respuestas de "demasiadas peticiones" — o sea, dejaría
  // de avisar justo cuando hay algo que avisar.
  //
  // Cinco minutos deja el cupo en doce llamadas por hora, con lugar de sobra.
  static const _cadaCuanto = Duration(minutes: 5);

  // Y cuando ya se sabe que hay algo por salir, se mira seguido.
  //
  // Un release se publica por partes: cada plataforma sube su archivo al
  // terminar de compilar, y las notas pueden escribirse después. En esa ventana
  // la comprobación ve la versión nueva pero no avisa, porque avisar a medias
  // manda a una descarga que no existe o deja al usuario eligiendo sin saber
  // qué trae.
  //
  // Ahí es cuando conviene mirar seguido: falta poco y ya se sabe. Se pasa a un
  // minuto hasta que el release esté entero, y recién ahí sale el aviso — que
  // es exactamente el momento pedido: "cuando la release completa todo, ahí
  // sale". Es una ráfaga corta y acotada, no el ritmo permanente.
  static const _cadaCuantoEsperando = Duration(minutes: 1);

  /// Hay una versión más nueva pero el release todavía no está entero.
  static bool _esperandoReleaseIncompleto = false;

  /// Cuántas comprobaciones rápidas seguidas se llevan hechas.
  ///
  /// La ráfaga tiene techo a propósito. Un release puede quedar publicado y las
  /// notas no escribirse nunca, o un job del CI fallar y ese archivo no llegar
  /// jamás: ahí la espera no termina sola. Sin límite, la app se quedaría
  /// mirando cada minuto para siempre — sesenta llamadas por hora, justo el
  /// tope de la API de GitHub, así que el mecanismo puesto para avisar ANTES
  /// terminaría agotando el cupo y dejando de avisar del todo.
  ///
  /// Veinte minutos alcanzan de sobra: un release que tarda más que eso en
  /// completarse no se está completando. Pasado ese punto se vuelve al ritmo
  /// normal, que igual lo va a encontrar cuando esté listo — solo que sin
  /// insistir.
  static int _rafagasRapidas = 0;
  static const _maxRafagasRapidas = 20;

  static void iniciarChequeoPeriodico(BuildContext context) {
    if (kIsWeb) return;
    // Uno solo: en Android el shell se reconstruye al cambiar de pestaña, y sin
    // esto quedaba un temporizador nuevo por cada reconstrucción.
    _chequeoPeriodico?.cancel();
    // El temporizador late al ritmo RÁPIDO siempre, y adentro se decide si toca
    // preguntar. Así el cambio de ritmo no obliga a destruir y recrear el
    // temporizador, que es donde se cuelan los duplicados.
    var pulsos = 0;
    _chequeoPeriodico = Timer.periodic(_cadaCuantoEsperando, (_) {
      pulsos++;
      // Ver _maxRafagasRapidas: la espera acelerada tiene techo.
      final rapido =
          _esperandoReleaseIncompleto && _rafagasRapidas < _maxRafagasRapidas;
      final cadaCuantosPulsos = rapido
          ? 1
          : _cadaCuanto.inMinutes ~/ _cadaCuantoEsperando.inMinutes;
      if (pulsos % cadaCuantosPulsos != 0) return;
      if (rapido) _rafagasRapidas++;
      // Se relee el ajuste en cada vuelta: si el usuario lo apaga mientras
      // tanto, esto deja de molestar sin necesidad de reiniciar nada.
      if (PrismHubStorage.getSetting(SettingKey.autoCheckUpdate) != true) return;
      if (!context.mounted) return;
      // checkForcedUpdate y no checkUpdate: cuando aparece una version nueva
      // con la app abierta, el aviso BLOQUEA hasta actualizar, igual que el
      // que sale al arrancar. Antes esta comprobacion mostraba el dialogo
      // descartable, asi que se podia seguir usando una version vieja sin
      // enterarse — que es justo lo que se queria evitar.
      //
      // Es seguro llamarlo cada tanto: tiene guardas propias para no apilar la
      // pantalla si ya esta abierta (_forcedUpdatePageOpen) ni lanzar dos
      // comprobaciones a la vez (_forcedUpdateCheckInFlight). Y si no hay
      // version nueva no muestra nada.
      unawaited(checkForcedUpdate(context));
    });
  }

  static void detenerChequeoPeriodico() {
    _chequeoPeriodico?.cancel();
    _chequeoPeriodico = null;
  }

  // Reintento cuando el release todavía se está publicando.
  //
  // Los tres jobs del workflow suben lo suyo al terminar, así que un release
  // recién publicado pasa unos minutos incompleto (medido: hasta ~10 entre el
  // primero y el último). En esa ventana no se ofrece nada, y el aviso dice que
  // la actualización va a aparecer sola.
  //
  // Para que eso sea cierto hay que volver a mirar. Se hace un puñado de veces
  // y se para: si después de media hora sigue sin estar, o el release quedó a
  // medias por un job que falló, insistir para siempre solo gastaría datos.
  static Timer? _reintentoActualizacion;
  static int _reintentosHechos = 0;
  static const _maxReintentos = 5;
  static const _esperaEntreReintentos = Duration(minutes: 6);

  static void _programarReintento(BuildContext context) {
    if (_reintentosHechos >= _maxReintentos) return;
    // Uno solo a la vez: tocar "Comprobar" varias veces no debe dejar cinco
    // temporizadores pisándose.
    _reintentoActualizacion?.cancel();
    _reintentosHechos++;
    _reintentoActualizacion = Timer(_esperaEntreReintentos, () {
      if (!context.mounted) return;
      // showSnackbar en false: este reintento no lo pidió el usuario, así que
      // si sigue incompleto se queda callado. Cuando el release esté entero,
      // el aviso de versión nueva sale solo, que es lo prometido.
      unawaited(checkUpdate(context));
    });
  }

  /// Corta los reintentos pendientes. Se llama al encontrar una versión nueva
  /// —ya no hay nada que esperar— para no dejar un temporizador vivo.
  static void _cancelarReintentos() {
    _reintentoActualizacion?.cancel();
    _reintentoActualizacion = null;
    _reintentosHechos = 0;
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    Map<String, dynamic> asset,
    String version,
  ) async {
    var progressDialogOpen = false;
    if (context.mounted) {
      progressDialogOpen = true;
      unawaited(showPlatformDialog(
        context: context,
        title: 'upgrade.check-update'.i18n,
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text('upgrade.downloading'.i18n)),
            ],
          ),
        ),
        // null y no []: con una lista vacia, fluent dibuja igual la barra
        // de acciones y se veia un recuadro oscuro suelto abajo del dialogo.
        actions: null,
        maxWidth: 360,
        barrierDismissible: false,
      ));
      await Future<void>.delayed(Duration.zero);
    }

    try {
      final url = asset['browser_download_url'] as String;
      // En Android usar app cache (cubierto por FileProvider), en desktop
      // system temp es suficiente porque no hay FileProvider de por medio.
      final downloadDir = Platform.isAndroid
          ? Directory(
              '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}update',
            )
          : Directory.systemTemp.createTempSync('PrismHub_update_');
      downloadDir.createSync(recursive: true);
      final downloadPath =
          '${downloadDir.path}${Platform.pathSeparator}${asset['name']}';

      // Descargar con progreso
      await dio.download(url, downloadPath, onReceiveProgress: (count, total) {
        if (total > 0) {
          debugPrint(
            'Download progress: ${(count / total * 100).toStringAsFixed(2)}%',
          );
        }
      });

      final assetName = (asset['name'] as String).toLowerCase();

      // Android: descargar e instalar APK automáticamente
      if (Platform.isAndroid && assetName.endsWith('.apk')) {
        if (progressDialogOpen) RouterUtils.pop();
        await _installAndroidApk(downloadPath, context);
        return;
      }

      // Windows: instalador .exe
      if (Platform.isWindows && assetName.endsWith('.exe')) {
        if (progressDialogOpen) RouterUtils.pop();
        await _runWindowsInstaller(downloadPath);
        return;
      }

      // Windows/Linux: descargar y reemplazar app
      final extractDir =
          Directory('${downloadDir.path}${Platform.pathSeparator}app');
      extractDir.createSync();

      if (Platform.isLinux) {
        final result = await Process.run('tar', [
          '-xzf',
          downloadPath,
          '-C',
          extractDir.path,
        ]);
        _throwIfProcessFailed('tar', result);
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          'Expand-Archive',
          '-Path',
          downloadPath,
          '-DestinationPath',
          extractDir.path,
          '-Force',
        ]);
        _throwIfProcessFailed('Expand-Archive', result);
      }

      if (progressDialogOpen) RouterUtils.pop();

      final sourceDir = _findExtractedAppDir(extractDir);
      await _replaceAndRestart(sourceDir, downloadDir);
    } catch (e) {
      if (progressDialogOpen) RouterUtils.pop();
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.install-failed'.i18n,
          content: e.toString(),
        );
      }
      debugPrint('Download/install error: $e');
    }
  }

  static void _throwIfProcessFailed(String command, ProcessResult result) {
    if (result.exitCode == 0) return;
    throw '$command failed (${result.exitCode}): ${result.stderr}';
  }

  static const _canalActualizacion =
      MethodChannel('com.example.prismhub/update');

  /// Reintenta la instalación sola cuando el usuario vuelve de la pantalla de
  /// permisos de Android.
  ///
  /// Antes, si faltaba el permiso de "instalar apps desconocidas", se abría
  /// Ajustes y se lanzaba un error: el APK recién descargado se daba por
  /// perdido y el aviso de "actualizando" desaparecía. Al volver, la app se
  /// veía igual que siempre y no quedaba ninguna señal de que hubiera una
  /// actualización a medio instalar — había que ir a Ajustes, comprobar de
  /// nuevo y volver a descargar todo.
  ///
  /// Ahora el APK ya bajado se conserva y la instalación se retoma sola al
  /// volver a la app, que es lo que el usuario espera después de haber dado el
  /// permiso.
  static Future<void> _instalarAlVolver(
    String apkPath,
    BuildContext context,
  ) async {
    final observador = _EsperaPermisoDeInstalacion(() async {
      // El permiso puede tardar un instante en verse reflejado justo después
      // de volver, así que se consulta un par de veces antes de rendirse.
      for (var intento = 0; intento < 3; intento++) {
        final permitido = await _canalActualizacion
                .invokeMethod<bool>('canInstallApks') ??
            false;
        if (permitido) {
          try {
            await _canalActualizacion
                .invokeMethod('installApk', {'apkPath': apkPath});
          } catch (e) {
            debugPrint('Reintento de instalación falló: $e');
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      // Siguió sin permiso: se avisa con el APK todavía guardado, así que
      // tocar actualizar otra vez no vuelve a descargar nada.
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.install-failed'.i18n,
          content: 'upgrade.needs-install-permission'.i18n,
        );
      }
    });
    observador.empezar();
    await _canalActualizacion.invokeMethod('openInstallSettings');
  }

  static Future<void> _installAndroidApk(
    String apkPath,
    BuildContext context,
  ) async {
    final file = File(apkPath);
    if (!await file.exists()) {
      throw 'APK file not found: $apkPath';
    }

    const platform = _canalActualizacion;
    final canInstall =
        await platform.invokeMethod<bool>('canInstallApks') ?? false;
    if (!canInstall) {
      // Ya NO se lanza un error acá. Se abre Ajustes y queda esperando la
      // vuelta para instalar solo (ver _instalarAlVolver): lanzar cortaba el
      // flujo y obligaba a rehacer todo desde cero.
      //
      // OJO con volver a un fallback tipo launchUrl(Uri.file(...)): en Android
      // 7.0+ un file:// crudo sin FileProvider tira FileUriExposedException, y
      // esa excepción tapaba el mensaje útil sin dejar ninguna pista de qué
      // hacer. installApk (nativo) ya arma el intent con FileProvider.
      await _instalarAlVolver(apkPath, context);
      return;
    }
    // installApk (nativo) ya arma el intent con FileProvider — no hace
    // falta ni conviene un fallback acá: cualquier fallback Dart-side con un
    // Uri.file() crudo pisaría exactamente el mismo bug de FileUriExposedException
    // de arriba. Si esto falla, el error real sube tal cual al snackbar de
    // _downloadAndInstall.
    await platform.invokeMethod('installApk', {'apkPath': apkPath});
  }

  static Directory _findExtractedAppDir(Directory extractDir) {
    final currentExeName =
        Platform.resolvedExecutable.split(Platform.pathSeparator).last;
    final targetExeName = currentExeName.toLowerCase();
    final exeFiles = extractDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    final matchingExe = exeFiles.firstWhereOrNull(
      (f) => f.uri.pathSegments.last.toLowerCase() == targetExeName,
    );
    if (matchingExe != null) return matchingExe.parent;

    final prismExe = exeFiles.firstWhereOrNull(
      (f) => f.uri.pathSegments.last.toLowerCase().contains('prismhub'),
    );
    if (prismExe != null) return prismExe.parent;

    if (Platform.isLinux) {
      final currentName =
          Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      final matchingFile = extractDir
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhereOrNull(
            (f) =>
                f.uri.pathSegments.last.toLowerCase() ==
                currentName.toLowerCase(),
          );
      if (matchingFile != null) return matchingFile.parent;
    }

    return extractDir;
  }

  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  static bool _canWriteTo(Directory dir) {
    try {
      final probe = File(
        '${dir.path}${Platform.pathSeparator}.prismhub-update-write-test',
      );
      probe.writeAsStringSync('ok');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _runWindowsInstaller(String installerPath) async {
    // El instalador arranca DESPUES de que este proceso se haya ido.
    //
    // Antes se lanzaba de inmediato y recien despues se llamaba a exit(0). El
    // instalador usa el Restart Manager para detectar la app abierta, y ese
    // escaneo ocurria mientras PrismHub todavia estaba vivo: aparecia la
    // pantalla de "hay que cerrar estas aplicaciones" y quedaba en manos del
    // usuario aceptar. Si la cerraba mal, o el proceso quedaba a medio salir,
    // la actualizacion podia escribir sobre archivos en uso.
    //
    // Con la espera, cuando el instalador mira ya no hay nada corriendo y hace
    // su trabajo sin preguntar nada.
    //
    // El comando va en un archivo .ps1 y no en -Command: encadenar la espera y
    // el Start-Process en una sola linea obliga a anidar comillas dentro de
    // comillas, y basta con que la ruta de instalacion tenga un espacio o un
    // apostrofo para que se rompa de formas dificiles de ver.
    final script = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'prismhub-update-${DateTime.now().millisecondsSinceEpoch}.ps1',
    );
    await script.writeAsString(
      // 3 segundos: de sobra para que el proceso muera, y poco como para que
      // no parezca que el boton no hizo nada.
      'Start-Sleep -Seconds 3\n'
      'Start-Process -FilePath ${_psQuote(installerPath)} -Verb RunAs\n'
      // El script se borra solo: es temporal y no tiene por que quedar.
      'Remove-Item -LiteralPath ${_psQuote(script.path)} -Force '
      '-ErrorAction SilentlyContinue\n',
    );

    // Sin await: este powershell tiene que SOBREVIVIR al exit(0) de abajo. Con
    // Process.run se esperaria a que termine, y lo que hace es justamente
    // esperar a que nos vayamos.
    unawaited(Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
      ],
      mode: ProcessStartMode.detached,
    ));

    // Un respiro para que el proceso hijo quede lanzado antes de irnos.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  static Future<void> _replaceAndRestart(
    Directory sourceDir,
    Directory tempDir,
  ) async {
    final currentExe = Platform.resolvedExecutable;
    final installDir = Directory(currentExe).parent;
    final exeName = currentExe.split(Platform.pathSeparator).last;

    if (Platform.isLinux) {
      try {
        if (!_canWriteTo(installDir)) {
          throw 'La carpeta de instalación no permite escritura: ${installDir.path}';
        }
        // Copiar archivos con permisos
        final copyResult = await Process.run(
            'cp', ['-r', '${sourceDir.path}/.', installDir.path]);
        _throwIfProcessFailed('cp', copyResult);
        // Asegurar que el ejecutable sea ejecutable
        final chmodResult =
            await Process.run('chmod', ['+x', '${installDir.path}/$exeName']);
        _throwIfProcessFailed('chmod', chmodResult);
        // Iniciar la app actualizada en un nuevo proceso
        Process.start(
          '${installDir.path}/$exeName',
          [],
          mode: ProcessStartMode.detached,
        );
        // Dar tiempo para que el nuevo proceso inicie antes de salir
        await Future.delayed(const Duration(milliseconds: 500));
        exit(0);
      } catch (e) {
        debugPrint('Linux update failed: $e');
        rethrow;
      }
    } else if (Platform.isWindows) {
      final scriptPath = '${tempDir.path}\\update.ps1';
      final logPath =
          '${Directory.systemTemp.path}\\PrismHub-update-${DateTime.now().millisecondsSinceEpoch}.log';

      File(scriptPath).writeAsStringSync(
        r'''
param(
  [string]$SourceDir,
  [string]$InstallDir,
  [string]$ExeName,
  [string]$TempDir,
  [string]$LogPath,
  [int]$AppPid
)

$ErrorActionPreference = 'Continue'
$VerbosePreference = 'Continue'

function Log([string]$Message) {
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  $logMessage = "[$timestamp] $Message"
  Write-Host $logMessage
  Add-Content -LiteralPath $LogPath -Value $logMessage
}

Log "Update script started"
Log "Source: $SourceDir"
Log "Install: $InstallDir"
Log "App PID: $AppPid"

try {
  # Esperar a que la aplicación se cierre (máximo 30 segundos)
  Log "Waiting for PrismHub process $AppPid to exit..."
  try {
    $process = Get-Process -Id $AppPid -ErrorAction SilentlyContinue
    if ($process) {
      $process.WaitForExit(30000)
      Log "Process exited"
    } else {
      Log "Process not found, proceeding with update"
    }
  } catch {
    Log "Could not wait for process: $_"
  }
  
  # Crear directorio de instalación si no existe
  if (-not (Test-Path $InstallDir)) {
    Log "Creating install directory: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  }
  
  # Copiar archivos
  Log "Copying files from $SourceDir to $InstallDir"
  Get-ChildItem -LiteralPath $SourceDir -Force |
    Copy-Item -Destination $InstallDir -Recurse -Force -ErrorAction Stop
  
  Log "Copy completed"
  
  # Iniciar la aplicación actualizada
  $exePath = Join-Path $InstallDir $ExeName
  Log "Starting $exePath"
  Start-Process -FilePath $exePath -PassThru
  Log "Application started"
  
} catch {
  Log "ERROR: $($_.Exception.Message)"
  Log "Attempting to start existing application..."
  try {
    Start-Process -FilePath (Join-Path $InstallDir $ExeName)
  } catch {
    Log "Failed to start application: $_"
  }
} finally {
  Log "Cleaning up temp directory..."
  try {
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    Log "Temp directory cleaned"
  } catch {
    Log "Could not clean temp: $_"
  }
  Log "Update script finished"
}
''',
      );

      final args = [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-SourceDir',
        sourceDir.path,
        '-InstallDir',
        installDir.path,
        '-ExeName',
        exeName,
        '-TempDir',
        tempDir.path,
        '-LogPath',
        logPath,
        '-AppPid',
        pid.toString(),
      ];

      try {
        if (_canWriteTo(installDir)) {
          // Permisos suficientes: ejecutar sin elevar
          await Process.start(
            'powershell',
            args,
            mode: ProcessStartMode.detached,
          );
          debugPrint('Update script started with standard permissions');
        } else {
          // Sin permisos: elevar con RunAs
          final argLine = args.map(_psQuote).join(' ');
          final command = 'Start-Process -FilePath powershell '
              '-ArgumentList ${_psQuote(argLine)} '
              '-Verb RunAs -WindowStyle Hidden';
          await Process.run('powershell', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            command,
          ]);
          debugPrint('Update script started with elevated permissions');
        }
        // Esperar un poco antes de salir para que PowerShell inicie
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        debugPrint('Failed to start update script: $e');
        rethrow;
      }

      exit(0);
    }
  }
}

// Página de pantalla completa sin forma de descartarla (PopScope con
// canPop:false, sin AppBar/botón atrás) — se muestra solo cuando
// checkForcedUpdate() confirmó una versión más nueva. En Windows/Linux con
// asset disponible, "Actualizar ahora" descarga+instala+reinicia el proceso
// solo (nunca vuelve a esta página). En Android (y Desktop sin asset
// coincidente) abre la página de GitHub en el navegador y agrega un botón
// "Ya actualicé": vuelve a consultar PackageInfo.fromPlatform() (lee el
// paquete instalado en el SO, no el proceso en memoria) para detectar si la
// actualización ya se instaló y, en ese caso, recién ahí cierra el gate.
class _ForcedUpdatePage extends StatefulWidget {
  const _ForcedUpdatePage({
    required this.remoteVersion,
    required this.changelog,
    required this.htmlUrl,
    required this.asset,
  });

  final String remoteVersion;
  final String changelog;
  final String htmlUrl;
  final Map<String, dynamic>? asset;

  @override
  State<_ForcedUpdatePage> createState() => _ForcedUpdatePageState();
}

class _ForcedUpdatePageState extends State<_ForcedUpdatePage> {
  bool _checking = false;

  // Uno por variante: solo se construye una de las dos, pero teniendolos
  // separados un cambio de tamano de ventana (de la disposicion de escritorio a
  // la de celular) no deja un mismo controller enganchado a dos vistas.
  final _scrollEscritorio = ScrollController();
  final _scrollMovil = ScrollController();

  @override
  void dispose() {
    _scrollEscritorio.dispose();
    _scrollMovil.dispose();
    super.dispose();
  }

  bool get _needsManualRetry => Platform.isAndroid || widget.asset == null;

  Future<void> _retryCheck() async {
    setState(() => _checking = true);
    try {
      packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.version == widget.remoteVersion) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        return;
      }
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'upgrade.still-outdated'.i18n,
        );
      }
    } catch (_) {
      if (mounted) {
        showPlatformSnackbar(context: context, content: 'upgrade.error'.i18n);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // Mientras se descarga, los botones quedan apagados. Sin esto, tocar
  // "Actualizar ahora" dos veces arrancaba DOS descargas del mismo archivo
  // sobre la misma ruta, cada una escribiendo encima de la otra: el instalador
  // podía quedar a medio escribir y fallar sin motivo aparente.
  bool _descargando = false;

  bool get _ocupado => _checking || _descargando;

  /// Etiqueta del boton principal. Mientras se descarga muestra una rueda y el
  /// texto de "descargando": los botones quedan apagados, y sin ninguna senal
  /// parecia que el toque no habia hecho nada y se volvia a tocar.
  Widget get _etiquetaActualizar {
    if (!_descargando) return Text('upgrade.update-now'.i18n);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'upgrade.downloading'.i18n,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _updateNow() async {
    if (_ocupado) return;
    // Sin asset no hay nada que descargar: se abre la página de versiones y
    // listo, no hay estado que bloquear.
    if (widget.asset == null) {
      await launchUrl(
        Uri.parse(widget.htmlUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    setState(() => _descargando = true);
    try {
      // Mismo camino en las tres plataformas: _downloadAndInstall ya ramifica
      // adentro (APK en Android, instalador o comprimido en escritorio).
      await ApplicationUtils._downloadAndInstall(
        context,
        widget.asset!,
        widget.remoteVersion,
      );
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (!isMobile) {
      return PopScope(
        canPop: false,
        // Fondo propio: sin esto queda el negro crudo de la ventana, que no es
        // el fondo de la app y se notaba sobre todo arriba, alrededor de la
        // franja de arrastre.
        child: ColoredBox(
          color: HomeTheme.bg,
          child: Column(
          children: [
            // Barra de ventana propia. La barra nativa de Windows esta oculta
            // (TitleBarStyle.hidden en main.dart), asi que antes aca solo habia
            // una franja transparente de 32px: se podia arrastrar, pero se veia
            // como una banda negra sin nada y —mas importante— no habia NINGUNA
            // forma de minimizar ni cerrar. Con esta pantalla abierta al
            // arrancar, la unica salida era el administrador de tareas.
            if (Platform.isWindows || Platform.isLinux)
              const _BarraVentanaActualizacion(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    elevation: 8,
                    // Colores de la app y no los de Material: en escritorio la
                    // raiz es FluentApp, asi que no hay Theme y Card caia al
                    // tema CLARO por defecto — tarjeta casi blanca sobre el
                    // fondo oscuro.
                    color: HomeTheme.cardSurface,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: HomeTheme.border)),
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: 600,
                        maxHeight: 500,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color:
                                  HomeTheme.accentPink.withValues(alpha: 0.1),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.system_update,
                                    size: 24, color: HomeTheme.accentPink),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    FlutterI18n.translate(
                                      context,
                                      'upgrade.new-version',
                                      translationParams: {
                                        'version': widget.remoteVersion
                                      },
                                    ),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: HomeTheme.accentPink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: _scrollEscritorio,
                              // Siempre visible: es la unica pista de que las
                              // notas siguen mas abajo. Por defecto aparece
                              // solo mientras se arrastra, o sea justo cuando
                              // ya te enteraste de que habia scroll.
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                              controller: _scrollEscritorio,
                              child: Padding(
                                // Aire a la derecha para que la barra no quede
                                // pintada encima del texto.
                                padding: const EdgeInsets.fromLTRB(24, 24, 32, 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      FlutterI18n.translate(
                                        context,
                                        'upgrade.forced-required',
                                        translationParams: {
                                          'actual': packageInfo.version
                                        },
                                      ),
                                      style: const TextStyle(
                                          color: HomeTheme.textPrimary),
                                    ),
                                    const SizedBox(height: 16),
                                    MarkdownBody(
                                      data: widget.changelog,
                                      styleSheet: estiloNotasVersion(),
                                      onTapLink: abrirEnlaceDeNotas,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                if (_needsManualRetry) ...[
                                  Expanded(
                                    child: PlatformTextButton(
                                      onPressed: _ocupado ? null : _retryCheck,
                                      child:
                                          Text('upgrade.already-updated'.i18n),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: PlatformFilledButton(
                                    onPressed: _ocupado ? null : _updateNow,
                                    child: _etiquetaActualizar,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      );
    }

    // Mobile: pantalla completa forzada (sin forma de salir)
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 8,
              // Ver el comentario de la tarjeta de escritorio.
              color: HomeTheme.cardSurface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: HomeTheme.border)),
              child: Container(
                constraints: BoxConstraints(
                  // Tope de ancho: en horizontal, con el telefono acostado, la
                  // tarjeta se estiraba de borde a borde y las lineas quedaban
                  // larguisimas e incomodas de leer.
                  maxWidth: 560,
                  // En horizontal el alto util es la mitad, asi que 0.8 dejaba
                  // el contenido apretado contra los bordes; se deja mas margen
                  // cuando la pantalla es baja.
                  maxHeight: MediaQuery.of(context).size.height *
                      (MediaQuery.of(context).orientation ==
                              Orientation.landscape
                          ? 0.86
                          : 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollMovil,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                        controller: _scrollMovil,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 30, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.system_update,
                                  size: 48, color: HomeTheme.accentPink),
                              const SizedBox(height: 16),
                              Text(
                                FlutterI18n.translate(
                                  context,
                                  'upgrade.new-version',
                                  translationParams: {
                                    'version': widget.remoteVersion
                                  },
                                ),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: HomeTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                FlutterI18n.translate(
                                        context,
                                        'upgrade.forced-required',
                                        translationParams: {
                                          'actual': packageInfo.version
                                        },
                                      ),
                                style: const TextStyle(
                                    color: HomeTheme.textPrimary),
                              ),
                              const SizedBox(height: 16),
                              MarkdownBody(
                                data: widget.changelog,
                                styleSheet: estiloNotasVersion(),
                                onTapLink: abrirEnlaceDeNotas,
                              ),
                            ],
                          ),
                        ),
                      ),
                      ),
                    ),
                    // Botones en COLUMNA y no en fila. Con los dos al lado,
                    // "Ya actualice" y "Actualizar ahora" se repartian medio
                    // ancho de telefono cada uno: los textos entraban justos,
                    // se partian en dos lineas o quedaban con puntos
                    // suspensivos. Uno abajo del otro cada uno tiene el ancho
                    // entero, y el principal queda primero, que es lo que se
                    // espera que toques.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BotonActualizarMovil(
                            onPressed: _ocupado ? null : _updateNow,
                            principal: true,
                            child: _etiquetaActualizar,
                          ),
                          if (_needsManualRetry) ...[
                            const SizedBox(height: 10),
                            _BotonActualizarMovil(
                              onPressed: _ocupado ? null : _retryCheck,
                              principal: false,
                              child: Text('upgrade.already-updated'.i18n),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Espera a que la app vuelva al frente para retomar algo que quedo pendiente
/// en una pantalla del sistema (ver ApplicationUtils._instalarAlVolver).
///
/// Se desengancha solo despues del primer regreso: no puede quedar escuchando
/// para siempre ni disparar dos veces.
class _EsperaPermisoDeInstalacion with WidgetsBindingObserver {
  _EsperaPermisoDeInstalacion(this._alVolver);

  final Future<void> Function() _alVolver;
  bool _terminado = false;

  void empezar() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_terminado || state != AppLifecycleState.resumed) return;
    _terminado = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_alVolver());
  }
}


/// Las notas de la version dentro del dialogo de "hay version nueva".
///
/// Tiene su propio ScrollController por dos motivos: hace falta para que la
/// barra de desplazamiento sepa a que atarse (sin controller explicito no se
/// dibuja), y siendo un StatefulWidget se puede liberar en dispose en vez de
/// quedar colgado en cada apertura del dialogo.
///
/// Usa MarkdownBody y no Markdown: el segundo trae su propia area
/// desplazable, y anidada dentro de otra las dos se pelean el gesto — el de
/// adentro se lo queda y el contenido queda cortado o rebotando. MarkdownBody
/// solo pinta, y el scroll lo pone este widget una sola vez.
class _NotasDeVersion extends StatefulWidget {
  const _NotasDeVersion(this.body);

  final String body;

  @override
  State<_NotasDeVersion> createState() => _NotasDeVersionState();
}

class _NotasDeVersionState extends State<_NotasDeVersion> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  MarkdownStyleSheet get _estilo => estiloNotasVersion();

  @override
  Widget build(BuildContext context) {
    // Alto acotado: sin esto el dialogo crece con el largo de las notas y se
    // pasa de la pantalla. En el telefono se mide contra el alto real (funciona
    // igual en vertical que en horizontal, donde el alto util es la mitad).
    final alto = Platform.isAndroid
        ? MediaQuery.of(context).size.height * 0.42
        : 400.0;
    return SizedBox(
      width: double.maxFinite,
      height: alto,
      child: Scrollbar(
        controller: _scroll,
        // Siempre visible: es la unica pista de que hay mas texto abajo. Por
        // defecto solo aparece mientras se arrastra, o sea justo cuando ya
        // sabias que habia scroll.
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          // Aire a la derecha para la barra. Sin esto queda pintada ENCIMA del
          // texto, que era lo que se veia en escritorio.
          padding: const EdgeInsets.only(right: 16),
          child: MarkdownBody(
            data: widget.body,
            styleSheet: _estilo,
            onTapLink: abrirEnlaceDeNotas,
          ),
        ),
      ),
    );
  }
}

/// Colores de la app para las notas de version, en vez de los del tema por
/// defecto.
///
/// Sin esto, en Android el Markdown se pintaba con los colores de Material:
/// enlaces y titulos en azul sobre el fondo oscuro de la app, que ademas de
/// no pegar con nada se leia mal. La usan el dialogo de "hay version nueva"
/// y la pantalla de actualizacion obligatoria, que muestran lo mismo.
MarkdownStyleSheet estiloNotasVersion() {
  const cuerpo = TextStyle(
    color: HomeTheme.textPrimary,
    fontSize: 13.5,
    height: 1.5,
  );
  const titulo = TextStyle(
    color: HomeTheme.textPrimary,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );
  return MarkdownStyleSheet(
    p: cuerpo,
    listBullet: cuerpo,
    strong: cuerpo.copyWith(fontWeight: FontWeight.w700),
    em: cuerpo.copyWith(fontStyle: FontStyle.italic),
    // El acento de la app en vez del azul de Material.
    a: cuerpo.copyWith(
      color: HomeTheme.accentPink,
      decoration: TextDecoration.underline,
      decorationColor: HomeTheme.accentPink,
    ),
    h1: titulo.copyWith(fontSize: 19),
    h2: titulo.copyWith(fontSize: 17),
    h3: titulo.copyWith(fontSize: 15),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h2Padding: const EdgeInsets.only(top: 14, bottom: 4),
    h3Padding: const EdgeInsets.only(top: 10, bottom: 2),
    blockquote: cuerpo.copyWith(color: HomeTheme.textMuted),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    blockquoteDecoration: BoxDecoration(
      color: HomeTheme.cardSurface,
      borderRadius: BorderRadius.circular(8),
      border: const Border(
        left: BorderSide(color: HomeTheme.accentPink, width: 3),
      ),
    ),
    code: const TextStyle(
      color: HomeTheme.accentPink,
      fontSize: 12.5,
      fontFamily: 'monospace',
      backgroundColor: Colors.transparent,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: HomeTheme.cardSurface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: HomeTheme.border),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: HomeTheme.border)),
    ),
    tableHead: cuerpo.copyWith(fontWeight: FontWeight.w700),
    tableBody: cuerpo,
    tableBorder: TableBorder.all(color: HomeTheme.border, width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    listBulletPadding: const EdgeInsets.only(right: 6),
    blockSpacing: 10,
  );
}


/// Barra de ventana de la pantalla de actualizacion obligatoria.
///
/// La app oculta la barra de titulo nativa, asi que cada pantalla que pueda
/// aparecer sola tiene que dibujar la suya. Esta pantalla se muestra ANTES que
/// el resto de la interfaz, o sea antes de que exista cualquier otra barra.
///
/// Lleva minimizar y cerrar a proposito: la actualizacion es obligatoria para
/// USAR la app, no para tenerla abierta. Sin estos botones, y con la barra
/// nativa oculta, la unica manera de salir era matar el proceso.
class _BarraVentanaActualizacion extends StatelessWidget {
  const _BarraVentanaActualizacion();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: HomeTheme.cardSurface,
        border: Border(bottom: BorderSide(color: HomeTheme.border)),
      ),
      child: Row(
        children: [
          // El area arrastrable se queda con todo el espacio libre, no solo con
          // el ancho del texto: asi se puede mover la ventana desde cualquier
          // parte vacia de la barra, como en cualquier ventana del sistema.
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.system_update,
                        size: 16, color: HomeTheme.accentPink),
                    const SizedBox(width: 10),
                    const Text(
                      'PrismHub',
                      style: TextStyle(
                        color: HomeTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'v${packageInfo.version}',
                      style: const TextStyle(
                        color: HomeTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _BotonVentana(
            icono: Icons.remove,
            onTap: () => windowManager.minimize(),
          ),
          _BotonVentana(
            icono: Icons.close,
            peligro: true,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _BotonVentana extends StatefulWidget {
  const _BotonVentana({
    required this.icono,
    required this.onTap,
    this.peligro = false,
  });

  final IconData icono;
  final VoidCallback onTap;
  /// Cerrar se pinta en rojo al pasar por encima, como en Windows.
  final bool peligro;

  @override
  State<_BotonVentana> createState() => _BotonVentanaState();
}

class _BotonVentanaState extends State<_BotonVentana> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final fondo = !_encima
        ? Colors.transparent
        : (widget.peligro
            ? HomeTheme.accentRed
            : Colors.white.withValues(alpha: 0.08));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          color: fondo,
          child: Icon(
            widget.icono,
            size: 16,
            color: _encima && widget.peligro
                ? Colors.white
                : HomeTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}


/// Abre un enlace de las notas de version en el navegador del sistema.
///
/// Va aparte porque las notas se muestran en TRES lugares: el dialogo de "hay
/// version nueva" y las dos variantes —escritorio y celular— de la pantalla de
/// actualizacion obligatoria. En esas dos ultimas no habia manejador, asi que
/// los enlaces se veian subrayados y con el color de acento pero tocarlos no
/// hacia absolutamente nada.
///
/// La firma es la que espera MarkdownBody.onTapLink: (texto, href, titulo).
///
/// Nunca lanza: un href vacio o mal formado no puede tumbar la pantalla que
/// justamente esta pidiendo actualizar.
void abrirEnlaceDeNotas(String _, String? href, String __) {
  if (href == null || href.trim().isEmpty) return;
  try {
    final uri = Uri.parse(href.trim());
    // Sin esquema no hay a donde ir (un ancla interna del propio markdown, por
    // ejemplo): se ignora en vez de abrir el navegador en cualquier lado.
    if (!uri.hasScheme) return;
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  } catch (e) {
    debugPrint('No se pudo abrir el enlace de las notas: $e');
  }
}


/// Boton de la pantalla de actualizacion en celular.
///
/// No usa PlatformFilledButton porque ese cae en el FilledButton de Material
/// con el tema por defecto: color del sistema en vez del acento de la app, y
/// una altura pensada para un boton de formulario, no para la accion principal
/// de una pantalla que ocupa todo el ancho.
class _BotonActualizarMovil extends StatelessWidget {
  const _BotonActualizarMovil({
    required this.child,
    required this.onPressed,
    required this.principal,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// El principal va relleno con el acento; el otro, solo con borde. Deja claro
  /// cual es la accion que se espera sin tener que leer los dos.
  final bool principal;

  @override
  Widget build(BuildContext context) {
    final apagado = onPressed == null;
    final fondo = !principal
        ? Colors.transparent
        : (apagado
            // Apagado pero reconocible: en gris quedaba como si el boton no
            // existiera, y este es JUSTO el momento en que se esta descargando
            // y hay que ver que sigue ahi.
            ? HomeTheme.accentPink.withValues(alpha: 0.35)
            : HomeTheme.accentPink);
    final texto = principal
        ? Colors.white
        : (apagado ? HomeTheme.textMuted : HomeTheme.textPrimary);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: principal
                  ? null
                  : Border.all(
                      color: apagado ? HomeTheme.border : HomeTheme.accentPink),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: texto,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: texto),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
