import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:prismhub/utils/encabezado_de_sesion.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/zonas_del_registro.dart';
import 'package:share_plus/share_plus.dart';

/// Arma y entrega el archivo de registro para reportar un fallo.
///
/// ── Por qué no se manda el archivo tal cual ─────────────────────────────────
///
/// Antes se compartía `PrismHub.log` sin más. Eso son miles de líneas seguidas
/// donde todo está mezclado: lo del reproductor, lo de las extensiones y lo
/// general de la app, en el orden en que fueron pasando. Quien lo recibe tiene
/// que leerlo entero para encontrar lo que importa.
///
/// Acá se arma un archivo que se explica solo: primero un resumen de qué
/// aparato es y qué se encontró, y después las mismas líneas pero AGRUPADAS por
/// área, con su encabezado. Las de cada sección son las mismas que el visor
/// muestra con cada filtro, así que lo que se lee en pantalla y lo que se manda
/// son lo mismo.
///
/// ── Lo que NO lleva ─────────────────────────────────────────────────────────
///
/// Nada del usuario: el archivo ya viene saneado desde que se escribe (ver
/// [PrismLog.sanear]) — sin credenciales, sin qué se estaba viendo y sin el
/// nombre de usuario del sistema. Acá no hace falta volver a limpiarlo, pero sí
/// hace falta no agregar nada nuevo.
class ExportarRegistro {
  ExportarRegistro._();

  /// Las áreas del archivo, en el orden en que conviene leerlas.
  ///
  /// Los fallos primero: es lo que se busca. Lo general al final, que es el
  /// contexto de todo lo demás.
  ///
  /// Qué entra en cada una lo decide [ZonaDelRegistro], que es lo mismo que
  /// usa el visor: si acá hubiera una lista propia, «Fallos» significaría una
  /// cosa mirando la pantalla y otra abriendo el archivo exportado.
  static final _secciones = <(String, bool Function(String))>[
    (ZonaDelRegistro.fallos.seccion, ZonaDelRegistro.fallos.acepta),
    (ZonaDelRegistro.reproductor.seccion, ZonaDelRegistro.reproductor.acepta),
    (ZonaDelRegistro.extensiones.seccion, ZonaDelRegistro.extensiones.acepta),
    ('GENERAL DE LA APP', esGeneral),
  ];

  /// Arma el texto completo, ya ordenado por secciones.
  ///
  /// Con [soloArea] se arma solo esa —la que el usuario tenga elegida en el
  /// visor— para que lo que se lee desde otro aparato coincida con lo que se
  /// está mirando en la pantalla del televisor. Sin ella, van todas.
  ///
  /// Con [lineas] se arma sobre esas y no sobre el archivo entero — es como
  /// se exporta o se sirve una sesión anterior concreta, ya recortada por
  /// quien la eligió.
  static Future<String> armar({String? soloArea, List<String>? lineas}) async {
    await PrismLog.flush();
    lineas ??= await _leerTodo();

    final salida = StringBuffer()
      ..writeln('═══════════════════════════════════════════════════')
      ..writeln('  REGISTRO DE PRISMHUB')
      ..writeln('  ${DateTime.now().toIso8601String()}')
      ..writeln('═══════════════════════════════════════════════════');
    // La ficha entera del aparato y no una línea de resumen.
    //
    // Es lo primero que hay que saber al recibir un reporte, y preguntarlo
    // por mensaje cuesta un día de ida y vuelta. Marca, modelo, memoria y
    // pantalla son lo que separa «esto es un fallo» de «este aparato no da
    // más». Ver EncabezadoDeSesion.fichaDelAparato, que además explica qué se
    // deja afuera a propósito.
    for (final l in EncabezadoDeSesion.fichaDelAparato()) {
      salida.writeln('  $l');
    }
    salida
      ..writeln('═══════════════════════════════════════════════════')
      ..writeln();

    // Un resumen antes de las líneas: quien abre esto quiere saber en diez
    // segundos si hay algo roto, no leer dos mil líneas para averiguarlo.
    final fallos = lineas.where(ZonaDelRegistro.fallos.acepta).length;
    salida
      ..writeln('RESUMEN')
      ..writeln('  líneas en total: ${lineas.length}')
      ..writeln('  fallos y avisos: $fallos');
    final cierre =
        lineas.where((l) => l.contains('no se cerro normalmente')).length;
    if (cierre > 0) {
      salida.writeln('  ⚠ la app se cerró sola $cierre vez/veces');
    }
    salida.writeln();

    for (final (titulo, entra) in _secciones) {
      if (soloArea != null && titulo != soloArea) continue;
      final delArea = lineas.where(entra).toList(growable: false);
      salida
        ..writeln('───────────────────────────────────────────────────')
        ..writeln('  $titulo  (${delArea.length})')
        ..writeln('───────────────────────────────────────────────────');
      if (delArea.isEmpty) {
        salida.writeln('  (nada)');
      } else {
        for (final l in delArea) {
          salida.writeln(l);
        }
      }
      salida.writeln();
    }
    return salida.toString();
  }

