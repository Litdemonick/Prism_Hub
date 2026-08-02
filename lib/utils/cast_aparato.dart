import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:prismhub/utils/cast_chromecast.dart';
import 'package:prismhub/utils/cast_metadata.dart';
import 'package:prismhub/utils/log.dart';

/// Lo que el aparato informa sobre lo que está haciendo.
///
/// Se devuelve YA interpretado y no el XML crudo a propósito: DLNA y Chromecast
/// contestan cosas completamente distintas, y quien controla la reproducción no
/// tiene por qué saber cuál de los dos está del otro lado.
class EstadoAparato {
  EstadoAparato({
    required this.reproduciendo,
    required this.parado,
    this.posicion,
    this.duracion,
    this.velocidad,
    this.urlActual,
  });

  final bool reproduciendo;

  /// Parado de verdad (no en pausa): terminó, o alguien lo cortó desde el
  /// propio aparato.
  final bool parado;

  /// Null cuando el aparato no las informó en esta consulta — que no es lo
  /// mismo que cero, y confundirlos hacía saltar la barra al principio.
  final Duration? posicion;
  final Duration? duracion;

  /// Velocidad puesta en el aparato, si no es la normal ("2", "4"…).
  final String? velocidad;

  /// Lo que el aparato dice estar reproduciendo. Sirve para darse cuenta de que
  /// otro dispositivo le mandó otra cosa.
  final String? urlActual;
}

/// Un aparato al que se le puede mandar vídeo.
///
/// Existe para que el reproductor hable IGUAL con un televisor DLNA que con un
/// Chromecast, que son dos protocolos que no tienen nada que ver entre sí.
abstract class AparatoDeCasteo {
  /// Cómo se llama en la lista.
  String get nombre;

  /// Identifica al aparato para poder compararlos. No se usa el objeto en sí
  /// porque cada búsqueda crea instancias nuevas del mismo televisor.
  String get id;

  /// Para poder decirle al usuario con qué está hablando.
  bool get esChromecast;

  /// Deja el aparato listo. En DLNA no hace falta nada; el Chromecast tiene que
  /// abrir su conexión y lanzar el reproductor primero.
  Future<bool> preparar();

  Future<void> cargar({
    required String url,
    required String titulo,
    required String mime,
    String? portada,
  });

  Future<void> reproducir();
  Future<void> pausar();
  Future<void> parar();
  Future<void> irA(Duration donde);

  /// Volumen de 0 a 100.
  Future<void> ponerVolumen(int nivel);
  Future<int?> leerVolumen();

  /// Estado actual, o null si el aparato no contestó.
  Future<EstadoAparato?> leerEstado();

  /// Velocidad de reproducción. Devuelve si el aparato la aceptó: muchos solo
  /// admiten la normal.
  Future<bool> ponerVelocidad(int velocidad);

  /// Suelta la conexión. [pararAparato] en false cuando la reproducción ya no
  /// es nuestra y cortarla sería quitársela a otro.
  Future<void> soltar({bool pararAparato = true});
}

/// Un televisor o reproductor que habla DLNA.
///
/// Es un envoltorio delgado a propósito: hace exactamente lo mismo que hacía el
/// reproductor antes de que existiera esta interfaz, con las mismas consultas y
/// el mismo análisis de las respuestas. Así el casteo que ya funcionaba se
/// comporta igual que siempre.
class AparatoDlna implements AparatoDeCasteo {
  AparatoDlna(this.device);
  final DLNADevice device;

  @override
  String get nombre => device.info.friendlyName;

  @override
  String get id => device.info.URLBase;

  @override
  bool get esChromecast => false;

  @override
  Future<bool> preparar() async => true;

  @override
  Future<void> cargar({
    required String url,
    required String titulo,
    required String mime,
    String? portada,
  }) async {
    // Con ficha DIDL completa: sin protocolInfo, Kodi anota "invalid protocol
    // info ':::'" y tiene que adivinar el formato. Ver cast_metadata.dart.
    await castearConMetadata(device, url, titulo: titulo, mime: mime);
    await device.play();
  }

  @override
  Future<void> reproducir() => device.play();

  @override
  Future<void> pausar() => device.pause();

