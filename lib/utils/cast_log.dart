import 'package:prismhub/utils/log.dart';

/// El registro del casteo, en un solo lugar y sin nada del contenido.
///
/// Por qué existe: tres aparatos fallan de tres formas distintas y la app no
/// contaba nada de lo que hacía, así que todo diagnóstico era adivinanza. Un
/// televisor que no puede con el formato **acepta igual la orden** y muestra el
/// título, o sea que desde afuera se ve idéntico a que funcione.
///
/// Todas las líneas llevan `[casteo]` adelante para poder sacarlas del archivo
/// de un tirón.
///
/// **Nunca entra un título ni una dirección del contenido**: el archivo se
/// comparte para diagnosticar y la causa está en la negociación con el aparato,
/// no en qué vídeo era. Las direcciones pasan siempre por [donde], que cambia el
/// servidor por un seudónimo estable — así se sigue viendo si los pedacitos
/// salían de otro servidor que la lista, que sí es dato, sin decir de dónde.
class CastLog {
  static void paso(String texto) => logger.info('[casteo] $texto');

  static void fallo(String texto, [Object? error]) =>
      logger.warning('[casteo] $texto', error);

  /// Una dirección en forma publicable: `servidor#a3f1 .m3u8`.
  ///
  /// El seudónimo es el mismo mientras dure la ejecución, así que dos líneas
  /// con el mismo `#` hablan del mismo servidor. La dirección del relay se
  /// registra aparte y entera (ver [anuncio]): esa es nuestra.
  static String donde(String? url) {
    if (url == null || url.isEmpty) return 'sin direccion';
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return 'direccion ilegible';
    return 'servidor#${_seudonimo(u.host)} ${_extension(u)}';
  }

  /// La dirección que le anunciamos al aparato, entera y a propósito: es un
  /// equipo de la red del usuario, y el par IP:puerto es justamente lo que hay
  /// que mirar cuando el aparato no llega a pedirnos nada.
  static String anuncio(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    return '${u.host}:${u.port}';
  }

  /// Cabeceras en una línea, con los valores que pueden delatar el contenido
  /// tapados.
  ///
  /// Se tapa el VALOR y no la cabecera entera: que la fuente haya mandado un
  /// `Content-Disposition` es dato —ahí viaja el nombre del archivo, y eso lo
  /// cambia todo para un receptor que decide el formato por el nombre— pero el
  /// nombre en sí no puede quedar escrito en un archivo que se comparte.
  static const _valoresQueSeTapan = {
    'content-disposition',
    'location',
    'referer',
    'cookie',
    'set-cookie',
    'authorization',
  };

  static String cabeceras(Map<String, String> h) => h.isEmpty
      ? 'sin cabeceras'
      : h.entries
          .map((e) => _valoresQueSeTapan.contains(e.key.toLowerCase())
              ? '${e.key}: (tapado)'
              : '${e.key}: ${e.value}')
          .join(' | ');

  /// Qué contestó un aparato DLNA a una orden.
  ///
  /// Un fallo de UPnP viaja como un cuerpo SOAP con `<errorCode>` adentro y
  /// código HTTP 500, así que sin mirarlo todo error se veía igual. Los que más
  /// aparecen: 701 (no hay nada cargado), 714 (no reconoce el formato), 716 (no
  /// pudo bajar la dirección).
  static String respuestaUpnp(String xml) {
    final codigo =
        RegExp(r'<errorCode>(\d+)</errorCode>').firstMatch(xml)?.group(1);
    if (codigo == null) {
      return xml.contains('Fault') ? 'fallo SOAP sin codigo' : 'aceptado';
    }
    final texto = RegExp(r'<errorDescription>([^<]*)</errorDescription>')
        .firstMatch(xml)
        ?.group(1)
        ?.trim();
    return 'error UPnP $codigo${texto == null || texto.isEmpty ? '' : ' ($texto)'}';
  }

  static String _seudonimo(String host) =>
      (host.hashCode & 0xffff).toRadixString(16).padLeft(4, '0');

  static String _extension(Uri u) {
    final camino = u.path.toLowerCase();
    final punto = camino.lastIndexOf('.');
    // Más de cinco letras después del punto no es una extensión, es parte del
    // nombre: se prefiere no decir nada a decir algo del contenido.
    if (punto < 0 || camino.length - punto > 6) return 'sin extension';
    return camino.substring(punto);
  }
}
