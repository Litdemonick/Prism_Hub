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
  if (isConnectionError(error)) {
    return 'common.no-internet'.i18n;
  }
  return error.toString().split('\n').first;
}
