import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/resume_history.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// La Biblioteca en Android TV.
///
/// ── Por qué es un archivo aparte y no una rama dentro de `LibraryPage` ───
///
/// `LibraryPage` está pensada para tocar con el dedo o hacer clic: tarjetas
/// y menús de `HomeMediaCard`/`HomeSection`, sin marco de foco para D-pad.
/// Hasta ahora, la categoría "Biblioteca" del Inicio de TV la reusaba tal
/// cual —la única de todo el shell de TV sin una versión propia—, así que
/// se veía y se manejaba distinto al resto de la app en un televisor.
///
/// Mismo criterio que ya se aplicó en `nsfw18_zone_page_tv.dart` para la
/// Zona +18: pantalla nueva y separada, mismo controller y los mismos
/// datos de siempre (`HomePageController`, sin tag), pero un árbol de
/// widgets propio — `FocusableCard` en cada tarjeta, filas horizontales de
/// verdad. Ningún widget de Android ni de escritorio.
///
/// Solo dos filas, Continuar viendo y Favoritos, y solo lo que es video —
/// regla ya existente del proyecto: en Android TV no se lee, en ninguna
/// zona. Lo de lectura sigue estando en el Historial de siempre.
class LibraryPageTv extends StatelessWidget {
  const LibraryPageTv({super.key});

  static const _tabVideo = 1;

  // Mismo patrón que ya usaba `_LibraryPageState.initState`: reusar el
  // controller si ya existe (cambiar de pestaña en Android destruye y
  // reconstruye el Home entero) en vez de registrar uno nuevo cada vez.
  HomePageController get _c => Get.isRegistered<HomePageController>()
      ? Get.find<HomePageController>()
      : Get.put(HomePageController());

  void _abrirHistorial(BuildContext context) {
    Get.to(const HistoryPage(initialTab: _tabVideo));
  }

  void _abrirDetalle(BuildContext context, String url, String package,
      {String? cover, Map<String, String>? headers}) {
    ExtensionUtils.openExtensionDetail(
      context,
      package: package,
      url: url,
      cover: cover,
      coverHeaders: headers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Padding(
      padding: HomeTheme.margenTv(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'common.library'.i18n,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: HomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Obx(() {
              final continuar = c.resents
                  .where((h) => h.type == ExtensionType.bangumi)
                  .toList(growable: false);
              final favoritos = c.favorites
                  .where((f) => f.type == ExtensionType.bangumi)
                  .toList(growable: false);
              if (continuar.isEmpty && favoritos.isEmpty) {
                return _BibliotecaVaciaTv(
                  onHistorial: () => _abrirHistorial(context),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (continuar.isNotEmpty)
                    _FilaBibliotecaTv(
                      titulo: 'home.continue-video'.i18n,
                      onVerTodo: () => _abrirHistorial(context),
                      items: [
                        for (final h in continuar)
                          _ItemBibliotecaTv(
                            key: ValueKey('cont-${h.package}|${h.url}'),
                            titulo: h.title,
                            subtitulo: FlutterI18n.translate(
                              context,
                              'home.watched-episode',
                              translationParams: {
                                'ep': ExtensionUtils.episodeNumberLabel(
                                  h.episodeTitle,
                                  h.episodeId,
                                ),
                              },
                            ),
                            cover: PortadaHistorial.de(h).url,
                            coverFile: PortadaHistorial.de(h).archivo,
                            headers: PortadaHistorial.de(h).necesitaHeaders
                                ? c.headersForPackage(h.package)
                                : null,
                            onTap: () => resumeHistoryItem(context, h),
                          ),
                      ],
                    ),
                  if (continuar.isNotEmpty && favoritos.isNotEmpty)
                    const SizedBox(height: 32),
                  if (favoritos.isNotEmpty)
                    _FilaBibliotecaTv(
                      titulo: 'home.favorite-video'.i18n,
                      onVerTodo: () => _abrirHistorial(context),
                      items: [
                        for (final f in favoritos)
                          _ItemBibliotecaTv(
                            key: ValueKey('fav-${f.package}|${f.url}'),
                            titulo: f.title,
                            subtitulo: 'home.favorite'.i18n,
                            cover: f.cover,
                            coverFile: null,
                            headers: c.headersForPackage(f.package),
                            onTap: () => _abrirDetalle(
                              context,
                              f.url,
                              f.package,
                              cover: f.cover,
                              headers: c.headersForPackage(f.package),
                            ),
                          ),
                      ],
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Una fila: el título de la sección (con "Ver todo" al lado) arriba, la
/// tira de tarjetas debajo.
class _FilaBibliotecaTv extends StatelessWidget {
  const _FilaBibliotecaTv({
    required this.titulo,
    required this.items,
    required this.onVerTodo,
  });

  final String titulo;
  final List<Widget> items;
  final VoidCallback onVerTodo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: HomeTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 14),
            FocusableCard(
              borderRadius: 999,
              onTap: onVerTodo,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: HomeTheme.cardSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: HomeTheme.border),
                ),
                child: Text(
                  'common.show-all'.i18n,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HomeTheme.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _ItemBibliotecaTv.alto,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) => items[i],
          ),
        ),
      ],
    );
  }
}

/// Una tarjeta: portada 16:9 (es vídeo, siempre) con marco de foco, título y
/// subtítulo debajo. Idéntica a `_ItemNsfw18Tv` — mismo diseño, sin el
/// acento rojo que ahí marca la Zona +18.
class _ItemBibliotecaTv extends StatelessWidget {
  const _ItemBibliotecaTv({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.cover,
    required this.coverFile,
    required this.headers,
    required this.onTap,
  });

  final String titulo;
  final String subtitulo;
  final String? cover;
  final File? coverFile;
  final Map<String, String>? headers;
  final VoidCallback onTap;

  static const _ancho = 280.0;
  static const _altoPortada = _ancho * 9 / 16;
  static const alto = _altoPortada + 54;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ancho,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusableCard(
            borderRadius: HomeTheme.radioTv,
            altoMarco: _altoPortada,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(HomeTheme.radioTv),
              child: SizedBox(
                width: _ancho,
                height: _altoPortada,
                child: coverFile != null
                    ? Image.file(
                        coverFile!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _SinPortadaTv(),
                      )
                    : CacheNetWorkImagePic(
                        cover ?? '',
                        fit: BoxFit.cover,
                        headers: headers,
                        cacheWidth: (_ancho * 2).round(),
                        fallback: const _SinPortadaTv(),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: HomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SinPortadaTv extends StatelessWidget {
  const _SinPortadaTv();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: HomeTheme.cardSurface,
      child: Icon(
        Icons.movie_outlined,
        color: HomeTheme.textMuted,
        size: 32,
      ),
    );
  }
}

/// Sin nada guardado todavía: ni en curso, ni en favoritos.
class _BibliotecaVaciaTv extends StatelessWidget {
  const _BibliotecaVaciaTv({required this.onHistorial});

  final VoidCallback onHistorial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined,
              color: HomeTheme.textMuted, size: 44),
          const SizedBox(height: 16),
          Text(
            'home.no-record'.i18n,
            textAlign: TextAlign.center,
            style: TextStyle(color: HomeTheme.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 20),
          FocusableCard(
            borderRadius: 999,
            onTap: onHistorial,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: HomeTheme.cardSurface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: HomeTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded,
                      size: 20, color: HomeTheme.textPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'home.see-history'.i18n,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: HomeTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
