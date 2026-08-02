import 'dart:convert';

import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/copia_cifrado.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/log.dart';

/// Guardar y recuperar lo que el usuario construyó: su historial y su lista.
///
/// Todo eso vive en la base de datos del teléfono o de la PC, y hasta ahora no
/// había forma de sacarlo de ahí: cambiar de equipo, reinstalar o formatear
/// significaba empezar de cero. Esto lo deja en **un archivo de texto** que se
/// puede guardar donde sea y volver a meter después.
///
/// Es texto plano a propósito y no una copia de la base: así el archivo sirve
/// igual entre Windows, Linux y Android, que guardan la base de formas
/// distintas, y sigue sirviendo aunque la base cambie de forma más adelante.
class CopiaSeguridad {
  /// Versión del formato del archivo.
  ///
  /// Sube solo si un archivo nuevo deja de poder leerse con la app vieja. Se
  /// comprueba al importar para poder decir "este archivo es de una versión más
  /// nueva" en vez de leerlo a medias y dejar los datos a mitad de camino.
  static const formato = 1;

  /// Arma el archivo con todo lo que hay guardado.
  ///
  /// Van los dos lados juntos —el normal y el +18—, que es lo que hace que al
  /// recuperar quede todo como estaba. Cada registro lleva su marca de si es
  /// +18, así que al volver cada cosa cae donde iba.
  static Future<String> exportar(String clave) async {
    if (clave.isEmpty) {
      throw const CopiaInvalida('Poné una clave para proteger la copia.');
    }
    final historial = await DatabaseService.getHistorysByType();
    final favoritos = await DatabaseService.getFavoritesByType();

    final dentro = jsonEncode({
      // Para poder avisar cuáles faltan al importar en otro equipo: sin la
      // extensión instalada, su historial se ve pero no se puede abrir.
      'extensiones': ExtensionUtils.runtimes.keys.toList()..sort(),
      'historial': historial.map(_historialAMapa).toList(),
      'favoritos': favoritos.map(_favoritoAMapa).toList(),
    });
    final cerrado = CopiaCifrado.cerrar(dentro, clave);

    // Lo de afuera va en claro a propósito: es lo que permite decir "esto no es
    // una copia de PrismHub" o "es de una versión más nueva" ANTES de pedir la
    // clave, en vez de hacer escribirla para después fallar por otra cosa. Nada
    // de esto dice qué vio el usuario.
    return const JsonEncoder.withIndent('  ').convert({
      'formato': formato,
      'app': 'PrismHub',
      'fecha': DateTime.now().toIso8601String(),
      'cifrado': true,
      'sal': cerrado.sal,
      'nonce': cerrado.nonce,
      'datos': cerrado.datos,
    });
  }

