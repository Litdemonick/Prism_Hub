import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Deja que el televisor se haga encontrar en la red, para no escribir la
/// dirección a mano.
///
/// ── Por qué existe ──────────────────────────────────────────────────────────
///
/// Para leer el registro del televisor desde otro aparato había que mirar una
/// dirección en la pantalla y escribirla entera en el otro. Se acortó todo lo
/// que se pudo —puerto fijo, código de cuatro— y sigue siendo escribir una IP
/// leyendo de lejos.
///
/// Con esto no hace falta: mientras el servidor está encendido, el televisor
/// contesta a quien pregunte «¿hay algún PrismHub por acá?». El teléfono o el
/// PC preguntan, lo encuentran y abren el registro de una.
///
/// ── Cómo, y por qué así ─────────────────────────────────────────────────────
///
/// Un mensaje UDP a toda la red y una respuesta. Nada más.
///
/// La alternativa «de manual» sería mDNS —el `.local` de toda la vida— pero en
/// Android pide código nativo y del otro lado depende de que el sistema sepa
/// resolver `.local`: Windows moderno sí, Linux solo con Avahi, y no hay forma
/// de saberlo de antemano. Esto son cuarenta líneas, funciona igual en las
/// cuatro plataformas y se puede leer entero.
///
/// ── Qué se anuncia, y qué NO ────────────────────────────────────────────────
///
/// Solo mientras el servidor está encendido, que se enciende a mano y se apaga
/// solo a los tres cuartos de hora. Apagado, esto no contesta nada — ni
/// siquiera dice que la app existe.
///
/// Va el nombre del aparato y la dirección. El nombre es de la CLASE de
/// aparato («ANDROID TV · Samsung UE50»), no el que le puso la persona: en una
/// casa con varios televisores hay que poder distinguirlos, y para eso alcanza
/// con la marca.
///
/// ── Lo que esto cambia en seguridad, dicho claro ────────────────────────────
///
/// Antes, para leer el registro había que ver la pantalla del televisor. Ahora,
/// quien esté en la misma red puede encontrarlo mientras esté encendido, sin
/// verla. Es un intercambio a propósito: el registro sale saneado —sin
/// credenciales, sin qué se estaba viendo, sin datos de la persona— así que lo
/// que se gana en comodidad no se paga con nada que identifique a nadie.
class AnuncioDeRegistro {
  AnuncioDeRegistro._();

  /// El puerto por donde se pregunta y se contesta.
  ///
  /// Uno fijo y distinto del de la página: si fueran el mismo, cualquier cosa
  /// que ya ocupe ese puerto se llevaría las dos funciones de una.
  static const puerto = 8788;

  /// Lo que se manda para preguntar, y con lo que empieza la respuesta.
  ///
  /// Con marca propia para no confundirse con lo que ande dando vueltas por la
  /// red: en una casa con impresoras y altavoces, el aire está lleno de
  /// mensajes a toda la red.
  static const _pregunta = 'prismhub-registro?';
  static const _respuesta = 'prismhub-registro!';

  static RawDatagramSocket? _oyendo;

  /// Empieza a contestar. [url] es la dirección de la página del registro.
  static Future<void> anunciar({
    required String url,
    required String aparato,
  }) async {
    await callar();
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, puerto);
      _oyendo = s;
      s.listen((evento) {
        if (evento != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null) return;
        try {
          if (utf8.decode(d.data).trim() != _pregunta) return;
          final carta = jsonEncode({'aparato': aparato, 'url': url});
          s.send(utf8.encode('$_respuesta$carta'), d.address, d.port);
        } catch (_) {
          // Un mensaje suelto mal formado no puede tumbar nada.
        }
      });
      logger.info('El televisor se anuncia en la red para el registro');
    } catch (e) {
      // Que no se pueda anunciar no rompe nada: queda la dirección escrita en
      // pantalla, que es como funcionaba antes.
      logger.info('No se pudo anunciar en la red: $e');
    }
  }

  static Future<void> callar() async {
    final s = _oyendo;
    _oyendo = null;
    if (s == null) return;
    try {
      s.close();
    } catch (_) {
      // Ya estaba cerrado.
    }
  }

  /// Pregunta quién hay, y devuelve lo que conteste.
  ///
  /// [espera] es cuánto se queda escuchando. Dos segundos y medio: una red de
  /// casa contesta en milisegundos, y esperar más solo hace que la pantalla
  /// parezca colgada.
  ///
  /// Se pregunta varias veces dentro de esa ventana porque UDP no garantiza
  /// nada: un solo mensaje que se pierda —y en wifi se pierden— sería un
  /// televisor que «no aparece» estando encendido.
  static Future<List<({String aparato, String url})>> buscar({
    Duration espera = const Duration(milliseconds: 2500),
  }) async {
    final encontrados = <String, ({String aparato, String url})>{};
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.broadcastEnabled = true;
      s.listen((evento) {
        if (evento != RawSocketEvent.read) return;
        final d = s?.receive();
        if (d == null) return;
        try {
          final texto = utf8.decode(d.data).trim();
          if (!texto.startsWith(_respuesta)) return;
          final carta = jsonDecode(texto.substring(_respuesta.length));
          if (carta is! Map) return;
          final url = carta['url']?.toString() ?? '';
          final aparato = carta['aparato']?.toString() ?? '';
          if (url.isEmpty) return;
          // Por dirección: si contesta dos veces, es el mismo.
          encontrados[url] = (aparato: aparato, url: url);
        } catch (_) {
          // Alguien más en la red hablando otro idioma.
        }
      });
      final mensaje = utf8.encode(_pregunta);
      final aTodos = InternetAddress('255.255.255.255');
      final reloj = Stopwatch()..start();
      while (reloj.elapsed < espera) {
        try {
          s.send(mensaje, aTodos, puerto);
        } catch (_) {
          // Redes que no dejan mandar a todos. Se sigue esperando por si
          // alguna de las vueltas anteriores llegó.
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      logger.info('No se pudo buscar en la red: $e');
    } finally {
      try {
        s?.close();
      } catch (_) {}
    }
    return encontrados.values.toList(growable: false);
  }
}

