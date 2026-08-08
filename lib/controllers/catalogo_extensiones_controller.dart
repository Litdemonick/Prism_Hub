import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
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

/// Qué criterio usa una fila para traer su contenido.
enum ModoDeFila {
  /// Lo último que publicó la extensión. Es lo que da `latest()`, y lo que
  /// pueden todas.
  reciente,

  /// Lo más visto. Solo donde la extensión tiene un orden por popularidad —
  /// medido: JKAnime, LaMovie y ManhwaWeb. En las demás no se puede pedir.
  popular,

  /// Hay un filtro puesto: lo que manda es el filtro, no el criterio.
  filtrado,
}

/// Una fila del Home: una extensión y lo último que tiene.
class FilaDeExtension {
  FilaDeExtension({
    required this.package,
    required this.nombre,
    this.estadoExt = EstadoExtension.activa,
    this.esVistaPrevia = false,
  });

  final String package;
  final String nombre;
  final EstadoExtension estadoExt;

  /// El usuario NO la tiene instalada: se cargó solo para que el Home tenga
  /// contenido. Al tocar una de sus tarjetas se le ofrece instalarla.
  final bool esVistaPrevia;

  /// Qué está mostrando esta fila. Lo decide el controlador al armar la lista
  /// y se dice en el encabezado, para que el usuario sepa qué está viendo.
  ModoDeFila modo = ModoDeFila.reciente;

  /// Por qué página va. Sube cuando el usuario llega al final del carrusel y
  /// se piden más portadas. Ver `traerMas`.
  int pagina = 1;

  final estado = EstadoDeFila.pendiente.obs;
  final items = <ExtensionListItem>[].obs;

  /// ESTA fila está pidiendo algo ahora mismo.
  ///
  /// ── Por qué no alcanzaba con `estado` ───────────────────────────────────
  ///
  /// `estado` pasa a `cargando` solo cuando la fila no tiene NADA que mostrar:
  /// refrescar una que ya tiene portadas la deja en `lista` todo el tiempo, a
  /// propósito, para que las tarjetas no desaparezcan mientras llega lo nuevo.
  ///
  /// Pero entonces no había forma de saber que esa fila estaba trabajando, y el
  /// encabezado tenía que mirar una bandera GLOBAL —«se están aplicando
  /// filtros»— que no se apaga hasta que contestan las once. Resultado: filas
  /// que ya tenían su contenido nuevo seguían diciendo «Buscando…» durante
  /// veinte segundos por culpa de la más lenta.
  ///
  /// Con esto cada fila apaga su propio cartel en cuanto le llega lo suyo.
  final refrescando = false.obs;

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

  /// Ya se terminó de mirar qué extensiones hay.
  ///
  /// Hasta que sea true, una lista vacía significa «todavía no sé», no «no hay
  /// nada» — y el Home muestra bloques en vez del mensaje de vacío.
  final armado = false.obs;

  /// Las tandas que el carrusel puede mostrar AHORA.
  ///
  /// ── Por qué no es `destacados` a secas ──────────────────────────────────
  ///
  /// Porque con un filtro puesto, las extensiones que no lo tienen siguen
  /// trayendo su contenido de siempre —y está bien, su fila lo aclara con «Lo
  /// más reciente»—. Pero el carrusel no tiene encabezado por extensión: es una
  /// sola tira. Ahí, una película de FuegoCine entre puros animes en emisión se
  /// lee como que el filtro no funciona.
  ///
  /// Así que el carrusel muestra solo lo que SÍ está filtrado. Y como es una
  /// vista calculada y no una lista aparte, al restablecer vuelve todo en el
  /// acto sin volver a pedirle nada a nadie.
  List<(String, List<ExtensionListItem>)> get destacadosVisibles {
    final lista = hayFiltros
        ? destacados.where((d) => puedeConEsteGenero(d.$1)).toList()
        : destacados.toList();
    return _rotadas(lista);
  }

  /// La misma lista, empezando por otra extensión.
  ///
  /// ── Por qué rota ────────────────────────────────────────────────────────
  ///
  /// El acordeón intercala una portada de cada extensión, así que de entrada ya
  /// se ven ocho distintas. Pero la PRIMERA era siempre la misma —la primera de
  /// la lista— y esa se lleva la atención: es la grande del centro al abrir.
  ///
  /// Rotando, cada vez que se abre la app arranca por la siguiente. Se recorre
  /// el mismo contenido y en el mismo orden relativo; lo único que cambia es por
  /// dónde se entra. Nada se repite ni se pierde: es la misma lista corrida.
  /// Por qué extensión arranca, guardada POR NOMBRE y no por posición.
  ///
  /// ── El error que esto corrige ───────────────────────────────────────────
  ///
  /// Antes se rotaba con `_arranque % lista.length`, y esa cuenta cambia de
  /// resultado cada vez que cambia el LARGO de la lista. Y el largo cambia
  /// todo el tiempo: cada extensión que termina de cargar se suma, y poner o
  /// sacar un filtro agrega o quita varias de una.
  ///
  /// O sea que el acordeón se reordenaba solo. Al restablecer los filtros se
  /// veía clarísimo —mostraba una cosa, y al rato otra— pero también pasaba
  /// mientras el Home cargaba, con cada extensión que iba contestando.
  ///
  /// Guardando el PAQUETE, la rotación es la misma pase lo que pase con el
  /// largo: se busca esa extensión y se empieza por ella.
  String? _paqueteDeArranque;

  List<(String, List<ExtensionListItem>)> _rotadas(
      List<(String, List<ExtensionListItem>)> lista) {
    if (lista.length < 2) return lista;
    _paqueteDeArranque ??= lista[_arranque % lista.length].$1;
    final desde = lista.indexWhere((d) => d.$1 == _paqueteDeArranque);
    // Si no está en esta vista —la sacó un filtro— se empieza por la primera,
    // igual que antes cuando la cuenta daba cero.
    if (desde <= 0) return lista;
    return [...lista.sublist(desde), ...lista.sublist(0, desde)];
  }

  /// Por qué extensión entra el acordeón esta vez.
  ///
  /// Se guarda en disco y sube de uno en cada apertura, así que cambia sola
  /// aunque la app se cierre por completo. Un número al azar no servía: dos
  /// aperturas seguidas podían caer en la misma y parecía que no rotaba.
  int _arranque = 0;

  /// Sube cada vez que hay que llevar el acordeón al principio.
  ///
  /// Un contador y no un booleano: un booleano habría que apagarlo después, y si
  /// el acordeón no estaba montado en ese momento se perdería el aviso. Con un
  /// número, el acordeón compara con el último que vio y se pone al día cuando
  /// le toque, sin que nadie tenga que limpiar nada.
  final reinicios = 0.obs;

  /// Cuántas se toman de cada extensión para el carrusel.
  ///
  /// Ocho y no cinco: el acordeón deja ver cuatro o cinco de un vistazo, así
  /// que con cinco por extensión el usuario llegaba al final de la tanda casi
  /// sin deslizar. No cuesta nada — ya vienen en la misma respuesta de
  /// `latest()`, y el acordeón solo construye las que están cerca del foco.
  static const porExtension = 8;

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

  /// El acordeón ya se puso en su sitio en esta sesión del Home.
  ///
  /// ── Por qué vive acá y no en el widget ──────────────────────────────────
  ///
  /// Porque el widget se DESTRUYE al salir de pantalla: el Home es un
  /// `ListView.builder` y el acordeón es su ítem 2, así que basta con bajar
  /// un poco para que Flutter lo desmonte. Al volver a subir se creaba de
  /// cero, con su marca de «ya me ubiqué» en falso, y volvía a arrancar en la
  /// primera tarjeta. Reportado en vivo: «al hacer scroll el acordeón se
  /// vuelve al inicio».
  ///
  /// El controlador sobrevive a todo eso, así que la marca también. Sigue
  /// valiendo la regla de que abrir el Home empieza de cero — lo que cambia es
  /// que desplazarse ya no cuenta como abrirlo.
  bool acordeonUbicado = false;

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

  // ─── Los filtros del Home ─────────────────────────────────────────────────
  //
  // ── Lo que se puede filtrar y lo que no ─────────────────────────────────
  //
  // Se midió extensión por extensión (2026-08-07):
  //
  //   · **Tipo** (anime, series y películas, manga, novela): sale de
  //     `extension.type`, que la app ya tiene para las 17. Es fiable siempre y
  //     no hace falta preguntarle nada al sitio — se filtra qué FILAS se
  //     muestran, no qué trae cada una.
  //
  //   · **Género** (romance, terror…): sale del `createFilter()` de cada
  //     extensión. Lo tienen 8 de las 11 que no son +18. FuegoCine, Olympus y
  //     ShadeManga NO: a esas un género no les puede hacer nada, y se dicen
  //     así en pantalla en vez de mostrarlas vacías.
  //
  // ── Por qué se comparan por ETIQUETA y no por clave ─────────────────────
  //
  // Porque la clave es del sitio: «Romance» es `romance` en una, `12` en otra
  // y `genero/romance/` en la tercera. No hay forma de cruzarlas. La etiqueta,
  // en cambio, es el texto que el propio sitio le muestra a la gente, y ahí sí
  // coinciden. Así que un chip «Romance» se traduce, extensión por extensión,
  // a la clave que cada una espera.
  //
  // ── Por qué no se aplica al tocar ───────────────────────────────────────
  //
  // Porque aplicar significa volver a pedirle a ONCE sitios. Tocando tres
  // chips seguidos serían tres tandas de once pedidos, y las dos primeras se
  // tiran a la basura. Se elige tranquilo y se aplica de una, tirando de la
  // pantalla hacia abajo.

