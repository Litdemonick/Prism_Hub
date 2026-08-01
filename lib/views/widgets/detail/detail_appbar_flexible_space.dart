import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/views/widgets/detail/detail_continue_play.dart';
import 'package:prismhub/views/widgets/detail/detail_extension_tile.dart';
import 'package:prismhub/views/widgets/detail/detail_favorite_button.dart';
import 'package:prismhub/views/widgets/detail/detail_share_button.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/cover.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

class DetailAppbarflexibleSpace extends StatefulWidget {
  const DetailAppbarflexibleSpace({
    super.key,
    this.tag,
    this.height = 400,
    this.landscape = false,
  });

  final String? tag;
  // Debe matchear el expandedHeight del SliverAppBar que la contiene.
  final double height;
  // En horizontal se arma un layout HORIZONTAL propio (portada a la
  // izquierda, texto+botones a la derecha) en vez de achicar el mismo
  // diseño vertical — con poca altura ese enfoque dejaba la portada
  // recortada y pegada contra el botón de atrás.
  final bool landscape;

  @override
  State<DetailAppbarflexibleSpace> createState() =>
      _DetailAppbarflexibleSpaceState();
}

class _DetailAppbarflexibleSpaceState extends State<DetailAppbarflexibleSpace> {
  late DetailPageController c = Get.find(tag: widget.tag);

  double _offset = 1;
  double _opacity = 1;

  @override
  void initState() {
    super.initState();
    c.scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    c.scrollController.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    _offset = c.scrollController.offset;
    final next = _scrollListener();
    if ((next - _opacity).abs() < 0.02) return;
    setState(() => _opacity = next);
  }

  // Distancia real de scroll en la que el SliverAppBar colapsa: el 300 fijo
  // de antes era razonable para el diseño vertical (400 de alto, colapsa en
  // ~296px), pero en horizontal (200 de alto, colapsa en ~96px) dejaba el
  // contenido todavía a mitad de fade (~23% opacidad) mucho DESPUÉS de que
  // la caja ya se había achicado del todo — confirmado en vivo: los
  // botones "Continuar"/"Favorito" quedaban semi-visibles, superpuestos
  // con el TabBar ya fijo arriba. Escalando la distancia de fade al alto
  // real del header, siempre llega a 0 justo cuando la caja termina de
  // colapsar.
  double get _fadeDistance => (widget.height - 104).clamp(50.0, 400.0);

  double _scrollListener() {
    final fadeDistance = _fadeDistance;
    if (_offset <= 0) {
      return 1;
    } else if (_offset >= fadeDistance) {
      return 0;
    } else {
      return (_offset - fadeDistance) / (0 - fadeDistance);
    }
  }

  bool _needShowCover() {
    if (c.isLoading.value) return true;
    if (c.data.value?.cover != null) return true;
    return false;
  }

