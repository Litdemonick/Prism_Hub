import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:prismhub/utils/log.dart';

/// Habla con un Chromecast / Google TV.
///
/// Por qué existe: el casteo que ya andaba es DLNA, y el Chromecast NO habla
/// DLNA. Son dos protocolos distintos: aparece en la búsqueda de la red igual
/// que un televisor, pero al mandarle el vídeo por DLNA no pasa nada, que es de
/// donde salía el "no se pudo enviar la señal" al elegirlo.
///
/// El protocolo es CASTv2: mensajes protobuf con un largo de cuatro bytes
/// adelante, sobre TLS al puerto 8009.
///
/// El protobuf se arma y se lee A MANO en vez de traer un generador: el esquema
/// del mensaje son siete campos y no cambia nunca, así que la alternativa era
/// sumar una dependencia y un paso de generación de código para esto solo.
/// Medido contra un aparato real antes de escribir nada de esto.
class ChromecastCliente {
  ChromecastCliente(this.host, {this.puerto = 8009});

  final String host;
  final int puerto;

  static const _nsConexion = 'urn:x-cast:com.google.cast.tp.connection';
  static const _nsLatido = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const _nsReceptor = 'urn:x-cast:com.google.cast.receiver';
  static const _nsMedios = 'urn:x-cast:com.google.cast.media';

  /// El "Default Media Receiver" de Google: el reproductor genérico que trae
  /// cualquier aparato con Cast. No hace falta registrar ninguna app propia.
  static const _appMedios = 'CC1AD845';

  SecureSocket? _socket;
  Timer? _latido;
  int _pedido = 0;
  final _pendiente = BytesBuilder();

  /// Con quién se habla dentro del aparato una vez lanzado el receptor. Hasta
  /// que no llega, solo se le puede hablar al receptor general.
  String? _transporte;
  int? _sesionMedios;

  /// Último estado informado por el aparato.
  final estado = _EstadoCast();

  final _alCambiar = StreamController<_EstadoCast>.broadcast();

  /// Avisa cada vez que llega un estado nuevo del aparato.
  Stream<_EstadoCast> get cambios => _alCambiar.stream;

  bool get conectado => _socket != null;

  // ─── conexión ─────────────────────────────────────────────────────────────

