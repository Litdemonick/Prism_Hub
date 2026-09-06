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
        // ── Bloques grises mientras se arma, no el mensaje de vacío ──────
        //
        // Antes acá iba directo el aviso de «no tenés extensiones». Pero al
        // arrancar la app las filas TODAVÍA no están: hay que leer el caché de
        // disco y esperar a que los motores de las extensiones terminen de
        // cargar. En ese rato `filas` está vacío y no se sabe nada.
        //
        // Eso es la pantalla vacía al abrir en Windows, con el contenido
        // apareciendo de golpe después. El Home de celular ya lo resolvía así
        // desde antes; en escritorio faltaba, y era el único de los dos que
        // mostraba el hueco.
        //
        // El mensaje aparece recién cuando `armado` dice que de verdad terminó
        // de mirar y no encontró ninguna.
        if (c.filas.isEmpty) {
          return c.armado.value
              ? const _SinExtensiones()
              : const _HomeEsperando(conCabecera: false);
        }
        // Igual que en celular: la lista se calcula UNA vez, para que
        // `itemCount` y el constructor no puedan discrepar entre una
        // llamada y la otra.
        final visibles = c.filas
            .where(
                (f) => f.estadoExt == EstadoExtension.activa || f.esVistaPrevia)
            // Preferencia de Ajustes (Fase 11): qué zonas se mezclan en
            // Inicio. Vacía = todas, como siempre.
            .where((f) => ZonasPreferidasEnInicio.pasaElFiltro(
                  ExtensionUtils.zonasDe(f.package),
                ))
            .toList();
        return RefreshIndicator(
          // Sin la barra de chips ya no hay ningún filtro que "aplicar" —
          // deslizar hacia abajo siempre vuelve a pedir lo mismo de antes.
          onRefresh: c.refrescarTodo,
          child: ListView.builder(
            // Una pantalla de adelanto: cada fila pide lo suyo al construirse, así
            // que esto adelanta la PETICIÓN, no el dibujado. Ver home_page_tv.dart.
            scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas ??
                const ScrollCacheExtent.viewport(1),
            physics: const AlwaysScrollableScrollPhysics(),
            // Arriba también: el acordeón arrancaba pegado al borde de la
            // ventana, sin nada entre la barra de título y la primera portada.
            // Se leía como si el contenido estuviera cortado por arriba.
            padding: const EdgeInsets.only(top: 20, bottom: 36),
            // +1: el fondo grande de arriba.
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
            itemCount: (visibles.isEmpty ? 2 : visibles.length) + 1,
            // **Acá está la carga perezosa.** ListView.builder solo construye
            // lo que está cerca de la pantalla, y cada fila pide en su
            // initState — así, con 30 extensiones se piden las 2 o 3 que se
            // ven, no las 30.
            itemBuilder: (context, i) => switch (i) {
              // ── El mismo acordeón que en celular ───────────────────────
              //
              // Antes acá había un fondo grande a todo lo ancho que cambiaba
              // solo cada ocho segundos. Se veía bien pero mostraba UNA
              // portada: con once extensiones y cientos de títulos, el
              // escritorio —que es donde más espacio sobra— era el que menos
              // contenido enseñaba, y encima el usuario no podía elegir qué
              // mirar.
              //
              // El acordeón vive en el archivo de Android, pero los tres son
              // `part` de la misma biblioteca: se reusa tal cual, con la misma
              // lógica de anclaje, fantasmas y pedido de más páginas. Escribir
              // otro para escritorio sería tener dos que se desincronizan a la
              // primera, que es el error que ya cometimos con los filtros.
              //
              // Se adapta solo: las medidas salen de `Ancho.de(context)` y la
              // ventana de tarjetas que se dibuja sale del ancho real, así que
              // en un monitor grande llena el costado en vez de dejar hueco.
              // ── Con el mismo margen que las filas de abajo ────────────
              //
              // Sin esto el acordeón iba de borde a borde y la tarjeta quedaba
              // pegada a la barra lateral de iconos, sin nada en medio. Se ve
              // sobre todo con la ventana angosta, donde la grande se lleva
              // casi todo el ancho y termina tocando la barra.
              //
              // El margen es el mismo que usan las filas, así que el acordeón
              // queda alineado con ellas en vez de sobresalir. Las tarjetas de
              // los costados se siguen recortando igual —el recorte solo se
              // corre hacia adentro— así que no se pierde la señal de que hay
              // más para el lado.
              0 => Padding(
                  padding: EdgeInsets.symmetric(horizontal: _margen(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RepaintBoundary(child: _CarruselAndroid(c: c)),
                      // Pedido explícito: un botón para poner al día las
                      // filas de abajo sin que eso mueva ni cambie el
                      // carrusel — refrescarTodo() no toca
                      // carruselExt/carruselPos/_paqueteDeArranque en
                      // ningún lado.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 22, 0, 8),
                        // El ancho lo pone el SizedBox: el Column de arriba
                        // usa crossAxisAlignment.start (para el carrusel),
                        // así que sin esto Center no tenía dentro de qué
                        // centrarse y el botón quedaba pegado a la
                        // izquierda igual.
                        child: SizedBox(
                          width: double.infinity,
                          child: Center(
                              child: RefreshButton(onTap: c.refrescarTodo)),
                        ),
                      ),
                    ],
                  ),
                ),
              _ => visibles.isEmpty
                  ? const _FilaEsperando()
                  : (i - 1 < visibles.length
                      ? _FilaWindows(
                          key: ValueKey(visibles[i - 1].package),
                          c: c,
                          fila: visibles[i - 1],
                        )
                      : const SizedBox.shrink()),
            },
          ),
        );
      }),
    );
  }
}