  /// ── La lista de géneros es CURADA, no la unión de todo ─────────────────
  ///
  /// La primera versión juntaba todas las opciones de todas las extensiones.
  /// Salían más de cien chips, y entre ellos «Blu-ray», «Castellano»,
  /// «Aenime», «Especial» y «Todas» — que no son géneros — más duplicados por
  /// idioma y por acento.
  ///
  /// Se midió qué ofrece cada una (2026-08-07, ocho extensiones no +18 con
  /// filtro de género). El vocabulario resultó bastante consistente en
  /// español, así que no hace falta traducir nada: alcanza con **elegir** los
  /// que de verdad son géneros y aceptar las variantes con que cada sitio los
  /// escribe.
  ///
  /// ── La clave es un IDENTIFICADOR, no un texto ──────────────────────────
  ///
  /// La app está en español y en inglés, así que lo que se ve en el chip sale
  /// de i18n (`home.genero.<id>`). Si la clave fuera «Acción», el género
  /// elegido cambiaría de nombre al cambiar de idioma y dejaría de coincidir
  /// con lo guardado.
  ///
  /// La lista son las formas ya normalizadas —minúsculas y sin tildes— con las
  /// que el género puede venir del sitio. Van las españolas y las inglesas:
  /// hoy todas las extensiones escriben en español, pero las que vengan en
  /// inglés van a encajar sin tocar nada.
  static const _canonicos = <String, List<String>>{
    'accion': ['accion', 'action'],
    'aventura': ['aventura', 'aventuras', 'adventure'],
    'comedia': ['comedia', 'comedy'],
    'drama': ['drama'],
    'romance': ['romance', 'romantico', 'romantica'],
    'terror': ['terror', 'horror'],
    'suspenso': ['suspenso', 'suspense', 'thriller'],
    'misterio': ['misterio', 'mystery'],
    'fantasia': ['fantasia', 'fantasy'],
    'ciencia-ficcion': [
      'ciencia ficcion',
      'ciencia-ficcion',
      'sci-fi',
      'scifi',
      'science fiction'
    ],
    'sobrenatural': ['sobrenatural', 'supernatural'],
    'psicologico': ['psicologico', 'psychological'],
    'artes-marciales': ['artes marciales', 'marcial', 'martial arts'],
    'deportes': ['deportes', 'deporte', 'sports'],
    'historico': ['historico', 'historia', 'historical'],
    'escolar': ['escolares', 'escolar', 'colegial', 'vida escolar', 'school'],
    'magia': ['magia', 'magic'],
    'mecha': ['mecha'],
    'militar': ['militar', 'military'],
    'recuentos': [
      'recuentos de la vida',
      'cosas de la vida',
      'vida cotidiana',
      'slice of life',
    ],
    // ── Los que salieron del segundo barrido ─────────────────────────────
    //
    // Se volvió a medir pidiendo etiquetas presentes en DOS o más extensiones
    // en vez de tres. Estos aparecieron con esa vara, y son géneros de verdad
    // —no estados como «Finalizado» ni formatos como «OVA», que se
    // descartaron a mano—.
    'ecchi': ['ecchi'],
    'harem': ['harem'],
    'superpoderes': ['superpoderes', 'super poderes', 'super power'],
    'demonios': ['demonios', 'demons'],
    'gore': ['gore'],
    'vampiros': ['vampiros', 'vampire', 'vampires'],
    'isekai': ['isekai'],
    'tragedia': ['tragedia', 'tragedy'],
    'parodia': ['parodia', 'parody'],
    'musica': ['musica', 'music', 'musical'],
    'policia': ['policia', 'policial', 'police'],
    'samurai': ['samurai', 'samurais'],
    'espacial': ['espacial', 'space'],
    'apocaliptico': ['apocaliptico', 'post-apocaliptico', 'apocalyptic'],
    'reencarnacion': ['reencarnacion', 'reincarnation'],
    'infantil': ['infantil', 'kids'],
    'carreras': ['carreras', 'racing'],
    'demencia': ['demencia', 'dementia'],
    'boys-love': ['boys love', 'boys-love', 'yaoi', 'bl'],
    'girls-love': ['girls love', 'girls-love', 'yuri', 'gl'],
    // Demografías. No son género en sentido estricto, pero en un catálogo de
    // manga y anime es por donde mucha gente busca.
    'shounen': ['shounen', 'shonen'],
    'shoujo': ['shoujo', 'shojo'],
    'seinen': ['seinen'],
    'josei': ['josei'],
  };

  /// ── El estado, el otro eje que sirve para todas ────────────────────────
  ///
  /// Del barrido de filtros (2026-08-07) salió que cinco extensiones tienen un
  /// filtro «Estado» con las mismas dos ideas: lo que sigue saliendo y lo que
  /// ya terminó. Es de las primeras cosas que alguien quiere acotar —«algo
  /// terminado, para maratonear»— y no estaba.
  static const _estados = <String, List<String>>{
    'emision': [
      'en emision',
      'emision',
      'en emisión',
      'publicandose',
      'en curso',
      'ongoing',
      'airing',
      'releasing',
    ],
    'finalizado': [
      'finalizado',
      'finalizada',
      'completado',
      'concluido',
      'terminado',
      'finished',
      'completed',
    ],
  };

  /// ── El formato: película, serie, OVA… ──────────────────────────────────
  ///
  /// Sale del filtro «Tipo», que ocho extensiones tienen. Del barrido salieron
  /// etiquetas comparables: FuegoCine da «Películas/Series», AnimeFenix
  /// «Película/Serie/OVA/Especial/Corto», JKAnime «Animes/Películas/Ovas».
  ///
  /// OJO, esto NO es lo mismo que los chips de Vídeo/Manga/Novela que se
  /// sacaron. Aquellos eran el tipo de la EXTENSIÓN —y eso ya lo dice el
  /// nombre de la fila—; esto es el formato de cada obra, que es una pregunta
  /// distinta: «quiero una película», no «quiero una extensión de vídeo».
  static const _formatos = <String, List<String>>{
    'pelicula': ['pelicula', 'peliculas', 'movie', 'movies', 'film'],
    'serie': ['serie', 'series', 'tv', 'tv anime', 'anime', 'animes'],
    'ova': ['ova', 'ovas', 'ona', 'onas'],
    'especial': ['especial', 'especiales', 'special', 'corto', 'cortos'],
    'manhwa': ['manhwa', 'manhwas'],
    'manhua': ['manhua', 'manhuas'],
    'manga': ['manga', 'mangas'],
    'novela': ['novela', 'novelas', 'novel', 'light novel'],
  };

  /// Un chip solo aparece si al menos ESTAS extensiones pueden contestarlo.
  ///
  /// Con una sola, tocarlo dejaba el Home con una fila y quince líneas de «no
  /// tiene ese género» — se leía como que el filtro rompió algo.
  static const _minimoParaOfrecer = 2;

  /// Los géneros que se ofrecen, en el orden de [_canonicos].
  final generosDisponibles = <String>[].obs;

  /// Los estados que se ofrecen, en el orden de [_estados].
  final estadosDisponibles = <String>[].obs;
  final formatosDisponibles = <String>[].obs;

  final estadoElegido = RxnString();
  String? estadoAplicado;

  final formatoElegido = RxnString();
  String? formatoAplicado;

  /// Lo que el usuario tocó pero todavía no aplicó.
  final tipoElegido = Rxn<ExtensionType>();
  final generoElegido = RxnString();

  /// Lo que está aplicado de verdad, o sea con lo que se pidió el contenido.
  ExtensionType? tipoAplicado;
  String? generoAplicado;

  bool get hayCambiosSinAplicar =>
      tipoElegido.value != tipoAplicado ||
      generoElegido.value != generoAplicado ||
      estadoElegido.value != estadoAplicado ||
      formatoElegido.value != formatoAplicado;

  bool get hayFiltros =>
      tipoAplicado != null ||
      generoAplicado != null ||
      estadoAplicado != null ||
      formatoAplicado != null;

  /// Hay un cambio de filtro en curso.
  ///
  /// Mientras dure, las filas muestran los bloques grises en vez de su
  /// contenido: lo que está en pantalla es del filtro anterior, y dejarlo
  /// quieto haría creer que tocar el chip no sirvió de nada.
  final aplicandoFiltros = false.obs;

