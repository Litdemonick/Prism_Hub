import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:path/path.dart' as p;

/// En qué anda la fila de una extensión.
enum EstadoDeFila { pendiente, cargando, lista, fallo }

/// Si el usuario la tiene, y en qué estado.
///
/// El Home muestra TODAS, no solo las que andan: una que está instalada pero
/// apagada, o una del catálogo que ni se instaló, igual ocupan su fila. Así el
/// usuario ve todo lo que podría estar viendo, y de paso se entera de que
/// existe — escondidas, nadie descubre que están.
enum EstadoExtension { activa, desactivada, noInstalada }

/// Una fila del Home: una extensión y lo último que tiene.
class FilaDeExtension {
  FilaDeExtension({
    required this.package,
    required this.nombre,
    this.estadoExt = EstadoExtension.activa,
  });

  final String package;
  final String nombre;
  final EstadoExtension estadoExt;

  final estado = EstadoDeFila.pendiente.obs;
  final items = <ExtensionListItem>[].obs;

  /// De cuándo son los datos que se están mostrando. null = nunca cargó.
  DateTime? traidoEl;
}

/// Lo que alimenta el Home: **lo último de cada extensión instalada**.
///
/// ── El problema de fondo, y cómo se resuelve ──────────────────────────────
///
/// Pedirle a las extensiones es LENTO y poco confiable: medido, LaMovie tardó
/// entre 21 y 27 segundos en dar su portada, y hay sitios que directamente se
/// caen. Con 17 extensiones instaladas, pedirle a todas al abrir el Home son
/// 17 raspados lentos que se pelean el ancho de banda.
///
/// Las cinco decisiones que hacen que igual se sienta rápido:
///
///   1. **Nada se pide hasta que se ve.** Cada fila pide en su `initState`, y
///      como el Home es un `ListView.builder`, solo se construyen las filas
///      cercanas a la pantalla. Abrir el Home cuesta lo mismo con 3
///      extensiones que con 30.
///   2. **Ninguna fila espera a otra.** Que una tarde 27 segundos no puede
///      congelar a la que ya está lista. Nada de `Future.wait` sobre el grupo:
///      eso hace esperar a la más lenta de la tanda — la misma lección que ya
///      está escrita en el controlador de búsqueda.
///   3. **Tope de tres a la vez.** Diecisiete peticiones simultáneas en un
///      teléfono es peor que en tanda: se pelean la red y no llega ninguna.
///   4. **Caché en disco.** Al abrir se muestra lo guardado AL INSTANTE y se
///      refresca por detrás. Es la diferencia entre "abre ya" y "siempre
///      espera".
///   5. **Una fila que falla no rompe nada.** Queda con su aviso y su botón de
///      reintentar; las demás siguen.
class CatalogoExtensionesController extends GetxController {
  /// Cuánto vale lo guardado antes de volver a pedirlo.
  ///
  /// Media hora: el contenido nuevo de estos sitios no aparece cada minuto, y
  /// mientras tanto abrir el Home es instantáneo.
  static const _vigencia = Duration(minutes: 30);

  /// Cuántas extensiones se piden a la vez. Ver la decisión 3.
  static const _aLaVez = 3;

  final filas = <FilaDeExtension>[].obs;

  /// Lo del carrusel, **agrupado por extensión**.
  ///
  /// No es una bolsa mezclada: son tandas. El carrusel pasa las cinco de una
  /// extensión y recién ahí salta a la siguiente. Mezcladas, saltaba de sitio
  /// en sitio en cada cambio y no se entendía de dónde venía cada portada.
  final destacados = <(String, List<ExtensionListItem>)>[].obs;

  /// Cuántas se toman de cada extensión para el carrusel.
  static const porExtension = 5;

