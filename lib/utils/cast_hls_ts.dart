import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prismhub/utils/log.dart';

/// Convierte una lista HLS en un vídeo continuo que un televisor viejo entiende.
///
/// El problema: las extensiones sirven casi todo en HLS (`.m3u8`), y **ningún
/// televisor DLNA lo reproduce** — HLS es de 2009 y DLNA es anterior, nunca lo
/// incorporó. Medido en la red del usuario: Kodi publica `mpegurl` entre sus
/// formatos y reproduce; el televisor no lo publica y se queda en negro.
///
/// La salida: una lista HLS **ya es** MPEG-TS por dentro. Los pedacitos `.ts`
/// que la componen son trozos de un flujo MPEG-TS normal, cortados en pedazos.
/// Pegarlos uno atrás de otro devuelve un MPEG-TS válido, y `video/mpeg` sí
/// está en la lista de formatos del televisor. **No se recodifica nada**: los
/// bytes salen tal cual llegan, así que no cuesta procesador ni pierde calidad.
///
/// Lo que se pierde: no se puede adelantar. Al televisor se le manda un flujo
/// de largo desconocido, así que la barra de progreso no le sirve para saltar.
/// Se avisa antes de empezar en vez de dejar que lo descubra probando.
///
/// Cuándo NO se puede, y hay que decirlo en vez de mandar basura:
///
///  - **Pedacitos cifrados** (`#EXT-X-KEY`): habría que descifrarlos primero.
///  - **Pedacitos en formato MP4** (`#EXT-X-MAP`, el HLS moderno): no son
///    MPEG-TS, y pegarlos no da nada reproducible.
class CastHlsATs {
  /// Cuántas veces se reintenta un pedacito antes de saltearlo.
  static const _reintentos = 2;

