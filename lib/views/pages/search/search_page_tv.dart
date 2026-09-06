import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/utils/busquedas_recientes.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/search/search_all_extension.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/tv/teclado_tv.dart';

// ─── El buscador de Android TV ──────────────────────────────────────────
//
// Teclado en pantalla a la izquierda (ver TecladoTv) y resultados a la
// derecha, siempre a la vista.
//
// Lo que NO cambia: quién busca. `SearchPageController` ya consulta a TODAS
// las extensiones instaladas a la vez y `SearchAllExtSearch` ya dibuja una
// fila por extensión — es lo mismo que usan Android y escritorio. Acá solo
// cambia cómo se escribe y cómo se reparte la pantalla.
class SearchTV extends StatefulWidget {
  const SearchTV({
    super.key,
    required this.c,
    required this.accent,
    required this.onClickMore,
  });

  final SearchPageController c;
  final Color accent;
  final void Function(int index) onClickMore;

  @override
  State<SearchTV> createState() => _SearchTVState();
}

class _SearchTVState extends State<SearchTV> {
  late String _texto = widget.c.search.value;
  List<String> _recientes = BusquedasRecientes.obtener();

  /// El guardado no es en cada tecla — mientras se está escribiendo, lo
  /// escrito todavía no es una búsqueda "de verdad", es una palabra a
  /// medio terminar. Se anota recién cuando el usuario deja de tocar el
  /// mando un rato, que es la señal más simple de que llegó a lo que
  /// quería escribir.
  Timer? _guardadoDemorado;

  @override
  void dispose() {
    _guardadoDemorado?.cancel();
    super.dispose();
  }

  void _buscar(String texto) {
    setState(() => _texto = texto);
    // Se busca en vivo con cada tecla: el controller ya trae su propio
    // manejo de pedidos encadenados (ver `getResult`/`_randomKey`), así que
    // escribir rápido no apila búsquedas que se pisen.
    widget.c.submitSearch(texto);
    _guardadoDemorado?.cancel();
    if (texto.trim().isEmpty) return;
    _guardadoDemorado = Timer(const Duration(milliseconds: 1200), () {
      BusquedasRecientes.agregar(texto).then((_) {
        if (mounted) setState(() => _recientes = BusquedasRecientes.obtener());
      });
    });
  }

  Future<void> _borrarRecientes() async {
    await BusquedasRecientes.limpiar();
    if (mounted) setState(() => _recientes = BusquedasRecientes.obtener());
  }

  /// Cuánto puede llegar a medir el bloque de "últimas búsquedas".
  ///
  /// Es un TOPE, no una estimación: `_BusquedasRecientesTv` no deja que sus
  /// chips crezcan más allá de esto (ver `maxHeight` ahí). Con un número que
  /// de verdad se cumple, el teclado puede confiar en él para saber cuánto
  /// le queda a él — a diferencia de adivinar cuántas líneas ocupan los
  /// chips, que dependía de qué se hubiera buscado antes.
  static const _altoMaximoDeRecientes = 96.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cajaCompleta) {
      // ── Medido ACÁ, antes de entrar a ningún scroll ────────────────────
      //
      // Ver el porqué largo en `TecladoTv.alturaDisponible`: adentro de un
      // `SingleChildScrollView` cualquier medición de alto da "sin límite"
      // —así es como puede desplazarse—, así que el alto de verdad hay que
      // sacarlo de afuera, antes de entrar a él.
      final alturaTotal = cajaCompleta.maxHeight;
      final hayRecientes = _texto.isEmpty && _recientes.isNotEmpty;
      final alturaParaElTeclado = alturaTotal.isFinite
          ? alturaTotal -
              (hayRecientes ? _altoMaximoDeRecientes + 16 : 0.0) -
              HomeTheme.aireDeFocoTv * 2
          : null;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // El teclado mide 380 (ver `TecladoTv.ancho` más abajo); el
            // resto es aire para que el marco de foco no se corte contra
            // el borde del scroll — ver el porqué en el padding, unas
            // líneas abajo.
            width: 380 + HomeTheme.aireDeFocoTv * 2,
            child: SingleChildScrollView(
              // ── Red de seguridad, no la forma normal de llegar ─────────
              //
              // El achicado de `TecladoTv` (ver `alturaDisponible`) hace
              // que en el uso normal esto no llegue a desplazarse. Queda
              // puesto por si algún televisor midiera algo que no se
              // previó: preferible poder bajar un pelo a perder una tecla
              // del todo.
              //
              // Aire a los CUATRO lados, no solo a los costados: un
              // `SingleChildScrollView` RECORTA lo que se sale de él, y el
              // marco de foco se dibuja unos píxeles hacia afuera de cada
              // tecla — sin aire arriba, la primera fila ("123"/borrar)
              // quedaba con el marco mordido contra ese borde. Reportado
              // en vivo con foto. Mismo criterio que ya usa
              // `ColumnaDeAcciones` para el mismo problema.
              padding: const EdgeInsets.symmetric(
                horizontal: HomeTheme.aireDeFocoTv,
                vertical: HomeTheme.aireDeFocoTv,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: alturaTotal.isFinite
                      ? alturaTotal - HomeTheme.aireDeFocoTv * 2
                      : 0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Las últimas búsquedas, arriba del teclado ────────
                    //
                    // Solo mientras el campo está vacío: son un punto de
                    // partida para no escribir nada, y una vez que ya se
                    // está escribiendo o hay resultados en pantalla, dejan
                    // de aportar y solo ocuparían lugar. Escribir letra
                    // por letra con un control remoto es lo peor de
                    // cualquier app de TV — un botón con lo ya buscado
                    // vale por diez letras.
                    if (hayRecientes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _BusquedasRecientesTv(
                          terminos: _recientes,
                          accent: widget.accent,
                          onElegir: _buscar,
                          onBorrar: _borrarRecientes,
                          alturaMaxima: _altoMaximoDeRecientes,
                        ),
                      ),
                    TecladoTv(
                      texto: _texto,
                      onCambio: _buscar,
                      accent: widget.accent,
                      ancho: 380,
                      alturaDisponible: alturaParaElTeclado,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Los resultados: los mismos de siempre, sin envolver en nada
          // especial — cada tarjeta ya trae su propio foco por dentro (ver
          // ExtensionItemCard, que se envuelve sola en TV).
          Expanded(
            child: Obx(() {
              // ignore: invalid_use_of_protected_member
              final list = widget.c.searchResultList.value;
              return SearchAllExtSearch(
                kw: widget.c.search.value,
                runtimeList: list,
                onClickMore: widget.onClickMore,
                accent: widget.accent,
              );
            }),
          ),
        ],
      );
    });
  }
}

