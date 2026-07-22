import 'package:dio/dio.dart';
import 'package:prismhub/utils/i18n.dart';

/// True when an error string looks like a network/connectivity failure
/// (no internet, host unreachable, connection reset, etc.).
bool isConnectionError(String? error) {
  if (error == null) return false;
  final e = error.toLowerCase();
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
    'connecting timeout',
    'receiving timeout',
    'sending timeout',
  ];
  return markers.any(e.contains);
}

/// Maps a raw error to a clean, user-facing message. Connection failures
/// become a friendly "connect to the internet" notice; anything else returns
/// its first line so we never dump a full stack trace at the user.
String friendlyError(Object? error) {
  if (error == null) return '';
  // Chequeo directo del tipo primero: más confiable que matchear texto, y
  // cubre timeouts de Dio cuyo mensaje no calza con ningún marker de arriba.
  if (error is DioException &&
      (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError)) {
    return 'common.no-internet'.i18n;
  }
  final text = error.toString();
  if (isConnectionError(text)) {
    return 'common.no-internet'.i18n;
  }
  return text.split('\n').first;
}
