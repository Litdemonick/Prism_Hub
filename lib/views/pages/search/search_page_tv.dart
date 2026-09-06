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
  /// Confiable porque `_BusquedasRecientesTv` ahora acota cuántos CHIPS
  /// pide (ver `_maximoDeChips` ahí) en vez de cuánto ALTO les da — así
  /// nunca envuelve a más de dos líneas largas, y este número alcanza de
  /// sobra para esas dos líneas más el encabezado. El teclado usa esto
  /// para saber cuánto le queda a él, sin tener que adivinar.
  static const _altoMaximoDeRecientes = 130.0;

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
  });

  final List<String> terminos;
  final Color accent;
  final ValueChanged<String> onElegir;
  final VoidCallback onBorrar;

  /// Cuántas se muestran como mucho.
  ///
  /// ── Por qué un número de chips y no un alto ──────────────────────────
  ///
  /// Un alto fijo con scroll dejaba a la vista un renglón A MEDIAS —el de
  /// más abajo, cortado por la mitad— apenas había más búsquedas de las
  /// que entraban de una. Reportado en vivo con foto: «así no, que se vea
  /// bien, sin cortes». Un renglón entero o nada: acotando cuántos chips
  /// se PIDEN en vez de cuánto ALTO se les da, lo que se dibuja siempre
  /// son líneas completas — nunca una a medio cortar.
  ///
  /// Con ocho todavía se pasaba: un término largo ocupa buena parte del
  /// ancho disponible (180 como mucho, ver el tope más abajo), así que en
  /// la práctica entraban solo dos por línea — ocho eran cuatro líneas, no
  /// las dos que se habían calculado, y el teclado de abajo se quedaba sin
  /// lugar otra vez. Reportado en vivo con foto: «no debe agregar más
  /// para que no tenga que hacer scroll». Con cuatro, incluso en el peor
  /// caso (todos términos largos, dos por línea) entran en dos líneas de
  /// verdad. Siguen siendo las más recientes: se guardan todas igual,
  /// esto solo decide cuántas se OFRECEN de entrada.
  static const _maximoDeChips = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final termino in terminos.take(_maximoDeChips))
              FocusableCard(
                borderRadius: 999,
                accent: accent,
                onTap: () => onElegir(termino),
                // ── Con un tope de ancho, no confiando solo en la elipsis ──
                //
                // `Text(overflow: ellipsis)` recorta el texto que le sobra,
                // pero necesita que ALGUIEN le diga hasta dónde llegar. Un
                // `Wrap` no achica a sus hijos: si el término guardado era
                // larguísimo —alguien mantuvo apretada una tecla— el chip
                // entero pedía el ancho que hiciera falta y se salía de la
                // pantalla por la derecha, elipsis y todo ignorados.
                // Reportado en vivo con foto: "RIGHT OVERFLOWED BY 2.9
                // PIXELS" con un término de más de treinta letras.
                //
                // Con un ancho máximo puesto ACÁ, el chip nunca pide más de
                // la cuenta y la elipsis por fin tiene contra qué recortar.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
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
                        Flexible(
                          child: Text(
                            termino,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: HomeTheme.textPrimary,
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
      ],
    );
  }
}