  // ── Dónde va el carrusel ──────────────────────────────────────────────────
  //
  // La posición vive ACÁ y no en el widget del carrusel, y es a propósito: ese
  // widget se reconstruye cada vez que se vuelve a la pestaña —en Android
  // cambiar de pestaña reconstruye la página entera— así que su estado se
  // perdía y el carrusel volvía a arrancar en la primera extensión, siempre la
  // misma. Este controlador sobrevive, así que la posición también.
  //
  // Y la primera vez arranca en una extensión AL AZAR: si empezara siempre por
  // la primera, esa se llevaría toda la atención y las últimas no las vería
  // nadie.
  int carruselExt = 0;
  int carruselPos = 0;
  bool _carruselSembrado = false;

  /// Avanza una posición. Al terminar la tanda de una extensión salta a la
  /// siguiente, desde su primera.
  void avanzarCarrusel() {
    if (destacados.isEmpty) return;
    final actual = destacados[carruselExt % destacados.length].$2;
    if (carruselPos + 1 < actual.length) {
      carruselPos++;
    } else {
      carruselPos = 0;
      carruselExt = (carruselExt + 1) % destacados.length;
    }
  }

  var _enVuelo = 0;
  final _cola = <FilaDeExtension>[];
  Map<String, dynamic> _cache = const {};

  @override
  void onInit() {
    super.onInit();
    unawaited(_armar());
  }

  Future<void> _armar() async {
    await _leerCache();
    // ── Las +18 NO entran al Home, sin excepción ────────────────────────────
    //
    // A pedido explícito. Y se filtra por `extension.nsfw` y NO por
    // `isNsfwVisibleOutsideZone`, que deja pasar las +18 cuando el interruptor
    // general está prendido: con ese criterio, una portada +18 podía terminar
    // en el Home normal — ya pasó una vez con el hero y quedó documentado en
    // home_controller.
    //
    // Su lugar es la Zona +18, detrás de su puerta. Acá no.
    //
    // Se miran TODAS las instaladas, no solo las encendidas: una apagada
    // igual tiene su fila, con un botón para prenderla.
    final instaladas = Map.fromEntries(
      ExtensionUtils.runtimes.entries.where((e) => !e.value.extension.nsfw),
    );

    // ── El orden: primero lo que de verdad usás ─────────────────────────────
    //
    // Con muchas instaladas, esto importa más que cualquier otra cosa: lo que
    // abrís seguido tiene que estar arriba, no en la fila catorce. Sale del
    // historial, que ya sabe qué paquetes tocaste.
    final usos = <String, int>{};
    try {
      for (final h in await DatabaseService.getHistorysByType()) {
        usos[h.package] = (usos[h.package] ?? 0) + 1;
      }
    } catch (e) {
      logger.info('[home] no se pudo leer el historial para ordenar: $e');
    }

    final nuevas = instaladas.entries
        .map((e) => FilaDeExtension(
              package: e.key,
              nombre: e.value.extension.name,
              estadoExt: ExtensionUtils.isEnabled(e.key)
                  ? EstadoExtension.activa
                  : EstadoExtension.desactivada,
            ))
        .toList()
      ..sort((a, b) {
        // Las encendidas arriba: son las únicas que traen contenido, y son a
        // las que el usuario vino. Las apagadas y las que ni tiene van al
        // final, donde no le estorban pero se ven si baja.
        final ea = a.estadoExt == EstadoExtension.activa ? 0 : 1;
        final eb = b.estadoExt == EstadoExtension.activa ? 0 : 1;
        if (ea != eb) return ea - eb;
        final ua = usos[a.package] ?? 0;
        final ub = usos[b.package] ?? 0;
        // Más usada primero; a igualdad, alfabético para que el orden no
        // baile entre aperturas.
        if (ua != ub) return ub - ua;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });

    // Y al final, las del catálogo que el usuario todavía no tiene.
    //
    // El catálogo se lee de lo YA GUARDADO, sin forzar red: esto corre al abrir
    // el Home y no puede quedarse esperando una petición para dibujar la
    // pantalla. Si nunca se bajó, simplemente no salen y aparecen la próxima.
    try {
      final catalogo = await ExtensionUtils.fetchRepoIndex();
      final porInstalar = <FilaDeExtension>[];
      for (final e in catalogo) {
        if (e is! Map) continue;
        final pkg = e['package']?.toString();
        final nombre = e['name']?.toString();
        if (pkg == null || nombre == null) continue;
        if (instaladas.containsKey(pkg)) continue;
        // El catálogo solo trae `nsfw` cuando es true, y como texto.
        final esNsfw = e['nsfw'] == true || e['nsfw']?.toString() == 'true';
        if (esNsfw) continue;
        porInstalar.add(FilaDeExtension(
          package: pkg,
          nombre: nombre,
          estadoExt: EstadoExtension.noInstalada,
        ));
      }
      porInstalar
          .sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      nuevas.addAll(porInstalar);
    } catch (e) {
      logger.info('[home] no se pudo leer el catálogo: $e');
    }

    if (nuevas.isEmpty) {
      filas.clear();
      return;
    }

    // Lo guardado se muestra YA, sin esperar la red.
    for (final fila in nuevas) {
      final guardado = _cache[fila.package];
      if (guardado is! Map) continue;
      final items = _desdeJson(guardado['items']);
      if (items.isEmpty) continue;
      fila.items.assignAll(items);
      fila.traidoEl =
          DateTime.tryParse(guardado['fecha']?.toString() ?? '');
      fila.estado.value = EstadoDeFila.lista;
      _sumarADestacados(fila, items);
    }
    filas.assignAll(nuevas);
  }

