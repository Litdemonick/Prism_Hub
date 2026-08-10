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
      ExtensionUtils.openExtensionDetail(
        context,
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
            title: Text(_c.title),
            actions: [
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
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.back),
                onPressed: () => RouterUtils.closeReader(context),
              ),
              const SizedBox(width: 16),
              // DragToMoveArea only on the title text — buttons stay outside
              // so clicking them never accidentally drags the window.
              Expanded(
                child: DragToMoveArea(
                  child: Text(
                    // Con separador: era `_c.title + episodio`, pegados sin nada
                    // en el medio, así que se leía «Una Carta De Amor Del
                    // FuturoCap. 2: …» como si fuera una sola palabra.
                    episodio.isEmpty ? _c.title : '${_c.title} · $episodio',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: HomeTheme.textPrimary),
                  ),
                ),
              ),
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
                        barrierColor: Colors.black.withValues(alpha: 0.35),
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
                    _playListFlayoutcontroller.showFlyout(builder: (context) {
                      // Con fondo propio, del modo. El flyout de Fluent es
                      // translúcido, así que sin esto la lista de capítulos
                      // quedaba flotando sobre la página de manga y se leía la
                      // una encima de la otra.
                      return Container(
                        width: 300,
                        decoration: BoxDecoration(
                          color: HomeTheme.cardSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: HomeTheme.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Obx(
                          () => PlayList(
                            title: _c.title,
                            list: _c.playList.map((e) => e.name).toList(),
                            selectIndex: _c.index.value,
                            onChange: (value) {
                              _c.index.value = value;
                              router.pop();
                            },
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
                // BotonesVentana. Toma el brillo del FluentTheme de esta barra,
                // que es el del modo.
                child: BotonesVentana(
                  brightness: fluent.FluentTheme.of(context).brightness,
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
