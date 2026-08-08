import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/data/services/extension_service.dart';
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
    this.esVistaPrevia = false,
  });

  final String package;
  final String nombre;
  final EstadoExtension estadoExt;

  /// El usuario NO la tiene instalada: se cargó solo para que el Home tenga
  /// contenido. Al tocar una de sus tarjetas se le ofrece instalarla.
  final bool esVistaPrevia;

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
    'ciencia-ficcion': ['ciencia ficcion', 'ciencia-ficcion', 'sci-fi', 'scifi', 'science fiction'],
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

  /// Un chip solo aparece si al menos ESTAS extensiones pueden contestarlo.
  ///
  /// Con una sola, tocarlo dejaba el Home con una fila y quince líneas de «no
  /// tiene ese género» — se leía como que el filtro rompió algo.
  static const _minimoParaOfrecer = 2;

  /// Los géneros que se ofrecen, en el orden de [_canonicos].
  final generosDisponibles = <String>[].obs;

  /// Los estados que se ofrecen, en el orden de [_estados].
  final estadosDisponibles = <String>[].obs;

  final estadoElegido = RxnString();
  String? estadoAplicado;

  /// Lo que el usuario tocó pero todavía no aplicó.
  final tipoElegido = Rxn<ExtensionType>();
  final generoElegido = RxnString();

  /// Lo que está aplicado de verdad, o sea con lo que se pidió el contenido.
  ExtensionType? tipoAplicado;
  String? generoAplicado;

  bool get hayCambiosSinAplicar =>
      tipoElegido.value != tipoAplicado ||
      generoElegido.value != generoAplicado ||
      estadoElegido.value != estadoAplicado;

  bool get hayFiltros =>
      tipoAplicado != null || generoAplicado != null || estadoAplicado != null;

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
    if (_generosLeidos) return;
    _generosLeidos = true;

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
    for (var i = 0; i < 60 && (_enVuelo > 0 || _cola.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    final cuantas = <String, int>{};
    for (final e in _motoresDelHome.entries) {
      final runtime = e.value;
      // Las +18 no entran al Home, así que sus filtros tampoco.
      if (runtime.extension.nsfw) continue;
      try {
        final filtros =
            await runtime.createFilter().timeout(const Duration(seconds: 8));

        final deEsta = <String, ({String clave, String valor})>{};
        for (final f in filtros.entries) {
          final titulo = _normalizar(f.value.title);
          // «Género (+18)», «Adultos» y compañía: ni se miran.
          if (titulo.contains('18') || titulo.contains('adult')) continue;

          f.value.options.forEach((clave, etiqueta) {
            if (clave.isEmpty) return;
            final id = _canonicoDe(etiqueta) ?? _estadoDe(etiqueta);
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
          _ejesPorExtension[e.key] = deEsta;
          for (final id in deEsta.keys) {
            cuantas[id] = (cuantas[id] ?? 0) + 1;
          }
        }
      } catch (err) {
        logger.info('[home] ${runtime.extension.name} no dio sus filtros: $err');
      }
    }

    bool ofrecible(String id) => (cuantas[id] ?? 0) >= _minimoParaOfrecer;

    // En el orden de las listas curadas, no alfabético: así los más usados
    // —Acción, Aventura, Comedia— quedan primero y no hay que desplazarse.
    generosDisponibles
        .assignAll(_canonicos.keys.where(ofrecible));
    estadosDisponibles.assignAll(_estados.keys.where(ofrecible));
  }

  /// A qué estado canónico corresponde una etiqueta del sitio, si a alguno.
  static String? _estadoDe(String etiqueta) {
    final n = _normalizar(etiqueta);
    if (n.isEmpty) return null;
    for (final e in _estados.entries) {
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
    return true;
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
  Future<void> aplicarFiltros() async {
    tipoAplicado = tipoElegido.value;
    generoAplicado = generoElegido.value;
    estadoAplicado = estadoElegido.value;
    aplicandoFiltros.value = true;
    for (final fila in filas) {
      fila.traidoEl = null;
    }
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
    }
  }

  /// Vuelve a como estaba: sin filtros.
  Future<void> restablecerFiltros() async {
    tipoElegido.value = null;
    generoElegido.value = null;
    estadoElegido.value = null;
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

  Future<void> _armar() async {
    await _leerCache();
    // Antes de mirar qué hay: unas pocas del catálogo, para que el Home tenga
    // con qué llenarse aunque el usuario no haya instalado casi nada. Si falla
    // —sin red, catálogo caído— no pasa nada: sigue con lo que tenga.
    await ExtensionUtils.prepararVistaPrevia();
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
        // Las que se van a mostrar como vista previa salen de acá: si no,
        // aparecerían dos veces —una apagada y otra con contenido— y con la
        // misma clave, que además rompe el ListView.
        .where((e) => !ExtensionUtils.esVistaPrevia(e.key))
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

    // ── Y unas pocas del catálogo, ya cargadas ──────────────────────────
    //
    // Van DESPUÉS de las instaladas: lo que el usuario eligió manda, y esto es
    // relleno para que el Home no quede en una sola fila. Ver
    // ExtensionUtils.prepararVistaPrevia.
    for (final e in ExtensionUtils.vistaPrevia.entries) {
      if (e.value.extension.nsfw) continue;
      nuevas.add(FilaDeExtension(
        package: e.key,
        nombre: e.value.extension.name,
        esVistaPrevia: true,
      ));
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
      final items = await (genero == null
              ? runtime.latest(1)
              : runtime.search('', 1, filter: genero))
          .timeout(const Duration(seconds: 20));
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

  /// El filtro concreto que hay que mandarle a ESTA extensión, o null.
  ///
  /// Null significa «pedí lo último de siempre»: o no hay género aplicado, o
  /// esta extensión no lo conoce.
  Map<String, List<String>>? _generoPara(String package) {
    final ejes = _ejesPorExtension[package];
    if (ejes == null) return null;
    final filtro = <String, List<String>>{};
    for (final id in [generoAplicado, estadoAplicado]) {
      if (id == null) continue;
      final donde = ejes[id];
      if (donde == null) continue;
      // Dos ejes pueden caer en el mismo filtro del sitio; ahí se acumulan.
      (filtro[donde.clave] ??= <String>[]).add(donde.valor);
    }
    return filtro.isEmpty ? null : filtro;
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
