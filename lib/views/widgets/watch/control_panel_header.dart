import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/watch/playlist.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/titulo_expandible.dart';
import 'package:prismhub/views/widgets/window_caption_buttons.dart';
import 'package:window_manager/window_manager.dart';

class ControlPanelHeader<T extends ReaderController> extends StatefulWidget {
  const ControlPanelHeader(
    this.tag, {
    super.key,
    required this.buildSettings,
  });
  final String tag;
  final Widget Function(BuildContext context)? buildSettings;

  @override
  State<ControlPanelHeader> createState() => _ControlPanelHeaderState<T>();
}

class _ControlPanelHeaderState<T extends ReaderController>
    extends State<ControlPanelHeader> {
  late final _c = Get.find<T>(tag: widget.tag);

  /// Si hay un capítulo antes/después del que se está leyendo.
  ///
  /// Antes la ÚNICA forma de cambiar de capítulo era abrir la lista entera y
  /// elegir a mano — cómodo para saltar lejos, pero de más para el caso más
  /// común: seguir con el que sigue. Pedido explícito: agregar dos flechas
  /// para ir directo al anterior o al siguiente, acá arriba junto a
  /// ajustes/detalle/episodios.
  bool get _hayAnterior => _c.index.value > 0;
  bool get _haySiguiente => _c.index.value < _c.playList.length - 1;

  void _irACapitulo(int delta) {
    final destino = _c.index.value + delta;
    if (destino < 0 || destino >= _c.playList.length) return;
    _c.index.value = destino;
  }

  final fluent.FlyoutController _playListFlayoutcontroller =
      fluent.FlyoutController();
  final fluent.FlyoutController _settingFlayoutcontroller =
      fluent.FlyoutController();

  void _goToDetail(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
    // Si se entró desde la propia página de detalle (goWatch), ya hay un
    // DetailPage de este mismo título debajo en la pila — cerrar el lector
    // alcanza para revelarlo. Empujar uno nuevo ACÁ TAMBIÉN lo duplicaba:
    // confirmado en vivo, "atrás" quedaba pegado un toque de más (el primero
    // solo cerraba el duplicado) antes de volver de verdad.
    if (_c.cameFromDetail) return;
    final package = _c.runtime.extension.package;
    final url = _c.detailUrl;
    // Confirmado en vivo: empujar la ruta nueva en el mismo tick que el pop
    // del lector hacía que DetailPage montara mientras el lector (y su
    // ComicController/GetX) todavía estaban terminando de desmontar —
    // "DetailPageController not found" + overflow gigante, ambos síntomas
    // de un build a medio terminar. Postergar el push a después de que este
    // frame (el del pop) termine de procesarse le da tiempo real a
    // GetX/Navigator para asentarse antes de montar la página nueva.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // router.push (go_router) es lo que muestra DetailPage CON los
      // controles de ventana en desktop (ver comentario de arriba sobre el
      // shell/rootNavigator) — pero en Android la app no navega el detalle
      // por ahí, sino con Get.to (mismo patrón que usa
      // ExtensionItemCard._buildAndroid). Usar router.push también en
      // Android empujaba una ruta que nada mostraba: confirmado en vivo,
      // "Ver detalle" no hacía nada ahí aunque en PC sí funcionaba.
      //
      // ── Por qué NO se le pasa el `context` de este widget ───────────────
      //
      // Este `context` es el del ENCABEZADO DEL LECTOR, y arriba se acaba de
      // cerrar ese lector. Para cuando corre este callback, ese widget puede
      // estar ya desmontado — y `openExtensionDetail` arranca con un
      // `if (!context.mounted) return;`, así que en ese caso se cancelaba
      // sola, EN SILENCIO: el lector se cerraba, la ficha nunca se abría, y
      // quien tocó "Ver detalle" quedaba mirando lo que hubiera debajo (la
      // Biblioteca, el Inicio). Reportado en vivo: "me manda a biblioteca en
      // vez de a los detalles".
      //
      // Era una carrera, por eso a veces funcionaba: la animación de cierre
      // tarda, y un solo frame de espera muchas veces alcanzaba para que el
      // widget siguiera montado. Pero `openExtensionDetail` además hace un
      // `await` (consulta si la extensión tiene una actualización pendiente)
      // ANTES de comprobar `mounted`, así que cualquier demora ahí la perdía.
      // Y saltando de una obra a otra desde una burbuja la ruta vieja se saca
      // de una, sin animación: ahí la perdía siempre.
      //
      // `currentContext` (router.dart) es un getter vivo que devuelve el
      // contexto de navegación de ESTE momento, por plataforma (el de GetX en
      // Android, el del shell en escritorio) — no depende de que el lector
      // que se acaba de cerrar siga en pie.
      ExtensionUtils.openExtensionDetail(
        currentContext,
        package: package,
        url: url,
      );
    });
  }

  Widget _buildAndroid(BuildContext context) {
    // ── El fondo va POR FUERA del SafeArea ────────────────────────────────
    //
    // Antes el Container pintado estaba adentro, así que el color empezaba
    // recién debajo de la barra de estado / la cámara. Leyendo a pantalla
    // completa —donde la página sí se dibuja hasta el borde— arriba de la
    // barra quedaba una franja de manga suelta, como si la barra estuviera
    // despegada del techo (reportado en vivo con captura).
    //
    // Dado vuelta, el color llega hasta el borde de la pantalla y el
    // SafeArea de adentro sigue bajando el contenido lo que haga falta: el
    // título y los iconos nunca quedan debajo de la cámara. Es el único
    // cambio; los márgenes de los costados siguen siendo los de antes.
    return Container(
      // ── La barra del lector SIGUE al modo ────────────────────────────────
      //
      // Blanca en claro y oscura en oscuro, como el resto de la app. Lo que
      // se queda oscuro es la zona de lectura, que es donde va la página;
      // esto de acá es interfaz.
      //
      // Va puesto a mano igual, y ese era el problema: salía del tema
      // (scaffoldBackgroundColor para el fondo, y el color de texto del
      // AppBar para el título), y el AppBar de Material sobre una pantalla
      // que por dentro es oscura terminaba con el título ilegible.
      color: HomeTheme.cardSurface,
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: AppBar(
            backgroundColor: HomeTheme.cardSurface,
            // Pinta el título, la flecha de volver y los tres iconos de una.
            foregroundColor: HomeTheme.textPrimary,
            title: TituloExpandible(_c.title),
            actions: [
              // Las dos flechas van PRIMERO en la fila de acciones: son el
              // atajo más usado (seguir leyendo), así que quedan más a la
              // izquierda que ajustes/detalle/episodios.
              Obx(
                () => IconButton(
                  onPressed: _hayAnterior ? () => _irACapitulo(-1) : null,
                  tooltip: 'Capítulo anterior',
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
              ),
              Obx(
                () => IconButton(
                  onPressed: _haySiguiente ? () => _irACapitulo(1) : null,
                  tooltip: 'Capítulo siguiente',
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ),
              if (widget.buildSettings != null)
                IconButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      // Como el resto de las hojas de la app: esquinas
                      // redondeadas, agarradera arriba y un tope de ancho para
                      // que en una tablet no cruce de lado a lado. Estas dos
                      // eran las únicas que salían cuadradas y a pantalla
                      // completa, y se notaba.
                      backgroundColor: HomeTheme.cardSurface,
                      showDragHandle: true,
                      // ── Que se pueda subir hasta arriba ────────────────
                      //
                      // Sin `isScrollControlled`, Flutter le pone a la hoja
                      // un techo de 9/16 de la pantalla (56%) y NO se puede
                      // arrastrar más allá. En vertical eso alcanzaba justo,
                      // pero en horizontal son unos 200 puntos de alto: la
                      // lista de opciones quedaba cortada y no había forma
                      // de llegar a las de abajo. Reportado en vivo.
                      //
                      // Con esto la hoja puede crecer hasta donde haga
                      // falta, y `useSafeArea` es el tope: se frena debajo
                      // de la barra de estado en vez de meterse abajo de
                      // ella. El contenido ya trae su propio scroll (ver
                      // ComicReaderSettings / NovelReaderSettings), así que
                      // si aun así no entra, se desplaza.
                      isScrollControlled: true,
                      useSafeArea: true,
                      constraints: const BoxConstraints(maxWidth: 640),
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (context) => widget.buildSettings!(context),
                    );
                  },
                  icon: const Icon(Icons.settings),
                ),
              IconButton(
                onPressed: () => _goToDetail(context),
                tooltip: 'Ver detalle',
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: HomeTheme.cardSurface,
                    showDragHandle: true,
                    // Alta, pero no hasta arriba de todo: con la lista de una
                    // obra larga la hoja tapaba hasta la barra de estado y no se
                    // veía nada del lector que quedaba detrás, así que costaba
                    // entender que era una hoja y no otra pantalla.
                    constraints: BoxConstraints(
                      maxWidth: 640,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    // Sin esto la hoja se queda en la mitad de la pantalla y hay
                    // que arrastrarla antes de poder buscar el capítulo.
                    isScrollControlled: true,
                    builder: (context) {
                      return Obx(
                        () => PlayList(
                          title: _c.title,
                          list: _c.playList.map((e) => e.name).toList(),
                          selectIndex: _c.index.value,
                          onChange: (value) {
                            _c.index.value = value;
                            Get.back();
                          },
                        ),
                      );
                    },
                  );
                },
                icon: const Icon(Icons.list),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade();
  }

  Widget _buildDesktop(BuildContext context) {
    return Obx(() {
      // Las lecturas van ACÁ, en el cuerpo del Obx.
      //
      // Estaban dentro de un Builder anidado, y eso rompía la reactividad: el
      // builder de un Builder no corre cuando el Obx arma el árbol, corre
      // después, cuando ese hijo se construye. O sea que el Obx no llegaba a
      // ver ninguna lectura y GetX lo cortaba con "improper use of a GetX",
      // que era la pantalla negra con el texto en el medio al abrir un manga.
      //
      // El índice se comprueba igual: una ficha sin capítulos abre el lector
      // con la lista vacía, y sin esto reventaba con un RangeError.
      final lista = _c.playList;
      final i = _c.index.value;
      final episodio = (i >= 0 && i < lista.length) ? lista[i].name : '';
      // ── La barra del lector SIGUE al modo ───────────────────────────────
      //
      // Clara en claro y oscura en oscuro, como el resto de la app. Lo que se
      // queda oscuro es la zona donde va la página; esto de acá es interfaz.
      //
      // Va puesto a mano igual, y ese era el problema: el fondo salía del mica
      // de Fluent y el texto y los iconos de su tipografía, los dos siguiendo
      // el tema de Fluent y no el modo de la app. Sobre esta barra eso daba un
      // título que no se leía.
      //
      // El FluentTheme envuelve la barra entera para que el título, los iconos
      // y los botones de ventana tomen todos el mismo, en vez de ir pintando
      // uno por uno y olvidarse de alguno.
      return fluent.FluentTheme(
        data: fluent.FluentThemeData(
          brightness: ModoDeColor.claro ? Brightness.light : Brightness.dark,
        ),
        child: Container(
          width: double.infinity,
          height: 40,
          color: HomeTheme.cardSurface,
          // ── Centro de TODA la barra, no del grupo de botones ────────────
          //
          // Puesto adentro del Row de acciones, "al medio" terminaba siendo
          // el medio del CLUSTER de la derecha, no de la ventana entera —
          // corregido después de que el pedido original se malentendiera.
          // Un Stack con el Row de siempre abajo y esto flotando encima,
          // centrado contra el ANCHO TOTAL del Container, es la única forma
          // de que quede en el medio de verdad sin importar cuánto midan el
          // título o el resto de los íconos a los costados.
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Toda la barra mueve la ventana ────────────────────────
              //
              // Antes el arrastre estaba solo alrededor del TÍTULO, y con
              // eso agarraba en una franja mínima: en una fila centrada
              // verticalmente, esa zona mide lo que mide la letra (~20 px)
              // dentro de una barra de 40, y a lo ancho llega solo hasta
              // donde el título tiene espacio. O sea que había que acertarle
              // a una tira fina a la izquierda para poder mover la ventana.
              // Reportado en vivo.
              //
              // Esta capa cubre la barra ENTERA y va PRIMERA, o sea la más
              // de abajo del Stack: todo lo que se dibuja encima (los
              // botones, la cápsula de capítulos, los botones de ventana)
              // sigue recibiendo sus clics normalmente, porque se prueba
              // antes que esto. Lo que queda para acá es exactamente el
              // hueco entre medio — que es justo lo que tiene que mover la
              // ventana en cualquier barra de título.
              //
              // Y el doble clic para maximizar/restaurar viene incluido en
              // DragToMoveArea, así que ahora también funciona en toda la
              // barra en vez de solo sobre el título.
              const Positioned.fill(
                child: DragToMoveArea(child: SizedBox.expand()),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.back),
                      onPressed: () => RouterUtils.closeReader(context),
                    ),
                    const SizedBox(width: 16),
                    // El arrastre ya no va acá: lo cubre la capa de abajo,
                    // que agarra la barra entera (ver el comentario largo
                    // arriba). Dejarlo también acá solo agregaba un segundo
                    // detector de arrastre encima del mismo sitio.
                    Expanded(
                      child: TituloExpandible(
                        // Con separador: era `_c.title + episodio`, pegados sin nada
                        // en el medio, así que se leía «Una Carta De Amor Del
                        // FuturoCap. 2: …» como si fuera una sola palabra.
                        episodio.isEmpty ? _c.title : '${_c.title} · $episodio',
                        style: TextStyle(color: HomeTheme.textPrimary),
                      ),
                    ),
                    // Hueco reservado del ancho de la cápsula del medio, para
                    // que el título no se estire por debajo de ella en una
                    // ventana angosta — sin esto, un título largo terminaba
                    // tapado por los botones flotando encima.
                    const SizedBox(width: 96),
                    if (widget.buildSettings != null) ...[
                      fluent.FlyoutTarget(
                        controller: _settingFlayoutcontroller,
                        child: fluent.IconButton(
                          icon: const Icon(fluent.FluentIcons.settings),
                          onPressed: () {
                            // full: sin esto el flyout se anclaba pegado al botón de
                            // configuración (arriba a la derecha) — para un menú de
                            // elegir modo de lectura eso queda perdido/incómodo de
                            // leer. full le da todo el ancho de pantalla como
                            // constraints y deja que el propio contenido se
                            // posicione (ComicReaderSettings ya lo centra con
                            // Center en su rama de escritorio).
                            _settingFlayoutcontroller.showFlyout(
                              placementMode: fluent.FlyoutPlacementMode.full,
                              barrierColor:
                                  Colors.black.withValues(alpha: 0.35),
                              builder: (context) {
                                return widget.buildSettings!(context);
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    fluent.Tooltip(
                      message: 'Ver detalle',
                      child: fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.info),
                        onPressed: () => _goToDetail(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    fluent.FlyoutTarget(
                      controller: _playListFlayoutcontroller,
                      child: fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.collapse_menu),
                        onPressed: () {
                          _playListFlayoutcontroller.showFlyout(
                              // Centrada en la pantalla, no colgando del
                              // botón. Anclada al botón (arriba a la
                              // derecha) la lista quedaba pegada al techo y
                              // corrida a un costado — reportado en vivo:
                              // "no tan arriba, centrada". `full` le da
                              // toda la pantalla como espacio y deja que el
                              // contenido se ubique solo, que es lo mismo
                              // que ya hace el panel de ajustes de al lado.
                              placementMode: fluent.FlyoutPlacementMode.full,
                              barrierColor:
                                  Colors.black.withValues(alpha: 0.35),
                              builder: (context) {
                                // Con fondo propio, del modo. El flyout de Fluent es
                                // translúcido, así que sin esto la lista de capítulos
                                // quedaba flotando sobre la página de manga y se leía la
                                // una encima de la otra.
                                // ── Con tope de alto ────────────────────────
                                //
                                // PlayList arma un Column con la lista adentro
                                // de un Flexible, y este contenedor no le ponía
                                // ningún límite de alto: con una obra de
                                // muchos capítulos la lista se estiraba más
                                // allá de la ventana y se pasaba de largo.
                                // Reportado en vivo. Con el tope, la lista se
                                // desplaza por dentro y la tarjeta queda
                                // siempre entera y a la vista.
                                //
                                // Proporcional a la ventana, no un número
                                // fijo: la idea es que aproveche el alto de la
                                // pantalla —de arriba abajo— y solo se frene un
                                // poco antes del borde, no que quede una
                                // tarjetita chica en el medio (primer intento,
                                // con tope de 520: se veía corta y desaprovechaba
                                // toda la pantalla). Con muchos capítulos se
                                // desplaza por dentro.
                                final alto = MediaQuery.sizeOf(context).height;
                                final tope = (alto - 140).clamp(240.0, 900.0);
                                // Con `placementMode: full`, el flyout recibe la
                                // pantalla entera como espacio: es este Center
                                // el que decide dónde queda la tarjeta.
                                return Center(
                                  child: Container(
                                    width: 340,
                                    constraints:
                                        BoxConstraints(maxHeight: tope),
                                    decoration: BoxDecoration(
                                      color: HomeTheme.cardSurface,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: HomeTheme.border),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x66000000),
                                          blurRadius: 18,
                                          offset: Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Obx(
                                      () => PlayList(
                                        title: _c.title,
                                        list: _c.playList
                                            .map((e) => e.name)
                                            .toList(),
                                        selectIndex: _c.index.value,
                                        onChange: (value) {
                                          _c.index.value = value;
                                          router.pop();
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 138,
                      // La tercera copia de los mismos tres botones. Ver
                      // BotonesVentana. Toma el brillo del FluentTheme de
                      // esta barra, que es el del modo.
                      child: BotonesVentana(
                        brightness: fluent.FluentTheme.of(context).brightness,
                      ),
                    ),
                  ],
                ),
              ),
              // Antes iban sueltos, pegados al título y confundidos con el
              // resto de los íconos. Pedido explícito: al medio de TODA la
              // barra — no del grupo de botones — y con una identidad
              // visual propia, una cápsula con borde en vez de dos íconos
              // más en la fila.
              Obx(
                () => Container(
                  height: 38,
                  decoration: BoxDecoration(
                    border: Border.all(color: HomeTheme.border),
                    borderRadius: BorderRadius.circular(8),
                    color: HomeTheme.cardSurface,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 44,
                        child: fluent.Tooltip(
                          message: 'Capítulo anterior',
                          child: fluent.IconButton(
                            icon: const Icon(fluent.FluentIcons.previous,
                                size: 16),
                            onPressed:
                                _hayAnterior ? () => _irACapitulo(-1) : null,
                          ),
                        ),
                      ),
                      Container(width: 1, height: 22, color: HomeTheme.border),
                      SizedBox(
                        width: 44,
                        child: fluent.Tooltip(
                          message: 'Capítulo siguiente',
                          child: fluent.IconButton(
                            icon: const Icon(fluent.FluentIcons.next, size: 16),
                            onPressed:
                                _haySiguiente ? () => _irACapitulo(1) : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate().fade();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