  @override
  Future<void> parar() => device.stop();

  @override
  Future<void> irA(Duration donde) async {
    final h = donde.inHours.toString().padLeft(2, '0');
    final m = (donde.inMinutes % 60).toString().padLeft(2, '0');
    final s = (donde.inSeconds % 60).toString().padLeft(2, '0');
    await device.seek('$h:$m:$s');
  }

  @override
  Future<void> ponerVolumen(int nivel) => device.volume(nivel.clamp(0, 100));

  @override
  Future<int?> leerVolumen() async {
    final xml =
        await device.getVolume().timeout(const Duration(seconds: 4));
    final m = RegExp(r'<CurrentVolume>(\d+)</CurrentVolume>').firstMatch(xml);
    final v = int.tryParse(m?.group(1) ?? '');
    return v?.clamp(0, 100);
  }

  @override
  Future<EstadoAparato?> leerEstado() async {
    final transporte =
        await device.getTransportInfo().timeout(const Duration(seconds: 4));
    final reproduciendo = transporte.contains('PLAYING');
    final parado = transporte.contains('STOPPED') ||
        transporte.contains('NO_MEDIA_PRESENT');
    final velocidad = RegExp(r'<CurrentSpeed>([^<]+)</CurrentSpeed>')
        .firstMatch(transporte)
        ?.group(1)
        ?.trim();

    // Parado: no se le piden más datos. La posición que informe a esta altura
    // ya no dice nada útil, y son dos consultas de más al aparato.
    if (parado) {
      return EstadoAparato(
        reproduciendo: false,
        parado: true,
        velocidad: _velocidadUtil(velocidad),
      );
    }

    Duration? posicion;
    Duration? duracion;
    try {
      final crudo =
          await device.position().timeout(const Duration(seconds: 4));
      final p = PositionParser(crudo);
      final partes = p.AbsTime.split(':');
      if (partes.length >= 3) {
        posicion = Duration(
          hours: int.tryParse(partes[0]) ?? 0,
          minutes: int.tryParse(partes[1]) ?? 0,
          seconds: int.tryParse(partes[2]) ?? 0,
        );
        duracion = Duration(seconds: p.TrackDurationInt);
      }
    } catch (e) {
      // Que no informe la posición no invalida el resto: se devuelve lo que sí
      // se pudo leer en vez de dar la consulta entera por fallida.
      logger.info('El aparato no informó la posición: $e');
    }

    return EstadoAparato(
      reproduciendo: reproduciendo,
      parado: false,
      posicion: posicion,
      duracion: duracion,
      velocidad: _velocidadUtil(velocidad),
      urlActual: await _urlActual(),
    );
  }

  /// Lo que el aparato dice estar reproduciendo.
  ///
  /// Se pide aparte y sin hacer ruido si falla: no todos los aparatos
  /// implementan esta consulta, y sin ella lo único que se pierde es darse
  /// cuenta de que otro dispositivo tomó el televisor.
  Future<String?> _urlActual() async {
    try {
      final info =
          await device.getMediaInfo().timeout(const Duration(seconds: 4));
      final m =
          RegExp(r'<CurrentURI>([^<]*)</CurrentURI>').firstMatch(info);
      final u = m?.group(1)?.trim();
      return (u == null || u.isEmpty) ? null : u.replaceAll('&amp;', '&');
    } catch (_) {
      return null;
    }
  }

  static String? _velocidadUtil(String? v) {
    if (v == null || v.isEmpty || v == '1' || v == '1.0') return null;
    return v;
  }

  @override
  Future<bool> ponerVelocidad(int velocidad) =>
      reproducirAVelocidad(device, velocidad);

  @override
  Future<void> soltar({bool pararAparato = true}) async {
    if (pararAparato) await device.stop();
  }
}

/// Un Chromecast, Google TV o cualquier aparato con Cast integrado.
class AparatoChromecast implements AparatoDeCasteo {
  AparatoChromecast({
    required this.host,
    required String nombre,
  }) : _nombre = nombre;

  final String host;
  final String _nombre;
  ChromecastCliente? _cliente;

  @override
  String get nombre => _nombre;

