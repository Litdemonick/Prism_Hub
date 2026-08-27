import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/relleno_borroso.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

// Tarjeta de medio — calca el spec exacto del diseño (MediaCard.dc.html):
// 180x250, radio 14, degradado de fondo si no hay portada, badge arriba a
// la izquierda, barra de progreso abajo si corresponde, título+subtítulo
// debajo en una sola línea con ellipsis.
// Margen entre la portada mostrada entera y el borde del marco. Ver el
// comentario donde se usa: sin él la imagen toca los bordes y parece cortada.
double _coverInset = 8;

// Borde dibujado ENCIMA del contenido, como última capa del Stack. Puesto en
// la decoración del Container que recorta la portada, el propio recorte lo
// pisaba y en las esquinas redondeadas la línea desaparecía a trozos. Como
// capa de arriba queda entera y del color correcto.
//
// ── Ya no es del color de la zona ───────────────────────────────────────
//
// Era rosa —el acento— alrededor de CADA tarjeta. Con una grilla llena, eso
// son treinta recuadros rosas gritando a la vez y la portada, que es lo único
// que importa mirar, queda en segundo plano. Lo que hacía falta era separar
// una tarjeta de la de al lado, no pintarlas.
//
// Ahora es la misma línea gris que usan las demás superficies de la app
// (HomeTheme.border). Separa igual y no compite con nada. El acento sigue
// estando donde de verdad significa algo: la barra de progreso, la tilde de lo
// elegido, el puntito del filtro.
Widget _bordeCard(double radio) {
  return Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radio),
          // Una línea fina: solo tiene que decir dónde termina la tarjeta.
          border: Border.all(color: HomeTheme.border),
        ),
      ),
    ),
  );
}

// Arte de respaldo (portada que no cargó, o card ocultada por el usuario)
// mostrado ENTERO pero sin caja oscura detrás: el fondo es la misma imagen
// ampliada y desenfocada, igual que se hace con las portadas. Con contain
// sobre un ColoredBox quedaba como un logo chico dentro de un recuadro, y con
// cover a pantalla completa se le cortaban las puntas —el logo no es
// rectangular—. Así llena la card y se ve completo.
Widget _arteRespaldo(int cacheWidth) {
  // Solo la imagen, llenando la card entera. Sin fondo de ningún tipo.
  //
  // OJO si se vuelve a tocar esto: el logo es casi cuadrado y la card ancha
  // es 16:9. En un marco así, o la imagen LLENA y pierde un poco arriba y
  // abajo, o se ve entera y quedan barras a los costados. No hay una tercera
  // opción con este asset. Se eligió llenar, porque las barras se ven como un
  // fondo pegado detrás del logo y eso es justo lo que no se quiere.
  return Image.asset(
    'assets/carddefaultoffline.png',
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    cacheWidth: cacheWidth,
  );
}

class HomeMediaCard extends StatefulWidget {
  // Expuestas como static para que HomeSection sepa cuánto alto reservar
  // para la fila entera (portada + título/subtítulo debajo) sin duplicar
  // el número a mano en dos archivos distintos.
  // ── Más grandes ────────────────────────────────────────────────────────
  //
  // Todas subieron alrededor de un doce por ciento. Lo que las tenía chicas era
  // el relleno de la caja que envolvía cada sección: ahora que esa caja no
  // está (ver HomeSection.boxed), ese ancho quedó libre y lo aprovechan las
  // portadas, que es lo único que uno mira.
  //
  // La proporción de cada una se conserva exacta, así que ninguna portada se
  // deforma ni se recorta distinto que antes.
  // Eran campos fijos; pasan a ser getters porque en TV valen otra cosa: la
  // de escritorio, ver el porqué en HomeTheme y en el comentario de
  // `anchoAncha` más abajo. Nada más los usaba para asignarles nada, así que
  // el cambio no afecta a quien ya los lee.
  static double get androidWidth =>
      PlatformTv.esTelevisionSync ? desktopWidth : 168;
  static double get androidHeight =>
      PlatformTv.esTelevisionSync ? desktopHeight : 233;
  static double desktopWidth = 236;
  static double desktopHeight = 328;
  // Android landscape: la tarjeta a tamaño "vertical" (208 de alto) no
  // entraba entera en el poco alto disponible (confirmado en vivo, sobre
  // todo en Historial) — más chica en horizontal, mismo aspecto ~0.72:1.
  // Variante HORIZONTAL (escritorio): 16:9, la misma forma que los frames de
  // vídeo, así la portada de "Continuar" ya no se recorta.
  // ── Y también en el teléfono ───────────────────────────────────────────
  //
  // La ancha era solo de escritorio: en Android, «Continuar viendo» usaba la
  // vertical, o sea un marco de póster para una CAPTURA DE VÍDEO. La captura es
  // 16:9, así que entraba recortada por los costados —se perdía media escena— o
  // con franjas. Justo lo que esta tarjeta vino a resolver.
  //
  // Los números del teléfono son los mismos 16:9, más chicos: 264 de ancho
  // dejan ver la tarjeta entera y el borde de la siguiente en una pantalla de
  // 360, que es lo que invita a deslizar.
  //
  // Getters y no constantes porque dependen de la plataforma. Quien los use
  // tiene que usar LOS TRES: mezclarlos con los viejos deja la imagen de un
  // tamaño y el hueco reservado de otro.
  // ── Y también en televisor, con el tamaño de escritorio ────────────────
  //
  // Un televisor es Platform.isAndroid, así que sin este agregado se llevaba
  // la variante de teléfono — la misma tarjeta que en un celular de 6
  // pulgadas, en una pantalla que se mira desde el sillón. La de escritorio
  // ya está pensada para verse "más grande, más espacio en pantalla" (ver el
  // comentario de arriba), y el peldaño `enorme` de `Ancho` ya agrupa
  // monitores grandes CON televisores — reusarla es el mismo criterio, sin
  // inventar un tercer número sin probar.
  static bool get _grande => !Platform.isAndroid || PlatformTv.esTelevisionSync;
  static double get anchoAncha => _grande ? 380 : 264;
  static double get altoImagenAncha => _grande ? 214 : 148;
  // El alto total tiene que cubrir la etiqueta de la extensión, no solo el
  // subtítulo. La etiqueta es una pastilla con su relleno —unos 21 puntos—
  // contra los 16 de una línea de texto suelta, así que con la cuenta vieja
  // sobresalía por abajo y la franja de la fila se la comía a la mitad. Se ve
  // en «Continuar viendo», que es donde la etiqueta dice de qué extensión
  // viene cada cosa.
  static double get altoTotalAncha => _grande ? 292 : 224;