/// Una fila: el nombre de la extensión y lo último que tiene, en horizontal.
class _FilaWindows extends StatefulWidget {
  const _FilaWindows({
    super.key,
    required this.c,
    required this.fila,
    this.conFocoTv = false,
  });

  final CatalogoExtensionesController c;
  final FilaDeExtension fila;

  /// Si `true`, cada tarjeta se envuelve en [FocusableCard] para que sea
  /// navegable con D-pad. Solo lo usa [HomeTV] — en Windows queda en `false`
  /// y la fila se comporta exactamente igual que siempre.
  final bool conFocoTv;

  @override
  State<_FilaWindows> createState() => _FilaWindowsState();
}

/// El ancho de tarjeta en TV: un poco más grande que el de escritorio
/// (mismo `Ancho.anchoPara` como base) porque en TV se mira desde el
/// sillón, no a 30cm de la cara.
///
/// ── Por qué se achicó de 1.25 a 1.05 ────────────────────────────────────
///
/// Pedido explícito, con una captura de referencia de otra app de TV: ahí
/// se ven DOS filas a la vez —una entera arriba y la de abajo asomando— y
/// en esta pantalla, con las tarjetas al 1.25, una sola fila ocupaba casi
/// toda la altura visible: no quedaba ningún indicio de que había más para
/// abajo, se sentía como que la pantalla terminaba ahí. Con tarjetas más
/// chicas, la MISMA fila pesa menos en la pantalla y entra más de una a la
/// vez sin tocar el resto del diseño (el margen entre filas, pensado para
/// que la tarjeta enfocada crezca sin pisar el título de la siguiente,
/// sigue siendo el mismo).
/// El ancho de tarjeta en TV.
///
/// Sale de la misma cuenta que las filas de las zonas (`_anchoPosterTv`,
/// en home_page_tv.dart): siete pósters enteros por fila y el octavo
/// asomando. Del boceto aprobado — antes era el ancho de escritorio por
/// 1.05, que en un televisor dejaba cuatro o cinco enormes y media
/// pantalla desaprovechada.
double _anchoTarjetaTv(BuildContext context) => _anchoPosterTv(context);

