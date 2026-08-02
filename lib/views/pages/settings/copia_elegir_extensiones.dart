import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/copia_seguridad.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// En qué estado está una extensión de la copia EN ESTE equipo.
enum EstadoExt { lista, desactivada, inestable, ausente }

/// Elegir qué extensiones de la copia se importan.
///
/// El archivo puede venir de un equipo con otras extensiones puestas. Meter
/// todo a ciegas llena el inicio de tarjetas que no abren, y el usuario no
/// entiende por qué. Acá se ve, antes de tocar nada, de qué extensión es cada
/// cosa, cuánto trae y si en ESTE equipo va a funcionar.
///
/// Lo que no está listo **no se puede elegir**: se dice qué falta hacer
/// —instalarla, activarla, esperar a que se arregle— y se sigue con las demás.
/// Dejarlo elegir igual sería prometer algo que no va a andar.
///
/// Devuelve por `pop` el conjunto de paquetes elegidos, o null si se cancela.
class CopiaElegirExtensiones extends StatefulWidget {
  const CopiaElegirExtensiones({
    super.key,
    required this.copia,
    this.alExportar = false,
  });
  final CopiaAbierta copia;

  /// Al EXPORTAR la misma pantalla sirve para elegir qué se guarda.
  ///
  /// Cambia dos cosas: el texto de arriba —no viene de ninguna copia, es lo que
  /// hay en este equipo— y que todas se pueden elegir. Al exportar no importa
  /// si una está apagada o inestable: sus datos están en la base igual, y
  /// dejarlos afuera sería perderlos justo en la copia que se hace para no
  /// perder nada.
  final bool alExportar;

  @override
  State<CopiaElegirExtensiones> createState() => _CopiaElegirExtensionesState();
}

class _CopiaElegirExtensionesState extends State<CopiaElegirExtensiones> {
  late final Map<String, EstadoExt> _estados = {
    for (final p in widget.copia.paquetes)
      // Al exportar todas están listas: sus datos ya están en la base, y
      // dejarlos afuera por estar apagada sería perderlos en la copia que se
      // hace justamente para no perder nada.
      p: widget.alExportar ? EstadoExt.lista : _estadoDe(p),
  };

  /// Arrancan marcadas las que se pueden. Es lo que quiere el que viene a
  /// recuperar todo, que es el caso normal.
  late final Set<String> _elegidas = {
    for (final e in _estados.entries)
      if (e.value == EstadoExt.lista) e.key,
  };

  static EstadoExt _estadoDe(String package) {
    if (!ExtensionUtils.runtimes.containsKey(package)) {
      return EstadoExt.ausente;
    }
    if (!ExtensionUtils.isEnabled(package)) return EstadoExt.desactivada;
    // La versión cacheada y no la async: esto se lee dentro de un build, y la
    // otra pediría el catálogo por red en medio del dibujado.
    if (ExtensionUtils.isRemoteUnstableCached(package)) {
      return EstadoExt.inestable;
    }
    return EstadoExt.lista;
  }

  /// Cómo se llama, para mostrarlo.
  ///
  /// Si está puesta, su nombre. Si no, se arma uno legible a partir del
  /// identificador: "io.prismhub.tumangaonline" no le dice nada a nadie, y era
  /// lo que salía en la lista para las que no están instaladas.
  String _nombre(String package) {
    final puesto = ExtensionUtils.runtimes[package]?.extension.name;
    if (puesto != null && puesto.isNotEmpty) return puesto;
    // Se queda con lo último del identificador, que es el nombre real, y se le
    // pone mayúscula. "io.prismhub.tumangaonline" -> "Tumangaonline".
    final ultimo = package.split('.').last;
    if (ultimo.isEmpty) return package;
    return ultimo[0].toUpperCase() + ultimo.substring(1);
  }

  /// Propio y compartido entre la barra y la lista: si cada una tuviera el
  /// suyo, la barra no seguiría al desplazamiento.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _cuantasSePueden =>
      _estados.values.where((e) => e == EstadoExt.lista).length;

