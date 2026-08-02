import 'dart:async';
import 'dart:io';

import 'package:dlna_dart/dlna.dart';
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
  final List<RawDatagramSocket> _sockets = [];
  Timer? _reenvio;
  bool _parado = false;

  /// Aparatos encontrados, tal cual los publica el paquete.
  Stream<Map<String, DLNADevice>> get devices => _gestor.devices.stream;

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
        try {
          // Atado a la direccion CONCRETA de esta placa: asi el sistema no
          // puede elegir otra por su cuenta, que es el fallo de origen.
          final socket = await RawDatagramSocket.bind(direccion, 0);
          socket.multicastHops = 4;
          try {
            socket.joinMulticast(destino, placa);
          } catch (_) {
            // Algunas placas no admiten unirse al grupo. Igual sirven para
            // mandar la pregunta y recibir la respuesta directa, que es como
            // contesta la mayoria de los aparatos.
          }
          socket.listen((evento) {
            if (evento != RawSocketEvent.read) return;
            final datos = socket.receive();
            if (datos == null) return;
            try {
              _gestor.onMessage(String.fromCharCodes(datos.data).trim());
            } catch (e) {
              logger.warning('Respuesta de descubrimiento ilegible', e);
            }
          });
          _sockets.add(socket);
        } catch (e) {
          logger.warning(
              'No se pudo escuchar por ${placa.name} (${direccion.address})', e);
        }
      }
    }

    if (_sockets.isEmpty) {
      logger.warning('Sin ninguna placa de red util para buscar aparatos');
      return;
    }
    logger.info('Buscando aparatos por ${_sockets.length} placa(s) de red');

    _preguntar(destino);
    // Se repite: los mensajes multicast se pierden sin aviso, y un aparato que
    // recien se enciende no contesta a la primera.
    _reenvio = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_parado) return;
      _preguntar(destino);
    });
  }

  void _preguntar(InternetAddress destino) {
    // Se pregunta por los dos tipos que sirven para reproducir video, y por
    // todo. Algunos aparatos solo contestan a uno de los tres.
    const objetivos = [
      'urn:schemas-upnp-org:device:MediaRenderer:1',
      'urn:schemas-upnp-org:service:AVTransport:1',
      'ssdp:all',
    ];
    for (final socket in _sockets) {
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
    if (!_gestor.devices.isClosed) _gestor.devices.close();
  }
}
