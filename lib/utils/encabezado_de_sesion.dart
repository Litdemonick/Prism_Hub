import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// La cabecera que abre cada sesión en el registro.
///
/// ── Para qué ────────────────────────────────────────────────────────────────
///
/// El registro se lee para entender un fallo, y casi siempre lo primero que hay
/// que preguntar es «¿en qué aparato pasó?». Un tirón en un televisor de 1 GB y
/// el mismo tirón en un PC son dos problemas distintos con la misma línea de
/// registro.
///
/// Antes eso había que preguntarlo aparte. Ahora abre cada sesión, así que el
/// archivo se explica solo — sobre todo cuando trae varias sesiones seguidas y
/// hay que saber dónde empieza cada una.
///
/// ── Qué NO lleva ────────────────────────────────────────────────────────────
///
/// Nada que identifique a la persona ni al aparato en concreto: ni el nombre
/// del equipo, ni número de serie, ni cuenta. Lo que sirve para diagnosticar es
/// la CLASE de aparato —televisor o no, cuánta memoria, qué sistema— y eso no
/// señala a nadie.
class EncabezadoDeSesion {
  EncabezadoDeSesion._();

  /// El aparato en una línea, para encabezar un reporte.
  ///
  /// Es el resumen corto: marca, modelo y sistema. La ficha completa —con la
  /// memoria, la pantalla y el resto— está en [fichaDelAparato].
  static String resumenDelAparato() {
    final partes = <String>[_dondeEstamos(), _marcaYModelo(), _sistema()]
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    return partes.join(' · ');
  }

  /// Todo lo que hace falta saber del aparato para entender un fallo.
  ///
  /// ── Por qué tan detallado ───────────────────────────────────────────────
  ///
  /// Pedido explícito: «así me entero en qué sistema está el usuario, sus
  /// recursos, qué marca de tele, modelo, etc.». Y es exactamente lo que
  /// separa un reporte útil de uno que no se puede usar: un tirón en un
  /// televisor de 1 GB y el mismo tirón en un PC de 32 son dos problemas
  /// distintos con la misma línea de registro, y sin esto hay que preguntarlo
  /// por mensaje y esperar.
  ///
  /// Va en varias líneas y no en una: en una sola quedaba un renglón larguísimo
  /// que en un teléfono se corta y en un reporte nadie lee entero.
  ///
  /// ── Y qué sigue sin llevar ──────────────────────────────────────────────
  ///
  /// Marca y modelo no señalan a nadie: los comparten millones de aparatos, y
  /// son justo lo que hace falta para reproducir un fallo. Lo que identifica a
  /// UNA persona sigue afuera y a propósito: el nombre que le puso al aparato
  /// —que suele llevar el nombre propio—, el número de serie, el identificador
  /// de publicidad y cualquier cuenta.
  static List<String> fichaDelAparato() => [
        for (final p in fichaEnPares())
          '${p.etiqueta.padRight(10)} ${p.valor}',
      ];

  /// La misma ficha, en pares, para poder dibujarla en una pantalla.
  ///
  /// El registro la quiere alineada en una columna de texto; la pantalla de
  /// PrismHub+ la quiere como etiqueta y valor por separado. Se arma una sola
  /// vez acá y cada uno la formatea a su manera, para que no puedan decir cosas
  /// distintas.
  static List<({String etiqueta, String valor})> fichaEnPares() {
    final ficha = <({String etiqueta, String valor})>[];
    void agregar(String etiqueta, String valor) {
      if (valor.trim().isEmpty) return;
      ficha.add((etiqueta: etiqueta, valor: valor));
    }

    agregar('sistema', _sistemaCompleto());
    agregar('aparato', [_dondeEstamos(), _marcaYModelo()]
        .where((p) => p.isNotEmpty)
        .join(' · '));
    agregar('memoria', _memoriaFisica());
    agregar('cpu', _procesador());
    agregar('perfil', _perfil());
    agregar('pantalla', _pantalla());
    agregar('idioma', Platform.localeName);
    return ficha;
  }

