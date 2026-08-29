/// Nodos de CDN que no entregaron a tiempo.
///
/// ── Para qué sirve ──────────────────────────────────────────────────────────
///
/// Una lista HLS reparte sus pedacitos entre varios nodos del CDN, y no todos
/// responden igual: alguno puede estar caído, saturado o lejos. Pedirle a ese
/// nodo el pedacito siguiente es esperar por algo que ya se sabe que no va a
/// llegar, y el vídeo se corta.
///
/// Acá se anota cuál falló, para que el relay local elija otro de los que
/// sirven el mismo archivo (ver `RelayLocal`, donde se usa esto para ordenar
/// los candidatos: primero los que responden, y los malos solo como último
/// recurso).
///
/// ── Por qué se olvida ───────────────────────────────────────────────────────
///
/// A los cinco minutos. Un nodo puede estar caído un rato y volver, y
/// castigarlo para siempre dejaría la lista de candidatos cada vez más corta
/// hasta quedarse sin ninguno.
///
/// ── De dónde salió este archivo ─────────────────────────────────────────────
///
/// Era parte de `cast_hls_ts.dart`, que además reempaquetaba una lista HLS a
/// MPEG-TS para poder mandársela a un televisor DLNA que no entiende HLS. Al
/// retirarse el casteo, todo ese reempaquetado quedó sin nadie que lo llamara y
/// se fue; el registro de nodos lentos se quedó porque **nunca fue del
/// casteo**: lo usa la reproducción normal, en las cuatro plataformas.
class NodosLentos {
  NodosLentos._();

  static final Map<String, DateTime> _cuando = {};
  static const _cuantoSeRecuerda = Duration(minutes: 5);

  static void anotar(String host) {
    _cuando[host] = DateTime.now();
  }

  static bool esLento(String host) {
    final cuando = _cuando[host];
    if (cuando == null) return false;
    if (DateTime.now().difference(cuando) > _cuantoSeRecuerda) {
      _cuando.remove(host);
      return false;
    }
    return true;
  }
}
