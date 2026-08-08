part of 'home_page.dart';

// ─── El Home de escritorio ───────────────────────────────────────────────────
//
// Windows, Linux y macOS. Acá hay mouse, sobra ancho y «pasar por encima» es un
// gesto que existe, así que el diseño es otro:
//
//   · Un fondo a sangre arriba, que cambia solo cada ocho segundos. En una
//     pantalla de 1920 una tarjeta suelta en el medio se ve perdida.
//   · Filas horizontales con flechas. El ancho alcanza para seis o siete
//     portadas, y la fila se recorre con el cursor.
//   · La tarjeta abre su panel al pasarle el mouse, sin tocar nada.
//
// **Esto quedó tal cual estaba.** El rediseño de celular no lo tocó, y no es
// casualidad: acá el diseño ya está probado en uso, así que cualquier cambio es
// riesgo sin nada que ganar.

class HomeWindows extends StatelessWidget {
  const HomeWindows({super.key, required this.c});

  final CatalogoExtensionesController c;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Sin esto, el SafeArea empujaba TODO hacia abajo y quedaba una franja
      // vacía entre el borde y la imagen. En escritorio no hay barra de estado
      // igual, pero la app también corre en Android TV.
      top: false,
      child: Obx(() {
        if (c.filas.isEmpty) return const _SinExtensiones();
        // Igual que en celular: la lista se calcula UNA vez, para que
        // `itemCount` y el constructor no puedan discrepar cuando el filtro
        // acorta la lista entre una llamada y la otra.
        final visibles = () {
          final lista = c.filas
              .where((f) =>
                  f.estadoExt == EstadoExtension.activa || f.esVistaPrevia)
              .where(c.entraEnElTipo)
              .toList();

          // ── El orden NO cambia al filtrar ─────────────────────────────────
          //
          // Se probó subir las que pueden contestar el filtro. Se ve mal: al
          // aplicar, cada fila cambia de sitio y el título que estabas mirando se
          // reemplaza por el de otra extensión — parece que la app se barajó sola.
          //
          // Y ya no hace falta. Antes las que no tenían el filtro mostraban una
          // línea de disculpa, y dejarlas arriba era media pantalla vacía; ahora
          // todas traen contenido —filtrado si pueden, lo último si no, y el
          // encabezado lo dice— así que ninguna posición está desperdiciada.
          //
          // El orden se queda como está: por lo que más usás. Cada fila cambia su
          // contenido en su lugar, con los bloques grises mientras llega.

          return lista;
        }();
        return RefreshIndicator(
          onRefresh: () async {
            if (c.hayCambiosSinAplicar) {
              await c.aplicarFiltros();
              return;
            }
            await c.refrescarTodo();
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 36),
            // +2: el fondo grande de arriba y la barra de filtros.
            itemCount: visibles.length + 2,
            // **Acá está la carga perezosa.** ListView.builder solo construye
            // lo que está cerca de la pantalla, y cada fila pide en su
            // initState — así, con 30 extensiones se piden las 2 o 3 que se
            // ven, no las 30.
            itemBuilder: (context, i) => switch (i) {
              0 => _CarruselWindows(c: c),
              // Los mismos filtros que en celular. El widget vive en el
              // archivo de Android pero los tres son `part` de la misma
              // biblioteca, así que se reusa tal cual en vez de escribir otro
              // que se desincronice a la primera.
              1 => _BarraDeFiltros(c: c),
              _ => i - 2 < visibles.length
                  ? _FilaWindows(
                      key: ValueKey(visibles[i - 2].package),
                      c: c,
                      fila: visibles[i - 2],
                    )
                  : const SizedBox.shrink(),
            },
          ),
        );
      }),
    );
  }
}

/// El fondo grande de arriba, que va cambiando solo.
///
/// Se alimenta de lo que van trayendo las extensiones, así que empieza vacío y
/// se llena al toque. **No se reserva su alto cuando no hay nada**: un hueco
/// negro de media pantalla al abrir se ve peor que empezar directo por las
/// filas.
class _CarruselWindows extends StatefulWidget {
  const _CarruselWindows({required this.c});

  final CatalogoExtensionesController c;

  @override
  State<_CarruselWindows> createState() => _CarruselWindowsState();
}

class _CarruselWindowsState extends State<_CarruselWindows> {
  Timer? _reloj;

  // La posición NO se guarda acá: vive en el controlador. Este widget se
  // reconstruye al volver a la pestaña, así que un índice propio se perdía y el
  // carrusel volvía a empezar siempre por la misma extensión. Ver
  // CatalogoExtensionesController.carruselExt.

