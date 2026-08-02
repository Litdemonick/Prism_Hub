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
  /// Las pide TODAS, pero de a tandas chicas.
  ///
  /// Se le pregunta a la extensión por cada tarjeta que siga sin portada, hasta
  /// terminar — no unas pocas por vuelta. Se puede porque es un gasto de UNA
  /// sola vez: una vez guardada, esa portada no se vuelve a pedir nunca.
  ///
  /// Lo que no se puede es hacerlas todas de golpe. Cincuenta títulos serían
  /// cincuenta peticiones simultáneas a los mismos sitios, que además de tardar
  /// muchísimo es la forma más rápida de que una fuente empiece a rechazar. Así
  /// que van de a [_aLaVez], con un respiro entre tanda y tanda.
  ///
  /// [alArreglar] se llama después de cada tanda, no al final: así las tarjetas
  /// se van llenando de a poco en vez de quedarse en gris hasta que termine
  /// todo.
  static Future<int> repararConRed(
    List<History> items, {
    void Function()? alArreglar,
  }) async {
    // Una sola a la vez. El inicio se refresca seguido —al volver a la
    // pestaña, al importar, al tirar para abajo— y sin esto arrancaría otra
    // ronda encima de la que ya está corriendo.
    if (_enCurso) return 0;
    _enCurso = true;
    var arregladas = 0;
    try {
      final pendientes = <History>[];
      for (final h in items) {
        if (h.cover != null && h.cover!.isNotEmpty) continue;
        // Solo extensiones que se pueden usar: una desactivada o caída no va a
        // contestar, y preguntarle es tiempo perdido.
        if (!ExtensionUtils.enabledRuntimes.containsKey(h.package)) continue;
        // Se marca ACÁ, antes de pedir nada: si no, dos tandas seguidas
        // podrían pedir el mismo título.
        if (!_yaPedidos.add('${h.package}|${h.url}')) continue;
        pendientes.add(h);
      }
      if (pendientes.isEmpty) return 0;
      logger.info('Faltan ${pendientes.length} portadas: se piden por tandas');

      for (var i = 0; i < pendientes.length; i += _aLaVez) {
        final tanda = pendientes.skip(i).take(_aLaVez);
        final hechas = await Future.wait(tanda.map(_pedirYGuardar));
        final enEstaTanda = hechas.where((e) => e).length;
        arregladas += enEstaTanda;
        // Se avisa por tanda para que las tarjetas se vayan llenando.
        if (enEstaTanda > 0) alArreglar?.call();
        // Un respiro entre tandas: sin esto son ráfagas seguidas contra el
        // mismo sitio, que es lo que hace que empiecen a rechazar.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } finally {
      _enCurso = false;
    }
    if (arregladas > 0) {
      logger.info('Se recuperaron $arregladas portadas preguntando');
    }
    return arregladas;
  }

  /// Le pide la portada a la extensión y la guarda. True si la consiguió.
  static Future<bool> _pedirYGuardar(History h) async {
    final runtime = ExtensionUtils.enabledRuntimes[h.package];
    if (runtime == null) return false;
    try {
      final detalle =
          await runtime.detail(h.url).timeout(const Duration(seconds: 8));
      final c = detalle.cover;
      if (c == null || c.isEmpty) return false;
      h.cover = c;
      await DatabaseService.putHistoryRaw(h);
      return true;
    } catch (e) {
      // Sin red, con la fuente caída o con una dirección que ya no existe: se
      // deja la tarjeta como está y no se reintenta en esta sesión.
      logger.info('No se pudo pedir la portada de ${h.title}: $e');
      return false;
    }
  }

  /// Cuántas se piden a la vez.
  ///
  /// Tres es suficiente para que no se sienta lento y bajo como para no
  /// parecer una ráfaga desde el otro lado.
  static const _aLaVez = 3;

  /// Si ya hay una ronda de peticiones andando.
  static bool _enCurso = false;

  /// Los que ya se le pidieron a la extensión, aparte de los locales.
  static final Set<String> _yaPedidos = {};

  /// Aprovecha la portada que ya cargó la ficha del título.
  ///
  /// Al abrir un detalle, la portada está ahí sí o sí —es lo primero que se ve—
  /// aunque la tarjeta del inicio siga en gris. Sería absurdo tenerla en
  /// pantalla y no guardarla: se copia al historial y al favorito de ese mismo
  /// título, y al volver atrás la tarjeta ya está.
  ///
  /// Es además lo que arregla el caso de una extensión que se cayó y volvió:
  /// mientras estaba caída no se le podía pedir nada, pero en cuanto vuelve y
  /// el usuario entra al título, la portada queda guardada sola.
  ///
  /// Solo rellena lo que FALTA: si el registro ya tenía portada no se toca, que
  /// podría ser una mejor o una que el usuario ya vio.
  static Future<void> desdeLaFicha({
    required String package,
    required String url,
    String? cover,
  }) async {
    if (cover == null || cover.isEmpty) return;
    try {
      final h = await DatabaseService.getHistoryByPackageAndUrl(package, url);
      if (h != null && (h.cover == null || h.cover!.isEmpty)) {
        h.cover = cover;
        // Raw: sin mover la fecha. Abrir una ficha no es haber visto algo.
        await DatabaseService.putHistoryRaw(h);
      }
      final f = await DatabaseService.getFavorite(package: package, url: url);
      if (f != null && (f.cover == null || f.cover!.isEmpty)) {
        f.cover = cover;
        await DatabaseService.putFavoriteRaw(f);
      }
      // Y se olvida el intento fallido: si antes no se pudo conseguir, ahora sí
      // se pudo, así que no tiene sentido seguir dándolo por perdido.
      final clave = '$package|$url';
      _yaMirados.remove(clave);
      _yaPedidos.remove(clave);
    } catch (e) {
      // Guardar una portada nunca vale romper la apertura de una ficha.
      logger.info('No se pudo guardar la portada de la ficha: $e');
    }
  }

  /// Vuelve a permitir el intento. Para después de importar, donde puede haber
  /// aparecido una ficha nueva que sí tenga la portada.
  static void olvidarLoMirado() {
    _yaMirados.clear();
    _yaPedidos.clear();
  }
}