  /// Para cada extensión y cada valor canónico —género o estado—, EN QUÉ
  /// filtro vive y con qué valor se pide.
  ///
  /// ── Por qué se guarda también la clave del filtro ──────────────────────
  ///
  /// Porque el mismo concepto no vive siempre en el mismo sitio. Medido: en
  /// JKAnime, ManhwaWeb y TuMangaOnline, «Shounen» y «Seinen» NO están bajo
  /// «Género» sino bajo un filtro aparte llamado «Demografía». Buscando solo
  /// en «Género», esos cuatro chips no funcionaban en ninguna extensión.
  ///
  /// Así que se miran TODOS los filtros de cada extensión y se anota, valor
  /// por valor, de qué filtro salió.
  /// Por extensión, el valor SEGURO de cada filtro que tiene una puerta a
  /// contenido adulto.
  ///
  /// ── Por qué se manda aunque ya sea el defecto ───────────────────────────
  ///
  /// Se midió (2026-08-08): solo ManhwaWeb y ShadeManga son mixtas —tienen
  /// contenido normal y +18 detrás de un filtro— y las dos ya ponen «no» por su
  /// cuenta cuando no se les dice nada.
  ///
  /// Pero eso es una promesa de cada extensión, no una garantía del app. Una
  /// extensión nueva, o una actualización distraída, alcanzarían para que el
  /// Home empiece a mostrar +18 sin que nadie se entere. Mandándolo explícito,
  /// la regla la fija PrismHub y no depende de nadie.
  ///
  /// Y es lo que permite que estas extensiones SALGAN en la zona normal en vez
  /// de esconderlas enteras: se muestra lo suyo, sin la parte de adultos.
  final _segurosPorExtension = <String, Map<String, List<String>>>{};

  final _ejesPorExtension =
      <String, Map<String, ({String clave, String valor})>>{};
  bool _generosLeidos = false;

