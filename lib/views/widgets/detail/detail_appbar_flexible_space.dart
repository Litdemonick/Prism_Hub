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
import 'package:prismhub/views/widgets/boton_pulsable.dart';

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
    // Todo el bloque se apoya en el BORDE DE ABAJO y crece hacia arriba, en vez
    // de colgar cada pieza de una distancia fija.
    //
    // Antes el titulo y la fila de botones eran dos Positioned con numeros
    // calculados a mano sobre un alto de 400 (170 y 65, por una escala). Con
    // eso nada podia crecer: el titulo quedaba clavado a dos lineas con puntos
    // suspensivos aunque hubiera lugar, y los botones caian donde caian —
    // apretados contra el texto en unos telefonos y sueltos en otros. Cada
    // ajuste era volver a tocar esos numeros a ojo.
    //
    // Con una columna anclada abajo, cada pieza ocupa lo que necesita y el aire
    // entre ellas es el mismo en cualquier pantalla. El titulo ahora entra en
    // tres lineas: es lo primero que uno quiere leer y venia cortado.
    final coverThumbHeight = (150 * (widget.height / 400)).clamp(0.0, 150.0);
    final coverThumbWidth = coverThumbHeight * (100 / 150);

    return Stack(
      children: [
        _background(),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_needShowCover())
                    _coverThumb(
                        height: coverThumbHeight, width: coverThumbWidth),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          left: _needShowCover() ? 16 : 0, bottom: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.isLoading.value ? "" : c.data.value!.title,
                            softWrap: true,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              // 26 era mucho para un titulo largo en un
                              // telefono: comia dos lineas enteras con pocas
                              // palabras. 21 deja entrar bastante mas texto sin
                              // dejar de ser el titulo de la pantalla.
                              fontSize: 21,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: HomeTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DetailExtensionTile(tag: widget.tag),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  // 50/50 recortaba "Continuar Capitulo 30" con "..." — el
                  // texto es bastante mas largo que "Favorito", asi que le
                  // toca mas lugar real en vez de partir el ancho parejo.
                  // BotonPulsable: los botones no daban ninguna señal al
                  // tocarlos, y en el telefono eso lleva a tocar dos veces.
                  Expanded(
                    flex: 3,
                    child: BotonPulsable(
                        child: DetailContinuePlay(tag: widget.tag)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: BotonPulsable(
                        child: DetailFavoriteButton(tag: widget.tag)),
                  ),
                  const SizedBox(width: 2),
                  // Compartir la obra. Va aca y no en el menu: es una accion que
                  // se busca a proposito, no algo escondido. Compacto porque la
                  // fila ya la ocupan "Continuar" y "Favorito".
                  BotonPulsable(
                    child: DetailShareButton(tag: widget.tag, compacto: true),
                  ),
                ],
              ),
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
              // Faltaba en el diseño horizontal: estaba solo en el vertical.
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DetailShareButton(tag: widget.tag, compacto: true),
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
