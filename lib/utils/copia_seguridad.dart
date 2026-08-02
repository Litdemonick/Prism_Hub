import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  static Future<String> exportar(
    String clave, {
    required String nombre,
    required int numero,
  }) async {
    if (clave.length < CopiaCifrado.largoMinimo) {
      throw CopiaInvalida(
        'La clave tiene que tener al menos '
        '${CopiaCifrado.largoMinimo} caracteres.',
      );
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
      // Con qué equipo se hizo y cuál copia es. Van en claro porque son
      // justamente lo que hay que poder leer ANTES de pedir la clave: sirven
      // para reconocer el archivo entre varios guardados en la misma carpeta.
      // No dicen nada de lo que el usuario vio.
      'nombre': limpiarNombre(nombre),
      'numero': numero,
      'cifrado': true,
      'sal': cerrado.sal,
      'nonce': cerrado.nonce,
      'datos': cerrado.datos,
    });
  }

  /// Lee lo de afuera del archivo, sin la clave.
  ///
  /// Sirve para mostrar de qué copia se trata antes de pedir nada: de qué
  /// equipo salió, cuál número es y de cuándo. Y para poder rechazar un archivo
  /// que no sirve sin hacer escribir una clave para nada.
  static SobreDeCopia leerSobre(String contenido) {
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
      throw const CopiaInvalida('Este archivo no es una copia de PrismHub.');
    }
    final version = sobre['formato'];
    if (version is! int) {
      throw const CopiaInvalida('El archivo no dice de qué versión es.');
    }
    if (version > formato) {
      throw const CopiaInvalida(
        'Este archivo lo hizo una versión más nueva de PrismHub. '
        'Actualizá la app para poder importarlo.',
      );
    }
    return SobreDeCopia(
      // Saneado también al LEER, no solo al escribir: el archivo puede haberlo
      // tocado cualquiera, y este texto se muestra en pantalla.
      nombre: limpiarNombre('${sobre['nombre'] ?? ''}'),
      numero: sobre['numero'] is int ? sobre['numero'] as int : 0,
      fecha: _fecha(sobre['fecha']),
      conClave: sobre['cifrado'] == true,
    );
  }

  /// Deja un nombre de copia en algo que se pueda mostrar y guardar.
  ///
  /// Lo escribe el usuario y después viaja dentro de un archivo que puede ir y
  /// venir entre equipos, así que al volver **no es texto de confianza**. Se
  /// quita todo lo que no sea texto visible y se le pone un techo.
  ///
  /// No hay riesgo de inyección de SQL —la base es Isar, que no arma consultas
  /// con texto— pero sí de cosas más tontas y más reales: caracteres de control
  /// que rompen el dibujo de la pantalla, saltos de línea que descuadran un
  /// diálogo, marcas de derecha-a-izquierda que dan vuelta lo que se lee, y un
  /// nombre de mil caracteres que se come la ventana.
  static String limpiarNombre(String crudo) {
    // Se filtra por CODIGO y no con una expresion regular a proposito: los
    // rangos que hay que quitar son caracteres invisibles, y escribirlos
    // dentro de un patron deja el propio archivo fuente con bytes de control
    // incrustados que no se ven al editarlo.
    final salida = StringBuffer();
    var espacioPendiente = false;
    for (final c in crudo.runes) {
      // Control (incluye saltos de linea y tabulador) y el borrado.
      final esControl = c < 0x20 || (c >= 0x7F && c <= 0x9F);
      // Invisibles que dan vuelta o esconden lo que se lee.
      final esInvisible = (c >= 0x200B && c <= 0x200F) ||
          (c >= 0x202A && c <= 0x202E) ||
          (c >= 0x2066 && c <= 0x2069) ||
          c == 0xFEFF;
      if (esInvisible) continue;
      if (esControl || c == 0x20) {
        espacioPendiente = salida.isNotEmpty;
        continue;
      }
      if (espacioPendiente) {
        salida.write(String.fromCharCode(0x20));
        espacioPendiente = false;
      }
      salida.writeCharCode(c);
    }
    var s = salida.toString();
    if (s.length > _largoDeNombre) {
      s = '${s.substring(0, _largoDeNombre).trim()}…';
    }
    return s;
  }

  /// Techo del nombre. Entra en una línea en un teléfono en vertical.
  static const _largoDeNombre = 40;

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
    String contenido,
    String clave, {
    /// De 0 a 1. Sirve para mover la barra: una copia grande son cientos de
    /// registros y cada uno toca la base, así que sin esto el usuario mira una
    /// pantalla quieta sin saber si avanza.
    void Function(double)? onProgreso,
  }) async {
    // Las mismas comprobaciones que ya hizo quien mostró de qué copia se trata.
    // Se repiten porque importar tiene que poder llamarse solo: fiarse de que
    // alguien validó antes es como no validar.
    final quienEs = leerSobre(contenido);
    final sobre = jsonDecode(contenido) as Map<String, dynamic>;

    // SOLO se aceptan copias cifradas. Sin excepciones.
    //
    // Antes había una rama que leía un archivo sin cifrar "por si alguna vez
    // existiera". Eso era un agujero: cualquiera podía escribir a mano un JSON
    // con {"app":"PrismHub","formato":1,"historial":[…]} y meterlo entero sin
    // saber ninguna clave. El cifrado es lo que hace que el contenido de una
    // copia solo pueda venir de alguien que tiene la clave del usuario; dejar
    // una puerta al lado lo anulaba.
    //
    // Esta versión no genera copias sin cifrar, así que no se rompe nada.
    if (sobre['cifrado'] != true) {
      throw const CopiaInvalida(
        'Este archivo no es una copia protegida de PrismHub. '
        'Solo se pueden importar copias hechas desde la app.',
      );
    }
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
      //
      // Y acá está la defensa de fondo: para que lo de adentro llegue siquiera
      // a leerse, el archivo tuvo que cerrarse con ESTA clave. Un archivo
      // preparado por otro no pasa de esta línea.
      throw const CopiaInvalida(
        'La clave no es la de este archivo, o el archivo está dañado.',
      );
    }
    final Object? dentro;
    try {
      dentro = jsonDecode(abierto);
    } on FormatException {
      throw const CopiaInvalida('La copia venía dañada por dentro.');
    }
    if (dentro is! Map<String, dynamic>) {
      throw const CopiaInvalida('La copia venía dañada por dentro.');
    }
    final raiz = dentro;

    var historialNuevo = 0;
    var historialActualizado = 0;
    var favoritosNuevos = 0;
    var fallidos = 0;

    // Cuantos hay en total, para poder decir por donde va.
    final losHistorial = _lista(raiz['historial']);
    final losFavoritos = _lista(raiz['favoritos']);
    final cuantos = losHistorial.length + losFavoritos.length;
    var hechos = 0;
    void avanzar() {
      hechos++;
      if (cuantos > 0) onProgreso?.call(hechos / cuantos);
    }

    for (final crudo in losHistorial) {
      try {
        final entra = _historialDeMapa(crudo);
        final previo = await DatabaseService.getHistoryByPackageAndUrl(
            entra.package, entra.url);
        if (previo == null) {
          await DatabaseService.putHistoryRaw(entra);
          historialNuevo++;
        } else if (!entra.date.isBefore(previo.date)) {
          // Gana el más reciente, y con la MISMA fecha gana el que entra.
          //
          // Antes se exigía que fuera estrictamente más nuevo, y eso hacía que
          // volver a importar el mismo archivo no hiciera absolutamente nada:
          // las fechas coincidían, todo se salteaba y el resultado era "0 del
          // historial y 0 favoritos". Volver a importar tiene que poder reparar
          // lo que haya quedado mal, no rendirse por un empate.
          await DatabaseService.putHistoryRaw(entra);
          historialActualizado++;
        }
      } catch (e) {
        fallidos++;
        logger.warning('Copia: no se pudo importar un ítem del historial', e);
      }
      avanzar();
    }

    for (final crudo in losFavoritos) {
      try {
        final entra = _favoritoDeMapa(crudo);
        final yaEsta = await DatabaseService.isFavorite(
            package: entra.package, url: entra.url);
        // Se escribe igual si ya estaba: putFavoriteRaw reusa el mismo
        // registro, así que no duplica, y permite reparar uno que hubiera
        // quedado mal. Solo se cuenta como nuevo si de verdad no estaba.
        await DatabaseService.putFavoriteRaw(entra);
        if (!yaEsta) favoritosNuevos++;
      } catch (e) {
        fallidos++;
        logger.warning('Copia: no se pudo importar un favorito', e);
      }
      avanzar();
    }

    // Las que hacen falta y no están puestas en este equipo.
    final instaladas = ExtensionUtils.runtimes.keys.toSet();
    final faltantes = <String>{
      for (final p in _lista(raiz['extensiones']))
        if (p is String && !instaladas.contains(p)) p,
    }.toList()
      ..sort();

    return ResultadoImportacion(
      deQuien: quienEs,
      historialNuevo: historialNuevo,
      historialActualizado: historialActualizado,
      favoritosNuevos: favoritosNuevos,
      fallidos: fallidos,
      extensionesFaltantes: faltantes,
    );
  }

  /// Cuántos registros se aceptan de cada lista.
  ///
  /// Un historial de verdad no llega ni de cerca. El techo está para que una
  /// copia con millones de entradas —hecha a mano, o dañada— no deje la app
  /// escribiendo en la base durante horas sin forma de cancelar.
  static const _techoDeRegistros = 50000;

  static List<dynamic> _lista(Object? valor) {
    if (valor is! List) return const [];
    if (valor.length > _techoDeRegistros) {
      return valor.sublist(0, _techoDeRegistros);
    }
    return valor;
  }

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
      ..package = _identificador(m['package'], 'package')
      ..url = _direccion(m['url'], 'url')
      ..cover = _portada(m['cover'])
      ..type = _tipo(m['type'])
      ..episodeGroupId = _entero(m['episodeGroupId'])
      ..episodeId = _entero(m['episodeId'])
      ..title = _texto(m['title'], 'title')
      ..episodeTitle = _textoSuelto(m['episodeTitle'])
      ..progress = _textoSuelto(m['progress'], techo: 20)
      ..totalProgress = _textoSuelto(m['totalProgress'], techo: 20)
      ..date = _fecha(m['date']) ?? DateTime.now()
      ..isNsfw = m['isNsfw'] == true
      ..watchState = WatchState.values.firstWhere(
        (e) => e.name == m['watchState'],
        orElse: () => WatchState.pending,
      )
      ..seriesFinished = m['seriesFinished'] == true
      ..knownEpisodeCount = _entero(m['knownEpisodeCount'])
      ..newEpisodeLabel = _opcional(_textoSuelto(m['newEpisodeLabel']))
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
      ..package = _identificador(m['package'], 'package')
      ..url = _direccion(m['url'], 'url')
      ..type = _tipo(m['type'])
      ..title = _texto(m['title'], 'title')
      ..cover = _portada(m['cover'])
      ..date = _fecha(m['date']) ?? DateTime.now()
      ..isNsfw = m['isNsfw'] == true;
  }

  /// Una portada.
  ///
  /// Se aceptan también las que vienen SIN esquema (`//cdn.sitio/x.jpg`), que
  /// es una forma normalísima de escribirlas en la web: el navegador les pone
  /// el mismo esquema de la página. Rechazarlas dejaba tarjetas sin imagen
  /// después de importar, que fue exactamente lo que pasó.
  ///
  /// Lo que sí se rechaza es un esquema que no sea de red —`javascript:`,
  /// `file:`, `data:`—: eso no es una imagen, es algo que alguien quiere que
  /// la app cargue.
  ///
  /// Una portada rota no vale perder el registro: se devuelve sin ella y la
  /// tarjeta usa la imagen por defecto, como cuando falta.
  static String? _portada(Object? valor) {
    if (valor is! String || valor.isEmpty) return null;
    final s = valor.trim();
    if (s.length > _techoDeDireccion) return null;
    if (_tieneInvisibles(s)) return null;
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    // Sin esquema: relativa o "//host/…". Vale.
    if (!uri.hasScheme) return s;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return s;
  }

  /// Techo de una dirección. De sobra para cualquier enlace real.
  static const _techoDeDireccion = 2048;

  /// Si el texto trae caracteres de control o invisibles.
  ///
  /// En un identificador no se limpian: se RECHAZA el registro. Limpiarlos
  /// cambiaría la dirección, y una dirección cambiada no lleva a ningún lado —
  /// justamente lo que pasaba al pasarles el limpiador de nombres.
  static bool _tieneInvisibles(String s) {
    for (final c in s.runes) {
      if (c < 0x20 || (c >= 0x7F && c <= 0x9F)) return true;
      if ((c >= 0x200B && c <= 0x200F) ||
          (c >= 0x202A && c <= 0x202E) ||
          (c >= 0x2066 && c <= 0x2069) ||
          c == 0xFEFF) {
        return true;
      }
    }
    return false;
  }

  /// Un identificador: se usa tal cual o no se usa.
  ///
  /// `package` y `url` son con lo que se reconoce un título. **No se limpian ni
  /// se recortan**: cualquier cambio los convierte en otro identificador, y ahí
  /// el registro deja de encontrar su contenido. Pasó de verdad — se les estaba
  /// aplicando el limpiador de NOMBRES, que corta a 40 caracteres, así que toda
  /// dirección larga quedaba truncada y la ficha abría en "Página no
  /// encontrada".
  ///
  /// Así que en vez de arreglarlos, se comprueban: si traen algo que no
  /// corresponde, se descarta ese registro y se sigue con el resto.
  @visibleForTesting
  static String direccionDePrueba(Object? valor) => _direccion(valor, 'url');

  @visibleForTesting
  static String? portadaDePrueba(Object? valor) => _portada(valor);

  static String _identificador(Object? valor, String campo) {
    if (valor is! String || valor.trim().isEmpty) {
      throw FormatException('falta "$campo"');
    }
    final s = valor.trim();
    if (s.length > _techoDeDireccion) {
      throw FormatException('"$campo" es demasiado largo');
    }
    if (_tieneInvisibles(s)) {
      throw FormatException('"$campo" trae caracteres que no corresponden');
    }
    return s;
  }

  /// Vacío pasa a null, que es lo que la base entiende por "no hay".
  static String? _opcional(String s) => s.isEmpty ? null : s;

  static Map<String, dynamic> _mapa(Object? crudo) {
    if (crudo is Map<String, dynamic>) return crudo;
    throw const FormatException('registro con forma inesperada');
  }

  /// Un texto que se MUESTRA: título, nombre del episodio.
  ///
  /// Acá sí se limpia y se recorta, porque el destino es la pantalla y lo que
  /// importa es que se vea bien. El techo es amplio: un título de anime largo
  /// es normal, y cortarlo a lo bruto se ve peor que dejarlo.
  static String _texto(Object? valor, String campo, {int techo = 300}) {
    if (valor is! String || valor.isEmpty) {
      throw FormatException('falta "$campo"');
    }
    final limpio = _paraMostrar(valor, techo);
    if (limpio.isEmpty) throw FormatException('"$campo" venía vacío');
    return limpio;
  }

  /// Lo mismo, pero cuando el campo puede faltar sin invalidar el registro.
  static String _textoSuelto(Object? valor, {int techo = 300}) {
    if (valor is! String || valor.isEmpty) return '';
    return _paraMostrar(valor, techo);
  }

  /// Quita lo invisible y recorta, sin puntos suspensivos.
  ///
  /// Aparte de [limpiarNombre], que es SOLO para el nombre de la copia y corta
  /// a 40 con «…». Confundir las dos fue lo que truncó las direcciones.
  static String _paraMostrar(String crudo, int techo) {
    final salida = StringBuffer();
    var espacioPendiente = false;
    for (final c in crudo.runes) {
      final esControl = c < 0x20 || (c >= 0x7F && c <= 0x9F);
      final esInvisible = (c >= 0x200B && c <= 0x200F) ||
          (c >= 0x202A && c <= 0x202E) ||
          (c >= 0x2066 && c <= 0x2069) ||
          c == 0xFEFF;
      if (esInvisible) continue;
      if (esControl || c == 0x20) {
        espacioPendiente = salida.isNotEmpty;
        continue;
      }
      if (espacioPendiente) {
        salida.write(' ');
        espacioPendiente = false;
      }
      salida.writeCharCode(c);
    }
    final s = salida.toString();
    return s.length > techo ? s.substring(0, techo) : s;
  }

  /// Una dirección que después se va a abrir.
  ///
  /// Se guarda TAL CUAL (ver [_identificador]) y solo se comprueba el esquema:
  /// sin esto, un archivo preparado a mano podría dejar en el historial una
  /// entrada con `javascript:` o `file:`, y esa dirección terminaría abriéndose
  /// sola al tocar la tarjeta.
  ///
  /// Se aceptan las que no traen esquema, que es como muchas extensiones
  /// guardan sus enlaces.
  static String _direccion(Object? valor, String campo) {
    final s = _identificador(valor, campo);
    final uri = Uri.tryParse(s);
    if (uri == null) throw FormatException('"$campo" no es una dirección');
    if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException('"$campo" usa un esquema que no se acepta');
    }
    return s;
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
    required this.deQuien,
    required this.historialNuevo,
    required this.historialActualizado,
    required this.favoritosNuevos,
    required this.fallidos,
    required this.extensionesFaltantes,
  });

  /// De qué copia salió todo esto, para poder decirlo al terminar.
  final SobreDeCopia deQuien;

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

/// Lo que se puede leer de una copia SIN la clave.
///
/// Sirve para reconocer el archivo antes de pedir nada: de qué equipo salió,
/// cuál número de copia es y de cuándo. Con tres archivos guardados en la misma
/// carpeta, es la única forma de saber cuál es el último sin abrirlos.
class SobreDeCopia {
  const SobreDeCopia({
    required this.nombre,
    required this.numero,
    required this.fecha,
    required this.conClave,
  });

  /// El nombre que le puso quien la creó. Ya saneado.
  final String nombre;

  /// Qué copia es de ese equipo: 1, 2, 3… 0 si el archivo no lo dice.
  final int numero;

  final DateTime? fecha;
  final bool conClave;

  /// Cómo se lee de un vistazo: "Mi celular · copia n.º 3".
  String get etiqueta {
    final partes = <String>[
      if (nombre.isNotEmpty) nombre,
      if (numero > 0) 'copia n.º $numero',
    ];
    return partes.isEmpty ? 'Copia de PrismHub' : partes.join(' · ');
  }
}
