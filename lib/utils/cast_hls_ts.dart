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

  /// Pone las cabeceras de la extensión y se asegura de que salga un
  /// User-Agent de navegador.
  ///
  /// El User-Agent NO es cosmético: medido contra la fuente del usuario
  /// (nika.playmudos.com, detrás de Cloudflare), con el que pone dart:io por
  /// defecto la respuesta es **403** y con uno de navegador es **200**.
  ///
  /// Y hay que mirar las cabeceras de la extensión, no las del pedido: dart:io
  /// **siempre** deja puesto su `Dart/x.y (dart:io)`, así que preguntar si el
  /// pedido ya trae uno da que sí SIEMPRE y el de navegador no se aplicaba
  /// nunca. Eso hacía que no se pudiera leer ni la lista, y desde afuera se
  /// veía como "este aparato no soporta el formato".
  static void _preparar(
    HttpClientRequest req,
    Map<String, String> headers,
    String userAgent,
  ) {
    headers.forEach((k, v) => req.headers.set(k, v));
    final loTraeLaExtension =
        headers.keys.any((k) => k.toLowerCase() == 'user-agent');
    if (!loTraeLaExtension && userAgent.isNotEmpty) {
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
  }

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
      final duraciones = <double>[];
      double? ultimoExtinf;
      for (final linea in const LineSplitter().convert(texto)) {
        final limpia = linea.trim();
        if (limpia.isEmpty) continue;
        if (limpia.startsWith('#EXTINF:')) {
          ultimoExtinf =
              double.tryParse(limpia.substring(8).split(',').first.trim());
          continue;
        }
        if (limpia.startsWith('#')) continue;
        pedacitos.add(uri.resolve(limpia));
        // Cada pedacito con SU duracion, no una suma: es lo que permite saber
        // en cual cae un minuto concreto cuando el usuario adelanta.
        duraciones.add(ultimoExtinf ?? 0);
        ultimoExtinf = null;
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

      final plan = PlanTs(
        pedacitos: pedacitos,
        duraciones: duraciones,
        headers: headers,
        userAgent: userAgent,
      );
      logger.info('Reempaquetado a TS: ${pedacitos.length} pedacitos, '
          '${plan.duracion.inSeconds}s');
      return plan;
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
    // Desde donde diga el plan: adelantar es servir el mismo video empezando
    // por otro pedacito.
    for (var i = plan.desde; i < plan.pedacitos.length; i++) {
      final trozo = plan.pedacitos[i];
      var entregado = false;
      for (var intento = 0; intento <= _reintentos && !entregado; intento++) {
        try {
          final req = await _cliente.getUrl(trozo);
          _preparar(req, plan.headers, plan.userAgent);
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
    _preparar(req, headers, userAgent);
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
      _preparar(req, headers, userAgent);
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
    required this.duraciones,
    required this.headers,
    required this.userAgent,
    this.desde = 0,
  });

  /// Las direcciones de los pedacitos, en orden de reproducción.
  final List<Uri> pedacitos;

  /// Cuánto dura cada pedacito, en segundos, sacado de los `#EXTINF`.
  ///
  /// Es lo que permite adelantar: sabiendo cuánto dura cada uno se sabe en
  /// cuál cae cualquier minuto del episodio. Ver [indiceDe].
  final List<double> duraciones;

  /// Desde qué pedacito arranca este flujo.
  ///
  /// Adelantar en un vídeo reempaquetado es empezar uno nuevo desde otro
  /// pedacito, porque el televisor no puede saltar dentro de un flujo que se
  /// va armando sobre la marcha.
  final int desde;

  final Map<String, String> headers;
  final String userAgent;

  /// Lo que dura el episodio entero.
  Duration get duracion => Duration(
      milliseconds:
          (duraciones.fold<double>(0, (a, b) => a + b) * 1000).round());

  /// En qué momento del episodio empieza este flujo.
  ///
  /// La app le suma esto a lo que informa el televisor, que cuenta desde cero
  /// porque para él es un vídeo nuevo.
  Duration get inicio => Duration(
      milliseconds: (duraciones
                  .take(desde)
                  .fold<double>(0, (a, b) => a + b) *
              1000)
          .round());

  /// Qué pedacito contiene ese momento del episodio.
  int indiceDe(Duration donde) {
    var acumulado = 0.0;
    final objetivo = donde.inMilliseconds / 1000.0;
    for (var i = 0; i < duraciones.length; i++) {
      acumulado += duraciones[i];
      if (acumulado > objetivo) return i;
    }
    // Más allá del final: el último, para no quedar fuera de la lista.
    return duraciones.isEmpty ? 0 : duraciones.length - 1;
  }

  /// El mismo vídeo, empezando desde otro pedacito.
  PlanTs recortadoDesde(int indice) => PlanTs(
        pedacitos: pedacitos,
        duraciones: duraciones,
        headers: headers,
        userAgent: userAgent,
        desde: indice.clamp(0, pedacitos.length - 1),
      );
}
