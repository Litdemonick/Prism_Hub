import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/extension_signature.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
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

class ExtensionCard extends StatefulWidget {
  const ExtensionCard({
    super.key,
    required this.name,
    required this.version,
    required this.icon,
    required this.package,
    required this.lang,
    required this.nsfw,
    required this.type,
    this.unstable = false,
    this.blockedReasonKey = 'extension.unstable-blocked',
    this.unstableReason,
    this.url,
    this.webSite,
    this.license,
    this.description,
    this.signature,
  });
  final String? icon;
  final String? url;
  final String name;
  final String version;
  final String package;
  final String lang;
  final ExtensionType type;
  final bool nsfw;
  // Marcada `unstable` en el índice remoto (extensión con un bug conocido sin
  // arreglar todavía, ej. LaMovie) — bloquea instalarla de nuevo desde acá.
  // Si YA está instalada, el bloqueo real corre en ExtensionTile vía
  // hasExtensionUpdate (mismo mecanismo que "actualización requerida").
  final bool unstable;
  // Clave i18n del texto que explica POR QUÉ está bloqueada. Por defecto el
  // genérico de inestable; se cambia, por ejemplo, cuando la extensión declara
  // un `minProtocol` mayor al que entiende este app (ahí lo que falta es
  // actualizar PrismHub, no esperar un arreglo de la extensión).
  final String blockedReasonKey;

  /// Motivo publicado por el catalogo ('site-down', 'broken',
  /// 'outdated'). Decide el texto CORTO de la etiqueta; el largo sale
  /// de blockedReasonKey.
  final String? unstableReason;
  final String? webSite;
  final String? license;
  final String? description;
  // Firma Ed25519 de prism+ (del index.json). Si está y valida → oficial; si
  // está pero no valida → manipulada (se rechaza); si falta → externa.
  final String? signature;

  @override
  State<ExtensionCard> createState() => _ExtensionCardState();
}

class _ExtensionCardState extends State<ExtensionCard> {
  bool isLoading = false;
  bool isInstall = false;
  bool hasUpgrade = false;
  late String icon = widget.icon ?? '';

  @override
  void initState() {
    setState(() {
      isInstall = ExtensionUtils.runtimes.containsKey(widget.package);
      hasUpgrade = isInstall &&
          ExtensionUtils.runtimes[widget.package]!.extension.version !=
              widget.version;
    });
    super.initState();
  }

  // Mismo diálogo que ExtensionTile._toggleEnabled usa al activar — se
  // repite acá porque no comparten contexto de widget. El repositorio
  // ahora SIEMPRE muestra todas las extensiones (nunca oculta nsfw, ni
  // instaladas ni no instaladas), así que instalar una nsfw:true necesita
  // el mismo aviso/bloqueo que activar, no alcanza con confiar en que ya
  // esté filtrada de la lista.
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

