import 'dart:async';
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

  /// Los que aparecieron pero NO se pueden usar, con el motivo.
  ///
  /// Antes se descartaban en silencio y la lista simplemente no los mostraba.
  /// Desde afuera eso es idéntico a que el aparato no exista, y ahí empieza el
  /// problema: el usuario ve su televisor encendido, la app no lo lista, y no
  /// hay forma de saber si falta buscar más, si hay que acercarse al router o si
  /// hay que abrir algo en la tele.
  ///
  /// La app SÍ sabe por qué no sirve —lo comprobó para descartarlo— y esa
  /// información se estaba tirando. Mostrarlo apagado con el motivo al lado
  /// convierte un silencio en una instrucción.
  Stream<List<AparatoDescartado>> get descartados => _descartados.stream;

  final _descartados = StreamController<List<AparatoDescartado>>.broadcast();
  final Map<String, AparatoDescartado> _noSirven = {};

  /// Descripciones ya pedidas, por su dirección (la cabecera LOCATION).
  ///
  /// El paquete baja la descripción del aparato CADA VEZ que le llega un
  /// mensaje suyo, sin guardarla en ningún lado. Y por acá le llegan muchos:
  /// se repregunta cada dos segundos, por cuatro tipos y por cada placa de
  /// red, y encima con `ssdp:all` un aparato contesta una vez por CADA
  /// servicio que expone. Todas esas respuestas traen la misma dirección y
  /// cada una disparaba una descarga entera.
  ///
  /// Medido en una red real: la descripción del router se pidió siete veces
  /// en media búsqueda —fallando las siete, y tardando lo suyo cada una—
  /// mientras la búsqueda entera dura diez segundos. Con esto se pide una
  /// vez por aparato y se termina.
  final Set<String> _ubicacionesPedidas = {};

  /// Cuántas veces falló la descripción de cada dirección.
  final Map<String, int> _fallos = {};

  /// Un fallo suelto puede ser el aparato ocupado justo en ese instante, así
  /// que se le da una segunda oportunidad. Dos seguidos ya es un aparato que
  /// no va a contestar, e insistir solo gasta el rato de búsqueda.
  static const _intentosPorAparato = 2;

  void _clasificar(Map<String, DLNADevice> encontrados) {
    var huboCambio = false;
    for (final e in encontrados.entries) {
      if (!_yaMirados.add(e.key)) continue;
      final a = clasificar(e.value);
      if (a == null) {
        final nombre = e.value.info.friendlyName;
        logger.info('No sirve para reproducir: $nombre '
            '(${e.value.info.deviceType})');
        // Se guarda igual, para poder mostrarlo apagado con el motivo.
        if (!_noSirven.containsKey(nombre)) {
          _noSirven[nombre] = AparatoDescartado(
            nombre: nombre,
            motivo: 'No reproduce vídeo',
          );
          if (!_descartados.isClosed) {
            _descartados.add(_noSirven.values.toList());
          }
        }
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
      _clasificar,
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
        _procesar(String.fromCharCodes(datos.data).trim());
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

  /// Atiende un mensaje de descubrimiento, sin repetir descargas.
  ///
  /// Se espera el resultado a propósito. Antes se llamaba sin esperarlo dentro
  /// de un try, y eso NO atrapa nada: el trabajo de verdad (bajar la
  /// descripción del aparato) pasa después, ya fuera del try. Un aparato que
  /// contestaba mal terminaba en el registro como error grave con su traza
  /// entera, una vez cada dos segundos — en una búsqueda de diez segundos
  /// llenaba el archivo y tapaba lo que sí importaba.
  Future<void> _procesar(String mensaje) async {
    if (_parado) return;
    final ubicacion = _ubicacionDe(mensaje);
    // Sin dirección no hay descripción que bajar; se pasa igual porque el
    // paquete puede sacar algo del mensaje.
    if (ubicacion != null && !_ubicacionesPedidas.add(ubicacion)) return;
    try {
      await _gestor.onMessage(mensaje);
    } catch (e) {
      if (ubicacion == null) {
        logger.info('Mensaje de descubrimiento ilegible: $e');
        return;
      }
      final fallos = (_fallos[ubicacion] ?? 0) + 1;
      _fallos[ubicacion] = fallos;
      if (fallos < _intentosPorAparato) {
        // Se lo saca de los pedidos para que el próximo anuncio lo reintente.
        _ubicacionesPedidas.remove(ubicacion);
        return;
      }
      // A nivel informativo y una sola vez: que un aparato de la red no sepa
      // describirse no es un fallo del app, y no hay nada que hacer con él.
      logger.info(
        'No dice qué es, se deja de insistir: $ubicacion ($e)',
      );
    }
  }

  /// La cabecera LOCATION del mensaje: dónde está la descripción del aparato.
  ///
  /// Se parte por el PRIMER dos puntos y nada más: el valor es una dirección
  /// web y trae los suyos propios ("http://…", y el del puerto).
  static String? _ubicacionDe(String mensaje) {
    for (final linea in mensaje.split('\n')) {
      final corte = linea.indexOf(':');
      if (corte < 0) continue;
      if (linea.substring(0, corte).trim().toUpperCase() != 'LOCATION') {
        continue;
      }
      final valor = linea.substring(corte + 1).trim();
      if (valor.isNotEmpty) return valor;
    }
    return null;
  }

  void _preguntar(InternetAddress destino) {
    // Se pregunta por los dos tipos que sirven para reproducir video, y por
    // todo. Algunos aparatos solo contestan a uno de los tres.
    const objetivos = [
      'urn:schemas-upnp-org:device:MediaRenderer:1',
      'urn:schemas-upnp-org:service:AVTransport:1',
      // Roku no contesta a los de UPnP: tiene el suyo.
      'roku:ecp',
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
    if (!_descartados.isClosed) _descartados.close();
  }
}

/// Un aparato que apareció en la búsqueda pero no se puede usar.
///
/// Se muestra en la lista apagado, con el motivo: el router de casa y los
/// aparatos cuyo receptor está cerrado se anuncian igual que uno bueno, y
/// esconderlos deja al usuario sin saber si buscar más o revisar el aparato.
class AparatoDescartado {
  const AparatoDescartado({required this.nombre, required this.motivo});
  final String nombre;
  final String motivo;
}
