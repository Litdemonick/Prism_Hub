/// La portada que la tarjeta YA estaba mostrando cuando se tocó.
///
/// Al abrir una ficha, la app se queda un rato sin imagen: primero espera a que
/// la extensión conteste y recién ahí sabe qué portada pedir, y todavía tiene
/// que bajarla. Medido en HQPorner: 990 ms de la extensión más 1265 ms de
/// descarga (108 KB) — más de dos segundos de hueco.
///
/// Y no hace falta. La imagen de la tarjeta que se acaba de tocar ya está
/// descargada y en memoria. Anotándola acá, la ficha la dibuja de entrada y la
/// cambia sola si la extensión devuelve otra distinta.
///
/// Por qué acá y no como parámetro de navegación: en escritorio la ficha se
/// abre por una dirección con parámetros, y meter ahí una URL de imagen (más
/// sus cabeceras, que no son texto suelto) la ensucia sin necesidad. Esto es
/// un dato de presentación y de vida corta: si falta, la ficha se comporta
/// exactamente como antes.
class PortadaAdelantada {
  PortadaAdelantada._();

  /// Cuántas se recuerdan. Alcanza de sobra para ir y volver entre fichas
  /// mientras se navega, y pone un techo para que no crezca sin límite en una
  /// sesión larga.
  static const _maximo = 200;

  static final Map<String, ({String url, Map<String, String>? cabeceras})>
      _guardadas = {};

  static String _clave(String paquete, String url) => '$paquete|$url';

  /// Anota la portada que se está viendo, justo antes de abrir la ficha.
  static void anotar(
    String paquete,
    String url, {
    String? portada,
    Map<String, String>? cabeceras,
  }) {
    if (portada == null || portada.isEmpty) return;
    final clave = _clave(paquete, url);
    // Se saca y se vuelve a poner para que quede al final: así la que se
    // descarta al llegar al tope es siempre la más vieja.
    _guardadas.remove(clave);
    _guardadas[clave] = (url: portada, cabeceras: cabeceras);
    while (_guardadas.length > _maximo) {
      _guardadas.remove(_guardadas.keys.first);
    }
  }

  /// La portada anotada para esta ficha, si hay alguna.
  static ({String url, Map<String, String>? cabeceras})? de(
    String paquete,
    String url,
  ) =>
      _guardadas[_clave(paquete, url)];
}
