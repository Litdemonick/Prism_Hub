import 'dart:convert';

import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Las últimas búsquedas del buscador de TV.
///
/// ── Por qué hace falta ────────────────────────────────────────────────
///
/// Escribir letra por letra con un control remoto es lo peor de cualquier
/// app de TV. En un televisor uno busca casi siempre las mismas cuatro
/// cosas — la serie que está siguiendo, el estudio que le gusta — así que un
/// botón con lo ya buscado vale por diez letras tecleadas de a una.
///
/// Solo existe para TV a propósito: en teléfono y escritorio ya hay teclado
/// físico o táctil de verdad, y no tiene sentido guardar ahí lo mismo.
class BusquedasRecientes {
  BusquedasRecientes._();

  /// Cuántas se recuerdan. Ocho entran en una fila sin que haya que
  /// desplazarse, y alcanza de sobra: son las búsquedas de ESTE aparato, no
  /// un historial para siempre.
  static const _tope = 8;

  /// Se cargan una sola vez y se guardan en memoria — la misma pantalla las
  /// consulta en cada letra que se escribe (para no repetir una ya
  /// guardada), así que ir a disco cada vez sería innecesario.
  static List<String>? _cache;

  static List<String> obtener() {
    final cache = _cache;
    if (cache != null) return cache;
    final crudo = PrismHubStorage.getSetting(SettingKey.busquedasRecientesTv);
    if (crudo is! String || crudo.isEmpty) return _cache = const [];
    try {
      final lista = (jsonDecode(crudo) as List)
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      return _cache = lista;
    } catch (e) {
      // Un ajuste corrupto no puede impedir abrir el buscador: se descarta
      // y se sigue como si no hubiera ninguna.
      logger.info('No se pudieron leer las búsquedas recientes: $e');
      return _cache = const [];
    }
  }

  /// Guarda un término, al frente. Si ya estaba, se mueve al frente en vez
  /// de duplicarse — es la búsqueda MÁS reciente, sin importar que ya
  /// hubiera pasado por acá antes.
  /// Ninguna búsqueda real necesita más letras que esto — lo que exceda es
  /// alguien apoyado sobre una tecla, no un título. Sin este tope, ese
  /// texto se guardaba entero y el chip que lo mostraba después no tenía
  /// de dónde recortar: pedía el ancho que hiciera falta y se salía de la
  /// pantalla. Reportado en vivo con foto: "RIGHT OVERFLOWED BY 2.9
  /// PIXELS".
  static const _largoMaximo = 40;

  static Future<void> agregar(String termino) async {
    var limpio = termino.trim();
    // Menos de tres letras no vale la pena recordarlo: son las que se
    // escriben de paso hacia la palabra real, y llenarían la lista de
    // fragmentos ("a", "an", "ana") en vez de búsquedas de verdad.
    if (limpio.length < 3) return;
    if (limpio.length > _largoMaximo) limpio = limpio.substring(0, _largoMaximo);
    final actuales = List<String>.from(obtener());
    actuales.removeWhere((e) => e.toLowerCase() == limpio.toLowerCase());
    actuales.insert(0, limpio);
    if (actuales.length > _tope) actuales.removeRange(_tope, actuales.length);
    _cache = actuales;
    try {
      await PrismHubStorage.setSetting(
        SettingKey.busquedasRecientesTv,
        jsonEncode(actuales),
      );
    } catch (e) {
      logger.info('No se pudo guardar la búsqueda reciente: $e');
    }
  }

  static Future<void> limpiar() async {
    _cache = const [];
    try {
      await PrismHubStorage.setSetting(SettingKey.busquedasRecientesTv, '');
    } catch (e) {
      logger.info('No se pudieron borrar las búsquedas recientes: $e');
    }
  }
}
