import 'dart:convert';

import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/log.dart';

/// Vuelve a poner las portadas que quedaron vacías en el historial.
///
/// Hizo falta por un fallo real: al importar una copia sobre registros que ya
/// estaban, los que venían sin portada la borraron —el registro se reemplaza
/// entero—. Eso ya está arreglado en la importación, pero lo que se perdió no
/// vuelve solo, y quedaban tarjetas en un color liso mientras que al abrir el
/// título la imagen aparecía perfecta.
///
/// Se busca en tres sitios, del más barato al más caro:
///
///  1. La ficha del título, que se guarda al abrirla y trae su portada.
///  2. El favorito del mismo título, si está en la lista.
///  3. Preguntándole a la extensión. Esto SÍ usa red, así que va aparte y con
///     un techo mucho más bajo (ver [repararConRed]).
///
/// Los dos primeros son lectura de la base y salen al toque. El tercero existe
/// porque hay títulos que nunca se abrieron desde este equipo —los que llegaron
/// por una copia— y de esos no hay ficha de dónde sacar nada.
class PortadasPerdidas {
  /// Los que ya se miraron en esta sesión, hayan tenido arreglo o no.
  ///
  /// El inicio se refresca seguido; sin esto se reintentaría lo mismo en cada
  /// vuelta, y lo que no se pudo arreglar la primera vez tampoco se va a poder
  /// después.
  static final Set<String> _yaMirados = {};

  /// Cuántas se intentan por vuelta.
  ///
  /// Con un historial grande, arreglar todo de una golpea la base justo cuando
  /// el inicio se está dibujando. Se hace de a poco: lo que queda se arregla en
  /// el refresco siguiente, y mientras tanto la pantalla responde.
  static const _porVuelta = 12;

  /// Intenta reparar las que falten. Devuelve cuántas se arreglaron.
  ///
  /// Silenciosa a propósito: es una reparación de fondo y no algo que el
  /// usuario pidió, así que no interrumpe ni avisa. Si falla, la tarjeta se
  /// queda como estaba.
  static Future<int> reparar(List<History> items) async {
    var arregladas = 0;
    var intentos = 0;
    for (final h in items) {
      if (intentos >= _porVuelta) break;
      if (h.cover != null && h.cover!.isNotEmpty) continue;
      final clave = '${h.package}|${h.url}';
      if (!_yaMirados.add(clave)) continue;
      intentos++;
      try {
        final portada = await _buscar(h);
        if (portada == null || portada.isEmpty) continue;
        h.cover = portada;
        // Raw: guarda TAL CUAL, sin mover la fecha. Esto no es que el usuario
        // haya visto algo, así que no puede reordenarle el historial.
        await DatabaseService.putHistoryRaw(h);
        arregladas++;
      } catch (e) {
        logger.info('No se pudo recuperar la portada de ${h.title}: $e');
      }
    }
    if (arregladas > 0) {
      logger.info('Se recuperaron $arregladas portadas del historial');
    }
    return arregladas;
  }

  /// Dónde buscar, en orden de qué tan probable es que la tenga.
  static Future<String?> _buscar(History h) async {
    // La ficha guardada: es la fuente más completa y la que uso el propio
    // reproductor cuando le falta la portada.
    try {
      final cache = await DatabaseService.getPrismHubDetail(h.package, h.url);
      if (cache != null) {
        final detalle = ExtensionDetail.fromJson(jsonDecode(cache.data));
        final c = detalle.cover;
        if (c != null && c.isNotEmpty) return c;
      }
    } catch (_) {
      // Una ficha guardada con otra forma no vale cortar la reparación.
    }
    // El favorito del mismo título. Pasa seguido: lo que se ve suele estar
    // también en la lista, y ahí la portada se guarda igual.
    try {
      final fav =
          await DatabaseService.getFavorite(package: h.package, url: h.url);
      final c = fav?.cover;
      if (c != null && c.isNotEmpty) return c;
    } catch (_) {}
    return null;
  }

  /// Último recurso: pedírsela a la extensión.
  ///
  /// Se separa de [_buscar] porque esto SÍ usa red, y por eso va aparte y con
  /// un techo mucho más bajo. Sin él, un historial de cincuenta títulos sin
  /// portada dispararía cincuenta peticiones al abrir el inicio.
  ///
  /// Solo para los que no se pudieron arreglar con lo que ya había guardado —
  /// que en la práctica son los que nunca se abrieron desde este equipo, así
  /// que no hay ficha de dónde sacarla.
  static Future<int> repararConRed(List<History> items) async {
    var arregladas = 0;
    var intentos = 0;
    for (final h in items) {
      if (intentos >= _porVueltaConRed) break;
      if (h.cover != null && h.cover!.isNotEmpty) continue;
      final clave = '${h.package}|${h.url}';
      if (!_yaPedidos.add(clave)) continue;
      // Solo extensiones que se pueden usar: una desactivada o caída no va a
      // contestar, y preguntarle es tiempo perdido.
      final runtime = ExtensionUtils.enabledRuntimes[h.package];
      if (runtime == null) continue;
      intentos++;
      try {
        final detalle = await runtime
            .detail(h.url)
            .timeout(const Duration(seconds: 8));
        final c = detalle.cover;
        if (c == null || c.isEmpty) continue;
        h.cover = c;
        await DatabaseService.putHistoryRaw(h);
        arregladas++;
      } catch (e) {
        // Sin red, con la fuente caída o con una dirección que ya no existe:
        // se deja la tarjeta como está y no se vuelve a intentar en esta
        // sesión.
        logger.info('No se pudo pedir la portada de ${h.title}: $e');
      }
    }
    if (arregladas > 0) {
      logger.info('Se pidieron $arregladas portadas a las extensiones');
    }
    return arregladas;
  }

  /// Mucho más bajo que el de las locales: cada una es una petición de red.
  static const _porVueltaConRed = 4;

  /// Los que ya se le pidieron a la extensión, aparte de los locales.
  static final Set<String> _yaPedidos = {};

  /// Vuelve a permitir el intento. Para después de importar, donde puede haber
  /// aparecido una ficha nueva que sí tenga la portada.
  static void olvidarLoMirado() {
    _yaMirados.clear();
    _yaPedidos.clear();
  }
}
