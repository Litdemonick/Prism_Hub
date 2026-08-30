import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_mas.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/horizontal_scroll_fade.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

// Envoltorio de sección — calca el header del diseño (título + ›, botones
// prev/next redondeados) sin tocar HorizontalList, que es compartido con
// Búsqueda/otras páginas y no debía cambiar.
class HomeSection extends StatefulWidget {
  const HomeSection({
    super.key,
    required this.title,
    required this.onClickMore,
    required this.itemCount,
    required this.itemBuilder,
    this.showNavButtons = true,
    this.itemWidth,
    this.itemHeight,
    this.itemCoverHeight,
    this.boxed = false,
    this.accent,
  });

  final String title;
  final VoidCallback onClickMore;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final bool showNavButtons;
  // Tamaño de ítem a medida — para filas que no usan la card vertical
  // estándar (ej. la horizontal 16:9 del Home de escritorio).
  final double? itemWidth;
  final double? itemHeight;
  // Alto SOLO de la portada, sin el título de abajo. Se usa para centrar las
  // flechas flotantes de los costados: si se centran en el alto total de la
  // fila quedan más abajo que las imágenes con las que se supone que están
  // alineadas. Si no se pasa, se asume que el alto de ítem ya es el de la
  // portada (que es el caso de la card vertical).
  final double? itemCoverHeight;
  // true = la sección se dibuja sobre su propio panel redondeado. Sirve para
  // que "Continuar" y "Favoritos" se lean como dos bloques separados y no
  // como una lista larga de cards sueltas sobre el fondo de la página.
  final bool boxed;
  // Zona +18: se pasa HomeTheme.accentRed para diferenciar esa pantalla.
  /// En null usa el acento del tema. Ver AnimatedBackgroundGlow.accent.
  final Color? accent;

  Color get acento => accent ?? HomeTheme.accentPink;