  /// Los ajustes que cambian cómo se comporta la app.
  ///
  /// ── Por qué hacen falta ─────────────────────────────────────────────────
  ///
  /// Dos personas con el mismo aparato y la misma versión pueden tener
  /// historias completamente distintas según cómo lo tengan configurado. Con
  /// un proxy puesto, TODA la red pasa por otro lado y un «no carga» no
  /// significa lo mismo. Con el bloqueador apagado, una página que se cae por
  /// un anuncio se cae solo para quien lo apagó.
  ///
  /// Sin esto, cada reporte arranca con tres preguntas de ida y vuelta. Solo
  /// van los que cambian el comportamiento — no la lista entera de ajustes,
  /// que sería ruido.
  static List<String> ajustesQueImportan() {
    final salida = <String>[];
    void agregar(String etiqueta, Object? valor) {
      final texto = valor?.toString() ?? '';
      if (texto.trim().isEmpty) return;
      salida.add('${etiqueta.padRight(10)} $texto');
    }

    try {
      agregar('proxy', PrismHubStorage.getSetting(SettingKey.proxyType));
      agregar(
        'reproductor',
        PrismHubStorage.getSetting(SettingKey.videoPlayer),
      );
      agregar('idioma-app', PrismHubStorage.getSetting(SettingKey.language));
      final apagadas =
          PrismHubStorage.getSetting(SettingKey.disabledExtensions);
      if (apagadas is List && apagadas.isNotEmpty) {
        agregar('apagadas', '${apagadas.length} extensiones');
      }
    } catch (_) {
      // El almacenamiento todavía no está listo: se sigue sin esta parte.
    }
    return salida;
  }

  /// Escribe la cabecera. Se llama una vez, cuando ya se sabe qué aparato es.
  ///
  /// Va la presentación primero y los datos del aparato después, para que
  /// quien abra esta pantalla sin saber qué es entienda antes de leer nada.
  static void escribir({required String version, bool forzar = false}) {
    // ── Una sola vez por arranque, pase lo que pase ─────────────────────
    //
    // El recuadro es lo que marca dónde empieza una sesión: el historial parte
    // el archivo justo ahí. Así que escribirlo dos veces no es un renglón
    // repetido — es una apertura de más en la lista, con las líneas de la
    // primera cortadas por la mitad.
    //
    // Y se escribía desde el `initState` de un widget, o sea que cualquier
    // cosa que vuelva a montar ese widget lo escribía de nuevo. Reportado en
    // vivo: «en el historial no se guarda correctamente, o está dividiendo en
    // varias opciones cuando debe ser una sola».
    //
    // [forzar] es para limpiar: ahí sí corresponde empezar una sesión nueva,
    // y es el único sitio que lo pide a propósito.
    if (_yaSeEscribio && !forzar) return;
    _yaSeEscribio = true;
    // Crudo y no `logger.info`: el recuadro es un dibujo, y el encabezado de
    // `logging` delante lo desalinea línea por línea. Ver PrismLog.crudo.
    for (final l in _presentacion(version)) {
      PrismLog.crudo(l);
    }
  }

  static bool _yaSeEscribio = false;
  static bool _yaEscribioExtensiones = false;

  /// Dónde se guarda con qué versión se abrió la última vez.
  static const _claveVersionAnterior = 'registro-version-anterior';

  /// Deja escrito si esta sesión es la primera después de actualizar.
  ///
  /// ── Por qué importa ─────────────────────────────────────────────────────
  ///
  /// Al actualizar, el registro empieza limpio solo porque se instala un APK
  /// nuevo y el proceso arranca de cero — pasa, pero por casualidad, y el
  /// archivo no lo decía en ningún lado. Quien recibe un registro veía la
  /// versión de la cabecera y nada más: no había forma de saber si ese
  /// arranque era el primero con la versión nueva, que es justo cuando
  /// aparecen los fallos de una actualización.
  ///
  /// Ahora la primera sesión después de actualizar lo dice, y con la versión
  /// de la que se venía. Un fallo que empieza exactamente ahí ya no hay que
  /// deducirlo comparando archivos.
  ///
  /// Se llama después de [escribir], para que quede justo debajo de la ficha.
  static Future<void> avisarSiSeActualizo(String version) async {
    try {
      final anterior = PrismHubStorage.getSetting(_claveVersionAnterior);
      if (anterior is String && anterior.isNotEmpty && anterior != version) {
        PrismLog.crudo('  ── PRIMERA VEZ CON LA VERSIÓN $version '
            '(se venía de la $anterior) ──');
        PrismLog.crudo('');
      }
      if (anterior != version) {
        await PrismHubStorage.setSetting(_claveVersionAnterior, version);
      }
    } catch (e) {
      // Un dato de menos no puede impedir que la app arranque.
      logger.info('No se pudo comparar la versión anterior: $e');
    }
  }

