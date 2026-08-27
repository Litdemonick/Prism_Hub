import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/horizontal_list.dart';

/// Un ítem ya con de qué extensión salió — para poder abrir su detalle y,
/// si hiciera falta, mostrar de dónde vino.
typedef _Hallazgo = ({String package, ExtensionListItem item});

/// Reemplazo de `SearchAllExtSearch` que agrupa por CATEGORÍA de contenido
/// (Películas/Series/Anime/Mangas), no por extensión.
///
/// ── Por qué ──────────────────────────────────────────────────────────────
///
/// Pedido explícito, con una captura de referencia: al escribir algo, el
/// buscador tiene que mostrar "Series"/"Películas"/etc. mezclando lo que
/// encontró CADA extensión bajo un mismo título — no una fila por
/// extensión (así se veía antes: "AnimeAV1", "AnimeFenix", una debajo de
/// la otra, cada una con lo suyo). El mecanismo de búsqueda no cambia en
/// nada (sigue siendo `SearchPageController` preguntándole a cada
/// extensión) — esto solo reacomoda lo que ya llegó.
///
/// La categoría de cada resultado sale de `ExtensionUtils.zonasDe(package)`
/// — la MISMA clasificación que ya usan las zonas de Inicio. Una extensión
/// sin clasificar (`contentKind` ausente) no se pierde: cae a una sección
/// aparte por tipo (Vídeo/Lectura), igual que en Inicio nunca desaparece.
class SearchPorCategoria extends StatelessWidget {
  const SearchPorCategoria({
    super.key,
    required this.kw,
    required this.runtimeList,
    required this.onClickMore,
  });

  final String kw;
  final List<SearchResult> runtimeList;

  /// Se mantiene por compatibilidad de firma con `SearchAllExtSearch` (el
  /// llamador es el mismo en `search_page.dart`) — acá no tiene sentido por
  /// extensión, así que no se usa: cada sección arma su propio "ver más"
  /// (a la zona correspondiente) o no lo ofrece.
  final Function(int) onClickMore;

  static const _ordenDeZonas = [
    ZonaPrincipal.peliculas,
    ZonaPrincipal.series,
    ZonaPrincipal.anime,
    ZonaPrincipal.mangas,
  ];

  /// Un mismo anime/manga/película suele estar en varias extensiones a la
  /// vez (JKAnime y TioAnime publican el mismo anime, por ejemplo) — pedido
  /// explícito: "que no haya duplicaciones". Se compara por título
  /// normalizado (minúsculas, sin tildes) en vez de por URL —dos
  /// extensiones nunca comparten la misma URL de por sí, así que eso no
  /// habría filtrado nada— y se queda con la primera que apareció, sea de
  /// la extensión que sea.
  List<_Hallazgo> _sinTitulosDuplicados(List<_Hallazgo> items) {
    final vistos = <String>{};
    return items.where((h) {
      final titulo = SearchText.normalize(h.item.title);
      return titulo.isEmpty || vistos.add(titulo);
    }).toList();
  }

  String _tituloDeZona(ZonaPrincipal z) => switch (z) {
        ZonaPrincipal.peliculas => 'home.zona-peliculas'.i18n,
        ZonaPrincipal.series => 'home.zona-series'.i18n,
        ZonaPrincipal.anime => 'home.zona-anime'.i18n,
        ZonaPrincipal.mangas => 'home.zona-mangas'.i18n,
      };

  String _rutaDeZona(ZonaPrincipal z) => switch (z) {
        ZonaPrincipal.peliculas => '/peliculas',
        ZonaPrincipal.series => '/series',
        ZonaPrincipal.anime => '/anime',
        ZonaPrincipal.mangas => '/mangas',
      };