  @override
  String get id => 'chromecast://$host';

  @override
  bool get esChromecast => true;

  @override
  Future<bool> preparar() async {
    final c = ChromecastCliente(host);
    if (!await c.conectar()) return false;
    if (!await c.abrirReproductor()) {
      await c.desconectar();
      return false;
    }
    _cliente = c;
    return true;
  }

  @override
  Future<void> cargar({
    required String url,
    required String titulo,
    required String mime,
    String? portada,
  }) async {
    await _cliente?.cargar(
      url: url,
      titulo: titulo,
      mime: mime,
      portada: portada,
    );
  }

  @override
  Future<void> reproducir() async => _cliente?.reproducir();

  @override
  Future<void> pausar() async => _cliente?.pausar();

  @override
  Future<void> parar() async => _cliente?.parar();

  @override
  Future<void> irA(Duration donde) async => _cliente?.irA(donde);

  @override
  Future<void> ponerVolumen(int nivel) async =>
      _cliente?.volumen(nivel.clamp(0, 100) / 100);

  @override
  Future<int?> leerVolumen() async {
    final c = _cliente;
    if (c == null) return null;
    return (c.estado.volumen * 100).round().clamp(0, 100);
  }

  @override
  Future<EstadoAparato?> leerEstado() async {
    final c = _cliente;
    if (c == null || !c.conectado) return null;
    // El Chromecast avisa solo cada vez que algo cambia, así que su estado ya
    // está al día. Se le pide igual de tanto en tanto para que la barra siga
    // avanzando aunque no haya novedades.
    await c.pedirEstado();
    final e = c.estado;
    return EstadoAparato(
      reproduciendo: e.reproduciendo,
      // Cargando no es parado: tratarlo como parado cortaría la transmisión
      // justo mientras el aparato llena el buffer.
      parado: e.parado && !e.cargando,
      posicion: e.posicion,
      duracion: e.duracion > Duration.zero ? e.duracion : null,
      urlActual: null,
    );
  }

  @override
  Future<bool> ponerVelocidad(int velocidad) async {
    // El receptor de medios de Google no admite cambiar la velocidad desde el
    // mando. Se dice que no en vez de mandar algo que va a ignorar.
    return velocidad == 1;
  }

  @override
  Future<void> soltar({bool pararAparato = true}) async {
    final c = _cliente;
    _cliente = null;
    if (c == null) return;
    await c.desconectar(cerrarReproductor: pararAparato);
    c.dispose();
  }
}

/// Decide qué clase de aparato es, mirando su descripción.
///
/// Un Chromecast se anuncia en la red igual que cualquier otro aparato, pero su
/// descripción dice `dial-multiscreen`. Y el router, que también aparece, no
/// sirve para nada de esto: no expone AVTransport ni es un Chromecast.
///
/// Devuelve null cuando el aparato no puede reproducir vídeo — así no llega a
/// la lista y nadie lo elige para que después "no se pueda enviar la señal".
AparatoDeCasteo? clasificar(DLNADevice device, String descripcionXml) {
  final xml = descripcionXml;
  final esDial = xml.contains('dial-multiscreen-org') ||
      xml.contains('urn:dial-multiscreen-org:device:dial');
  if (esDial) {
    final host = Uri.tryParse(device.info.URLBase)?.host;
    if (host == null || host.isEmpty) return null;
    return AparatoChromecast(host: host, nombre: device.info.friendlyName);
  }
  if (xml.contains('AVTransport')) return AparatoDlna(device);
  return null;
}

/// Igual que [clasificar] pero bajando la descripción del aparato.
Future<AparatoDeCasteo?> clasificarBajando(
  DLNADevice device,
  Future<String> Function(Uri) bajar,
) async {
  final base = Uri.tryParse(device.info.URLBase);
  if (base == null) return null;
  try {
    return clasificar(device, await bajar(base));
  } catch (e) {
    logger.info('No se pudo leer la descripción de ${device.info.URLBase}: $e');
    return null;
  }
}

/// Para las pruebas y el registro.
String describir(AparatoDeCasteo a) =>
    '${a.nombre} (${a.esChromecast ? "Chromecast" : "DLNA"})';
