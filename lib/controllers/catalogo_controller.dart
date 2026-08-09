import 'package:get/get.dart';
import 'package:prismhub/data/metadata/anilist_catalogo.dart';
import 'package:prismhub/data/metadata/metadata_item.dart';
import 'package:prismhub/data/metadata/metadata_source.dart';
import 'package:prismhub/data/metadata/tmdb_catalogo.dart';
import 'package:prismhub/utils/log.dart';

/// Una fila del Home, ya lista para dibujar.
class FilaDelHome {
  const FilaDelHome({
    required this.titulo,
    required this.tipo,
    required this.obras,
  });

  /// Clave de traducción, no el texto. Ver `catalogo.*` en los i18n.
  final String titulo;

  /// De qué zona es. Se muestra al lado del título de la fila, porque en un
  /// solo desplazamiento con todo junto «Populares» a secas no dice de qué.
  final TipoDeObra tipo;

  final List<ObraDelCatalogo> obras;
}

/// Lo que alimenta el Home.
///
/// ── Cómo se arma la pantalla ──────────────────────────────────────────────
///
/// El Home es **un solo desplazamiento con todo junto**: anime, series,
/// películas y mangas, sin botones arriba para cambiar de zona. Eso obliga a
/// dos cosas que están resueltas acá:
///
///   · **Las cuatro fuentes se piden a la vez**, no una tras otra. En serie,
///     la última zona aparecería varios segundos después de la primera.
///   · **Las filas se intercalan**, no se apilan por zona. Si fueran cuatro
///     bloques seguidos, para ver una película habría que pasar de largo seis
///     filas de anime. Intercaladas, lo primero que se ve tiene de todo.
///
/// ── Lo que NO hace, a propósito ───────────────────────────────────────────
///
/// No toca las extensiones. El catálogo dice qué existe; las extensiones dicen
/// dónde verlo. Son dos cosas separadas y se juntan recién en la ficha.
class CatalogoController extends GetxController {
  /// Las zonas, en el orden en que se intercalan sus filas.
  ///
  /// Anime primero porque es el fuerte de la app y porque su fuente no pide
  /// clave: aunque TMDB no esté configurado, el Home igual arranca con
  /// contenido en vez de con un cartel.
  late final List<FuenteDeCatalogo> _fuentes = [
    CatalogoAniList(TipoDeObra.anime),
    CatalogoTMDB(TipoDeObra.serie),
    CatalogoTMDB(TipoDeObra.pelicula),
    CatalogoAniList(TipoDeObra.manga),
  ];

  final filas = <FilaDelHome>[].obs;
  final cargando = false.obs;

  /// Zonas que no pudieron traer nada, con su motivo. La pantalla lo usa para
  /// avisar QUÉ falta —la clave de TMDB, por ejemplo— en vez de callarse.
  final problemas = <TipoDeObra, MotivoSinCatalogo>{}.obs;

  /// true cuando no se consiguió una sola fila. Distinto de «alguna zona
  /// falló»: con anime andando el Home igual sirve.
  bool get vacioDelTodo => filas.isEmpty && !cargando.value;

  @override
  void onInit() {
    super.onInit();
    cargar();
  }

  /// Trae todo. [forzar] rehace el pedido aunque ya haya contenido.
  Future<void> cargar({bool forzar = false}) async {
    if (cargando.value) return;
    if (filas.isNotEmpty && !forzar) return;
    cargando.value = true;
    try {
      // Todas a la vez. `eagerError: false` es lo importante: si una zona
      // revienta, las otras tres se muestran igual.
      final respuestas = await Future.wait(
        _fuentes.map((f) => f.portada()),
        eagerError: false,
      );

      final problemasNuevos = <TipoDeObra, MotivoSinCatalogo>{};
      // Las filas de cada zona, en orden, para poder intercalarlas después.
      final porZona = <List<FilaDelHome>>[];
      for (var i = 0; i < _fuentes.length; i++) {
        final fuente = _fuentes[i];
        final r = respuestas[i];
        if (!r.hayDatos) {
          problemasNuevos[fuente.tipo] = r.motivo!;
          if (r.detalle != null) {
            logger.info('[catálogo] ${fuente.tipo.name}: ${r.detalle}');
          }
          porZona.add(const []);
          continue;
        }
        porZona.add([
          for (final s in r.secciones)
            FilaDelHome(titulo: s.titulo, tipo: fuente.tipo, obras: s.obras),
        ]);
      }

      filas.assignAll(_intercalar(porZona));
      problemas.assignAll(problemasNuevos);
    } finally {
      cargando.value = false;
    }
  }

  /// Toma la primera fila de cada zona, después la segunda de cada una, y así.
  ///
  /// Con las zonas apiladas, para llegar a una película había que pasar seis
  /// filas de anime. Intercaladas, la primera pantalla ya muestra de todo —
  /// que es justamente para lo que está el Home.
  static List<FilaDelHome> _intercalar(List<List<FilaDelHome>> porZona) {
    final salida = <FilaDelHome>[];
    final maximo =
        porZona.fold<int>(0, (n, l) => l.length > n ? l.length : n);
    for (var vuelta = 0; vuelta < maximo; vuelta++) {
      for (final zona in porZona) {
        if (vuelta < zona.length) salida.add(zona[vuelta]);
      }
    }
    return salida;
  }
}