  /// Deja escritas las extensiones instaladas y con qué versión.
  ///
  /// ── Por qué en su propio momento ────────────────────────────────────────
  ///
  /// La mayoría de los reportes son «esta extensión no carga», y hasta ahora
  /// el registro no decía ni cuáles hay puestas ni en qué versión — así que
  /// no se podía distinguir un fallo de la app de una extensión vieja, que es
  /// la primera pregunta.
  ///
  /// No va en la cabecera porque cuando esa se escribe las extensiones
  /// todavía no se cargaron. Se llama aparte, cuando ya están, y por eso es
  /// un método propio y no parte de [escribir].
  static void escribirExtensiones(
    Iterable<({String paquete, String version, bool activa})> instaladas,
  ) {
    // Por el mismo motivo que la cabecera: si el arranque se repite, esta
    // lista salía dos veces y se leía como si hubiera el doble de extensiones.
    if (_yaEscribioExtensiones) return;
    _yaEscribioExtensiones = true;
    final lista = instaladas.toList(growable: false);
    if (lista.isEmpty) {
      PrismLog.crudo('  extensiones: ninguna instalada');
      return;
    }
    PrismLog.crudo('  ┌─ EXTENSIONES INSTALADAS (${lista.length})');
    for (final e in lista) {
      final estado = e.activa ? '' : '  (apagada)';
      PrismLog.crudo('  │  ${e.paquete} · v${e.version}$estado');
    }
    PrismLog.crudo('  └─');
    PrismLog.crudo('');
  }

  /// Lo primero que se ve al abrir el registro.
  ///
  /// ── Por qué está ────────────────────────────────────────────────────────
  ///
  /// Esta pantalla la abre gente que no programa. Sin nada que lo explique,
  /// lo que se ve son cientos de líneas técnicas con direcciones y nombres
  /// raros — y la lectura natural de eso es «la app está anotando lo que
  /// hago». Que es exactamente al revés de lo que pasa.
  ///
  /// Así que se dice de entrada qué es esto, para qué sirve y qué NO lleva. Y
  /// se dice acá, dentro del propio archivo, para que siga estando cuando el
  /// registro se exporta y lo abre otra persona en otro lado.
  static List<String> _presentacion(String version) {
    return [
      // El sistema va DENTRO del recuadro, junto al nombre.
      //
      // Estaba debajo, en la línea del resumen, mezclado con la versión del
      // sistema y el perfil — o sea que para saber de qué aparato salía un
      // registro había que leer una línea larga. Pedido explícito: «indicá en
      // el mensaje de PrismHub de la consola en qué sistema se abrió».
      //
      // Es lo primero que se pregunta al abrir un registro que te mandaron, y
      // ahora está en grande junto al nombre. El detalle completo sigue justo
      // abajo, para lo que haga falta afinar.
      ..._marco([..._nombre, 'abierto en ${_dondeEstamos()}']),
      '',
      '  PrismHub $version',
      // La ficha entera, una línea por dato. Ver fichaDelAparato.
      for (final l in fichaDelAparato()) '  $l',
      // Y cómo está configurada la app, que cambia lo que significa todo lo
      // demás. Ver ajustesQueImportan.
      for (final l in ajustesQueImportan()) '  $l',
      // Con fecha y hora completas, y no solo por dejar constancia: es lo que
      // deja que el historial ponga «Hoy 21:59» en cada apertura. Las líneas
      // del recuadro van crudas, sin el encabezado de `logging`, así que sin
      // esto una sesión que no llegara a registrar nada más se quedaría sin
      // ninguna hora que mostrar.
      '  abierto: ${_sinMicrosegundos(DateTime.now())}',
      '',
      ..._bloque('QUÉ ES ESTO', [
        'Acá se ve lo que hace la app por dentro: qué extensión',
        'respondió, qué servidor falló, cuánto tardó un vídeo en',
        'empezar. Sirve para encontrar fallos y mejorar la app.',
        '',
        'Si algo no te anda, podés exportar este registro y',
        'mandárselo a quien mantiene PrismHub. Con esto se puede',
        'arreglar de verdad, en vez de adivinar.',
      ]),
      ..._bloque('QUÉ NO LLEVA', [
        '· No lleva qué estuviste viendo.',
        '· No lleva contraseñas ni credenciales de ningún sitio.',
        '· No lleva tu nombre ni tu cuenta.',
        '· No lleva el nombre que le pusiste al aparato, ni su',
        '  número de serie, ni identificadores de publicidad.',
        '',
        'Arriba sí está la marca y el modelo. Eso lo comparten',
        'millones de aparatos, no señala a nadie, y es lo que',
        'permite reproducir un fallo que solo pasa en el tuyo.',
        '',
        'Las direcciones salen recortadas a propósito: se conserva',
        'el servidor y el formato, que es lo que sirve para',
        'arreglar, y se va todo lo demás.',
      ]),
      ..._bloque('Y NADA SE MANDA SOLO', [
        'Este archivo se queda en tu aparato. No se sube a ningún',
        'lado ni lo lee nadie salvo que vos decidas compartirlo.',
        '',
        'PrismHub está hecho para ser seguro con quien lo usa, y',
        'todo lo que hace está a la vista, empezando por esto.',
      ]),
      '  └────────────────────────────────────────────────────────────',
      '',
    ];
  }

