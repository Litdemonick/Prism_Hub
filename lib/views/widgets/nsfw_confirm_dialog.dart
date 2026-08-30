import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';

// Diálogo de "¿es contenido +18?" que se muestra ANTES de abrir el
// reproductor/lector o de favoritear.
//
// Antes era un diálogo de texto con dos botones "Sí"/"No" que no explicaban
// nada: no decía qué estaba por pasar ni a dónde iba a quedar guardado el
// título según la respuesta. Ahora cada opción es una tarjeta con su ícono y
// una línea que dice exactamente dónde va a aparecer (Inicio normal o Zona
// +18), que es lo que el usuario necesita para decidir.
//
// Cross-plataforma sin trucos: se usa showPlatformDialog (que ya ramifica
// entre el ContentDialog de fluent en escritorio y el AlertDialog de Material
// en Android) y las tarjetas son GestureDetector + Container, NO InkWell ni
// ListTile — esos necesitan un ancestro Material y reventarían en el árbol
// fluent de escritorio.
// OJO con el async/await de acá: showPlatformDialog NO declara tipo de retorno,
// así que estáticamente es `dynamic`. Encadenarle `.then(...)` es una llamada
// DINÁMICA y el objeto que devuelve es un Future<dynamic>, que al asignarse a
// Future<bool?> explota en tiempo de ejecución con "type 'Future<dynamic>' is
// not a subtype of type 'Future<bool?>'" — confirmado en vivo: el diálogo
// abría, se elegía la opción y el pop llegaba bien, pero esa excepción subía
// por resolveIsNsfw hasta el onTap y mataba la acción en silencio (el favorito
// no se marcaba, los capítulos no abrían). Con `await` dentro de una función
// async el valor se convierte al tipo declarado sin ese problema.
Future<bool?> showNsfwConfirmDialog(
  BuildContext context, {
  required String title,
  required ExtensionType type,
  // true cuando se está por abrir el contenido (mostrar "vas a empezar a
  // leer/ver"); false cuando es solo para guardar en favoritos.
  bool opening = true,
  // La extensión YA viene marcada +18 en el catálogo. Cambia el tono del
  // diálogo: en vez de preguntar en frío como si nada sugiriera que es adulto,
  // se avisa que la extensión es +18 y se sugiere que lo más probable es que
  // sí lo sea — pero se deja elegir igual, porque una extensión +18 puede
  // tener contenido normal mezclado (ShadeManga/ManhwaWeb es justo el caso).
  bool extensionIsNsfw = false,
}) async {
  final isVideo = ExtensionUtils.videoTypes.contains(type);
  final actionLine = opening
      ? (isVideo
          ? 'nsfw18.is-adult-about-to-watch'.i18n
          : 'nsfw18.is-adult-about-to-read'.i18n)
      : 'nsfw18.is-adult-about-to-favorite'.i18n;

  final value = await showPlatformDialog(
    context: context,
    title: extensionIsNsfw
        ? 'nsfw18.is-adult-title-nsfw-ext'.i18n
        : 'nsfw18.is-adult-title'.i18n,
    content: _NsfwConfirmContent(
      title: title,
      actionLine: actionLine,
      isVideo: isVideo,
      extensionIsNsfw: extensionIsNsfw,
    ),
    // ── El contenido ya trae SU scroll ─────────────────────────────────
    //
    // Sin esto, el AlertDialog le pone otro por fuera, y es la trampa que el
    // propio showPlatformDialog documenta: dos scrolls anidados se pelean el
    // gesto —el de adentro se lo queda— y encima el de afuera hace que el
    // diálogo pida el alto entero del contenido, así que las acciones se
    // quedan sin lugar.
    //
    // Lo que se veía acostado: la tarjeta de «Sí, es contenido +18» cortada por
    // la mitad y el botón de Cancelar montado encima.
    scrollable: false,
    // Las acciones van dentro del contenido (las dos tarjetas), así que acá
    // solo queda cancelar. Cancelar devuelve null y quien llama trata eso como
    // "no hacer nada", no como "no es +18".
    actions: [
      const _CancelButton(),
    ],
  );
  // Chequeo en vez de `as bool?`: un `as` con un valor inesperado también
  // lanzaría. Cualquier cosa que no sea bool se trata como "canceló".
  final answer = value is bool ? value : null;

  // Repregunta: decir "no es +18" DENTRO de una extensión marcada +18 es casi
  // siempre un toque equivocado, y esa respuesta manda el contenido al Home
  // normal. Así que se re-confirma una sola vez, en vez de aceptarla en
  // silencio. Solo aplica cuando la extensión es +18 y solo para el "no": el
  // "sí" sigue de largo sin molestar.
  if (answer == false && extensionIsNsfw && context.mounted) {
    final sure = await showPlatformDialog(
      context: context,
      title: 'nsfw18.is-adult-recheck-title'.i18n,
      // Más ancho que el default (368): con el título en una sola línea y el
      // texto de la consecuencia respirando, se lee mucho mejor.
      maxWidth: 440,
      // Se puede cerrar tocando afuera, y eso CANCELA: no cambia nada. Estuvo
      // en false un tiempo por un motivo que ya no aplica — antes cualquier
      // cosa distinta de "true" se tomaba como "sí es +18", así que un toque
      // al costado marcaba el contenido solo. Ahora el resultado tiene tres
      // valores y el null se maneja como cancelación (ver más abajo), así que
      // dejar salir por la barrera es seguro y es lo que se espera de un
      // diálogo de confirmación.
      barrierDismissible: true,
      content: const _RecheckContent(),
      // Se cierra con el Navigator DEL DIÁLOGO (de ahí el Builder), nunca con
      // RouterUtils.pop: en escritorio eso es router.pop() de go_router y este
      // diálogo no es una ruta de go_router, así que el resultado no llegaría
      // nunca — es el mismo error que ya rompió las tarjetas de este diálogo
      // (ver el comentario largo en _OptionCard).
      actions: [
        // Volver atrás deja la respuesta en "sí, es +18", que es lo esperable
        // estando en una zona +18 — el camino seguro por defecto.
        Builder(
          builder: (ctx) => PlatformTextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: _RecheckButtonLabel(
              icon: Icons.arrow_back_rounded,
              label: 'nsfw18.is-adult-recheck-back'.i18n,
            ),
          ),
        ),
        Builder(
          builder: (ctx) => PlatformFilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: _RecheckButtonLabel(
              icon: Icons.check_rounded,
              label: 'nsfw18.is-adult-recheck-confirm'.i18n,
            ),
          ),
        ),
      ],
    );
    // Tres resultados distintos a propósito, no dos:
    //   true  → confirmó que NO es +18 → se respeta el "no".
    //   false → tocó "mejor no, sí es +18" → se corrige a "sí".
    //   null  → se cerró sin responder → CANCELAR (no hacer nada), no asumir.
    // Antes cualquier cosa que no fuera `true` caía en "sí es +18", así que un
    // cierre sin respuesta marcaba el contenido igual.
    if (sure == true) return false;
    if (sure == false) return true;
    return null;
  }

  return answer;
}

