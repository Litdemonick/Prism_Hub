import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/utils/log.dart';
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
  static List<String> fichaDelAparato() {
    final ficha = <String>[];
    void agregar(String etiqueta, String valor) {
      if (valor.trim().isEmpty) return;
      ficha.add('${etiqueta.padRight(10)} $valor');
    }

    agregar('sistema', _sistemaCompleto());
    agregar('aparato', [_dondeEstamos(), _marcaYModelo()]
        .where((p) => p.isNotEmpty)
        .join(' · '));
    agregar('memoria', _memoriaFisica());
    agregar('cpu', '${Platform.numberOfProcessors} núcleos');
    agregar('perfil', _perfil());
    agregar('pantalla', _pantalla());
    agregar('idioma', Platform.localeName);
    return ficha;
  }

  /// Escribe la cabecera. Se llama una vez, cuando ya se sabe qué aparato es.
  ///
  /// Va la presentación primero y los datos del aparato después, para que
  /// quien abra esta pantalla sin saber qué es entienda antes de leer nada.
  static void escribir({required String version}) {
    // Crudo y no `logger.info`: el recuadro es un dibujo, y el encabezado de
    // `logging` delante lo desalinea línea por línea. Ver PrismLog.crudo.
    for (final l in _presentacion(version)) {
      PrismLog.crudo(l);
    }
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
      return '${t.width.round()}x${t.height.round()} '
          '· ${ancho}x$alto pt · x${d.toStringAsFixed(1)}';
    } catch (_) {
      return '';
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

/// Si esta línea es parte del recuadro de presentación.
///
/// Vive acá, junto al sitio que dibuja el recuadro, para que no haya dos
/// ideas distintas de qué cuenta como recuadro. Si mañana cambia el dibujo,
/// cambia en un solo archivo.
bool esElRecuadro(String linea) {
  for (final c in _caracteresDelRecuadro) {
    if (linea.contains(c)) return true;
  }
  return false;
}

/// Los caracteres con los que está dibujado. Ninguno lo escribe otra cosa de
/// la app: son de dibujo de cajas, no de texto.
const _caracteresDelRecuadro = ['╔', '╚', '║', '╗', '╝', '┌', '└', '├', '│'];

/// Junta las líneas seguidas del recuadro en una sola.
///
/// El recuadro es un dibujo, no texto: solo se entiende con todas sus líneas
/// alineadas entre sí. Mostrado línea por línea, cada una se ajusta al ancho
/// por su cuenta y en cuanto una no entra se parte en dos — que es como se
/// rompía en pantalla.
///
/// Juntándolas, quien lo dibuja puede tratarlo como un bloque: achicarlo
/// entero hasta que entre, sin que las líneas se desalineen entre sí.
///
/// El resto de las líneas pasan tal cual, una por una, porque son texto de
/// verdad y ahí ajustar al ancho es lo correcto.
List<String> agruparElRecuadro(List<String> lineas) {
  if (lineas.isEmpty) return lineas;
  var hayAlguno = false;
  for (final l in lineas) {
    if (esElRecuadro(l)) {
      hayAlguno = true;
      break;
    }
  }
  // Sin recuadro no se copia nada: es el caso de casi todos los refrescos, y
  // recorrer miles de líneas para no cambiar ninguna sería trabajo tirado.
  if (!hayAlguno) return lineas;

  final salida = <String>[];
  final bloque = <String>[];
  void cerrarBloque() {
    if (bloque.isEmpty) return;
    salida.add(bloque.join('\n'));
    bloque.clear();
  }

  for (final l in lineas) {
    if (esElRecuadro(l)) {
      bloque.add(l);
    } else {
      cerrarBloque();
      salida.add(l);
    }
  }
  cerrarBloque();
  return salida;
}
