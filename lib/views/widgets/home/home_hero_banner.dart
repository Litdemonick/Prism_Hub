import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Banner — calca el hero del diseño (degradado, badge "Destacado",
// título+subtítulo, CTA). De fondo, una portada real random de tu
// contenido (favoritos/continuar viendo/recomendado) que cambia cada vez
// que se refresca el home — nunca una imagen fabricada.
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
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            // AnimatedSwitcher: transición suave cuando cambia la portada de
            // fondo (crossfade), en vez de un corte seco.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: background == null
                  ? const SizedBox.shrink(key: ValueKey('no-bg'))
                  : ImageFiltered(
                      key: ValueKey(background!.cover),
                      // Las portadas son thumbnails chicos — estirados a lo
                      // ancho del hero se ven pixelados. Un blur fuerte los
                      // convierte en un fondo ambiental prolijo (mismo truco
                      // que usan Spotify/Apple TV con arte de baja resolución)
                      // en vez de mostrar la pixelación.
                      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Transform.scale(
                        // Escala extra para que el blur no deje ver el borde
                        // transparente/repetido del filtro en los bordes.
                        scale: 1.15,
                        child: CacheNetWorkImagePic(
                          background!.cover,
                          fit: BoxFit.cover,
                          headers: background!.headers,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: background != null
                    ? HomeTheme.heroOverlayGradient
                    : HomeTheme.heroGradient,
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
  }
}