  @override
  State<HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends State<HomeSection> {
  final ScrollController _controller = ScrollController();
  bool _headerHover = false;

  // Los botones ‹ › del encabezado avanzan DE A POCO (un par de cards) —
  // para acomodar la fila con precisión. El salto largo es el de las flechas
  // flotantes de los costados, que recorren una pantalla entera de una.
  void _move(bool left) {
    _controller.animateTo(
      (_controller.offset + (left ? -400 : 400))
          .clamp(0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.ease,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mismo cuidado que en HomeMediaCard: un televisor siempre reporta
    // horizontal y no es un teléfono acostado — sin excluirlo acá también,
    // esta cuenta (que HomeMediaCard no controla) se llevaba igual la
    // variante más chica de las tres para la fila entera.
    final isAndroidLandscape = Platform.isAndroid &&
        !PlatformTv.esTelevisionSync &&
        MediaQuery.of(context).orientation == Orientation.landscape;
    final cardWidth = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeWidth
        : Platform.isAndroid
            ? HomeMediaCard.androidWidth
            : HomeMediaCard.desktopWidth;
    final cardHeight = isAndroidLandscape
        ? HomeMediaCard.androidLandscapeHeight
        : Platform.isAndroid
            ? HomeMediaCard.androidHeight
            : HomeMediaCard.desktopHeight;
    // Overrides opcionales: sin esto el alto de la fila sale SIEMPRE de las
    // constantes de la card vertical, así que cualquier card con otra forma
    // (ej. la horizontal 16:9 del Home de escritorio) se veía recortada y
    // parecía un bug del diseño cuando en realidad era el alto reservado acá.
    final effWidth = widget.itemWidth ?? cardWidth;
    final effHeight = widget.itemHeight ?? cardHeight;
    final list = ListView.builder(
      scrollDirection: Axis.horizontal,
      controller: _controller,
      itemExtent: effWidth + 16,
      // Cuánto se construye por fuera de lo que se ve, según el aparato.
      //
      // De fábrica Flutter construye 250 px de más a cada lado, y en un aparato
      // capaz eso es lo que hace que el carrusel vaya suave al deslizar. En uno
      // modesto es trabajo que no llega a tiempo —y portadas decodificadas que
      // quizá no se miren nunca—, que es justo lo que se reportó: «al deslizar
      // el carrusel se nota demora, y después va bien».
      //
      // Null es «lo que decida Flutter», o sea lo de siempre. Ver PrismHubMas.
      scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas,
      // Espacio arriba para la elevación de 4px que hace la card al pasar el
      // mouse: sin esto la lista la recortaba justo por ese borde y parecía
      // que se comía la tarjeta.
      padding: const EdgeInsets.only(top: 6),
      itemCount: widget.itemCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: widget.itemBuilder(context, index),
      ),
    );

    final esTv = PlatformTv.esTelevisionSync;
    final double tituloFontSize =
        esTv ? HomeTheme.tituloDeFilaTv(context).fontSize! : 17;
    Widget encabezado = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _headerHover = true),
      onExit: (_) => setState(() => _headerHover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: _headerHover ? widget.acento : HomeTheme.textPrimary,
              fontSize: tituloFontSize,
              fontWeight: FontWeight.w700,
            ),
            child: Text(widget.title),
          ),
          const SizedBox(width: 6),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: _headerHover ? widget.acento : HomeTheme.textMuted,
              fontSize: 15,
            ),
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 150),
              offset: _headerHover ? const Offset(0.25, 0) : Offset.zero,
              child: const Text('›'),
            ),
          ),
        ],
      ),
    );
    // ── En TV, "Ver todo" se envuelve para que el mando lo alcance ────────
    //
    // Con solo GestureDetector, este título es una de las pocas cosas de la
    // Biblioteca que un mouse o un dedo pueden tocar pero un control remoto
    // no: no hay foco que pedirle. `FocusableCard` es lo mismo que envuelve
    // cada tarjeta de la fila, así que "Ver todo" queda alcanzable con la
    // misma flecha que ya recorre la fila.
    encabezado = esTv
        ? FocusableCard(onTap: widget.onClickMore, child: encabezado)
        : GestureDetector(onTap: widget.onClickMore, child: encabezado);
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            encabezado,
            const Spacer(),
            // Las flechas de a poco son para mouse: con el mando, la fila ya
            // se recorre tarjeta por tarjeta con las flechas del control, así
            // que en TV no aportan nada y solo ocupan lugar sin que nadie
            // pueda tocarlas.
            if (widget.showNavButtons && !esTv) ...[
              _NavButton(icon: Icons.chevron_left, onTap: () => _move(true)),
              const SizedBox(width: 6),
              _NavButton(icon: Icons.chevron_right, onTap: () => _move(false)),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          // Con la card vertical, itemHeight es el alto de la PORTADA y hay
          // que sumarle el título/subtítulo de abajo — sin ese margen la fila
          // desborda (visto en vivo: "overflowed by 44/26 pixels"). En
          // Android horizontal usa su variante más chica (ver
          // androidLandscapeHeight) — hay que matchear acá también.
          //
          // Cuando se pasa itemHeight a mano (card ancha), ese número YA es el
          // alto total de la card: sumarle 50 dejaba una franja muerta de 50px
          // entre una sección y la siguiente. Solo se agrega un colchón chico
          // por si el texto redondea distinto en otra densidad de pantalla.
          // El margen debajo de la portada tiene que cubrir el título Y el pill de
          // la extensión, más los 6px de aire para la elevación del hover. Con
          // 56 alcanzaba justo en escritorio pero no en celular en vertical,
          // donde el pill quedaba cortado por el borde del panel de la
          // sección. NO cambia el tamaño de la card: solo el alto que la fila
          // reserva para lo que va debajo.
          height: widget.itemHeight != null ? effHeight + 18 : effHeight + 70,
          child: HorizontalScrollFade(
            controller: _controller,
            // Se centran con la PORTADA, no con el alto total de la fila
            // (que suma el título de abajo) — por eso quedaban corridas.
            arrowCenterFromTop: (widget.itemCoverHeight ?? effHeight) / 2,
            arrowColor: widget.acento,
            // Salto largo: estas flechas son las de "pasar rápido".
            pageScroll: true,
            // Solo la flecha, sin el velo de fondo.
            showFade: false,
            child: list,
          ),
        ),
      ],
    );

    if (!widget.boxed) return section;
    return Container(
      // En celular el panel va con menos aire a los costados: la página ya
      // aporta 16 de margen, y sumarle otros 16 dejaba las cards con muy
      // poco ancho útil en una pantalla angosta.
      padding: Platform.isAndroid
          ? const EdgeInsets.fromLTRB(10, 14, 10, 14)
          : const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        // Apenas más claro que el fondo de la página, con un borde tenue: la
        // idea es delimitar, no competir con las portadas.
        color: HomeTheme.cardSurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HomeTheme.border.withValues(alpha: 0.6)),
      ),
      child: section,
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: HomeTheme.border),
          ),
          child: Icon(icon, size: 15, color: HomeTheme.textMuted),
        ),
      ),
    );
  }
}

// Estado vacío / ghost card — el diseño usa una tarjeta punteada con "+" y
// un texto de ayuda en vez de simplemente no mostrar nada.
class HomeGhostCard extends StatelessWidget {
  const HomeGhostCard({super.key, required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 140,
          height: 250,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: HomeTheme.textMuted.withValues(alpha: 0.35),
              width: 1.5,
              style: BorderStyle.solid,
            ),
            color: HomeTheme.cardSurface.withValues(alpha: 0.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HomeTheme.textMuted.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child:
                    Icon(Icons.add, color: HomeTheme.textMuted, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: HomeTheme.textMuted, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
