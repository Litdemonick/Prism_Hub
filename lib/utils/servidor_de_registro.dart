import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:prismhub/utils/encabezado_de_sesion.dart';
import 'package:prismhub/utils/exportar_registro.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Deja leer el registro del televisor desde otro aparato de la misma red.
///
/// ── Para qué existe ─────────────────────────────────────────────────────────
///
/// En un televisor no hay dónde exportar un archivo ni con qué abrirlo, así
/// que el registro solo se puede mirar en la propia pantalla — con el mando,
/// línea por línea. Para un fallo de dos líneas alcanza; para un cierre que
/// hay que rastrear hacia atrás, no.
///
/// Con esto el televisor levanta un servidor chico en la red de casa y muestra
/// una dirección. Se escribe esa dirección en el navegador de cualquier PC o
/// teléfono y ahí está el registro entero: se puede buscar, copiar y pegar.
///
/// ── Por qué no SSH ──────────────────────────────────────────────────────────
///
/// Es lo primero que se piensa, y es la herramienta equivocada. Un servidor
/// SSH es acceso a una consola del aparato: mucha superficie para lo que hace
/// falta, que es leer un archivo de texto. Además pide claves y configuración
/// de los dos lados. Un servidor de solo lectura, con lo único que sirve y
/// nada más, hace el mismo trabajo sin abrir ninguna puerta.
///
/// ── Lo que lo hace seguro ───────────────────────────────────────────────────
///
///  - **Apagado de fábrica.** Se enciende a mano y solo para esa sesión.
///  - **Con un código al azar en la dirección.** Que alguien esté en el mismo
///    wifi no alcanza: hay que estar viendo la pantalla del televisor para
///    saber la dirección completa. Sin el código, el servidor contesta que no.
///  - **Se apaga solo a los quince minutos.** Nadie se lo olvida encendido.
///  - **Solo lee el registro.** No hay ninguna otra ruta, y no escribe nada.
///  - **Y ese registro ya viene saneado** desde que se escribe: sin
///    credenciales, sin qué se estaba viendo y sin el nombre de usuario del
///    sistema. Ver [PrismLog.sanear].
class ServidorDeRegistro {
  ServidorDeRegistro._();

  static HttpServer? _servidor;
  static String? _codigo;
  static Timer? _apagado;

  /// Cuánto queda encendido si nadie lo apaga.
  ///
  /// Quince minutos: alcanza de sobra para leer un registro y no deja el
  /// servidor abierto toda la tarde por olvido.
  static const _cuantoDura = Duration(minutes: 15);

  /// La dirección para escribir en el otro aparato, o null si está apagado.
  static String? direccion;

  /// Qué área se está mirando en el televisor, para servir lo mismo.
  ///
  /// Lo pone el visor cuando se cambia de filtro. Null = todas. Si lo que se
  /// ve en la pantalla grande y lo que llega al navegador no coincidieran,
  /// habría que ir traduciendo mentalmente entre los dos, que es justo lo que
  /// esto viene a evitar.
  static String? areaElegida;

  static bool get encendido => _servidor != null;

  /// Las líneas concretas que hay que servir, o null para el registro entero.
  ///
  /// Lo pone el visor cuando lo que se está mirando es una sesión anterior:
  /// ahí lo que interesa no es lo que está pasando ahora, sino ese arranque
  /// en particular. Sin esto, el navegador mostraría algo distinto de lo que
  /// hay en la pantalla del televisor.
  static List<String>? lineasFijas;

  /// Lo enciende y dice qué pasó.
  ///
  /// Devuelve la dirección, o el motivo por el que no se pudo. Antes devolvía
  /// null a secas para las tres formas de fallar, así que la pantalla solo
  /// podía decir «no se pudo» — y quien lo lee no tiene con qué saber si le
  /// falta conectar el televisor a la red o si el problema es otro.
  ///
  /// Solo en televisor: en un teléfono o un PC ya se puede exportar el
  /// archivo, así que abrir un servidor sería sumar riesgo sin ganar nada.
  static Future<({String? direccion, FalloDeServidor? fallo})> encender() async {
    if (!PlatformTv.esTelevisionSync) {
      return (direccion: null, fallo: FalloDeServidor.noEsTelevisor);
    }
    if (_servidor != null) return (direccion: direccion, fallo: null);
    try {
      _codigo = _codigoAlAzar();
      // Puerto 0: lo elige el sistema entre los libres. Fijar uno a mano es
      // pedir que choque con otra cosa del aparato.
      final s = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _servidor = s;
      s.listen(_atender, onError: (Object e) {
        logger.warning('servidor de registro: $e');
      });
      final ip = await _ipDeLaRed();
      if (ip == null) {
        await apagar();
        return (direccion: null, fallo: FalloDeServidor.sinRed);
      }
      direccion = 'http://$ip:${s.port}/r/$_codigo';
      _apagado = Timer(_cuantoDura, apagar);
      logger.info('Registro accesible desde la red durante '
          '${_cuantoDura.inMinutes} minutos');
      return (direccion: direccion, fallo: null);
    } catch (e) {
      logger.warning('No se pudo levantar el servidor de registro: $e');
      await apagar();
      return (direccion: null, fallo: FalloDeServidor.noSePudo);
    }
  }

