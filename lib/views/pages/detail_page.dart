import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/detail/detail_finished_button.dart';
import 'package:prismhub/data/providers/tmdb_provider.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/views/widgets/detail/detail_appbar_flexible_space.dart';
import 'package:prismhub/views/widgets/detail/detail_appbar_back.dart';
import 'package:prismhub/views/widgets/detail/detail_appbar_title.dart';
import 'package:prismhub/views/widgets/detail/detail_continue_play.dart';
import 'package:prismhub/views/widgets/detail/detail_background_color.dart';
import 'package:prismhub/views/widgets/detail/detail_episodes.dart';
import 'package:prismhub/views/widgets/detail/detail_extension_tile.dart';
import 'package:prismhub/views/widgets/detail/detail_favorite_button.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/pages/detail_page_tv.dart';
import 'package:prismhub/views/widgets/detail/detail_share_button.dart';
import 'package:prismhub/views/widgets/detail/detail_overview.dart';
import 'package:prismhub/views/widgets/detail/portada_con_relevo.dart';
import 'package:prismhub/utils/forma_portada.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/detail/detail_card_tile.dart';
import 'package:prismhub/views/widgets/detail/detail_tracking_button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:url_launcher/url_launcher.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.url,
    required this.package,
    this.tag,
    this.isAdultOption = false,
  });
  final String url;
  final String package;
  final String? tag;
  final bool isAdultOption;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late DetailPageController c;

  @override
  void initState() {
    c = Get.put(
      DetailPageController(
        package: widget.package,
        url: widget.url,
        heroTag: widget.tag,
        isAdultOption: widget.isAdultOption,
      ),
      tag: widget.tag,
    );
    super.initState();
  }

  @override
  void dispose() {
    Get.delete<DetailPageController>(
      tag: widget.tag,
    );
    super.dispose();
  }

  // Funde entre los tres estados de la pantalla —error, cargando y contenido—
  // en vez de cambiarlos de golpe.
  //
  // Antes el salto era seco: la rueda desaparecía y en el mismo fotograma
  // aparecía la pantalla entera armada, con la portada, el título y las
  // pestañas de una. Se notaba como un parpadeo, sobre todo cuando la
  // extensión responde rápido y la rueda apenas alcanza a verse.
  //
  // Todos los caminos tienen que devolver ESTO desde la misma posición del
  // árbol: así Flutter reutiliza el mismo AnimatedSwitcher entre
  // reconstrucciones y lo único que le cambia es la clave del hijo, que es lo
  // que dispara la animación. Devolver un AnimatedSwitcher nuevo por rama no
  // animaría nada.
  static Widget _transicion(String estado, Widget hijo) => AnimatedSwitcher(
        // Corto a propósito: es para suavizar el cambio, no para hacer
        // esperar.
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(key: ValueKey(estado), child: hijo),
      );

  /// La ficha todavía está cargando.
  ///
  /// Antes era una rueda sola sobre el fondo, y con una extensión lenta eso son
  /// segundos de pantalla vacía después de haber tocado una tarjeta que SÍ
  /// tenía imagen — medido en HQPorner: casi un segundo solo en que conteste la
  /// extensión. Se veía como que la app se colgó.
  ///
  /// Ahora se dibuja de entrada la portada de esa tarjeta, oscurecida para que
  /// la rueda se lea encima. Cuando la ficha real aparece, la misma imagen ya
  /// está ahí y el cambio no salta.
  Widget _pantallaCargando(BuildContext context) {
    final previa = c.portadaPrevia;
    return ColoredBox(
      color: HomeTheme.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previa != null) ...[
            CacheNetWorkImagePic(
              previa,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              headers: c.portadaPreviaHeaders,
            ),
            // Velo oscuro: la portada es solo un acompañamiento mientras se
            // espera, no el contenido. Sin esto, sobre una imagen clara la
            // rueda no se distingue.
            const Positioned.fill(
              child: ColoredBox(color: Color(0xCC08090D)),
            ),
          ],
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(HomeTheme.accentPink),
                  ),
                ),
                // Y si tarda de más, se dice en vez de girar sin fin. Ver
                // tardaDemasiado en el controlador: es la misma idea que en la
                // fila de la búsqueda, y va igual en celular y en escritorio
                // porque quien decide es el controlador, no cada pantalla.
                Obx(() => c.tardaDemasiado.value
                    ? Padding(
                        padding:
                            const EdgeInsets.only(top: 18, left: 32, right: 32),
                        child: Text(
                          FlutterI18n.translate(
                            context,
                            'common.extension-lenta',
                            translationParams: {
                              's': c.runtime.value?.extension.name ??
                                  'La extensión',
                            },
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: HomeTheme.textMuted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          // Botón de volver propio: mientras carga no existe todavía el
          // SliverAppBar que lo trae, y una extensión lenta dejaba la pantalla
          // sin salida visible.
          if (Platform.isAndroid)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  // Con la portada previa detrás, el fondo es el velo oscuro
                  // de arriba y no el de la app: ahí va blanca en los dos
                  // modos. Sin portada el fondo sí es el de la app y sigue al
                  // modo. Con textPrimary a secas, en modo claro la flecha
                  // quedaba casi negra sobre el velo — invisible, y es la
                  // única salida mientras carga.
                  icon: Icon(
                    Icons.arrow_back,
                    color: previa != null
                        ? HomeTheme.sobrePortada
                        : HomeTheme.textPrimary,
                  ),
                  // Navigator directo, no RouterUtils: esta rama es solo
                  // Android, donde la página se empuja con Get.to sobre el
                  // navegador de GetMaterialApp.
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// La ficha no se pudo cargar.
  ///
  /// Antes era el texto del error, solo, centrado y sin nada más. Con un corte
  /// de internet eso dejaba en pantalla el mensaje crudo de la librería de red,
  /// en inglés y hablando de RequestOptions.connectTimeout — que además de no
  /// decirle nada a nadie, parece que se rompió la app. Y no había forma de
  /// volver a intentar: había que salir de la ficha y entrar de nuevo.
  ///
  /// Es la misma en Windows, Linux y Android: los tres llegan acá por el mismo
  /// camino y el problema es el mismo en los tres.
  Widget _pantallaDeError(BuildContext context) {
    return ColoredBox(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Obx(() => Icon(
                        // Sin internet y "la fuente falló" no son lo mismo y no
                        // se arreglan igual, así que tampoco se dibujan igual.
                        c.errorEsDeConexion.value
                            ? Icons.wifi_off_rounded
                            : Icons.error_outline_rounded,
                        size: 48,
                        color: HomeTheme.textMuted,
                      )),
                  const SizedBox(height: 16),
                  Obx(() => Text(
                        c.error.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: HomeTheme.textPrimary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      )),
                  const SizedBox(height: 20),
                  PlatformFilledButton(
                    onPressed: c.reintentar,
                    child: Text('common.retry'.i18n),
                  ),
                ],
              ),
            ),
          ),
          // Botón de volver propio, igual que en el estado "cargando": en este
          // estado tampoco existe todavía el SliverAppBar que lo trae, así que
          // la pantalla quedaba sin salida a la vista.
          if (Platform.isAndroid)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: HomeTheme.textPrimary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAndroidDetail(BuildContext context) {
    return Scaffold(
      // La acción principal, siempre a la vista.
      //
      // Estaba dentro de la cabecera, así que se desvanecía con ella: uno baja
      // a mirar la lista, decide, y el botón de leer ya no estaba. Acá se
      // queda puesto, no se lleva alto de la cabecera —que en un teléfono en
      // vertical es lo que falta— y vale igual en las tres formas de la
      // pantalla. Cuando no hay nada que abrir no se dibuja: ver
      // DetailContinuePlay.comoFab.
      floatingActionButton: Obx(() {
        if (c.error.value.isNotEmpty || c.isLoading.value) {
          return const SizedBox.shrink();
        }
        return DetailContinuePlay(tag: widget.tag, comoFab: true);
      }),
      body: Obx(() {
        if (c.error.value.isNotEmpty) {
          return _transicion('error', _pantallaDeError(context));
        }

        // Android no miraba isLoading (escritorio sí, más abajo): armaba la
        // pantalla entera de una con el detalle todavía en null, así que se
        // veía el hero vacío, el título en blanco y las pestañas sin nada
        // hasta que llegaba la respuesta de la extensión. Ahora espera igual
        // que en PC: rueda girando y recién después la info.
        if (c.isLoading.value) {
          return _transicion('cargando', _pantallaCargando(context));
        }

        // LayoutBuilder y no MediaQuery a secas: lo que importa es el tamaño
        // que la ficha tiene DE VERDAD para trabajar. Con la app en pantalla
        // partida o en una ventana chica de Android, la pantalla mide una cosa
        // y la ficha otra.
        //
        // Y el ValueListenableBuilder es por la forma de las portadas:
        // FormaPortada decide por catálogo y tarda cuatro portadas en hacerlo.
        // Si se resuelve con la ficha abierta, avisa por `revision` — sin
        // escucharla, la caja se quedaba con la forma equivocada hasta salir y
        // volver a entrar.
        return ValueListenableBuilder<int>(
          valueListenable: FormaPortada.revision,
          builder: (context, _, __) => LayoutBuilder(
            builder: (context, constraints) => _transicion(
              'listo',
              _fichaArmada(context, constraints.biggest),
            ),
          ),
        );
      }),
    );
  }

  /// La ficha ya cargada, armada para el tamaño que hay.
  ///
  /// Dos formas, y las dos salen del ancho medido en el momento:
  ///
  /// - **Un panel** (teléfono en vertical): cabecera, pestañas y debajo la
  ///   lista de capítulos o la sinopsis.
  /// - **Dos paneles** (tablet, y también el teléfono acostado): la ficha a la
  ///   izquierda y la lista de capítulos a la derecha, entera y con todo el
  ///   alto. En horizontal esto es la diferencia entre ver dos capítulos y ver
  ///   la lista completa.
  Widget _fichaArmada(BuildContext context, Size tamano) {
    final episodesString = c.type == ExtensionType.bangumi
        ? 'video.episodes'.i18n
        : 'reader.chapters'.i18n;

    // Antes esto salía de LayoutUtils.isTablet, que mide el ancho UNA vez y lo
    // guarda para toda la sesión: al rotar seguía contestando lo de antes, así
    // que un aparato que arrancó en vertical dibujaba el diseño angosto sobre
    // una pantalla apaisada, y uno que arrancó acostado quedaba con dos
    // paneles al ponerlo derecho. Ese cacheado NO se toca —lo usa el
    // reproductor para otra decisión— pero acá se mide en vivo.
    //
    // No alcanza con el ancho. Una tablet de 10" en vertical (800x1280) pasa
    // los 720 y partirla en dos deja la ficha en 368 puntos: la portada baja a
    // 95x137, más chica que en un teléfono. Así que se parte cuando la
    // pantalla es ancha para lo alta que es —el caso de acostado, que es donde
    // hace falta— o cuando hay tanto ancho que las dos mitades siguen siendo
    // holgadas.
    //
    // Y hay un tercer caso, que es el que faltaba: la PANTALLA BAJA. Con menos
    // de 480 puntos de alto no entra apilar cabecera, pestañas y lista de
    // ninguna manera — el contenido queda espachurrado abajo y, apenas se
    // desplaza, se mete debajo de la barra: se veía el botón «Reproducir»
    // partido al medio por las pestañas. Ahí la lista tiene que ir al costado,
    // donde se queda con el alto entero y sin ninguna barra encima que la
    // pueda tapar. Con 560 de ancho ya alcanza para partir, aunque no llegue a
    // los 720 de la regla de arriba.
    final dosPaneles = tamano.width >= 1000 ||
        (tamano.width >= 720 && tamano.width >= tamano.height * 0.9) ||
        (tamano.height < 480 && tamano.width >= 560);

    final tabs = [
      if (!dosPaneles) Tab(text: episodesString),
      Tab(text: 'detail.overview'.i18n),
      if (c.type == ExtensionType.bangumi) Tab(text: 'detail.cast'.i18n),
    ];
    // Una sola pestaña no es una pestaña: es un rótulo que se lleva 48 puntos
    // de alto sin ofrecer nada que elegir. Pasa con dos paneles en lectura,
    // donde los capítulos ya están al costado y solo queda la sinopsis.
    final hayPestanas = tabs.length > 1;

    // Con dos paneles, la ficha se queda con algo más de la mitad: la lista de
    // capítulos son etiquetas cortas y le alcanza con menos, y de ese ancho de
    // más sale que el título entre entero al lado de la portada. El techo de
    // 600 es para pantallas grandes, donde la mitad de 1600 sería una columna
    // absurdamente ancha para una portada y un título.
    // El piso baja a 300 (antes 320) para que en una ventana chica y baja el
    // panel de los capítulos no quede en una rendija: a 560 de ancho, 300 acá
    // le dejan 259 al de al lado, que es lo mínimo para una tarjeta.
    final anchoFicha =
        dosPaneles ? (tamano.width * 0.52).clamp(300.0, 600.0) : tamano.width;

    final medidas = MedidasCabecera(
      disponible: Size(
        anchoFicha,
        tamano.height - MediaQuery.paddingOf(context).top,
      ),
      proporcionPortada: c.portadaProporcion,
      reservaInferior: hayPestanas ? 48 : 0,
    );

    // El alto libre debajo de la cabecera desplegada. De acá sale si cada
    // pestaña necesita desplazamiento o no.
    final relleno = MediaQuery.paddingOf(context);
    final espacioLibre = tamano.height -
        relleno.top -
        relleno.bottom -
        medidas.alto -
        (hayPestanas ? 48 : 0);

    // Una entrada por pestaña, en el mismo orden: si su contenido entra sin
    // plegar la cabecera, ahí la pantalla no se desplaza.
    final entraCadaPestana = <bool>[
      if (!dosPaneles) _capitulosEntran(context, anchoFicha, espacioLibre),
      _sinopsisEntra(context, anchoFicha, espacioLibre),
      // El reparto es una lista de largo desconocido: nunca se bloquea.
      if (c.type == ExtensionType.bangumi) false,
    ];

    bool sinScroll(int pestana) =>
        pestana >= 0 &&
        pestana < entraCadaPestana.length &&
        entraCadaPestana[pestana];

    final ficha = DefaultTabController(
      length: tabs.length,
      child: _SegunLaPestana(
        alCambiar: (pestana) => _volverArribaSiNoHayScroll(sinScroll(pestana)),
        builder: (context, pestana) => NestedScrollView(
          controller: c.scrollController,
          // El tope que faltaba: si la lista entra sin plegar la cabecera, la
          // pantalla no se desplaza. Con un capítulo solo se podía seguir
          // bajando hasta dejar la cabecera plegada y la pantalla casi vacía,
          // sin nada que ver más abajo.
          //
          // Solo en la pestaña de capítulos, que es la única cuyo alto se
          // puede contar exacto. La sinopsis puede ser larguísima y bloquearla
          // por error escondería texto, que es peor que un desplazamiento de
          // sobra.
          physics:
              sinScroll(pestana) ? const NeverScrollableScrollPhysics() : null,
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return [
              SliverAppBar(
                pinned: true,
                floating: false,
                snap: false,
                primary: true,
                // El tema de la app deja TODAS las barras transparentes
                // (appBarTheme.backgroundColor). Acá eso se nota: al hacer
                // scroll, el cuerpo de la página pasa por debajo de la barra y
                // se veía la lista de capítulos cruzando por encima del botón de
                // atrás. Con el fondo puesto, la barra tapa lo que pasa debajo.
                backgroundColor: HomeTheme.bg,
                surfaceTintColor: Colors.transparent,
                // Flecha propia: la automática toma el color del tema, o sea
                // el de la barra PLEGADA, y desplegada queda sobre la portada.
                // En modo claro eso daba una flecha casi negra encima de una
                // imagen oscura. Ver DetailAppbarBack.
                leading: DetailAppbarBack(
                  controller: c.scrollController,
                  desde: medidas.relevoDelTitulo,
                  onVolver: () => Navigator.of(context).maybePop(),
                ),
                title: DetailAppbarTitle(
                  c.detail?.title ?? '',
                  controller: c.scrollController,
                  desde: medidas.relevoDelTitulo,
                ),
                flexibleSpace: DetailAppbarflexibleSpace(
                  tag: widget.tag,
                  medidas: medidas,
                ),
                bottom: hayPestanas
                    ? PreferredSize(
                        preferredSize: const Size.fromHeight(48),
                        // Fondo sólido: el TabBar es transparente por defecto —
                        // sin esto, una franja de la portada/imagen del hero se
                        // veía asomando (recortada, fea) justo arriba de las
                        // pestañas en vez de quedar tapada prolijamente.
                        child: Container(
                          color: HomeTheme.bg,
                          // Sin estilar, TabBar usa los colores por defecto de
                          // Material: el indicador sale MORADO —el color semilla
                          // del tema, que no es el del app— y debajo queda una
                          // línea divisoria GRIS que Material 3 dibuja sola. Las
                          // dos cruzaban la ficha de lado a lado y no pegaban con
                          // nada del diseño.
                          child: TabBar(
                            tabs: tabs,
                            indicatorColor: HomeTheme.accentPink,
                            labelColor: HomeTheme.textPrimary,
                            unselectedLabelColor: HomeTheme.textMuted,
                            // La franja de arriba ya la da el Container de acá,
                            // así que la divisoria solo agregaba una raya suelta.
                            dividerColor: Colors.transparent,
                            indicatorSize: TabBarIndicatorSize.label,
                          ),
                        ),
                      )
                    : null,
                // Favorito y compartir viven acá, no en la cabecera. En la
                // cabecera se plegaban con el scroll —justo cuando uno ya está
                // mirando la lista— y encima cada uno tenía su propia forma y su
                // propio alto. Acá los tres son iconos de barra: miden lo mismo,
                // se alinean solos y están siempre a mano.
                actions: [
                  // ── El botón solo cuando el gesto NO puede ──────────────
                  //
                  // En Android se refresca deslizando hacia abajo, así que el
                  // botón sobra y se sacó. Pero hay un caso en el que el gesto
                  // no existe: cuando el contenido entra sin plegar la
                  // cabecera, la pantalla se bloquea a propósito (ver
                  // `physics`) y sin arrastre no hay nada que dispare el
                  // refresco. Pasa en las fichas de un solo capítulo.
                  //
                  // Sacando el botón sin mirar eso, esas fichas se quedaban sin
                  // ninguna forma de ponerse al día. Así que aparece justo ahí
                  // y en ningún otro lado.
                  if (sinScroll(pestana)) _botonRefrescar(),
                  DetailFavoriteButton(tag: widget.tag, compacto: true),
                  DetailShareButton(tag: widget.tag, compacto: true),
                  DetailTrackingButton(
                    tag: widget.tag,
                  ),
                  const SizedBox(width: 4),
                ],
                expandedHeight: medidas.alto,
              ),
            ];
          },
          body: SafeArea(
            top: false,
            child: TabBarView(
              children: [
                if (!dosPaneles) DetailEpisodes(tag: widget.tag),
                DetailOverView(
                  tag: widget.tag,
                  onAlto: _anotarAltoSinopsis,
                ),
                if (c.type == ExtensionType.bangumi) _repartoAndroid(context),
              ],
            ),
          ),
        ),
      ),
    );

    if (!dosPaneles) return _conRefresco(ficha);

    return Row(
      children: [
        SizedBox(width: anchoFicha, child: _conRefresco(ficha)),
        VerticalDivider(width: 1, thickness: 1, color: HomeTheme.border),
        // El panel de capítulos se queda con todo el alto, incluida la franja
        // de la barra de estado — de ahí el SafeArea, que antes no estaba y
        // dejaba el primer capítulo debajo del reloj.
        Expanded(
          child: SafeArea(
            left: false,
            child: DetailEpisodes(tag: widget.tag),
          ),
        ),
      ],
    );
  }

  /// ¿La lista de capítulos entra sin tener que plegar la cabecera?
  ///
  /// Si entra, la pantalla no se desplaza (ver `physics`, más arriba): con un
  /// capítulo solo se podía seguir bajando hasta dejar la cabecera plegada y
  /// la pantalla casi vacía.
  ///
  /// Ante la duda se contesta que NO entra. Bloquear el desplazamiento de más
  /// escondería contenido —y eso es peor que un desplazamiento de sobra— así
  /// que cada alto va estimado por lo ALTO (68 por capítulo es una tarjeta de
  /// dos líneas más su separación, el caso más grande) y encima se pide un
  /// margen de 48 puntos.
  bool _capitulosEntran(
      BuildContext context, double anchoFicha, double espacioLibre) {
    final grupos = c.detail?.episodes;
    if (grupos == null || grupos.isEmpty) return false;
    final indice = c.selectEpGroup.value;
    if (indice < 0 || indice >= grupos.length) return false;
    final urls = grupos[indice].urls;
    if (urls.isEmpty) return false;

    // Con muchos capítulos no entra ni por asomo, y medir uno por uno solo
    // tiene sentido mientras la cuenta pueda dar justa.
    if (urls.length > 40) return false;

    final alto = GeometriaCapitulos.altoDeLaLista(
      context: context,
      ancho: anchoFicha,
      etiquetas: [for (final u in urls) DetailEpisodes.etiquetaDe(u.name)],
      enGrilla: c.type == ExtensionType.bangumi,
      hayGrupos: grupos.length > 1,
    );
    if (alto == null) return false;
    // 8 de margen y no 48: las alturas ya no se estiman, se miden con la misma
    // geometría con la que se dibuja la lista. El margen grande de antes hacía
    // que la cuenta diera "no entra" casi siempre y no se bloqueara nada.
    return alto + 8 <= espacioLibre;
  }

  /// Lo mismo para la pestaña de sinopsis.
  /// Envuelve la ficha con el gesto de deslizar hacia abajo para refrescar.
  ///
  /// ── El choque con el tope del scroll, y cómo se resuelve ────────────────
  ///
  /// Cuando el contenido entra sin plegar la cabecera, la pantalla se bloquea
  /// a propósito (ver `physics`, arriba). Pero ese gesto es el MISMO que el de
  /// refrescar: sin arrastre no hay nada que lo dispare, así que en esas
  /// fichas —las de un solo capítulo— deslizar no haría nada.
  ///
  /// Por eso el refresco también vive como botón en la barra, en las dos
  /// plataformas. El gesto es el camino natural cuando la ficha se desplaza; el
  /// botón es el que siempre está.
  Widget _conRefresco(Widget hijo) {
    return RefreshIndicator(
      onRefresh: c.refrescarAMano,
      color: HomeTheme.accentPink,
      backgroundColor: HomeTheme.cardSurface,
      // Debajo de la barra, no encima: arriba de todo la rueda queda tapada
      // por el título y la flecha de volver.
      edgeOffset: MediaQuery.paddingOf(context).top + 56,
      child: hijo,
    );
  }

  /// El botón de refrescar, para cuando el gesto de deslizar no aplica.
  Widget _botonRefrescar() {
    return Obx(() {
      // Mientras carga no se ofrece: ya está trayendo lo mismo que pediría.
      if (c.isLoading.value) return const SizedBox.shrink();
      return IconButton(
        tooltip: 'common.refresh'.i18n,
        // Encima de la portada. Ver HomeTheme.sobrePortada.
        color: HomeTheme.sobrePortada,
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => unawaited(c.refrescarAMano()),
      );
    });
  }

  /// El alto REAL de la pestaña de sinopsis, medido por ella misma.
  ///
  /// Ver [DetailOverView.onAlto]. La estimación solo sabía contestar con la
  /// sinopsis pelada: en cuanto hay datos de TMDB —que en vídeo es casi
  /// siempre— se rendía, y esta pestaña no se bloqueaba nunca.
  double? _altoSinopsis;

  void _anotarAltoSinopsis(double alto) {
    if (!mounted) return;
    final anterior = _altoSinopsis;
    if (anterior != null && (anterior - alto).abs() < 1) return;
    setState(() => _altoSinopsis = alto);
  }

  bool _sinopsisEntra(
      BuildContext context, double anchoFicha, double espacioLibre) {
    // La medida de verdad manda; llega después del primer dibujado. Hasta
    // entonces se usa la estimación, que es conservadora.
    final alto =
        _altoSinopsis ?? DetailOverView.altoEstimado(context, anchoFicha, c);
    // null es "no se puede saber" — ver DetailOverView.altoEstimado. Ahí se da
    // por hecho que no entra: bloquear el desplazamiento por error escondería
    // texto, y eso es peor que un desplazamiento de sobra.
    if (alto == null) return false;
    // 8 y no 48: esto ya no se estima, se mide.
    return alto + 8 <= espacioLibre;
  }

  /// Al entrar a una pestaña que no se puede desplazar, la pantalla no puede
  /// quedarse a medio plegar: se vuelve arriba sola.
  void _volverArribaSiNoHayScroll(bool sinScroll) {
    if (!sinScroll) return;
    final controlador = c.scrollController;
    if (!controlador.hasClients || controlador.offset <= 0) return;
    // Después del fotograma: esto sale de un aviso del TabController, en plena
    // reconstrucción, y mover el scroll ahí mismo es pedir problemas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controlador.hasClients) return;
      controlador.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// La pestaña de reparto (solo vídeo, y solo si TMDB devolvió algo).
  Widget _repartoAndroid(BuildContext context) {
    return Obx(() {
      if (c.tmdbDetail == null || c.tmdbDetail!.casts.isEmpty) {
        // ── Centrado y con scroll, no colgado de un hueco fijo ────────────
        //
        // Antes era un Column con 100 puntos de relleno arriba y sin nada que
        // lo dejara desplazarse. En una pantalla baja eso no entra: el texto
        // quedaba cortado contra las pestañas y sin márgenes, pegado a los dos
        // bordes. Se reportó con captura.
        //
        // Centrado ocupa lo que hay, y con el scroll de respaldo nunca se
        // desborda por chica que sea la caja.
        return LayoutBuilder(
          builder: (context, cons) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (cons.maxHeight - 40).clamp(0.0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'detail.no-tmdb-data'.i18n,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: HomeTheme.textMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      c.modifyTMDBBinding();
                    },
                    child: Text(
                      'detail.modify-tmdb-binding'.i18n,
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      }
      return ListView.builder(
        // El mismo hueco de abajo que la lista de capítulos: el botón flotante
        // se apoya en esa esquina y tapaba al último del reparto.
        padding: const EdgeInsets.only(bottom: 88),
        itemBuilder: (context, index) {
          final cast = c.tmdbDetail!.casts[index];
          late String url = '';
          if (cast.profilePath != null) {
            url = TmdbApi.getImageUrl(cast.profilePath!) ?? '';
          }

          return ListTile(
            leading: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: CacheNetWorkImagePic(
                url,
                width: 50,
                height: 50,
                headers: c.detail?.headers,
              ),
            ),
            title: Text(cast.name),
            subtitle: Text(cast.character),
            onTap: () {
              launchUrl(
                Uri.parse(
                  "https://www.themoviedb.org/person/${cast.id}",
                ),
              );
            },
          );
        },
        itemCount: c.tmdbDetail!.casts.length,
      );
    });
  }

  /// Las acciones de la ficha en escritorio: favorito, compartir y refrescar.
  ///
  /// En una tarjeta con fondo propio y no sueltos sobre la portada: encima de
  /// una imagen clara, tres iconos blancos no se leen.
  Widget _barraDeAcciones() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailFavoriteButton(tag: widget.tag, compacto: true),
          DetailShareButton(tag: widget.tag, compacto: true),
          Obx(() {
            // Mientras carga no se ofrece: ya está trayendo lo mismo que
            // pediría. En el teléfono este botón no está —ahí se refresca
            // deslizando— pero en escritorio ese gesto no existe.
            if (c.isLoading.value) return const SizedBox.shrink();
            return fluent.IconButton(
              icon: const Icon(fluent.FluentIcons.refresh, size: 16),
              onPressed: () => unawaited(c.refrescarAMano()),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDesktopDetail(BuildContext context) {
    return Obx(() {
      if (c.error.value.isNotEmpty) {
        return _transicion('error', _pantallaDeError(context));
      }

      if (c.isLoading.value) {
        return _transicion('cargando', _pantallaCargando(context));
      }
      // Nombrado y no devuelto directo: envolver el Stack entero en la llamada
      // reindentaría sus trescientas y pico de líneas por un cambio de dos.
      final contenido = Stack(
        children: [
          RepaintBoundary(
            child: PortadaConRelevo(
              alt: c.detail?.title ?? '',
              urlPrevia: c.portadaPrevia,
              cabecerasPrevias: c.portadaPreviaHeaders,
              urlFinal: c.backgorund,
              cabecerasFinales: c.portadaHeaders,
              noText: true,
              alignment: const Alignment(0, 0.35),
            ),
          ),
          Positioned.fill(
            child: DetailBackgroundColor(controller: c.scrollController),
          ),
          Positioned.fill(child: LayoutBuilder(
            builder: (context, constraints) {
              // El aire de arriba y el alto del bloque salen de la ventana, no
              // de dos números fijos. Con 300 de aire más 330 de bloque, en una
              // ventana de 700 de alto la ficha entera arrancaba fuera de la
              // pantalla: había que desplazar para ver hasta el título. Y en un
              // monitor grande sobraba fondo vacío arriba.
              final altoVentana = constraints.maxHeight;
              final aireArriba = (altoVentana * 0.34).clamp(120.0, 320.0);
              final altoHero = (altoVentana * 0.44).clamp(240.0, 400.0);
              // Mismo criterio que en el teléfono: el título crece con el
              // bloque en vez de quedar clavado en 30.
              final tamanoTitulo = (altoHero * 0.09).clamp(24.0, 34.0);
              return SingleChildScrollView(
                controller: c.scrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth > 1200 ? 150 : 20,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    SizedBox(height: aireArriba),
                    SizedBox(
                      height: altoHero,
                      child: Row(
                        children: [
                          // c.portada y no c.detail!.cover: si la extensión no
                          // devolvió portada pero la tarjeta que se tocó sí
                          // tenía una, se usa esa. Antes esta condición dejaba
                          // la ficha SIN póster —el hueco quedaba de color
                          // liso— y pasa de verdad: la de HQPorner se rinde a
                          // los 1200 ms y devuelve la ficha sin imagen.
                          if (c.portada != null)
                            if (constraints.maxWidth > 600) ...[
                              // Anclada abajo, como el texto de al lado: la
                              // apaisada es más baja que la caja y centrada
                              // quedaría flotando a media altura.
                              Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    // Con la proporción real de las portadas
                                    // de esta extensión, así la imagen llena
                                    // el hueco sin franjas ni recortes. Ver
                                    // DetailPageController.portadaProporcion.
                                    //
                                    // Las verticales se miden desde el alto y
                                    // las apaisadas desde el ancho: al revés,
                                    // una apaisada saldría enorme y una
                                    // vertical, minúscula.
                                    width: c.portadaApaisada
                                        ? altoHero * 0.97
                                        : altoHero * c.portadaProporcion,
                                    height: c.portadaApaisada
                                        ? altoHero * 0.97 / c.portadaProporcion
                                        : altoHero,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: HomeTheme.cardSurface,
                                      borderRadius: BorderRadius.circular(12),
                                      border:
                                          Border.all(color: HomeTheme.border),
                                      // La misma sombra que en el teléfono: la
                                      // portada va sobre su propia imagen
                                      // ampliada y sin esto el borde se pierde
                                      // en las portadas oscuras.
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x99000000),
                                          blurRadius: 24,
                                          offset: Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: PortadaConRelevo(
                                      alt: c.detail?.title ?? '',
                                      urlPrevia: c.portadaPrevia,
                                      cabecerasPrevias: c.portadaPreviaHeaders,
                                      urlFinal: c.portada,
                                      cabecerasFinales: c.portadaHeaders,
                                      canFullScreen: true,
                                      // Red de seguridad por si un título
                                      // suelto trae otra forma.
                                      entera: true,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 30),
                            ],
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SelectableText(
                                c.detail?.title ?? '',
                                // 3 líneas (antes 2): con dos, los títulos
                                // largos se cortaban teniendo lugar de sobra
                                // al lado de la portada.
                                maxLines: 3,
                                style: TextStyle(
                                  fontSize: tamanoTitulo,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  color: HomeTheme.textPrimary,
                                  // Igual que en el teléfono: el título va
                                  // sobre la propia portada ampliada y sobre
                                  // una imagen clara se comía con el fondo.
                                  shadows: const [
                                    Shadow(
                                        color: Color(0xCC000000),
                                        blurRadius: 14),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              DetailExtensionTile(tag: widget.tag),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  // Favorito, compartir y refrescar YA NO van
                                  // acá: se fueron a la barra de arriba, como
                                  // en el teléfono (ver _barraDeAcciones).
                                  // Eran cuatro botones anchos con texto
                                  // cruzando la portada, y tres de ellos decían
                                  // con palabras lo que el icono ya dice.
                                  // Se oculta solo en películas — ver
                                  // DetailFinishedButton.
                                  DetailFinishedButton(tag: widget.tag),
                                  const SizedBox(width: 8),
                                  DetailTrackingButton(
                                    tag: widget.tag,
                                  ),
                                  const SizedBox(width: 8),

                                  if (c.tmdbDetail != null)
                                    fluent.Button(
                                      style: fluent.ButtonStyle(
                                        backgroundColor:
                                            fluent.WidgetStateProperty.all(
                                          HomeTheme.cardSurface,
                                        ),
                                        foregroundColor:
                                            fluent.WidgetStateProperty.all(
                                          HomeTheme.textPrimary,
                                        ),
                                        shape: fluent.WidgetStateProperty.all(
                                          RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            side: BorderSide(
                                                color: HomeTheme.border),
                                          ),
                                        ),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.only(
                                            left: 10,
                                            right: 10,
                                            top: 5,
                                            bottom: 5),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text("TMDB"),
                                            SizedBox(width: 8),
                                            Icon(fluent.FluentIcons.pop_expand,
                                                size: 14)
                                          ],
                                        ),
                                      ),
                                      onPressed: () {
                                        launchUrl(
                                          Uri.parse(
                                            "https://www.themoviedb.org/${c.tmdbDetail!.mediaType}/${c.tmdbDetail!.id}",
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ],
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (c.detail?.episodes != null)
                      DetailEpisodes(tag: widget.tag),
                    const SizedBox(height: 16),
                    Obx(
                      () {
                        if (c.tmdbDetail == null ||
                            c.tmdbDetail!.backdrop == null) {
                          return const SizedBox();
                        }
                        final images = [
                          c.tmdbDetail!.backdrop!,
                          ...c.tmdbDetail!.images
                        ];
                        return fluent.Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DetailCardTile(
                            title: 'tmdb.backdrops'.i18n,
                            child: SizedBox(
                              height: 300,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemBuilder: (context, index) {
                                  final image = images[index];
                                  final url = TmdbApi.getImageUrl(image);
                                  if (url == null) {
                                    return const SizedBox();
                                  }
                                  return Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    margin: const EdgeInsets.only(right: 8),
                                    child: CacheNetWorkImagePic(
                                      url,
                                      height: 200,
                                      canFullScreen: true,
                                    ),
                                  );
                                },
                                itemCount: images.length,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Obx(
                      () {
                        if (c.tmdbDetail == null ||
                            c.tmdbDetail!.casts.isEmpty) {
                          return const SizedBox();
                        }
                        return fluent.Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DetailCardTile(
                            title: 'detail.cast'.i18n,
                            child: SizedBox(
                              height: 150,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemBuilder: (context, index) {
                                  final cast = c.tmdbDetail!.casts[index];
                                  String? url;
                                  if (cast.profilePath != null) {
                                    url =
                                        TmdbApi.getImageUrl(cast.profilePath!);
                                  }
                                  return MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () {
                                        launchUrl(
                                          Uri.parse(
                                            "https://www.themoviedb.org/person/${cast.id}}",
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding:
                                            const EdgeInsets.only(right: 16),
                                        width: 170,
                                        child: Column(
                                          children: [
                                            Container(
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: CacheNetWorkImagePic(
                                                url ?? '',
                                                width: 100,
                                                height: 100,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              cast.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: HomeTheme.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              cast.character,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: HomeTheme.textMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                itemCount: c.tmdbDetail!.casts.length,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Obx(
                      () {
                        final desc = c.tmdbDetail?.overview ?? c.detail?.desc;
                        final hasDesc = desc != null && desc.isNotEmpty;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DetailCardTile(
                            title: "detail.overview".i18n,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: SelectableText(
                                hasDesc ? desc : "detail.no-description".i18n,
                                style: TextStyle(
                                  height: 2,
                                  color: hasDesc
                                      ? HomeTheme.textPrimary
                                      : HomeTheme.textMuted,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Obx(
                      () {
                        if (c.tmdbDetail == null) {
                          return const SizedBox();
                        }
                        return DetailCardTile(
                          title: 'detail.additional-info'.i18n,
                          child: Wrap(children: [
                            ...[
                              _buildInfoTile(
                                context,
                                'tmdb.status'.i18n,
                                c.tmdbDetail!.status,
                              ),
                              _buildInfoTile(
                                context,
                                'tmdb.genres'.i18n,
                                c.tmdbDetail!.genres.join(', '),
                              ),
                              _buildInfoTile(
                                context,
                                'tmdb.languages'.i18n,
                                c.tmdbDetail!.languages.join(', '),
                              ),
                              _buildInfoTile(
                                context,
                                'tmdb.release-date'.i18n,
                                c.tmdbDetail!.releaseDate,
                              ),
                              _buildInfoTile(
                                context,
                                'tmdb.original-title'.i18n,
                                c.tmdbDetail!.originalTitle,
                              ),
                              _buildInfoTile(
                                context,
                                'tmdb.runtime'.i18n,
                                c.tmdbDetail!.runtime.toString(),
                              ),
                            ].map((e) => SizedBox(
                                  width: 200,
                                  child: e,
                                )),
                          ]),
                        );
                      },
                    )
                  ],
                ),
              );
            },
          )),
          // ── Las acciones, arriba a la derecha ────────────────────────
          //
          // Estaban dentro del hero, en una fila de botones anchos con texto
          // cruzando la portada. Tres de ellos —favorito, compartir,
          // refrescar— decían con palabras exactamente lo que su icono ya
          // dice, y encima se iban con el desplazamiento justo cuando uno ya
          // está mirando la lista de capítulos.
          //
          // Arriba y fijos, como en el teléfono: los tres miden lo mismo, se
          // alinean solos y están siempre a mano. Lo que se queda abajo es lo
          // que NO se puede resumir en un icono («marcar como finalizada») o
          // lo que abre otra pantalla (el seguimiento).
          Positioned(
            top: 8,
            right: 12,
            child: _barraDeAcciones(),
          ),
        ],
      );
      return _transicion('listo', contenido);
    });
  }

  /// La ficha de TV: dos paneles fijos, hecha de cero (ver detail_page_tv).
  ///
  /// Los estados de error y carga se comparten con las otras plataformas —
  /// son pantallas centradas sin nada que navegar, así que no hace falta una
  /// versión distinta.
  Widget _buildTvDetail(BuildContext context) {
    return Obx(() {
      if (c.error.value.isNotEmpty) {
        return _transicion('error', _pantallaDeError(context));
      }
      if (c.isLoading.value) {
        return _transicion('cargando', _pantallaCargando(context));
      }
      return _transicion(
        'contenido',
        DetailTV(c: c, tag: widget.tag),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // TV primero: un Android TV sigue siendo `Platform.isAndroid`, así que
    // sin esto PlatformBuildWidget lo manda a la ficha de teléfono.
    if (PlatformTv.esTelevisionSync) return _buildTvDetail(context);
    return PlatformBuildWidget(
      androidBuilder: _buildAndroidDetail,
      desktopBuilder: _buildDesktopDetail,
    );
  }
}

/// Rearma a su hijo cuando cambia la pestaña visible — y SOLO entonces.
///
/// De la pestaña activa depende si la pantalla se puede desplazar o no, así
/// que hay que enterarse del cambio. Escuchando la animación del TabController
/// se reconstruiría en cada fotograma del deslizamiento, que es tirar trabajo:
/// acá se compara el índice y se avisa una sola vez.
class _SegunLaPestana extends StatefulWidget {
  const _SegunLaPestana({required this.builder, this.alCambiar});

  final Widget Function(BuildContext context, int pestana) builder;
  final void Function(int pestana)? alCambiar;

  @override
  State<_SegunLaPestana> createState() => _SegunLaPestanaState();
}

class _SegunLaPestanaState extends State<_SegunLaPestana> {
  TabController? _tab;
  int _indice = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nuevo = DefaultTabController.of(context);
    if (identical(nuevo, _tab)) return;
    _tab?.removeListener(_alCambiar);
    _tab = nuevo..addListener(_alCambiar);
    _indice = nuevo.index;
  }

  void _alCambiar() {
    final actual = _tab?.index ?? 0;
    if (actual == _indice) return;
    setState(() => _indice = actual);
    widget.alCambiar?.call(actual);
  }

  @override
  void dispose() {
    _tab?.removeListener(_alCambiar);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _indice);
}

_buildInfoTile(BuildContext context, String title, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: HomeTheme.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      SelectableText(
        value,
        style: TextStyle(color: HomeTheme.textMuted),
      ),
      const SizedBox(height: 16)
    ],
  );
}