  /// Minúsculas, sin tildes y sin espacios de más.
  ///
  /// Es lo que permite que «Ciencia Ficción», «ciencia ficcion» y «Ciencia
  /// ficción» sean lo mismo sin tener que anotarlas las tres.
  static String _normalizar(String s) {
    const con = 'áàäâéèëêíìïîóòöôúùüûñç';
    const sin = 'aaaaeeeeiiiioooouuuunc';
    var r = s.toLowerCase().trim();
    for (var i = 0; i < con.length; i++) {
      r = r.replaceAll(con[i], sin[i]);
    }
    return r.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// A qué género canónico corresponde una etiqueta del sitio, si a alguno.
  static String? _canonicoDe(String etiqueta) {
    final n = _normalizar(etiqueta);
    if (n.isEmpty) return null;
    for (final e in _canonicos.entries) {
      if (e.value.contains(n)) return e.key;
    }
    return null;
  }

  /// Todos los motores que alimentan el Home: los encendidos y los de vista
  /// previa.
  ///
  /// Los dos, porque las filas del Home salen de los dos. Mirando solo los
  /// encendidos, un usuario sin nada activado no veía ningún chip aunque el
  /// Home estuviera lleno de contenido de la vista previa.
  Map<String, ExtensionService> get _motoresDelHome => {
        ...ExtensionUtils.enabledRuntimes,
        ...ExtensionUtils.vistaPrevia,
      };

  /// Lee los géneros de cada extensión y arma la lista de chips.
  ///
  /// Una extensión que falle o que no tenga género no rompe nada: simplemente
  /// no aporta.
  Future<void> cargarGeneros() async {
    // ── Marca de EN CURSO, no de HECHO ──────────────────────────────────
    //
    // Antes se marcaba como leído al entrar, y si el escaneo no encontraba
    // nada —porque la cola nunca se vació, o porque las extensiones no
    // contestaron— quedaba marcado igual y NO SE REINTENTABA NUNCA. Los chips
    // de filtro no aparecían en toda la sesión.
    //
    // Ahora la marca definitiva se pone solo cuando de verdad se leyó algo. Si
    // falló, la próxima vez que alguien pida los géneros se vuelve a intentar.
    if (_generosLeidos || _leyendoGeneros) return;
    _leyendoGeneros = true;
    try {
      await _leerGeneros();
    } finally {
      _leyendoGeneros = false;
    }
  }

  bool _leyendoGeneros = false;

  /// Esta extensión está pidiendo contenido ahora mismo.
  ///
  /// Preguntarle los filtros mientras tanto haría que las dos llamadas se
  /// pisen en su motor QuickJS y fallen las dos.
  bool _ocupada(String package) {
    for (final f in filas) {
      if (f.package != package) continue;
      return f.estado.value == EstadoDeFila.cargando || _cola.contains(f);
    }
    return false;
  }

  Future<void> _leerGeneros() async {
    // ── Primero que terminen las filas ─────────────────────────────────
    //
    // `createFilter()` y `latest()` corren en el MISMO motor QuickJS de cada
    // extensión, y ese motor no es reentrante — el comentario de
    // extension_service.dart:715 ya documenta un error viejo por dos llamadas
    // pisándose sobre la misma instancia.
    //
    // Llamando a los géneros apenas se monta el Home, las `createFilter()`
    // caían encima de las `latest()` que estaban en vuelo y **fallaban las
    // dos**: el Home entero quedaba diciendo «no respondió».
    // Un respiro para que arranque la primera tanda, y nada más. Esperar a que
    // la cola se vacíe ENTERA era el error: en una tablet con el emulador
    // lento, o con `traerMas` pidiendo más páginas, esa cola casi nunca está
    // vacía. Se agotaban los treinta segundos, el escaneo salía con las manos
    // vacías y los chips no aparecían nunca. En el teléfono sí, porque
    // contestaba más rápido — de ahí que pasara en una y no en la otra.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // Lo guardado ya está en pantalla; esto lo confirma o lo corrige. Si el
    // escaneo no encuentra nada —sin extensiones activas, todas fallando— se
    // deja lo anterior en vez de vaciar la barra.
    final cuantas = <String, int>{};
    var alguna = false;
    var salteadas = 0;
    for (final e in _motoresDelHome.entries) {
      final runtime = e.value;
      // ── Se saltea la que está ocupada, no se espera a todas ────────────
      //
      // El motor QuickJS es de CADA extensión, así que el choque es por
      // extensión y no global: mientras JKAnime trae su contenido, se le
      // pueden pedir los filtros a TioAnime sin ningún riesgo.
      //
      // La que esté ocupada se saltea y queda para el próximo intento — que
      // sale solo, porque la barra vuelve a pedir los géneros mientras no
      // tenga ninguno.
      if (_ocupada(e.key)) {
        salteadas++;
        continue;
      }
      // Las +18 no entran al Home, así que sus filtros tampoco.
      if (runtime.extension.nsfw) continue;
      try {
        final filtros =
            await runtime.createFilter().timeout(const Duration(seconds: 8));

        final deEsta = <String, ({String clave, String valor})>{};
        for (final f in filtros.entries) {
          // Un filtro con puerta a adultos: se anota su valor seguro —el que
          // la propia extensión declara como defecto— para mandarlo siempre.
          final adulto = f.value.adultOption;
          if (adulto != null && adulto.isNotEmpty) {
            (_segurosPorExtension[e.key] ??= {})[f.key] = [
              f.value.defaultOption
            ];
          }
          final titulo = _normalizar(f.value.title);
          // «Género (+18)», «Adultos» y compañía: ni se miran.
          if (titulo.contains('18') || titulo.contains('adult')) continue;

          // ¿Este filtro sabe ordenar por lo más visto?
          if (titulo.contains('orden')) {
            f.value.options.forEach((clave, etiqueta) {
              if (clave.isEmpty) return;
              if (!_formasDePopular.contains(_normalizar(etiqueta))) return;
              _popularPorExtension.putIfAbsent(
                  e.key, () => (clave: f.key, valor: clave));
            });
          }

          f.value.options.forEach((clave, etiqueta) {
            if (clave.isEmpty) return;
            final id = _canonicoDe(etiqueta) ??
                _estadoDe(etiqueta) ??
                _deLista(_formatos, etiqueta);
            // Lo que no está en las listas curadas se descarta. Ahí quedan
            // afuera «Blu-ray», «Castellano», las ochenta y pico de
            // TuMangaOnline, y los ejes que no sirven de forma global —el
            // orden, la letra, el año—.
            if (id == null) return;
            // Si el mismo valor aparece en dos filtros, manda el primero.
            deEsta.putIfAbsent(id, () => (clave: f.key, valor: clave));
          });
        }

        if (deEsta.isNotEmpty) {
          alguna = true;
          _ejesPorExtension[e.key] = deEsta;
          for (final id in deEsta.keys) {
            cuantas[id] = (cuantas[id] ?? 0) + 1;
          }
        }
      } catch (err) {
        logger
            .info('[home] ${runtime.extension.name} no dio sus filtros: $err');
      }
    }

    // Sin nada leído no se marca como hecho: se reintenta la próxima.
    if (!alguna) return;
    // Y tampoco se cierra si quedó alguna sin consultar: sus géneros faltarían
    // para siempre. Se muestran los que ya hay y el próximo intento completa.
    if (salteadas == 0) _generosLeidos = true;

    bool ofrecible(String id) => (cuantas[id] ?? 0) >= _minimoParaOfrecer;

    // En el orden de las listas curadas, no alfabético: así los más usados
    // —Acción, Aventura, Comedia— quedan primero y no hay que desplazarse.
    generosDisponibles.assignAll(_canonicos.keys.where(ofrecible));
    estadosDisponibles.assignAll(_estados.keys.where(ofrecible));
    formatosDisponibles.assignAll(_formatos.keys.where(ofrecible));
    _repartirModos();
    unawaited(_guardarFiltros());
  }

  /// Decide qué muestra cada fila.
  ///
  /// ── Por qué no todas «Populares» ────────────────────────────────────────
  ///
  /// Porque el Home se lee de arriba abajo y si todas las filas dijeran lo
  /// mismo, el rótulo dejaría de significar nada. Alternando, la de arriba
  /// trae lo último y la siguiente lo más visto — y con dos criterios se ve
  /// más variedad de títulos, que es a lo que se vino.
  ///
  /// Se reparte por POSICIÓN y no al azar: al azar, cada apertura de la app
  /// cambiaría el rótulo de una fila que trae exactamente lo mismo, y eso se
  /// lee como que la app no sabe lo que muestra.
  ///
  /// ── Y manda la sección del sitio ────────────────────────────────────────
  ///
  /// Si la extensión declara CÓMO SE LLAMA su sección de novedades —«Programa-
  /// ción», «Episodios recientes», «Novedades»— esa gana, siempre. Es lo que la
  /// página muestra al entrar, con su nombre, y es lo que el usuario espera ver
  /// reflejado.
  ///
  /// Sin esta regla pasaba lo que se reportó con JKAnime: su fila caía en el
  /// turno impar, pedía lo más visto, y el Home mostraba One Piece y Dragon
  /// Ball Z —los de siempre— en vez de la Programación de hoy. El rótulo decía
  /// «Lo más visto», así que no era un error de dibujo: era que estaba pidiendo
  /// otra cosa. Y encima dejaba sin usar el nombre de sección que la extensión
  /// se había tomado el trabajo de declarar.
  ///
  /// Medido: hoy las diecisiete declaran la suya, así que en la práctica ninguna
  /// va por lo más visto. La alternancia se queda igual, no como resto: una
  /// extensión de la comunidad que no declare su sección no tiene nombre propio
  /// que mostrar, y ahí sí conviene la variedad.
  void _repartirModos() {
    var i = 0;
    for (final fila in filas) {
      final ext = ExtensionUtils.runtimes[fila.package]?.extension ??
          ExtensionUtils.vistaPrevia[fila.package]?.extension;
      final tieneSeccionPropia = (ext?.latestLabel?.trim() ?? '').isNotEmpty;
      if (tieneSeccionPropia ||
          !_popularPorExtension.containsKey(fila.package)) {
        fila.modo = ModoDeFila.reciente;
        continue;
      }
      fila.modo = i.isOdd ? ModoDeFila.popular : ModoDeFila.reciente;
      i++;
    }
    filas.refresh();
  }

  /// Cómo se llama «lo más visto» en cada sitio.
  ///
  /// Medido (2026-08-07): de las once no +18, solo JKAnime, LaMovie y
  /// ManhwaWeb tienen un orden por popularidad. Las demás únicamente saben
  /// devolver lo último, y eso es lo que su fila va a decir — no se inventa un
  /// «Populares» que en realidad sería lo mismo de siempre.
  static const _formasDePopular = [
    'popularidad',
    'populares',
    'popular',
    'mas vistos',
    'mas visto',
    'vistos',
    'valorados',
    'views',
  ];

  /// Para cada extensión que sabe ordenar por popularidad: en qué filtro y con
  /// qué valor.
  final _popularPorExtension = <String, ({String clave, String valor})>{};

  /// A qué estado canónico corresponde una etiqueta del sitio, si a alguno.
  static String? _estadoDe(String etiqueta) => _deLista(_estados, etiqueta);

  /// Busca una etiqueta del sitio en una de las listas curadas.
  static String? _deLista(Map<String, List<String>> lista, String etiqueta) {
    final n = _normalizar(etiqueta);
    if (n.isEmpty) return null;
    for (final e in lista.entries) {
      if (e.value.contains(n)) return e.key;
    }
    return null;
  }

  /// ¿Esta extensión puede contestar al género que está aplicado?
  bool puedeConEsteGenero(String package) {
    final ejes = _ejesPorExtension[package];
    for (final id in [generoAplicado, estadoAplicado]) {
      if (id == null) continue;
      if (ejes == null || !ejes.containsKey(id)) return false;
    }
    final formato = formatoAplicado;
    if (formato != null) {
      final loTieneComoFiltro = ejes?.containsKey(formato) ?? false;
      if (!loTieneComoFiltro && !_yaEsDeEseFormato(package, formato)) {
        return false;
      }
    }
    return true;
  }

  /// La extensión ENTERA es de ese formato, así que no necesita filtrarlo.
  ///
  /// ── El caso que faltaba ─────────────────────────────────────────────────
  ///
  /// Olympus es un sitio de manga y su `type` lo dice, pero NO tiene filtro
  /// «Tipo» — porque todo lo que publica ya es manga, no hay nada que elegir.
  /// Con la regla anterior, pedirle el formato «Manga» lo dejaba afuera: justo
  /// al revés de lo que corresponde.
  ///
  /// ── Por qué solo manga y novela ─────────────────────────────────────────
  ///
  /// Porque son los únicos donde el tipo de la extensión ES el formato. Un
  /// sitio de vídeo tiene películas Y series mezcladas, así que su `type` no
  /// alcanza para contestar «solo películas»: ahí sí hace falta el filtro del
  /// sitio, y si no lo tiene, no puede.
  bool _yaEsDeEseFormato(String package, String formato) {
    final tipo = ExtensionUtils.runtimes[package]?.extension.type ??
        ExtensionUtils.vistaPrevia[package]?.extension.type;
    if (tipo == null) return false;
    return switch (formato) {
      'manga' => tipo == ExtensionType.manga,
      'novela' => tipo == ExtensionType.fikushon,
      _ => false,
    };
  }

  /// ¿Esta fila entra en el tipo elegido?
  bool entraEnElTipo(FilaDeExtension fila) {
    final t = tipoAplicado;
    if (t == null) return true;
    final ext = ExtensionUtils.runtimes[fila.package]?.extension ??
        ExtensionUtils.vistaPrevia[fila.package]?.extension;
    return ext?.type == t;
  }

  /// Deja lo elegido como aplicado y vuelve a pedir todo.
  ///
  /// ── Lo viejo se queda hasta que llegue lo nuevo ────────────────────────
  ///
  /// La primera versión de esto vaciaba `items` y `destacados` antes de pedir
  /// nada. Se veía pésimo y era peligroso: si un sitio tardaba o fallaba —y
  /// con once a la vez siempre falla alguno— esa fila se quedaba SIN nada y
  /// mostrando «no respondió». O sea que aplicar un filtro podía dejar el Home
  /// entero vacío, y encima daba a entender que la culpa era de las
  /// extensiones.
  ///
  /// Ahora solo se marca que hay que volver a pedir (`traidoEl = null`). Cada
  /// fila reemplaza su contenido cuando el suyo llega, y la que falle se queda
  /// con lo de antes — que es exactamente la regla que `_traer` ya seguía para
  /// los refrescos normales.
  ///
  /// El precio es un rato con contenido del filtro anterior en pantalla. Es
  /// mucho más barato que un Home en blanco.
  /// Lo que muestra una fila ahora mismo, para el encabezado.
  ///
  /// Solo dice «según tu filtro» si esta extensión PUEDE contestarlo. Las que
  /// no lo tienen siguen mostrando lo suyo, y el encabezado lo dice: mentirles
  /// con «según tu filtro» sobre contenido que no está filtrado es peor que no
  /// filtrar.
  /// Cómo llama ESTA extensión a su sección de «lo último».
  ///
  /// Sale del manifiesto de la extensión (`@latestLabel`): «Programación»,
  /// «Últimos añadidos», «Novedades». Es el nombre que el propio sitio le da a
  /// esa sección, así que el usuario reconoce de dónde viene lo que ve.
  ///
  /// Null cuando la extensión no lo declara —una vieja, o una de la comunidad—
  /// y ahí el Home cae al texto genérico. Nada se rompe por no tenerlo.
  ///
  /// Y solo aplica al modo «reciente»: con un filtro puesto, o mostrando lo más
  /// visto, la fila NO está mostrando esa sección y decir su nombre sería
  /// mentir.
  String? etiquetaDe(FilaDeExtension fila) {
    if (modoDe(fila) != ModoDeFila.reciente) return null;
    final ext = ExtensionUtils.runtimes[fila.package]?.extension ??
        ExtensionUtils.vistaPrevia[fila.package]?.extension;
    final clave = ext?.latestLabel?.trim();
    if (clave == null || clave.isEmpty) return null;

    // ── Se traduce, con respaldo ────────────────────────────────────────
    //
    // La extensión manda una CLAVE (`programacion`, `novedades`) y acá se
    // busca su texto en el idioma del usuario. Si la clave no está en el
    // diccionario —una extensión de la comunidad que inventó la suya, o una
    // nueva del repo que llegó antes que la traducción— i18n devuelve la ruta
    // completa, que no le sirve a nadie.
    //
    // En ese caso se muestra lo que vino tal cual. Es peor idioma pero es
    // información real, y una extensión no puede quedarse sin rótulo por no
    // estar en una lista nuestra.
    final ruta = 'home.seccion.$clave';
    final texto = ruta.i18n;
    return texto == ruta ? clave : texto;
  }

  ModoDeFila modoDe(FilaDeExtension fila) =>
      (hayFiltros && puedeConEsteGenero(fila.package))
          ? ModoDeFila.filtrado
          : fila.modo;

  Future<void> aplicarFiltros() async {
    // Ya hay uno en curso: tocar «Filtrar» dos veces, o deslizar mientras
    // todavía está pidiendo, encadenaba dos esperas de veinte segundos y dos
    // tandas de pedidos a once sitios. La segunda se descarta.
    if (aplicandoFiltros.value) return;
    tipoAplicado = tipoElegido.value;
    generoAplicado = generoElegido.value;
    estadoAplicado = estadoElegido.value;
    formatoAplicado = formatoElegido.value;
    aplicandoFiltros.value = true;
    // ── Al principio del acordeón ──────────────────────────────────────
    //
    // Filtrar cambia QUÉ contenido hay, así que la posición vieja no significa
    // nada: si estabas en la tarjeta treinta y el filtro deja doce, quedabas al
    // final de una lista que no habías visto. Y si deja cuarenta, arrancabas por
    // el medio sin haber visto lo primero, que es justo lo que pediste ver.
    reinicios.value++;
    for (final fila in filas) {
      fila.traidoEl = null;
      // Se vuelve a la primera página: las que se habían pedido de más son de
      // otra búsqueda y no tienen nada que ver con este filtro.
      fila.pagina = 1;
    }
    // ── Avisar del cambio A MANO ───────────────────────────────────────
    //
    // `tipoAplicado`, `generoAplicado` y `formatoAplicado` son campos planos,
    // no Rx. Eso es a propósito —se leen en cada fila y no hace falta que cada
    // lectura suscriba— pero tiene una consecuencia: al aplicar no cambia nada
    // observable, así que el Obx del Home NO se entera.
    //
    // El síntoma medido en PC: se filtraba y las extensiones que no tenían ese
    // género seguían arriba; había que bajar hasta el final para encontrar las
    // que sí. Recién al salir del Home y volver aparecían ordenadas, porque
    // ahí el árbol se reconstruía por otro motivo.
    //
    // Este `refresh` es el aviso. Y va ANTES de pedir nada: el orden se sabe
    // de entrada —sale de los filtros ya leídos, no del contenido— así que los
    // bloques grises salen directamente en su sitio definitivo y no se mueve
    // nada cuando llegan las portadas.
    filas.refresh();
    try {
      await refrescarTodo();
      // `refrescarTodo` solo ENCOLA; el trabajo sigue después. Se espera a que
      // la cola se vacíe para que los bloques grises no desaparezcan mientras
      // todavía falta traer la mitad de las filas.
      for (var i = 0; i < 80 && (_enVuelo > 0 || _cola.isNotEmpty); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      aplicandoFiltros.value = false;
      // Y otra vez al terminar: alguna fila pudo quedar sin contenido para
      // este filtro, y eso cambia dónde va.
      filas.refresh();
    }
  }

  /// Vuelve a como estaba: sin filtros.
  Future<void> restablecerFiltros() async {
    tipoElegido.value = null;
    generoElegido.value = null;
    estadoElegido.value = null;
    formatoElegido.value = null;
    await aplicarFiltros();
  }

  var _enVuelo = 0;
  final _cola = <FilaDeExtension>[];
  Map<String, dynamic> _cache = const {};

  @override
  void onInit() {
    super.onInit();
    unawaited(_armar());
  }

  /// La fila que YA estaba para ese paquete, si sigue sirviendo.
  ///
  /// ── Por qué no se rehacen todas ─────────────────────────────────────────
  ///
  /// Armar creaba una `FilaDeExtension` nueva para cada paquete, siempre. Y
  /// como armar es lo que corre al instalar, prender o apagar una extensión,
  /// bastaba con tocar UNA para que las otras dieciséis perdieran sus portadas
  /// y su estado, y volvieran a pedir todo desde cero.
  ///
  /// Eso es el parpadeo al refrescar: la pantalla entera se iba a bloques
  /// grises y volvía. Con la fila reusada, las que ya tenían contenido no se
  /// enteran de nada y solo la recién llegada aparece —en su lugar definitivo,
  /// con sus bloques— y se llena sola.
  ///
  /// Se reusa solo si es LA MISMA: mismo nombre, mismo estado, misma clase. Una
  /// que pasó de apagada a encendida tiene que empezar de nuevo, porque lo que
  /// mostraba antes era el aviso de que estaba apagada.
  FilaDeExtension _reusarOCrear(FilaDeExtension recien) {
    for (final vieja in filas) {
      if (vieja.package == recien.package &&
          vieja.nombre == recien.nombre &&
          vieja.estadoExt == recien.estadoExt &&
          vieja.esVistaPrevia == recien.esVistaPrevia) {
        return vieja;
      }
    }
    return recien;
  }

  /// Cuántas veces se volvió a intentar armar por no haber motores todavía.
  int _reintentosDeArmado = 0;

  /// Para que dos armados no se pisen.
  ///
  /// A `_armar` se llega por tres caminos: al abrir, al prender una extensión
  /// desde su fila, y al terminar la carga de segundo plano. Los tres pueden
  /// caer casi juntos, y como tiene `await` adentro, dos ejecuciones se
  /// entrelazan y la segunda pisa la lista que la primera todavía estaba
  /// llenando — se ve como un parpadeo o como filas que aparecen y se van.
  bool _armando = false;

  Future<void> _armar() async {
    if (_armando) return;
    _armando = true;
    try {
      await _armarDeVerdad();
    } finally {
      _armando = false;
    }
  }

  Future<void> _armarDeVerdad() async {
    await _leerCache();
    // Los filtros de la vez pasada, para que los chips estén puestos desde el
    // primer cuadro en vez de aparecer a los pocos segundos.
    await _leerFiltrosGuardados();
    // ── NADA de red antes de dibujar ───────────────────────────────────
    //
    // Acá se esperaba a `detectarMixtas` y `prepararVistaPrevia`. La segunda
    // pide el catálogo por red, y SIN CONEXIÓN esa espera no termina hasta que
    // vence el tiempo: el Home se quedaba en negro, sin filas y sin siquiera el
    // mensaje de vacío, con la app entera aparentemente colgada.
    //
    // Las dos son mejoras, no requisitos: una decide si una extensión mixta
    // entra al Home, la otra agrega extensiones de vidriera. Ninguna hace falta
    // para mostrar lo que el usuario YA tiene instalado y cacheado.
    //
    // Así que van por detrás, y cuando terminan la lista se rehace. Con red se
    // nota apenas; sin red, la app abre igual.
    unawaited(_completarPorDetras());
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
    // ── Las mixtas SÍ entran ────────────────────────────────────────────
    //
    // Antes se descartaba toda extensión marcada `nsfw`, y eso dejaba fuera a
    // ManhwaWeb — que es mixta: tiene manhwa y manga normales, y lo +18 detrás
    // de un filtro propio. Esconderla entera era perder su parte normal.
    //
    // Lo que garantiza que no se cuele nada es otra cosa: a las mixtas SIEMPRE
    // se les manda el valor seguro de su filtro de adultos (ver
    // `_segurosPorExtension`). La zona normal ve su contenido normal; la Zona
    // +18 ve el otro, con el filtro invertido.
    //
    // Una extensión +18 de punta a punta —HentaiLA, Eporner— sigue afuera: no
    // tiene nada normal que mostrar.
    final instaladas = Map.fromEntries(
      ExtensionUtils.runtimes.entries.where((e) =>
          !e.value.extension.nsfw ||
          ExtensionUtils.esMixta(e.value.extension.package)),
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
        // Las que se van a mostrar como vista previa salen de acá: si no,
        // aparecerían dos veces —una apagada y otra con contenido— y con la
        // misma clave, que además rompe el ListView.
        .where((e) => !ExtensionUtils.esVistaPrevia(e.key))
        .map((e) => _reusarOCrear(FilaDeExtension(
              package: e.key,
              nombre: e.value.extension.name,
              estadoExt: ExtensionUtils.isEnabled(e.key)
                  ? EstadoExtension.activa
                  : EstadoExtension.desactivada,
            )))
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

    // ── Y unas pocas del catálogo, ya cargadas ──────────────────────────
    //
    // Van DESPUÉS de las instaladas: lo que el usuario eligió manda, y esto es
    // relleno para que el Home no quede en una sola fila. Ver
    // ExtensionUtils.prepararVistaPrevia.
    for (final e in ExtensionUtils.vistaPrevia.entries) {
      if (e.value.extension.nsfw) continue;
      nuevas.add(_reusarOCrear(FilaDeExtension(
        package: e.key,
        nombre: e.value.extension.name,
        esVistaPrevia: true,
      )));
    }

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
        // Ya está arriba con su contenido: repetirla acá como «Instalar»
        // sería listarla dos veces.
        if (ExtensionUtils.esVistaPrevia(pkg)) continue;
        // El catálogo solo trae `nsfw` cuando es true, y como texto.
        final esNsfw = e['nsfw'] == true || e['nsfw']?.toString() == 'true';
        if (esNsfw) continue;
        porInstalar.add(FilaDeExtension(
          package: pkg,
          nombre: nombre,
          estadoExt: EstadoExtension.noInstalada,
        ));
      }
      porInstalar.sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      nuevas.addAll(porInstalar);
    } catch (e) {
      logger.info('[home] no se pudo leer el catálogo: $e');
    }

    if (nuevas.isEmpty) {
      filas.clear();
      // ── Puede ser que los motores todavía no estén ────────────────────
      //
      // Este armado sale al abrir el Home, y en ese momento las extensiones
      // pueden estar todavía cargando: `runtimes` está vacío y esto termina sin
      // una sola fila.
      //
      // Antes lo único que volvía a intentar era la carga de segundo plano, que
      // depende de la RED —pide el catálogo—: con internet lento eran varios
      // segundos de Home vacío y contenido apareciendo de golpe. Y `armado`
      // sigue en falso, así que la pantalla se queda en bloques grises hasta
      // entonces, sin nada que la despierte antes.
      //
      // Con este reintento, en cuanto los motores están la lista se arma, sin
      // esperar a la red. Tres intentos cortos y se deja: si a los dos segundos
      // no hay ninguna extensión, es que de verdad no hay, y ahí el que manda
      // es el aviso de vacío.
      if (_reintentosDeArmado < 3) {
        _reintentosDeArmado++;
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (filas.isEmpty) unawaited(_armar());
        });
        return;
      }
      // Se agotaron los intentos: ahora sí, no hay extensiones y se dice.
      armado.value = true;
      return;
    }
    _reintentosDeArmado = 0;

