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

/// Maps a raw error to a clean, user-facing message. Connection failures
/// become a friendly "connect to the internet" notice; anything else returns
/// its first line so we never dump a full stack trace at the user.
String friendlyError(Object? error) {
  if (error == null) return '';
  if (isConnectionError(error)) {
    return 'common.no-internet'.i18n;
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
