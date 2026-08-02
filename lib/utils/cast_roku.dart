import 'dart:async';
import 'dart:io';

import 'package:prismhub/utils/log.dart';

/// Habla con un Roku.
///
/// Roku no es un receptor DLNA —su "Roku Media Player" es lo contrario: un
/// cliente que busca contenido en la red— ni habla Google Cast. Usa lo suyo,
/// ECP, que es HTTP plano en el puerto 8060: sin cifrado, sin emparejamiento.
///
/// Se le manda el vídeo lanzando su reproductor de medios con la dirección
/// como parámetro, y se lo controla mandando pulsaciones de mando a distancia.
///
/// LÍMITE IMPORTANTE: ECP no tiene un "saltar al minuto X". Se puede adelantar
/// y retroceder a saltos con las teclas del mando, pero no ir a un punto
/// exacto. Por eso [permiteSaltar] es false y la app lo dice en vez de dejar
/// una rueda girando esperando algo que no va a pasar.
class RokuCliente {
  RokuCliente(this.host, {this.puerto = 8060});

  final String host;
  final int puerto;

  /// El canal "Roku Media Player", que viene de fábrica en todos los Roku.
  /// Es el que sabe reproducir una dirección suelta.
  static const _canalMedios = '2213';

  static final _cliente = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  Uri _u(String camino) => Uri.parse('http://$host:$puerto$camino');

  Future<bool> _post(String camino) async {
    try {
      final req = await _cliente.postUrl(_u(camino));
      req.contentLength = 0;
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      logger.warning('El Roku no acepto $camino', e);
      return false;
    }
  }

  Future<String?> _get(String camino) async {
    try {
      final req = await _cliente.getUrl(_u(camino));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await res.drain<void>();
        return null;
      }
      return await res
          .transform(const SystemEncoding().decoder)
          .join()
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      logger.info('El Roku no contesto $camino: $e');
      return null;
    }
  }

  /// Lanza el reproductor con el vídeo.
  ///
  /// El título va aparte para que se vea en la pantalla del Roku en vez del
  /// nombre del archivo.
  Future<bool> cargar({
    required String url,
    required String titulo,
    String mime = 'video/mp4',
  }) async {
    final tipo = _formato(mime, url);
    final camino = '/launch/$_canalMedios'
        '?t=v'
        '&u=${Uri.encodeQueryComponent(url)}'
        '&videoName=${Uri.encodeQueryComponent(titulo)}'
        '&videoFormat=$tipo';
    return _post(camino);
  }

  /// El formato que espera Roku, que no es el tipo MIME sino un nombre corto.
  static String _formato(String mime, String url) {
    final u = url.split('?').first.toLowerCase();
    if (mime.contains('mpegurl') || u.endsWith('.m3u8')) return 'hls';
    if (u.endsWith('.mkv')) return 'mkv';
    if (u.endsWith('.mp4') || mime.contains('mp4')) return 'mp4';
    return 'mp4';
  }

  /// Play y Pause son la MISMA tecla en el mando: alterna.
  Future<void> alternarPausa() => _post('/keypress/Play').then((_) {});

  Future<void> parar() => _post('/keypress/Home').then((_) {});

  Future<void> subirVolumen() => _post('/keypress/VolumeUp').then((_) {});
  Future<void> bajarVolumen() => _post('/keypress/VolumeDown').then((_) {});

  /// Estado del reproductor, interpretado.
  ///
  /// Devuelve null si no contestó o si no se está reproduciendo nada nuestro.
  Future<EstadoRoku?> estado() async {
    final xml = await _get('/query/media-player');
    if (xml == null) return null;
    return EstadoRoku.desdeXml(xml);
  }

  /// Nombre del aparato, para la lista.
  Future<String?> nombre() async {
    final xml = await _get('/query/device-info');
    if (xml == null) return null;
    return _entre(xml, 'user-device-name') ??
        _entre(xml, 'friendly-device-name') ??
        _entre(xml, 'model-name');
  }

  static String? _entre(String s, String etiqueta) {
    final i = s.indexOf('<$etiqueta>');
    if (i < 0) return null;
    final j = s.indexOf('</$etiqueta>', i);
    if (j < 0) return null;
    final v = s.substring(i + etiqueta.length + 2, j).trim();
    return v.isEmpty ? null : v;
  }
}

/// Lo que informa `/query/media-player`.
class EstadoRoku {
  EstadoRoku({
    required this.reproduciendo,
    required this.parado,
    this.posicion,
    this.duracion,
  });

  final bool reproduciendo;
  final bool parado;
  final Duration? posicion;
  final Duration? duracion;

  /// Interpreta la respuesta de ECP.
  ///
  /// Viene así:
  ///
  ///     <player error="false" state="play">
  ///       <position>28998 ms</position>
  ///       <duration>1746346 ms</duration>
  ///     </player>
  ///
  /// Los tiempos traen la unidad pegada, así que hay que quedarse con el
  /// número. Y `state` puede ser play, pause, close, startup o none.
  static EstadoRoku? desdeXml(String xml) {
    final estado = RegExp(r'state="([^"]*)"').firstMatch(xml)?.group(1);
    if (estado == null) return null;
    // "close" y "none" significan que no hay nada cargado: eso es parado.
    final parado = estado == 'close' || estado == 'none';
    return EstadoRoku(
      reproduciendo: estado == 'play',
      parado: parado,
      posicion: _tiempo(xml, 'position'),
      duracion: _tiempo(xml, 'duration'),
    );
  }

  static Duration? _tiempo(String xml, String etiqueta) {
    final m = RegExp('<$etiqueta>([^<]*)</$etiqueta>').firstMatch(xml);
    final crudo = m?.group(1)?.trim();
    if (crudo == null || crudo.isEmpty) return null;
    // "28998 ms" → 28998. Se toma solo la parte numérica del principio.
    final num = RegExp(r'^(\d+)').firstMatch(crudo)?.group(1);
    if (num == null) return null;
    final ms = int.tryParse(num);
    if (ms == null || ms <= 0) return null;
    return Duration(milliseconds: ms);
  }
}