  static Future<void> apagar() async {
    _apagado?.cancel();
    _apagado = null;
    final s = _servidor;
    _servidor = null;
    direccion = null;
    _codigo = null;
    lineasFijas = null;
    if (s == null) return;
    try {
      await s.close(force: true);
      logger.info('Servidor de registro apagado');
    } catch (_) {
      // Ya estaba cerrado.
    }
  }

  /// Seis caracteres al azar. No es una contraseña —la protección de verdad es
  /// que hay que ver la pantalla— pero evita que alguien que sepa la IP entre
  /// probando la ruta.
  static String _codigoAlAzar() {
    const alfabeto = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(6, (_) => alfabeto[r.nextInt(alfabeto.length)]).join();
  }

  static Future<void> _atender(HttpRequest pedido) async {
    try {
      final esperado = _codigo;
      final ruta = pedido.uri.pathSegments;
      // Una sola ruta válida, y con el código. Cualquier otra cosa se contesta
      // igual —404 pelado— para no ir diciendo qué existe y qué no.
      final valido = esperado != null &&
          ruta.length == 2 &&
          ruta[0] == 'r' &&
          ruta[1] == esperado;
      if (!valido) {
        pedido.response.statusCode = HttpStatus.notFound;
        await pedido.response.close();
        return;
      }
      final texto = await ExportarRegistro.armar(
        soloArea: areaElegida,
        lineas: lineasFijas,
      );
      pedido.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        // Nada de caché: se abre para ver lo último, no lo de hace un rato.
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(_pagina(texto));
      await pedido.response.close();
    } catch (e) {
      logger.info('servidor de registro: $e');
      try {
        pedido.response.statusCode = HttpStatus.internalServerError;
        await pedido.response.close();
      } catch (_) {}
    }
  }

  /// La página que se ve en el navegador.
  ///
  /// Sencilla a propósito: texto monoespaciado sobre fondo oscuro, con un
  /// refresco cada cinco segundos. Nada de esto se sirve desde fuera —es un
  /// solo archivo, sin recursos— así que no hay nada más que traer.
  static String _pagina(String registro) {
    final escapado = const HtmlEscape().convert(registro);
    return '''<!doctype html>
<html lang="es"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="5">
<title>Registro de PrismHub</title>
<style>
  body{background:#11131a;color:#c9ccd6;font:12px/1.5 ui-monospace,Consolas,monospace;margin:0;padding:16px}
  h1{color:#f0568d;font-size:15px;margin:0 0 4px}
  p{color:#7b8194;margin:0 0 16px;font-size:12px}
  pre{white-space:pre-wrap;word-break:break-word;margin:0}
</style></head><body>
<h1>Registro de PrismHub</h1>
<p>${const HtmlEscape().convert(EncabezadoDeSesion.resumenDelAparato())} · ${const HtmlEscape().convert(areaElegida ?? 'todo el registro')} · se actualiza solo cada 5 s</p>
<pre>$escapado</pre>
</body></html>''';
  }

  /// La dirección de este aparato en la red de casa.
  static Future<String?> _ipDeLaRed() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final dir in iface.addresses) {
          // Solo redes privadas: si lo único que hay es una dirección pública,
          // esto no es una red de casa y no corresponde publicar nada.
          final a = dir.address;
          if (a.startsWith('192.168.') ||
              a.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a)) {
            return a;
          }
        }
      }
    } catch (_) {
      // Sin permiso de red o sin interfaces: se avisa arriba.
    }
    return null;
  }
}

/// Por qué no se pudo encender el servidor.
///
/// Cada uno lleva a un mensaje distinto en pantalla, porque llevan a arreglos
/// distintos: uno se soluciona conectando el televisor a la red y los otros
/// no se solucionan desde ahí.
enum FalloDeServidor {
  /// No es un televisor. No debería llegar acá: el botón no existe fuera de
  /// televisor. Está por si algún día se llama desde otro lado.
  noEsTelevisor,

  /// El aparato no está en ninguna red de casa. Es el caso realista: un
  /// televisor sin wifi ni cable conectado.
  sinRed,

  /// El sistema no dejó abrir el puerto. Algunos televisores con la app en
  /// segundo plano, o con políticas del fabricante, lo bloquean.
  noSePudo,
}
