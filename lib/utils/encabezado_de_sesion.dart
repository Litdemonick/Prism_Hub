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
    for (final l in _presentacion(version)) {
      logger.info(l);
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
    final aparato = resumenDelAparato();
    return [
      '╔══════════════════════════════════════════════════════════════╗',
      '║                                                              ║',
      '║      ██████╗ ██████╗ ██╗███████╗███╗   ███╗                  ║',
      '║      ██╔══██╗██╔══██╗██║██╔════╝████╗ ████║                  ║',
      '║      ██████╔╝██████╔╝██║███████╗██╔████╔██║   H U B          ║',
      '║      ██╔═══╝ ██╔══██╗██║╚════██║██║╚██╔╝██║                  ║',
      '║      ██║     ██║  ██║██║███████║██║ ╚═╝ ██║                  ║',
      '║      ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚═╝     ╚═╝                  ║',
      '║                                                              ║',
      '╚══════════════════════════════════════════════════════════════╝',
      '',
      '  ┌─ QUÉ ES ESTO ──────────────────────────────────────────────',
      '  │',
      '  │  Acá se ve lo que hace la app por dentro: qué extensión',
      '  │  respondió, qué servidor falló, cuánto tardó un vídeo en',
      '  │  empezar. Sirve para encontrar fallos y mejorar la app.',
      '  │',
      '  │  Si algo no te anda, podés exportar este registro y',
      '  │  mandárselo a quien mantiene PrismHub. Con esto se puede',
      '  │  arreglar de verdad, en vez de adivinar.',
      '  │',
      '  ├─ QUÉ NO LLEVA ─────────────────────────────────────────────',
      '  │',
      '  │  · No lleva qué estuviste viendo.',
      '  │  · No lleva contraseñas ni credenciales de ningún sitio.',
      '  │  · No lleva tu nombre, tu cuenta ni el nombre de tu equipo.',
      '  │',
      '  │  Las direcciones salen recortadas a propósito: se conserva',
      '  │  el servidor y el formato, que es lo que sirve para',
      '  │  arreglar, y se va todo lo demás.',
      '  │',
      '  ├─ Y NADA SE MANDA SOLO ─────────────────────────────────────',
      '  │',
      '  │  Este archivo se queda en tu aparato. No se sube a ningún',
      '  │  lado ni lo lee nadie salvo que vos decidas compartirlo.',
      '  │',
      '  │  PrismHub está hecho para ser seguro con quien lo usa, y',
      '  │  todo lo que hace está a la vista, empezando por esto.',
      '  │',
      '  └────────────────────────────────────────────────────────────',
      '',
      '═══ PrismHub $version · $aparato',
      '',
    ];
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