/// El margen izquierdo de una fila, título y tarjetas por igual.
///
/// ── Por qué no es `_margen` a secas ─────────────────────────────────────
///
/// En escritorio el título y la tira llevaban el mismo margen salvo que la
/// tira sumaba 26 de aire, para que el marco de foco de la primera tarjeta
/// no quedara mordido contra el recorte de la fila. En televisor eso se
/// veía como que las tarjetas arrancaban corridas respecto del título —
/// reportado: «que alinee bien el título, que también vaya a la izquierda,
/// y que las cards vayan a la izquierda».
///
/// En TV ya no hace falta ese aire: la fila no recorta (`Clip.none`) y el
/// contenido arranca pegado al rail. Así que las dos cosas van al mismo
/// sitio, y bien a la izquierda.
/// ── Por qué 8 y no 2 ────────────────────────────────────────────────────
///
/// El marco de foco se dibuja POR FUERA de la tarjeta. Con 2, la PRIMERA de
/// cada fila tenía su lado izquierdo casi pegado al recorte, y ahí la línea
/// se ve más fina que en los otros tres lados. Reportado con foto: «en la
/// primera card se me achica la línea rosada del lado izquierdo; a la
/// derecha ya lo mejoraste, falta el izquierdo».
///
/// Sigue alineada con el título de la fila a ojo —ocho puntos no se leen
/// como una sangría— y ahora el marco entra entero.
double _margenDeFilaTv(BuildContext context) => HomeTheme.aireDeFocoTv;

