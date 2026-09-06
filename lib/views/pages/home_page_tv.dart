part of 'home_page.dart';

// ─── El Home de Android TV ───────────────────────────────────────────────
//
// Aparece solo cuando `_esTelevision` (ver el bifurcado en `home_page.dart`)
// da true. Reusa lo mismo que ya prueba escritorio: el mismo `_CarruselAndroid`
// para el destacado de arriba y `_FilaWindows` para cada fila —con
// `conFocoTv: true` para que las tarjetas sean navegables con D-pad—. Nada
// de eso se reescribe.
//
// Lo nuevo es el sidebar de categorías a la izquierda y la barra de arriba a
// la derecha, que es lo que la referencia (estilo Magis TV) agrega sobre el
// diseño de escritorio.
//
// ── Por qué Mangas no tiene entrada acá ────────────────────────────────
//
// Regla explícita del plan de rediseño: en TV solo streaming, nunca
// lectura, en ninguna zona. `ZonaPrincipal.mangas` directamente no tiene
// categoría en este sidebar — ni siquiera "en construcción" — así que no
// hay forma de llegar a ella desde TV, ni aunque una extensión la
// declare.
//
// ── Por qué Películas/Series/Anime YA muestran catálogo real ────────────
//
// Usan el mismo `ZonaCatalogoController` que ya prueban las 4 pestañas de
// Android/Windows/Linux (Fase 6d del plan de rediseño), registrado con el
// mismo `tag: zona.name` — visitar la misma zona desde el teléfono y
// después desde TV encuentra lo que ya se había cargado, no hay dos
// copias. Lo único propio de TV es CÓMO se dibuja: filas horizontales
// (`_FilaZonaTv`) en vez de una grilla — ver el comentario largo en
// `_ZonaTv` sobre por qué, con la navegación D-pad de una grilla 2D sin
// probar todavía, no conviene arriesgarla acá.
enum _CategoriaTV {
  /// El catálogo de todas las extensiones — lo que se ve al abrir, y por eso
  /// va primero: es donde arranca el foco y de donde parte todo.
  inicio(Icons.home_rounded, null),

  /// Canales en vivo. Todavía no existe.
  tv(Icons.live_tv_rounded, null, enConstruccion: true),

  /// Continuar viendo/leyendo y favoritos: la LibraryPage de siempre.
  biblioteca(Icons.video_library_rounded, null, esBiblioteca: true),

  peliculas(Icons.movie_outlined, null, zona: ZonaPrincipal.peliculas),
  series(Icons.tv_rounded, null, zona: ZonaPrincipal.series),
  anime(Icons.animation_rounded, null, zona: ZonaPrincipal.anime);

  const _CategoriaTV(
    this.icono,
    this.tipo, {
    this.enConstruccion = false,
    this.esBiblioteca = false,
    this.zona,
  });
  final IconData icono;
  final ExtensionType? tipo;
  final bool enConstruccion;
  final bool esBiblioteca;

  /// Si no es null, esta categoría muestra el catálogo de esa zona vía
  /// `ZonaCatalogoController` — ver `_ZonaTv`.
  final ZonaPrincipal? zona;

  String etiqueta() => switch (this) {
        _CategoriaTV.inicio => 'common.home'.i18n,
        _CategoriaTV.tv => 'home.tv-canales'.i18n,
        _CategoriaTV.biblioteca => 'common.library'.i18n,
        _CategoriaTV.peliculas => 'home.zona-peliculas'.i18n,
        _CategoriaTV.series => 'home.zona-series'.i18n,
        _CategoriaTV.anime => 'home.zona-anime'.i18n,
      };
}

/// El ancho del sidebar, por tamaño de pantalla. Una TV real cae casi
/// siempre en `enorme` (≥1600px lógicos), pero se sigue el mismo criterio de
/// `Ancho` que el resto de la app en vez de un número fijo pensado para una
/// sola resolución — así una TV 1080p, una 4K o el emulador en una ventana
/// chica se acomodan solas.
double _anchoSidebarTv(Ancho a) =>
    a.elegir(compacto: 120, medio: 170, amplio: 190, enorme: 200);

/// El ancho del sidebar CONTRAÍDO — solo los íconos.
///
/// Vive acá y no adentro de `_SidebarTVState` porque el panel de contenido
/// también lo necesita: reserva ese mismo ancho como margen fijo para que
/// las tarjetas nunca queden debajo del sidebar. Un solo número para las
/// dos partes, para que no puedan desincronizarse.
double _anchoSidebarContraidoTv(Ancho a) =>
    a.elegir<double>(compacto: 48, medio: 54, amplio: 58, enorme: 58);

/// El aire entre el rail de íconos y donde arranca el contenido.
///
/// Del boceto aprobado (`bocetos/compacto.html`): el contenido no deja un
/// margen grande, arranca casi pegado al rail y llega hasta el borde
/// derecho — es lo que hace que entren siete pósters por fila y que se
/// vean dos filas y media.
///
/// ── Por qué subió de 12 a 22 ────────────────────────────────────────────
///
/// El marco de foco de una tarjeta NO se dibuja adentro: sale unos píxeles
/// hacia afuera, y encima lleva un resplandor bastante más ancho que eso.
/// Con 12, la PRIMERA tarjeta de cada fila tenía su marco pegado al rail y
/// se veía mordido. Reportado en vivo con foto: «la primera card de la
/// extensión se corta a la izquierda, no hay espacio ahí».
const double _aireDelRailTv = 22;

/// Lo que se deja libre contra el borde derecho.
///
/// ── Por qué ya no es cero ───────────────────────────────────────────────
///
/// Era cero a propósito, para que la fila llegara hasta el filo y la
/// tarjeta siguiente asomara cortada —eso es lo que dice «hay más para el
/// lado»—. Pero con cero, la ÚLTIMA tarjeta a la que se puede llegar queda
/// con su marco de foco contra el borde de verdad de la pantalla, y ahí no
/// hay nada que lo dibuje: se ve cortado. Reportado en vivo: «cuando estoy
/// en la última card a la derecha, la selección se topa y no se ve».
///
/// Con este aire la fila sigue asomando la siguiente —el recorte pasa a
/// estar unos píxeles antes, que no se nota— y el marco entra entero.
const double _aireDerechoTv = 22;

/// El hueco entre las tarjetas grandes de Inicio. Casi pegadas.
const double _huecoGrandeTv = 6;

/// El hueco entre pósters de una fila.
const double _huecoPosterTv = 10;

/// El tope de filas de una zona: una por extensión, hasta acá.
///
/// Acordado con el usuario: «hacia abajo, veintiséis, el límite». No es un
/// límite técnico sino de lectura — una zona con cuarenta filas no se
/// recorre con un mando, y cada fila de más es una extensión más a la que
/// pedirle contenido.
///
/// Inicio queda afuera a propósito: ahí las filas son las extensiones que
/// el usuario tiene, y esconderle algunas sería decidir por él.
const int _maxFilasPorZonaTv = 26;

/// El tope de tarjetas de una fila.
///
/// Acordado con el usuario: «en cada fila, quince hacia la derecha, el
/// tope». Alcanza de sobra para recorrer con el mando sin que la fila se
/// vuelva infinita, y le pone un techo claro a cuántas portadas puede
/// llegar a tener vivas una sola fila.
const int _maxTarjetasPorFilaTv = 15;

/// Cuántos pósters entran enteros en una fila. El siguiente asoma cortado
/// contra el borde, que es justo lo que dice "hay más para el lado".
const int _postersPorFilaTv = 7;

/// El alto de la fila de tarjetas grandes de Inicio.
///
/// ── Por qué bajó del 55% al 44% ───────────────────────────────────────
///
/// Con el 55% (más el 24% de las medianas de abajo) el hero y las medianas
/// se comían casi el 80% del alto útil, y a la primera fila de extensiones
/// —la que sigue después— no le quedaba lugar: el título aparecía pegado al
/// borde de abajo y ni una tarjeta llegaba a asomar. Reportado en vivo con
/// foto: «sale solo el título de jkanime cortado y ni se ven las cards
/// abajo», con una app de referencia al lado donde SÍ se ve el título
/// siguiente entero y las tarjetas empiezan a asomar.
///
/// Con menos alto acá, a la fila siguiente le queda más para mostrarse sin
/// esperar a que el usuario baje.
double _altoGrandesTv(BuildContext context) {
  final util = MediaQuery.sizeOf(context).height - _altoBarraTv;
  return (util * 0.44).clamp(150.0, 340.0);
}

/// El alto de la fila de medianas: ídem, bajó del 24% al 16%.
double _altoMedianasTv(BuildContext context) {
  final util = MediaQuery.sizeOf(context).height - _altoBarraTv;
  return (util * 0.16).clamp(70.0, 140.0);
}

/// Lo que se lleva la barra de arriba.
const double _altoBarraTv = 46;

/// El ancho de un póster de fila, para que entren [_postersPorFilaTv].
///
/// ── Por qué el tope bajó de 260 a 200 ────────────────────────────────────
///
/// Con 260 la portada (3:2, más el título debajo) pasaba los 400 de alto:
/// cada fila —tanto las de Inicio como las de una zona— pesaba tanto que la
/// siguiente quedaba fuera de la pantalla. Reportado en vivo junto con el
/// del hero: «hace más chico las cards por si ocupan mucho espacio». Con
/// 200 entran las mismas siete por fila pero cada una pesa menos, así que
/// asoma antes lo que sigue debajo.
double _anchoPosterTv(BuildContext context) {
  final util = MediaQuery.sizeOf(context).width -
      _anchoSidebarContraidoTv(Ancho.de(context)) -
      _aireDelRailTv -
      _aireDerechoTv;
  final ancho =
      (util - _huecoPosterTv * (_postersPorFilaTv - 1)) / _postersPorFilaTv;
  return ancho.clamp(96.0, 200.0);
}

/// El margen "TV-safe" contra el borde de la pantalla (overscan).
///
/// Estaba escrito acá y en `detail_page_tv.dart` con el mismo cuerpo — ahora
/// las dos apuntan a la única definición, en `HomeTheme.overscanTv`.

/// Escucha el aviso de «me estoy quedando sin memoria» del sistema y suelta
/// las zonas que no se están viendo.
///
/// Aparte y no en el propio State para no obligar a `_HomeTVState` a ser un
/// `WidgetsBindingObserver` entero (con sus catorce métodos) por un solo
/// aviso.
class _AlivioDeZonasTv extends WidgetsBindingObserver {
  _AlivioDeZonasTv(this.soltar);

  final VoidCallback soltar;

  @override
  void didHaveMemoryPressure() => soltar();
}

class HomeTV extends StatefulWidget {
  const HomeTV({super.key, required this.c});

  final CatalogoExtensionesController c;

  @override
  State<HomeTV> createState() => _HomeTVState();
}

class _HomeTVState extends State<HomeTV> {
  /// El foco de la primera categoría, para que el sidebar arranque con algo
  /// enfocado apenas se entra a la Home — sin esto el mando queda "sin
  /// dónde" hasta que alguien toca una flecha por las dudas.
  final _primerFoco = FocusNode(debugLabel: 'sidebar-tv-0');

  /// Qué categoría está elegida. Se guarda acá y no se deduce de
  /// `c.tipoElegido` porque dos categorías pueden compartir tipo: `tv` y
  /// `todo` no filtran nada las dos (`tipo == null`), así que mirando solo
  /// el tipo del controller quedarían las dos resaltadas a la vez.
  _CategoriaTV _categoria = _CategoriaTV.inicio;

