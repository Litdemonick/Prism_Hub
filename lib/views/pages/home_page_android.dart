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

  /// Las filas que se dibujan: solo las que pueden traer contenido y que
  /// entran en el tipo elegido.
  ///
  /// ── Por qué se van las apagadas y las no instaladas ─────────────────────
  ///
  /// Estaban a propósito, con su botón de «Activar» o «Instalar»: la idea era
  /// que nadie se perdiera una extensión por no saber que existía.
  ///
  /// En la práctica no funciona. Con una sola extensión andando, el Home queda
  /// con una portada arriba y DIECISÉIS renglones de botones debajo — se lee
  /// como una lista de tareas pendientes, no como una pantalla para descubrir
  /// algo. Y el lugar para prender o instalar ya existe, es la zona de
  /// Extensiones, que está a un toque en la barra.
  ///
  /// El tipo se resuelve ACÁ y no pidiéndole nada a nadie: `extension.type` ya
  /// está cargado para las diecisiete. Elegir «solo mangas» es no dibujar las
  /// que no lo son, y eso es instantáneo. El género es otra cosa: ese sí hay
  /// que preguntárselo al sitio, y por eso espera a que el usuario actualice.
  List<FilaDeExtension> _visibles(CatalogoExtensionesController c) {
    final lista = c.filas
        // Las de vista previa también: no están encendidas —por eso son vista
        // previa— pero sí traen contenido, que es lo único que el Home pide.
        .where((f) => f.estadoExt == EstadoExtension.activa || f.esVistaPrevia)
        .where(c.entraEnElTipo)
        .toList();

    // ── Con filtro puesto, las que lo tienen van arriba ────────────────
    //
    // Esto se sacó una vez porque al aplicar cambiaba el título que el usuario
    // estaba mirando. Vuelve, pero ahora el reordenamiento pasa EN EL MISMO
    // INSTANTE en que todas las filas pasan a bloques grises —`aplicarFiltros`
    // avisa antes de pedir nada— así que no se ve un título reemplazando a
    // otro sobre contenido: se ve la lista acomodándose para el filtro, y
    // recién después se llena.
    //
    // Y hace falta: sin esto, marcar «Isekai» dejaba arriba las extensiones
    // que no lo tienen, y había que bajar hasta el final para encontrar las que
    // sí. El orden es estable —entre las que pueden se respeta el de siempre,
    // el del historial— así que no baila entre cargas.
    if (c.hayFiltros) {
      lista.sort((a, b) {
        final pa = c.puedeConEsteGenero(a.package) ? 0 : 1;
        final pb = c.puedeConEsteGenero(b.package) ? 0 : 1;
        return pa - pb;
      });
    }
    return lista;
  }

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
        // ── Vacío no siempre es «no hay nada» ──────────────────────────
        //
        // Al abrir, la lista tarda un instante en armarse —y sin conexión, lo
        // de la vista previa tarda más—. Mostrar «no tenés extensiones» en ese
        // hueco es decirle al usuario algo que todavía no se sabe, y encima
        // suena a que perdió lo que tenía.
        //
        // Los bloques grises dicen lo correcto: esperá. El mensaje aparece
        // recién cuando de verdad terminó de mirar y no hay ninguna.
        if (c.filas.isEmpty) {
          return c.armado.value
              ? const _SinExtensiones()
              : const _HomeEsperando();
        }
        // ── Se calcula UNA vez por construcción ──────────────────────────
        //
        // Antes `_visibles(c)` se llamaba de nuevo en cada línea que lo
        // necesitaba: una para `itemCount` y otra por cada ítem. Son listas
        // recién filtradas, y entre una llamada y la siguiente el filtro puede
        // haber cambiado —al aplicar un tipo, la lista se acorta— así que
        // `itemCount` decía diez y el constructor encontraba dos:
        //
        //   RangeError (length): Invalid value: Not in inclusive range 0..1: 2
        //
        // Con la lista capturada acá, las dos cuentas salen del mismo dato.
        final visibles = _visibles(c);
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
            // ── Sin filas visibles, bloques grises: NUNCA el hueco ──────
            //
            // `visibles` puede quedar vacío aunque `filas` no lo esté: al
            // arrancar, entre que se leen las extensiones, su estado de
            // encendido y los filtros guardados, hay cuadros en los que ninguna
            // pasa el filtro. Ahí el Home dibujaba el acordeón, la barra de
            // filtros y NADA debajo, y las extensiones aparecían de golpe unos
            // segundos después. Reportado en Windows, con captura.
            //
            // En vez de seguir persiguiendo cada motivo por el que la lista
            // puede quedar corta un instante, se cubre el caso entero: si no
            // hay ninguna que mostrar, van dos filas en gris. Cuando llegan las
            // de verdad, ocupan su lugar sin que nada aparezca de la nada.
            //
            // El aviso de «no tenés extensiones» no se pierde: ese sale antes,
            // arriba, y solo cuando `armado` dice que de verdad no hay ninguna.
            // +3: la cabecera, los filtros y el carrusel.
            itemCount: (visibles.isEmpty ? 2 : visibles.length) + 3,
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
              // El acordeón en su propia capa: mide, calcula y dibuja seis
              // tarjetas grandes. Sin esto, cualquier repintado de la lista
              // —una fila que termina de cargar más abajo— lo arrastra a
              // repintarse entero aunque no haya cambiado nada suyo.
              2 => RepaintBoundary(child: _CarruselAndroid(c: c)),
              // RepaintBoundary por fila: sin esto, cualquier repintado
              // —el fondo animado, una portada que termina de cargar— vuelve a
              // pintar TODA la lista visible. Con la capa propia, cada fila se
              // guarda rasterizada y solo se rehace la que cambió.
              // El índice se vuelve a comprobar igual: entre que el
              // ListView pidió su `itemCount` y que llama acá puede haber
              // pasado un cuadro, y una lista más corta no puede tumbar la
              // pantalla entera por una fila de más.
              _ => visibles.isEmpty
                  ? const _FilaEsperando()
                  : (i - 3 < visibles.length
                      ? RepaintBoundary(
                          child: _FilaAndroid(
                            key: ValueKey(visibles[i - 3].package),
                            c: c,
                            fila: visibles[i - 3],
                          ),
                        )
                      : const SizedBox.shrink()),
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
  /// Para las flechas de escritorio. En celular no se usa: ahí la fila se
  /// arrastra con el dedo.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Los filtros que están marcados, con su texto y cómo apagarlos.
  ///
  /// Se devuelven en el mismo orden que los grupos de la barra —estado,
  /// formato, género— para que al marcar dos no bailen entre sí.
  List<(String, String, VoidCallback)> _marcados(
      CatalogoExtensionesController c) {
    final lista = <(String, String, VoidCallback)>[];
    final e = c.estadoElegido.value;
    if (e != null) {
      lista.add((e, 'home.estado.$e'.i18n, () => c.estadoElegido.value = null));
    }
    final f = c.formatoElegido.value;
    if (f != null) {
      lista.add(
          (f, 'home.formato.$f'.i18n, () => c.formatoElegido.value = null));
    }
    final g = c.generoElegido.value;
    if (g != null) {
      lista.add((g, 'home.genero.$g'.i18n, () => c.generoElegido.value = null));
    }
    return lista;
  }

  /// Corre la fila de chips la mayor parte de su ancho.
  void _correr(int signo) {
    if (!_scroll.hasClients) return;
    final salto = _scroll.position.viewportDimension * 0.8;
    _scroll.animateTo(
      (_scroll.offset + salto * signo)
          .clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

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
      final hayAlgo =
          c.tipoElegido.value != null || c.generoElegido.value != null;

      // ── El alto de la barra NUNCA cambia ──────────────────────────────
      //
      // Los géneros se leen en segundo plano, después de que carguen las
      // filas. Antes, mientras tanto, la barra medía seis píxeles y al llegar
      // saltaba a su tamaño completo empujando el carrusel y todas las filas
      // hacia abajo — el usuario ya estaba mirando algo y se le movía solo.
      //
      // Ahora ocupa siempre lo mismo y lo que cambia es el contenido:
      // primero bloques grises con forma de chip, después los chips de
      // verdad. Igual que las tarjetas.
      final cargandoChips = generos.isEmpty &&
          c.estadosDisponibles.isEmpty &&
          c.formatosDisponibles.isEmpty;

      // ── Reintentar mientras no haya nada ────────────────────────────────
      //
      // El primer intento sale al montar la barra, y puede volver con las manos
      // vacías: la cola de pedidos todavía llena, una extensión que no
      // contestó, sin red. Antes eso dejaba los chips sin aparecer en toda la
      // sesión.
      //
      // Este build corre cada vez que algo del catálogo cambia —una fila que
      // termina de cargar, por ejemplo—, así que sirve de reintento natural sin
      // necesidad de un reloj. Y `cargarGeneros` se protege sola de correr dos
      // veces a la vez, así que llamarla de más no cuesta nada.
      if (cargandoChips) unawaited(c.cargarGeneros());

      // Se calcula UNA vez: se consultaba cuatro veces por construcción y cada
      // una armaba su propia lista. Misma clase de error que `_visibles`, y
      // acá además puede discrepar entre una lectura y la siguiente.
      final marcados = _marcados(c);

      return Padding(
        // Despegada del título: pegada arriba, la barra se leía como parte de
        // la cabecera y no como algo que se puede tocar.
        padding: const EdgeInsets.only(top: 14, bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Solo géneros ──────────────────────────────────────────
            //
            // Los chips de tipo —Vídeo, Manga, Novela— se sacaron: en el Home
            // cada fila YA lleva el nombre de su extensión, y con eso el
            // usuario sabe de sobra si está mirando anime o manga. Ocupaban la
            // primera pantalla de la barra empujando los géneros, que son los
            // que de verdad sirven para encontrar algo.
            if (cargandoChips)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: margen),
                  itemCount: 7,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  // Anchos distintos: siete cápsulas idénticas se leen como un
                  // patrón, no como chips que están por aparecer.
                  itemBuilder: (_, i) => Esqueleto(
                    radio: 20,
                    width: 78.0 + (i % 3) * 26,
                    height: 38,
                  ),
                ),
              )
            else
              Row(
                children: [
                  // Flechas solo en escritorio: en una pantalla táctil la fila
                  // se arrastra con el dedo y las flechas solo taparían chips.
                  if (!_esTactil) SizedBox(width: margen - 8),
                  if (!_esTactil)
                    _FlechaDeFila(
                        icono: Icons.chevron_left_rounded,
                        onTap: () => _correr(-1)),
                  // ── Los activos, FIJOS a la izquierda ─────────────────
                  //
                  // Fuera del área que se desplaza: así el filtro puesto se ve
                  // siempre, aunque el usuario se haya ido al final de los
                  // cuarenta y cuatro géneros buscando otro. Antes iba adentro y
                  // se perdía de vista al primer arrastre.
                  //
                  // Flexible y con su propio desplazamiento: con tres activos en
                  // un teléfono angosto, si no, se comerían la barra entera.
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _esTactil ? null : _scroll,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.only(
                          left: _esTactil ? margen : 6,
                          right: _esTactil ? margen : 6),
                      child: Row(
                        children: [
                          // ── Los activos, primeros y en la MISMA fila ──────
                          //
                          // Antes iban en un grupo aparte, fijo a la izquierda
                          // y fuera del área que se desplaza. La idea era que
                          // el filtro puesto se viera siempre, pero ese grupo
                          // se llevaba hasta un tercio del ancho y se lo quitaba
                          // a los demás: al marcar uno, la fila de chips
                          // terminaba trescientos píxeles antes y parecía que
                          // todo se hubiera achicado. Reportado en las tres
                          // plataformas, con capturas.
                          //
                          // Acá adentro no le quita ancho a nadie: la fila
                          // ocupa lo mismo marcada que sin marcar. Y siguen
                          // siendo lo primero que se ve, así que en la práctica
                          // se ven igual —recién marcado nadie está desplazado
                          // al final de los cuarenta y cuatro géneros—.
                          for (final m in marcados)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _Chip(
                                  texto: m.$2, marcado: true, onTap: m.$3),
                            ),
                          if (marcados.isNotEmpty) _separadorDeChips,
                          // ── Lo elegido, al principio de todo ──────────────────
                          //
                          // Con cuarenta y cuatro géneros, el chip marcado podía
                          // quedar a tres pantallazos de distancia: el usuario filtra
                          // y después no ve por qué filtró. Adelante y con su ganchito
                          // se lee de un vistazo, y se apaga tocándolo sin buscarlo.
                          // El estado va primero: son dos chips y acotan mucho más que
                          // un género —«algo terminado, para maratonear» es de las
                          // primeras cosas que alguien busca—.
                          for (final e in c.estadosDisponibles)
                            if (c.estadoElegido.value != e)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _Chip(
                                  texto: 'home.estado.$e'.i18n,
                                  marcado: c.estadoElegido.value == e,
                                  onTap: () => c.estadoElegido.value =
                                      c.estadoElegido.value == e ? null : e,
                                ),
                              ),
                          if (c.estadosDisponibles.isNotEmpty &&
                              c.formatosDisponibles.isNotEmpty)
                            _separadorDeChips,
                          // El formato después del estado y antes del género: son
                          // pocos y acotan mucho —«una película», «un manhwa»— así
                          // que van donde se ven sin desplazar.
                          for (final f in c.formatosDisponibles)
                            if (c.formatoElegido.value != f)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _Chip(
                                  texto: 'home.formato.$f'.i18n,
                                  marcado: c.formatoElegido.value == f,
                                  onTap: () => c.formatoElegido.value =
                                      c.formatoElegido.value == f ? null : f,
                                ),
                              ),
                          if ((c.estadosDisponibles.isNotEmpty ||
                                  c.formatosDisponibles.isNotEmpty) &&
                              generos.isNotEmpty)
                            _separadorDeChips,
                          for (final g in generos)
                            if (c.generoElegido.value != g)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _Chip(
                                  // El chip muestra la traducción; lo que se guarda y se
                                  // compara es el identificador.
                                  texto: 'home.genero.$g'.i18n,
                                  marcado: c.generoElegido.value == g,
                                  // Volver a tocar el mismo lo apaga: sin eso, una vez
                                  // elegido un género no habría forma de volver a
                                  // «todos» salvo con Restablecer.
                                  onTap: () => c.generoElegido.value =
                                      c.generoElegido.value == g ? null : g,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  if (!_esTactil) ...[
                    _FlechaDeFila(
                        icono: Icons.chevron_right_rounded,
                        onTap: () => _correr(1)),
                    SizedBox(width: margen - 8),
                  ],
                ],
              ),
            // ── El alto está SIEMPRE reservado ────────────────────────
            //
            // Antes esta línea aparecía al marcar un chip y desaparecía al
            // aplicar. Cada vez, todo lo de abajo —el carrusel y las filas
            // enteras— saltaba cuarenta píxeles. Con el alto fijo solo cambia
            // lo que hay adentro, y nada se mueve.
            SizedBox(
              height: 44,
              // ── En escritorio la fila está SIEMPRE ────────────────────
              //
              // Acá vive el botón de refrescar, y hasta ahora la fila entera
              // solo aparecía si había un filtro puesto o marcado. O sea que
              // el botón se escondía justo en el caso normal: sin ningún
              // filtro, que es cuando alguien instala una extensión y quiere
              // verla en el Home. Quedaba otra vez sin forma de actualizar que
              // no fuera cerrar la app.
              //
              // En celular no hace falta: ahí se tira de la pantalla y el
              // gesto está siempre disponible, así que la fila sigue
              // apareciendo solo cuando tiene algo que decir.
              child: (c.hayCambiosSinAplicar || hayAlgo || !_esTactil)
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(margen, 10, margen, 0),
                      child: Row(
                        children: [
                          // ── Cómo se aplica, según el aparato ──────────────
                          //
                          // En celular se desliza hacia abajo, que es el gesto que
                          // ya existe para refrescar. En escritorio ese gesto no
                          // existe —nadie tira de una ventana con el mouse— así que
                          // ahí va un botón, que es lo que se busca.
                          if (c.hayCambiosSinAplicar && _esTactil) ...[
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
                          if (hayAlgo || c.hayFiltros)
                            TextButton(
                              onPressed: c.restablecerFiltros,
                              child: Text('home.filtros-restablecer'.i18n),
                            ),
                          // En escritorio no hay «tirar para refrescar»: el gesto
                          // no existe con mouse. Sin esto, la única forma de poner el
                          // Home al día —o de que aparezca una extensión recién
                          // instalada— era cerrar y volver a abrir la app.
                          if (!_esTactil) ...[
                            const SizedBox(width: 8),
                            _BotonDeBarra(
                              // Mientras trabaja cambia de ícono y no se deja
                              // tocar: sin eso, el botón no daba ninguna señal
                              // de que estuviera pasando algo y la gente lo
                              // tocaba tres veces seguidas.
                              icono: c.refrescando.value
                                  ? Icons.hourglass_top_rounded
                                  : Icons.refresh_rounded,
                              etiqueta: 'home.refrescar'.i18n,
                              onTap:
                                  c.refrescando.value ? null : c.refrescarTodo,
                            ),
                          ],
                          if (!_esTactil && c.hayCambiosSinAplicar) ...[
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: c.aplicarFiltros,
                              icon: const Icon(Icons.filter_alt_rounded,
                                  size: 18),
                              label: Text('home.filtros-aplicar'.i18n),
                              style: FilledButton.styleFrom(
                                backgroundColor: HomeTheme.accentPink,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    });
  }
}

/// La rayita que separa un grupo de chips del siguiente.
const _separadorDeChips = Padding(
  padding: EdgeInsets.only(right: 8),
  child: SizedBox(
    width: 1,
    height: 22,
    child: ColoredBox(color: Color(0x24FFFFFF)),
  ),
);

/// Un botón discreto de la barra de filtros, solo con su ícono.
class _BotonDeBarra extends StatelessWidget {
  const _BotonDeBarra({
    required this.icono,
    required this.etiqueta,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: etiqueta,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icono, size: 20, color: HomeTheme.textMuted),
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        splashRadius: 19,
      ),
    );
  }
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
        // ── Ni el ancho ni la posición del texto cambian al marcarlo ──────
        //
        // Van tres intentos con esto, así que vale explicar por qué los dos
        // anteriores no alcanzaban:
        //
        //   1. Achicar el relleno izquierdo para hacerle sitio al ganchito.
        //      El chip CRECÍA al tocarlo y empujaba a los de la derecha.
        //   2. Reservar el hueco del ganchito siempre, dentro de la fila.
        //      El ancho ya no cambiaba, pero el texto quedaba corrido a la
        //      derecha en los que NO estaban marcados — el hueco vacío lo
        //      empujaba igual.
        //
        // Lo que funciona: relleno **parejo a los dos lados** y el ganchito
        // fuera del flujo, dibujado encima. El texto está centrado siempre,
        // el chip mide lo mismo en los dos estados, y nada se mueve.
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: marcado ? Colors.white : HomeTheme.textMuted,
              ),
            ),
            // El ganchito, no solo el color: sobre un fondo oscuro, «rosa
            // tenue» y «gris» se parecen bastante, y hay gente que no
            // distingue esos dos tonos. La marca tiene que ser una forma.
            //
            // Va como capa y con desplazamiento negativo: se mete en el relleno
            // de 24 que ya está reservado, sin ocupar lugar en el flujo.
            if (marcado)
              const Positioned(
                left: -19,
                child: Icon(Icons.check_rounded,
                    size: 15, color: HomeTheme.accentPink),
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

  /// El último aviso de «volvé al principio» que se atendió. Ver `reinicios`.
  int _reinicioVisto = 0;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  Animation<double>? _viaje;

  /// Qué parte del ancho grande le queda a una tarjeta de los costados.
  ///
  /// ── Por qué cambia con el tamaño de la pantalla ─────────────────────────
  ///
  /// En un teléfono, 0.22 es lo que hace que se vea UNA grande con dos tiras
  /// asomando: la forma que se buscaba desde el principio.
  ///
  /// En un monitor ancho ese mismo número da tiras de cien píxeles, y entonces
  /// entran trece a lo ancho. Deja de leerse como «una elegida con sus vecinas»
  /// y pasa a ser una pared de portadas: cargado y sin foco. Medido en vivo con
  /// la ventana maximizada.
  ///
  /// Con tiras más anchas entran las mismas siete que en el teléfono, ocupando
  /// todo el ancho. La grande sigue destacando —más del doble que una tira— y
  /// el acordeón se lee igual de ordenado que en Android, que es de donde salió.
  static double _proporcionChicaDe(Ancho a) =>
      a.elegir(compacto: 0.22, medio: 0.32, amplio: 0.42);

  /// Cuántas rayitas como mucho, por larga que sea la tanda.
  static const _maxPuntitos = 8;

  static const _aire = 9.0;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      // Tocar otra zona mientras el acordeón se está acomodando desmonta este
      // widget con la animación en curso. Sin esta guarda, el oyente llama a
      // setState sobre algo que ya no está.
      if (!mounted) return;
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
  /// La firma de la lista la última vez que se acomodó la posición.
  int _firmaVista = -1;

  /// ── El ancla es la TARJETA, no un número ────────────────────────────────
  ///
  /// `_p` es una posición en la lista aplanada, y esa lista CRECE por el medio:
  /// cuando `traerMas` le suma ocho portadas a una extensión, todo lo que viene
  /// después se corre ocho lugares. El mismo `_p` pasa a apuntar a otra
  /// tarjeta.
  ///
  /// La version anterior recalculaba `_p` desde (extension, posicion). Eso
  /// arreglaba el caso simple, pero perdia la FRACCION del gesto —el usuario
  /// estaba a mitad de camino entre dos tarjetas y quedaba clavado en una— asi
  /// que habia que esperar a que soltara. Y ahi aparecia el otro problema: al
  /// soltar, la animacion arrancaba hacia un destino calculado con los indices
  /// VIEJOS, terminaba en el lugar equivocado, y recien despues se corregia.
  /// Eso es el «va para atras, para adelante, y despues se acomoda».
  ///
  /// Guardando qué tarjeta se está mirando, encontrarla de nuevo en la lista
  /// nueva es exacto: se le suma la misma fracción y el dibujo no cambia ni un
  /// píxel. Al ser invisible, se puede hacer EN CUALQUIER MOMENTO —incluso con
  /// el dedo en la pantalla— y desaparece toda la maquinaria de postergarlo.
  String? _anclaPaquete;
  String? _anclaUrl;

  /// Cuánto se pasó de la última tarjeta real, si está entre las que esperan.
  ///
  /// Entre los fantasmas no hay tarjeta que anclar —todavía no existen— así que
  /// el ancla es la última REAL y esto guarda la distancia hasta ella. Ver
  /// `_recordarAncla`.
  double _sobrante = 0;

  /// Cuántas tarjetas en espera se dibujan después de la última real.
  ///
  /// ── Por qué existen ─────────────────────────────────────────────────────
  ///
  /// Sin ellas el acordeón termina en seco: se desliza, se choca contra una
  /// pared invisible y nada dice si viene más o si eso es todo. Con internet
  /// lento la pared aparece mucho antes de que llegue la página siguiente, y se
  /// siente como que la app se colgó.
  ///
  /// Tres brillando dicen «viene más» sin escribirlo, y de paso dan lugar para
  /// seguir deslizando mientras se pide. Cuando el contenido llega, se
  /// reemplazan por las tarjetas de verdad EN EL MISMO SITIO: no hay salto.
  ///
  /// Cero cuando ya no queda nada por traer: prometer contenido que no va a
  /// venir es peor que mostrar el final.
  static const _maxFantasmas = 3;

  /// A qué tarjeta va la animación en curso. Ver `_corregirViajeEnCurso`.
  double _destino = 0;

  /// Barata y suficiente: cambia si cambió la cantidad de extensiones o la de
  /// portadas de alguna.
  static int _firmaDe(List<(String, List<ExtensionListItem>)> grupos) {
    var f = grupos.length;
    for (final g in grupos) {
      f = f * 31 + g.$2.length;
    }
    return f;
  }

  /// El resultado de la última vez, para no rearmarlo en cada cuadro.
  List<(String, ExtensionListItem)>? _planosCache;
  int _firmaDeLosGrupos = -1;

  List<(String, ExtensionListItem)> _planos(
      List<(String, List<ExtensionListItem>)> grupos) {
    // ── Se rearma solo cuando cambió algo ──────────────────────────────
    //
    // Este método se llama desde `build`, y `build` corre en CADA cuadro del
    // arrastre —el gesto hace setState para mover el acordeón—. Con ocho
    // portadas por extensión eso ya eran noventa allocations por cuadro; al
    // permitir pedir más páginas, pueden ser dos mil. Sesenta veces por
    // segundo, mientras el dedo está en la pantalla.
    //
    // La firma es barata de calcular y alcanza: si cambió la cantidad de
    // extensiones o la de portadas de alguna, se rearma; si no, se reusa.
    final firma = _firmaDe(grupos);
    final guardado = _planosCache;
    if (guardado != null && firma == _firmaDeLosGrupos) return guardado;

    // ── Sin repetidos, por si acaso ────────────────────────────────────
    //
    // Cada tanda ya se arma sin duplicados, pero algunos sitios devuelven los
    // mismos títulos en dos páginas distintas y basta con que uno se cuele para
    // que el usuario vea el mismo anime dos veces al deslizar. Red de seguridad
    // barata: un conjunto de direcciones ya vistas.
    // ── Una de cada extensión, por turnos ──────────────────────────────
    //
    // Antes se recorría extensión por extensión: las cuarenta de FuegoCine, y
    // recién después las de AnimeFenix. Con eso el acordeón SIEMPRE empezaba con
    // la misma —había que deslizar cuarenta tarjetas para ver otra— y las
    // últimas extensiones no aparecían nunca.
    //
    // Por turnos, las primeras tarjetas son lo más nuevo de ocho extensiones
    // distintas. Se ve de entrada todo lo que hay abajo, una de cada una, y
    // recién cuando se agota la primera vuelta empieza la segunda. Las que
    // tienen menos portadas se acaban antes y las demás siguen: no queda hueco.
    final todo = <(String, ExtensionListItem)>[];
    final vistas = <String>{};
    final masLarga =
        grupos.fold<int>(0, (m, g) => g.$2.length > m ? g.$2.length : m);
    for (var vuelta = 0; vuelta < masLarga; vuelta++) {
      for (final (package, items) in grupos) {
        if (vuelta >= items.length) continue;
        final item = items[vuelta];
        // La misma dirección en DOS extensiones distintas sí es otro ítem, así
        // que la clave lleva el paquete.
        if (!vistas.add('$package|${item.url}')) continue;
        todo.add((package, item));
      }
    }
    _firmaDeLosGrupos = firma;
    _planosCache = todo;
    return todo;
  }

  /// De (extensión, posición) al índice en la lista plana.
  ///
  /// ── Se busca, no se calcula ─────────────────────────────────────────────
  ///
  /// Antes se sumaban los largos de los grupos anteriores, y eso solo servía
  /// mientras la lista fuera extensión por extensión. Ahora va por turnos —una
  /// de cada una— así que ese cálculo daría cualquier cosa.
  ///
  /// Buscando en la lista ya aplanada no hay dos maneras de contar que puedan
  /// discrepar: la posición sale de la misma lista que se dibuja. Es un recorrido
  /// de unos cientos de elementos y solo corre cuando se pierde el ancla, no en
  /// cada cuadro.
  int _indiceGlobal(List<(String, List<ExtensionListItem>)> grupos) {
    final planos = _planosCache;
    if (planos == null || planos.isEmpty || grupos.isEmpty) return 0;
    final ext = widget.c.carruselExt % grupos.length;
    final (paquete, items) = grupos[ext];
    if (items.isEmpty) return 0;
    final pos = widget.c.carruselPos.clamp(0, items.length - 1);
    final url = items[pos].url;
    final i = planos.indexWhere((e) => e.$1 == paquete && e.$2.url == url);
    return i >= 0 ? i : 0;
  }

  /// Del índice en la lista plana de vuelta a (extensión, posición).
  void _ubicar(List<(String, List<ExtensionListItem>)> grupos, int indice) {
    final planos = _planosCache;
    if (planos == null || indice < 0 || indice >= planos.length) return;
    final (paquete, item) = planos[indice];
    for (var g = 0; g < grupos.length; g++) {
      if (grupos[g].$1 != paquete) continue;
      final pos = grupos[g].$2.indexWhere((e) => e.url == item.url);
      if (pos < 0) return;
      widget.c.carruselExt = g;
      widget.c.carruselPos = pos;
      return;
    }
  }

  /// Vuelve a poner `_p` sobre la MISMA tarjeta después de que la lista cambió.
  ///
  /// Se conserva la parte decimal: si el usuario estaba a un tercio de camino
  /// hacia la siguiente, sigue a un tercio. Por eso no se ve nada.
  void _reubicarPorAncla(
    List<(String, ExtensionListItem)> planos,
    List<(String, List<ExtensionListItem>)> grupos,
  ) {
    final pkg = _anclaPaquete;
    final url = _anclaUrl;
    if (pkg == null || url == null) return;

    // Entre los fantasmas el «resto» no es la fracción sino la distancia hasta
    // la última real, que puede ser mayor que uno. En los dos casos es lo que
    // hay que volver a sumarle al ancla.
    final fraccion = _sobrante > 0 ? _sobrante : _p - _p.floorToDouble();
    final i = planos.indexWhere((e) => e.$1 == pkg && e.$2.url == url);
    if (i >= 0) {
      final antes = _p;
      _p = i + fraccion;
      _corregirViajeEnCurso(_p - antes);
      return;
    }
    // La tarjeta ya no está —cambió el filtro, o la extensión devolvió otra
    // cosa—. Ahí se cae a la posición guardada, que es lo mejor que hay.
    _p = _indiceGlobal(grupos)
        .toDouble()
        .clamp(0.0, (planos.length - 1).toDouble());
  }

  /// Corre la animación en curso el mismo tanto que se corrió la posición.
  ///
  /// ── El agujero que quedaba ──────────────────────────────────────────────
  ///
  /// El `Tween` de `_irA` se arma con los índices que había EN ESE MOMENTO, y
  /// su oyente escribe `_p` en cada cuadro. Así que un re-anclaje a mitad del
  /// viaje se deshacía al instante: el siguiente cuadro pisaba `_p` con un
  /// valor del espacio de índices viejo, y la tarjeta se iba a la anterior.
  ///
  /// Eso es lo que se veía como «deslizo y a veces me regresa». Pasaba solo si
  /// la lista crecía justo entre soltar y que terminara de acomodarse —una
  /// ventana de trescientos milisegundos— por eso era intermitente.
  ///
  /// Corrigiendo el viaje con el mismo desplazamiento, la animación sigue hacia
  /// la MISMA tarjeta a la que iba, y termina donde corresponde.
  void _corregirViajeEnCurso(double desplazamiento) {
    if (desplazamiento == 0 || !_anim.isAnimating) return;
    if (_viaje == null) return;
    // El valor actual ya está corregido en `_p`; lo que hay que mover es el
    // destino. Se rearma el viaje desde donde está ahora.
    _destino += desplazamiento;
    _viaje = Tween<double>(begin: _p, end: _destino)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
  }

  /// Anota qué tarjeta se está mirando, para poder encontrarla después.
  ///
  /// ── Va por el PISO, no por el redondeo ──────────────────────────────────
  ///
  /// Y tiene que ser el mismo criterio que usa `_reubicarPorAncla` para la
  /// fracción, o el ancla queda corrida.
  ///
  /// Con `_p = 5.7`: redondeando, el ancla seria la tarjeta 6, pero la fraccion
  /// que se guarda —0.7— esta medida desde la 5. Al restaurar se le sumaba 0.7
  /// al indice de la 6, o sea una tarjeta de mas. Ese era el salto: aparecia
  /// solo cuando la lista crecia con el gesto pasado de la mitad, que es
  /// justamente cuando el usuario esta deslizando.
  void _recordarAncla(List<(String, ExtensionListItem)> planos) {
    if (planos.isEmpty) return;
    final ultimoReal = planos.length - 1;
    // ── Parado entre las que esperan ──────────────────────────────────────
    //
    // Ahí no hay tarjeta que recordar. Se ancla a la última real y se guarda
    // cuánto se pasó, así al llegar contenido nuevo el usuario queda justo
    // donde estaba: al final de lo que ya había, mirando lo que acaba de
    // aparecer. Anclar al número pelado lo dejaría en cualquier lado, porque
    // las páginas nuevas se meten en el medio de la lista, no al final.
    if (_p > ultimoReal) {
      _anclaPaquete = planos[ultimoReal].$1;
      _anclaUrl = planos[ultimoReal].$2.url;
      _sobrante = _p - ultimoReal;
      return;
    }
    _sobrante = 0;
    final i = _p.floor();
    if (i < 0 || i >= planos.length) return;
    _anclaPaquete = planos[i].$1;
    _anclaUrl = planos[i].$2.url;
  }

  void _irA(double destino, List<(String, List<ExtensionListItem>)> grupos) {
    _viaje = Tween<double>(begin: _p, end: destino)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _destino = destino;
    _anim.forward(from: 0);
    // La posición guardada se actualiza YA, sin esperar a que termine el
    // viaje: si el usuario se va de la pestaña a mitad de la animación, tiene
    // que volver a donde estaba yendo, no a donde estaba.
    _ubicar(grupos, destino.round());
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final grupos = widget.c.destacadosVisibles;
      // Filtrando NO se vacía: las portadas se quedan y se reemplazan cuando
      // llega lo nuevo. Vaciarlo dejaba media pantalla en gris y después todo
      // de vuelta — dos saltos para una sola espera.
      final planos = grupos.isEmpty
          ? const <(String, ExtensionListItem)>[]
          : _planos(grupos);
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
      // ── Filtrar lleva al principio ────────────────────────────────────
      //
      // Se mira acá, dentro del Obx, para que el aviso llegue solo: no hace
      // falta que nadie llame a nada. Y se limpia el ancla, porque apunta a una
      // tarjeta que con el filtro nuevo puede no estar.
      final reinicio = widget.c.reinicios.value;
      if (reinicio != _reinicioVisto) {
        _reinicioVisto = reinicio;
        _anclaPaquete = null;
        _anclaUrl = null;
        _sobrante = 0;
        // ── Viajando, no de un salto ────────────────────────────────────
        //
        // Aparecer de golpe en la primera no se entiende: el usuario no sabe si
        // volvió al principio o si le cambiaron la lista debajo. Yendo, se ve de
        // dónde a dónde fue.
        //
        // El viaje se pide para el próximo cuadro y no acá: esto corre DENTRO de
        // `build`, y arrancar la animación en el medio de un dibujo dispara un
        // `setState` mientras Flutter todavía está dibujando.
        //
        // Si todavía no se había sembrado —o ya estaba en la primera— no hay
        // nada que animar y se siembra en cero como siempre.
        if (_sembrado && _p > 0.01) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _irA(0, widget.c.destacadosVisibles);
          });
        } else {
          _sembrado = false;
        }
      }
      if (!_sembrado) {
        _sembrado = true;
        // ── Siempre desde la primera ──────────────────────────────────
        //
        // Antes arrancaba donde el usuario había quedado la vez pasada. La
        // idea era no perderle el hilo, pero en la práctica molesta: al abrir
        // la app te dejaba en la tarjeta cuarenta de la extensión siete, sin
        // ninguna pista de por qué, y lo nuevo —que es a lo que uno viene—
        // quedaba atrás. Encima, si esa tanda había cambiado, la posición
        // guardada apuntaba a otra cosa.
        //
        // Abrir el Home es empezar de cero: la primera tarjeta de la primera
        // extensión. Moverse desde ahí cuesta un gesto.
        widget.c.carruselExt = 0;
        widget.c.carruselPos = 0;
        _p = 0;
      }
      // ── La posición se re-ancla, y NUNCA en pleno gesto ─────────────
      //
      // `_p` es un índice en la lista APLANADA. Cuando `traerMas` suma portadas
      // a una extensión, todos los índices posteriores se corren: el mismo `_p`
      // pasa a apuntar a otra tarjeta. Eso es lo que se veía como un salto
      // hacia atrás.
      //
      // La posición de verdad es (extensión, posición en la tanda), que
      // `_ubicar` mantiene al día y no se corre cuando otra extensión crece. Al
      // detectar que la lista cambió, `_p` se recalcula desde ahí.
      //
      // Pero eso corre en `build`, y `build` corre en cada cuadro del arrastre.
      // Hacerlo con el dedo en la pantalla pierde la fracción del gesto y la
      // tarjeta pega un tirón — se siente como si la app hubiera recargado
      // algo. Así que si la lista cambió mientras arrastrabas, queda anotado y
      // se acomoda al soltar, cuando ya no se nota.
      final firma = _firmaDe(grupos);
      if (firma != _firmaVista) {
        _firmaVista = firma;
        _reubicarPorAncla(planos, grupos);
      }

      // Hasta dónde se puede deslizar: las reales más las que esperan.
      final fantasmas = widget.c.puedeTraerMas ? _maxFantasmas : 0;
      final ultimoReal = (planos.length - 1).toDouble();
      final ultimo = ultimoReal + fantasmas;
      if (_p > ultimo) _p = ultimo;
      if (_p < 0) _p = 0;
      // Con la posición ya acomodada, se anota qué tarjeta es. Va en cada
      // cuadro a propósito: durante el arrastre el foco cambia todo el tiempo,
      // y el ancla tiene que seguirlo o al crecer la lista apuntaría a una
      // tarjeta que el usuario dejó atrás hace rato.
      _recordarAncla(planos);

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
                    _p = (_p - (d.primaryDelta ?? 0) / paso).clamp(0.0, ultimo);
                  });
                },
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  // Con impulso se salta a la siguiente aunque el dedo no haya
                  // llegado a la mitad: es lo que espera un deslizar rápido.
                  var destino = _p.roundToDouble();
                  if (v.abs() > 380) {
                    destino =
                        v < 0 ? _p.floorToDouble() + 1 : _p.ceilToDouble() - 1;
                  }
                  _irA(destino.clamp(0.0, ultimo), grupos);
                  // ── Traer más cuando queda poco ──────────────────────
                  //
                  // Al soltar y no en cada píxel del arrastre: así se pide una
                  // vez por gesto y no cincuenta.
                  //
                  // El margen se cuenta desde la última REAL, no desde el tope
                  // con fantasmas: si se contara desde el tope, las tres
                  // tarjetas en espera se comerían el aviso y el pedido saldría
                  // tres tarjetas más tarde, justo cuando ya se ve el final.
                  //
                  // Diez y no cinco. Con internet lento, cinco tarjetas es
                  // menos de un segundo deslizando rápido y la página no llega
                  // a tiempo; diez da margen sin pedir de más, porque igual no
                  // se dispara dos veces mientras una está en curso.
                  if (destino >= ultimoReal - 10) {
                    unawaited(widget.c.traerMas());
                  }
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      // ── Recorta a los costados, NO arriba y abajo ────────
                      //
                      // Cada tarjeta lleva una sombra desplazada ocho píxeles
                      // hacia abajo. Con un recorte rectangular común, esa
                      // sombra se corta al ras del borde inferior: se ve media
                      // sombra terminando en seco, en línea recta, debajo de
                      // cada portada. Con trece tarjetas al lado se leía como
                      // una banda sucia cruzando el carrusel.
                      //
                      // Este recorte deja escapar arriba y abajo justo para
                      // eso. Ya existía para las filas horizontales, que tienen
                      // el mismo problema con la sombra del ratón encima.
                      child: _conPuntasDifuminadas(
                        ClipRect(
                          clipper: const _SoloCostados(),
                          child: _acordeon(
                              planos, m, caja.maxWidth, grupos, fantasmas),
                        ),
                      ),
                    ),
                    // ── Flechas solo con mouse ─────────────────────────────
                    //
                    // Arrastrar con el mouse funciona —el gesto es el mismo—
                    // pero nadie lo intenta: en escritorio uno espera hacer
                    // clic. Sin flechas, en PC el acordeón parecía una imagen
                    // fija con tres portadas al lado.
                    //
                    // En pantalla táctil no van: el dedo ya arrastra, y dos
                    // botones encima taparían justo las tarjetas de los
                    // costados, que son las que invitan a deslizar.
                    // Con su propio fondo: la flecha suelta es un ícono gris
                    // claro, y acá cae encima de una portada. Sobre una imagen
                    // oscura desaparece y sobre una clara tampoco se lee. El
                    // disco la separa del fondo sea cual sea la portada.
                    if (!_esTactil) ...[
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _discoDeFlecha(
                            _FlechaDeFila(
                              icono: Icons.chevron_left_rounded,
                              onTap: () => _irA(
                                  (_p.roundToDouble() - 1).clamp(0.0, ultimo),
                                  grupos),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _discoDeFlecha(
                            _FlechaDeFila(
                              icono: Icons.chevron_right_rounded,
                              onTap: () {
                                _irA(
                                    (_p.roundToDouble() + 1).clamp(0.0, ultimo),
                                    grupos);
                                // Misma regla que al soltar el dedo: si queda
                                // poco por delante, se pide la página siguiente.
                                // Sin esto, quien navega a puro clic se choca
                                // contra el final y no pasa nada.
                                if (_p >= ultimoReal - 10) {
                                  unawaited(widget.c.traerMas());
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // En táctil la sombra sigue estando y ya no se corta, así que
            // necesita dónde caer: con ocho llegaba a los puntitos. En
            // escritorio no hay sombra, y dieciséis serían un hueco de gusto.
            SizedBox(height: _esTactil ? 16 : 8),
            // ── Los puntitos NO crecen con la tanda ────────────────────
            //
            // Antes había uno por portada, así que al pedir más páginas la
            // fila pasaba de ocho rayitas a dieciséis, a veinticuatro… hasta
            // ocupar el ancho entero y dejar de significar nada.
            //
            // Ahora son ocho como mucho y cada una representa un tramo. Sirven
            // para lo mismo —saber por dónde vas— sin volverse una regla
            // graduada.
            _Indicadores(
              cantidad:
                  tanda.length < _maxPuntitos ? tanda.length : _maxPuntitos,
              actual: tanda.length <= _maxPuntitos
                  ? widget.c.carruselPos.clamp(0, tanda.length - 1)
                  : (widget.c.carruselPos * _maxPuntitos ~/ tanda.length)
                      .clamp(0, _maxPuntitos - 1),
              onTocar: (i) {
                // Con la tanda larga, cada puntito lleva al principio de su
                // tramo.
                final destino = tanda.length <= _maxPuntitos
                    ? i
                    : i * tanda.length ~/ _maxPuntitos;
                _irA((base + destino).toDouble().clamp(0.0, ultimo), grupos);
              },
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
    int fantasmas,
  ) {
    double anchoDe(int i) {
      final lejos = (_p - i).abs().clamp(0.0, 1.0);
      return m.anchoChico + (m.ancho - m.anchoChico) * (1 - lejos);
    }

    // ── Siempre dos a cada lado ────────────────────────────────────────
    //
    // La ventana se centraba en `_p.floor()`, que salta de golpe al cruzar un
    // entero: en ese cuadro, la tarjeta del extremo pasaba a quedar fuera de
    // la ventana y **desaparecía de la nada** en vez de irse deslizando.
    //
    // Redondeando, la ventana cambia cuando la tarjeta del centro ya cambió, y
    // se pide una de más a cada lado: la que entra y la que sale siguen
    // dibujadas mientras se mueven, así que el borde nunca parpadea.
    final centroEntero = _p.round();
    // El tope incluye las que esperan: son parte del recorrido aunque todavía
    // no tengan contenido.
    final tope = planos.length - 1 + fantasmas;

    // ── Cuántas se dibujan sale del ancho de la ventana ───────────────────
    //
    // Antes eran tres a cada lado y punto. En un teléfono alcanza de sobra,
    // pero en un monitor ancho no: a los costados de la grande entran ocho o
    // diez tiras, y las que pasaban de la séptima simplemente no se dibujaban.
    // Quedaba un hueco negro contra los bordes.
    //
    // Se calcula cuántas tiras caben en lo que sobra a cada lado de la grande,
    // y se pide una de más de margen: es la que está entrando o saliendo, y
    // tiene que existir mientras se mueve o el borde parpadea.
    //
    // El mínimo de tres se queda: en pantallas angostas es lo que ya andaba, y
    // bajar de ahí rompería el mismo borde que esto viene a arreglar.
    final costado = (anchoUtil - m.ancho) / 2;
    final cabenAlLado =
        costado <= 0 ? 0 : (costado / (m.anchoChico + _aire)).ceil();
    //
    // ── Y nunca más de cuatro por lado ────────────────────────────────────
    //
    // Tres visibles y una de margen —la que está entrando o saliendo—. Ese es
    // el acordeón que se buscaba: una elegida, tres vecinas a cada lado, y se
    // acabó.
    //
    // Sin este tope, en una tablet ancha la cuenta pedía cinco o seis por lado
    // y el carrusel se volvía una pared de portadas, sin nada que mirara al
    // centro. Reportado en tablet y en escritorio, con la misma frase: se ven
    // demasiadas.
    //
    // De paso acota lo que cuesta: cada tarjeta decodifica su portada al tamaño
    // de la grande —medio megabyte— aunque en pantalla sea una tira.
    final radio = (cabenAlLado + 1).clamp(3, 4);

    final desde = (centroEntero - radio).clamp(0, tope);
    final hasta = (centroEntero + radio).clamp(0, tope);
    final foco = _p.floor();

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

    // ── Siempre centrada, también en los extremos ──────────────────────
    //
    // Se probó apoyarla en el borde al llegar al principio o al final, para
    // que no quedara hueco de un lado. Se ve peor: la tarjeta en foco cambia
    // de sitio según dónde estés en la lista, así que la vista salta al pasar
    // la primera o la última.
    //
    // Centrada siempre, el foco está SIEMPRE en el mismo lugar de la pantalla
    // y el ojo no tiene que ir a buscarlo. El hueco de los extremos es el
    // precio, y es el barato.

    return Stack(
      children: [
        for (var i = desde; i <= hasta; i++)
          Positioned(
            key: ValueKey(i >= planos.length
                ? 'esperando-$i'
                : '${planos[i].$1}|${planos[i].$2.url}'),
            left: xs[i]! + dx,
            // Todas del MISMO alto. Lo que distingue a la elegida es el
            // ancho, y nada más: encogiéndolas también de alto quedaban
            // escalonadas, como si cada una estuviera a otra distancia.
            top: 0,
            width: anchoDe(i),
            height: m.alto,
            // ── Sin Opacity acá ──────────────────────────────────────────
            //
            // Había un desvanecido para las tarjetas de la punta. Sobraba: el
            // acordeón va dentro de un ClipRect, así que a esa distancia ya
            // están fuera de la pantalla y no se ven igual.
            //
            // Y costaba caro. Un Opacity sobre algo con sombra y recorte
            // obliga a dibujarlo en una capa aparte, y con Impeller además
            // saltaba una queja por cada tarjeta, cinco veces por cuadro:
            //
            //   Contents::SetInheritedOpacity should never be called when
            //   Contents::CanAcceptOpacity returns false
            // Todavía no llegó: una tarjeta brillando en su lugar. Cuando el
            // contenido llegue va a ocupar exactamente este hueco.
            child: i >= planos.length
                ? Esqueleto(radio: 20, width: anchoDe(i), height: m.alto)
                : _TarjetaGrande(
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
                    fuente:
                        ExtensionUtils.runtimes[planos[i].$1]?.extension.name ??
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

  /// Desvanece las puntas del acordeón en vez de cortarlas de golpe.
  ///
  /// ── El problema ─────────────────────────────────────────────────────────
  ///
  /// El acordeón se desborda a propósito: las tarjetas siguen más allá del
  /// borde para que se entienda que hay más. Pero el recorte las corta en
  /// vertical y al ras, así que la de la punta muestra media esquina redonda y
  /// el resto cuadrado. Parece un error de dibujo, no un recorte.
  ///
  /// ── Por qué solo en escritorio ──────────────────────────────────────────
  ///
  /// En un teléfono el acordeón va de borde a borde: el corte cae justo contra
  /// el canto de la pantalla, donde nadie lo lee como un corte. En escritorio
  /// cae en medio de la ventana, contra el fondo, y ahí sí se ve.
  ///
  /// Y esto cuesta: obliga a dibujar el acordeón en una capa aparte para
  /// aplicarle la máscara, en cada cuadro del arrastre. En escritorio sobra
  /// potencia; en un teléfono sería pagar por arreglar algo que no se nota.
  static Widget _conPuntasDifuminadas(Widget acordeon) {
    if (_esTactil) return acordeon;
    return ShaderMask(
      // `dstIn` apaga la propia imagen según el gris de la máscara, en vez de
      // pintarle encima un degradado hacia el color de fondo. La diferencia
      // importa: con un degradado opaco quedaría una banda del color del tema
      // sobre el fondo animado, y se vería el borde de la banda.
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        // Angosto a propósito: lo justo para que la punta se apague, sin
        // comerse la tarjeta que está entrando.
        stops: [0.0, 0.05, 0.95, 1.0],
      ).createShader(rect),
      child: acordeon,
    );
  }

  /// Un disco oscuro detrás de la flecha, para que se lea sobre cualquier
  /// portada.
  static Widget _discoDeFlecha(Widget flecha) => DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xB3101018),
        ),
        child: Padding(padding: const EdgeInsets.all(3), child: flecha),
      );

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
        ? a.elegir(compacto: 0.46, medio: 0.36, amplio: 0.34, enorme: 0.28)
        : a.elegir(compacto: 0.66, medio: 0.5, amplio: 0.42, enorme: 0.34);

    var ancho = anchoUtil * parte;
    var alto = ancho * relacion;

    // ── Cuánto alto se le deja ─────────────────────────────────────────
    //
    // En un teléfono acostado el alto es lo escaso, así que se le da casi
    // todo. De pie sobra, y el carrusel no puede comerse la pantalla: hay
    // filas debajo que también tienen que verse sin desplazar.
    //
    // La tablet es el caso que faltaba. Con el 0.4 del teléfono, sus 800
    // píxeles de alto daban tarjetas de 320 — chiquitas y perdidas en 1280 de
    // ancho. Tiene sitio de sobra para el doble, y debajo igual entra la
    // primera fila.
    final tope = altoPantalla *
        (bajo ? 0.66 : a.elegir(compacto: 0.4, medio: 0.42, amplio: 0.55));
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
      anchoChico: (ancho * _proporcionChicaDe(a)).clamp(38.0, ancho),
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
          // ── Sin relleno detrás de la portada ─────────────────────────────
          //
          // Había un fondo del color de las tarjetas. Es redondeado, y la
          // portada va recortada encima con el mismo radio: donde el recorte
          // suaviza el borde, ese fondo —más claro que el de la pantalla— se
          // asoma un píxel y deja un hilo claro siguiendo el contorno. Es la
          // línea que se veía debajo de la tarjeta en escritorio.
          //
          // No hacía falta: mientras la portada carga, el hueco ya lo pinta el
          // marcador de posición, que va ADENTRO del recorte y no se asoma.
          // ── El filo y la sombra, solo en pantalla táctil ─────────────────
          //
          // El filo blanco y la sombra existen para que la forma de la tarjeta
          // se lea sobre una portada oscura, y en el teléfono cumplen: ahí se
          // ve una grande con dos tiras asomando contra el borde de la
          // pantalla, y se ven bien.
          //
          // En escritorio no. Las tiras quedan a nueve píxeles una de otra, así
          // que los filos aparecen de a pares y las sombras se superponen en el
          // hueco: se leen como rayas verticales entre portada y portada, no
          // como bordes. Y las de las puntas quedan cortadas por el recorte,
          // con el filo terminando en seco contra el aire.
          //
          // En una ventana grande la portada ya se ve entera y las esquinas
          // redondas le dan forma de sobra. Limpia se ve mejor.
          border: _esTactil
              ? Border.all(color: Colors.white.withValues(alpha: 0.11))
              : null,
          boxShadow: _esTactil
              ? const [
                  BoxShadow(
                    color: Color(0x73000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
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
                // Un bloque brillando mientras baja la portada, no un
                // rectángulo gris quieto. Con el gris, una tarjeta a medio
                // cargar se ve igual que una rota; con el brillo se entiende
                // que está en camino.
                placeholder: const Esqueleto(radio: 20),
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
    // ── Sin ese filtro, igual se muestra ────────────────────────────
    //
    // Antes acá iba una línea diciendo «no tiene ese género» en vez de la
    // fila. Se probó y no sirve: el usuario marca «Manga» y se queda con media
    // pantalla de renglones de disculpa en lugar de contenido.
    //
    // Ahora la fila trae lo suyo de siempre y el encabezado dice «Lo más
    // reciente» en vez de «Según tu filtro». Se ve contenido, y no se miente
    // sobre qué es. Las que SÍ pueden filtrar ya van arriba (ver `_visibles`),
    // así que estas quedan abajo sin estorbar.
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
              c: widget.c,
              items: items,
              // ── Los bloques SOLO si no hay nada que mostrar ─────────
              //
              // Se probó mostrarlos también al filtrar, con contenido en
              // pantalla, para que se notara que estaba trabajando. Se ve mal:
              // las tarjetas desaparecen, entran bloques grises y vuelven a
              // aparecer tarjetas. Son tres cambios visuales para una sola
              // cosa, y parece que la pantalla se rompiera.
              //
              // Ahora las tarjetas se quedan EN SU LUGAR y se reemplazan cuando
              // llega lo nuevo. Que está buscando lo dice el encabezado, en la
              // línea que ya está ahí — así no se mueve nada.
              // ── Pendiente TAMBIÉN cuenta como cargando ──────────────
              //
              // Antes solo salían los bloques con el estado `cargando`, que se
              // pone cuando la fila EMPIEZA a pedir. Pero la cola atiende tres
              // a la vez: con once extensiones, ocho quedan en `pendiente`
              // esperando turno, con la lista vacía y sin bloques.
              //
              // Eso es la pantalla en blanco al entrar: filas sin nada debajo
              // del título y contenido que aparecía de golpe cuando les tocaba.
              // Reportado en escritorio, pero pasa en los tres.
              //
              // Con `pendiente` incluido, desde el primer cuadro cada fila
              // muestra la forma de lo que va a llegar y nada aparece de la
              // nada.
              cargando: items.isEmpty && estado != EstadoDeFila.fallo,
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
      // El nombre y, debajo, qué está mostrando. Sin eso, dos filas iguales
      // con títulos distintos no dicen por qué son distintas.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
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
          Text(
            // Su propio estado, no el global: ver `refrescando`.
            widget.fila.refrescando.value
                ? 'home.modo-buscando'.i18n
                : widget.c.etiquetaDe(widget.fila) ??
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
    required this.c,
    required this.items,
    required this.cargando,
    required this.package,
  });

  final CatalogoExtensionesController c;
  final List<ExtensionListItem> items;
  final bool cargando;
  final String package;

  @override
  State<_GrillaPaginada> createState() => _GrillaPaginadaState();
}

class _GrillaPaginadaState extends State<_GrillaPaginada> {
  /// Cuántas portadas ofrece cada extensión, en cualquier aparato.
  ///
  /// ── Por qué un número de PORTADAS y no de páginas ──────────────────────
  ///
  /// Porque cuántas entran por página depende de la pantalla: tres columnas
  /// por dos filas en un teléfono, cinco por dos en una tablet. Con un tope de
  /// páginas, el teléfono ofrecía dieciocho y la tablet treinta — la misma
  /// extensión mostraba casi el doble de cosas según el aparato, sin ningún
  /// motivo.
  ///
  /// Fijando las portadas y calculando las páginas al revés, todos ven más o
  /// menos lo mismo: seis páginas de tres en un teléfono acostado, dos de diez
  /// en una tablet.
  static const _porExtension = 18;

  /// Tope duro de páginas. No por contenido: por los puntitos. Con ocho o
  /// nueve dejan de leerse como «vas por la segunda de tres».
  static const _maxPaginas = 5;
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
    final filasDeseadas = MediaQuery.sizeOf(context).height < 500 ? 1 : 2;

    // De la caja y no de MediaQuery: en horizontal el ancho de pantalla
    // incluye la franja de la barra del sistema y la grilla se desbordaba.
    return LayoutBuilder(builder: (context, caja) {
      if (!caja.maxWidth.isFinite || caja.maxWidth < 120) {
        return const SizedBox(height: 12);
      }
      // ── Las filas salen del CONTENIDO, no del deseo ────────────────
      //
      // Reservando siempre dos, una extensión que devuelve cuatro portadas
      // dejaba media pantalla de vacío negro debajo — se ve como si la app se
      // hubiera colgado a mitad de dibujar.
      //
      // Ahora se reserva lo que de verdad hay: con cinco columnas y cuatro
      // ítems va una fila y el alto es de una fila.
      final filas = widget.items.isEmpty
          ? filasDeseadas
          : ((widget.items.length + columnas - 1) ~/ columnas)
              .clamp(1, filasDeseadas);
      final porPagina = columnas * filas;

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

      // ── Solo páginas LLENAS ────────────────────────────────────────
      //
      // Antes se redondeaba hacia arriba: con veinte portadas y ocho por
      // página salían tres páginas, y la última tenía cuatro. Como el alto
      // está reservado para dos filas —tiene que ser fijo, si no el Home
      // saltaría al pasar de página— esa última dejaba una fila entera de
      // negro debajo. Es exactamente el hueco que se ve al llegar al final de
      // una extensión.
      //
      // Redondeando hacia ABAJO, todas las páginas están llenas. Se pierden
      // las portadas del resto —hasta siete— y está bien: esto es una
      // vidriera, no el catálogo, y una fila vacía se nota mucho más que
      // cuatro portadas que nadie sabía que existían.
      // Las páginas salen de cuántas portadas se quieren mostrar, no al
      // revés. Y siempre llenas: una a medias deja una fila de negro.
      // ── La grilla CRECE con lo que vaya llegando ────────────────────
      //
      // Antes se quedaba en las dieciocho de la primera carga: el usuario
      // pasaba una página y se acababa, aunque la extensión tuviera cientos.
      //
      // Ahora el objetivo de dieciocho es el PISO, no el techo: si ya hay más
      // portadas traídas —porque se pidieron más al llegar al final— la grilla
      // suma páginas hasta el tope.
      final objetivo = (_porExtension / porPagina).round();
      final llenasDisponibles = widget.items.length ~/ porPagina;
      var paginas = llenasDisponibles > objetivo ? llenasDisponibles : objetivo;
      if (llenasDisponibles >= 1 && paginas > llenasDisponibles) {
        paginas = llenasDisponibles;
      }
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
              onPageChanged: (i) {
                setState(() => _actual = i);
                // Al llegar a la última se piden más. Igual que en el
                // acordeón: una vez por gesto, y el controlador ignora el
                // pedido si ya hay uno en curso.
                if (i >= paginas - 1) unawaited(widget.c.traerMas());
              },
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

/// El Home mientras todavía no se sabe qué hay.
class _HomeEsperando extends StatelessWidget {
  const _HomeEsperando({this.conCabecera = true});

  /// El nombre del app arriba. En escritorio no va: ahí el título vive en la
  /// barra de la ventana, y dibujarlo dos veces se vería como un error.
  final bool conCabecera;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      // En escritorio, el mismo aire de arriba que tiene el Home de verdad:
      // sin esto el bloque del acordeón arranca pegado al borde y al llegar el
      // contenido todo se corre veinte píxeles hacia abajo.
      padding: conCabecera ? EdgeInsets.zero : const EdgeInsets.only(top: 20),
      children: [
        if (conCabecera) ...const [
          _Cabecera(),
          SizedBox(height: 8),
        ],
        const _CarruselEsperando(),
        const _FilaEsperando(),
        const _FilaEsperando(),
      ],
    );
  }
}

/// Una fila con su nombre y sus portadas en gris.
class _FilaEsperando extends StatelessWidget {
  const _FilaEsperando();

  @override
  Widget build(BuildContext context) {
    final margen = _margen(context);
    final a = Ancho.de(context);
    final columnas = a.elegir(compacto: 3, medio: 4, amplio: 5, enorme: 6);
    return LayoutBuilder(builder: (context, caja) {
      if (!caja.maxWidth.isFinite || caja.maxWidth < 120) {
        return const SizedBox(height: 12);
      }
      final ancho =
          (caja.maxWidth - margen * 2 - 12 * (columnas - 1)) / columnas;
      return Padding(
        padding: EdgeInsets.fromLTRB(margen, 20, margen, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Esqueleto(width: 150, height: 20, radio: 6),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < columnas; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  EsqueletoTarjeta(ancho: ancho),
                ],
              ],
            ),
          ],
        ),
      );
    });
  }
}
