part of 'home_page.dart';

// ─── El Home de celular ──────────────────────────────────────────────────────
//
// Android e iOS. Acá se toca con el pulgar, la pantalla es alta y angosta y no
// existe «pasar por encima», así que el diseño es otro:
//
//   · Arriba, el nombre de la app y sus atajos.
//   · Después, tarjetas grandes que se deslizan con el dedo, con las vecinas
//     asomando a los costados y encogidas para que se vea cuál está elegida.
//   · Y cada extensión en una grilla que se pasa de página, no en una fila.
//
// ── Lo que hay que cuidar en cada medida ────────────────────────────────────
//
// Nada se calcula sobre `MediaQuery.sizeOf(context).width` a secas. En
// horizontal, la barra de navegación del sistema se mete por un COSTADO y se
// come entre 40 y 60 píxeles del ancho: usar el ancho de pantalla ahí es un
// desborde asegurado. Todo lo ancho sale de un LayoutBuilder, que ya viene sin
// esa franja porque el SafeArea de arriba se la sacó.
//
// Y nada se calcula solo sobre el ancho tampoco. Un teléfono en horizontal es
// ANCHO Y BAJO: las mismas cuentas que en vertical dan tarjetas más altas que
// la pantalla. Por eso cada alto se recorta contra el alto real, y cuando se
// recorta, el ancho lo acompaña — si no, quedan tarjetas chatas separadas por
// huecos enormes.

class HomeAndroid extends StatelessWidget {
  const HomeAndroid({super.key, required this.c});

  final CatalogoExtensionesController c;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Arriba no: la cabecera se encarga sola de la barra de estado, y así
      // puede llevar su propio aire en vez de heredar una franja pelada.
      top: false,
      // Abajo tampoco: la barra flotante tiene que dejar ver las portadas
      // corriendo por atrás. El lugar no se pierde, se pasa al relleno de la
      // lista — así lo último se termina de ver igual, pero el fondo llega
      // hasta el borde de la pantalla.
      bottom: false,
      // Los costados SÍ. En horizontal es donde aparece la barra del sistema,
      // y es lo que evita que las tarjetas queden debajo de los botones.
      child: Obx(() {
        if (c.filas.isEmpty) return const _SinExtensiones();
        return RefreshIndicator(
          onRefresh: c.refrescarTodo,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            // Lo que ocupa la barra flotante, que con `extendBody` llega acá
            // como relleno del MediaQuery, más aire.
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 28),
            // +2: la cabecera y el carrusel.
            itemCount: c.filas.length + 2,
            // **Acá está la carga perezosa.** ListView.builder solo construye
            // lo que está cerca de la pantalla, y cada fila pide en su
            // initState — así, con 30 extensiones se piden las 2 o 3 que se
            // ven, no las 30.
            itemBuilder: (context, i) => switch (i) {
              // Se desplaza con el resto, no queda fija: en un teléfono una
              // barra clavada arriba se come una franja de pantalla para
              // siempre, y acá lo que importa es la portada.
              0 => const _Cabecera(),
              1 => _CarruselAndroid(c: c),
              _ => _FilaAndroid(
                  key: ValueKey(c.filas[i - 2].package),
                  c: c,
                  fila: c.filas[i - 2],
                ),
            },
          ),
        );
      }),
    );
  }
}

/// El nombre de la app y sus atajos, arriba de todo.
///
/// Solo en celular. En escritorio esto ya está en la barra lateral, que está
/// siempre a la vista, así que repetirlo sería gastar alto de pantalla en algo
/// que el usuario ya tiene enfrente.
///
/// Ajustes también está en los tres puntos de abajo, sí. No es redundancia
/// gratis: esa barra es para MOVERSE por la app y estos son atajos a lo que se
/// toca de paso — la misma división que hace cualquier app de streaming.
class _Cabecera extends StatelessWidget {
  const _Cabecera();

  void _ajustes() {
    if (!Get.isRegistered<MainController>()) return;
    Get.find<MainController>().changeTab(MainController.tabAjustes);
  }

  void _historial() => Get.to(() => const HistoryPage());

