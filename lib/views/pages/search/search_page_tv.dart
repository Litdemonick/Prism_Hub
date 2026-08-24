import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/views/widgets/search/search_all_extension.dart';
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

  void _buscar(String texto) {
    setState(() => _texto = texto);
    // Se busca en vivo con cada tecla: el controller ya trae su propio
    // manejo de pedidos encadenados (ver `getResult`/`_randomKey`), así que
    // escribir rápido no apila búsquedas que se pisen.
    widget.c.submitSearch(texto);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TecladoTv(texto: _texto, onCambio: _buscar, accent: widget.accent),
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
            );
          }),
        ),
      ],
    );
  }
}
