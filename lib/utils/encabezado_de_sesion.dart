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

  /// Escribe la cabecera. Se llama una vez, cuando ya se sabe qué aparato es.
  static void escribir({required String version}) {
    final linea = StringBuffer()
      ..write('═══ PrismHub $version · ')
      ..write(_dondeEstamos())
      ..write(' · ')
      ..write(_sistema());
    final memoria = _memoria();
    if (memoria != null) linea.write(' · $memoria');
    logger.info(linea.toString());
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