  /// Las zonas que el usuario ABRIÓ alguna vez.
  ///
  /// ── Por qué no se construyen todas de entrada ───────────────────────────
  ///
  /// `IndexedStack` construye a TODOS sus hijos, muestre al que muestre. O sea
  /// que entrar al Inicio armaba también la Biblioteca entera —con sus
  /// controllers, su fondo y sus animaciones— aunque nadie la hubiera abierto.
  /// Y como la Biblioteca ya vive además como zona propia de la barra
  /// principal (ver main_page.dart), quedaba montada DOS VECES a la vez.
  ///
  /// Peor todavía: el `IndexedStack` esconde con `Offstage`, que no apaga los
  /// relojes de animación. La Biblioteca escondida acá seguía latiendo a 60
  /// cuadros por segundo sin que se viera nada.
  ///
  /// Con esto, una zona se arma recién la primera vez que se entra. Lo que el
  /// `IndexedStack` vino a dar se conserva entero: una vez armada se queda
  /// viva, así que volver la encuentra tal cual se dejó.
  /// ── Y por qué en un aparato modesto NO se quedan vivas ─────────────────
  ///
  /// Mantenerlas vivas es cómodo (volver encuentra la zona tal cual se dejó)
  /// pero cada zona viva sostiene sus portadas DECODIFICADAS: mientras el
  /// widget está montado, esas imágenes cuentan como «vivas» para
  /// `ImageCache` y **no se pueden desalojar por más que se pase del techo**
  /// (ver `alivio_de_memoria.dart`). Con Inicio + Películas + Series + Anime
  /// abiertas, son cuatro pantallas enteras de portadas que la caché no
  /// puede soltar aunque el sistema esté pidiendo memoria a gritos.
  ///
  /// Reportado en vivo, televisor de 893 MB: «al navegar se cierra el app,
  /// al ir a otra zona me saca». En un aparato así la comodidad no vale el
  /// cierre: se conserva SOLO la que se está viendo, y volver a otra la
  /// vuelve a armar. Los datos no se pierden —el `ZonaCatalogoController`
  /// sigue registrado en GetX con todo lo cargado—, así que volver es
  /// rearmar widgets con lo que ya está en memoria, sin pedir red de nuevo.
  final Set<_CategoriaTV> _visitadas = {_CategoriaTV.inicio};

  /// Si este aparato no puede permitirse tener varias zonas montadas.
  bool get _memoriaJusta => PrismHubMas.nivel == NivelDeAparato.bajo;

  @override
  void initState() {
    super.initState();
    _alivio = _AlivioDeZonasTv(_soltarLasQueNoSeVen);
    WidgetsBinding.instance.addObserver(_alivio);
  }

  late final _AlivioDeZonasTv _alivio;