/// La fila de chips con las últimas búsquedas.
class _BusquedasRecientesTv extends StatelessWidget {
  const _BusquedasRecientesTv({
    required this.terminos,
    required this.accent,
    required this.onElegir,
    required this.onBorrar,
    required this.alturaMaxima,
  });

  final List<String> terminos;
  final Color accent;
  final ValueChanged<String> onElegir;
  final VoidCallback onBorrar;

  /// Tope real, no una sugerencia: ver `SearchTV._altoMaximoDeRecientes`.
  ///
  /// Con muchas búsquedas recientes de nombres largos, los chips pueden
  /// envolver a más líneas de las que caben en el lugar que el teclado le
  /// dejó reservado. Antes de esto, esa diferencia se la comía el
  /// teclado —empujado hacia abajo, sin entrar entero—. Recortando ACÁ en
  /// cambio, lo que no entra son las últimas búsquedas más viejas, que
  /// siguen estando (se guardan igual) y vuelven a aparecer apenas hay
  /// lugar; el teclado nunca se entera de que faltó algo.
  final double alturaMaxima;

  @override
  Widget build(BuildContext context) {
    // ── Alto FIJO, no un tope que igual desborda ────────────────────────
    //
    // Un `ConstrainedBox(maxHeight)` alrededor de un `Column` no evita el
    // desborde: si los chips envuelven a más líneas de las que entran, es
    // el propio `Column` el que sigue midiendo de más y Flutter lo avisa
    // con el cartel de "RenderFlex overflowed" — el `ClipRect` de afuera
    // solo tapa lo que se ve, no la medida. Reportado en vivo, con foto:
    // "BOTTOM OVERFLOWED BY 89 PIXELS" justo debajo de los chips.
    //
    // Con un alto EXACTO en vez de un tope, y el renglón de las últimas
    // búsquedas puesto en un `Expanded` con su propio scroll, lo que no
    // entra se desplaza ahí adentro en vez de desbordar: un
    // `SingleChildScrollView` nunca mide de más, sea cual sea su
    // contenido.
    return SizedBox(
      height: alturaMaxima,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── El encabezado, con aire para su propio marco de foco ───────
          //
          // El botón de borrar es una `FocusableCard` como cualquier otra:
          // su anillo se dibuja unos píxeles hacia afuera. Pegado al borde
          // de arriba de este bloque —que es, a su vez, el borde de arriba
          // del scroll que lo contiene— quedaba mordido. Reportado en vivo
          // con foto: «el botón de borrar se corta con los bordes
          // rosados». Un poco de aire alrededor alcanza para que el anillo
          // entre entero.
          Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Text(
                  'search.recent'.i18n,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: HomeTheme.textMuted,
                  ),
                ),
                const Spacer(),
                FocusableCard(
                  borderRadius: 8,
                  onTap: onBorrar,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: HomeTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // ── Los chips, con su propio scroll ─────────────────────────────
          //
          // `Expanded` le da a esto lo que quede del alto FIJO de arriba
          // (ver el porqué en el comentario grande de más arriba), y el
          // `SingleChildScrollView` nunca desborda sea cual sea la
          // cantidad de búsquedas guardadas: lo que no entra se desplaza
          // acá adentro en vez de tirar el "RenderFlex overflowed" contra
          // el teclado de abajo.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final termino in terminos)
                    FocusableCard(
                      borderRadius: 999,
                      accent: accent,
                      onTap: () => onElegir(termino),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: HomeTheme.cardSurface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: HomeTheme.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_rounded,
                                size: 15, color: HomeTheme.textMuted),
                            const SizedBox(width: 6),
                            Text(
                              termino,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
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
            ),
          ),
        ],
      ),
    );
  }
}
