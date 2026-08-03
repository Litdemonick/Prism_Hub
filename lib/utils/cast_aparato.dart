import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:flutter/foundation.dart';
import 'package:prismhub/utils/cast_chromecast.dart';
import 'package:prismhub/utils/cast_log.dart';
import 'package:prismhub/utils/cast_metadata.dart';
import 'package:prismhub/utils/cast_roku.dart';
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

  /// Marca, modelo, protocolo elegido y por dónde se le habla, en una línea.
  ///
  /// Para el registro: tres aparatos fallan de tres formas distintas y sin
  /// saber cuál es cuál y por qué camino se le habló, leer el archivo después
  /// no sirve de nada. Es lo único de todo el casteo que identifica al aparato:
  /// del contenido no se registra nada (ver CastLog).
  String get ficha;

  /// Si se le puede pedir "andá al minuto X".
  ///
  /// No todos pueden: el mando de Roku adelanta a saltos pero no sabe ir a un
  /// punto exacto. Preguntarlo antes evita quedarse esperando una respuesta
  /// que no va a llegar, y permite decirlo en vez de fingir que se mandó.
  bool get permiteSaltar => true;

  /// Deja el aparato listo. En DLNA no hace falta nada; el Chromecast tiene que
  /// abrir su conexión y lanzar el reproductor primero.
  Future<bool> preparar();

  /// [puedeSaltar] es false cuando lo que se le manda es un flujo que se arma
  /// sobre la marcha (el reempaquetado a MPEG-TS): ahí no hay largo ni bytes a
  /// los que reposicionarse, y decirle lo contrario hace que el aparato intente
  /// un salto imposible. Ver cast_metadata.dart.
  Future<void> cargar({
    required String url,
    required String titulo,
    required String mime,
    String? portada,
    bool puedeSaltar = true,
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

  /// Si ya se avisó de que este aparato no informa la posición de forma
  /// legible. Ver el catch de leerEstado: se pregunta una vez por segundo.
  bool _avisoDePosicionDado = false;

  @override
  String get nombre => device.info.friendlyName;

  @override
  String get id => device.info.URLBase;

  @override
  bool get esChromecast => false;

  @override
  String get ficha => '${device.info.friendlyName} — DLNA — '
      '${device.info.deviceType} — ${device.info.URLBase}';

  @override
  bool get permiteSaltar => true;

  @override
  Future<bool> preparar() async {
    // Cuenta limpia del registro en cada envío. Al cambiar de episodio se reusa
    // ESTA misma instancia, así que sin esto el detalle de las primeras
    // consultas —que es justo lo que cuenta cómo arrancó— solo quedaba escrito
    // para el primer episodio de la sesión.
    _consultas = 0;
    _ultimoTransporte = null;
    return true;
  }

  @override
  Future<void> cargar({
    required String url,
    required String titulo,
    required String mime,
    String? portada,
    bool puedeSaltar = true,
  }) async {
    // Con ficha DIDL completa: sin protocolInfo, Kodi anota "invalid protocol
    // info ':::'" y tiene que adivinar el formato. Ver cast_metadata.dart.
    await castearConMetadata(device, url,
        titulo: titulo, mime: mime, puedeSaltar: puedeSaltar);
    final respuesta = await device.play();
    CastLog.paso('Play ← ${CastLog.respuestaUpnp(respuesta)}');
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

  /// Un "hh:mm:ss" de DLNA, o null si el aparato no contesto un tiempo.
  ///
  /// Devuelve null tambien con "NOT_IMPLEMENTED", que es lo que contestan los
  /// aparatos que no llevan esa cuenta. Tratarlo como cero hacia que la barra
  /// volviera al principio en cada consulta.
  @visibleForTesting
  static Duration? tiempo(String crudo) => _tiempo(crudo);

  static Duration? _tiempo(String crudo) {
    final partes = crudo.trim().split(':');
    if (partes.length < 3) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    // Los segundos pueden venir con decimales ("12.500").
    final s = double.tryParse(partes[2]);
    if (h == null || m == null || s == null) return null;
    return Duration(
        milliseconds: ((h * 3600 + m * 60) * 1000 + (s * 1000).round()));
  }

  /// Lo último que informó GetTransportInfo, y cuántas veces se preguntó.
  ///
  /// La consulta corre cada segundo: registrarlas todas llenaría el archivo de
  /// líneas idénticas. Pero las PRIMERAS son justamente las que cuentan la
  /// historia —TRANSITIONING, NO_MEDIA_PRESENT, PLAYING…— así que se anotan
  /// enteras al principio y después solo cuando el aparato cambia de estado.
  String? _ultimoTransporte;
  int _consultas = 0;

  static const _consultasDetalladas = 15;

  @override
  Future<EstadoAparato?> leerEstado() async {
    final transporte =
        await device.getTransportInfo().timeout(const Duration(seconds: 4));
    final estado = RegExp(r'<CurrentTransportState>([^<]*)</CurrentTransportState>')
            .firstMatch(transporte)
            ?.group(1)
            ?.trim() ??
        'sin estado';
    if (++_consultas <= _consultasDetalladas || estado != _ultimoTransporte) {
      final motivo =
          RegExp(r'<CurrentTransportStatus>([^<]*)</CurrentTransportStatus>')
              .firstMatch(transporte)
              ?.group(1)
              ?.trim();
      CastLog.paso('GetTransportInfo #$_consultas: $estado'
          '${motivo == null || motivo == 'OK' ? '' : ' ($motivo)'}');
    }
    _ultimoTransporte = estado;
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
      // RelTime primero y AbsTime como respaldo.
      //
      // Antes se leia SOLO AbsTime, y muchos televisores no lo implementan:
      // contestan "NOT_IMPLEMENTED" o ceros ahi y ponen el dato bueno en
      // RelTime. Con esos, la barra se quedaba en 0:00 toda la reproduccion
      // aunque el video estuviera avanzando en la pantalla grande. RelTime es
      // el que el estandar da por obligatorio.
      posicion = _tiempo(p.RelTime) ?? _tiempo(p.AbsTime);
      // El largo, aparte y con su propia red.
      //
      // TrackDurationInt REVIENTA con lo que contestan algunos aparatos: uno
      // medido en vivo devuelve "0-2562047788015" ahí, y al intentar leerlo como
      // número la excepción se llevaba puesta TAMBIÉN la posición, que ya se
      // había leído bien tres líneas más arriba. Separándolo, un largo ilegible
      // deja de costar la posición.
      //
      // Y cero NO es una duracion, es "no lo se": un televisor que no sabe
      // cuanto dura contesta 00:00:00, y eso PISABA el largo real que la app ya
      // conocia de haber abierto el video antes de castear. Con largo cero la
      // barra queda sin recorrido: no se puede arrastrar ni ver por donde va.
      try {
        final largo = Duration(seconds: p.TrackDurationInt);
        if (largo > Duration.zero) duracion = largo;
      } catch (_) {
        // Sin largo utilizable: se conserva el que la app ya tenía.
      }
    } catch (e) {
      // Que no informe la posición no invalida el resto: se devuelve lo que sí
      // se pudo leer en vez de dar la consulta entera por fallida.
      //
      // Se avisa UNA sola vez por aparato y no en cada consulta. Se pregunta una
      // vez por segundo durante toda la reproducción, así que un aparato que
      // contesta algo raro llenaba el registro con cientos de líneas idénticas y
      // tapaba todo lo demás — medido: veinte minutos de casteo, más de mil
      // líneas iguales, y entre medio se perdían las que sí importaban.
      if (!_avisoDePosicionDado) {
        _avisoDePosicionDado = true;
        logger.info('El aparato no informa la posición de forma legible; se '
            'sigue sin ella y no se vuelve a avisar: $e');
      }
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
  String get ficha => '$_nombre — Chromecast (CASTv2) — $host:8009';

  @override
  bool get permiteSaltar => true;

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
    // El Chromecast no usa el flag de DLNA: su receptor decide solo. Se acepta
    // para cumplir la firma comun.
    bool puedeSaltar = true,
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

  /// Lo ultimo que el aparato dijo que salio mal, si dijo algo.
  String? get fallo => _cliente?.ultimoFallo;

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

/// Un Roku.
///
/// Habla lo suyo (ECP): HTTP plano, sin cifrado ni emparejamiento. Se le manda
/// el vídeo lanzando su reproductor de medios y se lo controla con pulsaciones
/// de mando a distancia.
class AparatoRoku implements AparatoDeCasteo {
  AparatoRoku({required this.host, required String nombre}) : _nombre = nombre;

  final String host;
  final String _nombre;
  late final RokuCliente _cliente = RokuCliente(host);

  @override
  String get nombre => _nombre;

  @override
  String get id => 'roku://$host';

  @override
  bool get esChromecast => false;

  @override
  String get ficha => '$_nombre — Roku (ECP) — $host:8060';

  /// ECP no tiene "ir al minuto X": el mando adelanta a saltos y nada más.
  @override
  bool get permiteSaltar => false;

  @override
  Future<bool> preparar() async {
    _cliente.reiniciarRegistro();
    return true;
  }

  @override
  Future<void> cargar({
    required String url,
    required String titulo,
    required String mime,
    String? portada,
    // El Roku tampoco lo usa: su protocolo (ECP) no tiene este concepto.
    bool puedeSaltar = true,
  }) async {
    final ok = await _cliente.cargar(url: url, titulo: titulo, mime: mime);
    if (!ok) throw StateError('El Roku no acepto el video');
  }

  // Play y Pause son la MISMA tecla del mando: alterna. Quien llama ya sabe en
  // que estado esta, asi que mandar la tecla hace lo correcto en los dos casos.
  @override
  Future<void> reproducir() => _cliente.alternarPausa();

  @override
  Future<void> pausar() => _cliente.alternarPausa();

  @override
  Future<void> parar() => _cliente.parar();

  @override
  Future<void> irA(Duration donde) async {
    // No se puede. Se deja constancia en vez de fallar en silencio.
    logger.info('El Roku no admite saltar a un punto exacto');
  }

  @override
  Future<void> ponerVolumen(int nivel) async {
    // ECP solo sube o baja de a un paso: no hay "poner en 40". Lo maneja el
    // controlador, que sabe si el usuario pidio subir o bajar.
  }

  @override
  Future<int?> leerVolumen() async => null;

  @override
  Future<EstadoAparato?> leerEstado() async {
    final e = await _cliente.estado();
    if (e == null) return null;
    return EstadoAparato(
      reproduciendo: e.reproduciendo,
      parado: e.parado,
      posicion: e.posicion,
      duracion: e.duracion,
    );
  }

  @override
  Future<bool> ponerVelocidad(int velocidad) async => velocidad == 1;

  @override
  Future<void> soltar({bool pararAparato = true}) async {
    if (pararAparato) await _cliente.parar();
  }
}

/// Decide qué clase de aparato es, con lo que YA se sabe de él.
///
/// No descarga nada: el paquete ya bajó la descripción del aparato para poder
/// darnos su nombre, y de paso dejó ahí su tipo y su lista de servicios. Eso
/// alcanza para saber si sirve.
///
/// Antes esto SÍ descargaba, y desde `URLBase` — que no es la dirección de la
/// descripción sino solo el origen (`http://ip:puerto`). Esa petición devolvía
/// otra cosa o directamente fallaba, así que se descartaban aparatos que
/// funcionaban perfectamente: dejaron de aparecer televisores que antes sí
/// salían en la lista.
///
/// Devuelve null cuando el aparato no puede reproducir vídeo — así no llega a
/// la lista y nadie lo elige para que después "no se pueda enviar la señal".
AparatoDeCasteo? clasificar(DLNADevice device) {
  final tipo = device.info.deviceType.toLowerCase();

  // Un Chromecast, Google TV o Android TV se anuncia como "dial". No habla
  // DLNA, así que va por el otro camino.
  if (tipo.contains('dial-multiscreen')) {
    final host = Uri.tryParse(device.info.URLBase)?.host;
    if (host == null || host.isEmpty) return null;
    return AparatoChromecast(host: host, nombre: device.info.friendlyName);
  }

  // Roku se anuncia con su propio tipo. No habla DLNA ni Cast: va por ECP.
  if (tipo.contains('roku')) {
    final host = Uri.tryParse(device.info.URLBase)?.host;
    if (host == null || host.isEmpty) return null;
    return AparatoRoku(host: host, nombre: device.info.friendlyName);
  }

  // Reproduce vídeo si expone AVTransport, que es el servicio con el que se le
  // manda y se le controla. El router, por ejemplo, aparece en la búsqueda pero
  // no lo tiene.
  final sirve = device.info.serviceList.any((s) {
    final servicio = '${s['serviceType'] ?? ''} ${s['serviceId'] ?? ''}';
    return servicio.toLowerCase().contains('avtransport');
  });
  if (sirve) return AparatoDlna(device);

  // Sin lista de servicios legible no se puede afirmar que NO sirva. Si dice
  // ser un reproductor, se deja pasar: es preferible ofrecer uno de más que
  // esconder el televisor de alguien.
  if (device.info.serviceList.isEmpty && tipo.contains('mediarenderer')) {
    return AparatoDlna(device);
  }
  return null;
}

/// Para las pruebas y el registro.
String describir(AparatoDeCasteo a) => a.ficha;
