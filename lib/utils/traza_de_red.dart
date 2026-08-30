import 'package:dio/dio.dart';
import 'package:prismhub/utils/log.dart';

/// Deja constancia de cada pedido de red de la app.
///
/// ── Por qué hace falta ──────────────────────────────────────────────────────
///
/// Lo que hacen las extensiones ya se anotaba, pero lo que pide la app por su
/// cuenta —el catálogo de extensiones, el aviso de versión nueva, las portadas,
/// el seguimiento— no dejaba rastro. Así que cuando algo «no carga» y la
/// extensión ni intervino, el registro no tenía nada que decir: había que
/// adivinar si el problema era el servidor, el proxy, la red o la app.
///
/// Pedido explícito: «si no hay logs suficientes de todo el app no se podrá
/// fixear cosas».
///
/// ── Una línea por pedido, y qué lleva ───────────────────────────────────────
///
/// Método, dirección, código de respuesta y cuánto tardó. Con eso se separa lo
/// que hay que separar: un 404 es un problema del servidor, un tiempo agotado
/// es de la red, y trescientos milisegundos con respuesta correcta es que el
/// problema está en otro lado.
///
/// **Ni cabeceras ni contenido**, a propósito: ahí es donde viajan las cookies
/// y las credenciales, y el saneado del registro limpia direcciones, no
/// cabeceras. Las direcciones sí salen recortadas solas al escribirse — ver
/// [PrismLog.sanear].
class TrazaDeRed extends Interceptor {
  /// La marca con que se firman estas líneas.
  ///
  /// Un prefijo fijo y no texto suelto: es lo que deja clasificarlas después
  /// sin adivinar por las palabras que traiga el mensaje.
  static const marca = '[red]';

  static const _cuando = 'traza-inicio';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_cuando] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    logger.info('$marca ${response.requestOptions.method} '
        '${response.requestOptions.uri} → ${response.statusCode}'
        '${_cuantoTardo(response.requestOptions)}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Como aviso y no como información: esto es lo que se busca al abrir la
    // zona de fallos, y sin el nivel correcto quedaría enterrado entre
    // cientos de pedidos que salieron bien.
    logger.warning('$marca ${err.requestOptions.method} '
        '${err.requestOptions.uri} → ${_porQue(err)}'
        '${_cuantoTardo(err.requestOptions)}');
    handler.next(err);
  }

  /// El motivo en palabras, no el volcado de la excepción.
  ///
  /// `e.toString()` de Dio son varias líneas con la petición entera adentro,
  /// cabeceras incluidas — justo lo que no puede ir al registro. Y para
  /// diagnosticar alcanza con saber cuál de estas cinco cosas pasó.
  static String _porQue(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout => 'no se pudo conectar (tiempo)',
        DioExceptionType.sendTimeout => 'tiempo agotado enviando',
        DioExceptionType.receiveTimeout => 'tiempo agotado esperando',
        DioExceptionType.badCertificate => 'certificado rechazado',
        DioExceptionType.badResponse => '${e.response?.statusCode}',
        DioExceptionType.cancel => 'cancelado',
        DioExceptionType.connectionError => 'sin conexión',
        DioExceptionType.transformTimeout => 'tiempo agotado procesando',
        DioExceptionType.unknown => 'falló',
      };

  static String _cuantoTardo(RequestOptions options) {
    final desde = options.extra[_cuando];
    if (desde is! DateTime) return '';
    return ' · ${DateTime.now().difference(desde).inMilliseconds} ms';
  }
}
