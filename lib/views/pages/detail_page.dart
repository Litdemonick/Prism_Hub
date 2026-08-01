import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/views/widgets/detail/detail_finished_button.dart';
import 'package:prismhub/data/providers/tmdb_provider.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/views/widgets/detail/detail_appbar_flexible_space.dart';
import 'package:prismhub/views/widgets/detail/detail_appbar_title.dart';
import 'package:prismhub/views/widgets/detail/detail_background_color.dart';
import 'package:prismhub/views/widgets/detail/detail_episodes.dart';
import 'package:prismhub/views/widgets/detail/detail_extension_tile.dart';
import 'package:prismhub/views/widgets/detail/detail_favorite_button.dart';
import 'package:prismhub/views/widgets/detail/detail_share_button.dart';
import 'package:prismhub/views/widgets/detail/detail_overview.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/cover.dart';
import 'package:prismhub/views/widgets/detail/detail_card_tile.dart';
import 'package:prismhub/views/widgets/detail/detail_tracking_button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/boton_pulsable.dart';
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

  Widget _buildAndroidDetail(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        late String episodesString;
        if (c.type == ExtensionType.bangumi) {
          episodesString = 'video.episodes'.i18n;
        } else {
          episodesString = 'reader.chapters'.i18n;
        }

        if (c.error.value.isNotEmpty) {
          return _transicion('error', Center(child: Text(c.error.value)));
        }

        // Android no miraba isLoading (escritorio sí, más abajo): armaba la
        // pantalla entera de una con el detalle todavía en null, así que se
        // veía el hero vacío, el título en blanco y las pestañas sin nada
        // hasta que llegaba la respuesta de la extensión. Ahora espera igual
        // que en PC: rueda girando y recién después la info.
        if (c.isLoading.value) {
          return _transicion(
              'cargando',
              ColoredBox(
                color: HomeTheme.bg,
                child: Stack(
                  children: [
                    const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation(HomeTheme.accentPink),
                      ),
                    ),
                    // Botón de volver propio: mientras carga no existe todavía
                    // el SliverAppBar que lo trae, y una extensión lenta dejaba
                    // la pantalla sin salida visible.
                    SafeArea(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: HomeTheme.textPrimary),
                          // Navigator directo, no RouterUtils: esta rama es solo
                          // Android, donde la página se empuja con Get.to sobre
                          // el navegador de GetMaterialApp.
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ));
        }

        final tabs = [
          if (!LayoutUtils.isTablet) Tab(text: episodesString),
          Tab(text: 'detail.overview'.i18n),
          if (c.type == ExtensionType.bangumi) Tab(text: 'detail.cast'.i18n),
        ];

        // Fijo en 400 tapaba casi toda la pantalla en horizontal sin dejar
        // lugar para capítulos/sinopsis debajo. En vez de solo achicar el
        // mismo diseño vertical (portada arriba, texto+botones apilados
        // abajo — con poca altura eso dejaba la portada recortada y pegada
        // al botón de atrás), en horizontal el hero pasa a un layout
        // HORIZONTAL propio (ver DetailAppbarflexibleSpace.landscape):
        // portada a la izquierda, título+botones a la derecha, usando el
        // ancho de sobra en vez de pelear por la poca altura.
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        // 440 en vertical (antes 400): los botones pasaron a dos filas para que
        // las etiquetas entren enteras, y el titulo a cuatro lineas porque los
        // largos se cortaban. Con 400 ese bloque se desbordaba hacia arriba y
        // se metia debajo del boton de atras.
        //
        // Llego a estar en 470 con los botones de 50 de alto. Bajados a 42 y
        // con menos aire entre filas, el bloque ocupa 30 menos: dejarlo en 470
        // seria un encabezado innecesariamente alto que empuja los episodios
        // fuera de la pantalla.
        final heroHeight = isLandscape ? 200.0 : 440.0;

        final content = DefaultTabController(
          length: tabs.length,
          child: NestedScrollView(
            controller: c.scrollController,
            headerSliverBuilder:
                (BuildContext context, bool innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  pinned: true,
                  floating: false,
                  snap: false,
                  primary: true,
                  title: DetailAppbarTitle(
                    c.detail?.title ?? '',
                    controller: c.scrollController,
                  ),
                  flexibleSpace: DetailAppbarflexibleSpace(
                    tag: widget.tag,
                    height: heroHeight,
                    landscape: isLandscape,
                  ),
                  // Fondo sólido: el TabBar es transparente por defecto —
                  // sin esto, una franja de la portada/imagen del hero se
                  // veía asomando (recortada, fea) justo arriba de las
                  // pestañas en vez de quedar tapada prolijamente.
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
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
                        // La franja de arriba ya la da el Container de acá, así
                        // que la divisoria solo agregaba una raya suelta.
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.label,
                      ),
                    ),
                  ),
                  actions: [
                    // DetailTrackingButton
                    DetailTrackingButton(
                      tag: widget.tag,
                    ),
                  ],
                  expandedHeight: heroHeight,
                ),
              ];
            },
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: SafeArea(
                top: false,
                child: TabBarView(
                  children: [
                    if (!LayoutUtils.isTablet)
                      DetailEpisodes(
                        tag: widget.tag,
                      ),
                    DetailOverView(
                      tag: widget.tag,
                    ),
                    if (c.type == ExtensionType.bangumi)
                      Obx(() {
                        if (c.tmdbDetail == null ||
                            c.tmdbDetail!.casts.isEmpty) {
                          return Column(
                            children: [
                              const SizedBox(height: 100),
                              Text('detail.no-tmdb-data'.i18n),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: () {
                                  c.modifyTMDBBinding();
                                },
                                child: Text(
                                  'detail.modify-tmdb-binding'.i18n,
                                ),
                              )
                            ],
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.all(0),
                          itemBuilder: (context, index) {
                            final cast = c.tmdbDetail!.casts[index];
                            late String url = '';
                            if (cast.profilePath != null) {
                              url =
                                  TmdbApi.getImageUrl(cast.profilePath!) ?? '';
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
                      }),
                  ],
                ),
              ),
            ),
          ),
        );
        if (LayoutUtils.isTablet) {
          return Row(
            children: [
              Expanded(child: content),
              Expanded(
                child: SafeArea(
                    child: DetailEpisodes(
                  tag: widget.tag,
                )),
              ),
            ],
          );
        }
        return _transicion('listo', content);
      }),
    );
  }

  Widget _buildDesktopDetail(BuildContext context) {
    return Obx(() {
      if (c.error.value.isNotEmpty) {
        return _transicion(
            'error',
            ColoredBox(
              color: HomeTheme.bg,
              child: Center(
                child: Text(
                  c.error.value,
                  style: const TextStyle(color: HomeTheme.textPrimary),
                ),
              ),
            ));
      }

      if (c.isLoading.value) {
        return _transicion(
            'cargando',
            const ColoredBox(
              color: HomeTheme.bg,
              child: Center(
                child: fluent.ProgressRing(activeColor: HomeTheme.accentPink),
              ),
            ));
      }
      // Nombrado y no devuelto directo: envolver el Stack entero en la llamada
      // reindentaría sus trescientas y pico de líneas por un cambio de dos.
      final contenido = Stack(
        children: [
          RepaintBoundary(
            child: Cover(
              alt: c.detail?.title ?? '',
              url: c.backgorund,
              noText: true,
              headers: c.detail?.headers,
              alignment: const Alignment(0, 0.35),
            ),
          ),
          Positioned.fill(
            child: DetailBackgroundColor(controller: c.scrollController),
          ),
          Positioned.fill(child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: c.scrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth > 1200 ? 150 : 20,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 300),
                    SizedBox(
                      height: 330,
                      child: Row(
                        children: [
                          if (c.detail!.cover != null)
                            if (constraints.maxWidth > 600) ...[
                              Container(
                                width: 230,
                                height: double.infinity,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: HomeTheme.cardSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: HomeTheme.border),
                                ),
                                child: CacheNetWorkImagePic(
                                  c.detail?.cover ?? '',
                                  headers: c.detail?.headers,
                                  canFullScreen: true,
                                ),
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
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: HomeTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              DetailExtensionTile(tag: widget.tag),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  // 收藏按钮
                                  // Ver BotonPulsable: la misma señal al
                                  // tocar que en el telefono.
                                  BotonPulsable(
                                      child: DetailFavoriteButton(
                                          tag: widget.tag)),
                                  const SizedBox(width: 8),
                                  BotonPulsable(
                                      child:
                                          DetailShareButton(tag: widget.tag)),
                                  const SizedBox(width: 8),
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
                                            side: const BorderSide(
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
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: HomeTheme.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              cast.character,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
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
          ))
        ],
      );
      return _transicion('listo', contenido);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroidDetail,
      desktopBuilder: _buildDesktopDetail,
    );
  }
}

_buildInfoTile(BuildContext context, String title, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: HomeTheme.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      SelectableText(
        value,
        style: const TextStyle(color: HomeTheme.textMuted),
      ),
      const SizedBox(height: 16)
    ],
  );
}
