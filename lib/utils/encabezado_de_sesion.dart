import 'dart:io';

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

  /// El aparato en una línea, sin la versión ni el adorno.
  ///
  /// La usa el exportador para encabezar el reporte. Va acá y no allá para que
  /// haya UN solo sitio que decida qué se cuenta del aparato — si mañana se
  /// suma o se saca un dato, no hay dos textos que se separen.
  static String resumenDelAparato() {
    final partes = <String>[_dondeEstamos(), _sistema()];
    final m = _memoria();
    if (m != null) partes.add(m);
    return partes.join(' · ');
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
      ..._marco(_nombre),
      '',
      '  PrismHub $version',
      '  ${resumenDelAparato()}',
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
        '· No lleva tu nombre, tu cuenta ni el nombre de tu equipo.',
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

  static String _sistema() {
    try {
      // La versión del sistema, sin el nombre del equipo: en Windows y en
      // Linux `operatingSystemVersion` a veces trae el nombre de la máquina, y
      // ese sí identifica.
      final crudo = Platform.operatingSystemVersion;
      return crudo.length > 60 ? crudo.substring(0, 60) : crudo;
    } catch (_) {
      return 'sistema desconocido';
    }
  }

  /// El perfil que la app le asignó al aparato y en qué se basó.
  ///
  /// Es la mitad de entender un problema de rendimiento: si un televisor quedó
  /// clasificado como capaz y va a tirones, puede que la clasificación esté
  /// mal, y eso solo se ve teniéndola escrita.
  static String? _memoria() {
    try {
      return 'perfil ${PerfilDeAparato.nivel.name} · '
          '${Platform.numberOfProcessors} núcleos';
    } catch (_) {
      return null;
    }
  }
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
