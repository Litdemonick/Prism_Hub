import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/modo_app.dart';

/// Impide que se abra una SEGUNDA copia del app en escritorio.
///
/// Windows resuelve un `prismhub://…` ejecutando el programa registrado con la
/// dirección al final de la línea de comandos (ver la sección [Registry] del
/// instalador). Sin nada que lo frene, cada enlace que se toca arranca un
/// proceso NUEVO aunque el app ya esté abierto.
///
/// Y no es solo una ventana de más: las dos copias abren la MISMA carpeta de
/// datos —historial, favoritos, ajustes— cada una con su propia idea de lo que
/// hay adentro. La segunda pisa lo que escribe la primera, y de ahí salen los
/// ajustes que "se resetean solos", como el aviso de beta volviendo a aparecer.
///
/// Cómo funciona: la primera copia se queda escuchando en un puerto de la
/// máquina (solo 127.0.0.1, no se ve desde la red). Las que arranquen después
/// no van a poder tomar ese puerto, así que le pasan el enlace a la que ya está
/// y se cierran solas.
class InstanciaUnica {
  /// Puerto fijo en el equipo. Alto y poco común a propósito, para no chocar
  /// con nada de uso habitual.
  ///
  /// **Uno distinto para las compilaciones de pruebas.** Con el mismo puerto,
  /// arrancar una prueba con la versión instalada abierta no abría nada: la
  /// prueba veía "ya hay una copia" y le cedía el control a la instalada, que
  /// es exactamente lo que hacía parecer que una reemplazaba a la otra.
  static int get _puerto => ModoApp.esRelease ? 47814 : 47815;

  /// Saludo con el que las dos copias se reconocen.
  ///
  /// Sin esto, cualquier otro programa que estuviera usando este puerto haría
  /// creer al app que ya hay una copia abierta, y no arrancaría nunca. Con el
  /// saludo, si del otro lado no contesta lo que corresponde, se sigue de
  /// largo y se abre normal.
  ///
  /// Cambia con el modo, por si los puertos se cruzaran: así una prueba nunca
  /// se reconoce con la instalada aunque terminen en el mismo puerto.
  static String get _saludo => 'PRISMHUB-1${ModoApp.sufijo}';
  static const _ok = 'OK';

  static ServerSocket? _servidor;

  /// ¿Esta copia es la que se queda?
  ///
  /// `true` = seguí arrancando normal. `false` = ya hay otra abierta, se le
  /// pasó el enlace y esta copia tiene que cerrarse.
  ///
  /// Ante cualquier duda devuelve `true`: es preferible una ventana de más que
  /// un app que no abre.
  static Future<bool> tomarElControl(
    List<String> args, {
    required void Function(Uri) alRecibirEnlace,
  }) async {
    if (Platform.isAndroid) return true;
    try {
      _servidor = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _puerto,
        shared: false,
      );
    } on SocketException {
      // El puerto está tomado: puede ser otra copia nuestra… o cualquier otro
      // programa. Se pregunta antes de rendirse.
      final entregado = await _pasarleElEnlaceAlaOtra(args);
      if (entregado) return false;
      logger.info(
        'El puerto de instancia única está ocupado por otro programa; '
        'se arranca igual',
      );
      return true;
    } catch (e, st) {
      logger.warning('No se pudo reservar la instancia única', e, st);
      return true;
    }

    _servidor!.listen(
      (cliente) => _atender(cliente, alRecibirEnlace),
      onError: (Object e) =>
          logger.warning('Fallo escuchando la instancia única', e),
    );
    return true;
  }

  static Future<void> _atender(
    Socket cliente,
    void Function(Uri) alRecibirEnlace,
  ) async {
    try {
      final texto = await utf8.decoder
          .bind(cliente)
          .join()
          .timeout(const Duration(seconds: 3));
      final lineas = const LineSplitter().convert(texto);
      if (lineas.isEmpty || lineas.first.trim() != _saludo) return;
      cliente.write(_ok);
      await cliente.flush();
      // La segunda línea es el enlace, si vino con uno. Puede no venir: alguien
      // que abre el app de nuevo desde el icono no trae ninguno, y ahí lo único
      // que corresponde es traer la ventana al frente.
      if (lineas.length > 1 && lineas[1].trim().isNotEmpty) {
        final uri = Uri.tryParse(lineas[1].trim());
        if (uri != null) alRecibirEnlace(uri);
      }
    } catch (e) {
      logger.warning('No se pudo leer lo que mandó la otra copia', e);
    } finally {
      try {
        await cliente.close();
      } catch (_) {}
    }
  }

  static Future<bool> _pasarleElEnlaceAlaOtra(List<String> args) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _puerto,
        timeout: const Duration(seconds: 2),
      );
      final enlace = args.firstWhere(
        (a) => a.contains('://'),
        orElse: () => '',
      );
      socket.write('$_saludo\n$enlace\n');
      await socket.flush();
      // Se cierra SOLO la salida: hay que dejar la entrada abierta para poder
      // leer la respuesta. Cerrando el socket entero acá, la otra copia recibe
      // el mensaje pero esta nunca se entera de si lo entendió.
      await socket.close();
      final respuesta = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 2), onTimeout: () => '');
      return respuesta.contains(_ok);
    } catch (e) {
      logger.info('No se pudo hablar con la otra copia: $e');
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }
}
