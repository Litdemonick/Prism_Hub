import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_access.dart';
import 'package:prismhub/views/pages/search/extension_searcher_page.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/texto_que_no_cabe.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';
import 'package:prismhub/utils/platform_tv.dart';

class ExtensionTile extends StatefulWidget {
  const ExtensionTile(this.extension, {super.key});
  final Extension extension;

  @override
  State<ExtensionTile> createState() => _ExtensionTileState();
}

class _ExtensionTileState extends State<ExtensionTile> {
  final fluent.FlyoutController moreFlyoutController =
      fluent.FlyoutController();

  late bool _enabled = ExtensionUtils.isEnabled(widget.extension.package);
  bool _updateRequired = false;
  bool _unstable = false;
  // Motivo publicado por el catalogo: decide si la etiqueta dice
  // "En mantenimiento", "En correccion" o solo "Inestable".
  String? _motivoInestable;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    // Chequeo async contra el índice remoto del repo — no bloquea el primer
    // build (arranca sin badge y aparece un instante después si corresponde).
    ExtensionUtils.hasExtensionUpdate(widget.extension.package).then((value) {
      if (mounted) setState(() => _updateRequired = value);
    });
    ExtensionUtils.isRemoteUnstable(widget.extension.package).then((value) {
      if (mounted) {
        setState(() {
          _unstable = value;
          _motivoInestable =
              ExtensionUtils.unstableReasonCached(widget.extension.package);
        });
      }
    });
  }

  // Actualiza sin salir de "Extensiones instaladas" — antes la única forma
  // era navegar al repositorio a mano. Reintenta el chequeo de actualización
  // al terminar para que el badge/botón desaparezcan solos si ya no hace falta.
  Future<void> _performUpdate() async {
    // Guarda de reentrada: el boton no miraba _updating, asi que dos toques
    // seguidos lanzaban dos actualizaciones en paralelo del mismo paquete,
    // escribiendo el mismo archivo.
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await ExtensionUtils.updateInstalledFromRepo(
        widget.extension.package,
        context,
      );
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'extension.install-success'.i18n,
          severity: fluent.InfoBarSeverity.success,
        );
      }
      // Invalida el caché del índice ANTES de re-chequear. Sin esto el
      // re-chequeo puede resolverse contra la copia cacheada y dejar el botón
      // "Actualizar" encendido para siempre aunque la instalación haya salido
      // bien — es el mismo problema que ya se había arreglado para el
      // deslizar-para-refrescar de esta misma página (ver
      // clearRemoteVersionsCache, reportado en vivo con Olympus), pero este
      // camino, el del botón, se había quedado sin la invalidación.
      ExtensionUtils.clearRemoteVersionsCache();
      final stillRequired =
          await ExtensionUtils.hasExtensionUpdate(widget.extension.package);
      if (mounted) setState(() => _updateRequired = stillRequired);
    } catch (e) {
      // Antes esto era solo un debugPrint: si la actualización fallaba (firma
      // inválida, red, repo caído) el spinner paraba, el botón seguía ahí y el
      // usuario no se enteraba de NADA — imposible de diagnosticar desde el
      // otro lado. Ahora el motivo real se muestra.
      debugPrint(e.toString());
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'extension.update-failed'.i18n,
          content: e.toString(),
          severity: fluent.InfoBarSeverity.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  // La lista de "Extensiones instaladas" no tiene Key por ítem (ver
  // extension_page.dart), así que Flutter reutiliza este mismo State al
  // reconstruir la lista (ej. al recibir ExtensionPageController.callRefresh)
  // en vez de recrearlo — sin esto, _enabled/_updateRequired quedaban
  // pegados para siempre en lo que valía la PRIMERA vez que se montó el
  // tile. Necesario para que (a) el apagado automático de una extensión
  // nsfw (settings_page.dart, al apagar el ajuste +18) se refleje en el
  // switch, y (b) actualizar una extensión desde el REPOSITORIO (otra
  // página) haga desaparecer el "actualización requerida" de acá sin
  // salir y volver a entrar — confirmado en vivo que quedaba pegado.
  @override
  void didUpdateWidget(covariant ExtensionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fresh = ExtensionUtils.isEnabled(widget.extension.package);
    if (fresh != _enabled) {
      setState(() => _enabled = fresh);
    }
    // Sin condición de versión: el botón de refrescar (limpia el caché de
    // versiones remotas y reasigna `runtimes`) NO cambia la versión — solo
    // el estado que hay que re-consultar contra el catálogo. Con la
    // condición de antes, tocar refrescar no disparaba ningún re-chequeo y
    // parecía que el botón no hacía nada (confirmado en vivo). Repetir esto
    // es barato: hasExtensionUpdate/isRemoteUnstable comparten un caché con
    // TTL de 10 min, así que solo pegan a la red cuando de verdad hace falta.
    ExtensionUtils.hasExtensionUpdate(widget.extension.package).then((value) {
      if (mounted && value != _updateRequired) {
        setState(() => _updateRequired = value);
      }
    });
    ExtensionUtils.isRemoteUnstable(widget.extension.package).then((value) {
      if (mounted && value != _unstable) {
        setState(() {
          _unstable = value;
          _motivoInestable =
              ExtensionUtils.unstableReasonCached(widget.extension.package);
        });
      }
    });
  }

  // Confirmación +18 antes de activar una extensión nsfw — mismo diálogo que
  // ExtensionCard usa al instalar (ver ese archivo), acá se repite porque no
  // comparten contexto de widget.
  Future<bool> _confirmNsfw() async {
    if (!mounted) return false;
    final result = await showPlatformDialog(
      context: context,
      title: 'extension.nsfw-warning-title'.i18n,
      content: Text('extension.nsfw-warning-content'.i18n),
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
    return result == true;
  }

  /// Este interruptor está trabajando.
  ///
  /// Prender o apagar escribe en disco y toca la lista de motores, y el
  /// interruptor de Flutter deja darle mil veces por segundo. Sin esta guarda,
  /// castigarlo encadenaba escrituras contradictorias sobre el mismo paquete y
  /// el estado terminaba siendo el de la que ganara la carrera, no el último que
  /// pidió el usuario.
  bool _cambiandoEstado = false;

  Future<void> _toggleEnabled(bool value) async {
    if (_cambiandoEstado) return;
    _cambiandoEstado = true;
    try {
      await _toggleEnabledDeVerdad(value);
    } finally {
      if (mounted) setState(() => _cambiandoEstado = false);
      // Sin `mounted` no hay setState, pero la marca se libera igual: si el
      // widget volviera, tiene que poder cambiarse de nuevo.
      _cambiandoEstado = false;
    }
  }

  Future<void> _toggleEnabledDeVerdad(bool value) async {
    // Una extension marcada inestable no se puede ACTIVAR. Antes se podia:
    // el interruptor la prendia igual y recien al tocar su contenido saltaba
    // el aviso, asi que quedaba encendida en la lista y aportando resultados
    // vacios a la busqueda. Apagarla siempre se permite.
    if (value && _unstable) {
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'extension.unstable-title'.i18n,
          content: ExtensionUtils.unstableReasonLabel(_motivoInestable),
          severity: fluent.InfoBarSeverity.warning,
        );
        // El interruptor ya se pinto encendido por el gesto: se vuelve a
        // dibujar desde el estado real para que no quede mintiendo.
        setState(() {});
      }
      return;
    }
    // Activar una extensión nsfw: si el ajuste +18 de Ajustes está apagado no
    // se deja activar (mensaje explicando por qué); si está prendido, se pide
    // confirmación +18 antes de activarla de verdad. Desactivar nunca se
    // bloquea.
    if (value && widget.extension.nsfw) {
      if (PrismHubStorage.getSetting(SettingKey.enableNSFW) != true) {
        if (mounted) {
          showPlatformSnackbar(
            context: context,
            content: 'extension.nsfw-setting-required'.i18n,
            severity: fluent.InfoBarSeverity.warning,
          );
        }
        return;
      }
      if (!await _confirmNsfw()) return;
    }
    // mounted: arriba se pudo haber esperado el dialogo de confirmacion +18, y
    // en ese rato la pantalla pudo cerrarse.
    if (!mounted) return;
    setState(() => _enabled = value);
    await ExtensionUtils.setExtensionEnabled(widget.extension.package, value);
  }

  // Borra las cookies guardadas de ESTA extensión. El frasco es persistente y
  // está ligado al paquete, así que desinstalar y reinstalar NO lo limpia: una
  // sesión que queda en mal estado sobrevive a cualquier versión nueva, y hasta
  // ahora la única salida era borrar los datos del app entero.
  //
  // Va con confirmación porque en extensiones que requieren login esto cierra
  // la sesión — es reversible volviendo a entrar, pero no debería pasar por un
  // toque accidental.
  Future<void> _clearCookies() async {
    if (!mounted) return;
    final ok = await showPlatformDialog(
      context: context,
      title: 'extension.clear-cookies'.i18n,
      content: Text('extension.clear-cookies-confirm'.i18n),
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
    if (ok != true) return;
    try {
      await PrismRequest.clearCookiesForPackage(widget.extension.package);
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: 'extension.clear-cookies-done'.i18n,
          severity: fluent.InfoBarSeverity.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'extension.clear-cookies'.i18n,
          content: e.toString(),
          severity: fluent.InfoBarSeverity.error,
        );
      }
    }
  }

  void _openExtensionSearch(BuildContext context) async {
    if (_updateRequired) {
      // Mismo diálogo compartido que usan ahora todos los demás puntos de
      // entrada a contenido de una extensión (ver ExtensionUtils) — antes
      // era una copia propia acá.
      await ExtensionUtils.blockedByPendingUpdate(
        context,
        widget.extension.package,
      );
      return;
    }
    if (!_enabled) return;
    // Extensión marcada +18: no se entra directo desde Instaladas. Pide
    // confirmación y PIN, igual que la Zona +18 y que el botón +18 del buscador
    // — antes desde acá se llegaba a su contenido salteando las dos cosas.
    if (widget.extension.nsfw) {
      final allowed = await confirmNsfw18Access(context);
      if (!allowed || !context.mounted) return;
    }
    // Ramifica por plataforma igual que ExtensionUtils.openExtensionDetail, y no
    // por gusto: en Android el árbol es GetMaterialApp con home:AndroidMainPage,
    // o sea que go_router NO está montado y router.push no hace nada. Se notaba
    // solo en las extensiones +18: como el gate de arriba come el toque con el
    // diálogo y el PIN, el usuario confirmaba y después no pasaba nada
    // (reportado en vivo). Get.to sí navega en Android; en escritorio es al
    // revés y manda go_router.
    if (Platform.isAndroid) {
      Get.to(() => ExtensionSearcherPage(package: widget.extension.package));
      return;
    }
    router.push(Uri(
      path: '/search_extension',
      queryParameters: {'package': widget.extension.package},
    ).toString());
  }

  // Misma caja con marca que ExtensionCard (repositorio) — antes el ícono (o
  // su fallback) quedaba flotando suelto sobre la fila.
  Widget _iconBox({required double size, required double iconSize}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: HomeTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: CacheNetWorkImagePic(
        widget.extension.icon ?? '',
        key: ValueKey(widget.extension.icon),
        fit: BoxFit.contain,
        // Se decodifica al tamaño en que se DIBUJA, no al del archivo.
        //
        // Sin esto, un icono de 512 píxeles se decodifica entero y se sube a
        // la GPU entero para pintarse en una caja de 40. Con diecisiete
        // extensiones eso es una ráfaga de subidas de textura justo al abrir
        // la pantalla, y sale en el registro como cuadros lentos con
        // `build=0ms` y el raster por las nubes — reportado en vivo en
        // Android. Las tarjetas del Home ya lo hacían; estas se habían
        // quedado afuera.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        fallback: Icon(
          fluent.FluentIcons.puzzle,
          size: iconSize,
          color: HomeTheme.accentPink,
        ),
      ),
    );
  }

  // Container con superficie propia (mismo tratamiento que las cards del
  // repositorio, ver ExtensionCard._buildAndroid) — antes esta fila iba
  // suelta contra el fondo de la página, sin ninguna separación visual
  // clara entre una extensión y la siguiente.
  Widget _buildAndroid(BuildContext context) {
    return Opacity(
      opacity: _enabled ? 1 : 0.7,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomeTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        // El ListTile necesita un Material propio debajo: pinta su fondo y
        // su efecto de toque sobre el más cercano, y el Container de acá
        // arriba (que sí tiene color) se los tapaba. Flutter lo avisaba en
        // consola una vez por extensión de la lista.
        child: Material(
          color: Colors.transparent,
          child: _buildAndroidTile(context),
        ),
      ),
    );
  }

  Widget _buildAndroidTile(BuildContext context) {
    // En TV todo más grande: la fila se mira desde el sillón, no a 30cm.
    // Con las medidas de teléfono, el nombre y el icono quedan chiquitos en
    // el medio de una pantalla enorme, y el interruptor —que es lo que uno
    // viene a tocar— es un blanco diminuto para el mando.
    final tv = PlatformTv.esTelevisionSync;
    return ListTile(
      contentPadding: tv
          ? const EdgeInsets.symmetric(horizontal: 22, vertical: 14)
          : null,
      leading: tv
          ? _iconBox(size: 56, iconSize: 28)
          : _iconBox(size: 40, iconSize: 20),
      // Si el nombre no entra, al lado sale el botón para verlo completo. En
      // una lista de diecisiete, dos que empiezan igual y se cortan en el
      // mismo punto se ven idénticas.
      title: TextoQueNoCabe(
        widget.extension.name,
        estilo: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: tv ? 20 : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wrap de pills (antes Text sueltos de distinto tamaño que en
          // desktop) — mismo _badge() que usa la card de escritorio, para
          // que se vea y mida igual en las dos plataformas.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _badge(widget.extension.version),
              _badge(ExtensionUtils.typeToString(widget.extension.type)),
              if (widget.extension.nsfw) _badge('18+', color: Colors.redAccent),
              if (_unstable)
                _badge(ExtensionUtils.etiquetaCortaInestable(_motivoInestable),
                    color: Colors.orange),
            ],
          ),
          // Descripción — de qué va la extensión (anime, lectura, series,
          // películas, etc), antes no se mostraba en ningún lado pese a que
          // el catálogo ya la trae.
          if (widget.extension.description != null &&
              widget.extension.description!.trim().isNotEmpty &&
              widget.extension.description != widget.extension.name)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.extension.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // Botón real (antes era un texto rojo subrayado, se sentía como
          // un link roto en vez de una acción) — mismo look que el botón
          // "Actualizar" de la card de escritorio, adaptado a Material.
          if (_updateRequired)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.system_update,
                          size: 13, color: Colors.redAccent),
                      const SizedBox(width: 4),
                      Text(
                        'extension.update-required'.i18n,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 28,
                    child: _updating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: ProgressRing(),
                          )
                        : FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: Size.zero,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              backgroundColor:
                                  Colors.redAccent.withValues(alpha: 0.15),
                              foregroundColor: Colors.redAccent,
                              textStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _performUpdate,
                            child: Text('extension-repo.upgrade'.i18n),
                          ),
                  ),
                ],
              ),
            ),
          if (ExtensionUtils.isFailing(widget.extension.package))
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 13, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'extension.not-working'.i18n,
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ),
        ],
      ),
      // Deshabilitada: no se puede entrar a buscar/navegar dentro de ella
      // desde acá — el toggle apagado ahora también bloquea este atajo.
      // Actualización pendiente: bloquea el uso igual (aunque esté
      // habilitada) y en vez de navegar explica que hay que actualizar.
      onTap: _enabled || _updateRequired
          ? () => _openExtensionSearch(context)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: _enabled,
            onChanged: _cambiandoEstado ? null : _toggleEnabled,
          ),
          IconButton(
            onPressed: () {
              // 弹出菜单 — solo desinstalar (ajustes/editar código quitados a
              // pedido del usuario).
              showModalBottomSheet(
                context: context,
                builder: (context) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined),
                        title: Text('extension.clear-cookies'.i18n),
                        subtitle: Text('extension.clear-cookies-subtitle'.i18n),
                        onTap: () {
                          Get.back();
                          _clearCookies();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete),
                        title: Text('common.uninstall'.i18n),
                        onTap: () {
                          ExtensionUtils.uninstall(widget.extension.package);
                          Get.back();
                        },
                      ),
                    ],
                  );
                },
              );
            },
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
  }

  // Descripción con "ver más" — mismo widget que ExtensionCard del
  // repositorio, repetido acá porque no comparten archivo.
  Widget _descriptionWithSeeMore(
    BuildContext context, {
    required String text,
    required TextStyle style,
    required int maxLines,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = tp.didExceedMaxLines;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            if (overflow)
              GestureDetector(
                onTap: () => showPlatformDialog(
                  context: context,
                  title: widget.extension.name,
                  content: SingleChildScrollView(child: Text(text)),
                  actions: [
                    PlatformFilledButton(
                      onPressed: () => RouterUtils.pop(),
                      child: Text('common.confirm'.i18n),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'common.see-more'.i18n,
                    style: TextStyle(
                      fontSize: 10,
                      color: HomeTheme.accentPink,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Pill con fondo propio para cada badge — mismo widget que ExtensionCard
  // del repositorio, repetido acá porque no comparten archivo.
  Widget _badge(String text, {Color? color}) {
    final c = color ?? HomeTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    // Card vertical de alto fijo (mismo criterio que ExtensionCard del
    // repositorio, ver ese archivo) — esta vista ahora se arma como grid de
    // cards en vez de una lista de filas horizontales (ver
    // extension_page.dart), así que necesita el mismo tratamiento: alto
    // fijo + Spacer para que el botón/switch de abajo quede anclado
    // siempre en el mismo lugar sin importar cuántos badges haya arriba.
    return Opacity(
      opacity: _enabled ? 1 : 0.7,
      child: Container(
        height: 335,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomeTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _enabled || _updateRequired
                  ? () => _openExtensionSearch(context)
                  : null,
              child: MouseRegion(
                cursor: _enabled || _updateRequired
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _iconBox(size: 40, iconSize: 20),
                    const SizedBox(height: 10),
                    // Cortado, al lado sale el botón para verlo completo:
                    // acá el nombre es lo único que distingue una tarjeta de
                    // otra.
                    TextoQueNoCabe(
                      widget.extension.name,
                      estilo: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.extension.author,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: HomeTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Descripción — de qué va la extensión (anime, lectura, series,
            // películas, etc), antes no se mostraba en ningún lado pese a
            // que el catálogo ya la trae.
            if (widget.extension.description != null &&
                widget.extension.description!.trim().isNotEmpty &&
                widget.extension.description != widget.extension.name) ...[
              const SizedBox(height: 6),
              _descriptionWithSeeMore(
                context,
                text: widget.extension.description!,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11,
                  color: HomeTheme.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Un solo Wrap para todos los badges (antes versión/tipo iban en
            // una columna aparte y "actualización requerida"/"no funciona"
            // eran filas propias) — mismo criterio que ExtensionCard: reflowa
            // en varias líneas en vez de desbordar, y el alto fijo de más
            // arriba ya deja lugar para hasta 3.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                _badge(widget.extension.version),
                _badge(ExtensionUtils.typeToString(widget.extension.type)),
                if (widget.extension.nsfw)
                  _badge('18+', color: Colors.redAccent),
                if (_unstable)
                  _badge(
                      ExtensionUtils.etiquetaCortaInestable(_motivoInestable),
                      color: Colors.orange),
                if (_updateRequired)
                  _badge('extension.update-required'.i18n,
                      color: Colors.redAccent),
                if (ExtensionUtils.isFailing(widget.extension.package))
                  _badge('extension.not-working'.i18n, color: Colors.orange),
              ],
            ),
            const Spacer(),
            if (_updateRequired)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: _updating
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: ProgressRing(),
                          ),
                        )
                      : fluent.FilledButton(
                          onPressed: _performUpdate,
                          child: Text(
                            'extension-repo.upgrade'.i18n,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                fluent.ToggleSwitch(
                  checked: _enabled,
                  onChanged: _cambiandoEstado ? null : _toggleEnabled,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    fluent.Tooltip(
                      message: 'Abrir',
                      child: fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.search),
                        // Deshabilitada / actualización pendiente: mismo
                        // bloqueo que en la versión móvil.
                        onPressed: _enabled || _updateRequired
                            ? () => _openExtensionSearch(context)
                            : null,
                      ),
                    ),
                    // "..." solo con Desinstalar — ajustes/editar código
                    // quitados a pedido del usuario.
                    fluent.FlyoutTarget(
                      controller: moreFlyoutController,
                      child: fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.more),
                        onPressed: () {
                          moreFlyoutController.showFlyout(
                            autoModeConfiguration:
                                fluent.FlyoutAutoConfiguration(
                              preferredMode:
                                  fluent.FlyoutPlacementMode.bottomLeft,
                            ),
                            builder: (context) {
                              return fluent.MenuFlyout(
                                items: [
                                  fluent.MenuFlyoutItem(
                                    leading: const Icon(
                                        fluent.FluentIcons.clear_formatting),
                                    text: Text('extension.clear-cookies'.i18n),
                                    onPressed: () {
                                      fluent.Flyout.of(context).close();
                                      _clearCookies();
                                    },
                                  ),
                                  fluent.MenuFlyoutItem(
                                    leading:
                                        const Icon(fluent.FluentIcons.delete),
                                    text: Text('common.uninstall'.i18n),
                                    onPressed: () {
                                      ExtensionUtils.uninstall(
                                          widget.extension.package);
                                      fluent.Flyout.of(context).close();
                                    },
                                  ),
                                ],
                              );
                            },
                            barrierDismissible: true,
                            dismissWithEsc: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