  @override
  Widget build(BuildContext context) {
    final paquetes = widget.copia.paquetes;
    final tenue =
        DefaultTextStyle.of(context).style.color?.withValues(alpha: .65);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.alExportar
              ? FlutterI18n.translate(
                  context, 'settings.backup-pick-hint-export',
                  translationParams: {'n': '${widget.copia.total}'})
              : FlutterI18n.translate(context, 'settings.backup-pick-hint',
                  translationParams: {
                      'nombre': widget.copia.deQuien.etiqueta,
                      'n': '${widget.copia.total}',
                    }),
          style: TextStyle(fontSize: 12.5, height: 1.4, color: tenue),
        ),
        const SizedBox(height: 8),
        if (_cuantasSePueden > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                // Solo se toca lo que se PUEDE elegir: "todas" no puede marcar
                // algo que igual no va a poder importarse.
                if (_elegidas.length == _cuantasSePueden) {
                  _elegidas.clear();
                } else {
                  _elegidas
                    ..clear()
                    ..addAll(_estados.entries
                        .where((e) => e.value == EstadoExt.lista)
                        .map((e) => e.key));
                }
              }),
              child: Text((_elegidas.length == _cuantasSePueden
                      ? 'settings.backup-pick-none'
                      : 'settings.backup-pick-all')
                  .i18n),
            ),
          ),
        // Altura acotada: con muchas extensiones la lista se desplaza en vez de
        // empujar los botones fuera de la pantalla. En un teléfono en
        // horizontal eso pasaba ya con cuatro filas.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(context).height * 0.45).clamp(150, 380),
          ),
          // Con barra de desplazamiento a la vista y siempre.
          //
          // Sin ella, con más extensiones de las que entran en pantalla no hay
          // ninguna señal de que la lista sigue: se ve una lista cortada y
          // parece que eso es todo lo que hay.
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _scroll,
              shrinkWrap: true,
              // Sitio a la derecha para que la barra no se dibuje encima de los
              // interruptores.
              padding: const EdgeInsets.only(right: 10),
              itemCount: paquetes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _fila(paquetes[i], tenue),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PlatformTextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.cancel'.i18n),
            ),
            const SizedBox(width: 8),
            PlatformFilledButton(
              // Sin nada elegido no hay nada que importar: se apaga en vez de
              // dejar tocar y que no pase nada.
              onPressed: _elegidas.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_elegidas),
              child: Text('settings.backup-import-action'.i18n),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fila(String package, Color? tenue) {
    final estado = _estados[package]!;
    final cuenta = widget.copia.porPaquete[package]!;
    final sePuede = estado == EstadoExt.lista;
    final marcada = _elegidas.contains(package);

    return Opacity(
      // Lo que no se puede elegir se ve apagado, pero se SIGUE viendo: es
      // justamente la información que el usuario necesita para saber qué le
      // falta hacer para recuperar eso.
      opacity: sePuede ? 1 : 0.7,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: marcada
              ? HomeTheme.accentPink.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: marcada
                ? HomeTheme.accentPink.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nombre(package),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FlutterI18n.translate(
                        context, 'settings.backup-pick-counts',
                        translationParams: {
                          'historial': '${cuenta.historial}',
                          'favoritos': '${cuenta.favoritos}',
                        }),
                    style: TextStyle(fontSize: 11.5, color: tenue),
                  ),
                  // Qué hay que hacer para poder pasar esta. Solo cuando hace
                  // falta: en las que están listas sería ruido.
                  if (!sePuede) ...[
                    const SizedBox(height: 3),
                    Text(
                      _queFalta(estado),
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    // Y el atajo para ir a resolverlo.
                    //
                    // Decirle qué le falta sin decirle dónde se hace lo deja
                    // buscando por los ajustes. Las que no están puestas llevan
                    // al repositorio, que es donde se instalan; las que están
                    // pero apagadas, a la lista de instaladas.
                    if (estado != EstadoExt.inestable)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 0),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: HomeTheme.accentPink,
                          ),
                          onPressed: () {
                            // La lista se abre ya buscando ESTA extensión: sin
                            // esto se llegaba a una lista de decenas y había
                            // que encontrar a mano la que el aviso nombró.
                            ExtensionUtils.filtroPendiente = _nombre(package);
                            final destino = estado == EstadoExt.ausente
                                ? '/extension_repo'
                                : '/extension';
                            // Se cierra el diálogo antes de navegar: dejarlo
                            // abierto encima de la otra pantalla lo deja
                            // tapando justo lo que el usuario fue a hacer.
                            Navigator.of(context).pop();
                            // Y la navegación va en el cuadro SIGUIENTE.
                            //
                            // En el mismo, el cierre del diálogo y el cambio de
                            // ruta se pisan: go_router procesa la ruta nueva
                            // mientras el Navigator todavía está desmontando el
                            // diálogo, y el resultado era que no se movía de
                            // Ajustes. Por eso "ir a instalarla" no llevaba a
                            // ningún lado.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              router.go(destino);
                            });
                          },
                          child: Text(
                            (estado == EstadoExt.ausente
                                    ? 'settings.backup-pick-go-install'
                                    : 'settings.backup-pick-go-enable')
                                .i18n,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Switch(
              value: marcada,
              onChanged: sePuede
                  ? (v) => setState(() {
                        if (v) {
                          _elegidas.add(package);
                        } else {
                          _elegidas.remove(package);
                        }
                      })
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _queFalta(EstadoExt estado) {
    switch (estado) {
      case EstadoExt.ausente:
        return 'settings.backup-pick-missing'.i18n;
      case EstadoExt.desactivada:
        return 'settings.backup-pick-disabled'.i18n;
      case EstadoExt.inestable:
        return 'settings.backup-pick-unstable'.i18n;
      case EstadoExt.lista:
        return '';
    }
  }
}