  /// La pide si hace falta. La llama cada fila cuando entra en pantalla.
  ///
  /// Con [forzar] va aunque lo guardado esté vigente — es el "reintentar" y el
  /// tirar-para-refrescar.
  void pedirSiHaceFalta(FilaDeExtension fila, {bool forzar = false}) {
    // Una apagada o sin instalar no tiene a quién preguntarle.
    if (fila.estadoExt != EstadoExtension.activa) return;
    if (fila.estado.value == EstadoDeFila.cargando) return;
    if (!forzar && fila.estado.value == EstadoDeFila.lista) {
      final traido = fila.traidoEl;
      if (traido != null && DateTime.now().difference(traido) < _vigencia) {
        return;
      }
    }
    if (_cola.contains(fila)) return;
    _cola.add(fila);
    _mover();
  }

  void _mover() {
    while (_enVuelo < _aLaVez && _cola.isNotEmpty) {
      final fila = _cola.removeAt(0);
      _enVuelo++;
      unawaited(_traer(fila).whenComplete(() {
        _enVuelo--;
        _mover();
      }));
    }
  }

  Future<void> _traer(FilaDeExtension fila) async {
    // Solo se muestra "cargando" si no hay nada viejo que mostrar. Con datos
    // en pantalla, refrescar por detrás no tiene que parpadear.
    if (fila.items.isEmpty) fila.estado.value = EstadoDeFila.cargando;
    try {
      final runtime = ExtensionUtils.enabledRuntimes[fila.package];
      if (runtime == null) {
        fila.estado.value = EstadoDeFila.fallo;
        return;
      }
      // Tope propio: sin esto, un sitio colgado deja la fila girando para
      // siempre. Con él, a los 20 s dice que no respondió y ofrece reintentar.
      final items = await runtime.latest(1).timeout(const Duration(seconds: 20));
      if (items.isEmpty) {
        fila.estado.value =
            fila.items.isEmpty ? EstadoDeFila.fallo : EstadoDeFila.lista;
        return;
      }
      fila.items.assignAll(items);
      fila.traidoEl = DateTime.now();
      fila.estado.value = EstadoDeFila.lista;
      _sumarADestacados(fila, items);
      unawaited(_guardarCache(fila, items));
    } catch (e) {
      logger.info('[home] ${fila.nombre} no respondió: $e');
      // Con datos viejos en pantalla NO se marca como fallo: mostrar lo de
      // antes es mejor que borrarlo porque el refresco falló.
      fila.estado.value =
          fila.items.isEmpty ? EstadoDeFila.fallo : EstadoDeFila.lista;
    }
  }

