import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/horizontal_list.dart';
import 'package:prismhub/views/widgets/card_default_placeholder.dart';

class SearchAllTile extends StatefulWidget {
  const SearchAllTile({
    super.key,
    required this.searchResult,
    required this.onClickMore,
    required this.kw,
  });

  final String kw;
  final SearchResult searchResult;
  final Function() onClickMore;

  @override
  State<SearchAllTile> createState() => _SearchAllTileState();
}

class _SearchAllTileState extends State<SearchAllTile> {
  @override
  Widget build(BuildContext context) {
    final list = HorizontalList(
      onClickMore: widget.onClickMore,
      title: widget.searchResult.runitme.extension.name,
      contentBuilder: (controller) {
        final data = widget.searchResult.result;

        // Un error con resultado previo válido (result no nulo/vacío) se
        // ignora acá — se prioriza seguir mostrando ese contenido viejo en
        // vez de taparlo con el mensaje de error apenas falla un refresh
        // (ver mismo criterio en SearchAllExtSearch, isConnFailureWithNoContent).
        final hasUsableData = data != null && data.isNotEmpty;
        if (widget.searchResult.error != null && !hasUsableData) {
          // Los errores de conexión sin datos no llegan acá: SearchAllExtSearch
          // los saca de la lista y los agrupa en un único banner arriba
          // (ver comentario ahí) — este Text queda para errores propios de
          // la extensión (no de red) o de conexión sin nada previo. Mismo
          // alto que las demás filas (antes un Text suelto sin SizedBox
          // hacía que la fila se "achicara" comparada con una con contenido).
          return SizedBox(
            height: Platform.isAndroid ? 170 : 280,
            child: Center(
              child: Text(
                friendlyError(widget.searchResult.error!),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        // Todavía no resolvió — antes esto se ocultaba entero (para evitar
        // el parpadeo de "aparece y desaparece" al refrescar), pero para
        // una extensión que JAMÁS tuvo contenido eso dejaba un hueco vacío
        // raro mientras carga. Ahora se muestran tarjetas con la imagen por
        // defecto (carddefaultoffline.png) del mismo tamaño exacto que las
        // reales: el contenedor nunca cambia de tamaño ni se mueve, solo se
        // reemplaza la imagen cuando llegan los datos.
        if (data == null) {
          return SizedBox(
            height: Platform.isAndroid ? 170 : 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ListView.builder(
                  scrollDirection: Axis.horizontal,
                  // physics fijo: mientras carga no hay nada real que
                  // scrollear y dejarlo scrolleable hacía que la fila se
                  // moviera sola bajo el dedo justo antes de que llegara
                  // el contenido.
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  itemBuilder: (context, index) => Container(
                    width: Platform.isAndroid ? 110 : 170,
                    margin: const EdgeInsets.only(right: 16),
                    child: const CardDefaultPlaceholder(),
                  ),
                ),
                // Spinner real encima de las placeholder — antes solo se
                // veía la imagen estática sin ningún indicio de que algo
                // seguía cargando (se sentía "plantado" en vez de
                // "cargando"). No se toca CardDefaultPlaceholder (su
                // diseño estático fue un pedido explícito anterior).
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(
                      HomeTheme.accentPink.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Mismo alto que las demás filas (antes un Text suelto sin SizedBox
        // hacía que la fila se "achicara" al no encontrar nada, en vez de
        // quedar del mismo tamaño que cuando carga o trae resultados).
        // Menciona la extensión — antes decía lo mismo genérico en cada
        // fila, sin aclarar CUÁL de todas es la que no encontró nada.
        if (data.isEmpty) {
          return SizedBox(
            height: Platform.isAndroid ? 170 : 280,
            child: Center(
              child: Text(
                FlutterI18n.translate(
                  context,
                  'common.no-result-in-extension',
                  translationParams: {
                    'extension': widget.searchResult.runitme.extension.name,
                  },
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: HomeTheme.textMuted),
              ),
            ),
          );
        }

        return SizedBox(
          height: Platform.isAndroid ? 170 : 280,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            controller: controller,
            itemCount: data.length,
            itemBuilder: ((context, index) {
              return Container(
                width: Platform.isAndroid ? 110 : 170,
                margin: const EdgeInsets.only(right: 16),
                child: ExtensionItemCard(
                  headers: data[index].headers,
                  key: ValueKey(data[index].url),
                  title: data[index].title,
                  url: data[index].url,
                  package: widget.searchResult.runitme.extension.package,
                  cover: data[index].cover,
                  update: data[index].update,
                ),
              );
            }),
          ),
        );
      },
    );

    if (Platform.isAndroid) return Center(child: list);

    // Banner/box propio por extensión — antes cada fila de resultados
    // quedaba flotando sobre el mismo fondo sin ningún límite visual entre
    // una extensión y la siguiente.
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomeTheme.border),
        ),
        child: list,
      ),
    );
  }
}
