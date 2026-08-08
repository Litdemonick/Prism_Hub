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

  /// Las filas que corresponden al tipo elegido.
  ///
  /// El tipo se resuelve ACÁ y no pidiéndole nada a nadie: `extension.type` ya
  /// está cargado para las diecisiete. Elegir «solo mangas» es no dibujar las
  /// que no lo son, y eso es instantáneo.
  ///
  /// El género es otra cosa: ese sí hay que preguntárselo al sitio, y por eso
  /// espera a que el usuario actualice.
  List<FilaDeExtension> _visibles(CatalogoExtensionesController c) =>
      c.filas.where(c.entraEnElTipo).toList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Arriba no: la cabecera se encarga sola de la barra de estado, y así
      // el fondo con brillo pasa por detrás del reloj en vez de cortarse en
      // una franja negra.
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
          // ── Deslizar aplica los filtros ────────────────────────────────
          //
          // Y no solo refresca. El aviso de arriba dice «deslizá hacia abajo
          // para aplicar», y hasta acá el gesto llamaba a `refrescarTodo`,
          // que vuelve a pedir lo mismo de antes: el usuario marcaba un
          // género, deslizaba, y no cambiaba nada.
          //
          // Sin cambios pendientes se comporta como siempre.
          onRefresh: () async {
            if (c.hayCambiosSinAplicar) {
              await c.aplicarFiltros();
              return;
            }
            await c.refrescarTodo();
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            // Lo que ocupa la barra flotante, que con `extendBody` llega acá
            // como relleno del MediaQuery, más aire.
            // `padding.bottom` ya viene siendo el alto exacto de la barra
            // flotante, cortesía de `extendBody`. Solo se le suma un poco de
            // aire: más que eso es un hueco negro al final que obliga a
            // desplazarse de gusto.
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 10),
            // +3: la cabecera, los filtros y el carrusel.
            itemCount: _visibles(c).length + 3,
            // **Acá está la carga perezosa.** ListView.builder solo construye
            // lo que está cerca de la pantalla, y cada fila pide en su
            // initState — así, con 30 extensiones se piden las 2 o 3 que se
            // ven, no las 30.
            itemBuilder: (context, i) => switch (i) {
              // Se desplaza con el resto, no queda fija: en un teléfono una
              // barra clavada arriba se come una franja de pantalla para
              // siempre, y acá lo que importa es la portada.
              0 => const _Cabecera(),
              1 => _BarraDeFiltros(c: c),
              2 => _CarruselAndroid(c: c),
              // RepaintBoundary por fila: sin esto, cualquier repintado
              // —el fondo animado, una portada que termina de cargar— vuelve a
              // pintar TODA la lista visible. Con la capa propia, cada fila se
              // guarda rasterizada y solo se rehace la que cambió.
              _ => RepaintBoundary(
                  child: _FilaAndroid(
                    key: ValueKey(_visibles(c)[i - 3].package),
                    c: c,
                    fila: _visibles(c)[i - 3],
                  ),
                ),
            },
          ),
        );
      }),
    );
  }
}

/// Los filtros del Home: por tipo y por género.
///
/// ── Por qué no se aplican al tocar ────────────────────────────────────────
///
/// Porque aplicar un género significa volver a pedirle contenido a once
/// sitios. Tocando tres chips seguidos serían tres tandas de once pedidos, y
/// las dos primeras se tiran a la basura antes de llegar.
///
/// Entonces el toque solo MARCA. Cuando el usuario terminó de elegir, tira de
/// la pantalla hacia abajo y ahí se pide todo, una vez. Mientras haya algo
/// marcado sin aplicar, aparece un aviso que lo dice — un filtro elegido que
/// no cambió nada en pantalla se lee como que la app no funciona.
class _BarraDeFiltros extends StatefulWidget {
  const _BarraDeFiltros({required this.c});

  final CatalogoExtensionesController c;

  @override
  State<_BarraDeFiltros> createState() => _BarraDeFiltrosState();
}