  /// Alimenta el carrusel con la tanda de esta extensión.
  ///
  /// Se toman [porExtension] con portada. Sin portada no sirven: el carrusel
  /// es una imagen grande y un hueco ahí se ve peor que no mostrar nada.
  void _sumarADestacados(FilaDeExtension fila, List<ExtensionListItem> items) {
    final conPortada = items
        .where((i) => (i.cover ?? '').isNotEmpty)
        .take(porExtension)
        .toList();
    if (conPortada.isEmpty) return;
    final i = destacados.indexWhere((d) => d.$1 == fila.package);
    if (i >= 0) {
      destacados[i] = (fila.package, conPortada);
    } else {
      destacados.add((fila.package, conPortada));
    }
    // La primera tanda que llega decide por dónde se empieza. Una sola vez por
    // sesión: re-sortear en cada extensión que contesta haría saltar el
    // carrusel mientras el usuario lo está mirando.
    if (!_carruselSembrado && destacados.isNotEmpty) {
      _carruselSembrado = true;
      carruselExt = Random().nextInt(destacados.length);
      carruselPos = 0;
    }
  }

  /// Vuelve a armar la lista entera.
  ///
  /// Hace falta cuando cambia el ESTADO de una extensión —se prendió, se
  /// instaló— y no solo su contenido: ahí una fila tiene que pasar de
  /// «apagada» a activa, y eso no se arregla refrescando lo que ya está.
  Future<void> recargar() async {
    destacados.clear();
    await _armar();
  }

  Future<void> refrescarTodo() async {
    for (final fila in filas) {
      pedirSiHaceFalta(fila, forzar: true);
    }
  }

  // ─── Caché en disco ───────────────────────────────────────────────────────
  //
  // Un solo archivo con todo, no uno por extensión: son pocos kilobytes y así
  // se lee de una sola vez al arrancar en vez de abrir diecisiete archivos.

  File get _archivo =>
      File(p.join(PrismHubDirectory.getDirectory, 'home_extensiones.json'));

  Future<void> _leerCache() async {
    try {
      final f = _archivo;
      if (!await f.exists()) return;
      final crudo = jsonDecode(await f.readAsString());
      if (crudo is Map<String, dynamic>) _cache = crudo;
    } catch (e) {
      // Un caché ilegible no puede impedir que el Home abra: se descarta.
      logger.info('[home] caché ilegible, se ignora: $e');
      _cache = const {};
    }
  }

  Future<void> _guardarCache(
      FilaDeExtension fila, List<ExtensionListItem> items) async {
    try {
      // Solo lo que se dibuja en la fila. Guardar más engorda el archivo sin
      // que nadie lo lea.
      final recorte = items.take(24).map((i) => {
            'title': i.title,
            'url': i.url,
            'cover': i.cover,
          });
      final copia = Map<String, dynamic>.from(_cache);
      copia[fila.package] = {
        'fecha': DateTime.now().toIso8601String(),
        'items': recorte.toList(),
      };
      _cache = copia;
      await _archivo.writeAsString(jsonEncode(copia));
    } catch (e) {
      logger.info('[home] no se pudo guardar el caché: $e');
    }
  }

  static List<ExtensionListItem> _desdeJson(dynamic crudo) {
    if (crudo is! List) return const [];
    final salida = <ExtensionListItem>[];
    for (final e in crudo) {
      if (e is! Map) continue;
      final titulo = e['title']?.toString();
      final url = e['url']?.toString();
      if (titulo == null || url == null) continue;
      salida.add(ExtensionListItem(
        title: titulo,
        url: url,
        cover: e['cover']?.toString(),
      ));
    }
    return salida;
  }
}
