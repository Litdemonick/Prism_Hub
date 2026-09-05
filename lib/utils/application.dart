// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prismhub/utils/connectivity.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/modo_app.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/tv/desplazable_con_mando.dart';
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

  /// Ya se está descargando/instalando una actualización.
  ///
  /// ── Por qué hace falta ────────────────────────────────────────────────
  ///
  /// La descarga de una versión nueva puede llevar varios minutos con una
  /// conexión lenta, y mientras tanto el chequeo periódico sigue latiendo:
  /// volvía a encontrar la misma versión nueva y sacaba el aviso ENCIMA de la
  /// descarga que ya estaba en curso. Desde afuera se ve como que la app
  /// insiste con algo que uno ya aceptó.
  ///
  /// La bandera que había vivía dentro del widget del diálogo, así que se
  /// perdía en cuanto ese widget se reconstruía o se abría otra pantalla —
  /// que es justo lo que pasa en Android al cambiar de pestaña.
  ///
  /// Estática: hay una sola actualización a la vez en toda la app.
  static bool _instalacionEnCurso = false;

  /// Para que otras partes puedan preguntar sin poder tocarla.
  static bool get instalacionEnCurso => _instalacionEnCurso;

  /// Ya hay un aviso de versión nueva en pantalla.
  ///
  /// ── El fallo que tapa ─────────────────────────────────────────────────
  ///
  /// Reportado en vivo con captura, en PC: salían DOS avisos de la misma
  /// versión, uno encima del otro.
  ///
  /// La causa es que hay dos caminos distintos que avisan, y ninguno sabía
  /// del otro:
  ///
  ///   checkForcedUpdate   la pantalla que TAPA la app entera. Sale sola al
  ///                       arrancar y en el chequeo periódico.
  ///   checkUpdate         el diálogo descartable. Sale al tocar «Comprobar»
  ///                       en Ajustes y en los reintentos que se programan
  ///                       cuando el release todavía estaba a medio publicar.
  ///
  /// Cada uno tenía sus propios candados —`_forcedUpdatePageOpen`,
  /// `_forcedUpdateCheckInFlight`— pero eran suyos: nada impedía que el
  /// reintento del segundo saltara justo cuando el primero ya estaba
  /// mostrando la pantalla, que es exactamente lo que pasó.
  ///
  /// Este es uno solo para los dos. Ninguna app debería mostrar el mismo
  /// aviso dos veces.
  static bool _avisoDeVersionEnPantalla = false;
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

  /// ¿Todavía no está claro qué trae este release — nada subido aún, o
  /// alguno de sus archivos a medias?
  ///
  /// Cada job del workflow sube lo suyo al terminar, así que un release recién
  /// publicado pasa por estados intermedios — visto en vivo: Linux listo a los
  /// 4 minutos, Windows y Android todavía compilando. Un asset a medio subir
  /// aparece en la API con state "uploaded" recién cuando terminó; cualquier
  /// otro estado significa que sigue en curso.
  ///
  /// Una lista de assets VACÍA cuenta igual como "todavía en curso" — no como
  /// "no trae nada para mí" —: un release recién creado empieza sin ningún
  /// archivo listado hasta que el primer job termina de subir el suyo, y en
  /// esa ventana no se sabe todavía si va a incluir esta plataforma o no.
  static bool _algoTodaviaSubiendo(dynamic assets) {
    try {
      final list = (assets as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return true;
      return list.any((a) {
        final estado = (a['state'] as String?)?.toLowerCase();
        return estado != null && estado != 'uploaded';
      });
    } catch (_) {
      // Ante un formato inesperado se asume que sigue en curso: no avisar de
      // más es preferible a mandar a alguien a una descarga rota.
      return true;
    }
  }

  /// ¿Este release trae el archivo de la plataforma en la que corre la app?
  ///
  /// Desde que un release puede publicarse para UNA SOLA plataforma (ver
  /// `_ultimoReleaseParaEstaPlataforma`), ya no tiene sentido pedir las tres
  /// juntas acá: un release hecho a propósito solo para Android, por
  /// ejemplo, nunca va a traer el instalador de Windows, y eso no lo vuelve
  /// "incompleto" para quien SÍ corre en Android.
  static bool _traeEstaPlataforma(dynamic assets) {
    try {
      final nombres = (assets as List)
          .cast<Map<String, dynamic>>()
          .map((a) => (a['name'] as String?)?.toLowerCase() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (nombres.isEmpty) return false;
      if (Platform.isAndroid) return nombres.any((n) => n.endsWith('.apk'));
      if (Platform.isLinux) return nombres.any((n) => n.contains('linux'));
      // En Windows puede venir el instalador, el comprimido, o los dos.
      return nombres.any((n) => n.endsWith('.exe') || n.contains('windows'));
    } catch (_) {
      return false;
    }
  }

  /// ¿Este release se declaró a mano como exclusivo de OTRA plataforma?
  ///
  /// Hay dos casos que el nombre de los archivos no puede distinguir solo:
  ///
  ///  - **Android TV contra celular/tablet**: corren el MISMO APK, así que no
  ///    hay forma de compilar uno sin el otro.
  ///  - **Un release que se publicó completo pero solo interesa a una
  ///    plataforma**: los tres archivos existen, pero avisar a las demás sería
  ///    mandarlas a actualizar por algo que no les cambia nada.
  ///
  /// Para los dos se declara a mano en el cuerpo del release — mismo mecanismo
  /// que `min-update-from`, un comentario HTML invisible en la página de
  /// GitHub pero legible desde acá:
  ///
  ///     <!-- solo-plataforma: androidtv -->
  ///
  /// Valores aceptados: `androidtv`, `android`, `windows` y `linux`. Se puede
  /// poner más de uno separados por coma.
  ///
  /// Sin la marca, el release aplica a todos — igual que siempre.
  static bool _soloParaOtraPlataforma(dynamic body) {
    if (body is! String) return false;
    final marca = RegExp(
      r'solo-plataforma:\s*([a-z, ]+)',
      caseSensitive: false,
    ).firstMatch(body)?.group(1);
    if (marca == null) return false;
    final para = marca
        .toLowerCase()
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (para.isEmpty) return false;
    final soyYo = switch (true) {
      _ when Platform.isAndroid && PlatformTv.esTelevisionSync => 'androidtv',
      _ when Platform.isAndroid => 'android',
      _ when Platform.isWindows => 'windows',
      _ when Platform.isLinux => 'linux',
      _ => '',
    };
    // Un valor que no se reconoce no puede dejar a nadie sin actualizaciones:
    // si la marca no nombra ninguna plataforma conocida, se ignora.
    const conocidas = {'androidtv', 'android', 'windows', 'linux'};
    if (!para.any(conocidas.contains)) return false;
    return !para.contains(soyYo);
  }

  /// Busca, entre los releases más recientes del repo, el más nuevo que sea
  /// candidato para ESTA plataforma — no necesariamente el último publicado
  /// en el repo entero, si ese fue hecho a propósito solo para otra(s)
  /// plataforma(s) (ver el pedido de "actualizar solo Android sin molestar a
  /// Windows/Linux con algo que no les trae nada").
  ///
  /// "Candidato" no es lo mismo que "listo para ofrecer": acá solo se decide
  /// SI aplica, no si ya está completo. Cada llamador decide qué hacer con
  /// un candidato que todavía se está publicando o le faltan las notas — el
  /// chequeo forzado espera en silencio (`_ultimoReleaseParaEstaPlataforma`),
  /// el manual le explica al usuario qué falta (`checkUpdate`).
  ///
  /// Antes esto era un solo `GET releases/latest`: alcanzaba porque un
  /// release siempre traía las tres plataformas juntas. Con releases
  /// parciales, "el último del repo" y "el último que me toca a mí" pueden
  /// ser dos cosas distintas, así que hay que mirar hacia atrás hasta
  /// encontrar el que aplique.
  ///
  /// `per_page=10` alcanza de sobra para el ritmo de publicación de este
  /// proyecto — y sigue costando UNA sola llamada a la API (mismo cupo que
  /// antes, no se multiplicó nada).
  ///
  /// Una versión de la app ANTERIOR a este cambio sigue pidiendo
  /// `releases/latest` con la lógica vieja (exige las tres plataformas), así
  /// que un release parcial le resulta invisible — nunca rompe nada, sigue
  /// esperando en silencio hasta que salga un release completo que sí la
  /// actualice. Por eso el primer release que lleve este fix conviene que
  /// salga completo para las tres plataformas.
  static Future<Map<String, dynamic>?> _candidatoRelevante() async {
    const url =
        "https://api.github.com/repos/Litdemonick/Prism_Hub/releases?per_page=10";
    final res = await dio.get(url);
    final releases = (res.data as List).cast<Map<String, dynamic>>();
    for (final release in releases) {
      final tagName = release['tag_name'] as String;
      if (!_isRemoteVersionNewer(tagName.replaceFirst('v', ''))) {
        // Llegamos a uno igual o más viejo que lo instalado: no hay nada
        // más nuevo detrás de este en la lista (viene ordenada del más
        // reciente al más viejo), así que no tiene sentido seguir mirando.
        return null;
      }
      if (_soloParaOtraPlataforma(release['body'])) {
        // Declarado a mano para otra plataforma: no es para mí aunque el
        // archivo esté ahí. Ya se sabe con certeza por la marca, así que no
        // hace falta esperar a que termine de subir nada. Sigo mirando hacia
        // atrás por si uno anterior sí me incluía.
        continue;
      }
      if (_algoTodaviaSubiendo(release['assets']) ||
          _traeEstaPlataforma(release['assets'])) {
        // O bien todavía no se sabe qué va a traer (se está publicando: no
        // conviene saltarlo, podría terminar incluyendo esta plataforma), o
        // bien ya se sabe que SÍ la incluye. Cualquiera de los dos es un
        // candidato válido para ofrecer (una vez que termine de estar listo).
        return release;
      }
      // Publicado a propósito solo para otra(s) plataforma(s), y ya
      // terminó de subir todo: no es para mí. Sigo mirando hacia atrás por
      // si uno más viejo (pero igual más nuevo que lo instalado) sí me
      // incluía.
    }
    return null;
  }

  /// Versión de `_candidatoRelevante` para el chequeo que NO puede molestar
  /// a nadie si algo todavía está a medias (el forzado/periódico, que
  /// bloquea la app entera): solo devuelve un release cuando está
  /// completamente listo para esta plataforma, y deja
  /// `_esperandoReleaseIncompleto` en el estado que le corresponde para que
  /// el chequeo periódico sepa si tiene que insistir pronto o no.
  static Future<Map<String, dynamic>?>
      _ultimoReleaseParaEstaPlataforma() async {
    final release = await _candidatoRelevante();
    if (release == null) {
      // Nada nuevo de verdad: si venía esperando un release a medio
      // publicar, ya no hay por qué seguir mirando seguido.
      _esperandoReleaseIncompleto = false;
      _rafagasRapidas = 0;
      return null;
    }
    if (_algoTodaviaSubiendo(release['assets']) ||
        !_traeEstaPlataforma(release['assets']) ||
        !_notasPublicadas(release['body'])) {
      // Candidato real, pero todavía no está listo del todo (subiendo, o
      // completo pero sin notas escritas): se sigue mirando seguido hasta
      // que lo esté (ver _cadaCuantoEsperando).
      _esperandoReleaseIncompleto = true;
      return null;
    }
    _esperandoReleaseIncompleto = false;
    _rafagasRapidas = 0;
    return release;
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
    r'|^\s*#{1,6}\s*(📦\s*)?Descargas?\s*$'
    // El encabezado con el nombre y la versión: sale igual en todos los
    // releases y no cuenta como haber escrito nada. Se descuenta para poder
    // bajar el umbral sin que un título suelto se haga pasar por notas.
    r'|^\s*#{0,6}\s*\*{0,2}PrismHub\s*v?\d[\d.]*\*{0,2}\s*(—.*)?$',
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
    // Bajo a propósito: lo que llega hasta acá ya es texto escrito a mano,
    // porque arriba se descontó todo lo que sale solo —el changelog de GitHub,
    // la tabla de descargas, el encabezado con la versión y los marcadores que
    // lee la app—.
    //
    // Estaba en 40 y eso dejaba afuera notas cortas pero legítimas: un release
    // que arregla una sola cosa se describe en menos. Ese release no le habría
    // avisado a nadie, nunca — y sin ningún error, simplemente callado, que es
    // la peor forma de fallar.
    //
    // 15 alcanza para una frase de verdad y sigue descartando lo que queda
    // cuando alguien publicó sin escribir: un signo suelto, dos palabras a
    // medio tipear.
    return visible.length >= 15;
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
    final marca =
        RegExp(r'min-update-from:\s*v?(\d+(?:\.\d+){0,2})').firstMatch(body);
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
    // Dos nombres para el instalador de Windows, y no uno.
    //
    // Desde la 1.0.28 lleva "windows" adentro (antes era solo "setup", que en
    // una lista con archivos de tres plataformas no decía para cuál era). El
    // nombre viejo se sigue aceptando: una versión anterior instalada tiene
    // que poder actualizarse igual, y quien publique un release con el nombre
    // de antes no se queda sin actualizaciones.
    final nombresDelSetup = <String>[
      'PrismHub-setup-windows-$tagName.exe',
      'PrismHub-setup-$tagName.exe',
    ];
    try {
      final list = assets as List;
      if (Platform.isWindows && _windowsInstallLooksManaged) {
        for (final esperado in nombresDelSetup) {
          final setup = list.firstWhereOrNull(
            (a) => (a['name'] as String?) == esperado,
          );
          if (setup != null) return setup as Map<String, dynamic>;
        }
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
    // En una compilación de prueba no se avisa de actualizaciones.
    //
    // Esa compilación se rehace todo el tiempo mientras se trabaja, así que
    // comparar su versión contra la publicada da "hay una nueva" casi siempre
    // — y este aviso es el que BLOQUEA la app hasta actualizar. Quedaba
    // tapando la pantalla justo cuando se está probando un cambio.
    //
    // Solo se calla el aviso: la comprobación manual desde Ajustes sigue
    // estando, para poder verificar que el flujo de actualización anda (ver
    // checkUpdate, que avisa en qué modo está).
    if (!ModoApp.esRelease) return;
    if (_forcedUpdatePageOpen) return;
    // El otro camino ya tiene un aviso en pantalla: no se apila encima. Es la
    // otra mitad del candado — ver _avisoDeVersionEnPantalla.
    if (_avisoDeVersionEnPantalla) return;
    // Ya se está bajando/instalando: no se vuelve a avisar de la misma
    // versión encima de la descarga que el usuario ya aceptó. Con una
    // conexión lenta la descarga dura minutos y el chequeo periódico seguía
    // latiendo — ver _instalacionEnCurso.
    if (_instalacionEnCurso) return;
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
      // Busca el release más nuevo que aplique a esta plataforma — ver
      // _ultimoReleaseParaEstaPlataforma. Si vuelve null puede ser que no
      // haya nada más nuevo que lo instalado, o que sí haya pero todavía
      // esté incompleto: en los dos casos no hay nada para ofrecer todavía,
      // y la función ya dejó _esperandoReleaseIncompleto en el valor que
      // corresponde para el chequeo periódico (ver _cadaCuantoEsperando).
      final release = await _ultimoReleaseParaEstaPlataforma();
      if (release == null) return;
      if (!context.mounted) return;

      final tagName = release['tag_name'] as String;
      final remoteVersion = tagName.replaceFirst('v', '');

      final asset = Platform.isAndroid
          ? _findAndroidAsset(release['assets'])
          : _findAsset(release['assets'], tagName);
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
      _avisoDeVersionEnPantalla = true;
      try {
        await Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, animation, secondaryAnimation) =>
                _ForcedUpdatePage(
              remoteVersion: remoteVersion,
              changelog: (release['body'] as String?) ?? '',
              htmlUrl: release['html_url'] as String,
              asset: asset,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
          ),
        );
      } finally {
        _forcedUpdatePageOpen = false;
        _avisoDeVersionEnPantalla = false;
      }
    } catch (e) {
      // Mismo motivo que en checkUpdate: el candado no puede quedarse trabado
      // por un fallo.
      _avisoDeVersionEnPantalla = false;
      // Silencioso: si no se puede chequear (sin internet, GitHub caído), no
      // hay que bloquear el uso de la app por un error de red — el gate solo
      // se muestra cuando SÍ se confirma una versión nueva.
      debugPrint('checkForcedUpdate error: $e');
    }
  }

  static checkUpdate(BuildContext context, {bool showSnackbar = false}) async {
    // En una compilación de prueba se dice y no se comprueba nada.
    //
    // Comparar la versión de una compilación de trabajo contra la publicada no
    // significa nada: se rehace en cada cambio. Pero tampoco conviene que el
    // botón se quede mudo, porque desde afuera no se distingue de que esté
    // roto — así que se explica por qué no hizo nada.
    if (!ModoApp.esRelease) {
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'Estás en una compilación de prueba (${ModoApp.etiqueta}): '
              'las actualizaciones solo se comprueban en la versión publicada.',
        );
      }
      return;
    }
    // Ya hay un aviso puesto (la pantalla bloqueante, u otro diálogo): no se
    // apila un segundo. Ver _avisoDeVersionEnPantalla.
    if (_avisoDeVersionEnPantalla || _forcedUpdatePageOpen) return;
    // Y tampoco mientras se está bajando algo: el usuario ya aceptó.
    if (_instalacionEnCurso) return;
    try {
      final release = await _candidatoRelevante();
      if (release != null) {
        final tagName = release['tag_name'] as String;
        final remoteVersion = tagName.replaceFirst('v', '');
        debugPrint('remoteVersion: $remoteVersion');
        // Esta versión es demasiado vieja para instalar la nueva encima: no se
        // ofrece la actualización automática, se manda a la página de
        // versiones. Ver _demasiadoViejoParaActualizar.
        if (_demasiadoViejoParaActualizar(release['body'])) {
          // Diálogo y no un aviso pasajero: esto no es "che, hay novedades",
          // es "esta actualización NO se va a poder instalar sola". Si se va
          // solo a los dos segundos, el usuario se queda sin saber qué hacer.
          if (context.mounted) {
            _avisoDeVersionEnPantalla = true;
            try {
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
                        Uri.parse(release['html_url'] as String),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Text('upgrade.download'.i18n),
                  ),
                ],
              );
            } finally {
              _avisoDeVersionEnPantalla = false;
            }
          }
          return;
        }
        // Ver el comentario largo de _ultimoReleaseParaEstaPlataforma:
        // mientras el archivo de esta plataforma no esté subido (o el
        // release recién esté empezando a publicarse), no se ofrece nada.
        final completo = !_algoTodaviaSubiendo(release['assets']) &&
            _traeEstaPlataforma(release['assets']);
        final asset = completo
            ? (Platform.isAndroid
                ? _findAndroidAsset(release['assets'])
                : _findAsset(release['assets'], tagName))
            : null;
        // Las notas se tratan igual que los archivos: un release se puede
        // publicar con el cuerpo vacío y editarse después, y ofrecer la
        // actualización en esa ventana es pedirle al usuario que decida sin
        // saber qué trae. Ver _notasPublicadas.
        final notasListas = _notasPublicadas(release['body']);
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
        _avisoDeVersionEnPantalla = true;
        if (Platform.isAndroid) {
          try {
            await showPlatformDialog(
              context: context,
              title: FlutterI18n.translate(
                context,
                'upgrade.new-version',
                translationParams: {
                  'version': remoteVersion,
                },
              ),
              content: _notasDeVersion(release['body']),
              // El contenido ya desplaza solo: ver el comentario de `scrollable`
              // en showPlatformDialog.
              scrollable: false,
              actions: [
                PlatformTextButton(
                  onPressed: () {
                    RouterUtils.pop();
                    _recordarComoActualizarDespues(context);
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
          } finally {
            _avisoDeVersionEnPantalla = false;
          }
          return;
        }

        // El de escritorio NO se espera (no lleva `await`), así que el
        // candado se suelta cuando el diálogo se cierra, no acá.
        unawaited(showPlatformDialog(
          context: context,
          title: FlutterI18n.translate(
            context,
            'upgrade.new-version',
            translationParams: {
              'version': remoteVersion,
            },
          ),
          content: _notasDeVersion(release['body']),
          maxWidth: _anchoDialogoNotas,
          actions: [
            PlatformTextButton(
              onPressed: () {
                RouterUtils.pop();
                _recordarComoActualizarDespues(context);
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
        ).whenComplete(() => _avisoDeVersionEnPantalla = false));
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
      // El candado se suelta pase lo que pase.
      //
      // Sin esto, un fallo entre tomarlo y mostrar el diálogo lo dejaría
      // puesto para siempre — y con él puesto no vuelve a avisarse NUNCA de
      // ninguna versión nueva, en toda la sesión. Un candado que se traba es
      // peor que el aviso duplicado que vino a arreglar.
      _avisoDeVersionEnPantalla = false;
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

  /// Al posponer, se recuerda por dónde se actualiza — y por qué conviene.
  ///
  /// No se insiste ni se vuelve a abrir el diálogo: si dijo que ahora no, es
  /// que ahora no. Pero cerrarlo sin más deja a alguien sin saber que puede
  /// volver cuando quiera, y con la idea de que perdió la oportunidad hasta
  /// que la app decida avisar de nuevo. Un renglón alcanza para dejar claro
  /// que la decisión sigue siendo suya y dónde está el botón.
  static void _recordarComoActualizarDespues(BuildContext context) {
    if (!context.mounted) return;
    showPlatformSnackbar(
      context: context,
      title: 'upgrade.check-update'.i18n,
      content: 'upgrade.later-hint'.i18n,
    );
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
      final cadaCuantosPulsos =
          rapido ? 1 : _cadaCuanto.inMinutes ~/ _cadaCuantoEsperando.inMinutes;
      if (pulsos % cadaCuantosPulsos != 0) return;
      if (rapido) _rafagasRapidas++;
      // Se relee el ajuste en cada vuelta: si el usuario lo apaga mientras
      // tanto, esto deja de molestar sin necesidad de reiniciar nada.
      if (PrismHubStorage.getSetting(SettingKey.autoCheckUpdate) != true) {
        return;
      }
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
    // Ya hay una descarga andando: no se arranca otra ni se avisa de nuevo.
    // Ver _instalacionEnCurso.
    if (_instalacionEnCurso) return;
    // ── Sin conexión no se arranca a ciegas ────────────────────────────
    //
    // Reportado en vivo: se cortaba el wifi o se cambiaba de red y la
    // pantalla de actualizar quedaba trabada — se tocaba «Actualizar» y no
    // pasaba nada visible durante el timeout entero de la descarga, y
    // después un error crudo de Dio que no dice nada.
    //
    // Diciéndolo de entrada, el botón queda libre para volver a intentar en
    // cuanto vuelva la red, sin haber esperado nada.
    if (!ConnectivityUtils.isOnline.value) {
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.install-failed'.i18n,
          content: 'upgrade.sin-conexion'.i18n,
        );
      }
      return;
    }
    _instalacionEnCurso = true;
    var progressDialogOpen = false;
    // Cuánto va descargado, para poder mostrarlo.
    //
    // Antes esto se calculaba igual y se mandaba SOLO al registro de depuración
    // (ver el onReceiveProgress de abajo): en pantalla había una rueda girando
    // sin principio ni fin. Una actualización de 80 MB con una conexión lenta
    // son varios minutos mirando algo que no dice si avanza ni cuánto falta, y
    // no hay forma de distinguirlo de que se haya colgado.
    final progreso = ValueNotifier<({double? parte, String texto})>(
      (parte: null, texto: ''),
    );
    if (context.mounted) {
      progressDialogOpen = true;
      unawaited(showPlatformDialog(
        context: context,
        title: 'upgrade.check-update'.i18n,
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _BarraDeDescarga(progreso: progreso),
        ),
        // null y no []: con una lista vacia, fluent dibuja igual la barra
        // de acciones y se veia un recuadro oscuro suelto abajo del dialogo.
        actions: null,
        maxWidth: 360,
        barrierDismissible: false,
      ));
      await Future<void>.delayed(Duration.zero);
    }

    // Declarado ACÁ afuera —no `final` adentro del try— porque el catch de
    // más abajo necesita mostrar esta ruta cuando lo único que falló fue
    // abrir el instalador: la descarga en sí ya terminó bien. Una variable
    // de un `try` no se ve en su propio `catch`.
    String? downloadPath;
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
      downloadPath =
          '${downloadDir.path}${Platform.pathSeparator}${asset['name']}';

      // Si ya está descargado de un intento anterior, no se vuelve a bajar.
      //
      // Reportado en vivo en Android TV: la primera pasada por Actualizar
      // terminaba de descargar pero se quedaba sin dar el permiso de
      // instalar apps desconocidas (ver openInstallSettings), así que
      // había que tocar Actualizar de nuevo — y eso volvía a bajar los
      // mismos megas de antes, con la conexión lenta típica de un
      // televisor. El tamaño exacto lo da GitHub en cada asset del
      // release; si el archivo que ya está en disco coincide byte a byte,
      // es el mismo APK completo y no partido a la mitad — se salta la
      // descarga y se va directo a instalar.
      final tamanoEsperado = asset['size'] as int?;
      final archivoDescarga = File(downloadPath);
      final yaDescargado = tamanoEsperado != null &&
          await archivoDescarga.exists() &&
          await archivoDescarga.length() == tamanoEsperado;
      if (yaDescargado) {
        progreso.value = (
          parte: 1.0,
          texto: '${_enMegas(tamanoEsperado)} MB',
        );
      } else {
        // Descargar con progreso
        await dio.download(url, downloadPath,
            onReceiveProgress: (count, total) {
          // total llega en -1 cuando el servidor no dice cuanto pesa. Ahi la
          // barra se queda indeterminada, pero al menos se muestra lo bajado:
          // que el numero suba ya dice que no se colgo.
          progreso.value = total > 0
              ? (
                  parte: count / total,
                  texto: '${_enMegas(count)} / ${_enMegas(total)} MB',
                )
              : (parte: null, texto: '${_enMegas(count)} MB');
        });
      }

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
        // Si no se pudo lanzar, se DICE. Antes se salia del app pasara lo que
        // pasara, asi que un fallo se veia igual que un exito: la ventana se
        // cerraba y no aparecia ningun instalador. Ahora la app se queda
        // abierta y explica que el archivo ya esta bajado y donde.
        final lanzado = await _runWindowsInstaller(downloadPath);
        if (!lanzado && context.mounted) {
          showPlatformSnackbar(
            context: context,
            content: FlutterI18n.translate(
              context,
              'upgrade.installer-failed',
              translationParams: {'path': downloadPath},
            ),
          );
        }
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
      // ── El caso "el APK está perfecto, lo que falló es abrirlo" ────────
      //
      // `installApk` (nativo) ahora prueba DOS intents antes de rendirse
      // (ver MainActivity.kt) — esto es lo que queda cuando ninguno de los
      // dos encontró una app que lo atienda, típicamente en una caja de
      // Android TV con el instalador recortado por el fabricante. La
      // descarga terminó bien: no hay nada que borrar, y decir "falló la
      // descarga" sería directamente mentir. Se avisa con la MISMA frase
      // que ya usa el instalador de Windows cuando no pudo lanzarse solo:
      // el archivo queda ahí y se dice dónde.
      final esFaltaDeInstalador = Platform.isAndroid &&
          e is PlatformException &&
          e.message == 'NO_INSTALLER_AVAILABLE';
      if (esFaltaDeInstalador) {
        if (context.mounted) {
          showPlatformSnackbar(
            context: context,
            title: 'upgrade.install-failed'.i18n,
            content: FlutterI18n.translate(
              context,
              'upgrade.installer-failed',
              translationParams: {'path': downloadPath ?? ''},
            ),
          );
        }
        debugPrint('Download/install error: $e');
        return;
      }
      // ── Lo que quedó a medias se borra ───────────────────────────────
      //
      // Si el wifi se cortó en mitad de la descarga queda un archivo
      // incompleto en disco. El chequeo de tamaño de más arriba ya lo
      // descarta —no coincide con el que dice GitHub— pero dejarlo ahí es
      // ocupar espacio en un aparato que suele andar justo, y encima
      // arriesgarse a que un día el tamaño coincida por casualidad y se
      // intente instalar un APK partido.
      unawaited(_borrarDescargaAMedias(asset));
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.install-failed'.i18n,
          content: _porQueFallo(e),
        );
      }
      debugPrint('Download/install error: $e');
    } finally {
      // En finally: por el camino bueno esta funcion puede terminar cerrando la
      // app para instalar, y por el malo sale por el catch. Soltarlo en uno
      // solo de los dos lo dejaba colgado en el otro.
      progreso.dispose();
      // El candado se suelta pase lo que pase. Si la descarga fallo, el
      // usuario tiene que poder volver a intentar; y si salio bien, la app
      // se esta por cerrar igual para instalar.
      _instalacionEnCurso = false;
    }
  }

  /// Traduce el fallo a algo que se entienda.
  ///
  /// Antes se mostraba `e.toString()` tal cual: una línea de Dio con la
  /// ruta, el tipo de excepción y el stack, que no le dice nada a nadie y
  /// encima tapa lo único que importa —si fue la red o fue otra cosa—.
  static String _porQueFallo(Object e) {
    if (!ConnectivityUtils.isOnline.value) return 'upgrade.sin-conexion'.i18n;
    if (e is DioException) {
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.connectionError =>
          'upgrade.se-corto'.i18n,
        _ => 'upgrade.fallo-descarga'.i18n,
      };
    }
    return 'upgrade.fallo-descarga'.i18n;
  }

  /// Borra el archivo a medio bajar, si quedó alguno.
  static Future<void> _borrarDescargaAMedias(Map<String, dynamic> asset) async {
    try {
      final nombre = asset['name'] as String?;
      if (nombre == null) return;
      final carpeta = Platform.isAndroid
          ? Directory(
              '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}update',
            )
          : null;
      if (carpeta == null || !carpeta.existsSync()) return;
      final archivo = File('${carpeta.path}${Platform.pathSeparator}$nombre');
      if (!archivo.existsSync()) return;
      final esperado = asset['size'] as int?;
      // Solo si está incompleto: uno entero sirve para reintentar sin
      // volver a bajar los mismos megas.
      if (esperado != null && await archivo.length() == esperado) return;
      await archivo.delete();
    } catch (_) {
      // Limpiar es cortesía: que no se pueda no puede tumbar nada.
    }
  }

  static String _enMegas(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

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
    // Cuánto tiempo total se espera antes de rendirse del todo.
    //
    // Reportado en vivo en Android TV: llegaba hasta acá, se descargaba
    // bien, pero al volver de Ajustes la app "pedía de nuevo" en vez de
    // instalar sola — había que tocar Actualizar una segunda vez para que
    // ahí sí funcionara. La causa: el reintento de abajo se rendía después
    // de apenas 3 intentos de 400ms (1.2 segundos) contados desde el
    // PRIMER "resumed". En un celular, tocar un interruptor lleva un
    // segundo. En un televisor, el mismo permiso se navega con el control
    // remoto — bajar el foco, confirmar, volver — y eso solo, sin
    // apurarse, ya pasa largo esos 1.2 segundos. Peor todavía: ese primer
    // "resumed" puede disparar apenas arranca la transición a Ajustes,
    // antes de que el usuario llegue siquiera a ver la pantalla — con lo
    // cual los tres intentos se gastaban solos, sin que hubiera pasado
    // nada todavía. El resultado se sentía igual en los dos casos: "se
    // canceló", y la segunda pasada por Actualizar (que ya no tiene apuro,
    // revisa el permiso una sola vez) andaba porque para entonces el
    // permiso ya estaba dado hacía rato.
    //
    // Ahora se sigue escuchando a través de VARIOS "resumed" — el usuario
    // puede volver a entrar a Ajustes más de una vez — durante hasta 3
    // minutos en vez de rendirse en el primero.
    final limite = DateTime.now().add(const Duration(minutes: 3));
    final observador = _EsperaPermisoDeInstalacion(() async {
      // El permiso puede tardar un instante en verse reflejado justo después
      // de volver, así que se consulta un par de veces antes de rendirse de
      // esta pasada — pero rendirse acá ya no apaga el observador (ver abajo).
      for (var intento = 0; intento < 5; intento++) {
        final permitido =
            await _canalActualizacion.invokeMethod<bool>('canInstallApks') ??
                false;
        if (permitido) {
          try {
            await _canalActualizacion
                .invokeMethod('installApk', {'apkPath': apkPath});
          } catch (e) {
            // Mismo caso que en _downloadAndInstall, pero acá el permiso SÍ
            // se consiguió y aun así no hay con qué abrir el instalador —
            // antes esto se perdía en un debugPrint que nadie ve fuera de un
            // depurador conectado, y el usuario se quedaba sin saber que el
            // APK ya está listo en disco.
            debugPrint('Reintento de instalación falló: $e');
            if (context.mounted) {
              showPlatformSnackbar(
                context: context,
                title: 'upgrade.install-failed'.i18n,
                content: FlutterI18n.translate(
                  context,
                  'upgrade.installer-failed',
                  translationParams: {'path': apkPath},
                ),
              );
            }
          }
          return true; // Listo — dejar de escuchar.
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (DateTime.now().isBefore(limite)) {
        return false; // Todavía sin permiso: puede volver a Ajustes, seguir esperando.
      }
      // Pasaron los 3 minutos sin permiso: recién ahí se avisa y se deja de
      // escuchar. El APK sigue guardado, así que tocar Actualizar otra vez
      // no vuelve a descargar nada.
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.install-failed'.i18n,
          content: 'upgrade.needs-install-permission'.i18n,
        );
      }
      return true;
    });
    observador.empezar();
    try {
      logger.info('Actualización: falta el permiso de instalar apps, '
          'se abren los ajustes del sistema');
      await _canalActualizacion.invokeMethod('openInstallSettings');
    } catch (e) {
      // El nativo ya prueba tres pantallas de Ajustes distintas antes de
      // rendirse (ver openInstallSettings en MainActivity.kt) — esto solo
      // cubre el caso de que ni siquiera esas tres existan. Sin el catch,
      // la excepción subía sin agarrar y el observador se quedaba
      // escuchando un "resumed" que ya nunca iba a llegar (la app nunca se
      // fue a segundo plano de verdad), así que tocar Actualizar de nuevo
      // era la ÚNICA forma de salir de ese estado — se avisa de una vez en
      // vez de dejar al usuario adivinando por qué "no pasó nada".
      debugPrint('openInstallSettings falló: $e');
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.install-failed'.i18n,
          content: 'upgrade.needs-install-permission'.i18n,
        );
      }
    }
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
    // Queda escrito qué camino se tomó.
    //
    // Reportado en vivo en televisor: «al darle actualizar, carga y luego se
    // queda en la misma pantalla, no redirige al instalador». Desde fuera,
    // «se abrió Ajustes de permisos» y «se lanzó el instalador y el sistema
    // no lo trajo al frente» se ven igual —la app sigue ahí— y llevan a
    // arreglos distintos. Con esto, el registro lo dice.
    logger.info('Actualización: APK listo en disco · permiso para instalar: '
        '${canInstall ? "sí" : "no"}');
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
    try {
      await platform.invokeMethod('installApk', {'apkPath': apkPath});
      logger.info('Actualización: se lanzó el instalador del sistema');
    } catch (e) {
      logger.warning('Actualización: el instalador del sistema no arrancó: $e');
      rethrow;
    }
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

  static Future<bool> _runWindowsInstaller(String installerPath) async {
    // Se ESPERA a que PowerShell termine de lanzar el instalador, y recien
    // despues nos vamos.
    //
    // Antes se dejaba corriendo un PowerShell que dormia tres segundos y luego
    // lanzaba el instalador, mientras esta app se cerraba de inmediato. Eso NO
    // funciona: el hijo pertenece al mismo grupo de procesos de Windows, asi
    // que al irse el padre se lo lleva puesto. Resultado medido en un equipo
    // real: el script quedaba en el disco SIN ejecutarse —ni siquiera llegaba a
    // borrarse solo, que es lo ultimo que hace— y para el usuario el app se
    // cerraba y no pasaba nada mas.
    //
    // Sin la espera de tres segundos tampoco hace falta: el instalador ya trae
    // CloseApplications=force, o sea que el mismo cierra el app si la encuentra
    // abierta, sin preguntar (ver inno_setup.iss).
    //
    // El proceso que abre Start-Process SI sobrevive, porque lo crea el propio
    // Windows por fuera de nuestro grupo. Comprobado con una prueba aparte
    // antes de escribir esto.
    final script = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'prismhub-update-${DateTime.now().millisecondsSinceEpoch}.ps1',
    );
    try {
      await script.writeAsString(
        // -Verb RunAs: el instalador pide permisos de administrador. Sin esto
        // Windows lo rechaza antes de arrancar.
        'Start-Process -FilePath ${_psQuote(installerPath)} -Verb RunAs\n',
      );
      final r = await Process.run(
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
      ).timeout(const Duration(seconds: 60));
      // Distinto de cero = no se lanzo. El caso normal es que el usuario haya
      // dicho que no en el aviso de permisos de Windows.
      if (r.exitCode != 0) {
        debugPrint('No se pudo lanzar el instalador '
            '(codigo ${r.exitCode}): ${r.stderr}');
        return false;
      }
    } catch (e, st) {
      debugPrint('No se pudo lanzar el instalador: $e / $st');
      return false;
    } finally {
      // El script ya cumplio: se limpia aca y no desde adentro de si mismo.
      try {
        if (script.existsSync()) script.deleteSync();
      } catch (_) {}
    }

    // Recien AHORA nos vamos, y solo si de verdad se lanzo. Antes se salia
    // pasara lo que pasara, asi que un fallo se veia igual que un exito: el
    // app se cerraba y listo.
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
    final isMobile = MediaQuery.sizeOf(context).width < 600;

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
                          side: BorderSide(color: HomeTheme.border)),
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
                                  Icon(Icons.system_update,
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
                                      style: TextStyle(
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
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 24, 32, 24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          FlutterI18n.translate(
                                            context,
                                            'upgrade.forced-required',
                                            translationParams: {
                                              'actual': packageInfo.version
                                            },
                                          ),
                                          style: TextStyle(
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
                                        onPressed:
                                            _ocupado ? null : _retryCheck,
                                        child: Text(
                                            'upgrade.already-updated'.i18n),
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
                  side: BorderSide(color: HomeTheme.border)),
              child: Container(
                constraints: BoxConstraints(
                  // Tope de ancho: en horizontal, con el telefono acostado, la
                  // tarjeta se estiraba de borde a borde y las lineas quedaban
                  // larguisimas e incomodas de leer.
                  maxWidth: 560,
                  // En horizontal el alto util es la mitad, asi que 0.8 dejaba
                  // el contenido apretado contra los bordes; se deja mas margen
                  // cuando la pantalla es baja.
                  maxHeight: MediaQuery.sizeOf(context).height *
                      (MediaQuery.orientationOf(context) ==
                              Orientation.landscape
                          ? 0.86
                          : 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DesplazableConMando(
                        controlador: _scrollMovil,
                        child: Scrollbar(
                          controller: _scrollMovil,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollMovil,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 24, 30, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.system_update,
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
                                    style: TextStyle(
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
                                    style:
                                        TextStyle(color: HomeTheme.textPrimary),
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
/// `_alVolver` devuelve si ya terminó (true, se desengancha) o si hay que
/// seguir esperando el próximo regreso (false) — un solo "resumed" no
/// alcanza para dar por hecho que el usuario ya volvió de verdad: en un
/// televisor, navegar la pantalla de permisos con el control remoto lleva
/// más de un ida y vuelta.
class _EsperaPermisoDeInstalacion with WidgetsBindingObserver {
  _EsperaPermisoDeInstalacion(this._alVolver);

  final Future<bool> Function() _alVolver;
  bool _terminado = false;
  // Evita superponer una segunda pasada mientras la anterior sigue
  // consultando el permiso, si el sistema manda "resumed" más de una vez
  // seguida (pasa en algunas transiciones de actividad).
  bool _procesando = false;

  void empezar() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_terminado || _procesando || state != AppLifecycleState.resumed) {
      return;
    }
    _procesando = true;
    unawaited(_alVolver().then((listo) {
      _procesando = false;
      if (listo) {
        _terminado = true;
        WidgetsBinding.instance.removeObserver(this);
      }
    }));
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
    final alto =
        Platform.isAndroid ? MediaQuery.sizeOf(context).height * 0.42 : 400.0;
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
  final cuerpo = TextStyle(
    color: HomeTheme.textPrimary,
    fontSize: 13.5,
    height: 1.5,
  );
  final titulo = TextStyle(
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
      border: Border(
        left: BorderSide(color: HomeTheme.accentPink, width: 3),
      ),
    ),
    code: TextStyle(
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
    horizontalRuleDecoration: BoxDecoration(
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
      decoration: BoxDecoration(
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
                    Icon(Icons.system_update,
                        size: 16, color: HomeTheme.accentPink),
                    const SizedBox(width: 10),
                    Text(
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
                      style: TextStyle(
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

/// Lo que se ve mientras se baja una actualización.
///
/// Una barra con lo que va descargado y los megas al lado, en vez de una rueda
/// girando sin principio ni fin. Con una actualización de decenas de megas y
/// una conexión lenta, esa rueda no decía si avanzaba, cuánto faltaba, ni si se
/// había colgado — y no había forma de saberlo desde afuera.
///
/// Es el mismo diálogo en PC y en Android, así que la barra sale en los dos.
class _BarraDeDescarga extends StatelessWidget {
  const _BarraDeDescarga({required this.progreso});

  /// `parte` es de 0 a 1, o null cuando el servidor no dijo cuánto pesa: ahí la
  /// barra va indeterminada pero los megas siguen subiendo, que ya es señal de
  /// que la descarga está viva.
  final ValueNotifier<({double? parte, String texto})> progreso;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<({double? parte, String texto})>(
      valueListenable: progreso,
      builder: (context, valor, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('upgrade.downloading'.i18n),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: valor.parte,
                minHeight: 6,
                backgroundColor: HomeTheme.accentPink.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation<Color>(HomeTheme.accentPink),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  valor.texto,
                  style: TextStyle(
                    fontSize: 12,
                    color: DefaultTextStyle.of(context)
                        .style
                        .color
                        ?.withValues(alpha: 0.7),
                  ),
                ),
                if (valor.parte != null)
                  Text(
                    '${(valor.parte! * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: HomeTheme.accentPink,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