  /// Segundo intento con el catálogo recién bajado.
  ///
  /// Devuelve el script si esta vez la firma valida, o null si sigue sin
  /// validar — ahí sí hay que rechazar. Ver el porqué en quien lo llama.
  Future<String?> _reintentarConCatalogoFresco() async {
    try {
      final lista = await ExtensionUtils.fetchRepoIndex(
        forceRefresh: true,
        cacheBust: true,
      );
      final entrada = lista.firstWhere(
        (e) => e is Map && e['package']?.toString() == widget.package,
        orElse: () => null,
      );
      if (entrada is! Map) return null;
      final firma = entrada['signature']?.toString();
      final direccion = (entrada['script'] ?? entrada['url'])?.toString();
      if (firma == null || firma.isEmpty || direccion == null) return null;

      final sep = direccion.contains('?') ? '&' : '?';
      final bust = DateTime.now().millisecondsSinceEpoch;
      final res = await dio.get<String>(
        '$direccion${sep}t=$bust',
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      final script = res.data;
      if (script == null || script.isEmpty) return null;
      if (!ExtensionSignature.isOfficial(script, firma)) {
        logger.warning('[extensiones] ${widget.package}: la firma sigue sin '
            'validar con el catálogo fresco — se rechaza');
        return null;
      }
      logger.info('[extensiones] ${widget.package}: la firma no validaba con '
          'el catálogo que teníamos y sí con el recién bajado — era caché, no '
          'manipulación');
      return script;
    } catch (e) {
      logger.warning('[extensiones] no se pudo reintentar con el catálogo '
          'fresco para ${widget.package}: $e');
      return null;
    }
  }

  _install() async {
    // Guarda de reentrada. `isLoading` solo se usaba para pintar la rueda, y
    // ninguno de los cuatro botones que llaman aca lo miraba: tocar dos veces
    // seguidas arrancaba DOS descargas del mismo script, las dos escribiendo el
    // mismo archivo de extension y registrando el runtime en paralelo. De ahi
    // que tocar rapido rompiera la pantalla.
    if (isLoading) return;
    // Solo en la instalación de verdad, no en "Actualizar": si ya está
    // instalada es porque el usuario ya pasó este mismo aviso una vez.
    // Con el switch de NSFW apagado NO se bloquea instalar — se instala
    // igual pero queda desactivada (mismo criterio que activar una
    // extensión nsfw a mano estando el switch apagado). Bloquear instalar
    // del todo escondía la extensión del catálogo de facto; así el usuario
    // la ve, la puede instalar cuando quiera, y decide activarla recién
    // cuando prenda el switch — con un aviso claro de por qué no funciona
    // todavía en vez de dejarla "perdida" sin explicación.
    var installDisabled = false;
    if (widget.nsfw && !isInstall) {
      if (PrismHubStorage.getSetting(SettingKey.enableNSFW) != true) {
        installDisabled = true;
      } else if (!await _confirmNsfw()) {
        return;
      }
    }
    // mounted: arriba se pudo haber esperado el dialogo de confirmacion +18, y
    // en ese rato el usuario pudo cerrar la pantalla. Un setState sobre un
    // widget ya desmontado tira excepcion.
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });
    try {
      // Use direct url from index.json if available, otherwise fallback to repo convention
      final baseUrl = widget.url ??
          PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl) +
              "/repo/${widget.package}.js";
      // Cache-bust: GitHub raw cachea el .js unos minutos — sin esto, instalar
      // justo después de publicar una versión nueva podía traer la vieja.
      final bust = DateTime.now().millisecondsSinceEpoch;
      final sep = baseUrl.contains('?') ? '&' : '?';
      final url = '$baseUrl${sep}t=$bust';
      debugPrint(url);
      final res = await dio.get<String>(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );
      if (res.data == null) throw Exception("Does not seem to be an extension");

