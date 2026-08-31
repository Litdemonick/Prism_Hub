import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/search_text.dart';

/// Una entrada del catálogo del repositorio, ya leída y normalizada.
///
/// ── Por qué existe ──────────────────────────────────────────────────────
///
/// El catálogo llega como una lista de mapas sueltos, con campos que
/// cambiaron de nombre entre versiones (`script` hoy, `url` en los repos
/// viejos), banderas que vienen como texto o como booleano según quién lo
/// publicó, y un par de reglas que no están en los datos sino en el código
/// —una extensión que pide una versión de la app más nueva se trata como no
/// instalable, con otro motivo—.
///
/// Todo eso estaba escrito dentro del `build` de la pantalla de teléfono. Al
/// hacer la de televisor había dos caminos: copiarlo, o sacarlo acá. Copiado
/// se rompe solo: alcanza con que el catálogo agregue un campo y una de las
/// dos pantallas se entere.
class EntradaDelRepo {
  const EntradaDelRepo({
    required this.package,
    required this.name,
    required this.version,
    required this.lang,
    required this.type,
    required this.nsfw,
    required this.unstable,
    required this.claveDelBloqueo,
    this.icon,
    this.url,
    this.webSite,
    this.license,
    this.description,
    this.signature,
    this.motivoInestable,
  });

  final String package;
  final String name;
  final String version;
  final String lang;
  final ExtensionType type;
  final bool nsfw;

  /// No se puede instalar: o el catálogo la marcó inestable, o pide una
  /// versión de la app más nueva que esta.
  final bool unstable;

  /// Clave i18n que explica POR QUÉ está bloqueada. No es lo mismo «esperá un
  /// arreglo de la extensión» que «actualizá PrismHub».
  final String claveDelBloqueo;

  final String? icon;
  final String? url;
  final String? webSite;
  final String? license;
  final String? description;
  final String? signature;
  final String? motivoInestable;

  bool get instalada => ExtensionUtils.runtimes.containsKey(package);

  /// Lee una entrada del catálogo. Devuelve null si le falta algo sin lo cual
  /// no se puede ni mostrar ni instalar.
  static EntradaDelRepo? leer(dynamic entrada) {
    if (entrada is! Map) return null;
    final package = entrada['package'];
    final name = entrada['name'];
    final version = entrada['version'];
    final lang = entrada['lang'];
    if (package == null || name == null || version == null || lang == null) {
      return null;
    }
    final pideAppMasNueva = ExtensionUtils.entryNeedsNewerApp(entrada);
    return EntradaDelRepo(
      package: '$package',
      name: '$name',
      version: '$version',
      lang: '$lang',
      type: ExtensionType.values.firstWhere(
        (t) => t.toString() == 'ExtensionType.${entrada['type']}',
        orElse: () => ExtensionType.bangumi,
      ),
      // Las banderas llegan como texto o como booleano según quién publicó la
      // entrada. Comparar contra las dos formas es lo que ya hacía la
      // pantalla de teléfono; acá queda en un solo sitio.
      nsfw: entrada['nsfw'] == 'true' || entrada['nsfw'] == true,
      unstable: entrada['unstable'] == 'true' ||
          entrada['unstable'] == true ||
          pideAppMasNueva,
      claveDelBloqueo: pideAppMasNueva
          ? 'extension.needs-newer-app'
          : ExtensionUtils.claveMotivoInestable(entrada['unstableReason']),
      icon: entrada['icon'] as String?,
      // El catálogo de prism+ trae la dirección del guion en `script`; los
      // repos antiguos usaban `url`. Se aceptan las dos.
      url: (entrada['script'] ?? entrada['url']) as String?,
      webSite: entrada['webSite'] as String?,
      license: entrada['license'] as String?,
      description: entrada['description'] as String?,
      signature: entrada['signature'] as String?,
      motivoInestable: entrada['unstableReason'] as String?,
    );
  }

  static List<EntradaDelRepo> leerTodas(Iterable<dynamic> entradas) => entradas
      .map(EntradaDelRepo.leer)
      .whereType<EntradaDelRepo>()
      .toList(growable: false);
}

/// Los filtros del repositorio, aplicados en un solo sitio.
///
/// Son siete y se combinan entre sí. Escritos dos veces, lo que se rompe no
/// es «un filtro»: es una pantalla que muestra extensiones +18 donde la otra
/// no, que es el peor de los fallos posibles acá.
class FiltrosDelRepo {
  const FiltrosDelRepo({
    this.texto = '',
    this.tipos,
    this.zona,
    this.idioma = 'all',
    this.nivel = 'all',
    this.nsfw = 'all',
    this.instalacion = 'all',
    this.nsfwDesbloqueado = false,
  });

  /// Lo escrito en el buscador.
  final String texto;

  /// Vídeo o lectura, en general. Null = sin filtrar por tipo.
  final Set<ExtensionType>? tipos;

  /// Más fino que [tipos]: «aporta a ESTA zona». Null = todas.
  final ZonaPrincipal? zona;

  final String idioma;

  /// 'all' | 'stable' | 'unstable'
  final String nivel;

  /// 'all' | 'sfw' | 'nsfw'
  final String nsfw;

  /// 'all' | 'installed' | 'available' | 'new'
  final String instalacion;

  /// Se dio el PIN en ESTA visita. Sin esto las +18 no salen nunca, diga lo
  /// que diga [nsfw] — el filtro es una ayuda para encontrar, la compuerta es
  /// esto.
  final bool nsfwDesbloqueado;

  /// [esNueva] lo contesta el controlador: el catálogo no trae fecha de
  /// publicación, así que «nueva» es «no estaba la última vez que se abrió» y
  /// eso solo lo sabe quien guarda esa lista.
  List<EntradaDelRepo> aplicar(
    List<EntradaDelRepo> todas, {
    required bool Function(String package) esNueva,
  }) {
    // Los sinónimos dejan filtrar por tipo escribiendo en el mismo buscador
    // («anime», «manga») sin tener que ir al selector de tipo.
    final tiposDelTexto = texto.isEmpty
        ? null
        : SearchText.inferTypeFromQuery(
            texto,
            ExtensionUtils.videoTypes,
            ExtensionUtils.readingTypes,
          );
    return todas.where((e) {
      if (texto.isNotEmpty) {
        final porNombre = SearchText.matchesQuery(e.name, texto);
        final porTipo = tiposDelTexto != null && tiposDelTexto.contains(e.type);
        if (!porNombre && !porTipo) return false;
      }
      if (tipos != null && !tipos!.contains(e.type)) return false;
      if (zona != null) {
        // Sin clasificar (zonasDe da vacío) queda AFUERA de este filtro a
        // propósito, igual que en toda la app: sin `@contentKind` declarado no
        // se puede asegurar a qué zona pertenece. Se sigue viendo en «Todas».
        if (!ExtensionUtils.zonasDe(e.package).contains(zona)) return false;
      }
      if (idioma != 'all' && !ExtensionUtils.coincideIdioma(e.lang, idioma)) {
        return false;
      }
      if (nivel != 'all' && e.unstable != (nivel == 'unstable')) return false;
      if (nsfw != 'all' && e.nsfw != (nsfw == 'nsfw')) return false;
      if (!nsfwDesbloqueado && e.nsfw) return false;
      return switch (instalacion) {
        'installed' => e.instalada,
        'available' => !e.instalada,
        'new' => esNueva(e.package),
        _ => true,
      };
    }).toList(growable: false);
  }
}
