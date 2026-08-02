import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
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
  const CopiaElegirExtensiones({super.key, required this.copia});
  final CopiaAbierta copia;

  @override
  State<CopiaElegirExtensiones> createState() => _CopiaElegirExtensionesState();
}

class _CopiaElegirExtensionesState extends State<CopiaElegirExtensiones> {
  late final Map<String, EstadoExt> _estados = {
    for (final p in widget.copia.paquetes) p: _estadoDe(p),
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

  /// Cómo se llama, si está puesta. Si no, el identificador, que es lo único
  /// que se sabe de ella en este equipo.
  String _nombre(String package) =>
      ExtensionUtils.runtimes[package]?.extension.name ?? package;

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
          FlutterI18n.translate(context, 'settings.backup-pick-hint',
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
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: paquetes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) => _fila(paquetes[i], tenue),
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