  @override
  Widget build(BuildContext context) {
    final margen = _margen(context);
    // En horizontal el alto es lo que escasea: la cabecera se achica para no
    // robarle sitio a las portadas, que son a lo que se vino.
    final bajo = MediaQuery.sizeOf(context).height < 500;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        margen,
        // La barra de estado. Acá se respeta entera: es lo primero que se
        // dibuja y no hay ninguna imagen que gane con pasar por detrás.
        MediaQuery.paddingOf(context).top + (bajo ? 2 : 8),
        // Menos a la derecha: los botones ya traen su propia zona de toque y
        // con el margen completo el ícono quedaba despegado del borde.
        margen - 8,
        bajo ? 0 : 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'PrismHub',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: bajo ? 21 : 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: Colors.white,
              ),
            ),
          ),
          _BotonDeCabecera(
            icono: Icons.history_rounded,
            etiqueta: 'common.history'.i18n,
            onTap: _historial,
          ),
          _BotonDeCabecera(
            icono: Icons.settings_outlined,
            etiqueta: 'common.settings'.i18n,
            onTap: _ajustes,
          ),
        ],
      ),
    );
  }
}

class _BotonDeCabecera extends StatelessWidget {
  const _BotonDeCabecera({
    required this.icono,
    required this.etiqueta,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: etiqueta,
      icon: Icon(icono, size: 23, color: HomeTheme.textPrimary),
      // 44 es el mínimo para tocar con el pulgar sin errarle.
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      splashRadius: 22,
    );
  }
}

/// Las tarjetas grandes de arriba, que se deslizan con el dedo.
///
/// ── Por qué asoman las vecinas ────────────────────────────────────────────
///
/// Porque es lo único que dice que hay más. Una portada sola a pantalla
/// completa **no se lee como algo que se pueda mover**: parece una imagen de
/// cabecera y nadie la desliza nunca.
///
/// ── Por qué no rota sola ──────────────────────────────────────────────────
///
/// Porque acá el dedo está encima. Cambiar la tarjeta mientras alguien la está
/// leyendo se la corre de abajo del pulgar, y si justo la estaba arrastrando,
/// pelea con el gesto. En escritorio sí rota: ahí el cursor está en otro lado.
class _CarruselAndroid extends StatefulWidget {
  const _CarruselAndroid({required this.c});

  final CatalogoExtensionesController c;

  @override
  State<_CarruselAndroid> createState() => _CarruselAndroidState();
}

class _CarruselAndroidState extends State<_CarruselAndroid> {
  PageController? _paginas;
  double? _fraccion;

  // La posición NO se guarda acá: vive en el controlador. Este widget se
  // reconstruye al volver a la pestaña, así que un índice propio se perdía y
  // el carrusel volvía a empezar siempre por la misma extensión. Ver
  // CatalogoExtensionesController.carruselExt.

  @override
  void dispose() {
    _paginas?.dispose();
    super.dispose();
  }

  /// Todas las tandas, una atrás de otra, sin costura.
  ///
  /// El carrusel de celular **no es de una extensión**: es de todas. Al pasar
  /// la última de FuegoCine sigue la primera de la que venga después, sin
  /// tener que esperar nada.
  ///
  /// La lista solo CRECE POR EL FINAL —cada extensión que contesta se agrega
  /// al final de `destacados`— así que un índice que el usuario ya está
  /// mirando nunca se le corre bajo los pies.
  List<(String, ExtensionListItem)> _planos(
      List<(String, List<ExtensionListItem>)> grupos) {
    final todo = <(String, ExtensionListItem)>[];
    for (final (package, items) in grupos) {
      for (final item in items) {
        todo.add((package, item));
      }
    }
    return todo;
  }

  /// De (extensión, posición) al índice en la lista plana.
  int _indiceGlobal(List<(String, List<ExtensionListItem>)> grupos) {
    final ext = widget.c.carruselExt % grupos.length;
    var i = 0;
    for (var g = 0; g < ext; g++) {
      i += grupos[g].$2.length;
    }
    return i + widget.c.carruselPos;
  }

  /// Del índice en la lista plana de vuelta a (extensión, posición).
  void _ubicar(List<(String, List<ExtensionListItem>)> grupos, int indice) {
    var resto = indice;
    for (var g = 0; g < grupos.length; g++) {
      final largo = grupos[g].$2.length;
      if (resto < largo) {
        widget.c.carruselExt = g;
        widget.c.carruselPos = resto;
        return;
      }
      resto -= largo;
    }
  }