  // ── Y es 16:9 EXACTO ───────────────────────────────────────────────────
  //
  // En escritorio estaba en 316 × 186, o sea 1,70. Los frames de vídeo son
  // 1,78, así que a cada captura se le comía una franja arriba y abajo: hacía
  // lo contrario de para lo que existe esta tarjeta. Con 380 × 214 da 1,776 y
  // la miniatura entra entera. En el teléfono, 264 × 148 da 1,784.
  //
  // El alto TOTAL suma la imagen, la separación, dos líneas de título y la del
  // subtítulo.

  // 112 quedaba MUY chico: en horizontal entraban ocho cards por fila y no se
  // leía ni el pill de la extensión. El apretón real venía del hero, que a
  // tamaño normal se comía toda la ventana en horizontal — ya se pone
  // compacto (ver HomeHeroBanner), así que acá sobra lugar para agrandarlas.
  // Se mantiene el mismo aspecto ~0.72:1 que las otras dos variantes.
  // Acostado sube menos: ahí el alto es lo único que escasea, y cada punto que
  // gana la tarjeta se lo saca a la fila entera, que ya entra justa.
  static double androidLandscapeWidth = 144;
  static double androidLandscapeHeight = 200;

  const HomeMediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.type,
    this.extensionName,
    this.cover,
    this.coverFile,
    this.headers,
    this.progress,
    this.onTap,
    this.onDelete,
    this.deleteLabel,
    this.newEpisodeLabel,
    this.extraActionLabel,
    this.extraActionIcon,
    this.onExtraAction,
    this.onVerDetalle,
    this.esFavorito,
    this.onAlternarFavorito,
    this.gradientSeed,
    this.hidden = false,
    this.onToggleHide,
    this.accent,
    this.horizontal = false,
    this.ancho,
  });

  final String title;
  final String? subtitle;
  // Chip de tipo (video/manga/novela) — colores fijos por tipo (mismo
  // criterio que ExtensionTypeBadge en el grid de extensiones), en vez del
  // chip plano gris de antes que no distinguía nada de un vistazo.
  final ExtensionType? type;
  // De qué extensión viene — mostrado como pill arriba a la derecha (el
  // badge de tipo, video/manga/novela, va arriba a la izquierda). Útil
  // sobre todo en tarjetas armadas cruzando varias extensiones (Recomendado,
  // Tendencias, Nuevos capítulos, Categorías) donde el origen no es obvio.
  final String? extensionName;
  final String? cover;
  // Portadas locales (capturas de video) en vez de una URL de red — usado
  // por Historial para los ítems de tipo video.
  final File? coverFile;
  final Map<String, String>? headers;
  // 0.0–1.0, null = sin barra de progreso.
  final double? progress;
  final VoidCallback? onTap;
  // Si se pasa, agrega "Eliminar" al menú de tres puntos (usado por
  // Historial/Favoritos y los dos Homes).
  final VoidCallback? onDelete;

  /// Texto de la acción de borrar. En "Continuar" no borra nada —saca el ítem
  /// de la fila— así que llamarlo "Eliminar" ahí asustaría sin motivo.
  final String? deleteLabel;

  /// Acción extra del menú de tres puntos, encima de ocultar y eliminar. La
  /// usa el Historial para mover el ítem entre "en curso" y "visto" sin tener
  /// que abrirlo y leer un capítulo, que hoy es la única forma.
  /// Texto del capítulo/episodio nuevo, si lo hay. Se muestra como distintivo
  /// sobre la portada: es lo único que justifica que el ítem haya vuelto a
  /// "Continuar", así que tiene que verse sin leer el título.
  final String? newEpisodeLabel;

  final String? extraActionLabel;
  final IconData? extraActionIcon;
  final VoidCallback? onExtraAction;

  /// Abre la ficha del titulo desde el menu de tres puntos.
  ///
  /// Hace falta porque tocar la tarjeta NO siempre lleva ahi: en los dos Home,
  /// "Continuar" retoma la reproduccion o la lectura donde habia quedado. Sin
  /// esta opcion, para ver la ficha de algo que estabas siguiendo habia que
  /// buscarlo de nuevo por el buscador.
  final VoidCallback? onVerDetalle;

  /// Si el título ya está en favoritos. En null, la opción no se ofrece.
  ///
  /// ── Por qué en el menú y no como estrella suelta ───────────────────────
  ///
  /// Una estrella encima de la portada tapa la portada, que es lo único que la
  /// tarjeta tiene que mostrar. Y ya hay un menú de tres puntos que junta todo
  /// lo demás que se puede hacer con el título —ver la ficha, ocultarla,
  /// borrarla—; que favorito viviera aparte era la única acción sin un lugar
  /// claro donde buscarla.
  final bool? esFavorito;
  final VoidCallback? onAlternarFavorito;

  /// Ancho a la medida, para las grillas. Ver dónde se usa.
  final double? ancho;
  // Para elegir el degradado por posición cuando no hay portada — si no se
  // pasa, se deriva del título (mismo criterio que ColorUtils.getColorByText).
  final int? gradientSeed;
  // Tapa la portada real con el arte genérico de PRISM_HUB (privacidad —
  // alguien mirando de reojo no ve de qué es). Si onToggleHide es null, el
  // menú no ofrece ocultar (la card no es "ocultable" en ese contexto).
  final bool hidden;
  final VoidCallback? onToggleHide;
  // Zona +18: se pasa HomeTheme.accentRed para diferenciar la barra de
  // progreso en esa pantalla.
  /// En null usa el acento del tema. Ver AnimatedBackgroundGlow.accent.
  final Color? accent;

  Color get acento => accent ?? HomeTheme.accentPink;
  // true = variante horizontal 16:9 (solo Home de escritorio). La vertical
  // sigue siendo el default en todos los demás lugares.
  final bool horizontal;

  @override
  State<HomeMediaCard> createState() => _HomeMediaCardState();
}

