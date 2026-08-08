import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/controllers/search_controller.dart';
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
    this.cabecera,
  });

  /// La franja del título, como PRIMER elemento de la lista.
  ///
  /// Adentro y no arriba en una columna: así se desplaza con los resultados y
  /// al bajar se va sola, igual que el nombre de la app en el Inicio. Sin
  /// animaciones ni oyentes: no está pasando nada raro, solo se desplaza la
  /// lista. Ver la nota en franja_de_zona.dart.
  final Widget? cabecera;
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
                  Get.find<MainController>().selectedTab.value =
                      MainController.tabExtensiones;
                  return;
                }
                router.push('/extension_repo');
              },
            )
          ],
        ),
      );
    }
    // ── Ya no se esconde ninguna, ni se avisa ───────────────────────────────
    //
    // Antes las filas sin conexión se ocultaban y arriba salía un banner rojo
    // con «no se pudo cargar contenido de N extensiones». Eso ya era mejor que
    // repetir el aviso N veces, pero seguía siendo un cartel de error
    // ocupando la pantalla donde tendría que haber contenido.
    //
    // Por decisión del usuario, en las zonas CON TARJETAS no va ningún
    // mensaje: la fila se queda con sus bloques brillando (ver
    // SearchAllTile) y la pantalla se lee como que está cargando. Las filas se
    // dejan visibles justamente para eso — escondidas no habría dónde
    // mostrarlos.
    //
    // Ojo con lo que esto significa: sin red, esos bloques brillan sin fin y
    // no hay nada escrito que lo explique. Es a propósito.
    return SingleChildScrollView(
      // Sin esto, el gesto de "deslizar para refrescar" (RefreshIndicator)
      // no dispara cuando el contenido entra entero en la pantalla — el
      // scroll "corto" no deja hacer overscroll para activarlo.
      physics: const AlwaysScrollableScrollPhysics(),
      // Abajo, lo que ocupa la barra flotante de celular. Sale del MediaQuery
      // y no de una constante: en escritorio vale cero, así que esta lista la
      // comparten las dos plataformas sin un `if` de por medio.
      //
      // Sin esto, la última extensión de la lista quedaba debajo de la barra y
      // no se podía llegar a sus tarjetas por más que se desplazara.
      // Sin relleno lateral acá: la franja va de borde a borde, como en el
      // Inicio, así que el margen lo pone cada fila.
      padding:
          EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
      child: Column(
        children: [
          if (widget.cabecera != null) widget.cabecera!,
          for (final entry in widget.runtimeList.asMap().entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchAllTile(
                // Key estable por extensión — sin esto, Flutter reconcilia
                // esta lista por POSICIÓN: cuando una extensión sube al frente
                // (ver getResult(), las que traen resultados se insertan
                // primero), cada índice de acá para abajo se corre, y Flutter
                // termina actualizando el tile equivocado en cada posición en
                // vez de simplemente mover el que ya existía.
                key: ValueKey(entry.value.runitme.extension.package),
                kw: widget.kw,
                searchResult: entry.value,
                onClickMore: () {
                  widget.onClickMore(entry.key);
                },
              ),
            )
        ],
      ),
    );
  }
}
