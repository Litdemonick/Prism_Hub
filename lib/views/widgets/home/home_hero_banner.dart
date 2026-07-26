import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
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
  const HomeHeroBanner({super.key, this.background});
  final HeroBackground? background;

  void _openSearch() {
    if (Platform.isAndroid) {
      Get.find<MainController>().changeTab(1);
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

        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 220),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: HomeTheme.heroGradient),
                ),
              ),
              if (background != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: imageWidth,
                  // AnimatedSwitcher: transición suave cuando cambia la
                  // portada de fondo (crossfade), en vez de un corte seco.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    child: ShaderMask(
                      key: ValueKey(background!.cover),
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Colors.transparent, Colors.white],
                        stops: [0.0, 0.55],
                      ).createShader(rect),
                      child: CacheNetWorkImagePic(
                        background!.cover,
                        fit: BoxFit.cover,
                        width: imageWidth,
                        height: double.infinity,
                        headers: background!.headers,
                        filterQuality: FilterQuality.high,
                        // Sesga el recorte hacia arriba — en una portada
                        // vertical ahí suele estar la cara/personaje, no el
                        // fondo/torso del centro.
                        alignment: const Alignment(0, -0.5),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(28),
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
                            color: HomeTheme.textPrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Destacado',
                            style: TextStyle(
                              color: HomeTheme.textPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'home.hero-title'.i18n,
                          style: const TextStyle(
                            color: HomeTheme.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'home.hero-subtitle'.i18n,
                          style: TextStyle(
                            color: HomeTheme.textPrimary.withValues(alpha: 0.8),
                            fontSize: 14.5,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
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
                                    style: const TextStyle(
                                      color: Color(0xFF17141F),
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
