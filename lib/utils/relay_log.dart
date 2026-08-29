import 'package:prismhub/utils/log.dart';

/// El registro del relay local, en un solo lugar y sin nada del contenido.
///
/// Por qué existe: cuando el relay se mete en el medio para esquivar un nodo
/// caído, todo lo que pasa ocurre por debajo y sin dejar rastro — un pedacito
/// que no llegó y uno que se pidió a otro nodo se ven igual desde afuera.
///
/// Todas las líneas llevan `[relay]` adelante para poder sacarlas del archivo
/// de un tirón.
///
/// **Nunca entra un título ni una dirección del contenido**: el archivo se
/// comparte para diagnosticar y la causa está en qué nodo respondió y cuál no,
/// no en qué vídeo era. Las direcciones pasan siempre por [donde], que cambia el
/// servidor por un seudónimo estable — así se sigue viendo si los pedacitos
/// salían de otro servidor que la lista, que sí es dato, sin decir de dónde.
class RelayLog {
  static void paso(String texto) => logger.info('[relay] $texto');

  static void fallo(String texto, [Object? error]) =>
      logger.warning('[relay] $texto', error);

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
