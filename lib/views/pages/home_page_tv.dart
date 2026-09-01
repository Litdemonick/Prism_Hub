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
    a.elegir(compacto: 84, medio: 168, amplio: 190, enorme: 210);

/// El ancho del sidebar CONTRAÍDO — solo los íconos.
///
/// Vive acá y no adentro de `_SidebarTVState` porque el panel de contenido
/// también lo necesita: reserva ese mismo ancho como margen fijo para que
/// las tarjetas nunca queden debajo del sidebar. Un solo número para las
/// dos partes, para que no puedan desincronizarse.
double _anchoSidebarContraidoTv(Ancho a) =>
    a.elegir<double>(compacto: 64, medio: 72, amplio: 76, enorme: 80);

/// El margen "TV-safe" contra el borde de la pantalla (overscan).
///
/// Estaba escrito acá y en `detail_page_tv.dart` con el mismo cuerpo — ahora
/// las dos apuntan a la única definición, en `HomeTheme.overscanTv`.
double _overscanTv(BuildContext context) => HomeTheme.overscanTv(context);

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
  final Set<_CategoriaTV> _visitadas = {_CategoriaTV.inicio};

  @override
  void dispose() {
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
      // A partir de acá esta zona se arma y se queda viva. Ver [_visitadas].
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
    final overscan = _overscanTv(context);
    // El ancho contraído, siempre reservado — y solo ese.
    //
    // Dos correcciones en el mismo lugar, la segunda deshaciendo la
    // primera. Primero se sacó el margen entero (probado con foto: las
    // tarjetas quedaban tapadas por los íconos). Después, con más fotos,
    // quedó claro que CONTRAÍDO tiene que seguir siendo sólido y quedar AL
    // LADO del contenido —como cualquier rail de íconos— y que lo
    // transparente es solo lo que pasa al EXPANDIRSE: ahí sí, la franja más
    // ancha se dibuja encima sin correr nada. Ver el color condicional en
    // `_SidebarTVState`.
    final margenParaElSidebar =
        _anchoSidebarContraidoTv(Ancho.de(context)) + overscan * 1.5;
    // ── La barra de arriba manda en TODA la pantalla ────────────────────
    //
    // Estaba dentro del panel de contenido, así que entrar a una zona sin
    // catálogo (TV en vivo) o quedarse sin extensiones se llevaba puesto el
    // logo y los accesos: la pantalla quedaba sin salida visible. Acá arriba
    // vive fuera de todo lo que cambia — pase lo que pase debajo, siempre
    // están el nombre y los botones.
    return SafeArea(
      child: Padding(
        // Un solo sitio decide este margen. Ver HomeTheme.margenTv.
        padding: HomeTheme.margenTv(context),
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
                    Padding(
                      padding: EdgeInsets.only(left: margenParaElSidebar),
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
                        // La clave atada a la categoría es lo que hace que la
                        // animación vuelva a empezar en cada cambio.
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
                                            const LibraryPage(),
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
                    // Encima del contenido, no al lado — ver la nota de
                    // arriba. `Positioned` con los tres lados verticales fija
                    // el alto a la columna entera; el ancho lo decide el
                    // propio `_SidebarTV` con su `AnimatedContainer`.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: _SidebarTV(
                        c: widget.c,
                        primerFoco: _primerFoco,
                        elegida: _categoria,
                        onElegir: _elegir,
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
  KeyEventResult _frenarEnLosBordes(FocusNode node, KeyEvent evento) {
    if (evento is! KeyDownEvent) return KeyEventResult.ignored;
    if (evento.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    return _nodos.last.hasFocus
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _expandido ? null : HomeTheme.bg,
          gradient: _expandido
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    HomeTheme.bg.withValues(alpha: 0.96),
                    HomeTheme.bg.withValues(alpha: 0.78),
                    HomeTheme.bg.withValues(alpha: 0.0),
                  ],
                  stops: const [0, 0.68, 1],
                )
              : null,
        ),
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
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FocusableCard(
                      focusNode: _nodos[i],
                      autofocus: pedirFoco && categoria == _CategoriaTV.inicio,
                      borderRadius: 14,
                      onTap: () => widget.onElegir(categoria),
                      child: _ItemSidebarTV(
                        categoria: categoria,
                        elegido: widget.elegida == categoria,
                        expandido: _expandido,
                      ),
                    ),
                  ),
              ],
            ),
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
    required this.expandido,
  });

  final _CategoriaTV categoria;
  final bool elegido;

  /// Si el sidebar está desplegado. Contraído, solo se ve el ícono —
  /// centrado, en vez de pegado a la izquierda con un hueco donde iría el
  /// nombre.
  final bool expandido;

  @override
  Widget build(BuildContext context) {
    final color = elegido ? HomeTheme.accentPink : HomeTheme.textPrimary;
    // Ancho completo y alineado a la izquierda, como en la referencia: con
    // `MainAxisSize.min` cada fila medía lo que midiera su texto, así que
    // "TV" y "Novela" arrancaban en la misma x pero terminaban en distintas
    // — y el resaltado del elegido quedaba de un ancho distinto en cada
    // categoría, que es lo que se veía desprolijo.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        // Antes era un relleno plano rosa — pedido explícito: que la
        // elegida se note con un resplandor suave, como el halo de foco
        // del resto del app (`FocusableCard`), no con una caja de color.
        borderRadius: BorderRadius.circular(14),
        boxShadow: elegido
            ? [
                BoxShadow(
                  color: HomeTheme.accentPink.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment:
            expandido ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Icon(categoria.icono, size: 26, color: color),
          // El nombre no se anima entrando/saliendo con un fundido propio:
          // el `AnimatedContainer` de afuera ya recorta el ancho, así que el
          // texto desaparece con la caja misma sin necesidad de una segunda
          // animación superpuesta.
          if (expandido) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                categoria.etiqueta(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: elegido ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ],
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
    final radio = BorderRadius.circular(20);
    return GestureDetector(
      onTap: () => _abrir(context, item, package),
      child: DecoratedBox(
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
                cacheWidth: (MediaQuery.sizeOf(context).width *
                        MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 4096),
                headers: _cabeceras(package),
                placeholder: const Esqueleto(radio: 20),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
class _FilaMedianasTv extends StatelessWidget {
  const _FilaMedianasTv({required this.items});

  final List<(String package, ExtensionListItem item)> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // `altoImagenAncha`, no `altoTotalAncha`: en la variante horizontal
      // el título va superpuesto sobre la imagen (como el resto de estas
      // medianas), no debajo — `altoTotalAncha` reserva espacio de más
      // pensado para la variante vertical, que sí tiene texto aparte.
      height: HomeMediaCard.altoImagenAncha,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final (package, item) = items[i];
          return HomeMediaCard(
            horizontal: true,
            title: item.title,
            cover: item.cover,
            headers: _cabeceras(package),
            onTap: () => _abrir(context, item, package),
          );
        },
      ),
    );
  }
}

/// La cabecera de una zona de vídeo (Películas/Series/Anime): hero + hero
/// secundario + medianas, con los primeros `arriba.length` ítems de la
/// grilla de esa zona — nunca más de 6. Ninguno de los dos destacados es
/// infinito acá (solo el de Inicio lo es), así que los dos usan
/// `_HeroSecundarioTv` tal cual.
class _CabeceraZonaTv extends StatelessWidget {
  const _CabeceraZonaTv({required this.arriba});

  final List<ZonaItem> arriba;

  @override
  Widget build(BuildContext context) {
    final hero = arriba[0];
    final heroSecundario = arriba.length > 1 ? arriba[1] : null;
    final medianas = arriba.skip(2).map((zi) => (zi.package, zi.item)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, caja) {
              final anchoMitad = heroSecundario == null
                  ? caja.maxWidth
                  : (caja.maxWidth - 14) / 2;
              final alto = _medirCarrusel(
                context,
                anchoMitad,
                conFocoTv: true,
                compartido: true,
              ).alto;
              return SizedBox(
                height: alto,
                child: Row(
                  children: [
                    Expanded(
                      child: _HeroSecundarioTv(
                        package: hero.package,
                        item: hero.item,
                      ),
                    ),
                    if (heroSecundario != null) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: _HeroSecundarioTv(
                          package: heroSecundario.package,
                          item: heroSecundario.item,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (medianas.isNotEmpty) ...[
            const SizedBox(height: 18),
            _FilaMedianasTv(items: medianas),
          ],
        ],
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
      // En TV, nada de lectura — pedido explícito: "solo es video,
      // streaming, nada de lectura". `esSoloLectura` y no `zonasDe(...)
      // .isEmpty`: una extensión SIN @contentKind declarado (hoy, las 19
      // reales) también da zonasDe vacío, y esa nunca tiene que
      // desaparecer por "sin clasificar" — acá lo que importa es el
      // `type`, que siempre se conoce. Una mixta (ShadeManga) sigue
      // entrando porque SÍ aporta video, aunque su fila mezcle formatos
      // — ese reparto por formato es cosa de la Zona
      // (ZonaCatalogoController), que Inicio nunca hizo ni en teléfono
      // ni en PC.
      .where((f) => !ExtensionUtils.esSoloLectura(f.package))
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
              padding: const EdgeInsets.only(bottom: 24),
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
                0 => RepaintBoundary(
                    child: heroSecundario == null
                        ? _CarruselAndroid(c: c, conFocoTv: true)
                        : LayoutBuilder(
                            builder: (context, caja) {
                              final anchoMitad = (caja.maxWidth - 14) / 2;
                              final alto = _medirCarrusel(
                                context,
                                anchoMitad,
                                conFocoTv: true,
                                compartido: true,
                              ).alto;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _CarruselAndroid(
                                      c: c,
                                      conFocoTv: true,
                                      sinVecinos: true,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: SizedBox(
                                      height: alto,
                                      child: _HeroSecundarioTv(
                                        package: heroSecundario.$1,
                                        item: heroSecundario.$2,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                1 when medianas.isNotEmpty => Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _FilaMedianasTv(items: medianas),
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
    if (c.fuentes.isEmpty || c.entrelazados.isEmpty || c.hayExtensionesNuevas) {
      unawaited(c.cargarInicial());
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
    // El umbral se mide contra el ALTO de una tarjeta, no contra su ancho:
    // esta grilla se desplaza en vertical. Estaba con `anchoPara`, que daba
    // un número mucho más chico —una tarjeta es la mitad de ancha que de
    // alta— así que el pedido de la página siguiente salía recién casi
    // encima del final, y bajando rápido con el mando se llegaba al fondo
    // antes de que llegara nada. Dos tarjetas de alto dan margen de sobra
    // para que la página nueva entre sin que se note el corte.
    final altoTarjeta = TarjetaDeCatalogo.altoTotalPara(context);
    if (restante < altoTarjeta * 2) {
      unawaited(c.cargarMas());
    }
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
    if (c.hayExtensionesNuevas) unawaited(c.cargarInicial());
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
      // Mismo vestido visual que Inicio, con los primeros ítems de la
      // MISMA lista entrelazada. A diferencia de Inicio, acá NINGUNO de
      // los dos destacados es el carrusel infinito: son fijos (no hay
      // temporizador), porque "solo en Inicio la primera es infinita"
      // (pedido explícito). Se superponen con lo que después aparece en
      // las filas de abajo — mismo criterio que ya acepta Inicio entre su
      // destacado y sus propias filas, nunca se trató como un problema
      // ahí.
      final arriba = todos.take(6).toList();
      // ── Una fila por extensión, no una grilla mezclada ─────────────────
      //
      // Pedido explícito, calcando el boceto: cada extensión con su
      // propio título arriba (como ya hace Inicio), no todas revueltas en
      // una sola grilla. La paginación/caché de cada fuente
      // (`ZonaCatalogoController.cargarMas`) no se toca — sigue pidiendo
      // más para TODAS las fuentes por igual; esto solo cambia cómo se
      // dibuja lo que ya hay.
      final fuentes = c.fuentes;
      final cargandoMas = c.cargandoMas.value;
      return ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas ??
            const ScrollCacheExtent.viewport(1),
        // Cabecera + una por fuente + el pie.
        itemCount: fuentes.length + 2,
        itemBuilder: (context, i) => switch (i) {
          0 => arriba.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: _CabeceraZonaTv(arriba: arriba),
                ),
          _ when i - 1 < fuentes.length => _FilaZonaTv(
              key: ValueKey(fuentes[i - 1].package),
              fuente: fuentes[i - 1],
            ),
          // ── Un pie que diga en qué estado está la lista ────────────────
          //
          // Reportado en vivo: "al ir bajando no se da cuenta si están
          // cargando cards o si ya terminó". El pie va SIEMPRE al final y
          // dice una de las dos cosas.
          _ => Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: _PieDeZonaTv(
                cargando: cargandoMas,
                hayMas: c.puedeTraerMas,
                seAgotoDeVerdad: c.seAgotoDeVerdad,
              ),
            ),
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
  const _FilaZonaTv({super.key, required this.fuente});

  final ZonaFuente fuente;

  @override
  State<_FilaZonaTv> createState() => _FilaZonaTvState();
}

class _FilaZonaTvState extends State<_FilaZonaTv> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fuente;
    if (f.items.isEmpty) {
      // Ya se sabe que esta fuente no tiene nada para esta zona: no vale
      // la pena dejar un título con nada debajo para siempre.
      if (f.agotada && !f.isFetching) return const SizedBox.shrink();
      return RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(top: 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EncabezadoFilaZonaTv(nombre: f.nombre),
              const SizedBox(height: 18),
              EsqueletoDeFila(
                ancho: _anchoTarjetaTv(context),
                separacion: 14,
                padding: EdgeInsets.symmetric(horizontal: _margen(context)),
                paddingDeCadaUno: const EdgeInsets.only(top: 10),
              ),
            ],
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EncabezadoFilaZonaTv(nombre: f.nombre),
            const SizedBox(height: 18),
            SizedBox(
              height: _altoFilaTv(context),
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(
                  horizontal: _margen(context) + 26,
                ),
                itemCount: f.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final item = f.items[i];
                  // Sin isAdultOption: la Zona +18 de TV vive aparte, en
                  // Ajustes, con su propio PIN — acá `f` nunca es esa zona.
                  void abrir() => ExtensionUtils.openExtensionDetail(
                        context,
                        package: f.package,
                        url: item.url,
                        cover: item.cover,
                        coverHeaders: item.headers,
                      );
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: FocusableCard(
                      onTap: abrir,
                      altoMarco: _anchoTarjetaTv(context) * 3 / 2,
                      // `builder` y no `child`: mismo motivo que en Inicio —
                      // la tarjeta necesita saber si TIENE el foco para
                      // mostrar el panel con el nombre de la extensión.
                      builder: (tieneFoco) => TarjetaDeCatalogo(
                        titulo: item.title,
                        encabezado: f.nombre,
                        fecha: item.update,
                        portada: item.cover,
                        cabeceras: item.headers,
                        ancho: _anchoTarjetaTv(context),
                        tvFoco: tieneFoco,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _margen(context)),
      child: Text(
        nombre,
        style: HomeTheme.tituloDeFilaTv(context)
            .copyWith(fontWeight: FontWeight.w700),
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
            : Text(
                // Tres estados, no dos: "seguí bajando" mientras haya más
                // para traer, "no hay más datos" SOLO si todas las fuentes
                // dijeron de verdad que se quedaron sin nada, y un texto
                // neutro si lo que se alcanzó fue el tope propio de la app
                // (ver ZonaCatalogoController.seAgotoDeVerdad) — ahí sigue
                // habiendo contenido del otro lado, así que decir que no
                // hay más sería mentir.
                hayMas
                    ? 'home.zona-seguir-bajando'.i18n
                    : seAgotoDeVerdad
                        ? 'common.no-more-data'.i18n
                        : 'home.zona-hasta-aca'.i18n,
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
    return RepaintBoundary(child: barra);
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
