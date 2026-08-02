import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dlna_dart/dlna.dart';
import 'package:prismhub/utils/cast_aparato.dart';
import 'package:prismhub/utils/log.dart';

// Busca aparatos DLNA en la red.
//
// Existe porque el buscador que trae dlna_dart no encuentra nada en Windows,
// aunque el mismo televisor aparezca al toque desde el telefono. Son dos fallos
// distintos, los dos confirmados leyendo su codigo:
//
//  1. Se une al grupo multicast SIN decir por que placa de red. En un telefono
//     hay una sola y sale bien; una PC con Windows suele tener varias
//     (Hyper-V, VirtualBox, VMware, WSL, VPN), y ahi Windows elige por su
//     cuenta — muy seguido una virtual, que no llega a ningun lado. La
//     busqueda sale por una placa que no toca la red de casa.
//
//  2. Lee la respuesta con un receive() suelto JUSTO despues de mandar la
//     pregunta, en el mismo instante. Los aparatos tardan decenas o cientos de
//     milisegundos en contestar, asi que en ese momento no hay nada para leer
//     casi nunca; ademas se lee UNA sola respuesta cada tres segundos, cuando
//     una red con varios aparatos contesta varias de golpe.
//
// Aca en cambio se manda la pregunta por CADA placa de red y se escucha de
// forma continua. El analisis de las respuestas se reusa del propio paquete
// (DeviceManager.onMessage), que eso si funciona bien.
class CastDiscovery {
  static const _ipMulticast = '239.255.255.250';
  static const _puerto = 1900;

  final DeviceManager _gestor = DeviceManager();

  /// Todos los sockets abiertos, para poder cerrarlos al terminar.
  final List<RawDatagramSocket> _sockets = [];

  /// Solo los que sirven para PREGUNTAR. Los que escuchan en el puerto 1900 no
  /// se usan para mandar: ahi el puerto de origen tendria que ser el 1900 y
  /// varios aparatos contestan mal a eso.
  final List<RawDatagramSocket> _preguntadores = [];
  Timer? _reenvio;
  bool _parado = false;

  /// Aparatos encontrados, tal cual los publica el paquete.
  Stream<Map<String, DLNADevice>> get devices => _gestor.devices.stream;

  /// Solo los que de verdad pueden reproducir vídeo, ya clasificados.
  ///
  /// La búsqueda encuentra de todo: medido en una red real, de cinco aparatos
  /// solo dos servían — los otros eran el router y dos Chromecast, que
  /// aparecen igual pero no hablan DLNA. Elegir uno de esos terminaba en "no
  /// se pudo enviar la señal", y desde afuera parecía un fallo del app.
  ///
  /// Para saber qué es cada uno hay que bajar su descripción, así que se hace
  /// una sola vez por aparato y se recuerda.
  Stream<List<AparatoDeCasteo>> get aparatos => _aparatos.stream;

  final _aparatos = StreamController<List<AparatoDeCasteo>>.broadcast();
  final Map<String, AparatoDeCasteo> _clasificados = {};
  final Set<String> _yaMirados = {};

  Future<void> _clasificar(Map<String, DLNADevice> encontrados) async {
    var huboCambio = false;
    for (final e in encontrados.entries) {
      if (!_yaMirados.add(e.key)) continue;
      final a = await clasificarBajando(e.value, _bajarDescripcion);
      if (a == null) {
        logger.info('Se descarta ${e.value.info.friendlyName}: no reproduce');
        continue;
      }
      // Por identificador: el mismo televisor aparece una vez por cada placa
      // de red por la que contestó, y en la lista tiene que salir una sola.
      if (_clasificados.containsKey(a.id)) continue;
      _clasificados[a.id] = a;
      huboCambio = true;
      logger.info('Aparato util: ${describir(a)}');
    }
    if (huboCambio && !_aparatos.isClosed) {
      _aparatos.add(_clasificados.values.toList());
    }
  }

