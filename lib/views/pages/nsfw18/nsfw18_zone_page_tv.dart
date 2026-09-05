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
import 'package:prismhub/views/pages/nsfw18/nsfw18_search_page.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// El Inicio de la Zona +18 en Android TV.
///
/// ── Por qué es un archivo aparte y no una rama dentro de `Nsfw18ZonePage` ──
///
/// La pantalla de siempre (`nsfw18_zone_page.dart`) ya tenía una cabecera
/// adaptada a TV, pero el CUERPO seguía siendo el mismo que Android/
/// escritorio: el banner "Descubre tu próxima obsesión" pensado para tocar,
/// tarjetas y botones en píldora sin marco de foco pensado para D-pad.
/// Reportado en vivo con fotos: se veía la pantalla de siempre, estirada
/// sobre el televisor, no una pantalla de televisor de verdad.
///
/// En vez de seguir intercalando ramas `PlatformTv.esTelevisionSync` adentro
/// de un archivo pensado para mouse/dedo, esta es una pantalla nueva,
/// autocontenida, con SU PROPIO diseño — mismo criterio que ya se usa en
/// `home_page_tv.dart` para el Inicio normal. Comparte el controller y los
/// datos (mismo `HomePageController` con `HomePageController.zoneTag`, no
/// hay una copia de nada), pero ningún widget de Android o escritorio.
///
/// ── Por qué solo Continuar y Favoritos, sin catálogo ni banner ───────────
///
/// Pedido explícito: acá no hace falta explorar un catálogo entero como en
/// el Inicio normal —la Zona +18 es un rincón chico, no una tienda—, así
/// que la pantalla se reduce a lo que de verdad se usa seguido: seguir
/// viendo lo que se dejó a medias, y lo guardado como favorito. Para
/// encontrar algo nuevo está el botón de buscar, arriba.
///
/// ── Por qué solo vídeo ───────────────────────────────────────────────────
///
/// Regla ya existente del proyecto, repetida acá: en Android TV no se lee,
/// en ninguna zona. Los `History`/`Favorite` de lectura que puedan existir
/// (si se marcaron desde el teléfono) simplemente no aparecen en esta
/// pantalla — siguen estando en el Historial de siempre, a un toque del
/// botón de arriba, para quien de verdad los busque.
class Nsfw18ZonePageTv extends StatelessWidget {
  const Nsfw18ZonePageTv({super.key});

  static const _tabVideo = 1;

  // ── Por qué "registrar si no existe" y no un simple `Get.find` ─────────
  //
  // La pantalla de Android/escritorio (`Nsfw18ZonePage`) es la que hasta
  // ahora registraba este controller, la primera vez que se construía
  // (`late final c = Get.isRegistered(...) ? Get.find(...) : Get.put(...)`
  // en su propio `State`). Como esta pantalla nueva reemplaza a esa por
  // completo en TV, ese registro nunca llega a correr — sin repetir el
  // mismo patrón acá, el primer `Get.find` de más abajo revienta porque
  // nadie puso el controller todavía.
  HomePageController get _c =>
      Get.isRegistered<HomePageController>(tag: HomePageController.zoneTag)
          ? Get.find<HomePageController>(tag: HomePageController.zoneTag)
          : Get.put(
              HomePageController(nsfwOnly: true),
              tag: HomePageController.zoneTag,
            );

  void _abrirBuscador(BuildContext context) =>
      openNsfw18Search(context, yaAutorizado: true);

  void _abrirHistorial(BuildContext context) {
    Get.to(const HistoryPage(initialTab: _tabVideo, zone: true));
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
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: HomeTheme.margenTv(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CabeceraNsfw18Tv(
                onBuscar: () => _abrirBuscador(context),
                onHistorial: () => _abrirHistorial(context),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Obx(() {
                  final continuar = c.resents
                      .where((h) => h.type == ExtensionType.bangumi)
                      .toList(growable: false);
                  final favoritos = c.favorites
                      .where((f) => f.type == ExtensionType.bangumi)
                      .toList(growable: false);
                  if (continuar.isEmpty && favoritos.isEmpty) {
                    return _Nsfw18VacioTv(
                      onHistorial: () => _abrirHistorial(context),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (continuar.isNotEmpty)
                        _FilaNsfw18Tv(
                          titulo: 'home.continue-video'.i18n,
                          items: [
                            for (final h in continuar)
                              _ItemNsfw18Tv(
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
                        _FilaNsfw18Tv(
                          titulo: 'home.favorite-video'.i18n,
                          items: [
                            for (final f in favoritos)
                              _ItemNsfw18Tv(
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
        ),
      ),
    );
  }
}

/// El título + los dos atajos, arriba de todo. Mismo botón de volver grande
/// que ya usa `Nsfw18LockPage`, para que toda la Zona +18 se sienta como una
/// sola pantalla coherente y no como pedazos de distintos diseños.
class _CabeceraNsfw18Tv extends StatelessWidget {
  const _CabeceraNsfw18Tv({required this.onBuscar, required this.onHistorial});

  final VoidCallback onBuscar;
  final VoidCallback onHistorial;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FocusableCard(
          borderRadius: 999,
          accent: HomeTheme.accentRed,
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              shape: BoxShape.circle,
              border: Border.all(color: HomeTheme.border),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 26,
              color: HomeTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            'nsfw18.title'.i18n,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: HomeTheme.textPrimary,
            ),
          ),
        ),
        _BotonPildoraTv(
          icono: Icons.search_rounded,
          texto: 'common.search'.i18n,
          onTap: onBuscar,
        ),
        const SizedBox(width: 12),
        _BotonPildoraTv(
          icono: Icons.history_rounded,
          texto: 'home.see-history'.i18n,
          onTap: onHistorial,
        ),
      ],
    );
  }
}

/// Un botón en píldora de la cabecera — buscar, historial. Icono + texto:
/// desde el sillón un ícono solo no dice nada hasta que se enfoca.
class _BotonPildoraTv extends StatelessWidget {
  const _BotonPildoraTv({
    required this.icono,
    required this.texto,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      borderRadius: 999,
      accent: HomeTheme.accentRed,
      onTap: onTap,
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
            Icon(icono, size: 20, color: HomeTheme.textPrimary),
            const SizedBox(width: 8),
            Text(
              texto,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: HomeTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una fila: el título de la sección arriba, la tira de tarjetas debajo.
class _FilaNsfw18Tv extends StatelessWidget {
  const _FilaNsfw18Tv({required this.titulo, required this.items});

  final String titulo;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: HomeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _ItemNsfw18Tv.alto,
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
/// subtítulo debajo.
class _ItemNsfw18Tv extends StatelessWidget {
  const _ItemNsfw18Tv({
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
            accent: HomeTheme.accentRed,
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
class _Nsfw18VacioTv extends StatelessWidget {
  const _Nsfw18VacioTv({required this.onHistorial});

  final VoidCallback onHistorial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, color: HomeTheme.accentRed, size: 44),
          const SizedBox(height: 16),
          Text(
            'nsfw18.tv-empty'.i18n,
            textAlign: TextAlign.center,
            style: TextStyle(color: HomeTheme.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 20),
          _BotonPildoraTv(
            icono: Icons.history_rounded,
            texto: 'home.see-history'.i18n,
            onTap: onHistorial,
          ),
        ],
      ),
    );
  }
}