class _BarraDeFiltrosState extends State<_BarraDeFiltros> {
  @override
  void initState() {
    super.initState();
    // Los géneros se leen una vez por sesión, y recién cuando el Home ya está
    // en pantalla: `createFilter()` corre JavaScript en el motor de cada
    // extensión, y hacerlo durante el arranque sería sumarle tiempo justo al
    // momento en que menos sobra.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.c.cargarGeneros();
    });
  }

  @override
  Widget build(BuildContext context) {
    final margen = _margen(context);
    return Obx(() {
      final c = widget.c;
      final generos = c.generosDisponibles;
      final hayAlgo = c.tipoElegido.value != null || c.generoElegido.value != null;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: margen),
              child: Row(
                children: [
                  for (final t in _tipos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        texto: t.$2.i18n,
                        marcado: c.tipoElegido.value == t.$1,
                        // Volver a tocar el mismo lo apaga: sin eso, una vez
                        // elegido un tipo no habría forma de volver a «todos»
                        // salvo con Restablecer.
                        onTap: () => c.tipoElegido.value =
                            c.tipoElegido.value == t.$1 ? null : t.$1,
                      ),
                    ),
                  if (generos.isNotEmpty) ...[
                    Container(
                      width: 1,
                      height: 22,
                      margin: const EdgeInsets.only(right: 8),
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    for (final g in generos)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Chip(
                          texto: g,
                          marcado: c.generoElegido.value == g,
                          onTap: () => c.generoElegido.value =
                              c.generoElegido.value == g ? null : g,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (c.hayCambiosSinAplicar || hayAlgo)
              Padding(
                padding: EdgeInsets.fromLTRB(margen, 10, margen, 0),
                child: Row(
                  children: [
                    if (c.hayCambiosSinAplicar) ...[
                      const Icon(Icons.arrow_downward_rounded,
                          size: 15, color: HomeTheme.accentPink),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'home.filtros-desliza'.i18n,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: HomeTheme.accentPink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    TextButton(
                      onPressed: c.restablecerFiltros,
                      child: Text('home.filtros-restablecer'.i18n),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }

  /// Los tipos, con el nombre que ya usa el resto de la app.
  static const _tipos = <(ExtensionType, String)>[
    (ExtensionType.bangumi, 'extension-type.video'),
    (ExtensionType.manga, 'extension-type.comic'),
    (ExtensionType.fikushon, 'extension-type.novel'),
  ];
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.texto,
    required this.marcado,
    required this.onTap,
  });

  final String texto;
  final bool marcado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.fromLTRB(marcado ? 10 : 14, 8, 14, 8),
        decoration: BoxDecoration(
          color: marcado
              ? HomeTheme.accentPink.withValues(alpha: 0.18)
              : HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: marcado
                ? HomeTheme.accentPink
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // El ganchito, no solo el color: sobre un fondo oscuro, «rosa
            // tenue» y «gris» se parecen bastante, y encima hay gente que no
            // distingue esos dos tonos. La marca tiene que ser una forma.
            if (marcado) ...[
              const Icon(Icons.check_rounded,
                  size: 16, color: HomeTheme.accentPink),
              const SizedBox(width: 5),
            ],
            Text(
              texto,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: marcado ? Colors.white : HomeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
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
        // La barra de estado más un poco de aire. Ya no la reserva nadie
        // más arriba, así que sin esto el nombre de la app se metería debajo
        // del reloj.
        MediaQuery.paddingOf(context).top + (bajo ? 2 : 6),
        // Menos a la derecha: los botones ya traen su propia zona de toque y
        // con el margen completo el ícono quedaba despegado del borde.
        margen - 8,
        // Aire entre la cabecera y la primera tarjeta. Pegados, el nombre de
        // la app se leía como si fuera parte del carrusel; separados, se ve
        // que es la cabecera de la pantalla y las portadas arrancan abajo.
        //
        // Acostado se recorta: ahí cada píxel de alto sale de las portadas.
        bajo ? 4 : 14,
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

class _CarruselAndroidState extends State<_CarruselAndroid>
    with SingleTickerProviderStateMixin {
  /// Dónde está el carrusel, en índices y con decimales.
  ///
  /// 3.0 es «la cuarta, centrada y grande»; 3.5 es «a mitad de camino entre la
  /// cuarta y la quinta, las dos del mismo tamaño». De este número salen TODOS
  /// los anchos, así que el dibujo sigue al dedo sin saltos.
  double _p = 0;
  bool _sembrado = false;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  Animation<double>? _viaje;


  /// Qué parte del ancho grande le queda a una tarjeta de los costados.
  static const _proporcionChica = 0.22;

  static const _aire = 9.0;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final v = _viaje;
      if (v == null) return;
      setState(() => _p = v.value);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
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

  void _irA(double destino, List<(String, List<ExtensionListItem>)> grupos) {
    _viaje = Tween<double>(begin: _p, end: destino)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
    // La posición guardada se actualiza YA, sin esperar a que termine el
    // viaje: si el usuario se va de la pestaña a mitad de la animación, tiene
    // que volver a donde estaba yendo, no a donde estaba.
    _ubicar(grupos, destino.round());
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final grupos = widget.c.destacados;
      final planos = grupos.isEmpty ? const <(String, ExtensionListItem)>[] : _planos(grupos);
      // Nada todavía: en vez de un hueco negro de media pantalla, las tarjetas
      // que van a venir, en gris. Así el Home ya tiene su forma desde el
      // primer cuadro y al cargar no da un salto.
      if (planos.isEmpty) return const _CarruselEsperando();

      // ── La posición guardada puede haber quedado colgada ──────────────
      //
      // `carruselPos` sobrevive a la pestaña, pero la tanda que apunta no: si
      // la extensión refresca y esta vez devuelve tres portadas en vez de
      // cinco, el índice guardado apunta a una que ya no existe.
      widget.c.carruselExt = widget.c.carruselExt % grupos.length;
      final largoTanda = grupos[widget.c.carruselExt].$2.length;
      if (widget.c.carruselPos >= largoTanda) {
        widget.c.carruselPos = largoTanda > 0 ? largoTanda - 1 : 0;
      }
      if (!_sembrado) {
        _sembrado = true;
        _p = _indiceGlobal(grupos).toDouble();
      }
      final ultimo = (planos.length - 1).toDouble();
      if (_p > ultimo) _p = ultimo;

      // El ancho sale de acá y no de MediaQuery: en horizontal ya viene sin la
      // franja que se lleva la barra del sistema.
      return LayoutBuilder(builder: (context, caja) {
        // Una caja sin ancho útil pasa en el cuadro en que la pantalla se está
        // montando o girando. Calcular sobre eso da medidas negativas, y un
        // ancho negativo no es un dibujo feo: es una excepción de layout.
        if (!caja.maxWidth.isFinite || caja.maxWidth < 120) {
          return const SizedBox(height: 12);
        }
        final m = _medir(context, caja.maxWidth);
        final tanda = grupos[widget.c.carruselExt].$2;
        final base = _indiceGlobal(grupos) - widget.c.carruselPos;

        return Column(
          children: [
            SizedBox(
              height: m.alto,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => _anim.stop(),
                onHorizontalDragUpdate: (d) {
                  final paso = (m.ancho + m.anchoChico) / 2 + _aire;
                  setState(() {
                    _p = (_p - (d.primaryDelta ?? 0) / paso)
                        .clamp(0.0, ultimo);
                  });
                },
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  // Con impulso se salta a la siguiente aunque el dedo no haya
                  // llegado a la mitad: es lo que espera un deslizar rápido.
                  var destino = _p.roundToDouble();
                  if (v.abs() > 380) {
                    destino = v < 0 ? _p.floorToDouble() + 1 : _p.ceilToDouble() - 1;
                  }
                  _irA(destino.clamp(0.0, ultimo), grupos);
                },
                child: ClipRect(child: _acordeon(planos, m, caja.maxWidth, grupos)),
              ),
            ),
            const SizedBox(height: 8),
            _Indicadores(
              cantidad: tanda.length,
              actual: widget.c.carruselPos.clamp(0, tanda.length - 1),
              onTocar: (i) => _irA((base + i).toDouble().clamp(0.0, ultimo), grupos),
            ),
          ],
        );
      });
    });
  }

  /// ── El acordeón ──────────────────────────────────────────────────────────
  ///
  /// La diferencia con un carrusel común: acá las tarjetas **no miden todas lo
  /// mismo**. La que está en foco es ancha y las de los costados son tiras
  /// finas, y al deslizar la tira se va ENSANCHANDO hasta ocupar el centro
  /// mientras la anterior se afina.
  ///
  /// Eso no se puede hacer con un PageView: sus páginas miden todas igual y
  /// solo se corren. Por eso el ancho de cada una se calcula acá, a partir de
  /// la distancia a `_p`, y se posicionan a mano.
  ///
  /// Solo se dibuja una ventana alrededor del foco —unas seis— y no las
  /// ochenta y cinco: lo que queda fuera de la pantalla no se construye.
  Widget _acordeon(
    List<(String, ExtensionListItem)> planos,
    _MedidasCarrusel m,
    double anchoUtil,
    List<(String, List<ExtensionListItem>)> grupos,
  ) {
    double anchoDe(int i) {
      final lejos = (_p - i).abs().clamp(0.0, 1.0);
      return m.anchoChico + (m.ancho - m.anchoChico) * (1 - lejos);
    }


    final foco = _p.floor();
    final desde = (foco - 2).clamp(0, planos.length - 1);
    final hasta = (foco + 3).clamp(0, planos.length - 1);

    // Dónde empieza cada una, una atrás de la otra.
    final xs = <int, double>{};
    var x = 0.0;
    for (var i = desde; i <= hasta; i++) {
      xs[i] = x;
      x += anchoDe(i) + _aire;
    }

    double centroDe(int i) => (xs[i] ?? 0) + anchoDe(i) / 2;

    // El punto que tiene que caer en el medio de la pantalla. Se interpola
    // entre el centro de la actual y el de la siguiente, así el corrimiento
    // acompaña al dedo sin escalones.
    final f = foco.clamp(desde, hasta);
    final t = _p - f;
    final centro = (f + 1 <= hasta)
        ? centroDe(f) + t * (centroDe(f + 1) - centroDe(f))
        : centroDe(f);
    final dx = anchoUtil / 2 - centro;

    return Stack(
      children: [
        for (var i = desde; i <= hasta; i++)
          Positioned(
            left: xs[i]! + dx,
            // Todas del MISMO alto. Lo que distingue a la elegida es el
            // ancho, y nada más: encogiéndolas también de alto quedaban
            // escalonadas, como si cada una estuviera a otra distancia.
            top: 0,
            width: anchoDe(i),
            height: m.alto,
            child: _TarjetaGrande(
              // ── El ancho para DECODIFICAR es fijo ──────────────────────
              //
              // Y no el ancho real de la tarjeta, que cambia en cada cuadro
              // mientras el dedo arrastra. Con el real, la imagen se volvía a
              // decodificar sesenta veces por segundo a un tamaño distinto, y
              // eso es exactamente el parpadeo: entre una decodificación y la
              // siguiente no hay nada que dibujar.
              //
              // Se pide siempre al tamaño de la grande: es el máximo al que se
              // va a ver, así que nunca queda borrosa, y como el número no
              // cambia, la imagen se decodifica UNA vez y se reusa.
              ancho: m.ancho,
              item: planos[i].$2,
              fuente: ExtensionUtils
                      .runtimes[planos[i].$1]?.extension.name ??
                  '',
              cabeceras: _cabeceras(planos[i].$1),
              // El texto solo en la que está en foco: en una tira de cincuenta
              // píxeles no entra, y recortado se lee como un error.
              conTexto: (_p - i).abs() < 0.5,
              anchoTexto: m.ancho - 28,
              onTap: () {
                // Tocar una de los costados la trae al centro; tocar la que ya
                // está en foco abre la ficha. Sin esto, para abrir la de al
                // lado había que deslizar y después tocar.
                if ((_p - i).abs() > 0.35) {
                  _irA(i.toDouble(), grupos);
                  return;
                }
                _abrir(context, planos[i].$2, planos[i].$1);
              },
            ),
          ),
      ],
    );
  }

  /// Cuánto mide la tarjeta en foco, cuánto las de los costados, y el alto.
  ///
  /// El orden importa: primero el ancho que se querría, después el alto que
  /// sale de ese ancho, y si ese alto no entra en la pantalla se recorta **y
  /// el ancho vuelve atrás con él**. Sin ese último paso, en horizontal
  /// quedaban tarjetas chatas nadando en huecos enormes.
  _MedidasCarrusel _medir(BuildContext context, double anchoUtil) {
    final altoPantalla = MediaQuery.sizeOf(context).height;
    final a = Ancho.de(context);
    final bajo = altoPantalla < 500;

    // ── La forma cambia con la orientación ─────────────────────────────
    //
    // De pie, la tarjeta es un poco más alta que ancha. Acostado no puede
    // serlo: el alto disponible es la mitad, así que mantener esa proporción
    // obliga a tarjetas angostas — y entran cuatro o cinco, chiquitas, en vez
    // de las dos grandes que se quieren ver.
    //
    // Acostado se da vuelta: más ancha que alta, y entran dos.
    final relacion = bajo ? 0.86 : 1.1; // alto respecto del ancho

    // Cuanto más ancha la pantalla, menos se lleva la tarjeta en foco: en una
    // tablet, dos tercios del ancho serían una sola tarjeta enorme.
    final parte = bajo
        ? a.elegir(compacto: 0.46, medio: 0.36, amplio: 0.3, enorme: 0.24)
        : a.elegir(compacto: 0.66, medio: 0.46, amplio: 0.36, enorme: 0.28);

    var ancho = anchoUtil * parte;
    var alto = ancho * relacion;

    // En horizontal el alto es lo escaso; en vertical, lo que sobra.
    final tope = altoPantalla * (bajo ? 0.66 : 0.4);
    if (alto > tope) {
      alto = tope;
      ancho = alto / relacion;
    }
    if (alto < 160) {
      alto = 160;
      ancho = alto / relacion;
    }
    if (ancho > anchoUtil - _aire) ancho = anchoUtil - _aire;

    return _MedidasCarrusel(
      ancho: ancho,
      anchoChico: (ancho * _proporcionChica).clamp(38.0, ancho),
      alto: alto,
    );
  }
}


class _MedidasCarrusel {
  const _MedidasCarrusel({
    required this.ancho,
    required this.anchoChico,
    required this.alto,
  });

  /// La que está en foco.
  final double ancho;

  /// Las de los costados, cuando están del todo afuera del foco.
  final double anchoChico;

  final double alto;
}

/// Una tarjeta grande del carrusel.
///
/// Portada entera, sin marco de relleno detrás: la imagen se recorta para
/// llenar la tarjeta y no queda ninguna franja de fondo. El texto va ENCIMA,
/// abajo a la izquierda, sobre un degradado translúcido — acá sí, porque la
/// tarjeta es grande y el título tiene que viajar con la imagen al deslizar.
class _TarjetaGrande extends StatelessWidget {
  const _TarjetaGrande({
    required this.ancho,
    required this.item,
    required this.fuente,
    required this.cabeceras,
    required this.onTap,
    this.conTexto = true,
    this.anchoTexto = 0,
  });

  /// Para no decodificar la portada más grande de lo que se ve. Ver el
  /// comentario largo en TarjetaDeCatalogo.
  final double ancho;
  final ExtensionListItem item;
  final String fuente;
  final Map<String, String>? cabeceras;
  final VoidCallback onTap;

  /// En las tiras de los costados no entra ni una palabra, y un título
  /// recortado a dos letras se lee como un error, no como información.
  final bool conTexto;

  /// Con qué ancho se compone el texto. Ver el comentario largo abajo.
  final double anchoTexto;

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(20);
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radio,
          color: HomeTheme.cardSurface,
          // Un filo claro apenas visible. No es adorno: sobre una portada
          // oscura, el borde de la tarjeta se funde con el fondo y no se sabe
          // dónde termina. Con esto se lee la forma sin que parezca un marco.
          border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
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
                cacheWidth: (ancho * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 4096),
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
              if (conTexto)
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                  // ── El texto tiene ancho FIJO ──────────────────────────
                  //
                  // Y no el de la tarjeta, que cambia cuadro a cuadro
                  // mientras el dedo arrastra. Con el ancho variable, el
                  // título se vuelve a repartir en líneas sesenta veces por
                  // segundo: las palabras saltan de renglón, la elipsis
                  // aparece y desaparece, y las letras se ven «temblar».
                  //
                  // Fijándolo al ancho de la tarjeta en foco, el texto se
                  // compone UNA vez. Lo que sobra queda fuera del recorte de
                  // la tarjeta, que es exactamente lo que se quiere: el
                  // título entra completo justo cuando la tarjeta termina de
                  // abrirse.
                  child: OverflowBox(
                    alignment: Alignment.bottomLeft,
                    maxWidth: anchoTexto,
                    minWidth: anchoTexto,
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
    // Hay un género aplicado y este sitio no lo tiene entre sus filtros.
    // Se dice, en una línea: mostrarla con lo último de siempre haría creer
    // que ese contenido es del género elegido, y esconderla dejaría al usuario
    // preguntándose adónde se fue su extensión.
    if (!widget.c.puedeConEsteGenero(widget.fila.package)) {
      return _FilaSinEseGenero(nombre: widget.fila.nombre);
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
      padding: EdgeInsets.symmetric(horizontal: margen),
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
          // Sin flecha. Los puntitos de abajo ya dicen que hay más y cómo
          // llegar —deslizando—, y un ícono repetido en cada extensión era la
          // misma línea diecisiete veces peleándole espacio al título.
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
        // La grilla que VIENE, en gris y brillando. Mismas medidas, mismas
        // posiciones: cuando llegan las portadas no se mueve nada.
        return SizedBox(
          height: alto,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: margen),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnas,
                mainAxisSpacing: _hueco,
                crossAxisSpacing: _hueco,
                childAspectRatio: anchoCelda / altoCelda,
              ),
              itemCount: porPagina,
              itemBuilder: (_, __) => EsqueletoTarjeta(ancho: anchoCelda),
            ),
          ),
        );
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
          // Los puntitos son lo único que avisa que hay más portadas. Sin
          // ellos, una grilla llena se lee como «esto es todo» y nadie prueba
          // deslizar.
          if (paginas > 1) ...[
            const SizedBox(height: 6),
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

/// El carrusel antes de que llegue la primera extensión.
class _CarruselEsperando extends StatelessWidget {
  const _CarruselEsperando();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      if (!caja.maxWidth.isFinite || caja.maxWidth < 120) {
        return const SizedBox(height: 12);
      }
      final a = Ancho.de(context);
      final altoPantalla = MediaQuery.sizeOf(context).height;
      final bajo = altoPantalla < 500;
      final relacion = bajo ? 0.86 : 1.1;
      final parte = bajo
          ? a.elegir(compacto: 0.46, medio: 0.36, amplio: 0.3, enorme: 0.24)
          : a.elegir(compacto: 0.66, medio: 0.46, amplio: 0.36, enorme: 0.28);
      var ancho = caja.maxWidth * parte;
      var alto = ancho * relacion;
      final tope = altoPantalla * (bajo ? 0.66 : 0.4);
      if (alto > tope) {
        alto = tope;
        ancho = alto / relacion;
      }
      return Column(
        children: [
          SizedBox(
            height: alto,
            child: ClipRect(
              child: Stack(
                children: [
                  // La grande al medio y una tira a cada lado: la misma forma
                  // que va a tener cuando cargue.
                  Positioned(
                    left: caja.maxWidth / 2 - ancho / 2,
                    width: ancho,
                    height: alto,
                    child: Esqueleto(radio: 20, width: ancho, height: alto),
                  ),
                  Positioned(
                    left: caja.maxWidth / 2 - ancho / 2 - ancho * 0.22 - 9,
                    width: ancho * 0.22,
                    height: alto,
                    child: Esqueleto(radio: 20, height: alto),
                  ),
                  Positioned(
                    left: caja.maxWidth / 2 + ancho / 2 + 9,
                    width: ancho * 0.22,
                    height: alto,
                    child: Esqueleto(radio: 20, height: alto),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      );
    });
  }
}

/// La extensión no ofrece el género que está aplicado.
class _FilaSinEseGenero extends StatelessWidget {
  const _FilaSinEseGenero({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final margen = _margen(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margen, 14, margen, 0),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_off_outlined,
              size: 16, color: HomeTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$nombre · ${'home.fila-sin-genero'.i18n}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, color: HomeTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
