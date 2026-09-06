import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/horizontal_list.dart';
import 'package:prismhub/views/widgets/tv/recorte_de_fila.dart';

/// El recorte de fila de televisor, solo cuando toca.
///
/// Corta a los costados y deja pasar arriba y abajo, que es por donde sale
/// el marco de selección. Ver `RecorteDeFila`.
Widget _envolverParaTv(bool tv, Widget fila) {
  if (!tv) return fila;
  return ClipRect(
    clipper: const RecorteDeFila(aireLateral: 24),
    child: fila,
  );
}

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
  /// Cuánto se deja girar la rueda antes de avisar que algo va mal.
  ///
  /// Con un sitio caído la fila se quedaba girando para siempre, sin decir
  /// nada. Y desde afuera eso se lee como que la app se colgó, cuando en
  /// realidad está esperando a un servidor que no contesta. Medido en LaMovie
  /// el 2026-08-06: su propia portada tardaba entre 21 y 27 segundos, y abierta
  /// en un navegador directamente no cargaba.
  ///
  /// Doce segundos: por encima de lo que tarda cualquier extensión sana —las
  /// demás contestan en dos o tres— y por debajo del límite del puente de red,
  /// que corta a los veinte. Así el aviso llega ANTES de que el pedido muera,
  /// que es cuando quien mira ya se está preguntando qué pasa.
  static const _tardaDemasiado = Duration(seconds: 12);

  Timer? _reloj;
  bool _avisar = false;

  @override
  void initState() {
    super.initState();
    _mirarSiTarda();
  }

  @override
  void didUpdateWidget(SearchAllTile viejo) {
    super.didUpdateWidget(viejo);
    // Búsqueda nueva o refresco: la cuenta empieza de cero.
    if (viejo.kw != widget.kw ||
        viejo.searchResult.completed != widget.searchResult.completed) {
      _mirarSiTarda();
    }
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _mirarSiTarda() {
    _reloj?.cancel();
    if (_avisar) setState(() => _avisar = false);
    if (widget.searchResult.completed) return;
    _reloj = Timer(_tardaDemasiado, () {
      if (!mounted || widget.searchResult.completed) return;
      setState(() => _avisar = true);
    });
  }

  // ── Fila cargando: bloques que brillan, como en Inicio ──────────────────
  //
  // OJO, esto ya se intentó una vez y se sacó. Se dibujaban cuatro tarjetas de
  // relleno con la RUEDA ENCIMA, centrada en un Stack. El centro de la fila
  // cae justo sobre una de esas tarjetas, así que el aro se veía asomando por
  // detrás de ella; y como el centro depende del ancho, al cambiar el tamaño
  // de la ventana el aro se corría solo. Por eso quedó la rueda sola.
  //
  // Los bloques vuelven, pero SIN la rueda: no hay nada centrado que pueda
  // superponerse con ellos. Lo único que va encima es el aviso de "está
  // tardando", y va sobre un velo que lo separa del fondo — y solo aparece a
  // los doce segundos, no siempre.
  //
  // El motivo de traerlos es el de Inicio: la fila ya tiene la forma que va a
  // tener con contenido, así que al llegar las portadas nada salta de lugar. Y
  // con varias extensiones buscando a la vez, es lo que evita la pantalla
  // llena de ruedas —o de avisos repetidos— cuando la red está caída.

  /// El ancho de una tarjeta de esta fila.
  ///
  /// En el teléfono es el MISMO que el del Inicio (HomeMediaCard.androidWidth):
  /// estaba en 110 contra los 150 de allá, y al pasar de una zona a la otra las
  /// portadas se veían encogidas sin ningún motivo. Con el mismo número, la
  /// app se siente una sola.
  ///
  /// Con nombre y en un solo lugar porque lo usan las tarjetas de verdad Y los
  /// bloques que esperan: si se separan, al llegar el contenido todo se corre.
  static double get anchoTarjeta =>
      Platform.isAndroid ? HomeMediaCard.androidWidth : 170;

  /// El alto de la fila. Sigue al ancho: la portada guarda su proporción y
  /// debajo van el título y la línea de la extensión.
  ///
  /// Antes usaba HomeMediaCard.androidHeight (233) y 280 en escritorio, que
  /// eran el alto de la tarjeta CARGADA (imagen flexible + título +
  /// subtítulo) pero no alcanzaban para el esqueleto de espera: EsqueletoTarjeta
  /// arma su bloque de portada con proporción FIJA 2:3 (ancho*3/2 de alto) más
  /// 38 de textos (8+12+6+12), y esa cuenta da más que la tarjeta cargada.
  /// Con el número viejo, la fila entera desbordaba por la diferencia
  /// mientras esperaba resultados — confirmado en vivo: "overflowed by 13
  /// pixels" en escritorio (293 necesarios contra 280 disponibles) y por más
  /// todavía en el teléfono (290 contra 233). El número de acá es el que
  /// pide el esqueleto, con la MISMA fórmula que EsqueletoTarjeta.
  static double get altoFila =>
      anchoTarjeta * 3 / 2 + 8 + 12 + 6 + 12;

  Widget _cargando() {
    final alto = altoFila;
    return SizedBox(
      height: alto,
      child: Stack(
        children: [
          // ── Bloques brillando, no una rueda ──────────────────────────────
          //
          // Es lo mismo que hace el Inicio, y por el mismo motivo: la fila ya
          // tiene la forma que va a tener cuando llegue el contenido, así que
          // al llegar las portadas nada se mueve. Una rueda centrada deja la
          // fila vacía y después todo aparece de golpe.
          //
          // Y con varias extensiones buscando a la vez, esto es lo que evita
          // la pantalla llena de ruedas —o de avisos repetidos— cuando la red
          // está caída: se ve una zona cargando, que es lo que de verdad está
          // pasando.
          // Los que ENTRAN, no ocho fijos: en una ventana ancha la fila de
          // bloques se cortaba a media pantalla y quedaba un vacío al costado,
          // que se lee como «esta extensión ya trajo y trajo poco». Ver
          // EsqueletoDeFila.
          EsqueletoDeFila(ancho: anchoTarjeta),
          // El aviso de "está tardando" va ENCIMA de los bloques, centrado y
          // sobre un velo, para que se lea sin tapar la forma de la fila.
          if (_avisar)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: HomeTheme.bg.withValues(alpha: 0.72),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_top_rounded,
                          size: 20, color: HomeTheme.textMuted),
                      const SizedBox(height: 10),
                      // Ver _tardaDemasiado: unos bloques que brillan sin fin
                      // y sin explicar nada se leen como que la app se colgó.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          FlutterI18n.translate(
                            context,
                            'common.extension-lenta',
                            translationParams: {
                              's': widget.searchResult.runitme.extension.name,
                            },
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: HomeTheme.textMuted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
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

        // ── Sin conexión: bloques, no un aviso ────────────────────────────
        //
        // Decisión del usuario. Donde hay tarjetas, la zona se queda con los
        // bloques brillando y no se escribe nada: con muchas extensiones
        // instaladas, un aviso por fila —o incluso uno solo arriba— llenaba
        // la pantalla de texto rojo en vez de contenido.
        //
        // Solo cuando la fila NO tiene nada que mostrar. Si ya había cargado
        // algo antes, se sigue viendo eso: taparlo con bloques sería perder
        // contenido que el usuario ya tenía delante.
        if (widget.searchResult.error != null &&
            isConnectionError(widget.searchResult.error) &&
            (data == null || data.isEmpty)) {
          return _cargando();
        }

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
            height: altoFila,
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
            height: altoFila,
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
                style: TextStyle(color: HomeTheme.textMuted),
              ),
            ),
          );
        }

        final tv = PlatformTv.esTelevisionSync;
        return SizedBox(
          height: altoFila,
          // ── En televisor, el mismo trato que las filas de Inicio ──────
          //
          // El marco de selección se dibuja POR FUERA de la tarjeta, y una
          // lista recorta contra sus bordes: acá la fila iba sin nada, así
          // que la tarjeta enfocada quedaba con el marco mordido arriba,
          // abajo y en la primera de la izquierda. Reportado con foto: «en
          // el buscador, al seleccionar una card se corta, no hay aire».
          //
          // `RecorteDeFila` corta a los costados —donde molesta, para que
          // las tarjetas que salen no se dibujen sobre el resto— y deja
          // pasar arriba y abajo, que es por donde sale el marco. Fuera de
          // televisor todo queda como estaba.
          child: _envolverParaTv(
            tv,
            ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: tv ? Clip.none : Clip.hardEdge,
            padding: tv
                ? const EdgeInsets.symmetric(
                    horizontal: HomeTheme.aireDeFocoTv,
                  )
                : EdgeInsets.zero,
            controller: controller,
            itemCount: data.length,
            itemBuilder: ((context, index) {
              return Container(
                width: anchoTarjeta,
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