    // Lo guardado se muestra YA, sin esperar la red.
    for (final fila in nuevas) {
      // ── La reusada no se toca, pero SÍ vuelve al acordeón ─────────────
      //
      // Si viene reusada y ya tiene lo suyo, su contenido no se pisa: lo que
      // hay en memoria es más nuevo que el archivo y puede tener varias
      // páginas pedidas. Pisarlo le sacaría al usuario las portadas que ya
      // había traído deslizando.
      //
      // Pero hay que volver a sumarla igual. `recargar()` vacía el acordeón
      // antes de armar, así que saltear la fila entera la dejaba afuera: las
      // filas de abajo mostraban su contenido y el acordeón se quedaba en
      // bloques grises para siempre. Se arreglaba tocando refrescar, porque
      // eso vuelve a pedir y al llegar el contenido la suma de nuevo — que es
      // exactamente el síntoma que se reportó.
      if (fila.items.isNotEmpty) {
        _sumarADestacados(fila, fila.items);
        continue;
      }
      final guardado = _cache[fila.package];
      if (guardado is! Map) continue;
      final items = _desdeJson(guardado['items']);
      if (items.isEmpty) continue;
      fila.items.assignAll(items);
      fila.traidoEl = DateTime.tryParse(guardado['fecha']?.toString() ?? '');
      fila.estado.value = EstadoDeFila.lista;
      _sumarADestacados(fila, items);
    }
    filas.assignAll(nuevas);
    _firmaArmada = _firmaDeExtensiones();
    armado.value = true;
  }

  /// Hasta qué página se le pide a cada extensión.
  ///
  /// Alto a propósito: JKAnime o TioAnime tienen cientos de títulos en emisión,
  /// y la idea es que el que quiera seguir deslizando pueda. Veinticinco
  /// páginas son unas doscientas portadas por extensión — con once, más de dos
  /// mil.
  ///
  /// Pero tope al fin, y no infinito. Cada página es un pedido más al sitio, y
  /// una lista que crece sin límite termina costando aunque cada ítem sea
  /// barato. Si alguien llega hasta acá, ya vio más de lo que cualquier
  /// pantalla de inicio pretende mostrar.
  ///
  /// En disco NO se guarda todo: el caché se recorta a 24 por extensión (ver
  /// ). Lo de más vive solo mientras la app está abierta, que es
  /// donde tiene sentido.
  static const _maxPaginas = 25;

  /// Si se está trayendo una página más ahora mismo.
  final trayendoMas = false.obs;

  /// Pide una página más a cada extensión que ya mostró la anterior.
  ///
  /// ── Cómo evita el atracón ───────────────────────────────────────────────
  ///
  /// Va por la MISMA cola que el resto: tope de tres pedidos a la vez, y una
  /// extensión colgada no bloquea a las demás. Y no se dispara de nuevo
  /// mientras la anterior está en curso —`trayendoMas`— así que deslizar
  /// rápido hasta el final no encadena cinco tandas de once pedidos.
  ///
  /// Las portadas nuevas se AGREGAN al final de la tanda de cada extensión, así
  /// que el orden que ya estaba en pantalla no se mueve: el usuario sigue
  /// deslizando y aparecen más adelante.
  /// Si queda contenido por traer.
  ///
  /// Es la misma condición que usa `traerMas` para elegir a quién pedirle, pero
  /// sin pedir nada: el acordeón la necesita para saber si dibuja tarjetas en
  /// espera al final o si de verdad ya no hay más.
  ///
  /// Sirve para no mentir: dibujar tarjetas «cargando» al final cuando ya no
  /// va a llegar nada más deja al usuario esperando algo que no existe.
  ///
  /// Con `any` y no con `_candidatasAMas.isNotEmpty`: esto se lee desde el
  /// dibujo del acordeón, o sea sesenta veces por segundo mientras el dedo
  /// arrastra. Armar la lista entera para preguntar si tiene algo sería tirar
  /// once objetos por cuadro para nada.
  bool get puedeTraerMas => filas.any((f) =>
      (f.estadoExt == EstadoExtension.activa || f.esVistaPrevia) &&
      f.pagina < _maxPaginas &&
      f.items.isNotEmpty &&
      (!hayFiltros || puedeConEsteGenero(f.package)));

  /// Pide la página siguiente.
  ///
  /// ── [soloPaquete]: primero se termina la extensión que se está mirando ──
  ///
  /// Sin esto se le pedía a TODAS a la vez, y el resultado era el que se
  /// reportó: el acordeón mostraba las ocho de una extensión y saltaba a la
  /// siguiente sin haber terminado la primera. Como el pedido salía recién al
  /// acercarse al final de la lista ENTERA, mientras uno recorría las ocho de
  /// la primera no se pedía nada — así que ocho y a otra cosa.
  ///
  /// Pasando el paquete del foco, esa extensión sigue trayendo sus páginas
  /// mientras uno la recorre, y recién cuando se le acaban (o llega al tope de
  /// páginas) el acordeón continúa con la siguiente.
  ///
  /// Si la del foco ya no puede dar más, se les pide a las demás igual: el
  /// acordeón nunca se puede quedar sin nada por delante.
  Future<void> traerMas({String? soloPaquete}) async {
    if (trayendoMas.value) return;
    var candidatas = filas
        .where((f) => f.estadoExt == EstadoExtension.activa || f.esVistaPrevia)
        .where((f) => f.pagina < _maxPaginas)
        .where((f) => f.items.isNotEmpty)
        .where((f) => !hayFiltros || puedeConEsteGenero(f.package))
        .toList();
    if (soloPaquete != null) {
      final delFoco =
          candidatas.where((f) => f.package == soloPaquete).toList();
      if (delFoco.isNotEmpty) candidatas = delFoco;
    }
    if (candidatas.isEmpty) return;

    trayendoMas.value = true;
    try {
      for (final fila in candidatas) {
        if (_cola.contains(fila)) continue;
        fila.pagina++;
        fila.refrescando.value = true;
        _cola.add(fila);
      }
      _mover();
      // ── Se suelta apenas hay algo nuevo que mostrar ────────────────────
      //
      // Antes se esperaba a que la cola entera se vaciara, hasta treinta
      // segundos. Con internet lento eso es una eternidad: el usuario llegaba
      // al final, deslizaba, y cada gesto chocaba contra `trayendoMas` y se
      // iba sin pedir nada. Tenía que volver atrás y bajar despacio para que
      // alguna llegara sola. Medido y reportado en tablet.
      //
      // Lo que importa no es que contesten las once: es que haya algo más
      // adelante. En cuanto la lista crece se suelta el cerrojo, así el
      // siguiente gesto ya puede pedir la página que sigue mientras las
      // lentas terminan por su cuenta —siguen en la cola, nadie las cancela—.
      //
      // El tope de treinta segundos sigue estando por si NINGUNA contesta:
      // sin él, una extensión colgada dejaría el cerrojo puesto para siempre y
      // no se podría pedir nunca más.
      final antes = _cuantasPortadas();
      for (var i = 0; i < 120 && (_enVuelo > 0 || _cola.isNotEmpty); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_cuantasPortadas() > antes) break;
      }
    } finally {
      trayendoMas.value = false;
    }
  }

  /// Cuántas portadas hay en total ahora mismo, sumando todas las filas.
  int _cuantasPortadas() {
    var n = 0;
    for (final f in filas) {
      n += f.items.length;
    }
    return n;
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
    fila.refrescando.value = true;
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
    try {
      await _traerDeVerdad(fila);
    } finally {
      // Siempre, incluso si falló: un cartel de «Buscando…» que no se apaga es
      // peor que no haberlo puesto.
      fila.refrescando.value = false;
    }
  }

  Future<void> _traerDeVerdad(FilaDeExtension fila) async {
    // Solo se muestra "cargando" si no hay nada viejo que mostrar. Con datos
    // en pantalla, refrescar por detrás no tiene que parpadear.
    if (fila.items.isEmpty) fila.estado.value = EstadoDeFila.cargando;
    try {
      // En vista previa el motor puede venir de dos lados: uno bajado a
      // propósito, o uno YA instalado que el usuario tiene apagado.
      final runtime = fila.esVistaPrevia
          ? ExtensionUtils.vistaPrevia[fila.package]
          : ExtensionUtils.enabledRuntimes[fila.package];
      if (runtime == null) {
        fila.estado.value = EstadoDeFila.fallo;
        return;
      }
      // ── Con género aplicado se pide por búsqueda, no por «lo último» ──
      //
      // `latest()` no acepta filtros: devuelve lo último y punto. El que sí
      // los acepta es `search()`, con la palabra vacía — que es como el propio
      // buscador de la app lista un género completo.
      //
      // Sin filtros, esto es EXACTAMENTE lo de antes. La rama nueva solo se
      // pisa cuando el usuario eligió algo.
      final genero = _generoPara(fila.package);
      // Sin filtro, algunas filas piden lo más visto en vez de lo último.
      // Solo las que saben: ver _popularPorExtension.
      final popular = (genero == null && fila.modo == ModoDeFila.popular)
          ? _popularPorExtension[fila.package]
          : null;
      final filtro = genero ??
          (popular == null
              ? null
              : {
                  popular.clave: [popular.valor]
                });
      // La página que toca. Empieza en 1 y sube cuando el usuario pide más.
      final pagina = fila.pagina;
      final items = await (filtro == null
              ? runtime.latest(pagina)
              : runtime.search('', pagina, filter: filtro))
          .timeout(const Duration(seconds: 20));
      if (items.isEmpty) {
        fila.estado.value =
            fila.items.isEmpty ? EstadoDeFila.fallo : EstadoDeFila.lista;
        return;
      }
      if (pagina <= 1) {
        fila.items.assignAll(items);
      } else {
        // Página siguiente: se AGREGA, sin repetir lo que ya estaba. Algunos
        // sitios devuelven ítems solapados entre páginas, y una portada
        // duplicada en el carrusel se lee como un error.
        final vistas = fila.items.map((e) => e.url).toSet();
        fila.items.addAll(items.where((e) => !vistas.contains(e.url)));
      }
      fila.traidoEl = DateTime.now();
      fila.estado.value = EstadoDeFila.lista;
      _sumarADestacados(fila, fila.items);
      unawaited(_guardarCache(fila, fila.items));
    } catch (e) {
      logger.info('[home] ${fila.nombre} no respondió: $e');
      // ── Si falló, se devuelve la página ────────────────────────────────
      //
      // `traerMas` sube `pagina` ANTES de pedir. Si el pedido falla y no se
      // vuelve atrás, la próxima vez se pide la página siguiente a la que
      // nunca llegó: el contenido de la que falló se saltea para siempre.
      if (fila.pagina > 1) fila.pagina--;
      // Con datos viejos en pantalla NO se marca como fallo: mostrar lo de
      // antes es mejor que borrarlo porque el refresco falló.
      fila.estado.value =
          fila.items.isEmpty ? EstadoDeFila.fallo : EstadoDeFila.lista;
    }
  }

  /// El filtro concreto que hay que mandarle a ESTA extensión, o null.
  ///
  /// Null significa «pedí lo último de siempre»: o no hay género aplicado, o
  /// esta extensión no lo conoce.
  Map<String, List<String>>? _generoPara(String package) {
    final ejes = _ejesPorExtension[package];
    if (ejes == null) return null;
    // Se arranca con lo seguro puesto: si esta extensión tiene una puerta a
    // contenido adulto, va cerrada de entrada.
    final filtro = <String, List<String>>{
      ...?_segurosPorExtension[package],
    };
    for (final id in [generoAplicado, estadoAplicado, formatoAplicado]) {
      if (id == null) continue;
      // Si la extensión entera ya es de ese formato, no hay nada que pedirle:
      // todo lo que devuelva sirve. Ver `_yaEsDeEseFormato`.
      final donde = ejes[id];
      if (donde == null) continue;
      // Dos ejes pueden caer en el mismo filtro del sitio; ahí se acumulan.
      (filtro[donde.clave] ??= <String>[]).add(donde.valor);
    }
    // ── Con lo seguro puesto SIEMPRE se usa search ────────────────────
    //
    // Aunque el usuario no haya elegido nada. `latest()` no acepta filtros, así
    // que por ese camino no hay forma de decirle «sin contenido para adultos» —
    // y en ManhwaWeb `latest()` va a otro endpoint del sitio, uno que no toma
    // ese parámetro.
    //
    // Costar un `search(''')` en vez de un `latest()` para dos extensiones es
    // barato. Que se cuele una portada +18 en el Home no lo es.
    return filtro.isEmpty ? null : filtro;
  }

  /// Alimenta el carrusel con la tanda de esta extensión.
  ///
  /// Se toman [porExtension] con portada. Sin portada no sirven: el carrusel
  /// es una imagen grande y un hueco ahí se ve peor que no mostrar nada.
  /// Si dos tandas tienen exactamente las mismas portadas, en el mismo orden.
  static bool _mismasPortadas(
      List<ExtensionListItem> a, List<ExtensionListItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].url != b[i].url) return false;
    }
    return true;
  }

  void _sumarADestacados(FilaDeExtension fila, List<ExtensionListItem> items) {
    // ── El tope CRECE con las páginas ────────────────────────────────────
    //
    // Acá estaba el techo que dejaba el acordeón corto. Tomaba ocho y punto,
    // así que pedir más páginas no servía: `traerMas` traía cuarenta portadas y
    // este `take` volvía a dejar ocho.
    //
    // Ahora son ocho POR PÁGINA traída: con la primera hay ocho, con la
    // segunda dieciséis, y así. Es lo que hace que deslizando se siga
    // encontrando contenido en vez de terminarse a la segunda vuelta.
    final conPortada = items
        .where((i) => (i.cover ?? '').isNotEmpty)
        .take(porExtension * fila.pagina)
        .toList();
    if (conPortada.isEmpty) return;
    final i = destacados.indexWhere((d) => d.$1 == fila.package);
    if (i >= 0) {
      // ── No avisar si no cambió nada ──────────────────────────────────
      //
      // Acá se reemplazaba la entrada siempre, y eso notifica a la lista
      // observable: el Obx del acordeón se rearma entero —medidas, seis
      // tarjetas, re-anclaje de la posición—.
      //
      // El problema es cuándo pasa. Cada fila pide su contenido al entrar en
      // pantalla, así que AL DESPLAZARSE por el Home se disparaba una detrás de
      // otra, aunque el refresco devolviera exactamente lo mismo. Eso es el
      // parpadeo: el acordeón rearmándose mientras el usuario baja.
      //
      // Comparar las direcciones es barato al lado de reconstruirlo.
      if (_mismasPortadas(destacados[i].$2, conPortada)) return;
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

  /// Lo que necesita red o motores, después de que el Home ya se dibujó.
  ///
  /// Si algo de esto falla —sin conexión, catálogo caído, una extensión que no
  /// contesta— el Home se queda con lo que ya mostró. Ninguna de las dos cosas
  /// es imprescindible.
  bool _completado = false;

  Future<void> _completarPorDetras() async {
    // ── Una sola vez, y esto NO es opcional ────────────────────────────
    //
    // Sin este candado hay un bucle infinito: al terminar, esto llama a
    // `recargar()`, que llama a `_armar()`, que vuelve a lanzar esto. Los
    // candados de `detectarMixtas` y `prepararVistaPrevia` no alcanzan —
    // devuelven al toque, pero la llamada a `recargar()` de abajo sigue
    // ocurriendo igual.
    //
    // En pantalla se veía como el Home rearmándose sin parar: todo
    // parpadeando y moviéndose solo.
    if (_completado) return;
    _completado = true;
    try {
      await ExtensionUtils.detectarMixtas();
      await ExtensionUtils.prepararVistaPrevia();
    } catch (e) {
      logger.info('[home] no se pudo completar en segundo plano: $e');
      return;
    }
    // Solo si apareció algo nuevo que mostrar.
    if (ExtensionUtils.vistaPrevia.isEmpty && ExtensionUtils.mixtas.isEmpty) {
      return;
    }
    await recargar();
  }

  /// Si el conjunto de extensiones que alimentan el Home ya no es el mismo.
  ///
  /// Compara los paquetes, no la cantidad: instalar una y desactivar otra deja
  /// el mismo número y sí es un cambio.
  bool _cambiaronLasExtensiones() => _firmaDeExtensiones() != _firmaArmada;

  /// Qué extensiones hay y en qué estado, en una cadena comparable.
  ///
  /// ── Por qué una firma y no comparar con `filas` ──────────────────────────
  ///
  /// El intento anterior comparaba los paquetes que hay instalados contra los
  /// de las filas dibujadas. No servía: el Home también dibuja filas para las
  /// APAGADAS y para unas cuantas del catálogo que el usuario no instaló, y
  /// esas nunca están en `runtimes`. Los dos conjuntos casi siempre diferían,
  /// así que refrescar rehacía la lista entera SIEMPRE — justo el trabajo de
  /// más que se quería evitar, y encima con el parpadeo que trae.
  ///
  /// Y al revés, se le escapaba lo importante: prender o apagar una extensión
  /// no cambia qué paquetes hay, solo su estado. Activar una y refrescar no la
  /// traía.
  ///
  /// La firma lleva el paquete Y si está encendida, más las de vidriera. Con
  /// eso los cuatro casos quedan cubiertos: instalar, desinstalar, prender y
  /// apagar.
  String _firmaDeExtensiones() {
    final partes = <String>[
      for (final e in ExtensionUtils.runtimes.entries)
        '${e.key}:${ExtensionUtils.isEnabled(e.key) ? 1 : 0}',
      for (final p in ExtensionUtils.vistaPrevia.keys) 'v:$p',
    ]..sort();
    return partes.join(',');
  }

  /// La firma con la que se armó la lista que está en pantalla.
  String _firmaArmada = '';

  /// Vuelve a armar la lista entera.
  ///
  /// Hace falta cuando cambia el ESTADO de una extensión —se prendió, se
  /// instaló— y no solo su contenido: ahí una fila tiene que pasar de
  /// «apagada» a activa, y eso no se arregla refrescando lo que ya está.
  Future<void> recargar() async {
    // ── El acordeón NO se vacía primero ───────────────────────────────────
    //
    // Antes esto arrancaba con `destacados.clear()`, y eso es un parpadeo
    // garantizado: el acordeón pasa a bloques grises y vuelve a llenarse. Y al
    // abrir la app pasa más de una vez —el armado se reintenta si los motores
    // todavía no están, y la carga de segundo plano vuelve a armar cuando
    // termina— así que se veían dos o tres destellos seguidos. En una tablet,
    // donde el acordeón ocupa media pantalla, se nota muchísimo más.
    //
    // Se arma primero y recién después se sacan las que ya no tienen fila. Así
    // lo que estaba en pantalla sigue ahí todo el tiempo y solo desaparece lo
    // que de verdad se fue.
    await _armar();
    final vigentes = filas.map((f) => f.package).toSet();
    destacados.removeWhere((g) => !vigentes.contains(g.$1));
  }

  /// Se está poniendo el Home al día ahora mismo.
  ///
  /// Lo mira el botón de escritorio para girar mientras dura y no dejarse tocar
  /// dos veces.
  final refrescando = false.obs;

  Future<void> refrescarTodo() async {
    // Dos refrescos encima no traen nada nuevo: el segundo encuentra la cola
    // llena y solo alarga la espera. Tocar el botón dos veces, o tirar de la
    // pantalla mientras ya estaba trabajando, no puede empeorar las cosas.
    if (refrescando.value) return;
    refrescando.value = true;
    try {
      await _refrescarDeVerdad();
    } finally {
      refrescando.value = false;
    }
  }

  Future<void> _refrescarDeVerdad() async {
    // Tirar de la pantalla también reintenta los filtros: si la primera vez no
    // se pudieron leer, este es el gesto con el que el usuario pide de nuevo.
    unawaited(cargarGeneros());

    // ── Y si cambió QUÉ extensiones hay, se rehace la lista ──────────────
    //
    // Antes esto solo volvía a pedir contenido a las filas que YA existían. Si
    // el usuario instalaba una extensión nueva y volvía al Home, no aparecía
    // por más que tirara de la pantalla: la fila no existía y nada la creaba.
    // Había que cerrar la app.
    //
    // Refrescar es el gesto de «poneme al día», así que también tiene que
    // enterarse de las que se instalaron, se prendieron o se apagaron.
    if (_cambiaronLasExtensiones()) {
      await recargar();
      // Las filas nuevas piden lo suyo al dibujarse; se las espera igual que a
      // las de siempre, o la rueda se iría con todo todavía en gris.
      await _esperarALaCola();
      return;
    }
    for (final fila in filas) {
      pedirSiHaceFalta(fila, forzar: true);
    }
    await _esperarALaCola();
  }

  /// Espera a que las filas terminen de traer lo suyo.
  ///
  /// ── Por qué hay que esperar ─────────────────────────────────────────────
  ///
  /// `pedirSiHaceFalta` solo ENCOLA y vuelve enseguida, así que sin esto
  /// `refrescarTodo` terminaba en un milisegundo. En Android eso se veía
  /// clarísimo: la rueda de «tirar para refrescar» aparecía y desaparecía de
  /// golpe, antes de que llegara una sola portada, y parecía que el gesto no
  /// había hecho nada. En escritorio era peor todavía, porque ahí no hay ni
  /// rueda: el botón no daba ninguna señal.
  ///
  /// El tope es de quince segundos. No es para cortar el trabajo —las filas
  /// siguen en la cola y terminan igual— sino para que una extensión colgada no
  /// deje la rueda girando para siempre.
  Future<void> _esperarALaCola() async {
    for (var i = 0; i < 60 && (_enVuelo > 0 || _cola.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  // ─── Caché en disco ───────────────────────────────────────────────────────
  //
  // Un solo archivo con todo, no uno por extensión: son pocos kilobytes y así
  // se lee de una sola vez al arrancar en vez de abrir diecisiete archivos.

  File get _archivo =>
      File(p.join(PrismHubDirectory.getDirectory, 'home_extensiones.json'));

  // ─── El caché de los filtros ──────────────────────────────────────────────
  //
  // ── Por qué hace falta ──────────────────────────────────────────────────
  //
  // Leer los filtros llama a `createFilter()` en el motor QuickJS de cada
  // extensión, y ese motor no es reentrante: si se hace mientras las filas
  // piden contenido, se pisan y fallan las dos (ya pasó, ver `cargarGeneros`).
  // Por eso los géneros esperan a que la cola se vacíe.
  //
  // La consecuencia era visible: se abría el Home, y varios segundos después
  // aparecían los chips de golpe. Guardándolos, en el segundo arranque ya
  // están puestos antes de dibujar nada, y el escaneo de fondo solo los
  // actualiza si algo cambió.
  //
  // Archivo aparte del de las portadas a propósito: son cosas con vidas
  // distintas —las portadas vencen a los treinta minutos, los filtros de un
  // sitio casi nunca cambian— y mezclarlas obligaría a tirar las dos juntas.
  File get _archivoFiltros =>
      File(p.join(PrismHubDirectory.getDirectory, 'home_filtros.json'));

  Future<void> _leerFiltrosGuardados() async {
    try {
      final f = _archivoFiltros;
      if (!await f.exists()) return;
      final crudo = jsonDecode(await f.readAsString());
      if (crudo is! Map<String, dynamic>) return;

      final ejes = crudo['ejes'];
      if (ejes is Map) {
        ejes.forEach((pkg, mapa) {
          if (mapa is! Map) return;
          final porId = <String, ({String clave, String valor})>{};
          mapa.forEach((id, par) {
            if (par is! List || par.length != 2) return;
            porId['$id'] = (clave: '${par[0]}', valor: '${par[1]}');
          });
          if (porId.isNotEmpty) _ejesPorExtension['$pkg'] = porId;
        });
      }
      final pop = crudo['popular'];
      if (pop is Map) {
        pop.forEach((pkg, par) {
          if (par is! List || par.length != 2) return;
          _popularPorExtension['$pkg'] =
              (clave: '${par[0]}', valor: '${par[1]}');
        });
      }
      List<String> lista(String k) =>
          (crudo[k] as List?)?.map((e) => '$e').toList() ?? const [];
      generosDisponibles.assignAll(lista('generos'));
      estadosDisponibles.assignAll(lista('estados'));
      formatosDisponibles.assignAll(lista('formatos'));
    } catch (e) {
      // Un caché ilegible no puede impedir que el Home abra: se descarta y se
      // vuelve a escanear como la primera vez.
      logger.info('[home] filtros guardados ilegibles, se ignoran: $e');
    }
  }

  Future<void> _guardarFiltros() async {
    try {
      await _archivoFiltros.writeAsString(jsonEncode({
        'ejes': _ejesPorExtension.map((pkg, m) =>
            MapEntry(pkg, m.map((id, d) => MapEntry(id, [d.clave, d.valor])))),
        'popular': _popularPorExtension
            .map((pkg, d) => MapEntry(pkg, [d.clave, d.valor])),
        'generos': generosDisponibles.toList(),
        'estados': estadosDisponibles.toList(),
        'formatos': formatosDisponibles.toList(),
      }));
    } catch (e) {
      logger.info('[home] no se pudieron guardar los filtros: $e');
    }
  }

  Future<void> _leerCache() async {
    try {
      final f = _archivo;
      if (!await f.exists()) return;
      final crudo = jsonDecode(await f.readAsString());
      if (crudo is Map<String, dynamic>) _cache = crudo;
      // ── El turno de arranque, en el mismo archivo ─────────────────────
      //
      // Va acá y no en los ajustes para no sumar una clave más al almacén por
      // un contador: este archivo ya se lee al abrir el Home y se escribe cuando
      // llega contenido, así que el número viaja gratis. La clave lleva guion
      // bajo para que no se confunda nunca con un paquete.
      final guardado = _cache['_arranque'];
      _arranque = (guardado is int ? guardado : 0) + 1;
      // Se sube YA, sin esperar a que se guarde contenido: si la app se cierra
      // sin traer nada, la próxima apertura tiene que arrancar en otra igual.
      unawaited(_guardarArranque());
    } catch (e) {
      // Un caché ilegible no puede impedir que el Home abra: se descarta.
      logger.info('[home] caché ilegible, se ignora: $e');
      _cache = const {};
    }
  }

  /// Deja anotado el turno de arranque para la próxima apertura.
  Future<void> _guardarArranque() async {
    try {
      final copia = Map<String, dynamic>.from(_cache);
      copia['_arranque'] = _arranque;
      _cache = copia;
      await _archivo.writeAsString(jsonEncode(copia));
    } catch (e) {
      // Si no se puede escribir, la próxima arranca donde esta: molesta pero no
      // rompe nada.
      logger.info('[home] no se pudo anotar el arranque: $e');
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