double _altoFilaTv(BuildContext context) =>
    TarjetaDeCatalogo.altoDeUnaLineaDeAncho(_anchoTarjetaTv(context)) + 20;

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
    // ── Cada fila se pinta en su propia capa ──────────────────────────────
    //
    // Sin esto, cualquier cosa que cambie dentro de UNA fila —una portada que
    // termina de llegar, el marco de foco que se mueve, los dos bloques
    // brillando del final mientras refresca— obliga a volver a pintar todas
    // las filas que estén en pantalla.
    //
    // La rama de teléfono ya lo hacía (ver `home_page_android.dart`); acá
    // faltaba, y esta es justo la fila que usan escritorio y televisor. Va
    // adentro del widget y no en quien lo llama, para que valga en los dos
    // lados sin repetirlo.
    return RepaintBoundary(child: _contenido(context));
  }

  Widget _contenido(BuildContext context) {
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
        // En TV, más separación entre filas: la tarjeta enfocada crece hacia
        // arriba y hacia abajo, y con 26 la de una fila se metía sobre el
        // título de la siguiente.
        padding: EdgeInsets.only(top: widget.conFocoTv ? 34 : 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _encabezado(),
            SizedBox(height: widget.conFocoTv ? 18 : 14),
            SizedBox(
              // Aire de más para la sombra.
              //
              // La tarjeta crece y se le dibuja una sombra al pasar el mouse, y
              // las dos cosas se salen de su caja. Con el alto justo, la fila
              // recortaba contra su borde y la sombra aparecía cortada en
              // línea recta — se veía peor que no tenerla.
              //
              // En TV, más grande: se mira desde el sillón, no a 30cm de la
              // cara — el tamaño de escritorio se queda chico en un
              // televisor real. `_anchoTarjetaTv`/`_altoFilaTv` son las que
              // de verdad se usan cuando `conFocoTv`; el resto de la fila
              // (bloques grises, `ClipRect`, etc.) sigue funcionando igual
              // porque solo cambia el número que le pasan.
              height: widget.conFocoTv
                  ? _altoFilaTv(context)
                  : TarjetaDeCatalogo.altoTotalPara(context) + 28,
              // Bloques grises con la forma de las tarjetas, igual que en
              // celular: dicen QUÉ va a aparecer y dónde, así que al llegar el
              // contenido nada se mueve. Y salen también con contenido en
              // pantalla cuando hay un filtro en curso — lo que se ve es del
              // filtro anterior, y dejarlo quieto haría creer que no pasó
              // nada.
              // Solo si no hay nada que mostrar: con contenido en pantalla,
              // cambiarlo por bloques y volver son dos saltos para una espera.
              // Que está buscando lo dice el encabezado. Ver el comentario
              // largo en la grilla de celular.
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
              child: (items.isEmpty && estado != EstadoDeFila.fallo)
                  // ── En televisor, el giro; en el resto, los bloques ──
                  //
                  // Los bloques con forma de tarjeta se leen bien de cerca.
                  // A tres metros son cajas grises que parecen contenido
                  // roto. Pedido explícito y repetido: en TV, el giro en el
                  // centro de la fila y nada más hasta que llegue lo real.
                  ? (widget.conFocoTv
                      ? const Center(child: CargandoTv())
                      // Los que entran, no seis fijos: en una ventana ancha
                      // la fila de bloques terminaba a media pantalla. Ver
                      // EsqueletoDeFila.
                      : EsqueletoDeFila(
                          ancho: TarjetaDeCatalogo.anchoPara(context),
                          separacion: 14,
                          padding: EdgeInsets.symmetric(
                            horizontal: _margen(context),
                          ),
                          paddingDeCadaUno: const EdgeInsets.only(top: 10),
                        ))
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
                  : _conDesvanecido(ClipRect(
                      clipper: _SoloCostados(
                        aireLateral: widget.conFocoTv ? 24 : 0,
                      ),
                      child: ListView.separated(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        // Ver la nota igual en home_section.dart.
                        scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas,
                        // Que la tarjeta que sale de pantalla se destruya y
                        // suelte su portada, en vez de quedarse viva
                        // ocupando el techo de imágenes.
                        addAutomaticKeepAlives: false,
                        // Sin esto el recorte se come la sombra igual, por más
                        // aire que se le dé: un ListView recorta en su borde
                        // por defecto.
                        clipBehavior: Clip.none,
                        // En TV, más aire a los costados: la tarjeta
                        // enfocada crece y le sale un marco, y con el margen
                        // justo la primera y la última quedaban cortadas
                        // contra el recorte de la fila.
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.conFocoTv
                              ? _margenDeFilaTv(context)
                              : _margen(context),
                        ),
                        // ── Y dos brillando al final si está trayendo ──
                        //
                        // Refrescar una fila que ya tiene portadas no las
                        // reemplaza por bloques grises: eso probamos y se ve
                        // mal —desaparecen, entran bloques, vuelven— tres
                        // cambios para una sola espera.
                        //
                        // Pero sin nada, tampoco se notaba que estuviera
                        // trabajando. Dos bloques al FINAL lo dicen sin mover
                        // ni una tarjeta de las que ya están: se agregan
                        // después de la última y se van cuando llega lo nuevo.
                        itemCount: items.length +
                            (widget.fila.refrescando.value ? 2 : 0),
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) {
                          if (i >= items.length) {
                            final fantasma = Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: EsqueletoTarjeta(
                                ancho: widget.conFocoTv
                                    ? _anchoTarjetaTv(context)
                                    : TarjetaDeCatalogo.anchoPara(context),
                              ),
                            );
                            // ── En TV, con marco de foco propio ────────────
                            //
                            // Sin esto, estos dos bloques —que comparten el
                            // MISMO ListView.separated que las tarjetas
                            // reales, o sea el mismo scroll— no tienen
                            // ningún FocusNode. Parado en la última tarjeta
                            // de verdad mientras la fila está refrescando,
                            // apretar derecha no encuentra ningún vecino
                            // enfocable DENTRO de la fila —los fantasmas no
                            // cuentan— y la búsqueda de Flutter se ve
                            // obligada a buscar en cualquier otro lado de la
                            // pantalla: se pierde la selección, y una
                            // segunda pulsación termina bajando a otra fila
                            // sin que nadie lo pidiera.
                            //
                            // Reportado en vivo: «en la fila de esa
                            // extensión ya no hay más [tarjetas] pero sigue
                            // bajando al ir a la derecha».
                            //
                            // Con el marco puesto, el fantasma pasa a ser un
                            // destino legítimo DENTRO de la misma fila —sin
                            // onTap, no hace nada al confirmarlo, es solo
                            // una parada— y ahí sí se queda: no hay nada más
                            // a la derecha de un fantasma, así que el tope
                            // ya existente (`FocoConTopes`) lo frena ahí,
                            // como corresponde.
                            return widget.conFocoTv
                                ? FocusableCard(
                                    borderRadius: 8,
                                    onTap: () {},
                                    child: fantasma,
                                  )
                                : fantasma;
                          }
                          final item = items[i];
                          void abrir() =>
                              _abrir(context, item, widget.fila.package);
                          Widget tarjeta({bool tvFoco = false}) =>
                              TarjetaDeCatalogo(
                                titulo: item.title,
                                portada: item.cover,
                                cabeceras: _cabeceras(widget.fila.package),
                                encabezado: widget.fila.nombre,
                                // `update` es lo único con forma de fecha que
                                // devuelve `latest()`. Cada extensión lo
                                // escribe a su manera —«hace 2 días», «Ep 12»,
                                // una fecha— así que se muestra TAL CUAL:
                                // normalizarlo acá sería inventar una
                                // precisión que el dato no tiene.
                                fecha: item.update,
                                // Más grande en TV — se mira desde el sillón.
                                ancho: widget.conFocoTv
                                    ? _anchoTarjetaTv(context)
                                    : null,
                                // Sin onTap cuando hay foco de TV: FocusableCard ya
                                // lo maneja por fuera. Con los dos a la vez, un
                                // solo click dispara `abrir` DOS veces — cada
                                // GestureDetector reconoce el toque por su cuenta,
                                // ninguno "gana" sobre el otro porque no compiten
                                // por el mismo gesto (no hay arrastre de por medio).
                                onTap: widget.conFocoTv ? null : abrir,
                                // En televisor, una sola línea de título:
                                // ver TarjetaDeCatalogo.altoDeUnaLineaDeAncho.
                                tituloEnUnaLinea: widget.conFocoTv,
                                // Mismo criterio que la grilla de zonas
                                // (`_ZonaTv`): el panel con el nombre de la
                                // extensión solo aparece en la tarjeta que
                                // TIENE el foco ahora mismo, nunca en reposo.
                                tvFoco: tvFoco,
                              );
                          return Padding(
                            // Arriba, para que la tarjeta tenga hacia dónde
                            // crecer sin pisar el título de la fila.
                            padding: const EdgeInsets.only(top: 10),
                            child: widget.conFocoTv
                                ? FocusableCard(
                                    onTap: abrir,
                                    // Solo la PORTADA, no el título de
                                    // debajo: lo que se está eligiendo es la
                                    // imagen, y el marco alrededor de las
                                    // dos cosas encierra un texto suelto en
                                    // el aire.
                                    //
                                    // El alto es exacto: la portada de
                                    // TarjetaDeCatalogo es 2:3 sobre el
                                    // ancho que se le pasa (ver su
                                    // `altoPortada`). El primer intento se
                                    // veía corrido, pero no era la cuenta —
                                    // era que la tarjeta ADEMÁS se agrandaba
                                    // sola con el hover y crecía más que el
                                    // marco; eso ya no pasa en TV.
                                    altoMarco: _anchoTarjetaTv(context) * 3 / 2,
                                    // `builder` y no `child`: ver el mismo
                                    // comentario en `_ZonaTv` — la tarjeta
                                    // necesita saber si TIENE el foco ahora
                                    // mismo para mostrar el panel de info.
                                    builder: (tieneFoco) =>
                                        tarjeta(tvFoco: tieneFoco),
                                  )
                                : tarjeta(),
                          );
                        },
                      ),
                    )),
            ),
          ],
        ),
      );
    });
  }

  Widget _encabezado() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal:
            widget.conFocoTv ? _margenDeFilaTv(context) : _margen(context),
      ),
      child: Row(
        children: [
          Expanded(
            // El nombre y, debajo, qué está mostrando. Sin eso, dos filas
            // iguales con títulos distintos no dicen por qué son distintas.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
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
                    ),
                    // «Ver todo», PEGADA al nombre.
                    //
                    // Estaba al otro extremo, junto a las flechas de recorrer
                    // la fila, y ahí se leía como una tercera flecha de mover
                    // — tres iconos parecidos seguidos, y el que hace algo
                    // distinto era el primero. Al lado del título se entiende
                    // sola: «MangaDex ›» es entrar a MangaDex.
                    if (UltimasActualizacionesMangaDexPage.disponiblePara(
                            widget.fila.package) &&
                        widget.c.etiquetaDe(widget.fila) != null)
                      _VerTodo(
                        onTap: () => UltimasActualizacionesMangaDexPage.abrir(
                          context,
                          titulo: widget.fila.nombre,
                          etiqueta: widget.c.etiquetaDe(widget.fila),
                        ),
                      ),
                  ],
                ),
                Text(
                  // Su propio estado, no el global: ver `refrescando`.
                  widget.fila.refrescando.value
                      ? 'home.modo-buscando'.i18n
                      : widget.c.etiquetaDe(widget.fila) ??
                          switch (widget.fila.modo) {
                            ModoDeFila.popular => 'home.modo-popular'.i18n,
                            ModoDeFila.reciente => 'home.modo-reciente'.i18n,
                          },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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

  /// Un desvanecido a los dos costados, solo en televisor.
  ///
  /// El degradado en sí vive en `DesvanecidoDeFila`, al lado del recorte que
  /// esta fila ya comparte con las de las zonas: estaba escrito acá y las
  /// filas de Películas, Series y Anime se habían quedado sin él, que es
  /// justo lo que se pidió igualar.
  ///
  /// Solo en TV: con mouse, la fila entera ya se ve completa apenas se
  /// desliza un poco, y un desvanecido ahí solo restaría contraste sin
  /// avisar de nada que el usuario no sepa.
  Widget _conDesvanecido(Widget fila) {
    if (!widget.conFocoTv) return fila;
    return DesvanecidoDeFila(scroll: _scroll, child: fila);
  }
}