  /// El archivo si existe, y lo que haya en memoria si no.
  ///
  /// Los dos no se suman: lo que está en memoria ya se escribió al archivo por
  /// el volcado de arriba, así que juntarlos duplicaría el final.
  static Future<List<String>> _leerTodo() async {
    try {
      final f = File(PrismLog.logFilePath);
      if (await f.exists()) {
        final texto = await f.readAsString();
        return texto
            .split(RegExp(r'\r?\n'))
            .where((l) => l.trim().isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // Sin permiso o a medio escribir: se sigue con lo de memoria.
    }
    return PrismLog.enMemoria;
  }

  /// Entrega el archivo por donde corresponda en este aparato.
  ///
  /// En teléfono, por el menú de compartir. En escritorio, eligiendo dónde
  /// guardarlo. Devuelve false si la persona canceló.
  ///
  /// Con [soloArea] sale solo la zona que se está mirando en el visor: quien
  /// exporta desde el filtro de fallos quiere mandar los fallos, no dos mil
  /// líneas más de las que ya decidió que no le interesaban.
  ///
  /// Con [lineas] se exporta ese juego concreto —una apertura anterior
  /// elegida en el historial— en vez del archivo entero.
  /// Cómo se llama el archivo que sale.
  ///
  /// ── Por qué lleva la zona y la fecha ────────────────────────────────────
  ///
  /// Salían todos como `PrismHub-reporte.log`. Con dos exportados la carpeta
  /// ya tenía `PrismHub-reporte(1).log` y no había forma de saber cuál era
  /// cuál —ni de qué zona, ni de cuándo— sin abrirlos. Y quien los recibe,
  /// menos.
  ///
  /// Ahora el nombre lo dice: `PrismHub-fallos-2026-08-29-2319.log`. La fecha
  /// va al revés (año primero) para que ordenados por nombre queden también en
  /// orden de tiempo.
  static String nombreDeArchivo(String etiqueta) {
    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    final cuando = '${ahora.year}-${dos(ahora.month)}-${dos(ahora.day)}'
        '-${dos(ahora.hour)}${dos(ahora.minute)}';
    return 'PrismHub-$etiqueta-$cuando.log';
  }

  static Future<bool> entregar({
    String? soloArea,
    List<String>? lineas,
    String etiqueta = 'todo',
  }) async {
    final texto = await armar(soloArea: soloArea, lineas: lineas);
    final nombre = nombreDeArchivo(etiqueta);
    final destino =
        File('${File(PrismLog.logFilePath).parent.path}/$nombre');
    await destino.writeAsString(texto, flush: true);

    if (Platform.isAndroid || Platform.isIOS) {
      await Share.shareXFiles([XFile(destino.path)]);
      return true;
    }
    final elegido = await FilePicker.platform.saveFile(
      type: FileType.custom,
      allowedExtensions: ['log'],
      fileName: nombre,
    );
    if (elegido == null) return false;
    await destino.copy(elegido);
    return true;
  }
}
