import 'dart:io';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/extension.dart';

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
      // ── Lista vacía NO quiere decir «no hay extensiones» ────────────────
      //
      // Acá llega la lista de RESULTADOS, no la de extensiones instaladas. Con
      // el buscador recién abierto —o con una búsqueda que no encontró nada—
      // esa lista está vacía, y se mostraba «Sin extensiones instaladas» con
      // un botón para ir a instalar.
      //
      // Reportado en vivo en el televisor: «en buscar me sale sin extensiones
      // instaladas cuando sí hay». Y es de lo peor que puede decir una app:
      // manda a arreglar algo que no está roto.
      //
      // Son tres situaciones distintas y ahora se dicen distinto.
      final hayInstaladas = ExtensionUtils.enabledRuntimes.isNotEmpty;
      if (hayInstaladas) {
        return _EsperandoQueEscribas(
          sinEscribir: widget.kw.trim().isEmpty,
        );
      }
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

/// La pantalla del buscador cuando todavía no hay nada que mostrar.
///
/// ── Por qué no es solo una línea de texto ───────────────────────────────────
///
/// Era una frase gris en medio de una pantalla negra. Funcionaba, pero no
/// invitaba a nada: no se distingue de un error, y en un televisor —donde la
/// pantalla es enorme y uno está lejos— se lee como que la app se colgó.
///
/// Acá hay un icono que respira despacio y el texto debajo. El movimiento es lo
/// que hace la diferencia entre «esto está esperando algo» y «esto se quedó
/// trabado», que es exactamente la duda que uno tiene mirando de lejos.
///
/// ── Y por qué respira despacio, no rápido ───────────────────────────────────
///
/// Cuatro segundos por ciclo y solo la opacidad: es lo más barato que se puede
/// animar —no rehace la disposición ni vuelve a dibujar nada, solo mezcla— y en
/// un televisor modesto una animación continua es de las pocas cosas que puede
/// costar caro. Con este ritmo no compite con nada, ni siquiera mientras se
/// escribe.
class _EsperandoQueEscribas extends StatefulWidget {
  const _EsperandoQueEscribas({required this.sinEscribir});

  /// True: todavía no se escribió nada. False: se buscó y no hubo resultados.
  final bool sinEscribir;

  @override
  State<_EsperandoQueEscribas> createState() => _EsperandoQueEscribasState();
}

class _EsperandoQueEscribasState extends State<_EsperandoQueEscribas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    // Solo cuando invita a escribir. Sin resultados NO se anima: ahí la
    // pantalla está contando algo que ya pasó, y algo latiendo al lado se
    // leería como que sigue buscando.
    if (widget.sinEscribir) _pulso.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_EsperandoQueEscribas viejo) {
    super.didUpdateWidget(viejo);
    if (widget.sinEscribir == viejo.sinEscribir) return;
    if (widget.sinEscribir) {
      _pulso.repeat(reverse: true);
    } else {
      _pulso.stop();
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = PlatformTv.esTelevisionSync;
    final icono = widget.sinEscribir
        ? Icons.search_rounded
        : Icons.search_off_rounded;
    return SizedBox(
      height: tv ? 380 : 300,
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 0.9).animate(_pulso),
              child: Icon(
                icono,
                size: tv ? 74 : 54,
                color: HomeTheme.accentPink,
              ),
            ),
            SizedBox(height: tv ? 22 : 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.sinEscribir
                    ? 'search.escribi-algo'.i18n
                    : 'search.nada-encontrado'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: tv ? 19 : 15,
                  height: 1.45,
                  color: HomeTheme.textPrimary,
                ),
              ),
            ),
            if (widget.sinEscribir) ...[
              SizedBox(height: tv ? 10 : 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'search.busca-en-todas'.i18n,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: tv ? 15 : 12.5,
                    color: HomeTheme.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