  Future<bool> conectar() async {
    try {
      _socket = await SecureSocket.connect(
        host,
        puerto,
        // El aparato presenta un certificado propio, firmado por Google pero no
        // por una autoridad del sistema. Se acepta a propósito: es un aparato
        // de la red local que el usuario acaba de elegir de una lista.
        onBadCertificate: (_) => true,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      logger.warning('No se pudo conectar con el Chromecast $host', e);
      return false;
    }

    _socket!.listen(
      _recibir,
      onError: (Object e) {
        logger.warning('Se cortó la conexión con el Chromecast', e);
        _cerrarSocket();
      },
      onDone: _cerrarSocket,
      cancelOnError: true,
    );

    _mandar(_nsConexion, {'type': 'CONNECT'});
    // El aparato CORTA la conexión si no recibe señales de vida. Cada cinco
    // segundos es lo que espera el protocolo.
    _latido?.cancel();
    _latido = Timer.periodic(const Duration(seconds: 5), (_) {
      _mandar(_nsLatido, {'type': 'PING'});
    });
    return true;
  }

  /// Lanza el reproductor de medios y espera a poder hablarle.
  ///
  /// Devuelve false si el aparato no llegó a abrirlo — por ejemplo, si alguien
  /// lo está usando y rechaza la petición.
  Future<bool> abrirReproductor() async {
    if (_socket == null) return false;
    _mandar(_nsReceptor, {
      'type': 'LAUNCH',
      'appId': _appMedios,
      'requestId': ++_pedido,
    });
    // Se espera a que el aparato diga por dónde se le habla al reproductor.
    // Tarda: tiene que cambiar de aplicación en la pantalla.
    final hasta = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(hasta)) {
      if (_transporte != null) {
        // Hay que presentarse TAMBIÉN ante el reproductor, no alcanza con
        // haberlo hecho ante el aparato: son dos destinatarios distintos.
        _mandar(_nsConexion, {'type': 'CONNECT'}, destino: _transporte);
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    logger.warning('El Chromecast no abrió el reproductor de medios');
    return false;
  }

  // ─── control ──────────────────────────────────────────────────────────────

  /// Manda el vídeo al aparato y lo pone a reproducir.
  Future<void> cargar({
    required String url,
    required String titulo,
    String mime = 'video/mp4',
    String? portada,
    Duration desde = Duration.zero,
  }) async {
    if (_transporte == null) return;
    _mandar(
      _nsMedios,
      {
        'type': 'LOAD',
        'requestId': ++_pedido,
        'autoplay': true,
        if (desde > Duration.zero) 'currentTime': desde.inSeconds,
        'media': {
          'contentId': url,
          'contentType': mime,
          // LIVE deja la barra sin duración; BUFFERED es lo que corresponde
          // para un episodio con principio y fin.
          'streamType': 'BUFFERED',
          'metadata': {
            'type': 0,
            'metadataType': 0,
            'title': titulo,
            if (portada != null && portada.isNotEmpty)
              'images': [
                {'url': portada}
              ],
          },
        },
      },
      destino: _transporte,
    );
  }

  Future<void> reproducir() async => _comandoMedios('PLAY');
  Future<void> pausar() async => _comandoMedios('PAUSE');
  Future<void> parar() async => _comandoMedios('STOP');

  Future<void> irA(Duration donde) async {
    if (_transporte == null || _sesionMedios == null) return;
    _mandar(
      _nsMedios,
      {
        'type': 'SEEK',
        'requestId': ++_pedido,
        'mediaSessionId': _sesionMedios,
        'currentTime': donde.inSeconds,
      },
      destino: _transporte,
    );
  }

  /// Volumen del aparato, de 0 a 1.
  Future<void> volumen(double nivel) async {
    _mandar(_nsReceptor, {
      'type': 'SET_VOLUME',
      'requestId': ++_pedido,
      'volume': {'level': nivel.clamp(0.0, 1.0)},
    });
  }

  /// Pide el estado del reproductor. La respuesta llega por [cambios].
  Future<void> pedirEstado() async {
    if (_transporte == null) return;
    _mandar(
      _nsMedios,
      {'type': 'GET_STATUS', 'requestId': ++_pedido},
      destino: _transporte,
    );
  }

  Future<void> _comandoMedios(String tipo) async {
    if (_transporte == null || _sesionMedios == null) return;
    _mandar(
      _nsMedios,
      {
        'type': tipo,
        'requestId': ++_pedido,
        'mediaSessionId': _sesionMedios,
      },
      destino: _transporte,
    );
  }

  Future<void> desconectar({bool cerrarReproductor = true}) async {
    _latido?.cancel();
    _latido = null;
    try {
      if (cerrarReproductor && _socket != null) {
        // STOP del receptor cierra la aplicación en la pantalla y devuelve el
        // aparato a su inicio, en vez de dejar el episodio congelado ahí.
        _mandar(_nsReceptor, {'type': 'STOP', 'requestId': ++_pedido});
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } catch (_) {}
    _cerrarSocket();
  }

  void _cerrarSocket() {
    _latido?.cancel();
    _latido = null;
    _transporte = null;
    _sesionMedios = null;
    final s = _socket;
    _socket = null;
    try {
      s?.destroy();
    } catch (_) {}
  }

  // ─── mensajería ───────────────────────────────────────────────────────────

  void _mandar(String espacio, Map<String, dynamic> carga, {String? destino}) {
    final s = _socket;
    if (s == null) return;
    try {
      s.add(_armar(
        origen: 'sender-0',
        destino: destino ?? 'receiver-0',
        espacio: espacio,
        carga: jsonEncode(carga),
      ));
    } catch (e) {
      logger.warning('No se pudo hablarle al Chromecast', e);
    }
  }

  void _recibir(List<int> datos) {
    _pendiente.add(datos);
    var buf = _pendiente.toBytes();
    // Los mensajes vienen pegados y pueden llegar partidos: se procesa mientras
    // haya uno entero y se guarda el resto para la próxima tanda.
    while (buf.length >= 4) {
      final largo = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
      if (largo <= 0 || buf.length < 4 + largo) break;
      final mensaje = _leer(Uint8List.sublistView(buf, 4, 4 + largo));
      buf = Uint8List.sublistView(buf, 4 + largo);
      if (mensaje == null) continue;
      // Envuelto: un mensaje con una forma que no esperábamos no puede
      // llevarse puesta la conexión entera. Esto corre dentro del callback del
      // socket, así que una excepción acá no la atrapa nadie y se pierde el
      // aparato en el medio de la reproducción.
      try {
        _interpretar(mensaje.espacio, mensaje.carga);
      } catch (e) {
        logger.warning('Mensaje del Chromecast con forma inesperada', e);
      }
    }
    _pendiente.clear();
    _pendiente.add(buf);
  }

  void _interpretar(String espacio, String carga) {
    if (espacio == _nsLatido) {
      // PING del aparato: hay que contestarle o corta.
      if (carga.contains('"PING"')) _mandar(_nsLatido, {'type': 'PONG'});
      return;
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(carga) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (espacio == _nsReceptor) {
      // OJO: "status" NO siempre es un objeto. Al pedir abrir el reproductor,
      // el aparato contesta {"type":"LAUNCH_STATUS","status":"USER_ALLOWED"},
      // con status como TEXTO. Convertirlo a mapa a ciegas revienta ahí — pasó
      // en la prueba contra el aparato real, justo en el paso de abrirlo.
      final estadoRecep = json['status'];
      if (estadoRecep is! Map) return;
      final apps = estadoRecep['applications'];
      if (apps is List) {
        for (final a in apps) {
          if (a is Map && a['appId'] == _appMedios) {
            _transporte = a['transportId']?.toString();
            break;
          }
        }
      }
      final vol = estadoRecep['volume'];
      if (vol is Map && vol['level'] is num) {
        estado.volumen = (vol['level'] as num).toDouble();
        _alCambiar.add(estado);
      }
      return;
    }

    if (espacio == _nsMedios) {
      final lista = json['status'];
      if (lista is! List || lista.isEmpty) return;
      final m = lista.first;
      if (m is! Map) return;
      if (m['mediaSessionId'] is int) _sesionMedios = m['mediaSessionId'] as int;
      final p = m['playerState']?.toString();
      if (p != null) {
        estado.reproduciendo = p == 'PLAYING';
        // BUFFERING es "todavía cargando", no "en pausa": mostrarlo como pausa
        // haría creer que alguien lo paró.
        estado.cargando = p == 'BUFFERING';
        estado.parado = p == 'IDLE';
      }
      if (m['currentTime'] is num) {
        estado.posicion =
            Duration(milliseconds: ((m['currentTime'] as num) * 1000).round());
      }
      final medios = m['media'];
      final dur = medios is Map ? medios['duration'] : null;
      if (dur is num && dur > 0) {
        estado.duracion = Duration(milliseconds: (dur * 1000).round());
      }
      _alCambiar.add(estado);
    }
  }

  void dispose() {
    _cerrarSocket();
    if (!_alCambiar.isClosed) _alCambiar.close();
  }

  // ─── protobuf, a mano ─────────────────────────────────────────────────────

  static void _varint(BytesBuilder b, int v) {
    while (v > 0x7f) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  static void _campoTexto(BytesBuilder b, int campo, String s) {
    final bytes = utf8.encode(s);
    _varint(b, (campo << 3) | 2);
    _varint(b, bytes.length);
    b.add(bytes);
  }

  static void _campoVarint(BytesBuilder b, int campo, int v) {
    _varint(b, (campo << 3) | 0);
    _varint(b, v);
  }

  /// Arma un CastMessage con su largo de cuatro bytes adelante.
  ///
  /// Campos, en orden: 1 versión, 2 origen, 3 destino, 4 espacio de nombres,
  /// 5 tipo de carga (0 = texto), 6 la carga.
  static Uint8List _armar({
    required String origen,
    required String destino,
    required String espacio,
    required String carga,
  }) {
    final b = BytesBuilder();
    _campoVarint(b, 1, 0);
    _campoTexto(b, 2, origen);
    _campoTexto(b, 3, destino);
    _campoTexto(b, 4, espacio);
    _campoVarint(b, 5, 0);
    _campoTexto(b, 6, carga);
    final cuerpo = b.toBytes();
    final salida = BytesBuilder();
    salida.add([
      (cuerpo.length >> 24) & 0xff,
      (cuerpo.length >> 16) & 0xff,
      (cuerpo.length >> 8) & 0xff,
      cuerpo.length & 0xff,
    ]);
    salida.add(cuerpo);
    return salida.toBytes();
  }

  static ({String espacio, String carga})? _leer(Uint8List cuerpo) {
    var i = 0;
    var espacio = '';
    var carga = '';
    int leerVarint() {
      var r = 0, desp = 0;
      while (i < cuerpo.length) {
        final b = cuerpo[i++];
        r |= (b & 0x7f) << desp;
        if (b & 0x80 == 0) break;
        desp += 7;
      }
      return r;
    }

    while (i < cuerpo.length) {
      final tag = leerVarint();
      final campo = tag >> 3;
      final tipo = tag & 7;
      if (tipo == 0) {
        leerVarint();
      } else if (tipo == 2) {
        final largo = leerVarint();
        if (i + largo > cuerpo.length) return null;
        final texto =
            utf8.decode(cuerpo.sublist(i, i + largo), allowMalformed: true);
        i += largo;
        if (campo == 4) espacio = texto;
        if (campo == 6) carga = texto;
      } else {
        // Un tipo que no usamos: no se puede saber cuánto ocupa, así que se
        // descarta el mensaje entero en vez de leer basura.
        return null;
      }
    }
    return (espacio: espacio, carga: carga);
  }
}

/// Lo último que informó el aparato.
class _EstadoCast {
  bool reproduciendo = false;
  bool cargando = false;
  bool parado = false;
  Duration posicion = Duration.zero;
  Duration duracion = Duration.zero;
  double volumen = 1;
}
