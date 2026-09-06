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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 380,
          // ── Con scroll, no un tamaño fijo que confía en que entre ────
          //
          // El teclado completo (recientes + "123"/borrar + cinco filas de
          // letras) puede medir más de lo que queda de alto en un televisor
          // chico o con overscan grande. Sin nada que lo desplazara, lo que
          // no entraba se cortaba directo contra el borde de la pantalla —
          // fuera de la vista y, con el mando, fuera de alcance: no había
          // forma de bajar hasta ahí. Reportado en vivo con foto: "no me
          // deja navegar ni escribir en el teclado y está cortado el
          // fondo".
          //
          // No hace falta nada más que el `SingleChildScrollView`: el
          // resto de la app ya trae `RescateDeFoco`, que trae a la vista
          // sola cualquier tecla que reciba el foco dentro de CUALQUIER
          // scroll — el mismo mecanismo que ya usa toda la app, no algo
          // nuevo que mantener acá.
          // ── Centrado en vertical, no pegado arriba ────────────────────
          //
          // El teclado ocupa bastante menos que el alto de la pantalla, así
          // que arrancando arriba quedaba media pantalla vacía debajo y la
          // columna se leía como si se hubiera caído hacia el borde.
          // Pedido explícito: «el coso donde se escribe y los botones,
          // centralos».
          //
          // Sigue siendo desplazable: en un televisor de poca altura útil,
          // el `Center` deja de centrar y la columna se recorre como
          // cualquier otra, que es lo que evita que las últimas teclas
          // queden fuera de alcance.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Las últimas búsquedas, arriba del teclado ──────────────
                //
                // Solo mientras el campo está vacío: son un punto de partida
                // para no escribir nada, y una vez que ya se está escribiendo
                // o hay resultados en pantalla, dejan de aportar y solo
                // ocuparían lugar. Escribir letra por letra con un control
                // remoto es lo peor de cualquier app de TV — un botón con lo
                // ya buscado vale por diez letras.
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