/// El «ver todo» que va pegado al nombre de la fila.
///
/// Aparte de [_FlechaDeFila] a propósito, aunque las dos sean una flecha: esta
/// no recorre nada, ABRE otra pantalla. Que se vea distinta —más chica, en el
/// tono del subtítulo, encendiéndose al pasar por encima— es lo que evita que
/// se confunda con las de mover.
class _VerTodo extends StatefulWidget {
  const _VerTodo({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_VerTodo> createState() => _VerTodoState();
}

class _VerTodoState extends State<_VerTodo> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 24,
            color: _encima ? HomeTheme.textPrimary : HomeTheme.textMuted,
          ),
        ),
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
                ? HomeTheme.contraste.withValues(alpha: 0.12)
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
  const _SoloCostados({this.aireLateral = 0});

  /// Cuánto se deja escapar arriba y abajo. Con la sombra actual sobra.
  static const _aire = 60.0;

  /// Y cuánto a los costados. Cero en teléfono/escritorio: ahí el recorte
  /// lateral existe justamente para que una tarjeta que sale de la fila no
  /// se dibuje encima del margen ni de la barra lateral.
  ///
  /// En TV no puede ser cero: la tarjeta enfocada CRECE y le sale un marco,
  /// y con el corte al ras quedaba mordida por los dos lados. El aire es
  /// menor que el relleno extra que llevan las filas de TV, así que sigue
  /// sin llegar al sidebar.
  final double aireLateral;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        -aireLateral,
        -_aire,
        size.width + aireLateral,
        size.height + _aire,
      );

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
