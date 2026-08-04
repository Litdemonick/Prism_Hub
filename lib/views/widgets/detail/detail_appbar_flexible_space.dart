import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/views/widgets/detail/detail_continue_play.dart';
import 'package:prismhub/views/widgets/detail/detail_extension_tile.dart';
import 'package:prismhub/views/widgets/detail/detail_favorite_button.dart';
import 'package:prismhub/views/widgets/detail/detail_share_button.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/cover.dart';
import 'package:prismhub/views/widgets/detail/portada_con_relevo.dart';
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
    // Se desvanece en el primer 55% del recorrido, no en todo.
    //
    // Llegando a 0 justo al final, el titulo y los botones seguian visibles a
    // media opacidad cuando ya estaban encima de la barra de pestañas: se veian
    // los dos textos superpuestos y quedaba sucio. Terminando antes, el bloque
    // ya no esta para cuando las piezas se cruzan.
    final fadeDistance = _fadeDistance * 0.55;
    if (_offset <= 0) {
      return 1;
    } else if (_offset >= fadeDistance) {
      return 0;
    } else {
      return (_offset - fadeDistance) / (0 - fadeDistance);
    }
  }

  /// Ancho por cada unidad de alto de la miniatura: la proporción real de las
  /// portadas de esta extensión. Ver DetailPageController.portadaProporcion.
  double get _proporcionPortada => c.portadaProporcion;

  bool _needShowCover() {
    if (c.isLoading.value) return true;
    if (c.portada != null) return true;
    return false;
  }

  Widget _background() {
    return Stack(
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          // Ya no se esconde mientras carga: con la portada que traía la
          // tarjeta hay algo que mostrar desde el primer fotograma, y el
          // relevo se encarga de que el cambio a la definitiva no se note.
          child: PortadaConRelevo(
            alt: c.data.value?.title ?? '',
            urlPrevia: c.portadaPrevia,
            cabecerasPrevias: c.portadaPreviaHeaders,
            urlFinal: c.portada,
            cabecerasFinales: c.portadaHeaders,
            noText: true,
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Antes acá había una rueda ocupando toda la miniatura hasta que
              // la extensión contestara. Ahora se dibuja de una la portada que
              // traía la tarjeta, y la rueda pasa a ser una señal chica en la
              // esquina: sigue diciendo que falta algo, pero sin tapar lo que
              // ya se puede ver.
              PortadaConRelevo(
                alt: c.data.value?.title ?? '',
                urlPrevia: c.portadaPrevia,
                cabecerasPrevias: c.portadaPreviaHeaders,
                urlFinal: c.portada,
                cabecerasFinales: c.portadaHeaders,
                // topCenter: en la miniatura chica, BoxFit.cover con el
                // alignment por defecto (center) recortaba parejo arriba
                // y abajo — cortando la parte de arriba de la portada
                // (cara/cabeza, lo más reconocible). Sesgado hacia arriba
                // se ve más completa esa zona.
                alignment: Alignment.topCenter,
                canFullScreen: true,
                // Red de seguridad: la caja ya toma la forma que publica la
                // extensión, pero un título suelto puede traer una portada de
                // otra forma. Así se ve entera igual, con el resto de la caja
                // rellenado con la misma imagen desenfocada.
                entera: true,
              ),
              if (c.isLoading.value)
                const Positioned(
                  right: 6,
                  bottom: 6,
                  child: _RuedaChica(),
                ),
            ],
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
    final coverThumbWidth = coverThumbHeight * _proporcionPortada;

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
                            // 4 lineas (antes 3): hay titulos largos que a tres
                            // lineas seguian cortandose con puntos suspensivos,
                            // y el titulo es lo primero que uno quiere leer.
                            maxLines: 4,
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
              const SizedBox(height: 14),
              // Dos filas, no una.
              //
              // Con los tres botones en la misma fila no entraba ninguna
              // etiqueta entera en un telefono: "Continuar Episodio 1" salia
              // como "Continuar Epis..." y "Favorito" se partia en dos lineas
              // ("Favorit" y abajo "o"). Repartir el ancho de otra forma no
              // alcanzaba —los dos textos juntos no entran— asi que "Continuar"
              // se queda con la fila entera, que ademas es la accion principal,
              // y abajo van "Favorito" y compartir.
              //
              // BotonPulsable: los botones no daban ninguna señal al tocarlos, y
              // en el telefono eso lleva a tocar dos veces.
              SizedBox(
                width: double.infinity,
                child:
                    BotonPulsable(child: DetailContinuePlay(tag: widget.tag)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BotonPulsable(
                        child: DetailFavoriteButton(tag: widget.tag)),
                  ),
                  const SizedBox(width: 10),
                  // Compartir la obra. Va aca y no en el menu: es una accion que
                  // se busca a proposito, no algo escondido.
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
    final thumbWidth = thumbHeight * _proporcionPortada;

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
                  // Dos lineas: en horizontal el titulo comparte fila con los
                  // botones y con una sola se cortaba casi siempre. El ancho
                  // que le faltaba sale de hacer compactos Favorito y
                  // Compartir, que decian con palabras lo que su icono ya
                  // dice.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    height: 1.15,
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
              // Este SI conserva su texto: dice en que capitulo se quedo,
              // que es informacion y no una etiqueta.
              SizedBox(
                width: 230,
                child: BotonPulsable(
                  child: DetailContinuePlay(tag: widget.tag),
                ),
              ),
              const SizedBox(width: 10),
              // Compactos los dos: en esta fila cada punto de ancho que no
              // usan es ancho que gana el titulo.
              BotonPulsable(
                child: DetailFavoriteButton(tag: widget.tag, compacto: true),
              ),
              BotonPulsable(
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

/// La señal de "todavía falta algo", en la esquina de la portada.
///
/// Chica y con un fondo oscuro detrás a propósito: va encima de una imagen que
/// ya se ve, así que tiene que leerse sobre cualquier portada sin taparla.
/// Antes, mientras cargaba, una rueda grande ocupaba la miniatura entera y no
/// se veía nada más.
class _RuedaChica extends StatelessWidget {
  const _RuedaChica();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: HomeTheme.accentPink,
        ),
      ),
    );
  }
}
