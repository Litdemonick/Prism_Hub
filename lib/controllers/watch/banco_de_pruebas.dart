import 'package:prismhub/utils/log.dart';

/// Mide cómo se comportó cada servidor, para poder recorrer las extensiones una
/// por una sin anotar nada a mano.
///
/// ── Para qué existe ─────────────────────────────────────────────────────────
///
/// El recorrido es: por cada extensión, probar todos sus servidores y decidir
/// cuáles se quedan, cuáles hay que arreglar y cuáles se sacan. Son veinte
/// extensiones y varios servidores cada una — jkanime sola tiene once.
///
/// Sin esto, por cada servidor hay que mirar a ojo si se abrió el navegador
/// incrustado y, para saber cuánto tardó, abrir el registro y restar marcas de
/// tiempo a mano. Cien veces.
///
/// Con esto, cada servidor deja UNA línea que ya trae el veredicto:
///
///     RESULTADO · jkanime · VOE · NATIVO · 2,4 s hasta la imagen
///     RESULTADO · jkanime · Doodstream · WEBVIEW · no resolvió nativo
///     RESULTADO · latanime · Mega · FALLÓ · el servidor no entregó nada
///
/// Se exporta el registro desde Ajustes al terminar la extensión y la tabla ya
/// está hecha.
///
/// ── Por qué mide desde que se ELIGE el servidor ─────────────────────────────
///
/// El reloj arranca cuando se pide el servidor, no cuando empieza a abrirse el
/// vídeo. Lo que interesa medir es lo que espera la persona desde que toca,
/// y ahí adentro entra todo: que la extensión resuelva la dirección, que el
/// sniffer entre si hace falta, y recién después que el reproductor abra.
///
/// Un servidor puede reproducir perfecto y aun así tardar ocho segundos porque
/// su resolución es lenta. Eso es un resultado tan válido como «no anda», y sin
/// medirlo desde el principio no se ve.
///
/// ── Qué NO hace ─────────────────────────────────────────────────────────────
///
/// No decide nada ni cambia el comportamiento: solo mira y anota. Si algo acá
/// falla, la reproducción sigue igual — por eso todo va envuelto y nunca
/// relanza.
class BancoDePruebas {
  BancoDePruebas._();

  static String? _extension;
  static String? _servidor;
  static DateTime? _desde;
  static bool _yaDijoElResultado = false;

  /// Empieza a cronometrar un servidor. Se llama al pedirlo, no al abrirlo.
  static void empezar({required String extension, required String servidor}) {
    _extension = extension;
    _servidor = servidor;
    _desde = DateTime.now();
    _yaDijoElResultado = false;
  }

  /// Se vio la primera imagen: el servidor sirve, y se sabe cuánto tardó.
  static void seVio({String motor = 'mpv'}) =>
      _cerrar('NATIVO', extra: '${_cuanto()} hasta la imagen · $motor');

  /// Hubo que abrir el navegador incrustado: no se pudo resolver nativo.
  ///
  /// Es el veredicto que más importa del recorrido — es la lista de lo que hay
  /// que arreglar o sacar.
  static void cayoAlNavegador() =>
      _cerrar('WEBVIEW', extra: 'no resolvió nativo');

  /// El servidor no sirvió y no hay ni navegador al que caer.
  static void fallo(String porQue) => _cerrar('FALLÓ', extra: porQue);

  static String _cuanto() {
    final desde = _desde;
    if (desde == null) return 'tiempo desconocido';
    final ms = DateTime.now().difference(desde).inMilliseconds;
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }

  /// Una sola línea por servidor.
  ///
  /// El candado importa: un servidor puede pasar por varios caminos antes de
  /// asentarse (intenta nativo, falla, cae al navegador), y sin esto dejaría
  /// tres líneas contradictorias para el mismo intento. Manda la primera
  /// conclusión, que es la que describe qué pasó de verdad.
  static void _cerrar(String veredicto, {required String extra}) {
    try {
      if (_yaDijoElResultado) return;
      final ext = _extension;
      final srv = _servidor;
      if (ext == null || srv == null) return;
      _yaDijoElResultado = true;
      logger.info('RESULTADO · $ext · $srv · $veredicto · $extra');
    } catch (_) {
      // Es un instrumento de medición: no puede tumbar una reproducción.
    }
  }
}
