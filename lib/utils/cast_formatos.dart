import 'dart:io';

import 'package:dlna_dart/dlna.dart';
import 'package:prismhub/utils/log.dart';

/// Qué formatos acepta un televisor DLNA, preguntándoselo a él.
///
/// Todo aparato DLNA publica esa lista con `GetProtocolInfo`. Consultarla antes
/// de mandar nada es la diferencia entre transmitir y dejar la pantalla en
/// negro, porque un aparato que no puede con el formato **acepta igual la
/// orden**: contesta que sí, muestra el título que le mandamos en la ficha, y
/// no dibuja nunca nada. Desde afuera se ve idéntico a que funcione.
///
/// Medido en la red del usuario, esta es exactamente la diferencia entre el
/// aparato que anda y el que no:
///
/// - Kodi en la PC publica **94** formatos, `mpegurl` incluido → reproduce.
/// - El televisor publica **29**, y ni uno solo es HLS → pantalla negra.
///
/// HLS es de 2009 y DLNA es anterior; nunca lo incorporó. Como las extensiones
/// de vídeo sirven casi todo en HLS, el caso normal en un televisor es el malo.
class FormatosDelAparato {
  /// Lo ya preguntado, por aparato.
  ///
  /// Se consulta al elegir el aparato y otra vez en cada episodio; la respuesta
  /// no cambia mientras el televisor siga siendo el mismo.
  static final Map<String, Set<String>> _cache = {};

  static final HttpClient _cliente = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  /// Los tipos que el aparato dice aceptar, en minúscula (`video/mp4`, …).
  ///
  /// Vacío si no se pudo preguntar. Ojo con eso: vacío significa **no sé**, no
  /// "no acepta nada", y por eso [aceptaHls] contesta que sí ante un vacío.
  static Future<Set<String>> de(DLNADevice device) async {
    final clave = device.info.URLBase;
    final guardado = _cache[clave];
    if (guardado != null) return guardado;

    final control = _controlDeConnectionManager(device);
    if (control == null) return const {};

    try {
      final req = await _cliente.postUrl(control);
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set(
        'SOAPAction',
        '"urn:schemas-upnp-org:service:ConnectionManager:1#GetProtocolInfo"',
      );
      req.write(
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:GetProtocolInfo xmlns:u="urn:schemas-upnp-org:service:'
        'ConnectionManager:1"/></s:Body></s:Envelope>',
      );
      final res = await req.close().timeout(const Duration(seconds: 8));
      final cuerpo = await res.transform(const SystemEncoding().decoder).join();

      // <Sink> trae la lista separada por comas, cada entrada con la forma
      // "http-get:*:video/mp4:*". Nos quedamos con el tipo del medio.
      final tipos = <String>{};
      for (final entrada in (_entre(cuerpo, 'Sink') ?? '').split(',')) {
        final partes = entrada.trim().split(':');
        if (partes.length >= 3 && partes[2].isNotEmpty) {
          tipos.add(partes[2].toLowerCase());
        }
      }
      if (tipos.isEmpty) return const {};
      _cache[clave] = tipos;
      logger.info(
          'El aparato ${device.info.friendlyName} acepta ${tipos.length} '
          'formatos (HLS: ${_hayHls(tipos) ? "sí" : "no"})');
      return tipos;
    } catch (e) {
      // No poder preguntar no es motivo para no castear: se sigue como antes.
      logger.info('No se pudo preguntar los formatos del aparato: $e');
      return const {};
    }
  }

  /// Si al aparato se le puede mandar una lista HLS directamente.
  ///
  /// Ante la duda contesta **true**, a propósito: si no se pudo preguntar, lo
  /// que corresponde es intentar como se hacía siempre y no cambiarle el camino
  /// a un aparato que a lo mejor andaba bien.
  static Future<bool> aceptaHls(DLNADevice device) async {
    final tipos = await de(device);
    if (tipos.isEmpty) return true;
    return _hayHls(tipos);
  }

  /// Si el aparato acepta MPEG-TS, que es a lo que se puede reempaquetar HLS
  /// sin recodificar nada. Ver [CastHlsATs].
  ///
  /// Se aceptan los dos nombres porque no hay uno solo: DLNA lo publica como
  /// `video/mpeg` y el resto del mundo como `video/mp2t`. El televisor medido
  /// del usuario usa el primero.
  static Future<bool> aceptaTs(DLNADevice device) async {
    final tipos = await de(device);
    if (tipos.isEmpty) return false;
    return tipos.contains('video/mpeg') ||
        tipos.contains('video/mp2t') ||
        tipos.contains('video/x-mpegts');
  }

  static bool _hayHls(Set<String> tipos) =>
      tipos.any((t) => t.contains('mpegurl'));

  /// La dirección a la que se le hacen las preguntas de ConnectionManager.
  static Uri? _controlDeConnectionManager(DLNADevice device) {
    for (final s in device.info.serviceList) {
      if (s is! Map) continue;
      final tipo = '${s['serviceType']}';
      if (!tipo.contains('ConnectionManager')) continue;
      final control = '${s['controlURL']}';
      if (control.isEmpty || control == 'null') continue;
      if (control.startsWith('http')) return Uri.tryParse(control);
      final base = Uri.tryParse(device.info.URLBase);
      if (base == null) return null;
      return base.replace(
          path: control.startsWith('/') ? control : '/$control');
    }
    return null;
  }

  static String? _entre(String s, String etiqueta) {
    final i = s.indexOf('<$etiqueta>');
    if (i < 0) return null;
    final j = s.indexOf('</$etiqueta>', i);
    if (j < 0) return null;
    return s.substring(i + etiqueta.length + 2, j).trim();
  }
}
