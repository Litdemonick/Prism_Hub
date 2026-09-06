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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cajaCompleta) {
      // ── Medido ACÁ, antes de entrar a ningún scroll ────────────────────
      //
      // Adentro de un `SingleChildScrollView` cualquier medición de alto da
      // "sin límite" —así es como puede desplazarse—, así que el alto de
      // verdad hay que sacarlo de afuera, antes de entrar a él.
      final alturaTotal = cajaCompleta.maxHeight;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // El teclado mide 380 (ver `TecladoTv.ancho` más abajo); el
            // resto es aire para que el marco de foco no se corte contra
            // el borde del scroll — ver el porqué en el padding, unas
            // líneas abajo.
            width: 380 + HomeTheme.aireDeFocoTv * 2,
            height: alturaTotal.isFinite ? alturaTotal : null,
            child: SingleChildScrollView(
              // ── Red de seguridad, no la forma normal de llegar ─────────
              //
              // El `FittedBox` de abajo achica todo el bloque —recientes más
              // teclado— para que entre ENTERO en el alto disponible, así
              // que en el uso normal esto nunca llega a desplazarse. Queda
              // puesto por si algún televisor midiera algo raro: es
              // preferible poder bajar un pelo a perder una tecla del todo.
              //
              // Aire adentro del scroll, no afuera: un `SingleChildScrollView`
              // RECORTA lo que se sale de él, y el marco de foco se dibuja
              // unos píxeles hacia afuera de cada tecla — mismo criterio que
              // ya usa `ColumnaDeAcciones` para el mismo problema. Reportado
              // en vivo con foto.
              padding: const EdgeInsets.symmetric(
                horizontal: HomeTheme.aireDeFocoTv,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: alturaTotal.isFinite ? alturaTotal : 0,
                ),
                // ── Se achica para entrar entero, no se desplaza ─────────
                //
                // El bloque completo (recientes + teclado) podía medir más
                // que el alto útil de un televisor chico, o de uno con las
                // últimas búsquedas ocupando lugar arriba. Antes esto se
                // resolvía centrando y dejando que lo que no entrara se
                // desplazara — y desplazarse para tocar una tecla es
                // justamente lo que no se puede hacer con un mando de un
                // tirón. Pedido explícito, varias veces: «que se vean todos
                // los botones sin hacer scroll».
                //
                // `FittedBox` mide el tamaño NATURAL del contenido (sin
                // ningún límite) y lo escala entero, de una sola vez, para
                // que entre en el espacio real — sea cual sea la cantidad
                // de búsquedas recientes o el alto del televisor. No hace
                // falta adivinar ningún número: si entra, queda a tamaño
                // normal y centrado; si no entra, se achica lo justo.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 380,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Las últimas búsquedas, arriba del teclado ────
                        //
                        // Solo mientras el campo está vacío: son un punto
                        // de partida para no escribir nada, y una vez que
                        // ya se está escribiendo o hay resultados en
                        // pantalla, dejan de aportar y solo ocuparían
                        // lugar. Escribir letra por letra con un control
                        // remoto es lo peor de cualquier app de TV — un
                        // botón con lo ya buscado vale por diez letras.
                        if (_texto.isEmpty && _recientes.isNotEmpty)
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
                        ),
                      ],
                    ),
                  ),
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
            for (final termino in terminos)
              FocusableCard(
                borderRadius: 999,
                accent: accent,
                onTap: () => onElegir(termino),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
      ],
    );
  }
}
