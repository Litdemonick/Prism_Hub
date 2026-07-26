import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/controllers/search_controller.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/views/widgets/search/search_all_tile.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/button.dart';

class SearchAllExtSearch extends StatefulWidget {
  const SearchAllExtSearch({
    super.key,
    required this.kw,
    required this.runtimeList,
    required this.onClickMore,
  });
  final String kw;
  final List<SearchResult> runtimeList;
  final Function(int) onClickMore;

  @override
  State<SearchAllExtSearch> createState() => _SearchAllExtSearchState();
}

class _SearchAllExtSearchState extends State<SearchAllExtSearch> {
  @override
  Widget build(BuildContext context) {
    if (widget.runtimeList.isEmpty) {
      return SizedBox(
        height: 300,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('common.no-extension'.i18n),
            const SizedBox(height: 8),
            PlatformFilledButton(
              child: Text("common.extension-repo".i18n),
              onPressed: () {
                if (Platform.isAndroid) {
                  Get.find<MainController>().selectedTab.value = 2;
                  return;
                }
                router.push('/extension_repo');
              },
            )
          ],
        ),
      );
    }
    // Errores de conexión: antes cada extensión sin internet mostraba su
    // propia fila con ícono wifi-off — con muchas extensiones instaladas eso
    // repetía el mismo aviso N veces. Ahora se agrupan en un único banner
    // arriba y esas filas individuales se ocultan (no aportan nada más que
    // "esta también falló por lo mismo"); errores propios de la extensión
    // (no de red) siguen mostrándose por fila, sin cambios.
    //
    // Solo se agrupan/ocultan las que NO tienen ningún resultado previo
    // válido — si ya habían cargado algo (de una búsqueda o refresh
    // anterior) y el intento nuevo falló por conexión, se sigue mostrando
    // ese resultado viejo en vez de taparlo con el banner: sin este chequeo,
    // un refresh sin internet hacía que el contenido que YA estaba en
    // pantalla desapareciera de golpe, reemplazado por el aviso de sin
    // conexión — se sentía como un parpadeo/pérdida de contenido.
    bool isConnFailureWithNoContent(SearchResult r) =>
        r.error != null &&
        isConnectionError(r.error) &&
        (r.result == null || r.result!.isEmpty);

    bool shouldHide(SearchResult r) => isConnFailureWithNoContent(r);

    final connectionErrorCount =
        widget.runtimeList.where(isConnFailureWithNoContent).length;

    return SingleChildScrollView(
      // Sin esto, el gesto de "deslizar para refrescar" (RefreshIndicator)
      // no dispara cuando el contenido entra entero en la pantalla — el
      // scroll "corto" no deja hacer overscroll para activarlo.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (connectionErrorCount > 0)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, color: Colors.redAccent, size: 26),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      FlutterI18n.translate(
                        context,
                        'common.no-internet-multiple',
                        translationParams: {
                          'count': connectionErrorCount.toString(),
                        },
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final entry in widget.runtimeList.asMap().entries)
            if (!shouldHide(entry.value))
              SearchAllTile(
                // Key estable por extensión — sin esto, Flutter reconcilia
                // esta lista por POSICIÓN: cuando una extensión sube al
                // frente (ver getResult(), las que traen resultados se
                // insertan primero) o se oculta/reaparece (shouldHide),
                // cada índice de acá para abajo se corre, y Flutter termina
                // actualizando el tile equivocado en cada posición en vez de
                // simplemente mover el que ya existía.
                key: ValueKey(entry.value.runitme.extension.package),
                kw: widget.kw,
                searchResult: entry.value,
                onClickMore: () {
                  widget.onClickMore(entry.key);
                },
              )
        ],
      ),
    );
  }
}