  /// El nombre, dibujado con un solo carácter.
  ///
  /// ── Por qué solo con bloque lleno y espacios ────────────────────────────
  ///
  /// La versión anterior mezclaba el bloque lleno con esquinas de recuadro
  /// (╗ ╔ ╝) para redondear las letras. Se veía bien en un editor y mal en la
  /// app: son caracteres de familias distintas, y en cuanto la fuente
  /// monoespaciada del aparato no tiene alguno, el sistema lo saca de otra
  /// fuente con otro ancho — y ahí la letra se desarma. Reportado en vivo con
  /// foto en PC: «se corta el nombre de prism arriba».
  ///
  /// Con un solo carácter eso no puede pasar: o está y todo mide igual, o no
  /// está y todo mide igual de distinto, pero el dibujo se sostiene.
  static const _nombre = [
    '█████ █████  ███  █████ █   █',
    '█   █ █   █   █   █     ██ ██',
    '█████ █████   █   █████ █ █ █',
    '█     █  █    █       █ █   █',
    '█     █   █  ███  █████ █   █',
    '',
    'H U B  ·  registro de la aplicación',
  ];

  /// Encierra unas líneas en un recuadro, calculando el ancho.
  ///
  /// El ancho se mide acá y no se escribe a mano: un recuadro dibujado a mano
  /// en un literal se rompe con el primer carácter que alguien agregue o
  /// saque, y se rompe en silencio — nadie cuenta columnas al revisar un
  /// cambio. Midiéndolo, el recuadro cierra siempre.
  static List<String> _marco(List<String> dentro) {
    var ancho = 0;
    for (final l in dentro) {
      if (l.length > ancho) ancho = l.length;
    }
    final barra = '═' * (ancho + 4);
    return [
      '╔$barra╗',
      '║${' ' * (ancho + 4)}║',
      for (final l in dentro) '║  ${l.padRight(ancho)}  ║',
      '║${' ' * (ancho + 4)}║',
      '╚$barra╝',
    ];
  }

