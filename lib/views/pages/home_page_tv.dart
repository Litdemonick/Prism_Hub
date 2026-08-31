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
    // Cuánto le deja SIEMPRE reservado a los íconos del sidebar — nunca
    // cambia con `_expandido`. Ver el `Stack` más abajo: el contenido usa
    // esto como margen fijo, así que expandir el sidebar no lo mueve ni lo
    // achica un píxel.
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
      // Fondo propio, opaco: el sidebar ahora se dibuja ENCIMA de las
      // tarjetas (ver el `Stack` en `HomeTV`), así que sin esto se vería el
      // póster de una tarjeta asomando detrás de sus propios íconos.
      child: DecoratedBox(
        decoration: BoxDecoration(color: HomeTheme.bg),
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
                      autofocus:
                          pedirFoco && categoria == _CategoriaTV.inicio,
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
        color: elegido
            ? HomeTheme.accentPink.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
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
              // +1: el destacado.
              itemCount: (visibles.isEmpty ? 2 : visibles.length) + 1,
              itemBuilder: (context, i) => switch (i) {
                // Sin FocusableCard alrededor: el carrusel se enfoca solo y
                // maneja sus propias flechas (ver _CarruselAndroid con
                // conFocoTv). Envuelto, el foco se quedaba afuera y las
                // teclas nunca llegaban adentro.
                0 => RepaintBoundary(
                    child: _CarruselAndroid(c: c, conFocoTv: true),
                  ),
                _ => visibles.isEmpty
                    ? const _FilaEsperando()
                    : (i - 1 < visibles.length
                        ? _FilaWindows(
                            key: ValueKey(visibles[i - 1].package),
                            c: c,
                            fila: visibles[i - 1],
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
    if (c.fuentes.isEmpty ||
        c.entrelazados.isEmpty ||
        c.hayExtensionesNuevas) {
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

  /// Cuántas columnas entran y qué ancho tiene la celda.
  ({int columnas, double ancho}) _rejillaTv(
      BuildContext context, double disponible) {
    return RejillaDeTarjetas.calcular(
      disponible: disponible,
      separacion: 20,
      televisor: PlatformTv.esTelevisionSync,
      pantalla: Ancho.de(context),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      final items = c.entrelazados;
      if (items.isEmpty && !c.fuentes.any((f) => f.isFetching)) {
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
      return LayoutBuilder(
        builder: (context, restricciones) {
          const margen = 24.0;
          final disponible = restricciones.maxWidth - margen * 2;
          if (disponible <= 0) return const SizedBox.shrink();
          final rejilla = _rejillaTv(context, disponible);
          final alto = TarjetaDeCatalogo.altoTotalDeAncho(rejilla.ancho);
          final cargandoMas = c.cargandoMas.value;
          final extra = cargandoMas ? rejilla.columnas : 0;
          // ── Un pie que diga en qué estado está la lista ────────────────
          //
          // Reportado en vivo: "al ir bajando no se da cuenta si están
          // cargando cards o si ya terminó". Con solo una fila de
          // esqueletos, bajando rápido con el mando se llega al fondo antes
          // de que aparezcan, y ahí la grilla simplemente se corta: no hay
          // forma de distinguir "esperá que viene más" de "esto es todo".
          //
          // El pie va SIEMPRE al final y dice una de las dos cosas. Ocupa
          // una fila entera de la grilla para no dejar un hueco raro al
          // lado de las tarjetas.
          return CustomScrollView(
            controller: _scroll,
            // Mismo margen de precarga generoso que ZonaCatalogoPage: con
            // tarjetas altas, el default de Flutter (250px) apenas cubre
            // una fila de sobra.
            scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas ??
                ScrollCacheExtent.pixels(alto * 2),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(margen, 8, margen, 0),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: rejilla.columnas,
                    childAspectRatio: rejilla.ancho / alto,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 28,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: items.length + extra,
                    (context, i) {
                      if (i >= items.length) {
                        return EsqueletoTarjeta(ancho: rejilla.ancho);
                      }
                      final zi = items[i];
                      // Sin isAdultOption: a diferencia de ZonaCatalogoPage (que
                      // también representa la Zona +18 con `zona: null`), acá
                      // `zona` nunca es null — la Zona +18 de TV vive aparte, en
                      // Ajustes, con su propio PIN.
                      void abrir() => ExtensionUtils.openExtensionDetail(
                            context,
                            package: zi.package,
                            url: zi.item.url,
                            cover: zi.item.cover,
                            coverHeaders: zi.item.headers,
                          );
                      return FocusableCard(
                        onTap: abrir,
                        altoMarco: rejilla.ancho * 3 / 2,
                        // `builder` y no `child`: la tarjeta necesita saber si TIENE
                        // el foco ahora mismo para mostrar el panel de info (ver
                        // `TarjetaDeCatalogo.tvFoco`) — lo mismo que ya se ve al
                        // pasar el mouse en PC, pedido explícito de "replicar lo
                        // que tiene Windows a Android TV, sin duplicar el
                        // resaltado".
                        builder: (tieneFoco) => TarjetaDeCatalogo(
                          titulo: zi.item.title,
                          subtitulo: zi.item.update,
                          // Imprescindible acá: a diferencia de una fila con
                          // título propio, esta grilla mezcla varias fuentes en la
                          // misma pantalla.
                          encabezado: zi.nombre,
                          fecha: zi.item.update,
                          portada: zi.item.cover,
                          cabeceras: zi.item.headers,
                          ancho: rejilla.ancho,
                          tvFoco: tieneFoco,
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _PieDeZonaTv(
                  cargando: cargandoMas,
                  hayMas: c.puedeTraerMas,
                  seAgotoDeVerdad: c.seAgotoDeVerdad,
                ),
              ),
            ],
          );
        },
      );
    });
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
