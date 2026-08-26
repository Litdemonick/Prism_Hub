import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Banner — calca el hero del diseño (degradado, badge "Destacado",
// título+subtítulo, CTA). A la derecha, una portada real random de tu
// contenido (favoritos/continuar viendo/recomendado) que cambia cada vez
// que se refresca el home — nunca una imagen fabricada.
//
// La portada NO se estira de borde a borde: las portadas son verticales y
// chicas (thumbnails), y forzarlas a cubrir todo el ancho del banner exigía
// un recorte extremo (solo se veía una franja irreconocible) y una
// ampliación muy grande (se veía pixelada). Mostrarla cerca de su tamaño
// natural, angostita a la derecha, evita ambos problemas — se ve nítida y
// reconocible — y se difumina con una máscara hacia el degradado de la
// izquierda, donde va el texto.
class HomeHeroBanner extends StatelessWidget {
  const HomeHeroBanner({
    super.key,
    this.background,
    this.gradient,
    this.onExploreCatalog,
  });
  final HeroBackground? background;
  // Zona +18: se pasa HomeTheme.heroGradientRed para diferenciar esa
  // pantalla del Home normal.
  /// En null usa el degradado del tema. No puede tener valor por defecto:
  /// ahora es un getter —cambia con el modo claro/oscuro— y un valor por
  /// defecto tiene que ser constante.
  final Gradient? gradient;
  // Zona +18 en Android se llega empujándola ENCIMA del shell principal
  // (Get.to, no es una tab del bottom-nav) — el default de acá
  // (Get.find<MainController>().changeTab) cambiaba la tab del shell que
  // quedó TAPADO debajo, sin mostrarse (confirmado en vivo: "Explorar
  // catálogo" no hacía nada visible en Zona +18/Android, en PC sí porque
  // router.go reemplaza la ruta actual sea cual sea). Zona +18 pasa acá su
  // propio callback (cerrar esta pantalla y RECIÉN AHÍ cambiar de tab).
  final VoidCallback? onExploreCatalog;

  void _openSearch() {
    if (onExploreCatalog != null) {
      onExploreCatalog!();
      return;
    }
    // Buscar ya no es una pestaña del shell principal (ver
    // main_controller.dart) — en Android/TV se empuja como pantalla propia,
    // igual que ya se hace con Historial/Favoritos/Extensiones desde acá.
    if (Platform.isAndroid) {
      Get.to(() => const SearchPage());
      return;
    }
    router.go('/search');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * 0.34).clamp(160.0, 420.0)
            : 280.0;
        final isDesktop =
            Platform.isWindows || Platform.isLinux || Platform.isMacOS;
        // En horizontal de celular la pantalla mide ~300-390 de alto: el hero
        // con su tamaño normal (220 de mínimo + 28 de padding arriba y abajo)
        // se comía TODA la ventana, así que al hacer scroll no quedaba lugar
        // para las filas de cards y el inicio se sentía apretado. Acá se pone
        // compacto — mismo contenido, menos aire y tipografía más chica.
        final compact = Platform.isAndroid &&
            MediaQuery.of(context).orientation == Orientation.landscape;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (imageWidth * dpr).ceil().clamp(1, 4096).toInt();

        return Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: compact ? 132 : 220),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: gradient ?? HomeTheme.heroGradient,
                  ),
                ),
              ),
              if (background != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: imageWidth,
                  // Sin key acá (a propósito): _HeroCover es el mismo Element
                  // entre un refresh y otro, así que su AnimatedSwitcher
                  // interno mantiene su estado y puede animar el crossfade
                  // entre portada vieja y nueva. Con key: ValueKey(cover) acá
                  // (como estaba antes) Flutter destruye y reconstruye TODO
                  // el subárbol —AnimatedSwitcher incluido— en cada cambio de
                  // portada, así que nunca llegaba a ver una portada
                  // "anterior" de la cual hacer fade: la nueva aparecía de
                  // golpe como si fuera la primera vez. La key que sí importa
                  // para el AnimatedSwitcher va en el child real, más abajo.
                  child: _HeroCover(
                    background: background!,
                    imageWidth: imageWidth,
                    cacheWidth: cacheWidth,
                    filterQuality:
                        isDesktop ? FilterQuality.low : FilterQuality.medium,
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(compact ? 16 : 28),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                HomeTheme.textPrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Destacado',
                            style: TextStyle(
                              color: HomeTheme.textPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 14),
                        Text(
                          'home.hero-title'.i18n,
                          style: TextStyle(
                            color: HomeTheme.textPrimary,
                            fontSize: compact ? 21 : 30,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: compact ? 6 : 10),
                        Text(
                          'home.hero-subtitle'.i18n,
                          // Compacto: el subtítulo es lo primero que sobra
                          // cuando el alto escasea, así que se acota en vez de
                          // empujar el CTA fuera de la vista.
                          maxLines: compact ? 2 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: HomeTheme.textPrimary.withValues(alpha: 0.8),
                            fontSize: compact ? 12.5 : 14.5,
                            height: compact ? 1.3 : 1.5,
                          ),
                        ),
                        SizedBox(height: compact ? 10 : 18),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _openSearch,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: HomeTheme.textPrimary,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    'home.hero-cta'.i18n,
                                    style: TextStyle(
                                      // El botón se pinta con el color de
                                      // máximo contraste, así que su texto va
                                      // en el opuesto. Estaba fijo en casi
                                      // negro: en modo claro quedaba una caja
                                      // negra con el texto negro adentro.
                                      color: HomeTheme.sobreContraste,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroCover extends StatelessWidget {
  const _HeroCover({
    required this.background,
    required this.imageWidth,
    required this.cacheWidth,
    required this.filterQuality,
  });

  final HeroBackground background;
  final double imageWidth;
  final int cacheWidth;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final cover = CacheNetWorkImagePic(
      background.cover,
      fit: BoxFit.cover,
      width: imageWidth,
      height: double.infinity,
      headers: background.headers,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      alignment: const Alignment(0, -0.5),
    );
    final image = ShaderMask(
      // Esta key es la que de verdad dispara el crossfade: AnimatedSwitcher
      // solo anima cuando ve un child con una key DISTINTA a la anterior,
      // manteniéndose él mismo montado (ver comentario en HomeHeroBanner).
      key: ValueKey(background.cover),
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.transparent, Colors.white],
        stops: [0.0, 0.55],
      ).createShader(rect),
      child: cover,
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: image,
    );
  }
}