  /// Deja montada solo la zona que se está viendo. Se llama al cambiar de
  /// zona (en aparatos modestos) y cuando el sistema pide memoria (en
  /// todos): ahí el ahorro vale más que la comodidad, sea cual sea el
  /// aparato.
  void _soltarLasQueNoSeVen() {
    if (!mounted) return;
    if (_visitadas.length <= 1) return;
    setState(() {
      _visitadas
        ..clear()
        ..add(_categoria);
    });
    // La pantalla que se acaba de soltar deja sus portadas en la caché: se
    // sueltan ahora, no cuando algo las eche.
    AlivioDeMemoria.soltarAlDejarLaPantalla();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_alivio);
    _primerFoco.dispose();
    super.dispose();
  }

  /// Marca la categoría elegida.
  ///
  /// Ya no toca ningún filtro compartido: cada categoría real (Inicio,
  /// Biblioteca) trae su propio contenido por su cuenta, y las de zona
  /// (Películas/Series/Anime) van a traer el suyo vía `ZonaCatalogoController`
  /// cuando se armen — ninguna de las dos depende de marcar nada acá.
  void _elegir(_CategoriaTV categoria) {
    CentinelaDeArranque.marcar('va a la zona ${categoria.name}');
    setState(() {
      _categoria = categoria;
      // A partir de acá esta zona se arma. En un aparato con memoria justa
      // se suelta la anterior; en el resto se quedan vivas, que es lo que
      // hace instantáneo volver. Ver [_visitadas].
      if (_memoriaJusta) _visitadas.clear();
      _visitadas.add(categoria);
    });
    // ── Y si la zona quedó vacía, se le pide de nuevo ──────────────────
    //
    // El chequeo equivalente al entrar por primera vez vive en
    // `_ZonaTvState.initState` (ver el comentario largo ahí sobre por qué
    // hace falta). Pero una zona ya visitada NO se vuelve a montar —
    // `_visitadas` la mantiene viva a propósito— así que ese initState no
    // corre de nuevo y volver a entrar no cambiaba nada.
    //
    // Con esto, entrar a una zona que quedó sin contenido vuelve a
    // intentar. Es también lo que hace que instalar una extensión nueva y
    // volver a la zona la encuentre, sin tener que cerrar la app.
    //
    // Solo si de verdad está vacía: con contenido cargado no se pide nada,
    // así que moverse entre zonas sigue siendo instantáneo.
    final zona = categoria.zona;
    if (zona == null) {
      // ── Inicio: el mismo problema, la misma cura ────────────────────
      //
      // El Home ya sabe detectar que cambiaron las extensiones, pero solo
      // lo mira al REFRESCAR — deslizar hacia abajo en Android, el botón
      // en escritorio. En un televisor no existe ninguno de los dos, así
      // que instalar una extensión y volver al Inicio no la mostraba
      // nunca: había que cerrar la app entera.
      //
      // ── Y el carrusel NO se resortea por esto ───────────────────────
      //
      // Aviso explícito: "nunca actualizar el carrusel, es único desde
      // que se abre la app". Verificado en el controller: por dónde
      // arranca el acordeón lo fija `_paqueteDeArranque ??=` UNA sola vez
      // por apertura (`??=`, no `=`), así que volver a armar la lista no
      // lo vuelve a sortear — el carrusel sigue entrando por la misma
      // extensión y en el mismo orden. Lo único que cambia es que una
      // extensión recién instalada pasa a tener su tanda, que es
      // justamente lo que se está pidiendo al instalarla.
      if (categoria == _CategoriaTV.inicio && widget.c.hayExtensionesNuevas) {
        unawaited(widget.c.recargar());
      }
      return;
    }
    if (!Get.isRegistered<ZonaCatalogoController>(tag: zona.name)) return;
    final c = Get.find<ZonaCatalogoController>(tag: zona.name);
    if (c.fuentes.isEmpty ||
        c.entrelazados.isEmpty ||
        // También si se instaló, activó o desactivó una extensión desde la
        // última vez — ver `ZonaCatalogoController.hayExtensionesNuevas`.
        // Sin esto, una zona que YA tenía contenido no se enteraba nunca de
        // una extensión nueva: había que cerrar la app.
        c.hayExtensionesNuevas) {
      unawaited(c.cargarInicial());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Del boceto aprobado: el contenido arranca casi pegado al rail (22px)
    // y llega hasta el borde derecho. Nada de overscan de más acá — eso
    // era lo que dejaba las tarjetas chicas y perdidas en el medio.
    final margenParaElSidebar =
        _anchoSidebarContraidoTv(Ancho.de(context)) + _aireDelRailTv;
    // ── La barra de arriba manda en TODA la pantalla ────────────────────
    //
    // Estaba dentro del panel de contenido, así que entrar a una zona sin
    // catálogo (TV en vivo) o quedarse sin extensiones se llevaba puesto el
    // logo y los accesos: la pantalla quedaba sin salida visible. Acá arriba
    // vive fuera de todo lo que cambia — pase lo que pase debajo, siempre
    // están el nombre y los botones.
    return SafeArea(
      child: Padding(
        // ── Sin margen a la DERECHA ────────────────────────────────────
        //
        // `HomeTheme.margenTv` deja overscan a los dos lados (hasta 64px en
        // un televisor de 1280). A la izquierda hace falta —ahí vive el
        // rail— pero a la derecha era justo lo que cortaba las filas antes
        // del borde: la última tarjeta terminaba y quedaba una franja negra,
        // así que no se leía que hubiera más para el lado. Reportado con
        // foto: «deben abarcar toda la derecha y ver que hay otras cards, no
        // cortándola desde ahí».
        //
        // Arriba y abajo se conserva: ahí el overscan sí protege de los
        // televisores que recortan los bordes.
        padding: HomeTheme.margenTv(context).copyWith(right: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BarraSuperiorTV(),
            Expanded(
              child: Obx(() {
                if (widget.c.filas.isEmpty) {
                  return widget.c.armado.value
                      ? const _SinExtensiones()
                      : const _HomeEsperando(conCabecera: false);
                }
                // ── Superpuesto, no empujado ───────────────────────────
                //
                // Antes esto era un `Row`: el sidebar y el contenido se
                // repartían el ancho, así que expandir el menú ACHICABA la
                // grilla — entraban menos columnas, las tarjetas se
                // reacomodaban, todo se corría. Pedido explícito: «mejor que
                // no mueva las cosas, todo sea estático».
                //
                // Con un `Stack`, el contenido usa SIEMPRE el mismo ancho
                // —el que le queda descontando `margenParaElSidebar`, fijo,
                // sin importar si el sidebar está expandido o no— y el
                // sidebar se dibuja ENCIMA, en su propia capa. Contraído
                // (solo íconos) cabe entero dentro de ese margen y no tapa
                // ninguna tarjeta; expandido, sí las tapa —las que quedan
                // debajo suyo—, que es la idea: mientras se está eligiendo
                // una categoría no hace falta ver esas tarjetas.
                return Stack(
                  children: [
                    // Las dos capas quedan marcadas como regiones distintas
                    // (ver RegionDeFocoTv): el mando puede recorrer cada una
                    // por dentro con arriba/abajo sin escaparse a la otra, y
                    // se cambia de una a otra solo yendo a los costados, que
                    // es un movimiento deliberado.
                    RegionDeFocoTv(
                      nombre: RegionDeFocoTv.contenido,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: margenParaElSidebar,
                          right: _aireDerechoTv,
                        ),
                        // ── IndexedStack y no AnimatedSwitcher ────────────
                        //
                        // El switcher DESTRUYE la zona que se deja: al volver,
                        // el scroll arrancaba de cero y el foco se perdía —
                        // justo lo contrario de lo que uno espera al ir y
                        // volver con el mando.
                        //
                        // Con IndexedStack las zonas se construyen una vez y
                        // se quedan vivas (mismo criterio que ya usa la barra
                        // de Android, ver main_page.dart): volver a una zona la
                        // encuentra tal cual se dejó.
                        //
                        // La entrada se anima igual, sin perder ese estado: la
                        // zona que se muestra aparece con un fundido y un
                        // desplazamiento corto hacia arriba, atado al índice —
                        // así cambiar de zona con el mando se siente como un
                        // movimiento y no como un parpadeo, pero volver sigue
                        // encontrando todo donde estaba.
                        //
                        // ── Y el fundido cuesta, así que se cuida ─────────
                        //
                        // Este `Opacity` envuelve el panel de contenido ENTERO
                        // —el carrusel, los filtros y todas las filas—, y bajar
                        // la intensidad de algo obliga a componerlo en una capa
                        // aparte. Es el mismo patrón que ya se sacó de la barra
                        // principal por costoso (ver main_page.dart).
                        //
                        // Acá se resuelve de dos maneras: con el
                        // `RepaintBoundary` de más abajo, el contenido se pinta
                        // UNA vez y el fundido solo compone esa capa ya lista;
                        // y en un aparato modesto el fundido no se hace, que en
                        // un televisor no se extraña —el cambio de zona pasa a
                        // ser instantáneo, que tampoco está mal.
                        child: _ZonaQueAparece(
                          // La clave atada a la categoría es lo que hace que
                          // la animación vuelva a empezar en cada cambio.
                          key: ValueKey(_categoria),
                          child: IndexedStack(
                            index: _CategoriaTV.values.indexOf(_categoria),
                            children: [
                              for (final z in _CategoriaTV.values)
                                // ── Y cada zona con su reloj apagado, y su foco cerrado ──
                                //
                                // `IndexedStack` esconde con `Offstage`, que NO
                                // toca `TickerMode`: sin esto, las zonas que no
                                // se ven siguen animando a 60 cuadros por
                                // segundo. Es el mismo cuidado que ya tiene la
                                // barra principal (ver main_page.dart), que acá
                                // faltaba.
                                //
                                // Y tampoco toca el FOCO. `IndexedStack` no
                                // pinta las zonas que no se muestran, pero las
                                // sigue midiendo en el MISMO lugar que la que sí
                                // se ve —ocupan la misma celda del Stack—. Sin
                                // `ExcludeFocus`, una tarjeta de una zona
                                // escondida es un candidato geométricamente
                                // válido para el salto del mando: está "ahí
                                // mismo", superpuesta con la que se ve.
                                //
                                // Reportado en vivo: moverse con el mando en una
                                // zona y, de golpe, "empieza a cargar contenido
                                // raro" — el foco se había ido a una tarjeta de
                                // OTRA zona, invisible pero viva, y esa zona
                                // arrancaba a pedir su catálogo al recibir el
                                // foco por primera vez.
                                ExcludeFocus(
                                  excluding: z != _categoria,
                                  child: TickerMode(
                                    enabled: z == _categoria,
                                    child: !_visitadas.contains(z)
                                        // Todavía no se entró nunca: no hay nada
                                        // que armar. Ver [_visitadas].
                                        ? const SizedBox.shrink()
                                        : switch (z) {
                                            final e when e.enConstruccion =>
                                              ZonaEnCreacion(
                                                  titulo: e.etiqueta()),
                                            _CategoriaTV.biblioteca =>
                                              const LibraryPageTv(),
                                            final e when e.zona != null =>
                                              _ZonaTv(zona: e.zona!),
                                            _ => _ContenidoTV(c: widget.c),
                                          },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Encima del contenido, no al lado — ver la nota de
                    // arriba. `Positioned` con los tres lados verticales fija
                    // el alto a la columna entera; el ancho lo decide el
                    // propio `_SidebarTV` con su `AnimatedContainer`.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: RegionDeFocoTv(
                        nombre: RegionDeFocoTv.rail,
                        child: _SidebarTV(
                          c: widget.c,
                          primerFoco: _primerFoco,
                          elegida: _categoria,
                          onElegir: _elegir,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// La zona que se acaba de elegir, entrando con un fundido corto y un
/// desplazamiento hacia arriba.
///
/// Envuelve al panel de contenido entero, así que es de lo más caro que se
/// anima en la Home de TV. Dos cosas lo hacen barato:
///
///   · El `RepaintBoundary` de adentro. Sin él, cada cuadro del fundido
///     obliga a repintar el carrusel, los filtros y todas las filas; con él,
///     eso se pinta una vez y el fundido solo compone la capa ya lista.
///   · En un aparato modesto no hay fundido: el contenido aparece puesto. En
///     un televisor no se extraña, y ahí 260 ms componiendo media pantalla en
///     cada cambio de zona es justo lo que no sobra.
class _ZonaQueAparece extends StatelessWidget {
  const _ZonaQueAparece({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final contenido = RepaintBoundary(child: child);
    // Sin fundido en NINGÚN televisor, no solo en los modestos.
    //
    // Este widget solo lo usa la Home de TV, así que esto es «nunca». El
    // motivo es el mismo que el del crecido del foco (ver FocusableCard):
    // reportado en vivo que la app va a tirones también en televisores
    // potentes, y componer media pantalla con opacidad durante 260 ms en cada
    // cambio de zona es de lo más caro que hace la interfaz. Un televisor es
    // potente decodificando vídeo; su GPU componiendo interfaz no lo es.
    //
    // El contenido aparece puesto, que en un televisor no se extraña.
    if (PlatformTv.esTelevisionSync ||
        PrismHubMas.nivel == NivelDeAparato.bajo) {
      return contenido;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, v, hijo) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: hijo,
        ),
      ),
      child: contenido,
    );
  }
}

/// El sidebar de categorías, a la izquierda.
class _SidebarTV extends StatefulWidget {
  const _SidebarTV({
    required this.c,
    required this.primerFoco,
    required this.elegida,
    required this.onElegir,
  });

  final CatalogoExtensionesController c;
  final FocusNode primerFoco;
  final _CategoriaTV elegida;
  final void Function(_CategoriaTV) onElegir;

  @override
  State<_SidebarTV> createState() => _SidebarTVState();
}

class _SidebarTVState extends State<_SidebarTV> {
  /// Un nodo por categoría, para saber en cuál está parado el mando y poder
  /// frenar en los extremos (ver `_frenarEnLosBordes`).
  late final List<FocusNode> _nodos = [
    for (final cat in _CategoriaTV.values)
      cat == _CategoriaTV.inicio
          ? widget.primerFoco
          : FocusNode(debugLabel: 'sidebar-${cat.name}'),
  ];

  /// Si el sidebar tiene que mostrarse desplegado (con el nombre de cada
  /// categoría) o solo con los íconos.
  ///
  /// ── El criterio: se despliega mientras el mando está PARADO ahí ────────
  ///
  /// Igual que el menú de Netflix o YouTube en TV: contraído mientras el
  /// foco está en el contenido —para no robarle ancho a las tarjetas—, y
  /// se abre solo mientras el usuario está eligiendo una categoría, que es
  /// el único momento en que el nombre hace falta (el ícono solo no dice si
  /// "Series" es la de video o si hay una zona de anime distinta).
  ///
  /// Arranca en `true` porque el foco inicial de la pantalla ES una
  /// categoría del sidebar (ver `autofocus` más abajo): si arrancara
  /// contraído, se abriría de golpe en el primer cuadro y se vería como un
  /// salto en vez de como el estado de reposo.
  bool _expandido = true;

  @override
  void initState() {
    super.initState();
    for (final nodo in _nodos) {
      nodo.addListener(_alCambiarElFoco);
    }
    // ── Y se comprueba contra la realidad al primer cuadro ───────────────
    //
    // `_expandido` arranca en true dando por sentado que el `autofocus` de
    // más abajo va a poner el foco en una categoría. Pero ese `autofocus`
    // puede NO llegar a aplicarse: Flutter solo lo respeta si en ese momento
    // nadie más tiene el foco dentro del ámbito, y acá compite con el aviso
    // de beta que se abre encima, con el rescate de foco y con lo que ya
    // tuviera el contenido.
    //
    // Y cuando no llega, esto quedaba roto para siempre: lo ÚNICO que
    // apagaba `_expandido` era el oyente de abajo, que solo corre cuando el
    // foco CAMBIA en uno de estos nodos. Sin foco nunca puesto no hay
    // cambio, así que el panel se quedaba desplegado toda la sesión —
    // tapando además la primera tarjeta de cada fila, porque abierto se
    // dibuja encima del contenido. Reportado en vivo con foto, varias
    // veces: «el panel izquierdo sale todo el rato mostrándose, no se
    // quita», y «la primera card de la extensión se corta a la izquierda».
    //
    // Con esto, al cuadro siguiente el panel se acomoda a lo que de verdad
    // pasó: si el foco quedó adentro sigue abierto (sin ningún salto), y si
    // no, se contrae como corresponde.
    WidgetsBinding.instance.addPostFrameCallback((_) => _alCambiarElFoco());
  }

  void _alCambiarElFoco() {
    final expandido = _nodos.any((n) => n.hasFocus);
    if (expandido != _expandido && mounted) {
      setState(() => _expandido = expandido);
    }
  }

  /// Si ya se enfocó algo alguna vez en esta pantalla.
  ///
  /// El `autofocus` tiene que correr UNA sola vez, al entrar por primera
  /// vez. Volviendo de otra pantalla (Extensiones, Ajustes, Favoritos) esta
  /// se reconstruye, y con el autofocus siempre puesto el foco se iba de
  /// vuelta a "Inicio" — o sea que ir a Ajustes y volver te dejaba en otro
  /// lado del que estabas. Con la bandera, al volver el foco se queda donde
  /// lo dejaste.
  bool _yaEnfoco = false;

  @override
  void dispose() {
    for (final nodo in _nodos) {
      nodo.removeListener(_alCambiarElFoco);
      // El primero lo creó y lo descarta HomeTV; los demás son de acá.
      if (nodo != widget.primerFoco) nodo.dispose();
    }
    super.dispose();
  }

  /// Abajo en la última categoría no hace nada. Arriba en la primera, sí.
  ///
  /// Sin frenar el ABAJO, bajar desde la última categoría mandaba el foco al
  /// panel de la derecha —lo más cercano hacia abajo— y con él se iba el
  /// scroll del contenido: se sentía como que la lista "se movía sola"
  /// mientras uno solo estaba recorriendo el menú.
  ///
  /// El ARRIBA estaba frenado igual, por simetría, y era un error: encima del
  /// menú está la barra con buscar, extensiones, favoritos, historial y
  /// ajustes. Frenarlo dejaba esos cinco botones inalcanzables desde el menú
  /// — estando en Inicio, que es la primera categoría, no había ninguna tecla
  /// que llevara arriba. Reportado en vivo: «puedo bajar, pero cuando quiero
  /// subir el foco no me deja».
  /// Arriba y abajo se mueven POR LA LISTA, no por geometría.
  ///
  /// ── Por qué no se deja que Flutter lo resuelva solo ──────────────────
  ///
  /// El recorrido de fábrica busca «lo más cercano en esa dirección» por
  /// posición en pantalla. En este rail eso falla: los íconos son chicos y
  /// están pegados al borde, mientras que a la derecha hay tarjetas enormes
  /// que ocupan casi toda la pantalla — y una tarjeta que está más arriba,
  /// aunque sea a la derecha del todo, puede quedar «más cerca» que el ícono
  /// de justo encima. Reportado en vivo: «en el panel lateral no me dejaba
  /// subir y me manda a la zona».
  ///
  /// Con la lista de nodos a mano el movimiento es exacto: arriba es la
  /// categoría anterior y abajo la siguiente, siempre, sin importar qué haya
  /// dibujado al lado.
  ///
  /// En los extremos se deja pasar la tecla para que el foco pueda salir:
  /// arriba en la primera va a la barra de arriba (buscar, extensiones,
  /// ajustes), y abajo en la última se frena, que si no el foco se escapaba
  /// al contenido por abajo. La derecha nunca se toca: es la que entra a la
  /// zona, y así tiene que seguir siendo.
  KeyEventResult _frenarEnLosBordes(FocusNode node, KeyEvent evento) {
    if (evento is! KeyDownEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    final arriba = tecla == LogicalKeyboardKey.arrowUp;
    final abajo = tecla == LogicalKeyboardKey.arrowDown;
    if (!arriba && !abajo) return KeyEventResult.ignored;

    final actual = _nodos.indexWhere((n) => n.hasFocus);
    // Ninguno de los nuestros tiene el foco: no es asunto de este rail.
    if (actual < 0) return KeyEventResult.ignored;

    final destino = arriba ? actual - 1 : actual + 1;
    if (destino < 0) {
      // Arriba del todo: se deja salir hacia la barra de arriba.
      return KeyEventResult.ignored;
    }
    if (destino >= _nodos.length) {
      // Abajo del todo: no hay a dónde ir, y dejarla pasar mandaba el foco
      // al contenido.
      return KeyEventResult.handled;
    }
    _nodos[destino].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final a = Ancho.de(context);
    // ── El autofocus solo si esta pantalla es la que está adelante ──────
    //
    // El aviso de beta se abre encima de la Home, y la Home se construye
    // después: su `autofocus` le arrancaba el foco al diálogo, así que las
    // flechas movían el sidebar de atrás mientras el aviso quedaba ahí
    // adelante sin poder manejarse. `isCurrent` es falso cuando hay algo
    // encima, y entonces acá no se pide nada.
    final alFrente = ModalRoute.of(context)?.isCurrent ?? true;
    // Solo la primera vez que esta pantalla está adelante (ver _yaEnfoco).
    final pedirFoco = alFrente && !_yaEnfoco;
    if (pedirFoco) {
      // Se anota para el próximo build, no ahora: cambiar estado durante el
      // build es justo lo que Flutter no deja.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _yaEnfoco = true;
      });
    }
    // ── Contraído a solo íconos, y desplegado mientras el mando está acá ──
    //
    // El ancho es lo único que cambia, y va en su PROPIA capa: así la
    // animación no arrastra al panel de contenido de al lado (que además ya
    // tiene su propio límite de repintado en `_ZonaQueAparece`), y en un
    // aparato modesto sigue siendo barata — es un `Transform`/tamaño, no un
    // repintado del texto ni de los íconos.
    final anchoObjetivo =
        _expandido ? _anchoSidebarTv(a) : _anchoSidebarContraidoTv(a);
    return RepaintBoundary(
      // Fondo propio, y DISTINTO según esté contraído o expandido.
      //
      // Contraído, el sidebar vive dentro de su propio margen reservado
      // (`margenParaElSidebar` en `HomeTV`) — es un rail de íconos AL LADO
      // del contenido, como cualquier otro, y va sólido: nada por detrás
      // que se vea a través. Reportado en vivo con foto: contraído no debe
      // superponerse, tiene que quedar al lado.
      //
      // Expandido, en cambio, la franja se vuelve más ancha que ese margen
      // y pasa a dibujarse ENCIMA de tarjetas que antes no tapaba nada —
      // ahí sí hace falta un degradado, para que se siga leyendo el texto
      // junto al ícono sin tapar del todo lo que queda debajo. Reportado en
      // vivo: «está feo, debe ser transparente» — pero esa nota era sobre
      // el expandido, no sobre el contraído.
      // ── Y contraído tampoco tapa: el halo de la tarjeta pasa por debajo ──
      //
      // El fondo sólido del rail cortaba en seco el resplandor rosado de la
      // primera tarjeta de cada fila: el halo llega hasta ahí y el rail se
      // pintaba encima, así que se veía media luna cortada por una línea
      // recta. Reportado en vivo: «el halo rosado no debe verse cortado en
      // el panel izquierdo, esa zona debe ser transparente».
      //
      // Sin fondo, el rail son sus íconos y nada más — el fondo de la
      // pantalla ya es el mismo color, así que a la vista no cambia nada
      // salvo que el halo ahora se apaga solo en vez de chocar contra un
      // borde.
      // ── Sin fondo, ni contraído ni abierto ───────────────────────────
      //
      // El panel abierto llevaba un degradado de negro casi pleno que se
      // abría hacia la derecha. La idea era que el nombre de cada categoría
      // se leyera sobre cualquier portada, pero contra el fondo carbón el
      // resultado fue peor que el problema: el tramo opaco no se funde con
      // nada, así que se recorta como un rectángulo negro pegado al costado.
      // Reportado en vivo: «la sombra del panel izquierdo hace como un
      // cuadrado raro» y, decidido después de verlo: «mejor quitale el halo
      // de fondo negro al panel izquierdo, dejalo transparente».
      //
      // Sin él, el panel son sus botones y nada más. La señal de dónde está
      // parado el usuario no se pierde —nunca dependió de este degradado—:
      // la da el fondo de cada botón en `_ItemSidebarTV`, que se pinta con el
      // acento cuando está elegido y con un gris claro cuando tiene el foco.
      // Eso se lee mejor que un panel entero oscurecido, y de paso el
      // resplandor de la primera tarjeta de cada fila ya no choca contra un
      // borde recto.
      child: AnimatedContainer(
        width: anchoObjetivo,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _frenarEnLosBordes,
          // Centrado vertical: son pocas categorías fijas, no una lista que
          // pueda crecer, así que no hace falta que puedan desplazarse —
          // alcanza con un Column centrado en el alto disponible, más
          // prolijo que dejarlas pegadas arriba con el resto de la
          // pantalla vacío debajo.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, categoria) in _CategoriaTV.values.indexed)
                Padding(
                  // Más aire entre uno y otro: pedido explícito, "no tan
                  // pegados y más grandes".
                  padding: const EdgeInsets.only(bottom: 18),
                  child: FocusableCard(
                    focusNode: _nodos[i],
                    autofocus: pedirFoco && categoria == _CategoriaTV.inicio,
                    borderRadius: 12,
                    // Ni borde ni resplandor: acá lo que se elige es un
                    // ícono suelto rodeado de negro, así que el halo era
                    // lo único que se veía y quedaba exagerado. La fila
                    // dibuja su propio fondo suave — se lee mejor y no
                    // cuesta un desenfoque por cada movimiento del mando.
                    conMarco: false,
                    conHalo: false,
                    onTap: () => widget.onElegir(categoria),
                    builder: (tieneFoco) => _ItemSidebarTV(
                      categoria: categoria,
                      elegido: widget.elegida == categoria,
                      enfocado: tieneFoco,
                      expandido: _expandido,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila del sidebar: ícono + etiqueta, grandes — en una TV se mira desde
/// el sillón, no a 30cm de la cara, así que el texto y el ícono de teléfono/
/// escritorio se quedan chicos acá.
class _ItemSidebarTV extends StatelessWidget {
  const _ItemSidebarTV({
    required this.categoria,
    required this.elegido,
    required this.enfocado,
    required this.expandido,
  });

  final _CategoriaTV categoria;

  /// La categoría que se está viendo ahora.
  final bool elegido;

  /// El mando está parado en esta fila ahora mismo.
  final bool enfocado;

  /// Si el sidebar está desplegado. Contraído, solo se ve el ícono —
  /// centrado, en vez de pegado a la izquierda con un hueco donde iría el
  /// nombre.
  final bool expandido;

  @override
  Widget build(BuildContext context) {
    // ── Calcado del boceto aprobado (`bocetos/compacto.html`) ───────────
    //
    //   .rail .item          → 32px, radio 9, opacidad .5
    //   .rail .item.elegido  → opacidad 1 + resplandor rosado
    //   .rail.abierto .item  → ancho completo, ícono + etiqueta a la
    //                          izquierda
    //
    // Sin relleno de color en el elegido: lo que lo distingue es que está
    // encendido (el resto va a media luz) y el resplandor alrededor.
    final apagado = !elegido && !enfocado;
    // Sobre el acento pleno el ícono va en blanco: pintarlo del mismo color
    // que su fondo lo haría desaparecer. Ver el bloque del fondo, abajo.
    final icono = Icon(
      categoria.icono,
      size: 27,
      color: HomeTheme.textPrimary,
    );
    // ── El fondo: sólido, no un velo ───────────────────────────────────
    //
    // Antes eran tintes translúcidos —el acento al 18/30 %, un gris al 12 %—
    // y sobre un fondo liso se veían bien. El problema aparece cuando el
    // panel se abre ENCIMA de las tarjetas: un velo deja pasar la portada
    // que hay detrás, así que el botón se mezclaba con la imagen y el
    // nombre de la categoría quedaba ilegible. Reportado con foto: «los
    // botones del panel izquierdo, en vez de blancos, ponelos de color
    // sólido para que se vea qué dicen».
    //
    // Ahora son opacos, así que tapan lo que tengan detrás y se leen igual
    // sobre cualquier cosa:
    //
    //   la que se está viendo  → el acento pleno, como la píldora de la foto
    //   por encima (enfocado)  → una superficie clara, opaca
    //   ninguna de las dos     → sin fondo, para que el rail no sea una
    //                            columna de cajas
    //
    // Nada de sombras ni degradados: son lo más caro que dibuja la GPU y acá
    // se recalcularían en cada apretón del mando.
    final Color fondo;
    if (elegido) {
      fondo = HomeTheme.accentPink;
    } else if (enfocado) {
      // El gris claro de siempre, pero OPACO. `alphaBlend` calcula qué color
      // sólido se ve igual que ese velo blanco sobre el fondo de la app, así
      // que a la vista es el mismo tono de antes y encima ya no deja pasar
      // la portada que haya detrás — que era todo el problema.
      fondo = Color.alphaBlend(
        HomeTheme.contraste.withValues(alpha: 0.22),
        HomeTheme.bg,
      );
    } else {
      fondo = Colors.transparent;
    }
    return AnimatedContainer(
      duration: PrismHubMas.animacion(const Duration(milliseconds: 140)),
      width: double.infinity,
      padding: expandido
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
          : const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: apagado ? 0.5 : 1,
        child: Row(
          mainAxisAlignment:
              expandido ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            icono,
            // El nombre no se anima entrando/saliendo con un fundido propio:
            // el `AnimatedContainer` de afuera ya recorta el ancho, así que
            // el texto desaparece con la caja misma.
            if (expandido) ...[
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  categoria.etiqueta(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    // Mismo motivo que el ícono de al lado: elegido pinta el
                    // fondo entero con `accentPink` sólido, así que el texto
                    // no puede ir de ese mismo color o desaparece contra su
                    // propio fondo — se vio en vivo, foto con el nombre de
                    // "Inicio" en blanco puro invisible sobre la píldora rosa.
                    color: HomeTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Todo lo que va a la derecha del sidebar: la barra de arriba, el
/// destacado, los filtros y las filas.
/// Entrevera los destacados de todas las extensiones, una posición a la vez
/// (primero la más reciente de cada una, después la segunda de cada una...).
///
/// Distinto de `_planos` (el que usa el carrusel infinito): ese reordena
/// pensando en el arrastre cuadro a cuadro y cachea contra su propio
/// `State`. Acá no hace falta nada de eso — esto se calcula una sola vez por
/// entrada a Inicio, para el hero secundario y las medianas, así que alcanza
/// con una función simple y sin estado.
List<(String package, ExtensionListItem item)> _entrelazarDestacados(
  List<(String, List<ExtensionListItem>)> grupos,
) {
  final resultado = <(String, ExtensionListItem)>[];
  var i = 0;
  var quedanMas = grupos.isNotEmpty;
  while (quedanMas) {
    quedanMas = false;
    for (final (package, items) in grupos) {
      if (i < items.length) {
        resultado.add((package, items[i]));
        quedanMas = true;
      }
    }
    i++;
  }
  return resultado;
}

/// El segundo destacado grande, al lado del carrusel infinito.
///
/// A diferencia del carrusel, este NO tiene temporizador propio ni se
/// re-sortea solo — pedido explícito: "solo en inicio la primera es
/// infinita [...] solo esa cambia el diseño". Mismo vestido visual que
/// `_TarjetaGrande` (radio, filo de acento, título abajo con sombra en vez
/// de velo — ver el comentario largo de por qué ahí NO hay velo).
class _HeroSecundarioTv extends StatelessWidget {
  const _HeroSecundarioTv({required this.package, required this.item});

  final String package;
  final ExtensionListItem item;

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(_radioGrandeTv);
    // ── El ancho para decodificar sale de la CAJA, no de la pantalla ────
    //
    // Estaba con el ancho de la pantalla entera: en un televisor de 1280
    // eso decodifica una portada de 1280 de ancho para una tarjeta que
    // mide la mitad — más del doble de ancho, casi siete veces los
    // píxeles, y encima queda VIVA en la caché mientras la tarjeta esté
    // montada (no se puede desalojar). En un aparato de 893 MB eso solo
    // ya es una mordida enorme del techo de imágenes.
    return LayoutBuilder(builder: (context, caja) {
      final anchoUtil = caja.maxWidth.isFinite
          ? caja.maxWidth
          : MediaQuery.sizeOf(context).width;
      // ── Enfocable de verdad ────────────────────────────────────────
      //
      // Era un `GestureDetector` suelto: se podía tocar con un mouse pero
      // el mando NUNCA lo alcanzaba, así que el segundo destacado del
      // Inicio no se podía elegir con el control.
      return FocusableCard(
        borderRadius: _radioGrandeTv,
        onTap: () => _abrir(context, item, package),
        builder: (tieneFoco) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radio,
            border: Border.all(
              color: HomeTheme.accentPink.withValues(alpha: 0.55),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: radio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CacheNetWorkImagePic(
                  item.cover ?? '',
                  fit: BoxFit.cover,
                  cacheWidth:
                      (anchoUtil * MediaQuery.devicePixelRatioOf(context))
                          .ceil()
                          .clamp(1, 4096),
                  headers: _cabeceras(package),
                  placeholder: const Esqueleto(radio: 20),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // De qué extensión viene: solo al enfocar, igual
                        // que en el resto de las tarjetas del televisor.
                        if (tieneFoco)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              ExtensionUtils
                                      .runtimes[package]?.extension.name ??
                                  '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: HomeTheme.accentPink,
                                shadows: const [
                                  Shadow(
                                      blurRadius: 4, color: Color(0xE6000000)),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: HomeTheme.sobrePortada,
                            shadows: [
                              Shadow(blurRadius: 3, color: Color(0xE6000000)),
                              Shadow(blurRadius: 12, color: Color(0x99000000)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// La fila de "medianas": tarjetas anchas con el título superpuesto, sin
/// panel de extensión (a diferencia de las filas de pósters de abajo). Es
/// el mismo puente visual que en el boceto — ni tan grande como el hero ni
/// tan chica como un póster.
///
/// Reusa `HomeMediaCard` (ya construida para tarjetas 16:9 con título
/// encima — la misma que arma Continuar viendo en Biblioteca) en vez de un
/// widget nuevo: ya trae foco D-pad propio en TV.
/// Una "mediana": tarjeta ancha con la portada a sangre y el titulo
/// superpuesto abajo a la izquierda. Del boceto aprobado
/// (bocetos/compacto.html, `.mediana`).
class _MedianaTv extends StatelessWidget {
  const _MedianaTv({required this.package, required this.item});

  final String package;
  final ExtensionListItem item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      final ancho = caja.maxWidth.isFinite
          ? caja.maxWidth
          : MediaQuery.sizeOf(context).width / 4;
      return FocusableCard(
        borderRadius: _radioGrandeTv,
        onTap: () => _abrir(context, item, package),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radioGrandeTv),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CacheNetWorkImagePic(
                item.cover ?? '',
                fit: BoxFit.cover,
                cacheWidth: (ancho * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 4096),
                headers: _cabeceras(package),
                placeholder: const Esqueleto(radio: 3),
              ),
              // El velo: solo lo justo para que el titulo se lea, apagandose
              // antes de la mitad. Mismos numeros del boceto.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                    stops: [0, 0.58],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: HomeTheme.sobrePortada,
                      shadows: [
                        Shadow(blurRadius: 4, color: Color(0xE6000000)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// La fila de medianas: CUATRO en columnas iguales, casi pegadas — no una
/// tira que se desplaza. Del boceto, `.medianas` es una grilla de cuatro
/// que ocupa todo el ancho.
class _FilaMedianasTv extends StatelessWidget {
  const _FilaMedianasTv({required this.items, required this.alto});

  final List<(String package, ExtensionListItem item)> items;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final cuantas = items.length < 4 ? items.length : 4;
    if (cuantas == 0) return const SizedBox.shrink();
    // ── Marcada como FILA, aunque no se desplace ────────────────────────
    //
    // Sin esto, el mando no tenía forma de saber que estas cuatro son «la
    // misma fila»: no cuelgan de ningún scroll horizontal del que agarrarse
    // (es un `Row` común). Y sin fila que respetar, la flecha derecha en la
    // última terminaba saltando abajo, que es justo lo que los topes vienen
    // a evitar. Reportado en vivo, ya con las filas de abajo arregladas:
    // «las 4 chicas y las 2 grandes, al ir a la derecha, salta y se va
    // abajo».
    //
    // La marca va ACÁ ADENTRO y no en quien la usa: así viaja con la fila y
    // no depende de que alguien se acuerde de ponerla —que es exactamente
    // lo que había pasado, el hero la tenía y esta no.
    return FranjaFijaTv(
      child: SizedBox(
      height: alto,
      // ── Aire contra el rail, antes de la primera tarjeta ────────────────
      //
      // Las filas de pósters reservan margen propio (`_margenDeFilaTv`) más
      // el aire del recorte de la fila (`aireLateral: 24`) antes de la
      // primera tarjeta. Esta fila no tenía ninguno de los dos: la primera
      // "mediana" arrancaba pegada al filo del rail. Con tarjetas angostas
      // eso pasaba casi desapercibido, pero una mediana es bastante más
      // ancha, así que el marco de foco (que crece hacia afuera al
      // seleccionarla) tenía casi nada de aire antes de chocar contra el
      // rail — reportado con foto: "las cards se cortan y se ven mal al
      // estar seleccionadas cerca del panel izquierdo".
      child: Padding(
        // Solo el de la izquierda: el de la derecha lo pone `_aireDerechoTv`
        // para todo el contenido por igual, así las medianas quedan
        // alineadas con las filas de abajo.
        // A los DOS lados: la última mediana llega al borde derecho del
        // contenido, y sin aire propio su marco se ve cortado ahí.
        // Reportado en vivo: «la card chica de la derecha, la última, dale
        // aire, se corta el borde rosado».
        padding: const EdgeInsets.symmetric(
          horizontal: HomeTheme.aireDeFocoTv,
        ),
        child: Row(
          children: [
            for (var i = 0; i < cuantas; i++) ...[
              if (i > 0) const SizedBox(width: _huecoGrandeTv),
              Expanded(
                child: _MedianaTv(package: items[i].$1, item: items[i].$2),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// Una tarjeta de fila densa: la portada 2:3 y el titulo CHICO debajo.
/// Del boceto: `.tarjeta` / `.tarjeta .arte` / `.tarjeta .nombre`.
class _TarjetaDensaTv extends StatelessWidget {
  const _TarjetaDensaTv({
    required this.package,
    required this.item,
    required this.ancho,
    this.encabezado,
    this.focusNode,
  });

  final String package;
  final ExtensionListItem item;
  final double ancho;

  /// De que extension viene. Solo se ve dentro del panel al enfocar, como
  /// en el resto del app.
  final String? encabezado;

  /// Para la primera tarjeta de la fila: el mismo nodo que tenía el giro de
  /// carga, así el foco no se pierde ni salta al llegar el contenido. Ver
  /// `_FilaZonaTv._focoFila`.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusableCard(
            focusNode: focusNode,
            // La MISMA curva que la portada (`TarjetaDeCatalogo` usa
            // `radioTv` en televisor). Con el radio grande de los destacados,
            // el marco dibujaba una esquina más abierta que la de la imagen y
            // se veía como si el borde no encajara.
            borderRadius: HomeTheme.radioTv,
            // Solo la portada lleva el marco: el nombre va afuera, debajo.
            altoMarco: ancho * 3 / 2,
            onTap: () => _abrir(context, item, package),
            builder: (tieneFoco) => TarjetaDeCatalogo(
              titulo: item.title,
              encabezado: encabezado,
              fecha: item.update,
              portada: item.cover,
              cabeceras: _cabeceras(package),
              ancho: ancho,
              tvFoco: tieneFoco,
              // Una sola línea: en una fila de televisor, las dos líneas de
              // título más los metadatos son cincuenta puntos por fila que
              // terminan empujando la fila siguiente fuera de pantalla.
              tituloEnUnaLinea: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila densa: el nombre de la extension en chico y arriba, y debajo la
/// tira de posters. Siete enteros y el siguiente asomando.
class _FilaDensaTv extends StatefulWidget {
  const _FilaDensaTv({
    required this.rotulo,
    required this.items,
    this.alLlegarAlFinal,
    this.focoPrimero,
  });

  final String rotulo;

  /// Paquete + item de cada tarjeta.
  final List<(String package, ExtensionListItem item)> items;

  /// Qué hacer cuando el usuario se acerca al final de la fila.
  ///
  /// En una zona de televisor las filas crecen a lo ANCHO, no a lo largo:
  /// la cantidad de filas es la cantidad de extensiones. Así que la página
  /// siguiente se pide acá, al llegar al final de esta fila.
  final VoidCallback? alLlegarAlFinal;

  /// El nodo de foco para la PRIMERA tarjeta — ver `_FilaZonaTv._focoFila`.
  final FocusNode? focoPrimero;

  @override
  State<_FilaDensaTv> createState() => _FilaDensaTvState();
}

class _FilaDensaTvState extends State<_FilaDensaTv> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.alLlegarAlFinal != null) {
      _scroll.addListener(_alAcercarseAlFinal);
    }
  }

  void _alAcercarseAlFinal() {
    if (!_scroll.hasClients) return;
    final restante = _scroll.position.maxScrollExtent - _scroll.offset;
    // Dos tarjetas de margen: alcanza para que la página nueva llegue antes
    // de que el usuario toque el final, sin pedirla apenas empieza a mover.
    if (restante < _anchoPosterTv(context) * 2) {
      widget.alLlegarAlFinal!();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_alAcercarseAlFinal);
    _scroll.dispose();
    super.dispose();
  }

  /// Corre la fila casi una pantalla hacia el lado que se pidió.
  ///
  /// Mismo salto y misma curva que las filas de Inicio (`_FilaWindows._correr`):
  /// el 80 % del ancho visible, para que la última tarjeta que se estaba
  /// viendo quede asomando del otro lado y no se pierda el hilo de dónde
  /// estaba uno.
  void _correr(int signo) {
    if (!_scroll.hasClients) return;
    final salto = _scroll.position.viewportDimension * 0.8;
    _scroll.animateTo(
      (_scroll.offset + salto * signo)
          .clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = _anchoPosterTv(context);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── El nombre de la extensión, bien visible ───────────────
            //
            // Estaba en gris tenue y a 14: desde el sillón no se leía, y
            // sin él una fila no dice de dónde viene lo que muestra.
            // Pedido explícito: «faltó el título arriba de cada, de qué es
            // de cada extensión, con su espacio correcto y que se vea».
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 2, bottom: 10),
              // ── Con sus flechas, igual que las filas de Inicio ─────────
              //
              // Las filas de Inicio (`_FilaWindows`) siempre tuvieron a la
              // derecha del título un par de chevrones que corren la fila.
              // Las de las zonas nacieron sin ellos, así que en Películas o
              // Anime nada avisaba de que cada fila sigue hacia el costado —
              // y con el fundido de los bordes, una fila con quince tarjetas
              // se veía igual que una con siete. Pedido explícito: «agregá
              // esas flechitas de izquierda derecha también en animes,
              // películas, etc., como en inicio».
              //
              // Se reusa `_FlechaDeFila` tal cual —vive en la parte de
              // Windows de esta misma biblioteca, así que se ve desde acá—
              // en vez de dibujar otro par igual.
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.rotulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: HomeTheme.textPrimary,
                      ),
                    ),
                  ),
                  _FlechaDeFila(
                    icono: Icons.chevron_left_rounded,
                    onTap: () => _correr(-1),
                  ),
                  const SizedBox(width: 4),
                  _FlechaDeFila(
                    icono: Icons.chevron_right_rounded,
                    onTap: () => _correr(1),
                  ),
                ],
              ),
            ),
            SizedBox(
              // Portada + aire + una línea de título (lo pone la tarjeta).
              height: TarjetaDeCatalogo.altoDeUnaLineaDeAncho(ancho),
              // ── Recortada a los costados, abierta arriba y abajo ───────
              //
              // Estaba con `Clip.none` a secas para que el marco de foco
              // pudiera salirse de la fila. Pero `Clip.none` no distingue
              // ejes: también dejaba que las tarjetas que se van POR LA
              // IZQUIERDA al desplazar la fila se siguieran dibujando fuera
              // de ella, encima del rail de categorías. Reportado con foto:
              // «las cards se comen la zona del panel izquierdo» y «los
              // botones están atrás del card».
              //
              // `_SoloCostados` es justo para esto y ya lo usaban las filas
              // de Inicio: corta a izquierda y derecha, donde molesta, y deja
              // pasar arriba y abajo, que es por donde sale el resplandor.
              //
              // El aire lateral tiene que ser mayor que lo que sobresale el
              // marco de foco (`_grosorDelMarco`, 3 puntos) o volveríamos a
              // ver el borde mordido — reportado también: «en esa zona se
              // corta el borde de selección de la card». Con 24 sobra, y
              // sigue siendo menos que el aire que la fila tiene hasta el
              // rail.
              // Y el mismo desvanecido que las filas de Inicio: sin él, la
              // tarjeta del borde termina en un filo recto y la fila se lee
              // como si ahí se acabara. Pedido explícito: «me gusta ese
              // difuminado del Inicio, replicalo a Anime, Películas, etc.».
              child: DesvanecidoDeFila(
                scroll: _scroll,
                child: ClipRect(
                  clipper: const RecorteDeFila(aireLateral: 24),
                  child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas,
                  // Que la tarjeta que sale de pantalla se DESTRUYA y suelte
                  // su portada, en vez de quedarse viva ocupando el techo de
                  // imágenes. Ninguna de estas tarjetas pide seguir viva.
                  addAutomaticKeepAlives: false,
                  // El mismo margen que las filas de Inicio, y por el mismo
                  // motivo: el marco de foco se dibuja por fuera de la
                  // tarjeta, así que la primera necesita unos puntos antes
                  // del recorte o su lado izquierdo se ve más fino que los
                  // otros tres. Ver `_margenDeFilaTv`.
                  padding: const EdgeInsets.symmetric(
                    horizontal: HomeTheme.aireDeFocoTv,
                  ),
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: _huecoPosterTv),
                  itemBuilder: (context, i) {
                    final par = widget.items[i];
                    return _TarjetaDensaTv(
                      package: par.$1,
                      item: par.$2,
                      ancho: ancho,
                      encabezado: widget.rotulo,
                      focusNode: i == 0 ? widget.focoPrimero : null,
                    );
                  },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContenidoTV extends StatelessWidget {
  const _ContenidoTV({required this.c});

  final CatalogoExtensionesController c;

  List<FilaDeExtension> _visibles() => c.filas
      .where((f) => f.estadoExt == EstadoExtension.activa || f.esVistaPrevia)
      // Preferencia de Ajustes (Fase 11): qué zonas se mezclan en Inicio.
      // Vacía = todas, como siempre.
      .where((f) => ZonasPreferidasEnInicio.pasaElFiltro(
            ExtensionUtils.zonasDe(f.package),
          ))
      // ── En TV, nada de lectura. Nada, ni mezclado ──────────────────
      //
      // Antes esto era `!esSoloLectura`, y una extensión MIXTA
      // (ShadeManga: anime y manga en el mismo sitio) pasaba el filtro
      // porque no es «solo lectura». Su fila se pide con `latest()` sin
      // filtros, así que traía capítulos de manga mezclados con los
      // episodios de anime.
      //
      // Regla del proyecto, repetida: «en Android TV solamente se puede
      // ver contenido de vídeo; en ninguna zona debe haber ni una card
      // que sea de lectura». Así que acá entran las que son vídeo y nada
      // más. La mixta no se pierde: en su ZONA sí se puede pedir solo su
      // parte de vídeo (`filtroDeFormatoZona`), que es lo que el Inicio no
      // tiene forma de hacer. Ver `ExtensionUtils.esSoloVideo`.
      .where((f) => ExtensionUtils.esSoloVideo(f.package))
      .toList();

  @override
  Widget build(BuildContext context) {
    // La barra de arriba NO va acá: vive en `HomeTV`, arriba de todo, para
    // que no se pierda al cambiar de zona ni al reciclarse la lista. Ver el
    // comentario ahí.
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            final visibles = _visibles();
            final entrelazados = _entrelazarDestacados(c.destacadosVisibles);
            final heroSecundario =
                entrelazados.length > 1 ? entrelazados[1] : null;
            final medianas = entrelazados.skip(2).take(4).toList();
            // Cuántos ítems ocupa la cabecera antes de llegar a las filas
            // por extensión: el hero (siempre) + las medianas (si hay).
            final extraArriba = medianas.isEmpty ? 1 : 2;
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              // ── Aire arriba y abajo, para el marco de foco ─────────────
              //
              // Una lista RECORTA contra sus bordes. La primera tarjeta y la
              // última quedan pegadas a ese recorte, y como el marco de foco
              // (más su resplandor) se dibuja por FUERA de la tarjeta, se
              // veía cortado justo en esas dos. Reportado en vivo: «arriba
              // en la grande del inicio se corta, no hay aire» y «las cards
              // de abajo las estás cortando».
              padding: const EdgeInsets.only(top: 20, bottom: 56),
              // ── Se construye una pantalla POR DELANTE ─────────────────
              //
              // Cada fila pide su contenido cuando se construye, y de fábrica
              // Flutter construye apenas 250 px de más: en un televisor eso es
              // menos de una fila, así que la fila se armaba justo al entrar en
              // pantalla y sus tarjetas llegaban un segundo después.
              //
              // Reportado en vivo: «bajo y veo el nombre de la extensión pero
              // no se ve nada, y cuando bajo otra vez ahí recién aparecen las
              // tarjetas». No era el dibujado: era el pedido, que arrancaba
              // tarde.
              //
              // Con una pantalla de adelanto, la fila siguiente ya pidió lo
              // suyo mientras se mira la anterior, y al llegar ya está puesta.
              //
              // Ojo: esto es lo CONTRARIO de lo que se hace en los carruseles
              // horizontales, donde construir de más es trabajo perdido. Acá lo
              // que se adelanta no es dibujado sino una petición de red, que es
              // justo lo que conviene adelantar.
              scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas ??
                  const ScrollCacheExtent.viewport(1),
              // El hero (+ medianas si hay) ocupan `extraArriba` ítems.
              itemCount: (visibles.isEmpty ? 2 : visibles.length) + extraArriba,
              itemBuilder: (context, i) => switch (i) {
                // Sin FocusableCard alrededor: el carrusel se enfoca solo y
                // maneja sus propias flechas (ver _CarruselAndroid con
                // conFocoTv). Envuelto, el foco se quedaba afuera y las
                // teclas nunca llegaban adentro.
                //
                // Si hay hero secundario, va al lado en la misma fila — con
                // el mismo alto que el carrusel se da a sí mismo para ESE
                // ancho (`_medirCarrusel`, la misma fórmula, no una
                // adivinada aparte), para que ninguno de los dos fuerce al
                // otro a un tamaño que no pidió.
                // ── Los dos grandes de arriba ────────────────────────
                //
                // Proporciones del boceto aprobado, medidas sobre la foto
                // del televisor: los grandes se llevan el 55% del alto
                // util y las medianas el 24%, con seis pixeles de hueco.
                // Casi pegadas: los catorce que habia antes se veian como
                // huecos negros entre tarjetas.
                0 => RepaintBoundary(
                    // El aire a los costados y arriba ya lo ponen
                    // `_aireDerechoTv`/`_aireDelRailTv` y el relleno de la
                    // lista, para TODO el contenido por igual — antes esto
                    // llevaba el suyo propio y dejaba el hero desalineado
                    // respecto de las filas de abajo.
                    // ── Y su propio aire arriba y a la derecha ────────────
                    //
                    // El destacado no lleva `FocusableCard` (se enfoca solo,
                    // ver más abajo): su borde de selección lo dibuja el
                    // carrusel AL RAS de la tarjeta, así que necesita que la
                    // tarjeta no llegue justo al filo de su caja. Reportado
                    // en vivo con foto: «arriba y derecha no hay aire, corta
                    // el borde».
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: SizedBox(
                      height: _altoGrandesTv(context),
                      child: heroSecundario == null
                          ? _CarruselAndroid(
                              c: c,
                              conFocoTv: true,
                              sinVecinos: true,
                            )
                          // Franja fija: ver FranjaHorizontalTv. Sin scroll
                          // de por medio (es un Row común de dos), el D-pad
                          // no tenía cómo saber que carrusel y hero
                          // secundario son "la misma fila" — al llegar al
                          // final del secundario y seguir con la derecha,
                          // la selección se perdía.
                          : FranjaFijaTv(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _CarruselAndroid(
                                      c: c,
                                      conFocoTv: true,
                                      sinVecinos: true,
                                      haySecundarioALaDerecha: true,
                                    ),
                                  ),
                                  const SizedBox(width: _huecoGrandeTv),
                                  Expanded(
                                    child: _HeroSecundarioTv(
                                      package: heroSecundario.$1,
                                      item: heroSecundario.$2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ),
                    ),
                  ),
                1 when medianas.isNotEmpty => Padding(
                    padding: const EdgeInsets.only(
                      top: _huecoGrandeTv,
                      bottom: 13,
                    ),
                    child: _FilaMedianasTv(
                      items: medianas,
                      alto: _altoMedianasTv(context),
                    ),
                  ),
                _ => visibles.isEmpty
                    ? const _FilaEsperando()
                    : (i - extraArriba < visibles.length
                        ? _FilaWindows(
                            key: ValueKey(visibles[i - extraArriba].package),
                            c: c,
                            fila: visibles[i - extraArriba],
                            conFocoTv: true,
                          )
                        : const SizedBox.shrink()),
              },
            );
          }),
        ),
      ],
    );
  }
}

/// El catálogo de una zona de contenido (Películas/Series/Anime), en TV.
///
/// Usa el mismo `ZonaCatalogoController` que ya prueban las 4 pestañas de
/// Android/Windows/Linux (Fase 6d del plan de rediseño) — mismo
/// `tag: zona.name`, así que visitar la misma zona desde el teléfono y
/// después desde TV encuentra lo que ya se había cargado, no arma dos
/// copias.
///
/// ── Por qué ahora SÍ es una grilla, igual que PC/Android ─────────────────
///
/// Pedido explícito, con una captura de `ZonaCatalogoPage` (PC): la misma
/// grilla intercalada (`c.entrelazados`, sin agrupar por extensión, sin un
/// título de fila por cada una) en vez de filas horizontales separadas por
/// fuente. Antes se había optado por filas por un riesgo sin confirmar
/// —el recorrido D-pad por defecto de Flutter (`focusInDirection`) no
/// estaba probado en un layout 2D—, pero el pedido es directo y se
/// implementa: mismo `SliverGridDelegateWithFixedCrossAxisCount` que ya usa
/// `ZonaCatalogoPage._rejilla`, mismo `TarjetaDeCatalogo` (póster vertical,
/// no la card horizontal que se había probado antes), cada celda envuelta
/// en `FocusableCard` para el D-pad. Si el recorrido direccional no se
/// siente bien en la práctica con un control remoto real, es el punto
/// concreto a revisar — no hay forma de confirmarlo sin probarlo en un
/// aparato de verdad.
class _ZonaTv extends StatefulWidget {
  const _ZonaTv({required this.zona});

  final ZonaPrincipal zona;

  @override
  State<_ZonaTv> createState() => _ZonaTvState();
}

class _ZonaTvState extends State<_ZonaTv> {
  late final ZonaCatalogoController c =
      Get.isRegistered<ZonaCatalogoController>(tag: widget.zona.name)
          ? Get.find<ZonaCatalogoController>(tag: widget.zona.name)
          : Get.put(
              ZonaCatalogoController(widget.zona),
              tag: widget.zona.name,
            );

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alAcercarseAlFinal);
    // ── Refresco al entrar, pero SOLO si hace falta ────────────────────
    //
    // Reportado en vivo: "en las zonas no hay refresco automático, el
    // usuario no tiene forma de que le aparezcan las cosas y no salen las
    // cards".
    //
    // El controller pide su primera carga solo al CREARSE (`onInit`). Si
    // ya estaba registrado de antes —la misma zona vista desde el teléfono,
    // o una visita anterior en esta misma sesión— se reusa tal cual, y si
    // aquella vez quedó sin nada (las extensiones todavía no habían
    // terminado de cargar y se agotaron los tres reintentos de
    // `cargarInicial`), la zona se quedaba vacía para siempre. En PC/
    // Android eso se arregla solo con el botón de refrescar o deslizando
    // hacia abajo; en TV no hay ninguno de los dos, así que no había NINGUNA
    // salida salvo cerrar la app.
    //
    // "Controlado" y no un refresco en cada entrada: solo se pide si de
    // verdad no hay nada que mostrar. Con contenido ya cargado no se toca
    // nada — volver a una zona la encuentra tal cual se dejó, que es lo que
    // este controller viene a garantizar. Y `cargarInicial()` tiene su
    // propio candado (`if (cargando.value) return`), así que aunque justo
    // estuviera cargando, esto no dispara un segundo pedido.
    // `pedirTodas: false`: se arma la lista de fuentes pero no se le pide
    // nada a ninguna. Cada fila pide lo suyo al construirse, o sea cuando de
    // verdad está por verse (ver `_FilaZonaTv`). Pedirle a las diez de golpe
    // al entrar levanta diez motores de JavaScript para mostrar dos filas —
    // que es lo que el registro del televisor mostraba justo antes de que el
    // sistema matara la app.
    if (c.fuentes.isEmpty || c.hayExtensionesNuevas) {
      unawaited(c.cargarInicial(pedirTodas: false));
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_alAcercarseAlFinal);
    _scroll.dispose();
    super.dispose();
  }

  void _alAcercarseAlFinal() {
    if (!_scroll.hasClients) return;
    final restante = _scroll.position.maxScrollExtent - _scroll.offset;
    // ── Bajar ya no pide más ─────────────────────────────────────────
    //
    // Con filas, la cantidad de filas es la cantidad de extensiones: bajar
    // no puede traer nada nuevo. Lo que crece es cada fila hacia la
    // DERECHA, y eso lo pide la propia fila al llegar a su final (ver
    // `ZonaCatalogoController.paginarFuente`). Pedir acá era una petición
    // por extensión, con su motor, para no mostrar nada.
    //
    // El método se conserva enganchado: es donde iría cualquier cosa que
    // dependa de haber llegado al fondo.
    if (restante < 0) return;
  }

  @override
  Widget build(BuildContext context) {
    // ── Refresco al VOLVER a esta categoría, no solo al crearla ─────────
    //
    // El chequeo de `hayExtensionesNuevas` estaba solo en `initState`, que
    // en televisor corre UNA vez por toda la vida de la app: cada categoría
    // vive para siempre dentro del `IndexedStack` (ver `_visitadas`), así
    // que `initState` nunca se vuelve a llamar por más veces que se entre y
    // se salga.
    //
    // Reportado en vivo: activar o desinstalar una extensión y volver a la
    // zona la dejaba diciendo "sin contenido" — el cambio había pasado,
    // pero nadie volvía a preguntar.
    //
    // Acá SÍ se vuelve a preguntar: cada vez que la categoría elegida
    // cambia (en cualquier pestaña, no solo esta), `_HomeTVState` se
    // reconstruye entera y Flutter reconcilia TODOS los hijos del
    // `IndexedStack` —los visibles y los escondidos—, así que este `build`
    // se vuelve a llamar sin importar si esta categoría es la que se ve
    // ahora. Es la misma pasada que ya obligó a poner `ExcludeFocus` y
    // `TickerMode` en cada hijo: barata, y se aprovecha para esto también.
    if (c.hayExtensionesNuevas) unawaited(c.cargarInicial(pedirTodas: false));
    return Obx(() {
      // Mismo criterio que en cualquier otra pantalla de la app: hasta que
      // `armado` diga que de verdad terminó de mirar, una lista vacía no
      // significa "no hay nada".
      if (!c.armado.value) {
        return const _HomeEsperando(conCabecera: false);
      }
      if (c.fuentes.isEmpty) {
        // Ninguna extensión activa entra en esta zona — la misma pantalla
        // que ya usa ZonaCatalogoPage para el mismo caso (Fase 5).
        return const ZonaSinClasificar();
      }
      final todos = c.entrelazados;
      if (todos.isEmpty && !c.fuentes.any((f) => f.isFetching)) {
        // Hay fuentes clasificadas pero su catálogo vino vacío de todas —
        // distinto de "ninguna la declara" (eso es ZonaSinClasificar,
        // arriba).
        return Center(
          child: Text(
            'common.no-data'.i18n,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 16),
          ),
        );
      }
      // ── Cabecera de la zona: hero + hero secundario + medianas ─────────
      //
      // ── Solo filas densas, una por extensión ──────────────────────
      //
      // Del boceto aprobado, calcando la foto del televisor: acá NO hay
      // destacados ni medianas —eso es de Inicio—. Una zona son puras
      // filas de pósters, siete por fila y el octavo asomando, con el
      // nombre de la extensión chico arriba y el título de cada uno
      // debajo. Se ven dos filas y media, que era el pedido: "mirá el
      // tamaño, el espacio, la proporción, se ve todo".
      //
      // La paginación/caché de cada fuente (`cargarMas`) no se toca: esto
      // solo decide cómo se dibuja lo que ya hay.
      // Hasta `_maxFilasPorZonaTv` filas: ver el porqué allá.
      // Rotadas: con muchas extensiones instaladas no entran todas, así
      // que cada visita arranca por otra y a lo largo de unas cuantas se
      // terminan viendo todas. Ver `ZonaCatalogoController.fuentesRotadas`.
      final todasLasFuentes = c.fuentesRotadas;
      final fuentes = todasLasFuentes.length > _maxFilasPorZonaTv
          ? todasLasFuentes.take(_maxFilasPorZonaTv).toList()
          : todasLasFuentes;
      final cargandoMas = c.cargandoMas.value;
      return ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // Mismo aire que en Inicio, y por el mismo motivo: la lista recorta
        // contra sus bordes y el marco de foco se dibuja por fuera de la
        // tarjeta. Ver el comentario en `_ContenidoTV`.
        padding: const EdgeInsets.only(top: 20, bottom: 56),
        scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas ??
            const ScrollCacheExtent.viewport(1),
        // Ver el mismo comentario en la tira de pósters: la fila que sale
        // de pantalla se destruye y suelta sus portadas.
        addAutomaticKeepAlives: false,
        // Una por fuente + el pie.
        itemCount: fuentes.length + 1,
        itemBuilder: (context, i) {
          if (i < fuentes.length) {
            return _FilaZonaTv(
              key: ValueKey(fuentes[i].package),
              fuente: fuentes[i],
              controlador: c,
            );
          }
          // ── Un pie que diga en qué estado está la lista ──────────────
          //
          // Reportado en vivo: "al ir bajando no se da cuenta si están
          // cargando cards o si ya terminó".
          // ── El pie, con filas, dice otra cosa ───────────────────────
          //
          // Con la grilla intercalada bajar traía más, y el pie invitaba a
          // seguir bajando. Con filas no: la cantidad de filas es la
          // cantidad de extensiones y no cambia por bajar. Lo que crece es
          // cada fila hacia la derecha (ver `_FilaDensaTv.alLlegarAlFinal`).
          //
          // Así que acá abajo ya no hay nada que prometer: se dice que eso
          // es todo. Reportado en vivo: «me dice seguí bajando para ver más
          // y no me da más contenido».
          return _PieDeZonaTv(
            cargando: cargandoMas,
            // Ni «seguí bajando» (abajo no hay más filas) ni «no hay más
            // datos» (sí lo hay: cada fila sigue hacia la derecha). El
            // texto neutro es el único que dice la verdad acá.
            hayMas: false,
            seAgotoDeVerdad: false,
          );
        },
      );
    });
  }
}

/// Una fila de la zona: el nombre de la extensión arriba, sus portadas
/// abajo — mismo molde visual que `_FilaWindows` en Inicio, adaptado a
/// `ZonaFuente` (el modelo de `ZonaCatalogoController`, más simple: sin
/// `estadoExt` ni `refrescando`, solo `isFetching`/`agotada`).
class _FilaZonaTv extends StatefulWidget {
  const _FilaZonaTv({
    super.key,
    required this.fuente,
    required this.controlador,
  });

  final ZonaFuente fuente;

  /// Para pedirle a ESTA fuente lo suyo cuando la fila aparece.
  final ZonaCatalogoController controlador;

  @override
  State<_FilaZonaTv> createState() => _FilaZonaTvState();
}

class _FilaZonaTvState extends State<_FilaZonaTv> {
  Timer? _esperaAntesDePedir;

  /// El nodo de foco de esta fila, de la primera posición.
  ///
  /// ── Por qué es UNO solo para el giro Y la primera tarjeta ────────────
  ///
  /// Mientras carga, el D-pad tiene que poder pararse en esta fila —si no,
  /// bajar la salta entera y sigue de largo a la próxima, que es el bug
  /// contrario al que se arregló acá: «bloquea el scroll» hasta que haya
  /// contenido, y recién ahí sigue.
  ///
  /// Y cuando el contenido llega, el giro desaparece y en su lugar aparecen
  /// las tarjetas de verdad: si el giro tenía el foco en ese instante y cada
  /// uno usara su propio `FocusNode`, el que tenía el foco se destruye y el
  /// foco cae al ámbito de la pantalla — la selección desaparece hasta la
  /// próxima flecha, el mismo bug ya visto varias veces esta sesión.
  ///
  /// Con el MISMO objeto pasado a los dos —el giro antes, la primera
  /// tarjeta después— Flutter lo desprende de uno y lo prende al otro
  /// dentro del mismo cuadro: el foco sigue estando ahí sin que nadie tenga
  /// que rescatarlo.
  final FocusNode _focoFila = FocusNode(debugLabel: 'zona-fila');

  /// Cuánto se espera antes de pedirle contenido a esta extensión.
  ///
  /// ── Por qué no se pide de una ───────────────────────────────────────
  ///
  /// Con el mando uno no desliza: aprieta abajo, abajo, abajo. Cada fila que
  /// pasa se construye —y si pidiera en el acto, bajar de golpe por una zona
  /// dispararía diez peticiones y diez motores de JavaScript en medio
  /// segundo, que es exactamente la ráfaga que el registro del televisor
  /// mostraba antes de que el sistema matara la app.
  ///
  /// Esperando un momento, la fila por la que solo se pasó de largo se
  /// desmonta antes de llegar a pedir nada: no gasta ni red ni memoria.
  static const _esperaDelMando = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    // **Acá se dispara la carga perezosa.** Este initState corre recién
    // cuando la lista construye la fila, o sea cuando está por entrar en
    // pantalla. Lo que nunca se ve, nunca se pide — mismo criterio que ya
    // usa el Inicio con sus filas.
    _esperaAntesDePedir = Timer(_esperaDelMando, () {
      if (!mounted) return;
      unawaited(widget.controlador.pedirFuente(widget.fuente));
    });
  }

  @override
  void dispose() {
    _esperaAntesDePedir?.cancel();
    _focoFila.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fuente;
    if (f.items.isEmpty) {
      // Ya se sabe que esta fuente no tiene nada para esta zona: no vale
      // la pena dejar un título con nada debajo para siempre.
      if (f.agotada && !f.isFetching) return const SizedBox.shrink();
      final ancho = _anchoPosterTv(context);
      return RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EncabezadoFilaZonaTv(nombre: f.nombre),
              const SizedBox(height: 6),
              // El mismo alto que tendría la fila real, para que al llegar
              // el contenido la pantalla no salte — ver el porqué de fondo,
              // sin esqueleto, en `CargandoTv`.
              SizedBox(
                height: TarjetaDeCatalogo.altoDeUnaLineaDeAncho(ancho),
                width: double.infinity,
                child: Center(
                  child: FocusableCard(
                    focusNode: _focoFila,
                    borderRadius: 999,
                    onTap: () {},
                    child: const CargandoTv(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Hasta `_maxTarjetasPorFilaTv` por fila: ver el porqué allá.
    final items = f.items.length > _maxTarjetasPorFilaTv
        ? f.items.take(_maxTarjetasPorFilaTv).toList()
        : f.items;
    return _FilaDensaTv(
      rotulo: f.nombre,
      items: [for (final item in items) (f.package, item)],
      // Con la fila en su tope no hace falta pedir más: ya está llena.
      alLlegarAlFinal: f.items.length >= _maxTarjetasPorFilaTv
          ? null
          : () => unawaited(widget.controlador.paginarFuente(f)),
      focoPrimero: _focoFila,
    );
  }
}

/// El título de una fila de zona: solo el nombre de la extensión, sin
/// subtítulo — a diferencia de Inicio, acá no hay un "modo" (recientes/
/// populares) que mostrar debajo. Pedido explícito: "en anime, películas,
/// etc no debes poner subtítulo, solo es título de la extensión y listo".
class _EncabezadoFilaZonaTv extends StatelessWidget {
  const _EncabezadoFilaZonaTv({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    // El MISMO sitio y el mismo estilo que cuando la fila ya cargó (ver
    // `_FilaDensaTv`): si no, al llegar el contenido el título saltaba de
    // lugar y de tamaño, que es de lo que más se nota en una pantalla
    // grande.
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 2, bottom: 10),
      child: Text(
        nombre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: HomeTheme.textPrimary,
        ),
      ),
    );
  }
}

/// El final de la grilla de una zona, en TV.
///
/// Dice si todavía viene más o si eso es todo — ver el porqué en el
/// comentario de `_ZonaTvState.build`. Sin esto la lista simplemente se
/// cortaba y no había forma de distinguir una cosa de la otra.
class _PieDeZonaTv extends StatelessWidget {
  const _PieDeZonaTv({
    required this.cargando,
    required this.hayMas,
    required this.seAgotoDeVerdad,
  });

  final bool cargando;
  final bool hayMas;

  /// Ver [ZonaCatalogoController.seAgotoDeVerdad]: solo con esto en true se
  /// puede afirmar que no hay más contenido. Sin él, quedarse sin páginas
  /// puede ser el tope propio de la app y no el final del catálogo.
  final bool seAgotoDeVerdad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
      child: Center(
        child: cargando
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(HomeTheme.accentPink),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'common.refreshing'.i18n,
                    style: TextStyle(
                      fontSize: 16,
                      color: HomeTheme.textMuted,
                    ),
                  ),
                ],
              )
            : (!hayMas && !seAgotoDeVerdad)
                // El tope es de la app (ZonaCatalogoController.seAgotoDeVerdad
                // en false), no del catálogo real: todavía hay contenido del
                // otro lado, así que ni "no hay más" ni un aviso aparte
                // tienen sentido acá — pedido explícito, que no diga nada y
                // quede ahí nomás.
                ? const SizedBox.shrink()
                : Text(
                    hayMas
                        ? 'home.zona-seguir-bajando'.i18n
                        : 'common.no-more-data'.i18n,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: HomeTheme.textMuted,
                    ),
                  ),
      ),
    );
  }
}

/// Buscar, Favoritos, Historial, Ajustes y el reloj — el equivalente TV de
/// `_Cabecera` (teléfono) y del rail de escritorio, que acá no están.
class _BarraSuperiorTV extends StatefulWidget {
  const _BarraSuperiorTV();

  @override
  State<_BarraSuperiorTV> createState() => _BarraSuperiorTVState();
}

class _BarraSuperiorTVState extends State<_BarraSuperiorTV> {
  /// El momento que muestra el reloj. Se guarda el `DateTime` y no el texto
  /// ya armado porque el formato (24h, o 12h con a. m./p. m.) depende del
  /// idioma y de la configuración del sistema, y eso solo se puede resolver
  /// con el `context` — o sea, al dibujar, no acá.
  DateTime _ahora = DateTime.now();
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    // Cada 30s alcanza de sobra para un reloj que solo muestra hora:minuto,
    // y es mucho más liviano que uno por segundo en una pantalla que además
    // ya tiene el fondo animado y el carrusel dibujándose.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _ahora = DateTime.now());
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  // Buscar ya no es una pestaña del shell principal (ver
  // main_controller.dart) — se empuja como pantalla propia, igual que ya
  // hacen Favoritos/Historial/Repositorio acá abajo.
  void _buscar() => Get.to(() => const SearchPage());

  void _favoritos() => Get.to(() => const HistoryPage(soloFavoritos: true));

  void _historial() => Get.to(() => const HistoryPage());

  void _ajustes() {
    if (!Get.isRegistered<MainController>()) return;
    Get.find<MainController>().changeTab(MainController.tabAjustes);
  }

  /// Extensiones instaladas y repositorio, arriba y a la vista.
  ///
  /// En TV son de lo MÁS usado, no un ajuste perdido: acá el contenido no
  /// viene de un catálogo propio sino de lo que el usuario tenga instalado,
  /// así que si no hay extensiones, no hay app. Enterrarlas dos niveles
  /// dentro de Ajustes era hacer difícil justamente lo primero que hay que
  /// hacer al abrir PrismHub por primera vez.
  void _instaladas() {
    if (!Get.isRegistered<MainController>()) return;
    Get.find<MainController>().changeTab(MainController.tabExtensiones);
  }

  void _repositorio() => Get.to(() => const ExtensionRepoPage());

  @override
  Widget build(BuildContext context) {
    final barra = Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Text(
            'PrismHub',
            style: HomeTheme.tituloDeZona(bajo: false),
          ),
          const Spacer(),
          _BotonSuperiorTV(
            icono: Icons.search_rounded,
            etiqueta: 'home.tv-buscar'.i18n,
            onTap: _buscar,
          ),
          _BotonSuperiorTV(
            icono: Icons.extension_outlined,
            etiqueta: 'common.extension-installed'.i18n,
            onTap: _instaladas,
          ),
          _BotonSuperiorTV(
            icono: Icons.travel_explore_outlined,
            etiqueta: 'common.extension-repo'.i18n,
            onTap: _repositorio,
          ),
          _BotonSuperiorTV(
            icono: Icons.favorite_border_rounded,
            etiqueta: 'home.tv-favoritos'.i18n,
            onTap: _favoritos,
          ),
          _BotonSuperiorTV(
            icono: Icons.history_rounded,
            etiqueta: 'home.tv-historial'.i18n,
            onTap: _historial,
          ),
          _BotonSuperiorTV(
            icono: Icons.settings_outlined,
            etiqueta: 'home.tv-ajustes'.i18n,
            onTap: _ajustes,
          ),
          // Separación clara antes del reloj: es información, no un botón
          // más, y pegado al último parecía parte de la fila de acciones.
          const SizedBox(width: 22),
          // La hora, en el formato del aparato: `alwaysUse24HourFormat` es
          // el interruptor de "usar 24 horas" del sistema, y el idioma de la
          // app decide cómo se escribe el resto (en español "p. m.", en
          // inglés "PM"). Escribirla a mano en 24h se veía mal para quien
          // tiene el teléfono/TV configurado en 12 horas.
          Text(
            MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay.fromDateTime(_ahora),
              alwaysUse24HourFormat:
                  MediaQuery.alwaysUse24HourFormatOf(context),
            ),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: HomeTheme.textMuted,
            ),
          ),
        ],
      ),
    );
    // La barra, en su propia capa.
    //
    // El reloj se actualiza cada 30 segundos, y ese `setState` vuelve a pintar
    // toda la barra —el nombre y los seis botones con sus iconos— y, sin
    // límite, también lo que quede alrededor. Con esto, cambiar la hora
    // repinta la barra y nada más.
    //
    // ── Y su propio margen a la derecha ────────────────────────────────
    //
    // La columna que la contiene se quedó SIN margen derecho a propósito,
    // para que las filas de tarjetas lleguen hasta el filo y se vea que
    // siguen. Pero la barra no es una fila: acá el último elemento es el
    // reloj, y sin margen quedaba pegado al borde de la pantalla —
    // reportado con foto: «la hora se pegó a la derecha».
    //
    // Se lo devuelve solo a la barra, que es la única que lo necesita. El
    // mismo overscan que usa el resto de la pantalla, no un número aparte:
    // en un televisor que recorta el borde, esto es lo que evita que la
    // hora quede cortada por la mitad.
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(right: HomeTheme.overscanTv(context)),
        child: barra,
      ),
    );
  }
}

/// Un botón grande de la barra superior — mismo criterio de tamaño que el
/// sidebar: se mira de lejos.
class _BotonSuperiorTV extends StatelessWidget {
  const _BotonSuperiorTV({
    required this.icono,
    required this.etiqueta,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // El aire tiene que dar para el crecido: al enfocarse el botón escala y
    // le suma su marco, así que con la separación justa el de al lado
    // quedaba tapado por el halo del que estaba seleccionado.
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Tooltip(
        message: etiqueta,
        child: FocusableCard(
          borderRadius: 999,
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HomeTheme.cardSurface,
            ),
            child: Icon(icono, size: 26, color: HomeTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}