  /// El controlador del PageView, atado a la fracción de ancho que ocupa cada
  /// tarjeta.
  ///
  /// Se rehace si esa fracción cambia —girar el teléfono, sobre todo— porque
  /// `viewportFraction` es de solo lectura una vez creado. El viejo se tira
  /// DESPUÉS del cuadro: soltarlo en pleno build lo destruiría mientras su
  /// PageView todavía está montado.
  PageController _controlador(double fraccion, int inicial) {
    if (_paginas == null || _fraccion != fraccion) {
      final viejo = _paginas;
      if (viejo != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => viejo.dispose());
      }
      _fraccion = fraccion;
      _paginas = PageController(
        viewportFraction: fraccion,
        initialPage: inicial,
      );
    }
    return _paginas!;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final grupos = widget.c.destacados;
      if (grupos.isEmpty) return const SizedBox(height: 12);
      final planos = _planos(grupos);
      if (planos.isEmpty) return const SizedBox(height: 12);

      // ── La posición guardada puede haber quedado colgada ──────────────
      //
      // `carruselPos` sobrevive a la pestaña, pero la tanda que apunta no:
      // si la extensión refresca y esta vez devuelve tres portadas en vez de
      // cinco, el índice guardado apunta a una que ya no existe. Se acomoda
      // ANTES de calcular nada, porque de ahí sale la página inicial del
      // PageView y una página fuera de rango deja el carrusel en blanco.
      widget.c.carruselExt = widget.c.carruselExt % grupos.length;
      final largoTanda = grupos[widget.c.carruselExt].$2.length;
      if (widget.c.carruselPos >= largoTanda) {
        widget.c.carruselPos = largoTanda > 0 ? largoTanda - 1 : 0;
      }