  Widget _background() {
    return Stack(
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: c.isLoading.value
              ? const SizedBox.shrink()
              : Cover(
                  alt: c.data.value?.title ?? '',
                  url: c.backgorund,
                  noText: true,
                  headers: c.detail?.headers,
                  // 0.35 (hacia abajo) recortaba de más la parte de arriba
                  // de la imagen de fondo — subido a 0 para mostrar más
                  // esa zona en vez de sesgar hacia el centro/abajo.
                  alignment: const Alignment(0, 0),
                ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x3308090D),
                  Color(0xE608090D),
                  HomeTheme.bg,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coverThumb({required double height, required double width}) {
    return Hero(
      tag: c.heroTag ?? '',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HomeTheme.border),
        ),
        child: SizedBox(
          height: height,
          width: width,
          child: c.isLoading.value
              ? const Center(
                  child: CircularProgressIndicator(
                    color: HomeTheme.accentPink,
                  ),
                )
              : CacheNetWorkImagePic(
                  c.data.value?.cover ?? '',
                  fit: BoxFit.cover,
                  // topCenter: en la miniatura chica, BoxFit.cover con el
                  // alignment por defecto (center) recortaba parejo arriba
                  // y abajo — cortando la parte de arriba de la portada
                  // (cara/cabeza, lo más reconocible). Sesgado hacia arriba
                  // se ve más completa esa zona.
                  alignment: Alignment.topCenter,
                  headers: c.detail?.headers,
                  canFullScreen: true,
                ),
        ),
      ),
    );
  }

  Widget _buildPortrait() {
    // Escala proporcional al 400 de diseño original (hoy en vertical
    // siempre es 400, pero se deja general por si cambia).
    final scale = widget.height / 400;
    final coverThumbHeight = (150 * scale).clamp(0.0, 150.0);
    final coverThumbWidth = coverThumbHeight * (100 / 150);
    // 170 (antes 105, luego 130): confirmado en vivo que seguía quedando
    // bajo, con mucho espacio vacío arriba entre la toolbar y la portada —
    // subido más para centrarla mejor en el hueco libre entre la toolbar
    // (termina ~104) y el TabBar (empieza en el último tramo del hero).
    final titleRowBottom = 170 * scale;
    // 65 (antes 40): quedaban casi pegados contra el TabBar de abajo —
    // confirmado en vivo, se veían encimados. Más aire.
    final buttonsRowBottom = 65 * scale;

    return Stack(
      children: [
        _background(),
        Positioned(
          left: 20,
          bottom: titleRowBottom,
          right: 20,
          child: Row(
            children: [
              if (_needShowCover())
                _coverThumb(height: coverThumbHeight, width: coverThumbWidth),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.isLoading.value ? "" : c.data.value!.title,
                        softWrap: true,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: HomeTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DetailExtensionTile(tag: widget.tag),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: buttonsRowBottom,
          child: Row(
            children: [
              // 50/50 recortaba "Continuar Capítulo 30" con "..." — el
              // texto es bastante más largo que "Favorito", así que le
              // toca más lugar real en vez de partir el ancho parejo.
              Expanded(flex: 3, child: DetailContinuePlay(tag: widget.tag)),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: DetailFavoriteButton(tag: widget.tag)),
              const SizedBox(width: 12),
              // Compartir la obra. Va acá y no en el menú: es una acción que
              // se busca a propósito, no algo escondido.
              DetailShareButton(tag: widget.tag),
            ],
          ),
        ),
      ],
    );
  }

  // Layout horizontal propio para landscape: portada a la IZQUIERDA (usa
  // el ancho de sobra), título+extensión+botones en una columna a la
  // derecha — en vez de achicar el diseño vertical (que con poca altura
  // dejaba la portada recortada, pegada contra el botón de atrás de la
  // toolbar, y los botones pegados contra el TabBar de abajo sin aire).
  Widget _buildLandscape() {
    // Corregido tras leer el source de Flutter (app_bar.dart): el toolbar y
    // el TabBar (bottom:) NO quedan pegados juntos arriba — van en un
    // Column con mainAxisAlignment.spaceBetween que ocupa TODO el alto
    // actual del SliverAppBar, así que el toolbar queda arriba (0-56) y el
    // TabBar queda ABAJO DE TODO (últimos 48px), con el medio libre para el
    // flexibleSpace. La versión anterior asumía el TabBar pegado debajo del
    // toolbar y dejaba el contenido empezando más abajo de la cuenta —
    // chocando de lleno contra el TabBar real, que está al final.
    const toolbarHeight = 56.0;
    const tabBarHeight = 48.0;
    const topGap = 8.0;
    const bottomGap = 8.0;
    final contentHeight =
        (widget.height - toolbarHeight - tabBarHeight - topGap - bottomGap)
            .clamp(36.0, 100.0);
    final thumbHeight = contentHeight.clamp(36.0, 80.0);
    final thumbWidth = thumbHeight * (100 / 150);

    return Stack(
      children: [
        _background(),
        Positioned(
          top: toolbarHeight + topGap,
          // 56 (antes 20): la portada quedaba justo debajo/detrás del
          // botón de atrás (leading de la toolbar, arriba a la izquierda)
          // — corrida a la derecha, más allá de su ancho.
          left: 56,
          right: 20,
          bottom: tabBarHeight + bottomGap,
          // Ahora que "bottom:" está bien calculado (ver comentario de
          // arriba), la franja libre real es más alta — centrado se ve
          // mejor que pegado arriba.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_needShowCover())
                _coverThumb(height: thumbHeight, width: thumbWidth),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  c.isLoading.value ? "" : c.data.value!.title,
                  softWrap: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: HomeTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 260 (antes 180): con 180 el texto "Continuar Capítulo 30"
              // se recortaba con "..." — justo la info que el botón tiene
              // que mostrar. Hay ancho real de sobra en horizontal (se ve
              // el hueco vacío entre el título corto y los botones), así
              // que ensancharlos no le quita lugar a nada.
              SizedBox(
                width: 260,
                child: DetailContinuePlay(tag: widget.tag),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: DetailFavoriteButton(tag: widget.tag),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Opacity(
        opacity: _opacity,
        child: widget.landscape ? _buildLandscape() : _buildPortrait(),
      ),
    );
  }
}
