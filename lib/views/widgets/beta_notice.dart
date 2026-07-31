import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Aviso de versión beta, una sola vez por instalación.
///
/// Se guarda la VERSIÓN en la que se aceptó y no un simple booleano: así, si
/// más adelante hace falta volver a avisar algo importante en una versión
/// nueva, alcanza con comparar. Y mientras el usuario no confirme —porque
/// cerró la app, porque tocó afuera— vuelve a salir en el próximo arranque,
/// que es lo pedido: solo desaparece cuando de verdad lo leyó y aceptó.
Future<void> showBetaNoticeIfNeeded(BuildContext context) async {
  try {
    final aceptada = PrismHubStorage.getSetting(SettingKey.betaNoticeAccepted);
    if (aceptada is String && aceptada.isNotEmpty) return;

    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    final confirmado = await showPlatformDialog(
      context: context,
      title: 'beta.title'.i18n,
      maxWidth: 520,
      // No se cierra tocando afuera: la idea es que quede constancia de que se
      // leyó. Si se pudiera esquivar, el aviso volvería en cada arranque y
      // terminaría siendo una molestia en vez de una advertencia.
      barrierDismissible: false,
      content: _BetaContent(version: info.version),
      actions: [
        // Justo donde se avisa que puede haber fallos: es el momento en que
        // el usuario más va a necesitar saber dónde reportarlos.
        Builder(
          builder: (ctx) => PlatformTextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://github.com/Litdemonick/Prism_Hub/issues'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text('beta.feedback'.i18n),
          ),
        ),
        Builder(
          builder: (ctx) => PlatformFilledButton(
            // Repregunta antes de cerrar: este aviso no vuelve a salir nunca
            // más, así que quien lo cierre de un toque sin leer se pierde lo
            // de los anuncios, las funciones a medias y el aviso legal.
            onPressed: () async {
              final seguro = await showPlatformDialog(
                context: ctx,
                title: 'beta.confirm-title'.i18n,
                maxWidth: 420,
                content: Text(
                  'beta.confirm-body'.i18n,
                  style: const TextStyle(
                    color: HomeTheme.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                actions: [
                  Builder(
                    builder: (c2) => PlatformTextButton(
                      onPressed: () => Navigator.of(c2).pop(false),
                      child: Text('beta.confirm-read-again'.i18n),
                    ),
                  ),
                  Builder(
                    builder: (c2) => PlatformFilledButton(
                      onPressed: () => Navigator.of(c2).pop(true),
                      child: Text('beta.confirm-yes'.i18n),
                    ),
                  ),
                ],
              );
              // Solo se cierra si confirmó; cualquier otra cosa lo deja
              // abierto donde estaba, sin perder el desplazamiento.
              if (seguro == true && ctx.mounted) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: Text('beta.accept'.i18n),
          ),
        ),
      ],
    );

    if (confirmado == true) {
      await PrismHubStorage.setSetting(
          SettingKey.betaNoticeAccepted, info.version);
    }
  } catch (e, st) {
    // Un aviso informativo no puede impedir que la app arranque.
    logger.warning('No se pudo mostrar el aviso de beta: $e', e, st);
  }
}

class _BetaContent extends StatefulWidget {
  const _BetaContent({required this.version});
  final String version;

  @override
  State<_BetaContent> createState() => _BetaContentState();
}

class _BetaContentState extends State<_BetaContent> {
  // Controller propio: dentro de un diálogo el scroll no es el primario, así
  // que sin esto la barra no sabe a qué lista seguir y no se dibuja.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _punto(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: HomeTheme.accentPink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: HomeTheme.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // El contenido es largo y el diálogo no scrollea solo: en una ventana
    // chica de escritorio, y sobre todo en celular en horizontal (donde el
    // alto útil es la mitad), se cortaba por arriba y no había forma de
    // llegar al resto. Se acota a un 55% del alto de pantalla y lo que no
    // entre se desplaza.
    // En Android el diálogo YA es un AlertDialog(scrollable: true): desplaza
    // título, contenido y botones juntos. Meterle acá otro
    // SingleChildScrollView con alto acotado dejaba DOS scrolls anidados —
    // el de afuera no podía pasar de largo y el final del texto quedaba
    // recortado, sobre todo en horizontal. Ahí se devuelve el contenido
    // pelado y desplaza el diálogo.
    //
    // En escritorio el ContentDialog de fluent no desplaza nada, así que el
    // scroll y el límite de alto se ponen acá.
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Insignia e idioma en la misma línea. El selector va ACÁ porque este
        // aviso es lo primero que ve alguien que recién instaló: si el app
        // arrancó en un idioma que no entiende, obligarlo a leer todo esto y
        // buscar Ajustes después no tiene sentido.
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: HomeTheme.accentPink.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: HomeTheme.accentPink),
              ),
              child: Text(
                'BETA · v${widget.version}',
                style: const TextStyle(
                  color: HomeTheme.accentPink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            _SelectorIdioma(onCambio: () => setState(() {})),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'beta.intro'.i18n,
          style: const TextStyle(
            color: HomeTheme.textPrimary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        _punto(Icons.bug_report_outlined, 'beta.point-bugs'.i18n),
        _punto(Icons.extension_outlined, 'beta.point-extensions'.i18n),
        _punto(Icons.cloud_download_outlined, 'beta.point-ext-updates'.i18n),
        _punto(Icons.update, 'beta.point-updates'.i18n),
        _punto(Icons.tune, 'beta.point-settings'.i18n),
        _punto(Icons.pending_outlined, 'beta.point-wip'.i18n),
        _punto(Icons.palette_outlined, 'beta.point-design'.i18n),
        // Solo en Linux: en Windows y Android sería ruido hablar de una
        // plataforma que no es la suya.
        if (Platform.isLinux)
          _punto(
              Icons.desktop_access_disabled_outlined, 'beta.point-linux'.i18n),
        _punto(Icons.construction, 'beta.point-author'.i18n),
        _punto(Icons.favorite_outline, 'beta.point-thanks'.i18n),
        // El aviso legal es un bloque aparte, no un punto mas de la lista:
        // sin esta separacion quedaba pegado al ultimo item y se leia como si
        // fuera parte de la enumeracion.
        const SizedBox(height: 10),
        // Aviso legal. Va DENTRO del aviso que todo usuario nuevo tiene que
        // aceptar, no escondido en un menú: si nadie lo lee, no cumple su
        // función. Se guarda que fue aceptado junto con el resto.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: HomeTheme.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.gavel_rounded,
                  size: 18, color: HomeTheme.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'beta.legal'.i18n,
                  style: const TextStyle(
                    color: HomeTheme.textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (Platform.isAndroid) return contenido;
    final alto = MediaQuery.sizeOf(context).height * 0.6;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: alto.clamp(200.0, 620.0)),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.only(right: 14, bottom: 8),
          child: contenido,
        ),
      ),
    );
  }
}

/// Selector de idioma compacto: dos mitades en una misma cápsula, la activa
/// resaltada. Un desplegable para dos opciones sería un toque de más, y en
/// este aviso el idioma tiene que poder cambiarse de un vistazo.
class _SelectorIdioma extends StatelessWidget {
  const _SelectorIdioma({required this.onCambio});
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context) {
    final actual = I18nUtils.currentLanguageCode;
    Widget mitad(String codigo, String etiqueta) {
      final activo = actual == codigo;
      return GestureDetector(
        onTap: activo
            ? null
            : () async {
                await PrismHubStorage.setSetting(SettingKey.language, codigo);
                await I18nUtils.changeLanguage(codigo);
                onCambio();
              },
        child: MouseRegion(
          cursor: activo ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: activo ? HomeTheme.accentPink : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              etiqueta,
              style: TextStyle(
                color: activo ? Colors.white : HomeTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HomeTheme.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [mitad('es', 'ES'), mitad('en', 'EN')],
      ),
    );
  }
}