  static Future<String> _bajarDescripcion(Uri base) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(base);
      final res = await req.close().timeout(const Duration(seconds: 6));
      return await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 6));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> start() async {
    _parado = false;
    final destino = InternetAddress(_ipMulticast);

    // Una placa de red puede fallar sola (una VPN caida, una virtual sin
    // enlace) sin que eso invalide a las demas, asi que cada una va en su
    // propio try.
    List<NetworkInterface> placas = const [];
    try {
      placas = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
    } catch (e) {
      logger.warning('No se pudieron listar las placas de red', e);
    }

    for (final placa in placas) {
      for (final direccion in placa.addresses) {
        // 1) El socket con el que se PREGUNTA, en un puerto cualquiera.
        //
        // Atado a la direccion CONCRETA de esta placa: asi el sistema no puede
        // elegir otra por su cuenta, que es el fallo de origen. Por aca llegan
        // las respuestas directas a nuestra pregunta.
        final preguntador = await _escuchar(direccion, 0, placa, destino);
        if (preguntador != null) _preguntadores.add(preguntador);

        // 2) El socket que ESCUCHA los anuncios, en el puerto 1900.
        //
        // Los aparatos no solo contestan cuando se les pregunta: tambien
        // anuncian su presencia cada tanto, al grupo y al puerto 1900. Eso no
        // llegaba: unirse al grupo desde un puerto cualquiera no alcanza,
        // porque el puerto de destino tiene que coincidir. Faltaba justamente
        // el camino que sirve cuando la respuesta directa no vuelve — por
        // ejemplo, con el cortafuegos filtrando lo que entra sin haber sido
        // pedido, que es lo habitual en Windows.
        //
        // Puede fallar si otro programa ya tiene ese puerto tomado (el propio
        // servicio de descubrimiento de Windows suele tenerlo). No es grave:
        // queda el camino de arriba.
        await _escuchar(direccion, _puerto, placa, destino);
      }
    }

    if (_preguntadores.isEmpty) {
      logger.warning('Sin ninguna placa de red util para buscar aparatos');
      return;
    }
    logger.info('Buscando aparatos: ${_preguntadores.length} placa(s), '
        '${_sockets.length} socket(s)');

    // Cada vez que aparece alguien nuevo se averigua QUE es.
    _gestor.devices.stream.listen(
      (m) => unawaited(_clasificar(m)),
      onError: (Object e) => logger.warning('Fallo clasificando', e),
    );

    _preguntar(destino);
    // Se repite: los mensajes multicast se pierden sin aviso, y un aparato que
    // recien se enciende no contesta a la primera.
    _reenvio = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_parado) return;
      _preguntar(destino);
    });
  }

  /// Abre un socket en una placa y puerto concretos y se pone a escuchar.
  ///
  /// Devuelve null si esa combinación no se pudo usar — una placa que se cayó,
  /// un puerto ya tomado por otro programa. Que una falle no invalida a las
  /// demás, así que nunca propaga el error.
  Future<RawDatagramSocket?> _escuchar(
    InternetAddress direccion,
    int puerto,
    NetworkInterface placa,
    InternetAddress grupo,
  ) async {
    try {
      final socket = await RawDatagramSocket.bind(
        direccion,
        puerto,
        // Imprescindible en el 1900: ahí casi siempre hay algo más escuchando
        // (el propio servicio de Windows, otro reproductor), y sin esto el
        // enlace falla y se pierde el camino de los anuncios.
        reuseAddress: true,
      );
      socket.multicastHops = 4;
      try {
        socket.joinMulticast(grupo, placa);
      } catch (_) {
        // Algunas placas no admiten unirse al grupo. El socket igual sirve
        // para preguntar y recibir la respuesta directa.
      }
      socket.listen((evento) {
        if (evento != RawSocketEvent.read) return;
        final datos = socket.receive();
        if (datos == null) return;
        try {
          _gestor.onMessage(String.fromCharCodes(datos.data).trim());
        } catch (e) {
          logger.warning('Mensaje de descubrimiento ilegible', e);
        }
      });
      _sockets.add(socket);
      return socket;
    } catch (e) {
      logger.info(
        'No se pudo escuchar por ${placa.name} '
        '(${direccion.address}:$puerto): $e',
      );
      return null;
    }
  }

  void _preguntar(InternetAddress destino) {
    // Se pregunta por los dos tipos que sirven para reproducir video, y por
    // todo. Algunos aparatos solo contestan a uno de los tres.
    const objetivos = [
      'urn:schemas-upnp-org:device:MediaRenderer:1',
      'urn:schemas-upnp-org:service:AVTransport:1',
      'ssdp:all',
    ];
    for (final socket in _preguntadores) {
      for (final objetivo in objetivos) {
        final mensaje = 'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ipMulticast:$_puerto\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: $objetivo\r\n\r\n';
        try {
          socket.send(mensaje.codeUnits, destino, _puerto);
        } catch (e) {
          // Una placa que se cayo entre medio no debe frenar a las otras.
          logger.warning('No se pudo preguntar por una placa de red', e);
        }
      }
    }
  }

  void stop() {
    _parado = true;
    _reenvio?.cancel();
    _reenvio = null;
    for (final socket in _sockets) {
      try {
        socket.close();
      } catch (_) {}
    }
    _sockets.clear();
    _preguntadores.clear();
    if (!_gestor.devices.isClosed) _gestor.devices.close();
    if (!_aparatos.isClosed) _aparatos.close();
  }
}
