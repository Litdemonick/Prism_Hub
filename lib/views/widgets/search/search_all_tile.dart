import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/horizontal_list.dart';

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
  // Fila cargando: el indicador solo, centrado, sin nada debajo.
  //
  // Antes se dibujaban cuatro tarjetas de relleno y el indicador iba encima
  // en un Stack centrado. El centro de la fila cae justo sobre una de esas
  // tarjetas, así que el aro se veía asomando POR DETRÁS de ella, como si
  // estuviera mal dibujado; y como el centro depende del ancho, al agrandar
  // o achicar la ventana el aro se corría solo. Sin tarjetas debajo no hay
  // con qué superponerse, sea cual sea el tamaño de la ventana.
  //
  // Mantiene el mismo alto que la fila con contenido, así que al llegar los
  // datos nada salta de lugar.
  Widget _cargando() {
    return SizedBox(
      height: Platform.isAndroid ? 170 : 280,
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(
              HomeTheme.accentPink.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = HorizontalList(
      onClickMore: widget.onClickMore,
      title: widget.searchResult.runitme.extension.name,
      contentBuilder: (controller) {
        final data = widget.searchResult.result;

        // Cargando: solo el indicador girando, nada más en la fila.
        //
        // Va ANTES que todo lo demás a propósito. Al buscar o al cambiar de
        // filtro, el controlador marca la extensión como no terminada pero
        // deja el resultado anterior intacto (a propósito, ver getResult:
        // así un refresh que falla no borra lo que ya estaba en pantalla).
        // El efecto era que la fila seguía mostrando las tarjetas de la
        // búsqueda VIEJA, quietas, sin ninguna señal de que se estaba
        // buscando otra cosa: parecía que el filtro no había hecho nada
        // hasta que de golpe cambiaba todo. Ahora la fila muestra el
        // indicador desde que arranca la búsqueda hasta que llega el
        // resultado nuevo.
        if (!widget.searchResult.completed) return _cargando();

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
        // Terminó pero no dejó ni resultado ni error. No debería pasar; si
        // pasa, es preferible seguir mostrando el indicador antes que un
        // hueco vacío sin explicación.
        if (data == null) return _cargando();

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