class _HomeMediaCardState extends State<HomeMediaCard> {
  bool _hover = false;

  Widget _extensionNamePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      // Opaco, no semitransparente: este pill vive debajo de la portada,
      // pero el mismo widget se usa en contextos donde queda encima, y ahí
      // el 65% de opacidad dejaba ver la imagen a través del texto.
      // ── El fondo sigue al modo ────────────────────────────────────────
      //
      // Estaba fijo en un azul muy oscuro. Con el texto puesto en el color del
      // tema —casi negro en claro— quedaba negro sobre azul oscuro: la
      // etiqueta se veía como una mancha sin letras. En claro va la superficie
      // de tarjeta, un tono por debajo, que es el mismo papel que cumplía el
      // azul en oscuro.
      decoration: BoxDecoration(
        color: ModoDeColor.claro
            ? HomeTheme.esqueletoBase
            : const Color(0xFF202030),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Text(
        widget.extensionName!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: HomeTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ─── Variante horizontal (escritorio) ────────────────────────────────────
  //
  // Camino de render SEPARADO del vertical a propósito: comparte el mismo
  // widget (mismos datos, mismas acciones) pero no reutiliza una sola línea de
  // su layout. Así la card vertical —que usan Historial, Favoritos y todo el
  // móvil— queda intacta mientras esta se prueba, y volver atrás es cambiar el
  // flag en una línea.
  Widget _buildHorizontal(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final imgW = (HomeMediaCard.anchoAncha * dpr).ceil().clamp(1, 4096);
    final hasCover = !widget.hidden &&
        (widget.cover?.isNotEmpty == true || widget.coverFile != null);

    // Arte de respaldo cuando la portada no carga. Va con contain y margen:
    // el respaldo interno de CacheNetWorkImagePic lo pinta a pantalla completa
    // con cover, y este logo NO es rectangular, así que le cortaba las puntas
    // (se veía la estrella partida arriba y abajo en las cards del Home).
    final arteDefault = _arteRespaldo(imgW);

    Widget cover;
    if (widget.hidden) {
      cover = arteDefault;
    } else if (widget.coverFile != null) {
      // Los frames ya son 16:9, o sea la MISMA forma que la card: acá cover no
      // recorta casi nada y no hace falta el fondo borroso de la variante
      // vertical. Esa es justamente la ventaja de este diseño para "Continuar".
      cover = Image.file(widget.coverFile!,
          fit: BoxFit.cover,
          cacheWidth: imgW,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF15151C)));
    } else if (hasCover) {
      // cover y NO contain: una portada de lectura es ~2:3 y la card ~0.72:1,
      // formas casi iguales, así que llena el marco entero recortando apenas
      // un 7% a los costados —imperceptible— en vez de dejar franjas del
      // fondo arriba y abajo. Ahora que "Continuar" está partido en dos, cada
      // tipo va en la card con su forma, así que esto ya no perjudica al
      // vídeo. El arte de respaldo sigue con contain (ver arteDefault): ese
      // logo NO es rectangular y con cover se le cortan las puntas.
      cover = CacheNetWorkImagePic(widget.cover!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          headers: widget.headers,
          fallback: arteDefault,
          cacheWidth: imgW);
    } else {
      // Sin portada: el arte de PrismHub, no un color liso.
      //
      // Antes acá iba solo un degradado, y una tarjeta así se lee como que algo
      // se rompió — sobre todo cuando al lado hay otras con su imagen. Con el
      // arte se entiende que la portada todavía no está, que es lo que pasa de
      // verdad: puede faltar porque el título llegó por una copia y nunca se
      // abrió, o porque la extensión todavía no la entregó.
      //
      // El degradado se conserva DETRÁS: el arte es casi cuadrado y la tarjeta
      // no, así que llenándola pierde un poco arriba y abajo; el color detrás
      // evita que se vea un hueco negro si el asset tardara en decodificarse.
      // Y sigue siendo distinto por título, así que dos tarjetas sin portada no
      // se ven idénticas.
      //
      // En cuanto la portada real aparezca —la reparación de fondo la pide y la
      // guarda, ver PortadasPerdidas— esta tarjeta pasa sola por la rama de
      // arriba y muestra la imagen de verdad.
      cover = Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: HomeTheme.gradientFor(
                    widget.gradientSeed ?? widget.title.hashCode),
              ),
            ),
          ),
          arteDefault,
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: RepaintBoundary(
          child: SizedBox(
            width: HomeMediaCard.anchoAncha,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Borde con el acento de la zona (morado en el Home normal,
                // rojo en la Zona +18): sobre el panel de la sección, que es
                // de un tono muy parecido al de la card, no se veía dónde
                // terminaba cada tarjeta.
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SizedBox(
                    width: HomeMediaCard.anchoAncha,
                    height: HomeMediaCard.altoImagenAncha,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        cover,
                        // Velo que se aclara con el hover — da la sensación de
                        // "se puede tocar" sin mover la card de lugar.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          color: Colors.black
                              .withValues(alpha: _hover ? 0.28 : 0.10),
                        ),
                        // El play ya no está siempre: tapaba el centro de la
                        // portada (justo donde suele estar lo que se quiere
                        // ver). Aparece solo cuando el mouse está encima, que
                        // es cuando de verdad indica "esto se puede abrir".
                        Center(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: _hover ? 1 : 0,
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 150),
                              scale: _hover ? 1.08 : 0.9,
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.45),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      width: 2),
                                ),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        ),
                        // Los distintivos ya no van ENCIMA de la portada: el
                        // de tipo lo dice el título de la sección, y el de la
                        // extensión pasó abajo, junto al título. Sobre la
                        // imagen tapaban justo las esquinas del contenido.
                        if (widget.newEpisodeLabel?.isNotEmpty == true)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                // Sólido y con contorno, mismo criterio que el
                                // resto de los distintivos: sobre una portada
                                // clara uno translúcido no se lee.
                                color: widget.acento,
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: const Color(0x8CFFFFFF)),
                              ),
                              child: Text(
                                widget.newEpisodeLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (widget.progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: widget.progress!.clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                              valueColor: AlwaysStoppedAnimation(widget.acento),
                            ),
                          ),
                        _bordeCard(8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Subtítulo y pill en la MISMA línea: puestos uno
                          // debajo del otro la card crecía, y el alto de la
                          // fila tiene que quedar igual que antes.
                          Row(
                            children: [
                              if (widget.subtitle?.isNotEmpty == true)
                                Flexible(
                                  child: Text(
                                    widget.subtitle!.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: HomeTheme.textMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.title,
                            // Una línea y no dos: el pill de la extensión pasa
                            // a ir DEBAJO del título, y con el título en dos
                            // líneas el bloque no entraba en el alto de la
                            // fila y el pill quedaba cortado por el borde del
                            // panel.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: HomeTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          if (widget.extensionName?.isNotEmpty == true) ...[
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _extensionNamePill(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Ocultar y eliminar viven los DOS en el menú de tres
                    // puntos: en la card horizontal el ojo suelto sobre la
                    // imagen tapaba parte del frame, que es justo lo que este
                    // diseño busca mostrar entero.
                    if (widget.onDelete != null || widget.onToggleHide != null)
                      _WideMenuButton(
                        hidden: widget.hidden,
                        onDelete: widget.onDelete,
                        onToggleHide: widget.onToggleHide,
                        deleteLabel: widget.deleteLabel,
                        extraLabel: widget.extraActionLabel,
                        extraIcon: widget.extraActionIcon,
                        onExtra: widget.onExtraAction,
                        onVerDetalle: widget.onVerDetalle,
                        esFavorito: widget.esFavorito,
                        onAlternarFavorito: widget.onAlternarFavorito,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // En TV la tarjeta se envuelve para que el D-pad pueda enfocarla —
    // igual que ExtensionItemCard, y por el mismo motivo: sin esto la
    // Biblioteca (y cualquier otra pantalla que use esta tarjeta) se ve
    // pero no se puede recorrer con el mando.
    //
    // El `IgnorePointer` apaga los gestos que la tarjeta trae adentro: con
    // los dos activos, un click abría la ficha dos veces. Se pierde el menú
    // de mantener apretado (ocultar/borrar), que es un gesto de dedo sin
    // equivalente en un control remoto — en TV esas acciones ya viven en
    // sus propias pantallas.
    if (PlatformTv.esTelevisionSync) {
      return FocusableCard(
        borderRadius: 10,
        accent: widget.acento,
        // ── El marco abarca la PORTADA, no la tarjeta entera ────────────
        //
        // Reportado en vivo con foto (Historial de TV): el resplandor y el
        // borde cubrían también el título y el subtítulo de abajo, y como
        // esos textos no tienen fondo propio, el halo rosa se veía a través
        // y los dejaba lavados, casi ilegibles. "Ahí solo es la card, no
        // todo".
        //
        // Lo que el usuario está eligiendo es la portada; el texto de
        // debajo es su etiqueta. Pasando el alto de la imagen, el marco se
        // dibuja solo alrededor de ella —igual que ya hacían las tarjetas
        // del catálogo (`TarjetaDeCatalogo`), que sí lo pasaban.
        altoMarco: _altoDeLaPortada(context),
        onTap: widget.onTap ?? () {},
        child: IgnorePointer(child: _construir(context)),
      );
    }
    return _construir(context);
  }

  /// El alto de la imagen sola, sin el título ni el subtítulo de abajo.
  ///
  /// Se calcula igual que en `_construir` — la horizontal tiene su alto
  /// fijo, y la vertical sigue al ancho para no deformar la portada.
  double _altoDeLaPortada(BuildContext context) {
    if (widget.horizontal) return HomeMediaCard.altoImagenAncha;
    final isAndroidLandscape = Platform.isAndroid &&
        !PlatformTv.esTelevisionSync &&
        MediaQuery.of(context).orientation == Orientation.landscape;
    final anchoBase = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeWidth
        : Platform.isAndroid
            ? HomeMediaCard.androidWidth
            : HomeMediaCard.desktopWidth;
    final altoBase = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeHeight
        : Platform.isAndroid
            ? HomeMediaCard.androidHeight
            : HomeMediaCard.desktopHeight;
    return widget.ancho == null
        ? altoBase
        : widget.ancho! * (altoBase / anchoBase);
  }

  Widget _construir(BuildContext context) {
    if (widget.horizontal) return _buildHorizontal(context);
    final hasCover = !widget.hidden &&
        (widget.cover?.isNotEmpty == true || widget.coverFile != null);
    final gradient = HomeTheme.gradientFor(
      widget.gradientSeed ?? widget.title.hashCode,
    );
    // Desktop más grande (más espacio en pantalla, y deja lugar real para
    // que el tag/badge de tipo+extensión no quede apretado); Android un
    // poco más chico para que entren más columnas, mismo aspecto ~0.72:1.
    // En horizontal (Android), el tamaño "vertical" no entraba entero en
    // el poco alto disponible — se usa la variante landscape, más chica.
    final hasMenu = widget.onDelete != null ||
        widget.onToggleHide != null ||
        widget.onExtraAction != null ||
        widget.onVerDetalle != null ||
        widget.onAlternarFavorito != null;
    // ── Un televisor SIEMPRE reporta horizontal, y no es un teléfono acostado
    //
    // Sin el `!PlatformTv.esTelevisionSync`, un Android TV entraba por acá:
    // es Android y su MediaQuery siempre da horizontal (no hay forma física
    // de girarlo), así que se llevaba `androidLandscapeWidth` — la variante
    // MÁS CHICA de las tres, pensada para un teléfono de costado con poco
    // alto. La Biblioteca de TV terminaba con tarjetas más chicas que las de
    // un teléfono, que es lo contrario de lo que hace falta en una pantalla
    // que se mira de lejos.
    final isAndroidLandscape = Platform.isAndroid &&
        !PlatformTv.esTelevisionSync &&
        MediaQuery.of(context).orientation == Orientation.landscape;
    final anchoBase = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeWidth
        : Platform.isAndroid
            ? HomeMediaCard.androidWidth
            : HomeMediaCard.desktopWidth;
    final altoBase = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeHeight
        : Platform.isAndroid
            ? HomeMediaCard.androidHeight
            : HomeMediaCard.desktopHeight;
    // ── El ancho lo puede poner quien la dibuja ──────────────────────────
    //
    // En una FILA el ancho fijo es lo correcto: las tarjetas se desplazan de
    // costado y todas tienen que medir igual.
    //
    // En una GRILLA no. La grilla reparte el ancho entre las columnas que
    // entran, y la tarjeta se quedaba en sus 150 dentro de una celda de 164:
    // sobraba aire a los costados de cada una y las portadas se veían chicas
    // sin motivo. Pasándole el ancho de la celda, la tarjeta la llena.
    //
    // El alto sigue al ancho para no deformar la portada.
    final width = widget.ancho ?? anchoBase;
    final height = widget.ancho == null
        ? altoBase
        : widget.ancho! * (altoBase / anchoBase);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * dpr).ceil().clamp(1, 4096).toInt();
    final defaultCover = _arteRespaldo(cacheWidth);
    // Tarjeta "oculta": mismo asset (carddefaultoffline.png) que el resto de
    // los placeholders default de la app, pero a pantalla completa (cover,
    // sin caja oscura ni padding) — el pedido fue sacar el recuadro, no la
    // imagen en sí.
    // Tarjeta oculta: el MISMO arte que el resto de los respaldos, con
    // contain y margen. Antes iba con cover a pantalla completa —"sacar el
    // recuadro"— pero el logo no es rectangular, así que al ocultar una card
    // se le cortaban las puntas y quedaba partido arriba y abajo.
    final hiddenCover = defaultCover;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: RepaintBoundary(
          // ── La tarjeta se eleva, pero su zona de toque NO se mueve ───────
          //
          // Al pasar el ratón la tarjeta sube cuatro puntos. Estaba hecho con
          // el `transform` de un AnimatedContainer, y un transform mueve el
          // dibujo Y el área que responde al clic.
          //
          // Lo que pasaba: entrás con el ratón a la tarjeta y hacés clic
          // enseguida. El clic cae DURANTE los 150 ms en los que la tarjeta se
          // está elevando, o sea mientras su área de toque se está corriendo
          // hacia arriba bajo el cursor. Si el puntero estaba en la franja de
          // abajo, para cuando soltás ya quedó fuera y Flutter cancela el
          // toque: el primer clic no hace nada y hay que dar otro. En pantalla
          // completa casi no se nota porque uno ya viene con el ratón adentro y
          // la elevación terminó hace rato; en ventana, con el ratón entrando
          // desde el borde, pasa casi siempre. Reportado en vivo.
          //
          // `transformHitTests: false` es exactamente para esto: la tarjeta se
          // ve elevada y el área de toque se queda donde estaba.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _hover ? -4 : 0),
            duration: const Duration(milliseconds: 150),
            builder: (context, dy, hijo) => Transform.translate(
              offset: Offset(0, dy),
              transformHitTests: false,
              child: hijo,
            ),
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: width,
                    height: height,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: hasCover
                          ? null
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradient,
                            ),
                      // Sin sombra con el modo claro puesto, por lo mismo que
                      // en las tarjetas del acordeón (ver _TarjetaGrande en
                      // home_page_android.dart): es negra y sobre un fondo
                      // claro no se lee como profundidad sino como un halo
                      // gris alrededor de cada portada. Sobre el fondo oscuro
                      // sí cumple, así que ahí se queda igual.
                      boxShadow: ModoDeColor.claro
                          ? null
                          : const [
                              BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.hidden)
                          hiddenCover
                        else if (widget.coverFile != null)
                          // Capturas del vídeo: son horizontales (~16:9) dentro de
                          // una card vertical (~0.72:1). Ni cover ni contain solos
                          // funcionan — cover recortaba tanto a los costados que
                          // del cuadro quedaba una franja irreconocible, y contain
                          // deja dos barras negras enormes.
                          //
                          // Se muestra el frame ENTERO (contain) sobre un fondo
                          // borroso de la MISMA imagen estirada a cubrir. Llena la
                          // card, no recorta nada y no se ve estirado.
                          //
                          // El fondo se decodifica mucho más chico: va
                          // desenfocado, así que más resolución no se notaría y sí
                          // costaría memoria en una lista con muchas cards. Cuánto
                          // más chico, y si el desenfoque se aplica de verdad o se
                          // consigue con el propio estirado, lo decide
                          // [RellenoBorroso] según el aparato — en un televisor
                          // este desenfoque, una vez por tarjeta, era de lo más
                          // caro de la fila.
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              RellenoBorroso(
                                anchoDeLaCaja: width,
                                imagen: (anchoDecodificado) => Image.file(
                                  widget.coverFile!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  cacheWidth: anchoDecodificado,
                                  // Sin errorBuilder acá: si la imagen falla, el
                                  // de la capa de arriba ya muestra el default.
                                  errorBuilder: (_, __, ___) =>
                                      const ColoredBox(
                                          color: Color(0xFF15151C)),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(_coverInset),
                                child: Image.file(
                                  widget.coverFile!,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                  cacheWidth: cacheWidth,
                                  errorBuilder: (context, error, stackTrace) =>
                                      defaultCover,
                                ),
                              ),
                            ],
                          )
                        else if (hasCover)
                          // El fondo borroso se puso cuando la imagen llegaba
                          // DEFORMADA (cacheWidth+cacheHeight juntos hacían que
                          // el decoder ignorara el aspecto original). Arreglado
                          // eso, un póster de lectura (2:3) contra una card de
                          // ~0.72:1 llena casi exacto con cover: se recorta un
                          // 7% a los costados, imperceptible, y se ve como una
                          // portada de verdad en vez de una imagen chica dentro
                          // de un marco. El fondo borroso queda SOLO para el
                          // caso donde de verdad hace falta: un frame de vídeo
                          // (16:9) metido en una card alta, donde cover dejaría
                          // una franja irreconocible.
                          // Ver el mismo caso en la card ancha: cover para
                          // que la portada llene la tarjeta, y el respaldo con
                          // contain para que el logo no se corte.
                          CacheNetWorkImagePic(
                            widget.cover!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            headers: widget.headers,
                            fallback: defaultCover,
                            cacheWidth: cacheWidth,
                          ),
                        // Ver la card ancha: los distintivos salieron de
                        // encima de la portada. Acá tapaban una esquina de cada
                        // lado, que en una card chica es bastante.
                        if (widget.progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 4,
                              color: const Color(0x80000000),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: widget.progress!.clamp(0, 1),
                                child: Container(color: widget.acento),
                              ),
                            ),
                          ),
                        _bordeCard(14),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Título y distintivo a la izquierda, menú de tres puntos a la
                  // derecha — la misma disposición que la card ancha. Antes el
                  // menú iba ENCIMA de la portada y tapaba una esquina de la
                  // imagen.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: HomeTheme.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.extensionName?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _extensionNamePill(),
                              ),
                            ] else if (widget.subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: HomeTheme.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasMenu)
                        _WideMenuButton(
                          hidden: widget.hidden,
                          onDelete: widget.onDelete,
                          onToggleHide: widget.onToggleHide,
                          deleteLabel: widget.deleteLabel,
                          extraLabel: widget.extraActionLabel,
                          extraIcon: widget.extraActionIcon,
                          onExtra: widget.onExtraAction,
                          onVerDetalle: widget.onVerDetalle,
                          esFavorito: widget.esFavorito,
                          onAlternarFavorito: widget.onAlternarFavorito,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Menú de tres puntos de la card horizontal. Agrupa ocultar y eliminar en vez
// de dejar botones sueltos sobre la portada, que en 16:9 tapaban parte del
// frame. Colores propios (HomeTheme) y no los del tema Material por defecto,
// para que no desentone con el resto del Home.
class _WideMenuButton extends StatelessWidget {
  const _WideMenuButton({
    required this.hidden,
    this.onDelete,
    this.onToggleHide,
    this.deleteLabel,
    this.extraLabel,
    this.extraIcon,
    this.onExtra,
    this.onVerDetalle,
    this.esFavorito,
    this.onAlternarFavorito,
  });

  // Eran parámetros, con estos mismos valores por defecto. El único que los
  // pasaba distinto era el menú de encima de la portada, que ya no existe.
  static final Color _iconColor = HomeTheme.textMuted;
  static const double _size = 28;

  final bool hidden;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleHide;
  final String? deleteLabel;
  final String? extraLabel;
  final IconData? extraIcon;
  final VoidCallback? onExtra;
  final VoidCallback? onVerDetalle;
  final bool? esFavorito;
  final VoidCallback? onAlternarFavorito;

  @override
  Widget build(BuildContext context) {
    // En escritorio la raíz es FluentApp, que NO pone un Material en el árbol
    // (por eso el resto de los botones de la card se envuelven a mano). Sin
    // esto, PopupMenuButton revienta con "No Material widget found" en
    // Windows/Linux mientras en Android anda, porque ahí la raíz es
    // GetMaterialApp. MaterialLocalizations sí las da FluentApp.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: _size,
        height: _size,
        child: PopupMenuButton<int>(
          tooltip: '',
          padding: EdgeInsets.zero,
          splashRadius: 18,
          iconSize: 18,
          color: HomeTheme.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: HomeTheme.border),
          ),
          // OJO: `constraints` acá es el tamaño del MENÚ desplegado, no el del
          // botón. Ponerle el tamaño del botón (30x30) abría un menú de 30px,
          // que se ve como "no abre nada". El tamaño del botón se controla con
          // el SizedBox de abajo.
          constraints: const BoxConstraints(minWidth: 170),
          icon: Icon(Icons.more_vert, color: _iconColor, size: 18),
          onSelected: (v) {
            if (v == 0) onToggleHide?.call();
            if (v == 1) onDelete?.call();
            if (v == 2) onExtra?.call();
            if (v == 3) onVerDetalle?.call();
            if (v == 4) onAlternarFavorito?.call();
          },
          itemBuilder: (context) => [
            // Ver la ficha va arriba de todo: es a donde uno quiere ir cuando
            // abre este menu desde una tarjeta que al tocarla hace otra cosa
            // —en los Home, retomar donde habia quedado—.
            if (onVerDetalle != null)
              PopupMenuItem<int>(
                value: 3,
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 17, color: HomeTheme.textMuted),
                    const SizedBox(width: 10),
                    Text(
                      'home.view-detail'.i18n,
                      style:
                          TextStyle(color: HomeTheme.textPrimary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            // Favorito, justo después de ver la ficha: es lo que uno más hace
            // con un título sin abrirlo. Con la estrella llena cuando ya está,
            // para que se lea de un vistazo qué va a pasar al tocarla.
            if (esFavorito != null && onAlternarFavorito != null)
              PopupMenuItem<int>(
                value: 4,
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      esFavorito! ? Icons.star_rounded : Icons.star_border,
                      size: 17,
                      color: esFavorito!
                          ? HomeTheme.accentPink
                          : HomeTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      esFavorito!
                          ? 'home.remove-favorite'.i18n
                          : 'home.add-favorite'.i18n,
                      style:
                          TextStyle(color: HomeTheme.textPrimary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            // La acción extra va primera: es la del contexto de la pantalla —
            // en el Historial, mover un título entre "en curso" y "visto"— y
            // por eso pesa más que ocultar o eliminar.
            //
            // Este bloque FALTABA. El botón recibía extraLabel, extraIcon y
            // onExtra desde el Historial pero no los dibujaba en ningún lado ni
            // los atendía en onSelected, así que la acción no existía para el
            // usuario: el menú de una tarjeta de historial abría con dos
            // opciones en vez de tres. Peor, `hasMenu` sí cuenta la acción
            // extra, así que una tarjeta cuya única acción fuera esa abría un
            // menú vacío.
            if (onExtra != null && extraLabel != null)
              PopupMenuItem<int>(
                value: 2,
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      extraIcon ?? Icons.check_rounded,
                      size: 17,
                      color: HomeTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        extraLabel!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: HomeTheme.textPrimary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (onToggleHide != null)
              PopupMenuItem<int>(
                value: 0,
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      hidden
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 17,
                      color: HomeTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      hidden ? 'home.show-card'.i18n : 'home.hide-card'.i18n,
                      style:
                          TextStyle(color: HomeTheme.textPrimary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            if (onDelete != null)
              PopupMenuItem<int>(
                value: 1,
                height: 40,
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline,
                        size: 17, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Text(
                      deleteLabel ?? 'common.delete'.i18n,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Acá vivía _CardOverlayMenu, el menú que iba ENCIMA de la portada en la card
// vertical. Cuando ese menú se movió abajo, al lado del título, dejó de usarse
// pero quedó en el archivo: una segunda versión del menú que nadie dibujaba y
// que no recibió ninguno de los arreglos posteriores. Se borra para que no haya
// dos lugares donde parezca que hay que tocar.