  @override
  Widget build(BuildContext context) {
    if (runtimeList.isEmpty) {
      // Dos casos bien distintos, antes con el mismo mensaje: sin ninguna
      // extensión instalada, lo que hace falta es ir al Repositorio a
      // instalar una. Con extensiones instaladas pero todas desactivadas
      // (o inestables, ver ExtensionUtils.enabledRuntimes), instalar de
      // nuevo no soluciona nada — lo que hace falta es activarlas, y eso
      // se hace en Extensiones instaladas, no en el Repositorio.
      final hayInstaladas = ExtensionUtils.runtimes.isNotEmpty;
      return SizedBox(
        height: 300,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(hayInstaladas
                ? 'common.no-extension-enabled'.i18n
                : 'common.no-extension'.i18n),
            const SizedBox(height: 8),
            PlatformFilledButton(
              child: Text((hayInstaladas
                      ? "common.extension-installed"
                      : "common.extension-repo")
                  .i18n),
              onPressed: () {
                if (Platform.isAndroid) {
                  Get.find<MainController>().selectedTab.value =
                      MainController.tabExtensiones;
                  return;
                }
                router.push(hayInstaladas ? '/extension' : '/extension_repo');
              },
            )
          ],
        ),
      );
    }

    // ── Se reparte lo que ya llegó, se ignora lo que falta ────────────────
    //
    // Nada de esto espera a que TODAS las extensiones terminen: cada vez que
    // una responde, este build corre de nuevo (Obx en search_page.dart) y
    // sus ítems se suman a la categoría que corresponda — las secciones
    // van creciendo solas, igual que antes crecía cada fila por separado.
    final porZona = <ZonaPrincipal, List<_Hallazgo>>{};
    final sinClasificar = <ExtensionType, List<_Hallazgo>>{};
    final relevantes = <_Hallazgo>[];
    final consultaNormalizada = SearchText.normalize(kw);
    final tokens = SearchText.queryTokens(kw);
    var algunaConDatos = false;

    for (final r in runtimeList) {
      final data = r.result;
      if (data == null || data.isEmpty) continue;
      algunaConDatos = true;
      final package = r.runitme.extension.package;
      final zonas = ExtensionUtils.zonasDe(package);
      for (final item in data) {
        final hallazgo = (package: package, item: item);
        if (zonas.isEmpty) {
          (sinClasificar[r.runitme.extension.type] ??= []).add(hallazgo);
        } else {
          for (final z in zonas) {
            (porZona[z] ??= []).add(hallazgo);
          }
        }
        if (kw.trim().isEmpty) continue;
        final tituloNormalizado = SearchText.normalize(item.title);
        if (tituloNormalizado == consultaNormalizada ||
            SearchText.matchesTokens(item.title, tokens)) {
          relevantes.add(hallazgo);
        }
      }
    }

    if (!algunaConDatos) {
      // Ninguna extensión trajo nada todavía — puede ser que sigan
      // cargando (search_page.dart ya muestra su propio indicador arriba)
      // o que de verdad no haya nada. No se inventa un mensaje de error
      // acá: el estado de carga/error por extensión ya lo maneja la
      // pantalla que envuelve esto.
      return const SizedBox.shrink();
    }

    Widget seccion({
      required String titulo,
      required List<_Hallazgo> items,
      required VoidCallback verMas,
      // "Más relevantes" no lleva a ningún lado (no hay una zona propia
      // para eso) — sin esto, su título salía con la flechita y el cursor
      // de mano de una sección que sí navega, prometiendo un "ver más" que
      // nunca pasaba nada al tocarlo.
      bool mostrarFlecha = true,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HorizontalList(
          title: titulo,
          onClickMore: verMas,
          mostrarFlecha: mostrarFlecha,
          contentBuilder: (controller) => SizedBox(
            height: 240,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              controller: controller,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final h = items[i];
                return Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 16),
                  child: ExtensionItemCard(
                    key: ValueKey('${h.package}|${h.item.url}'),
                    title: h.item.title,
                    url: h.item.url,
                    package: h.package,
                    cover: h.item.cover,
                    update: h.item.update,
                    headers: h.item.headers,
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding:
          EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (relevantes.isNotEmpty) ...[
            seccion(
              titulo: 'search.most-relevant'.i18n,
              // Sin duplicados (el mismo título puede coincidir en más de
              // una extensión) y con el que coincide EXACTO con lo escrito
              // siempre primero — sin esto, el orden dependía de qué
              // extensión respondió antes, así que lo que se buscaba de
              // verdad podía aparecer después de una coincidencia parcial.
              items: ({
                for (final h in relevantes) '${h.package}|${h.item.url}': h
              }.values.toList()
                ..sort((a, b) {
                  int rango(_Hallazgo h) => SearchText.normalize(h.item.title) ==
                          consultaNormalizada
                      ? 0
                      : 1;
                  return rango(a).compareTo(rango(b));
                })),
              verMas: () {},
              mostrarFlecha: false,
            ),
            const SizedBox(height: 20),
          ],
          for (final z in _ordenDeZonas)
            if (porZona[z]?.isNotEmpty ?? false) ...[
              seccion(
                titulo: _tituloDeZona(z),
                items: _sinTitulosDuplicados(porZona[z]!),
                verMas: () => router.push(_rutaDeZona(z)),
              ),
              const SizedBox(height: 20),
            ],
          for (final entrada in sinClasificar.entries)
            if (entrada.value.isNotEmpty) ...[
              seccion(
                titulo: entrada.key == ExtensionType.bangumi
                    ? 'extension-type.video'.i18n
                    : 'extension-type.reading'.i18n,
                items: _sinTitulosDuplicados(entrada.value),
                verMas: () {},
              ),
              const SizedBox(height: 20),
            ],
        ],
      ),
    );
  }
}