  @override
  void initState() {
    super.initState();
    // Ocho segundos: menos alcanza a cortar la lectura del título, y más se
    // siente una imagen fija.
    _reloj = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      setState(widget.c.avanzarCarrusel);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final grupos = widget.c.destacados;
      if (grupos.isEmpty) return const SizedBox(height: 12);
      final (package, items) = grupos[widget.c.carruselExt % grupos.length];
      if (items.isEmpty) return const SizedBox(height: 12);
      final item = items[widget.c.carruselPos % items.length];
      final a = Ancho.de(context);

      // Lo que ocupa la barra de estado. En escritorio es cero.
      final barra = MediaQuery.paddingOf(context).top;
      // El alto sale del ANCHO disponible, no de la altura: en una ventana
      // ancha y baja —una laptop, o el escritorio a media pantalla— reservar
      // un porcentaje del alto dejaba el carrusel aplastado. Y se acota al
      // alto real para que no se coma la pantalla entera.
      //
      // Se le SUMA la barra: la imagen crece para pasar por detrás de ella en
      // vez de perder esa franja, así el carrusel se sigue viendo del mismo
      // tamaño que si la barra no existiera.
      final alto = (MediaQuery.sizeOf(context).width *
                  a.elegir(
                      compacto: 0.62, medio: 0.42, amplio: 0.30, enorme: 0.24))
              .clamp(200.0, MediaQuery.sizeOf(context).height * 0.62) +
          barra;

      return SizedBox(
        height: alto,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── La imagen se DESVANECE, no se tapa ────────────────────────
            //
            // Antes el borde de abajo se cubría con un degradado que terminaba
            // en el color de fondo, opaco. Eso dejaba una línea horizontal
            // visible cruzando toda la pantalla: arriba de esa línea el
            // degradado tapaba el fondo animado y abajo no, así que el brillo
            // aparecía de golpe.
            //
            // Con una máscara, lo que se apaga es la propia imagen: su
            // transparencia baja a cero hacia abajo y lo que hay detrás —el
            // fondo animado— se ve igual a los dos lados del borde. No hay
            // línea porque no hay borde.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0.0, 0.55, 1.0],
              ).createShader(rect),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // El cruce entre imágenes va por la clave: al cambiar el
                  // índice, AnimatedSwitcher entiende que es otro hijo y hace
                  // el fundido.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    child: SizedBox.expand(
                      key: ValueKey(item.url),
                      child: CacheNetWorkImagePic(
                        item.cover ?? '',
                        fit: BoxFit.cover,
                        headers: _cabeceras(package),
                        placeholder:
                            const ColoredBox(color: HomeTheme.cardSurface),
                        fallback:
                            const ColoredBox(color: HomeTheme.cardSurface),
                      ),
                    ),
                  ),
                  // Oscurece hacia abajo y hacia la izquierda para que el
                  // texto se lea sobre cualquier portada. Los dos son
                  // TRANSLÚCIDOS: si alguno terminara en un color opaco,
                  // volvería la línea que este bloque vino a sacar.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xD90A0A12), Color(0x000A0A12)],
                        stops: [0.0, 0.72],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xE60A0A12), Color(0x000A0A12)],
                        stops: [0.0, 0.7],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    _margen(context), barra, _margen(context), 26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ExtensionUtils.runtimes[package]?.extension.name ?? '',
                        style: const TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: HomeTheme.accentPink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:
                              a.elegir(compacto: 21, medio: 26, amplio: 34),
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _Indicadores(
                        cantidad: items.length,
                        actual: widget.c.carruselPos % items.length,
                        onTocar: (i) =>
                            setState(() => widget.c.carruselPos = i),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _abrir(context, item, package),
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: Text('home.view-detail'.i18n),
                        style: FilledButton.styleFrom(
                          backgroundColor: HomeTheme.accentPink,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: a.elegir(compacto: 18, amplio: 22),
                            vertical: a.elegir(compacto: 12, amplio: 14),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Una fila: el nombre de la extensión y lo último que tiene, en horizontal.
class _FilaWindows extends StatefulWidget {
  const _FilaWindows({
    super.key,
    required this.c,
    required this.fila,
  });

  final CatalogoExtensionesController c;
  final FilaDeExtension fila;

  @override
  State<_FilaWindows> createState() => _FilaWindowsState();
}

class _FilaWindowsState extends State<_FilaWindows> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // **Acá se dispara la carga perezosa.** Este initState corre recién cuando
    // ListView.builder construye la fila, o sea cuando está por entrar en
    // pantalla. Lo que nunca se ve, nunca se pide.
    widget.c.pedirSiHaceFalta(widget.fila);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Desplaza la fila una pantalla, sin pasarse de los extremos.
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
        padding: const EdgeInsets.only(top: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _encabezado(),
            const SizedBox(height: 14),
            SizedBox(
              // Aire de más para la sombra.
              //
              // La tarjeta crece y se le dibuja una sombra al pasar el mouse, y
              // las dos cosas se salen de su caja. Con el alto justo, la fila
              // recortaba contra su borde y la sombra aparecía cortada en
              // línea recta — se veía peor que no tenerla.
              height: TarjetaDeCatalogo.altoTotalPara(Ancho.de(context)) + 28,
              // Bloques grises con la forma de las tarjetas, igual que en
              // celular: dicen QUÉ va a aparecer y dónde, así que al llegar el
              // contenido nada se mueve. Y salen también con contenido en
              // pantalla cuando hay un filtro en curso — lo que se ve es del
              // filtro anterior, y dejarlo quieto haría creer que no pasó
              // nada.
              child: (estado == EstadoDeFila.cargando &&
                      (items.isEmpty || widget.c.aplicandoFiltros.value))
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding:
                          EdgeInsets.symmetric(horizontal: _margen(context)),
                      itemCount: 6,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: EsqueletoTarjeta(
                          ancho: TarjetaDeCatalogo.anchoPara(Ancho.de(context)),
                        ),
                      ),
                    )
                  // ── Recorte solo a los costados ────────────────────
                  //
                  // `Clip.none` está para que la sombra del hover no se corte,
                  // pero también deja que las tarjetas se dibujen FUERA de la
                  // fila: al desplazarse, la que sale asomaba por el borde
                  // izquierdo y quedaba pintada encima del margen y hasta
                  // debajo de la barra lateral.
                  //
                  // Este recorte devuelve un rectángulo más alto que la fila:
                  // corta a izquierda y derecha —donde molesta— y deja pasar
                  // arriba y abajo, que es por donde sale la sombra.
                  : ClipRect(
                      clipper: const _SoloCostados(),
                      child: ListView.separated(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        // Sin esto el recorte se come la sombra igual, por más
                        // aire que se le dé: un ListView recorta en su borde
                        // por defecto.
                        clipBehavior: Clip.none,
                        padding:
                            EdgeInsets.symmetric(horizontal: _margen(context)),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return Padding(
                            // Arriba, para que la tarjeta tenga hacia dónde
                            // crecer sin pisar el título de la fila.
                            padding: const EdgeInsets.only(top: 10),
                            child: TarjetaDeCatalogo(
                              titulo: item.title,
                              portada: item.cover,
                              cabeceras: _cabeceras(widget.fila.package),
                              encabezado: widget.fila.nombre,
                              // `update` es lo único con forma de fecha que
                              // devuelve `latest()`. Cada extensión lo escribe a
                              // su manera —«hace 2 días», «Ep 12», una fecha— así
                              // que se muestra TAL CUAL: normalizarlo acá sería
                              // inventar una precisión que el dato no tiene.
                              fecha: item.update,
                              onTap: () =>
                                  _abrir(context, item, widget.fila.package),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _encabezado() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _margen(context)),
      child: Row(
        children: [
          Expanded(
            // El nombre y, debajo, qué está mostrando. Sin eso, dos filas
            // iguales con títulos distintos no dicen por qué son distintas.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fila.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Ancho.de(context)
                        .elegir(compacto: 17, medio: 19, amplio: 22),
                    fontWeight: FontWeight.w800,
                    color: HomeTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  switch (widget.c.modoDe(widget.fila)) {
                    ModoDeFila.popular => 'home.modo-popular'.i18n,
                    ModoDeFila.filtrado => 'home.modo-filtrado'.i18n,
                    ModoDeFila.reciente => 'home.modo-reciente'.i18n,
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: HomeTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Flechas para recorrer la fila.
          //
          // El botón de actualizar se sacó: la fila ya se refresca sola cuando
          // vence el caché y tirando de la pantalla hacia abajo. Un ícono más
          // en cada encabezado era ruido repetido diecisiete veces.
          _FlechaDeFila(
              icono: Icons.chevron_left_rounded, onTap: () => _correr(-1)),
          const SizedBox(width: 4),
          _FlechaDeFila(
              icono: Icons.chevron_right_rounded, onTap: () => _correr(1)),
        ],
      ),
    );
  }
}

/// Una flecha para recorrer una fila.
///
/// Discreta hasta que se la toca: sobre un fondo de portadas, un botón con
/// relleno propio compite con las tarjetas. Se enciende al pasar el mouse, que
/// es cuando el usuario la está buscando. Por eso vive acá y no en las piezas
/// compartidas: sin mouse, no tiene sentido.
class _FlechaDeFila extends StatefulWidget {
  const _FlechaDeFila({required this.icono, required this.onTap});

  final IconData icono;
  final VoidCallback onTap;

  @override
  State<_FlechaDeFila> createState() => _FlechaDeFilaState();
}

class _FlechaDeFilaState extends State<_FlechaDeFila> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _encima
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Icon(
            widget.icono,
            size: 20,
            color: _encima ? Colors.white : HomeTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Recorta a izquierda y derecha, y deja pasar arriba y abajo.
///
/// Para las filas horizontales: hay que cortar lo que se sale por los
/// costados —si no, las tarjetas se dibujan sobre el margen y sobre la barra
/// lateral— pero NO lo que se sale por arriba y por abajo, que es la sombra de
/// la tarjeta cuando se le pasa el mouse.
class _SoloCostados extends CustomClipper<Rect> {
  const _SoloCostados();

  /// Cuánto se deja escapar arriba y abajo. Con la sombra actual sobra.
  static const _aire = 60.0;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -_aire, size.width, size.height + _aire);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