      String script = res.data!;
      // Seguridad: si la entrada del catálogo trae firma, debe validar contra la
      // llave pública de prism+. Si no valida, la extensión fue alterada → no se
      // instala. Si no trae firma, es externa (no oficial) y se permite igual:
      // PrismHub es open source y admite sideload de terceros.
      bool officialVerified = false;
      if (widget.signature != null && widget.signature!.isNotEmpty) {
        if (!ExtensionSignature.isOfficial(script, widget.signature)) {
          // ── No es manipulación todavía: puede ser el caché de GitHub ──────
          //
          // El JS se pide con `?t=` para esquivar el caché, pero la firma NO
          // sale de ahí: sale del `index.json` del catálogo, que tiene su
          // propio caché. Si el catálogo que tenemos en mano quedó una versión
          // atrás y el JS ya es el nuevo, los dos archivos son legítimos y aun
          // así la firma no valida.
          //
          // Reportado en vivo el 2026-08-06 justo después de publicar tres
          // versiones seguidas de FuegoCine: salía «esta extensión fue
          // alterada», y unos minutos más tarde la misma actualización entraba
          // sola sin que nadie tocara nada. Se comprobó del otro lado que el
          // JS y su firma coincidían perfecto en el repositorio.
          //
          // Acusar de manipulación por un caché ajeno es lo peor de los dos
          // mundos: asusta y encima bloquea una actualización sana. Así que se
          // baja el catálogo DE NUEVO —forzado— y se reintenta una vez con la
          // firma fresca. Si con eso tampoco valida, ahí sí es un problema de
          // verdad y se rechaza como siempre.
          final frescos = await _reintentarConCatalogoFresco();
          if (frescos == null) {
            throw Exception('extension.invalid-signature'.i18n);
          }
          script = frescos;
        }
        // Firma oficial válida → puede instalarse aunque sea una nativa.
        officialVerified = true;
      }
      // Inject metadata header if missing (e.g. CDN cache serving old file)
      if (!script.contains('==PrismHubExtension==') &&
          !script.contains('==MiruExtension==') &&
          !script.contains('@package')) {
        final typeName = widget.type.toString().split('.').last;
        final header = '// ==PrismHubExtension==\n'
            '// @name         ${widget.name}\n'
            '// @version      ${widget.version}\n'
            '// @author       PrismPlus\n'
            '// @lang         ${widget.lang}\n'
            '// @license      ${widget.license ?? "MIT"}\n'
            '// @icon         ${widget.icon ?? ""}\n'
            '// @package      ${widget.package}\n'
            '// @type         $typeName\n'
            '// @nsfw         ${widget.nsfw}\n'
            '// @webSite      ${widget.webSite ?? ""}\n'
            '// @description  ${widget.description ?? widget.name}\n'
            '// ==/PrismHubExtension==\n\n';
        script = header + script;
      }
      if (!mounted) return;
      await ExtensionUtils.installByScript(script, context,
          officialVerified: officialVerified);
      if (installDisabled) {
        await ExtensionUtils.setExtensionEnabled(widget.package, false);
        // Se ANOTA como apagada por el ajuste de +18, no solo se apaga.
        //
        // Sin esto quedaba apagada y sin registrar, así que al encender el +18
        // no volvía sola: el interruptor solo devuelve las anotadas. Había que
        // ir a buscarla a Extensiones instaladas y activarla a mano, sin
        // ninguna pista de por qué estaba apagada.
        await ExtensionUtils.anotarApagadaPorNsfw(widget.package);
      }
      // Confirmación visible: antes el éxito no avisaba nada y parecía que
      // "no pasó nada" al instalar.
      if (mounted) {
        showPlatformSnackbar(
          context: context,
          content: installDisabled
              ? 'extension.install-success-disabled-nsfw'.i18n
              : 'extension.install-success'.i18n,
          severity: installDisabled
              ? fluent.InfoBarSeverity.warning
              : fluent.InfoBarSeverity.success,
        );
      }
    } catch (e) {
      // installByScript ya muestra un diálogo de error con el detalle; aquí solo
      // registramos. El estado real se sincroniza abajo desde runtimes.
      debugPrint(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          // Reflejar el estado REAL: si el init falló, la extensión no quedó en
          // runtimes → el botón vuelve a "Instalar" en vez de mentir "instalada".
          isInstall = ExtensionUtils.runtimes.containsKey(widget.package);
          hasUpgrade = isInstall &&
              ExtensionUtils.runtimes[widget.package]!.extension.version !=
                  widget.version;
        });
      }
    }
  }

  // Descripción con "ver más" — cuando el texto no entra en `maxLines`
  // (TextPainter mide contra el ancho real disponible), se agrega un link
  // chico debajo que abre un diálogo con el texto completo, en vez de
  // dejarla cortada con "..." sin forma de leerla entera.
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
                  title: widget.name,
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

  // Pill con fondo propio para cada badge (versión/tipo/idioma/18+/
  // inestable/oficial) — antes eran Text sueltos uno al lado del otro en
  // un Wrap, así que sin ningún límite visual entre ellos se leían todos
  // pegados como una sola frase corrida ("Lectura es 18+ PrismPlus").
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
        style: TextStyle(
          fontSize: 11,
          color: c,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Caja con fondo propio para el ícono — antes el ícono (o su fallback,
  // cuando la extensión no trae uno) quedaba flotando suelto sobre el fondo
  // de la tarjeta; con marca (borde + superficie) se ve intencional en vez
  // de una imagen rota. Tinte morado (en vez de gris neutro) para que se
  // sienta parte de la identidad de la app en vez de una caja genérica.
  Widget _iconBox({required double size, required double iconSize}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HomeTheme.accentPink.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CacheNetWorkImagePic(
        icon,
        fit: BoxFit.contain,
        // Al tamaño en que se dibuja, igual que en ExtensionTile: el
        // repositorio muestra decenas de tarjetas de una y cada icono se
        // decodificaba a resolución completa para una caja chica.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        fallback: Icon(
          fluent.FluentIcons.puzzle,
          size: iconSize,
          color: HomeTheme.accentPink,
        ),
      ),
    );
  }

  // Circulito con check arriba a la derecha de la card — de un vistazo,
  // sin tener que leer el botón de abajo, se sabe si esta ya está
  // instalada. Sutil (contorno, no relleno sólido) para no competir con el
  // resto de la card.
  Widget _installedBadge() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        shape: BoxShape.circle,
        border: Border.all(color: HomeTheme.accentPink, width: 1.4),
      ),
      child: Icon(Icons.check, size: 11, color: HomeTheme.accentPink),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    // Container con superficie propia (mismo tratamiento que las cards de
    // escritorio) — antes era un ListTile sin fondo ni borde, flotando
    // suelto contra el fondo de la página, sin separación visual clara
    // entre una extensión y la siguiente.
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          _buildAndroidTile(context),
          if (isInstall)
            Positioned(top: 8, right: 8, child: _installedBadge()),
        ],
      ),
    );
  }

  Widget _buildAndroidTile(BuildContext context) {
    return ListTile(
      leading: _iconBox(size: 40, iconSize: 20),
      title: Text(widget.name),
      subtitle: DefaultTextStyle(
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall!.color,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wrap en vez de Row: con varios badges juntos (versión + tipo
              // + idioma + 18+ + oficial) en pantallas angostas de celular,
              // un Row fijo tiraba RenderFlex overflow — confirmado en vivo
              // ("overflow by 28 pixels"). Wrap baja el resto a una segunda
              // línea en vez de desbordar, igual que ya hace la versión de
              // escritorio.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _badge(widget.version),
                  _badge(ExtensionUtils.typeToString(widget.type)),
                  _badge(widget.lang),
                  if (widget.nsfw) _badge('+18', color: Colors.redAccent),
                  if (widget.unstable)
                    _badge(ExtensionUtils.etiquetaCortaInestable(widget.unstableReason),
                        color: Colors.orange),
                  // Solo indica que el catálogo trae firma de prism+ (no
                  // valida acá — eso pasa recién al instalar, ver
                  // _install()). Es solo informativo, no editable.
                  if (widget.signature != null && widget.signature!.isNotEmpty)
                    _badge('extension.official-badge'.i18n,
                        color: HomeTheme.accentPink),
                ],
              ),
              // Descripción — de qué va la extensión (anime, lectura,
              // series, películas, etc), antes no se mostraba en ningún
              // lado pese a que el catálogo ya la trae.
              if (widget.description != null &&
                  widget.description!.trim().isNotEmpty &&
                  widget.description != widget.name)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    widget.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Mensaje completo (ancho total de la fila, sin límite de
              // líneas) en vez de meterlo adentro del trailing de 90px —
              // ahí quedaba cortado contra el borde de la pantalla
              // (confirmado en vivo). Visibility con maintainSize en vez de
              // un `if`: al instalar, este mensaje desaparece — sin reservar
              // su espacio el tile se achica de golpe y toda la lista salta
              // hacia arriba justo al tocar el botón.
              if (widget.unstable)
                Visibility(
                  visible: !isInstall,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.blockedReasonKey.i18n,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ),
            ],
          )),
      // Ancho SIEMPRE fijo (antes 90/96 según hasUpgrade) — que cambie de
      // 90 a 96 al instalar corría el botón unos píxeles hacia la
      // izquierda justo al tocarlo, se sentía como que "la card se mueve".
      trailing: SizedBox(
        width: 96,
        child: isLoading
            ? const SizedBox(
                width: 25,
                height: 25,
                child: ProgressRing(),
              )
            // Inestable y todavía no instalada: bloqueada, no se ofrece
            // "Instalar" — el mensaje ya se explica en el subtítulo de
            // abajo. Si YA estaba instalada, se deja el flujo normal
            // (Actualizar/Desinstalar) porque el bloqueo real de uso corre
            // en ExtensionTile vía hasExtensionUpdate.
            : (widget.unstable && !isInstall)
                ? const SizedBox.shrink()
            : isInstall
                ? Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      if (hasUpgrade)
                        SizedBox(
                          height: 32,
                          child: FilledButton(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              await _install();
                              // mounted: instalar y desinstalar tardan (red + escritura en disco) y
                              // la tarjeta puede irse mientras tanto —cambiando de pestaña, tocando
                              // atras, o simplemente porque la lista se refresco—. setState sobre un
                              // widget ya desmontado tira "setState() called after dispose()" y se
                              // lleva la pantalla puesta.
                              if (!mounted) return;
                              setState(() {});
                            },
                            child: Text('extension-repo.upgrade'.i18n),
                          ),
                        ),
                      SizedBox(
                        height: 32,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            await ExtensionUtils.uninstall(widget.package);
                            // Ver la nota de mounted mas arriba.
                            if (!mounted) return;
                            setState(() {
                              isInstall = false;
                            });
                          },
                          child: Text('common.uninstall'.i18n),
                        ),
                      ),
                    ],
                  )
                : TextButton(
                    onPressed: () async {
                      await _install();
                    },
                    child: Text('common.install'.i18n),
                  ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    // Alto FIJO (antes ajustado al contenido con mainAxisSize.min) — con
    // cantidad de badges variable (1 línea vs 2 según la extensión) las
    // cards quedaban de distinto tamaño en la misma fila del grid
    // (confirmado en vivo comparando ManhwaWeb/ShadeManga contra el resto).
    // Con alto fijo + Spacer, todas miden lo mismo y el botón de acción
    // siempre queda anclado abajo sin importar cuánto contenido haya arriba.
    // Contenido centrado (ícono/texto/badges/botón) para que se lea como
    // una tarjeta de "app store" en vez de un bloque alineado a la
    // izquierda.
    return Stack(
      children: [
        Container(
          height: 315,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HomeTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _iconBox(size: 40, iconSize: 20),
              const SizedBox(height: 10),
              // Cortado, al lado sale el botón para verlo completo: acá el
              // nombre es lo único que distingue una tarjeta de otra.
              TextoQueNoCabe(
                widget.name,
                estilo: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'v ${widget.version}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: fluent.FluentTheme.of(context).inactiveColor,
                ),
              ),
              // Descripción — de qué va la extensión (anime, lectura,
              // series, películas, etc), antes no se mostraba en ningún
              // lado pese a que el catálogo ya la trae.
              if (widget.description != null &&
                  widget.description!.trim().isNotEmpty &&
                  widget.description != widget.name) ...[
                const SizedBox(height: 6),
                _descriptionWithSeeMore(
                  context,
                  text: widget.description!,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11,
                    color: HomeTheme.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // Wrap en vez de Row: con varios badges juntos (tipo + idioma +
              // 18+ + inestable + oficial) en una card angosta del grid, un
              // Row fijo tira RenderFlex overflow — confirmado en vivo con
              // ShadeManga ("overflow by 14 pixels").
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _badge(ExtensionUtils.typeToString(widget.type)),
                  _badge(widget.lang),
                  if (widget.nsfw) _badge('+18', color: Colors.redAccent),
                  if (widget.unstable)
                    _badge(ExtensionUtils.etiquetaCortaInestable(widget.unstableReason),
                        color: Colors.orange),
                  if (widget.signature != null && widget.signature!.isNotEmpty)
                    _badge('extension.official-badge'.i18n,
                        color: HomeTheme.accentPink),
                ],
              ),
              if (widget.unstable && !isInstall) ...[
                const SizedBox(height: 8),
                Text(
                  widget.blockedReasonKey.i18n,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.orange),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Spacer(),
              // Alto fijo (36) para el área de acción entera — antes cada
              // rama (spinner/botón único/par de botones) tenía su propio
              // tamaño implícito y la fila se veía "saltar" de tamaño card
              // a card. minimumSize en cada botón: mismo ancho mínimo sin
              // importar si dice "Instalar" o "No disponible".
              SizedBox(
                height: 36,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: ProgressRing(),
                        )
                      : (widget.unstable && !isInstall)
                          ? ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 110,
                                minHeight: 36,
                              ),
                              child: fluent.FilledButton(
                                onPressed: null,
                                child: Text('extension.not-available'.i18n),
                              ),
                            )
                          : isInstall
                              ? Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (hasUpgrade)
                                      // Actualizar es la acción destacada
                                      // (relleno, acento morado); Desinstalar
                                      // queda como link — antes los dos eran
                                      // FilledButton y competían por atención.
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minWidth: 90,
                                          minHeight: 36,
                                        ),
                                        child: fluent.FilledButton(
                                          style: fluent.ButtonStyle(
                                            padding: fluent.WidgetStateProperty
                                                .all(
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10),
                                            ),
                                          ),
                                          child: Text(
                                            'extension-repo.upgrade'.i18n,
                                            style: const TextStyle(
                                                fontSize: 12),
                                          ),
                                          onPressed: () async {
                                            await _install();
                                            // Ver la nota de mounted arriba.
                                            if (!mounted) return;
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 36,
                                      ),
                                      child: fluent.HyperlinkButton(
                                        style: fluent.ButtonStyle(
                                          padding: fluent.WidgetStateProperty
                                              .all(
                                            const EdgeInsets.symmetric(
                                                horizontal: 4),
                                          ),
                                        ),
                                        child: Text(
                                          'common.uninstall'.i18n,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: HomeTheme.accentPink,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onPressed: () async {
                                          await ExtensionUtils.uninstall(
                                              widget.package);
                                          // Ver la nota de mounted arriba.
                                          if (!mounted) return;
                                          setState(() {
                                            isInstall = false;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                )
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 110,
                                    minHeight: 36,
                                  ),
                                  child: fluent.FilledButton(
                                    onPressed: () async {
                                      await _install();
                                    },
                                    child: Text('common.install'.i18n),
                                  ),
                                ),
                ),
              ),
            ],
          ),
        ),
        if (isInstall)
          Positioned(
            top: 8,
            right: 8,
            child: _installedBadge(),
          ),
      ],
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