  /// Mete de vuelta lo que traiga el archivo, SIN borrar lo que ya hay.
  ///
  /// Se junta con lo existente en vez de reemplazarlo, que es lo único seguro:
  /// importar en un equipo que ya se venía usando no puede costarle al usuario
  /// lo que vio ahí. Cuando un mismo título está en los dos lados gana **el más
  /// reciente**, comparando la fecha.
  ///
  /// Un registro roto no corta la importación: se cuenta como fallido y se
  /// sigue con el resto. Un archivo a medio leer sería peor que uno incompleto.
  static Future<ResultadoImportacion> importar(
      String contenido, String clave) async {
    final Map<String, dynamic> sobre;
    try {
      final leido = jsonDecode(contenido);
      if (leido is! Map<String, dynamic>) {
        throw const FormatException('el archivo no tiene la forma esperada');
      }
      sobre = leido;
    } on FormatException catch (e) {
      throw CopiaInvalida('No se pudo leer el archivo: ${e.message}');
    }

    if (sobre['app'] != 'PrismHub') {
      throw CopiaInvalida('Este archivo no es una copia de PrismHub.');
    }
    final version = sobre['formato'];
    if (version is! int) {
      throw CopiaInvalida('El archivo no dice de qué versión es.');
    }
    if (version > formato) {
      throw CopiaInvalida(
        'Este archivo lo hizo una versión más nueva de PrismHub. '
        'Actualizá la app para poder importarlo.',
      );
    }

    // Se abre con la clave. Todo lo de arriba se comprobó primero, para no
    // hacer escribir la clave y después fallar por otro motivo.
    final Map<String, dynamic> raiz;
    if (sobre['cifrado'] == true) {
      if (clave.isEmpty) {
        throw const CopiaInvalida('Esta copia tiene clave. Escribila.');
      }
      final abierto = CopiaCifrado.abrir(
        sal: '${sobre['sal']}',
        nonce: '${sobre['nonce']}',
        datos: '${sobre['datos']}',
        clave: clave,
      );
      if (abierto == null) {
        // No se distingue "clave equivocada" de "archivo dañado" a propósito:
        // no hay forma de saberlo sin arriesgarse a usar datos que no son.
        throw const CopiaInvalida(
          'La clave no es la de este archivo, o el archivo está dañado.',
        );
      }
      final dentro = jsonDecode(abierto);
      if (dentro is! Map<String, dynamic>) {
        throw const CopiaInvalida('La copia venía dañada por dentro.');
      }
      raiz = dentro;
    } else {
      // Copias sin clave: no las genera esta versión, pero si alguna vez
      // existieran, leerlas igual es mejor que rechazarlas.
      raiz = sobre;
    }

    var historialNuevo = 0;
    var historialActualizado = 0;
    var favoritosNuevos = 0;
    var fallidos = 0;

    for (final crudo in _lista(raiz['historial'])) {
      try {
        final entra = _historialDeMapa(crudo);
        final previo = await DatabaseService.getHistoryByPackageAndUrl(
            entra.package, entra.url);
        if (previo == null) {
          await DatabaseService.putHistoryRaw(entra);
          historialNuevo++;
        } else if (entra.date.isAfter(previo.date)) {
          // Gana el más reciente: el equipo donde se vio después es el que
          // tiene el progreso bueno.
          await DatabaseService.putHistoryRaw(entra);
          historialActualizado++;
        }
      } catch (e) {
        fallidos++;
        logger.warning('Copia: no se pudo importar un ítem del historial', e);
      }
    }

    for (final crudo in _lista(raiz['favoritos'])) {
      try {
        final entra = _favoritoDeMapa(crudo);
        final yaEsta = await DatabaseService.isFavorite(
            package: entra.package, url: entra.url);
        if (yaEsta) continue;
        await DatabaseService.putFavoriteRaw(entra);
        favoritosNuevos++;
      } catch (e) {
        fallidos++;
        logger.warning('Copia: no se pudo importar un favorito', e);
      }
    }

    // Las que hacen falta y no están puestas en este equipo.
    final instaladas = ExtensionUtils.runtimes.keys.toSet();
    final faltantes = <String>{
      for (final p in _lista(raiz['extensiones']))
        if (p is String && !instaladas.contains(p)) p,
    }.toList()
      ..sort();

    return ResultadoImportacion(
      historialNuevo: historialNuevo,
      historialActualizado: historialActualizado,
      favoritosNuevos: favoritosNuevos,
      fallidos: fallidos,
      extensionesFaltantes: faltantes,
    );
  }

  static List<dynamic> _lista(Object? valor) =>
      valor is List ? valor : const [];

  static Map<String, dynamic> _historialAMapa(History h) => {
        'package': h.package,
        'url': h.url,
        'cover': h.cover,
        'type': h.type.name,
        'episodeGroupId': h.episodeGroupId,
        'episodeId': h.episodeId,
        'title': h.title,
        'episodeTitle': h.episodeTitle,
        'progress': h.progress,
        'totalProgress': h.totalProgress,
        'date': h.date.toIso8601String(),
        'isNsfw': h.isNsfw,
        'watchState': h.watchState.name,
        'seriesFinished': h.seriesFinished,
        'knownEpisodeCount': h.knownEpisodeCount,
        'newEpisodeLabel': h.newEpisodeLabel,
        'lastCheckedAt': h.lastCheckedAt?.toIso8601String(),
      };

