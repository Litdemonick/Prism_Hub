import 'package:prismhub/data/metadata/metadata_item.dart';

/// Por qué el catálogo no puede fallar en silencio.
///
/// Una fuente cae, o pide una clave que el usuario no puso. La pantalla tiene
/// que poder decir CUÁL de las dos cosas pasó: "probá más tarde" y "te falta la
/// clave" llevan al usuario a lugares distintos, y un vacío mudo no lleva a
/// ninguno. Por eso el resultado viaja con su motivo.
enum MotivoSinCatalogo {
  /// La fuente necesita una clave que el usuario todavía no configuró.
  faltaLaClave,

  /// Se pidió y no contestó, o contestó mal. Reintentar puede servir.
  fuenteCaida,
}

/// Lo que devuelve una fuente: las secciones, o el motivo por el que no hay.
class RespuestaDelCatalogo {
  const RespuestaDelCatalogo.ok(this.secciones)
      : motivo = null,
        detalle = null;

  const RespuestaDelCatalogo.sinDatos(this.motivo, {this.detalle})
      : secciones = const [];

  final List<SeccionDelCatalogo> secciones;
  final MotivoSinCatalogo? motivo;

  /// Texto crudo para el registro. **No se le muestra al usuario**: la pantalla
  /// arma su propio mensaje a partir de [motivo].
  final String? detalle;

  bool get hayDatos => motivo == null;
}

/// De dónde salen los metadatos de una zona del catálogo.
///
/// Existe para que la pantalla no sepa nada de AniList ni de TMDB. Hoy hay dos
/// implementaciones y no es un capricho:
///
///   AniList  anime y mangas. Su API pública **no pide clave**, así que esas
///            zonas funcionan desde el primer arranque sin configurar nada.
///   TMDB     series y películas. Pide la clave del usuario, y para mangas
///            directamente no sirve: es cine y televisión.
///
/// Cambiar una fuente por otra es escribir otra clase y cambiar dónde se elige,
/// sin tocar el Home. Es la misma idea que hace que las extensiones sean
/// intercambiables, aplicada al catálogo.
abstract class FuenteDeCatalogo {
  /// Qué zona sirve esta fuente.
  TipoDeObra get tipo;

  /// Si hoy puede responder. En false, la zona muestra qué le falta.
  bool get lista;

  /// Las filas de la portada de esa zona: tendencias, populares, lo nuevo…
  Future<RespuestaDelCatalogo> portada();

  /// Buscar por texto dentro de esta zona.
  Future<List<ObraDelCatalogo>> buscar(String texto, {int pagina = 1});
}