      // El ancho sale de acá y no de MediaQuery: en horizontal ya viene sin la
      // franja que se lleva la barra del sistema.
      return LayoutBuilder(builder: (context, caja) {
        // Una caja sin ancho útil pasa en el cuadro en que la pantalla se está
        // montando o girando. Calcular sobre eso da medidas negativas, y un
        // ancho negativo no es un dibujo feo: es una excepción de layout.
        if (!caja.maxWidth.isFinite || caja.maxWidth < 120) {
          return const SizedBox(height: 12);
        }
        final medidas = _medir(context, caja.maxWidth);
        final ctrl = _controlador(medidas.fraccion, _indiceGlobal(grupos));

        // La tanda de la extensión que se está mirando, para los puntitos: con
        // la lista entera serían ochenta y cinco rayitas y no dirían nada. Así
        // dicen «la tercera de las cinco de esta extensión», que sí se
        // entiende.
        final tanda = grupos[widget.c.carruselExt % grupos.length].$2;
        final base = _indiceGlobal(grupos) - widget.c.carruselPos;

        return Column(
          children: [
            SizedBox(
              // El alto de la tarjeta grande. Las vecinas se encogen DENTRO de
              // este alto, así que la franja no cambia de tamaño al deslizar y
              // nada de lo de abajo se mueve.
              height: medidas.alto,
              child: PageView.builder(
                controller: ctrl,
                itemCount: planos.length,
                // Sin esto la sombra de la tarjeta se corta contra el borde.
                clipBehavior: Clip.none,
                onPageChanged: (i) {
                  if (!mounted) return;
                  setState(() => _ubicar(grupos, i));
                },
                itemBuilder: (context, i) {
                  final (package, item) = planos[i];
                  return _conFoco(
                    ctrl,
                    i,
                    Center(
                      child: SizedBox(
                        // Puede ser más angosta que su casillero: cuando el
                        // alto de la pantalla obliga a achicar la tarjeta, el
                        // ancho la sigue para no deformar la portada.
                        width: medidas.ancho,
                        // El alto va explícito. Center afloja las
                        // restricciones, y sin alto el Stack de la tarjeta
                        // queda sin límite y tumba el layout.
                        height: medidas.alto,
                        child: _TarjetaGrande(
                          item: item,
                          fuente: ExtensionUtils
                                  .runtimes[package]?.extension.name ??
                              '',
                          cabeceras: _cabeceras(package),
                          onTap: () => _abrir(context, item, package),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _Indicadores(
              cantidad: tanda.length,
              actual: widget.c.carruselPos.clamp(0, tanda.length - 1),
              onTocar: (i) => _saltarA(base + i),
            ),
          ],
        );
      });
    });
  }

  /// Salta a una tarjeta desde los puntitos.
  ///
  /// `animateToPage` revienta si el controlador todavía no tiene su PageView
  /// enganchado — pasa si se toca un puntito en el mismo cuadro en que la
  /// pantalla se está armando.
  void _saltarA(int indice) {
    final p = _paginas;
    if (p == null || !p.hasClients) return;
    p.animateToPage(
      indice,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  /// ── La del medio grande, las de los costados chicas ──────────────────────
  ///
  /// No es adorno: es lo que dice CUÁL está elegida. Con todas del mismo alto,
  /// las de los costados se leen como tarjetas cortadas por el borde de la
  /// pantalla; encogidas se leen como «la que sigue», y las de más allá como
  /// una pila que se va hacia el fondo.
  ///
  /// Se encoge solo el ALTO, no el ancho, para que no se abran huecos entre
  /// una tarjeta y la otra.
  ///
  /// Y se mueve únicamente con el dedo: `ctrl.page` es la posición real del
  /// gesto, así que el tamaño acompaña al arrastre y se queda quieto en cuanto
  /// el usuario suelta.
  Widget _conFoco(PageController ctrl, int i, Widget hijo) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, quieto) {
        final pagina = ctrl.hasClients && ctrl.position.haveDimensions
            ? (ctrl.page ?? i.toDouble())
            : ctrl.initialPage.toDouble();
        final lejos = (pagina - i).abs().clamp(0.0, 2.0);
        return Transform.scale(scaleY: 1 - 0.05 * lejos, child: quieto);
      },
      child: hijo,
    );
  }

  /// Cuánto mide cada tarjeta y qué parte del ancho ocupa su casillero.
  ///
  /// El orden importa: primero el ancho que se querría, después el alto que
  /// sale de ese ancho, y si ese alto no entra en la pantalla se recorta **y
  /// el ancho vuelve atrás con él**. Sin ese último paso, en horizontal
  /// quedaban tarjetas chatas nadando en casilleros enormes.
  _MedidasCarrusel _medir(BuildContext context, double anchoUtil) {
    const aire = 14.0; // lo que separa una tarjeta de la otra
    const relacion = 1.18; // alto respecto del ancho
    final altoPantalla = MediaQuery.sizeOf(context).height;
    final a = Ancho.de(context);

    // Cuanto más ancha la pantalla, más chica la fracción: en una tablet, dos
    // tercios del ancho serían una sola tarjeta enorme.
    final fraccionIdeal =
        a.elegir(compacto: 0.66, medio: 0.44, amplio: 0.34, enorme: 0.26);

    var ancho = anchoUtil * fraccionIdeal - aire;
    var alto = ancho * relacion;

    // En horizontal el alto es lo escaso; en vertical, lo que sobra.
    final tope = altoPantalla * (altoPantalla < 500 ? 0.62 : 0.46);
    if (alto > tope) {
      alto = tope;
      ancho = alto / relacion;
    }
    if (alto < 160) {
      alto = 160;
      ancho = alto / relacion;
    }
    // Nunca más ancha que el lugar que hay: con una sola extensión y pantalla
    // muy angosta, la cuenta de arriba podía pasarse.
    if (ancho > anchoUtil - aire) ancho = anchoUtil - aire;

    return _MedidasCarrusel(
      ancho: ancho,
      alto: alto,
      fraccion: ((ancho + aire) / anchoUtil).clamp(0.2, 1.0),
    );
  }
}

class _MedidasCarrusel {
  const _MedidasCarrusel({
    required this.ancho,
    required this.alto,
    required this.fraccion,
  });

  final double ancho;
  final double alto;
  final double fraccion;
}

/// Una tarjeta grande del carrusel.
///
/// Portada entera, sin marco de relleno detrás: la imagen se recorta para
/// llenar la tarjeta y no queda ninguna franja de fondo. El texto va ENCIMA,
/// abajo a la izquierda, sobre un degradado translúcido — acá sí, porque la
/// tarjeta es grande y el título tiene que viajar con la imagen al deslizar.
class _TarjetaGrande extends StatelessWidget {
  const _TarjetaGrande({
    required this.item,
    required this.fuente,
    required this.cabeceras,
    required this.onTap,
  });

  final ExtensionListItem item;
  final String fuente;
  final Map<String, String>? cabeceras;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(20);
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radio,
          color: HomeTheme.cardSurface,
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CacheNetWorkImagePic(
                item.cover ?? '',
                fit: BoxFit.cover,
                headers: cabeceras,
                placeholder: const ColoredBox(color: HomeTheme.cardSurface),
                fallback: const ColoredBox(color: HomeTheme.cardSurface),
              ),
              // Translúcido de punta a punta: si terminara en un color opaco
              // cortaría la portada con una línea recta.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xE6000000), Color(0x00000000)],
                    stops: [0.0, 0.6],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fuente,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: HomeTheme.textMuted,
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
  }
}

/// Una extensión: su nombre y sus portadas en grilla.
class _FilaAndroid extends StatefulWidget {
  const _FilaAndroid({
    super.key,
    required this.c,
    required this.fila,
  });

  final CatalogoExtensionesController c;
  final FilaDeExtension fila;

  @override
  State<_FilaAndroid> createState() => _FilaAndroidState();
}

class _FilaAndroidState extends State<_FilaAndroid> {
  @override
  void initState() {
    super.initState();
    // **Acá se dispara la carga perezosa.** Este initState corre recién cuando
    // ListView.builder construye la fila, o sea cuando está por entrar en
    // pantalla. Lo que nunca se ve, nunca se pide.
    widget.c.pedirSiHaceFalta(widget.fila);
  }

  @override
  Widget build(BuildContext context) {
    // Apagada o sin instalar: no hay contenido que traer, así que en vez de una
    // fila vacía va una línea con lo que hay que hacer para que traiga algo.
    if (widget.fila.estadoExt != EstadoExtension.activa) {
      return _FilaInactiva(fila: widget.fila, c: widget.c);
    }
    return Obx(() {
      final estado = widget.fila.estado.value;
      final items = widget.fila.items;

      // Ni cargando ni con contenido: no se dibuja NADA, ni siquiera el
      // título. Una fila con nombre y vacía debajo se lee como un error.
      if (estado == EstadoDeFila.fallo && items.isEmpty) {
        return _SinRespuesta(fila: widget.fila, c: widget.c);
      }

      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _encabezado(),
            const SizedBox(height: 10),
            _GrillaPaginada(
              items: items,
              cargando: items.isEmpty && estado == EstadoDeFila.cargando,
              package: widget.fila.package,
            ),
          ],
        ),
      );
    });
  }

  Widget _encabezado() {
    final margen = _margen(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margen, 0, margen - 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.fila.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Ancho.de(context).elegir(compacto: 18, medio: 20),
                fontWeight: FontWeight.w800,
                color: HomeTheme.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          // La grilla ya se pasa con el dedo, así que la flecha no sirve para
          // recorrer: sirve para SALIR de las pocas que caben y abrir la
          // extensión entera, con su búsqueda y sus filtros.
          IconButton(
            onPressed: () => _verTodo(widget.fila.package),
            tooltip: widget.fila.nombre,
            icon: const Icon(Icons.arrow_forward_rounded,
                size: 21, color: HomeTheme.accentPink),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

/// Las portadas de una extensión, en grilla que se pasa de página.
///
/// ── Por qué páginas y no una fila que se arrastra ─────────────────────────
///
/// Porque una fila horizontal en una pantalla angosta muestra dos tarjetas y
/// media y esconde el resto detrás de un gesto que no se ve. La grilla usa el
/// ancho completo, entra el triple de portadas de un vistazo, y los puntitos
/// de abajo dicen cuánto más hay — que es justo lo que la fila no podía decir.
///
/// ── Por qué páginas y no scroll vertical ──────────────────────────────────
///
/// El Home ya se desplaza hacia abajo para pasar de una extensión a otra. Si
/// cada extensión además creciera hacia abajo con todas sus portadas, llegar a
/// la segunda costaría media docena de gestos y las de más abajo no las vería
/// nadie. Paginando, **cada extensión ocupa siempre lo mismo** y el orden
/// vertical del Home se mantiene legible.
///
/// El tope de páginas es a propósito: esto es una vidriera, no un catálogo.
/// Para ver todo está la flecha del encabezado.
class _GrillaPaginada extends StatefulWidget {
  const _GrillaPaginada({
    required this.items,
    required this.cargando,
    required this.package,
  });

  final List<ExtensionListItem> items;
  final bool cargando;
  final String package;

  @override
  State<_GrillaPaginada> createState() => _GrillaPaginadaState();
}

class _GrillaPaginadaState extends State<_GrillaPaginada> {
  static const _maxPaginas = 3;
  static const _hueco = 12.0;

  final _paginas = PageController();
  int _actual = 0;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Ancho.de(context);
    final margen = _margen(context);
    final columnas = a.elegir(compacto: 3, medio: 4, amplio: 5, enorme: 6);
    // **Una sola fila en horizontal.** Dos filas de portadas 2:3 miden más que
    // la pantalla de un teléfono acostado: la segunda quedaba siempre cortada
    // y había que desplazarse para ver media tarjeta.
    final filas = MediaQuery.sizeOf(context).height < 500 ? 1 : 2;
    final porPagina = columnas * filas;

    // De la caja y no de MediaQuery: en horizontal el ancho de pantalla
    // incluye la franja de la barra del sistema y la grilla se desbordaba.
    return LayoutBuilder(builder: (context, caja) {
      if (!caja.maxWidth.isFinite || caja.maxWidth < 120) {
        return const SizedBox(height: 12);
      }
      final anchoCelda =
          (caja.maxWidth - margen * 2 - _hueco * (columnas - 1)) / columnas;
      final altoCelda = TarjetaDeCatalogo.altoTotalDeAncho(anchoCelda);
      final alto = altoCelda * filas + _hueco * (filas - 1);

      if (widget.cargando) {
        return SizedBox(
            height: alto, child: const Center(child: ProgressRing()));
      }

      var paginas = (widget.items.length + porPagina - 1) ~/ porPagina;
      if (paginas < 1) paginas = 1;
      if (paginas > _maxPaginas) paginas = _maxPaginas;
      // Girar el teléfono cambia cuántas entran por página, así que la página
      // en la que estaba el usuario puede dejar de existir. Sin esto el
      // PageView se queda apuntando a una página que ya no está y muestra un
      // hueco en blanco.
      if (_actual >= paginas) {
        _actual = paginas - 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _paginas.hasClients) _paginas.jumpToPage(_actual);
        });
      }
      // Nada de páginas a medio llenar más allá del tope: se corta la lista.
      final visibles = widget.items.length < paginas * porPagina
          ? widget.items.length
          : paginas * porPagina;

      return Column(
        children: [
          SizedBox(
            height: alto,
            child: PageView.builder(
              controller: _paginas,
              itemCount: paginas,
              onPageChanged: (i) => setState(() => _actual = i),
              itemBuilder: (context, pagina) {
                final desde = pagina * porPagina;
                final hasta =
                    desde + porPagina < visibles ? desde + porPagina : visibles;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: margen),
                  child: GridView.builder(
                    // La página no se desplaza sola: el gesto es del PageView.
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columnas,
                      mainAxisSpacing: _hueco,
                      crossAxisSpacing: _hueco,
                      // La celda mide EXACTO lo que mide la tarjeta: si no
                      // coincidieran, o sobra un hueco o el título se recorta.
                      childAspectRatio: anchoCelda / altoCelda,
                    ),
                    itemCount: hasta - desde,
                    itemBuilder: (context, i) {
                      final item = widget.items[desde + i];
                      return TarjetaDeCatalogo(
                        ancho: anchoCelda,
                        titulo: item.title,
                        portada: item.cover,
                        cabeceras: _cabeceras(widget.package),
                        // Sin panel a propósito. En una celda de tres columnas
                        // el panel de detalle tapa la portada entera y el texto
                        // no entra; y con panel el primer toque lo abre en vez
                        // de abrir la ficha, o sea dos toques para lo mismo.
                        // Acá tocar abre la ficha, que muestra todo completo.
                        onTap: () => _abrir(context, item, widget.package),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (paginas > 1) ...[
            const SizedBox(height: 4),
            _Indicadores(
              cantidad: paginas,
              actual: _actual,
              onTocar: (i) {
                if (!_paginas.hasClients) return;
                _paginas.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                );
              },
            ),
          ],
        ],
      );
    });
  }
}