  static History _historialDeMapa(Object? crudo) {
    final m = _mapa(crudo);
    return History()
      ..package = _texto(m['package'], 'package')
      ..url = _texto(m['url'], 'url')
      ..cover = m['cover'] as String?
      ..type = _tipo(m['type'])
      ..episodeGroupId = _entero(m['episodeGroupId'])
      ..episodeId = _entero(m['episodeId'])
      ..title = _texto(m['title'], 'title')
      ..episodeTitle = '${m['episodeTitle'] ?? ''}'
      ..progress = '${m['progress'] ?? ''}'
      ..totalProgress = '${m['totalProgress'] ?? ''}'
      ..date = _fecha(m['date']) ?? DateTime.now()
      ..isNsfw = m['isNsfw'] == true
      ..watchState = WatchState.values.firstWhere(
        (e) => e.name == m['watchState'],
        orElse: () => WatchState.pending,
      )
      ..seriesFinished = m['seriesFinished'] == true
      ..knownEpisodeCount = _entero(m['knownEpisodeCount'])
      ..newEpisodeLabel = m['newEpisodeLabel'] as String?
      ..lastCheckedAt = _fecha(m['lastCheckedAt']);
  }

  static Map<String, dynamic> _favoritoAMapa(Favorite f) => {
        'package': f.package,
        'url': f.url,
        'type': f.type.name,
        'title': f.title,
        'cover': f.cover,
        'date': f.date.toIso8601String(),
        'isNsfw': f.isNsfw,
      };

  static Favorite _favoritoDeMapa(Object? crudo) {
    final m = _mapa(crudo);
    return Favorite()
      ..package = _texto(m['package'], 'package')
      ..url = _texto(m['url'], 'url')
      ..type = _tipo(m['type'])
      ..title = _texto(m['title'], 'title')
      ..cover = m['cover'] as String?
      ..date = _fecha(m['date']) ?? DateTime.now()
      ..isNsfw = m['isNsfw'] == true;
  }

  static Map<String, dynamic> _mapa(Object? crudo) {
    if (crudo is Map<String, dynamic>) return crudo;
    throw const FormatException('registro con forma inesperada');
  }

  /// Los campos sin los que el registro no sirve para nada.
  ///
  /// package y url son con lo que se identifica un título: sin ellos no se
  /// puede ni comparar contra lo que ya hay ni volver a abrirlo.
  static String _texto(Object? valor, String campo) {
    if (valor is String && valor.isNotEmpty) return valor;
    throw FormatException('falta "$campo"');
  }

  static int _entero(Object? valor) =>
      valor is int ? valor : int.tryParse('$valor') ?? 0;

  static DateTime? _fecha(Object? valor) =>
      valor is String ? DateTime.tryParse(valor) : null;

  /// Un tipo desconocido no rompe: cae en el primero.
  ///
  /// Pasa si el archivo lo hizo una app que ya maneja un tipo de contenido que
  /// esta todavía no conoce. Perder el tipo exacto es mucho mejor que perder
  /// el registro entero.
  static ExtensionType _tipo(Object? valor) => ExtensionType.values.firstWhere(
        (e) => e.name == valor,
        orElse: () => ExtensionType.values.first,
      );
}

/// El archivo no se puede usar, y por qué.
///
/// Se distingue de un fallo cualquiera para poder decirle al usuario algo que
/// signifique algo —"esto no es una copia de PrismHub"— en vez de volcarle una
/// excepción en pantalla.
class CopiaInvalida implements Exception {
  const CopiaInvalida(this.motivo);
  final String motivo;
  @override
  String toString() => motivo;
}

/// Qué entró de verdad al importar.
class ResultadoImportacion {
  const ResultadoImportacion({
    required this.historialNuevo,
    required this.historialActualizado,
    required this.favoritosNuevos,
    required this.fallidos,
    required this.extensionesFaltantes,
  });

  final int historialNuevo;
  final int historialActualizado;
  final int favoritosNuevos;

  /// Registros que venían rotos y se saltearon.
  final int fallidos;

  /// Extensiones que el archivo usaba y no están puestas en este equipo.
  ///
  /// Su historial se importa igual —para no perderlo si después las instala—
  /// pero hasta entonces no se va a poder abrir, y eso hay que decirlo.
  final List<String> extensionesFaltantes;

  int get total => historialNuevo + historialActualizado + favoritosNuevos;
}
