import 'dart:async';

import 'package:dio/dio.dart';
import 'package:prismhub/utils/i18n.dart';

/// True when an error looks like a network/connectivity failure (no
/// internet, host unreachable, connection reset, timeout, etc.). Checks the
/// DioException type first (reliable, and covers cases like
/// "DioException [unknown]: null" whose text matches no marker below) before
/// falling back to matching the stringified message.
bool isConnectionError(Object? error) {
  if (error == null) return false;
  if (error is DioException &&
      (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError ||
          // DioExceptionType.unknown: en la práctica, casi siempre envuelve
          // una falla de socket/red que Dio no supo categorizar mejor (el
          // caso "DioException [unknown]: null" sin mensaje interno). Para
          // una petición HTTP simple como las de las extensiones, tratarlo
          // como "sin conexión" es más útil que mostrar el texto crudo.
          error.type == DioExceptionType.unknown)) {
    return true;
  }
  final e = error.toString().toLowerCase();
  const markers = [
    'connection error',
    'connectionerror',
    'socketexception',
    'connection reset',
    'connection closed',
    'failed host lookup',
    'connection refused',
    'connection timed out',
    'network is unreachable',
    'no address associated',
    'software caused connection abort',
    'xmlhttprequest error',
    // Fallo de TLS: típico de un ISP/firewall interceptando o cortando la
    // conexión antes de que llegue al sitio real (más común en conexiones
    // internacionales o países con bloqueo por proveedor) — no es "el sitio
    // está caído", es que la conexión nunca se estableció de verdad.
    'handshakeexception',
    'connection terminated during handshake',
    // Timeouts propios de Dio (connectTimeout/receiveTimeout/sendTimeout) —
    // el mensaje de Dio no incluye ninguna de las frases de arriba.
    //
    // Van las dos redacciones porque Dio le cambió el texto entre versiones y
    // eso rompió la detección sin que nadie tocara nada: las de abajo son las
    // que escribía Dio 4, y las de arriba las que escribe Dio 5 (comprobado en
    // dio_exception.dart de la versión instalada). Con solo las viejas, un
    // corte de internet al abrir una ficha mostraba el texto crudo en inglés
    // —"DioException [connection timeout]: The request connection took longer
    // than 0:00:15…"— en vez del aviso de siempre.
    'dioexception [connection timeout]',
    'dioexception [connection error]',
    'dioexception [receive timeout]',
    'dioexception [send timeout]',
    'connecting timeout',
    'receiving timeout',
    'sending timeout',
    // Las peticiones de las extensiones cruzan el puente JS (QuickJS) antes
    // de volver a Dart — confirmado en vivo que ahí se pierde el tipo real
    // DioException (queda solo el texto), así que el chequeo por tipo de
    // arriba no alcanza para ese caso. "[unknown]" es el propio formato de
    // Dio para DioExceptionType.unknown en su toString().
    'dioexception [unknown]',
  ];
  return markers.any(e.contains);
}

/// ¿La conexión SÍ se llegó a establecer y lo que falló fue el otro lado?
///
/// Porque no es lo mismo y hasta ahora se decía igual: **todo** fallo de red
/// salía como "conectate a internet", y en la mayoría de los casos el internet
/// del usuario estaba perfecto.
///
/// Medido el 2026-08-06 con Vidhide: la extensión resolvía bien y el CDN
/// (`acek-cdn.com`) contestaba **502 y 504** en tres episodios distintos. El
/// app decía que era su internet. Un rato después cargó solo, sin que nadie
/// tocara nada — porque nunca fue el internet.
///
/// La diferencia está en el tipo:
///
///   NO llegamos a conectar     no hay DNS, no hay ruta, rechazó la conexión.
///                              Ahí sí puede ser el internet del usuario.
///   Conectamos y se cayó       el otro lado no mandó a tiempo, cortó la
///                              conexión o la reinició. El internet anda; el
///                              que está mal es el servidor.
///
/// `isConnectionError` sigue devolviendo true para los dos, así que ninguna
/// pantalla cambia de camino: lo único que cambia es el texto.
bool _falloDelOtroLado(Object? error) {
  if (error is DioException &&
      (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout)) {
    return true;
  }
  final e = error.toString().toLowerCase();
  const delOtroLado = [
    'connection reset',
    'connection closed',
    'software caused connection abort',
    'dioexception [receive timeout]',
    'dioexception [send timeout]',
    'receiving timeout',
    'sending timeout',
  ];
  return delOtroLado.any(e.contains);
}

/// Maps a raw error to a clean, user-facing message. Connection failures
/// become a friendly notice; anything else returns its first line so we never
/// dump a full stack trace at the user.
String friendlyError(Object? error) {
  if (error == null) return '';
  if (isConnectionError(error)) {
    return _falloDelOtroLado(error)
        ? 'common.fuente-no-responde'.i18n
        : 'common.no-internet'.i18n;
  }
  if (isTimeoutError(error)) {
    return 'common.source-timeout'.i18n;
  }
  // Primera línea, y sin el nombre de la clase adelante.
  //
  // Lo que se veía en pantalla era "TimeoutException: Tiempo de espera
  // agotado", "Exception: ..." o directamente un nombre de clase de Dart. Al
  // usuario no le dice nada y encima parece que se rompió la app. El texto útil
  // es lo que va DESPUÉS de los dos puntos; el prefijo solo sirve para el log.
  final linea = error.toString().split('\n').first.trim();
  final sinClase =
      RegExp(r'^[A-Z][A-Za-z]*(?:Exception|Error)\s*:\s*').firstMatch(linea);
  final texto = sinClase == null ? linea : linea.substring(sinClase.end).trim();
  return texto.isEmpty ? linea : texto;
}

/// True cuando el error es que se agotó la espera.
///
/// La búsqueda general le da a cada extensión un tope de tiempo para que una
/// fuente colgada no deje la pantalla esperando para siempre. Cuando se cumple,
/// no es un fallo de la app ni de la extensión: el sitio tardó de más. Merece
/// un texto que lo diga y no el nombre de la excepción.
bool isTimeoutError(Object? error) {
  if (error == null) return false;
  if (error is TimeoutException) return true;
  // Los timeouts de Dio los toma antes isConnectionError, así que por el camino
  // de friendlyError acá no llegan. Se dejan igual para que esta función valga
  // por sí sola en cualquier otro uso.
  if (error is DioException &&
      (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout)) {
    return true;
  }
  return error.toString().toLowerCase().contains('timeoutexception');
}
