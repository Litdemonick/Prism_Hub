import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';

/// Las cuatro acciones que tocan TODAS las extensiones instaladas a la vez:
/// activarlas, desactivarlas, actualizarlas y desinstalarlas.
///
/// ── Por qué esto es un mixin y no está escrito en cada pantalla ───────
///
/// Porque son dos pantallas —la de teléfono/PC y la de televisor— y estas
/// cuatro no son botones: son cuatro tandas largas, con su candado
/// compartido, su ceder-el-cuadro entre una y otra, su confirmación antes de
/// borrar y sus mensajes al terminar. Cada una de esas decisiones se pagó con
/// un fallo reportado en vivo, y copiarlas a una segunda pantalla es la forma
/// segura de que dentro de un mes solo una de las dos tenga el arreglo
/// siguiente. (Es lo que ya pasó con la cuenta de columnas: estaba copiada en
/// tres sitios y los tres diferían.)
///
/// Un mixin y no una clase suelta porque todo esto vive de `setState`,
/// `mounted` y `context`: los avisos son diálogos y mensajes de la pantalla
/// que las disparó, y los botones se apagan mientras corren.
///
/// Quien lo use tiene que dar [instaladas] — de dónde salen las extensiones
/// sobre las que se actúa.
mixin AccionesMasivasDeExtensiones<T extends StatefulWidget> on State<T> {
  /// El controlador con las extensiones instaladas.
  ExtensionPageController get instaladas;

  /// Hay una acción masiva corriendo AHORA MISMO.
  ///
  /// ── Una sola para las cuatro ────────────────────────────────────────────
  ///
  /// Activar, desactivar, actualizar y desinstalar tocan todas lo mismo: la
  /// lista de extensiones instaladas y sus archivos en disco. Dos a la vez no es
  /// «el doble de rápido», es una carrera: desinstalar mientras se actualiza deja
  /// media extensión escrita, y activar mientras se desinstala vuelve a prender
  /// algo que ya no está.
  ///
  /// Con una sola marca compartida, la primera que arranca bloquea las cuatro
  /// hasta terminar. Y como cada botón la mira para apagarse, tocar quince veces
  /// hace exactamente lo mismo que tocar una.
  bool masivoEnCurso = false;

  /// Corre una acción masiva con el paso cerrado detrás.
  ///
  /// El `finally` no es adorno: si la de adentro tira una excepción y la marca
  /// quedara puesta, los cuatro botones se apagarían para siempre y habría que
  /// reiniciar la app para volver a usarlos.
  Future<void> conElPasoCerrado(Future<void> Function() accion) async {
    if (masivoEnCurso) return;
    setState(() => masivoEnCurso = true);
    try {
      await accion();
    } finally {
      if (mounted) setState(() => masivoEnCurso = false);
    }
  }

  Future<void> cambiarTodas(bool activar) async {
    final visibles = instaladas.runtimes.values.toList(growable: false);
    if (visibles.isEmpty) return;

    // Las +18 no se prenden en masa si el interruptor general está apagado.
    // Activarlas igual dejaría contenido adulto disponible sin que nadie lo
    // haya pedido, que es justo lo que ese interruptor existe para evitar.
    var salteadas = 0;
    final paquetes = <String>[];
    for (final r in visibles) {
      final ext = r.extension;
      if (activar && !ExtensionUtils.isNsfwVisibleOutsideZone(ext.nsfw)) {
        salteadas++;
        continue;
      }
      paquetes.add(ext.package);
    }
    // Una sola llamada y no una por extensión.
    //
    // En bucle, cada vuelta leía y reescribía la lista entera de desactivadas
    // Y pedía recargar Inicio, Buscar, Instaladas y el Repositorio. Con
    // diecisiete instaladas eran diecisiete cascadas encimadas y el app se
    // quedaba sin responder — reportado en vivo, no se podía tocar nada.
    await ExtensionUtils.setExtensionsEnabled(paquetes, activar);
    if (!mounted) return;
    final hechas = visibles.length - salteadas;
    // Frase entera, no un número suelto: «17» a secas no dice si son las que
    // se cambiaron, las que quedaron o cuántas hay en total.
    final base = FlutterI18n.translate(
      context,
      activar ? 'extension.masivo-activadas' : 'extension.masivo-desactivadas',
      translationParams: {'n': '$hechas'},
    );
    showPlatformSnackbar(
      context: context,
      title: activar
          ? 'extension.activar-todas'.i18n
          : 'extension.desactivar-todas'.i18n,
      content:
          salteadas == 0 ? base : '$base ${'extension.masivo-salteadas'.i18n}',
    );
  }

  /// Está actualizando todas ahora mismo.
  bool _actualizando = false;

  /// Baja la última versión de cada extensión instalada que tenga una.
  ///
  /// ── Por qué de a una y no todas a la vez ────────────────────────────────
  ///
  /// Cada actualización baja un guion, verifica su firma y reinstala. Diecisiete
  /// en paralelo es diecisiete descargas y diecisiete verificaciones peleando
  /// por el mismo hilo, y encima el catálogo se pide una vez por cada una.
  ///
  /// De a una tarda más, pero se puede contar cuántas van, y si una falla las
  /// demás siguen. Es una acción que se hace de vez en cuando, no algo que
  /// tenga que ser instantáneo.
  ///
  /// ── Sobre TODAS las instaladas, no sobre las filtradas ──────────────────
  ///
  /// Mismo criterio que activar/desactivar todas (ver cambiarTodas): dejar
  /// una extensión sin actualizar porque justo estaba filtrada no le sirve a
  /// nadie, y una desactualizada deja de funcionar sin avisar.
  Future<void> actualizarTodas() async {
    if (_actualizando) return;
    setState(() => _actualizando = true);
    var hechas = 0;
    var fallidas = 0;
    try {
      final todas = instaladas.runtimes.values.toList(growable: false);
      for (final r in todas) {
        final pkg = r.extension.package;
        try {
          if (!await ExtensionUtils.hasExtensionUpdate(pkg)) continue;
          if (!mounted) return;
          await ExtensionUtils.updateInstalledFromRepo(pkg, context);
          hechas++;
          // Un cuadro para la pantalla: reinstalar arranca el runtime, que es
          // trabajo de CPU y bloquea el isolate entero. Sin esto la tanda deja
          // el app sin dibujar de punta a punta.
          await ExtensionUtils.cederElCuadro();
        } catch (e) {
          // Una que falle no puede frenar a las demás: puede ser una extensión
          // retirada del catálogo, o el sitio de descarga caído un momento.
          fallidas++;
          logger.info('[extensiones] no se pudo actualizar $pkg: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      title: 'extension.actualizar-todas'.i18n,
      content: hechas == 0 && fallidas == 0
          ? 'extension.masivo-al-dia'.i18n
          : FlutterI18n.translate(
              context,
              'extension.masivo-actualizadas',
              translationParams: {'n': '$hechas'},
            ),
    );
  }

  /// Está desinstalando todas ahora mismo.
  bool _desinstalando = false;

  /// Borra de golpe las extensiones que se están viendo.
  ///
  /// ── Sobre TODAS las instaladas, +18 incluidas ───────────────────────────
  ///
  /// Antes solo alcanzaba a las FILTRADAS (lo que la pantalla mostraba en
  /// ese momento) — mismo motivo por el que activar/desactivar masivo NO
  /// respeta el filtro: pedido explícito, para no tener que entrar aparte a
  /// desbloquear el filtro +18 solo para poder desinstalarlas junto con el
  /// resto. La diferencia con activar/desactivar es que desinstalar no se
  /// deshace, así que acá el aviso previo dice EXPLÍCITAMENTE cuántas de
  /// esas son +18 — nadie se entera de un borrado que no esperaba.
  ///
  /// A diferencia de los otros botones masivos, este no se deshace: volver
  /// atrás significa reinstalar una por una y perder los ajustes de cada una.
  /// Por eso pregunta antes, y dice cuántas son — «desinstalar todas» sin un
  /// número es justo el aviso que la gente acepta sin leer.
  Future<void> desinstalarTodas() async {
    if (_desinstalando) return;
    final visibles = instaladas.runtimes.values.toList(growable: false);
    if (visibles.isEmpty) return;
    final nsfwCount = visibles.where((r) => r.extension.nsfw).length;

    final confirma = await showPlatformDialog(
      context: context,
      title: 'extension.desinstalar-todas'.i18n,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(FlutterI18n.translate(
            context,
            'extension.masivo-confirmar-borrado',
            translationParams: {'n': '${visibles.length}'},
          )),
          if (nsfwCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              FlutterI18n.translate(
                context,
                'extension.masivo-confirmar-borrado-incluye-nsfw',
                translationParams: {'n': '$nsfwCount'},
              ),
              style: const TextStyle(
                color: Color(0xFFE5484D),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
    if (confirma != true || !mounted) return;

    setState(() => _desinstalando = true);
    var hechas = 0;
    try {
      for (final r in visibles) {
        try {
          await ExtensionUtils.uninstall(r.extension.package);
          hechas++;
        } catch (e) {
          // Un archivo trabado por el sistema no puede dejar a medias el resto.
          logger.info('[extensiones] no se pudo desinstalar '
              '${r.extension.package}: $e');
        }
        // Igual que en las otras tandas: un cuadro para la pantalla entre una
        // y otra, así la rueda se mueve y el app no parece colgado.
        await ExtensionUtils.cederElCuadro();
      }
    } finally {
      if (mounted) setState(() => _desinstalando = false);
    }
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      title: 'extension.desinstalar-todas'.i18n,
      content: FlutterI18n.translate(
        context,
        'extension.masivo-desinstaladas',
        translationParams: {'n': '$hechas'},
      ),
    );
  }
}