// Etiqueta con ícono para los botones de la repregunta. Widget aparte y no un
// Row inline porque los botones de plataforma reciben un solo `child`, y así
// queda igual en el árbol fluent de escritorio y en el Material de Android.
class _RecheckButtonLabel extends StatelessWidget {
  const _RecheckButtonLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 6),
        // Sin salto de línea: con el diálogo a 440 de ancho entran las dos
        // etiquetas en una sola línea, que es lo que se veía mal antes.
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// Contenido de la repregunta ("¿seguro que no es +18?"). Mismo lenguaje visual
// que el diálogo principal (HomeTheme, insignia circular con ícono, caja de
// aviso) en vez del texto pelado que salía antes.
class _RecheckContent extends StatelessWidget {
  const _RecheckContent();

  @override
  Widget build(BuildContext context) {
    // En celular en horizontal queda muy poco alto: ahí se compacta igual que
    // hace _NsfwConfirmContent.
    final tight = MediaQuery.sizeOf(context).height < 560;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 400, maxHeight: tight ? 260 : 420),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: tight ? 38 : 46,
                  height: tight ? 38 : 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HomeTheme.accentRed.withValues(alpha: 0.16),
                    border: Border.all(
                      color: HomeTheme.accentRed.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    color: HomeTheme.accentRed,
                    size: tight ? 21 : 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'nsfw18.is-adult-recheck-lead'.i18n,
                    style: TextStyle(
                      color: HomeTheme.textPrimary,
                      fontSize: tight ? 13.5 : 14.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tight ? 12 : 16),
            // La consecuencia va en su propia caja: es el dato que de verdad
            // decide la respuesta, y suelto en el párrafo se perdía.
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(tight ? 10 : 13),
              decoration: BoxDecoration(
                color: HomeTheme.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: HomeTheme.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: tight ? 15 : 17,
                    color: HomeTheme.textMuted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'nsfw18.is-adult-recheck-consequence'.i18n,
                      style: TextStyle(
                        color: HomeTheme.textMuted,
                        fontSize: tight ? 12 : 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NsfwConfirmContent extends StatelessWidget {
  const _NsfwConfirmContent({
    required this.title,
    required this.actionLine,
    required this.isVideo,
    required this.extensionIsNsfw,
  });

  final String title;
  final String actionLine;
  final bool isVideo;
  final bool extensionIsNsfw;

  @override
  Widget build(BuildContext context) {
    // Solo el tamaño: con `MediaQuery.of(context)` entero, este diálogo se
    // reconstruía ante cualquier cambio del entorno y no solo ante el que mira.
    final media = MediaQuery.sizeOf(context);
    // Horizontal en un celular: la altura útil es muy poca y el diálogo dejaba
    // la tarjeta de "Sí, es contenido +18" fuera de la vista, sin forma de
    // llegar a ella (reportado en vivo). Se detecta por ALTURA, no por
    // orientación: una ventana de escritorio angosta de alto tiene el mismo
    // problema, y un tablet en horizontal tiene alto de sobra y no necesita
    // apretar nada.
    final tight = media.height < 560;
    final gap = tight ? 6.0 : 12.0;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isVideo ? Icons.play_circle_outline : Icons.menu_book_outlined,
              size: 18,
              color: HomeTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                actionLine,
                style: TextStyle(
                  fontSize: 13,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: tight ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: gap),
        // Aviso extra solo cuando la extensión ya está marcada +18: sin esto el
        // texto preguntaba en frío, como si nada indicara que es adulto, y
        // quedaba raro justo en las extensiones donde sí lo indica.
        if (extensionIsNsfw) ...[
          Container(
            width: double.infinity,
            padding:
                EdgeInsets.symmetric(horizontal: 10, vertical: tight ? 6 : 8),
            decoration: BoxDecoration(
              color: HomeTheme.accentRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: HomeTheme.accentRed.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: HomeTheme.accentRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'nsfw18.is-adult-ext-warning'.i18n,
                    style: TextStyle(
                      fontSize: 12,
                      color: HomeTheme.accentRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
        ],
        Text(
          extensionIsNsfw
              ? 'nsfw18.is-adult-question-nsfw-ext'.i18n
              : 'nsfw18.is-adult-question'.i18n,
          style: const TextStyle(fontSize: 13.5),
        ),
        SizedBox(height: gap),
        // Con la extensión marcada +18 el orden se invierte: primero la opción
        // más probable (que sí es +18), así es la que queda a mano.
        if (extensionIsNsfw) ...[
          _OptionCard(
            icon: Icons.lock_outline,
            accent: HomeTheme.accentRed,
            label: 'nsfw18.is-adult-yes'.i18n,
            hint: 'nsfw18.is-adult-yes-hint'.i18n,
            result: true,
            compact: tight,
          ),
          const SizedBox(height: 8),
          _OptionCard(
            icon: Icons.home_outlined,
            accent: HomeTheme.accentPink,
            label: 'nsfw18.is-adult-no'.i18n,
            hint: 'nsfw18.is-adult-no-hint'.i18n,
            result: false,
            compact: tight,
          ),
        ] else ...[
          _OptionCard(
            icon: Icons.home_outlined,
            accent: HomeTheme.accentPink,
            label: 'nsfw18.is-adult-no'.i18n,
            hint: 'nsfw18.is-adult-no-hint'.i18n,
            result: false,
            compact: tight,
          ),
          const SizedBox(height: 8),
          _OptionCard(
            icon: Icons.lock_outline,
            accent: HomeTheme.accentRed,
            label: 'nsfw18.is-adult-yes'.i18n,
            hint: 'nsfw18.is-adult-yes-hint'.i18n,
            result: true,
            compact: tight,
          ),
        ],
      ],
    );

    // El scroll propio es la red de seguridad real: el AlertDialog de Android
    // ya scrollea su contenido, pero con el alto de una pantalla en horizontal
    // eso no alcanzaba y la última tarjeta quedaba inalcanzable. Acotando el
    // alto a una fracción de la pantalla y scrolleando acá dentro, las dos
    // opciones siempre se pueden alcanzar, en cualquier orientación y en las
    // tres plataformas.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        // ── Se descuenta lo que ocupa el diálogo, no una fracción ────────
        //
        // Con pantalla baja, el 62% del alto no dejaba sitio para el título ni
        // para el botón de cancelar: entre los tres pedían más que la pantalla
        // y el diálogo terminaba con la última tarjeta cortada y el botón
        // encima. Descontando lo que se lleva el diálogo —título, botones y
        // sus márgenes— el contenido pide justo lo que queda y siempre entra.
        //
        // De pie sobra alto, así que ahí sigue la fracción de siempre: el
        // diálogo no tiene por qué ocupar toda la pantalla cuando no hace
        // falta.
        maxHeight: tight
            ? math.max(120.0, media.height - 200)
            : media.height * 0.7,
      ),
      child: SingleChildScrollView(child: content),
    );
  }
}

// Tarjeta tocable de una opción. Alto mínimo generoso: en celular tiene que
// ser cómoda de acertar con el dedo, y en escritorio queda bien igual.
class _OptionCard extends StatefulWidget {
  const _OptionCard({
    required this.icon,
    required this.accent,
    required this.label,
    required this.hint,
    required this.result,
    this.compact = false,
  });

  // En pantallas de poco alto (celular en horizontal) la tarjeta se achica:
  // menos padding y sin la línea de ayuda, para que las DOS opciones entren.
  final bool compact;

  final IconData icon;
  final Color accent;
  final String label;
  final String hint;
  // Se cierra con el Navigator PROPIO de este widget (que vive dentro de la
  // ruta del diálogo), no con RouterUtils.pop. En escritorio RouterUtils.pop
  // es router.pop() de go_router, y este diálogo NO es una ruta de go_router
  // (lo empuja fluent.showDialog sobre el Navigator) — por eso al tocar una
  // opción no llegaba ningún resultado, resolveIsNsfw recibía null y la acción
  // se abortaba: favorito no se marcaba y los capítulos no abrían (reportado
  // en vivo). Con Navigator.of(context) funciona igual en las dos plataformas
  // y sin depender del router.
  final bool result;

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(widget.result),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          constraints: BoxConstraints(minHeight: widget.compact ? 44.0 : 56.0),
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: widget.compact ? 6 : 10,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.16)
                : HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? widget.accent : HomeTheme.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: widget.compact ? 28 : 34,
                height: widget.compact ? 28 : 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.accent.withValues(alpha: 0.16),
                ),
                child: Icon(widget.icon,
                    size: widget.compact ? 16 : 18, color: widget.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: HomeTheme.textPrimary,
                      ),
                    ),
                    // La línea de ayuda ("aparece en tu Inicio..." / "solo en
                    // la Zona +18...") se oculta en compacto: es lo primero
                    // sacrificable para que las dos opciones entren en un
                    // celular en horizontal, y el ícono + la etiqueta ya
                    // dicen a dónde va.
                    if (!widget.compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.hint,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: HomeTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: HomeTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Mismo criterio que las tarjetas: se cierra con el Navigator propio.
      // Sin resultado -> null, que quien llama trata como "no hacer nada".
      onTap: () => Navigator.of(context).pop(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'common.cancel'.i18n,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