  static final HttpClient _cliente = HttpClient()
    ..maxConnectionsPerHost = 4
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 15);

  /// Mira la lista y decide si se puede reempaquetar.
  ///
  /// Devuelve null cuando no se puede — el motivo queda en el registro.
  static Future<PlanTs?> analizar(
    String url,
    Map<String, String> headers,
    String userAgent,
  ) async {
    try {
      var uri = Uri.parse(url);
      var texto = await _bajarTexto(uri, headers, userAgent);
      if (texto == null) return null;

      // Lista maestra: no trae pedacitos, trae una lista por calidad. Hay que
      // elegir una y volver a bajar.
      if (texto.contains('#EXT-X-STREAM-INF')) {
        final variante = _mejorVariante(texto, uri);
        if (variante == null) {
          logger.info('Reempaquetado a TS: la lista maestra no traía calidades');
          return null;
        }
        uri = variante;
        texto = await _bajarTexto(uri, headers, userAgent);
        if (texto == null) return null;
      }

      if (RegExp(r'#EXT-X-KEY:[^\r\n]*METHOD=(?!NONE)').hasMatch(texto)) {
        logger.info('Reempaquetado a TS: los pedacitos están cifrados');
        return null;
      }
      if (texto.contains('#EXT-X-MAP')) {
        logger.info('Reempaquetado a TS: los pedacitos son MP4, no MPEG-TS');
        return null;
      }

      final pedacitos = <Uri>[];
      var duracion = 0.0;
      for (final linea in const LineSplitter().convert(texto)) {
        final limpia = linea.trim();
        if (limpia.isEmpty) continue;
        if (limpia.startsWith('#EXTINF:')) {
          duracion +=
              double.tryParse(limpia.substring(8).split(',').first.trim()) ?? 0;
          continue;
        }
        if (limpia.startsWith('#')) continue;
        pedacitos.add(uri.resolve(limpia));
      }
      if (pedacitos.isEmpty) {
        logger.info('Reempaquetado a TS: la lista no tenía pedacitos');
        return null;
      }

      // Comprobación de verdad, no por el nombre del archivo: se bajan los
      // primeros bytes del primer pedacito y se mira si son MPEG-TS. Fiarse de
      // que termine en ".ts" es lo que haría mandarle basura al televisor
      // cuando la fuente usa otra extensión.
      if (!await _esMpegTs(pedacitos.first, headers, userAgent)) {
        logger.info('Reempaquetado a TS: el primer pedacito no es MPEG-TS');
        return null;
      }

      logger.info('Reempaquetado a TS: ${pedacitos.length} pedacitos, '
          '${duracion.round()}s');
      return PlanTs(
        pedacitos: pedacitos,
        duracion: Duration(seconds: duracion.round()),
        headers: headers,
        userAgent: userAgent,
      );
    } catch (e) {
      logger.info('Reempaquetado a TS: no se pudo analizar la lista — $e');
      return null;
    }
  }

  /// Los bytes del vídeo, en orden y sin cortes.
  ///
  /// Va bajando un pedacito mientras el televisor consume el anterior. No se
  /// junta todo en memoria: son cientos de megas.
  static Stream<List<int>> servir(PlanTs plan) async* {
    for (var i = 0; i < plan.pedacitos.length; i++) {
      final trozo = plan.pedacitos[i];
      var entregado = false;
      for (var intento = 0; intento <= _reintentos && !entregado; intento++) {
        try {
          final req = await _cliente.getUrl(trozo);
          plan.headers.forEach((k, v) => req.headers.set(k, v));
          if (req.headers.value(HttpHeaders.userAgentHeader) == null) {
            req.headers.set(HttpHeaders.userAgentHeader, plan.userAgent);
          }
          final res = await req.close().timeout(const Duration(seconds: 30));
          if (res.statusCode >= 400) {
            await res.drain<void>();
            throw HttpException('HTTP ${res.statusCode}');
          }
          await for (final bloque in res) {
            yield bloque;
          }
          entregado = true;
        } catch (e) {
          if (intento == _reintentos) {
            // Un pedacito perdido se nota como un saltito y el vídeo sigue.
            // Cortar la transmisión entera por uno sería mucho peor.
            logger.warning(
                'Reempaquetado a TS: se saltea el pedacito ${i + 1} — $e');
          }
        }
      }
    }
  }

  /// Baja una lista y la devuelve como texto, o null si no se pudo.
  static Future<String?> _bajarTexto(
    Uri uri,
    Map<String, String> headers,
    String userAgent,
  ) async {
    final req = await _cliente.getUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    if (req.headers.value(HttpHeaders.userAgentHeader) == null) {
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      await res.drain<void>();
      logger.info('Reempaquetado a TS: la lista contestó ${res.statusCode}');
      return null;
    }
    return res.transform(utf8.decoder).join();
  }

  /// La calidad más alta de una lista maestra.
  static Uri? _mejorVariante(String texto, Uri base) {
    final lineas = const LineSplitter().convert(texto);
    Uri? mejor;
    var mejorAncho = -1;
    for (var i = 0; i < lineas.length; i++) {
      if (!lineas[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final ancho = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(lineas[i])?.group(1) ??
                  '') ??
          0;
      for (var j = i + 1; j < lineas.length; j++) {
        final destino = lineas[j].trim();
        if (destino.isEmpty || destino.startsWith('#')) continue;
        if (ancho > mejorAncho) {
          mejorAncho = ancho;
          mejor = base.resolve(destino);
        }
        break;
      }
    }
    return mejor;
  }

  /// Si los bytes que llegan son de verdad MPEG-TS.
  ///
  /// Un MPEG-TS son paquetes de 188 bytes que empiezan siempre con 0x47. Se
  /// comprueban dos seguidos: que el primer byte sea 0x47 puede ser suerte, que
  /// además lo sea el byte 188 no lo es.
  static Future<bool> _esMpegTs(
    Uri trozo,
    Map<String, String> headers,
    String userAgent,
  ) async {
    try {
      final req = await _cliente.getUrl(trozo);
      headers.forEach((k, v) => req.headers.set(k, v));
      if (req.headers.value(HttpHeaders.userAgentHeader) == null) {
        req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-375');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode >= 400) {
        await res.drain<void>();
        return false;
      }
      final bytes = <int>[];
      await for (final b in res) {
        bytes.addAll(b);
        if (bytes.length >= 189) break;
      }
      if (bytes.length < 189) return false;
      return bytes[0] == 0x47 && bytes[188] == 0x47;
    } catch (_) {
      return false;
    }
  }
}

/// Todo lo que hace falta para servir una lista HLS como un MPEG-TS continuo.
class PlanTs {
  PlanTs({
    required this.pedacitos,
    required this.duracion,
    required this.headers,
    required this.userAgent,
  });

  /// Las direcciones de los pedacitos, en orden de reproducción.
  final List<Uri> pedacitos;

  /// Sumada de los `#EXTINF` de la lista.
  ///
  /// Sirve para decirle al televisor cuánto dura en la ficha del vídeo: sin
  /// esto la barra de progreso queda vacía toda la reproducción.
  final Duration duracion;

  final Map<String, String> headers;
  final String userAgent;
}