  /// Un apartado de texto, con su título.
  ///
  /// Sin borde derecho a propósito: el texto de adentro se puede tocar sin
  /// tener que volver a cuadrar nada, y una línea que se pase de largo no
  /// deja el recuadro abierto — que es la forma habitual en que estas cosas
  /// se ven rotas.
  static List<String> _bloque(String titulo, List<String> lineas) {
    final guiones = '─' * (58 - titulo.length - 4);
    return [
      '  ┌─ $titulo $guiones',
      '  │',
      for (final l in lineas) l.isEmpty ? '  │' : '  │  $l',
      '  │',
    ];
  }

  /// La fecha sin los microsegundos, que no le dicen nada a nadie.
  static String _sinMicrosegundos(DateTime cuando) {
    final s = cuando.toIso8601String().replaceFirst('T', ' ');
    final punto = s.indexOf('.');
    return punto < 0 ? s : s.substring(0, punto);
  }

  /// El nombre grande: es lo primero que se busca al abrir el archivo.
  static String _dondeEstamos() {
    if (PlatformTv.esTelevisionSync) return 'ANDROID TV';
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isWindows) return 'WINDOWS';
    if (Platform.isLinux) return 'LINUX';
    if (Platform.isMacOS) return 'MACOS';
    return 'DESCONOCIDO';
  }

  /// La versión del sistema en una línea corta.
  static String _sistema() {
    try {
      if (Platform.isAndroid) {
        return 'Android ${androidDeviceInfo.version.release}';
      }
      if (Platform.isWindows) {
        return windowsDeviceInfo.productName;
      }
      if (Platform.isLinux) {
        return linuxDeviceInfo.prettyName;
      }
      return Platform.operatingSystem;
    } catch (_) {
      // Todavía no se leyó la información del aparato, o esta plataforma no
      // la trae. Un dato de menos no puede impedir que se escriba el resto.
      return '';
    }
  }

  /// El sistema con todo lo que sirve: nombre, versión y compilación.
  ///
  /// «Windows 11 Pro (10.0.26200)» dice mucho más que «Windows»: una
  /// compilación concreta explica fallos que en otra no pasan.
  static String _sistemaCompleto() {
    try {
      if (Platform.isAndroid) {
        final v = androidDeviceInfo.version;
        return 'Android ${v.release} (API ${v.sdkInt}, ${v.incremental})';
      }
      if (Platform.isWindows) {
        final w = windowsDeviceInfo;
        return '${w.productName} '
            '(${w.majorVersion}.${w.minorVersion}.${w.buildNumber})';
      }
      if (Platform.isLinux) {
        final l = linuxDeviceInfo;
        return [l.prettyName, l.versionId].whereType<String>().join(' · ');
      }
    } catch (_) {
      // Se cae al de abajo.
    }
    return _recorte(Platform.operatingSystemVersion, 70);
  }

  /// Quién lo fabricó y qué modelo es.
  ///
  /// En Android es lo que dice si un fallo es de una caja concreta —los
  /// televisores baratos traen decodificadores muy distintos entre sí— y en
  /// escritorio no existe, así que ahí queda vacío y no se escribe.
  static String _marcaYModelo() {
    try {
      if (!Platform.isAndroid) return '';
      final a = androidDeviceInfo;
      final partes = <String>{a.manufacturer, a.brand}
          .where((p) => p.trim().isNotEmpty)
          .map(_conMayuscula)
          .toList();
      final marca = partes.join('/');
      return marca.isEmpty ? a.model : '$marca ${a.model}';
    } catch (_) {
      return '';
    }
  }

  /// Cuánta memoria tiene el aparato.
  ///
  /// Es la mitad de cualquier problema de rendimiento: la app se comporta muy
  /// distinto con 1 GB que con 8, y sin el dato no hay forma de saber si lo
  /// que se está mirando es un fallo o un aparato que no da más.
  static String _memoriaFisica() {
    try {
      if (Platform.isAndroid) {
        // device_info_plus no expone la RAM en Android, así que se lee de
        // /proc, que es de donde la saca el propio sistema.
        final linea = File('/proc/meminfo')
            .readAsLinesSync()
            .firstWhere((l) => l.startsWith('MemTotal'), orElse: () => '');
        final kb = int.tryParse(
          RegExp(r'(\d+)').firstMatch(linea)?.group(1) ?? '',
        );
        if (kb != null) return _enGigas(kb * 1024);
      }
      if (Platform.isWindows) {
        return _enGigas(windowsDeviceInfo.systemMemoryInMegabytes * 1024 * 1024);
      }
      if (Platform.isLinux) {
        final linea = File('/proc/meminfo')
            .readAsLinesSync()
            .firstWhere((l) => l.startsWith('MemTotal'), orElse: () => '');
        final kb = int.tryParse(
          RegExp(r'(\d+)').firstMatch(linea)?.group(1) ?? '',
        );
        if (kb != null) return _enGigas(kb * 1024);
      }
    } catch (_) {
      // Sin permiso de lectura o sin ese archivo: se sigue sin el dato.
    }
    return '';
  }

  static String _enGigas(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  /// El tamaño real de la pantalla y a cuántos puntos por pulgada dibuja.
  ///
  /// Explica una clase entera de fallos que solo se ven en un aparato: un
  /// texto que se corta o una tarjeta que no entra casi siempre son cuestión
  /// de cuántos píxeles lógicos hay, no del modelo.
  static String _pantalla() {
    try {
      final v = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
      if (v == null) return '';
      final t = v.physicalSize;
      final d = v.devicePixelRatio;
      if (t.isEmpty || d <= 0) return '';
      final ancho = (t.width / d).round();
      final alto = (t.height / d).round();
      // Los hercios: media docena de fallos del reproductor son de cuadros
      // que no encajan con el refresco de la pantalla, y sin este número no
      // se puede ni empezar a mirarlo. Ver FrecuenciaDePantalla.
      final hz = v.display.refreshRate;
      return '${t.width.round()}x${t.height.round()} '
          '· ${ancho}x$alto pt · x${d.toStringAsFixed(1)}'
          '${hz > 0 ? ' · ${hz.toStringAsFixed(0)} Hz' : ''}';
    } catch (_) {
      return '';
    }
  }

  /// Cuántos núcleos y de qué arquitectura.
  ///
  /// La arquitectura importa de verdad acá: mpv y los decodificadores traen
  /// binarios distintos por ABI, y un aparato que corre la app en 32 bits
  /// teniendo 64 —pasa en cajas de televisor mal armadas— se comporta
  /// distinto y no hay forma de saberlo si no está escrito.
  /// ── Lógicos y físicos, que no son lo mismo ─────────────────────────────
  ///
  /// `numberOfProcessors` devuelve los núcleos LÓGICOS: en un procesador con
  /// hilos por núcleo, ocho lógicos pueden ser cuatro físicos. Para decidir
  /// cuánto puede gastar la app importan los físicos —dos hilos del mismo
  /// núcleo no decodifican vídeo en paralelo— así que ver solo el número
  /// grande hacía parecer capaz a un aparato que no lo es.
  ///
  /// En Windows lo dice la información del sistema; en Linux y Android sale de
  /// contar los pares «id de núcleo + id de físico» distintos en
  /// `/proc/cpuinfo`, que es de donde lo saca cualquier herramienta del
  /// sistema. Si no se puede averiguar, se muestran solo los lógicos en vez de
  /// inventar un número.
  static String _procesador() {
    final logicos = Platform.numberOfProcessors;
    final fisicos = PerfilDeAparato.nucleosFisicos();
    final nucleos = (fisicos > 0 && fisicos != logicos)
        ? '$logicos núcleos ($fisicos físicos)'
        : '$logicos núcleos';
    try {
      if (!Platform.isAndroid) return nucleos;
      final a = androidDeviceInfo;
      final abi = a.supportedAbis.isEmpty ? '' : a.supportedAbis.first;
      final chip = a.hardware.isNotEmpty ? a.hardware : a.board;
      return [nucleos, abi, chip]
          .where((p) => p.trim().isNotEmpty)
          .join(' · ');
    } catch (_) {
      return nucleos;
    }
  }

  static String _perfil() {
    try {
      return PerfilDeAparato.nivel.name;
    } catch (_) {
      return '';
    }
  }

  static String _conMayuscula(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _recorte(String s, int tope) =>
      s.length > tope ? s.substring(0, tope) : s;

}