/// Un televisor que compartió su registro alguna vez.
class TelevisorConocido {
  const TelevisorConocido({
    required this.aparato,
    required this.url,
    required this.visto,
  });

  final String aparato;
  final String url;

  /// La última vez que contestó.
  final DateTime visto;

  Map<String, dynamic> aJson() => {
        'aparato': aparato,
        'url': url,
        'visto': visto.toIso8601String(),
      };

  static TelevisorConocido? deJson(Object? crudo) {
    if (crudo is! Map) return null;
    final url = crudo['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    return TelevisorConocido(
      aparato: crudo['aparato']?.toString() ?? '',
      url: url,
      visto: DateTime.tryParse(crudo['visto']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Los televisores que ya compartieron alguna vez, guardados en disco.
///
/// ── Por qué se guardan ──────────────────────────────────────────────────────
///
/// La lista de encontrados vivía solo mientras la pantalla estaba abierta. O
/// sea que si el televisor dejaba de compartir —porque se apagó, porque se
/// cumplió el tiempo o **porque la app se cayó**— al volver a entrar no había
/// nada: ni el televisor, ni rastro de que hubiera existido. Reportado en
/// vivo: «no está guardando, cuando se pierde la conexión se borra».
///
/// Y el tercer caso es justamente el que importa: si la app del televisor se
/// cayó, lo último que uno quiere es que la pantalla diga «acá nunca hubo
/// nada».
///
/// Se guarda lo mínimo para reconocerlo y volver: cómo se llama, en qué
/// dirección estaba y cuándo se lo vio por última vez. Nada del registro en sí.
class TelevisoresConocidos {
  TelevisoresConocidos._();

  /// Cuántos se recuerdan.
  ///
  /// Ocho: en una casa con más televisores que eso, los de más abajo son de
  /// hace tanto que la dirección ya no sirve.
  static const _cuantos = 8;

  static List<TelevisorConocido> leer() {
    try {
      final crudo =
          PrismHubStorage.getSetting(SettingKey.televisoresDeRegistro);
      if (crudo is! String || crudo.isEmpty) return const [];
      final lista = (jsonDecode(crudo) as List)
          .map(TelevisorConocido.deJson)
          .whereType<TelevisorConocido>()
          .toList();
      lista.sort((a, b) => b.visto.compareTo(a.visto));
      return lista;
    } catch (e) {
      // Un ajuste corrupto no puede impedir abrir la pantalla.
      logger.info('No se pudieron leer los televisores conocidos: $e');
      return const [];
    }
  }

  /// Anota los que contestaron ahora, conservando los de antes.
  static Future<void> anotar(
    Iterable<({String aparato, String url})> vistos,
  ) async {
    if (vistos.isEmpty) return;
    try {
      final ahora = DateTime.now();
      final porUrl = <String, TelevisorConocido>{
        for (final t in leer()) t.url: t,
        for (final v in vistos)
          v.url: TelevisorConocido(
            aparato: v.aparato,
            url: v.url,
            visto: ahora,
          ),
      };
      final lista = porUrl.values.toList()
        ..sort((a, b) => b.visto.compareTo(a.visto));
      await PrismHubStorage.setSetting(
        SettingKey.televisoresDeRegistro,
        jsonEncode(
          lista.take(_cuantos).map((t) => t.aJson()).toList(),
        ),
      );
    } catch (e) {
      logger.info('No se pudieron guardar los televisores conocidos: $e');
    }
  }

  /// Los olvida a todos.
  static Future<void> olvidar() async {
    try {
      await PrismHubStorage.setSetting(
        SettingKey.televisoresDeRegistro,
        '',
      );
    } catch (e) {
      logger.info('No se pudieron olvidar los televisores conocidos: $e');
    }
  }
}
