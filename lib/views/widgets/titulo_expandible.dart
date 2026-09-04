import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Un título de una sola línea que, si no entra y termina cortado en "...",
/// se puede tocar para verlo completo, grande, en el medio de la pantalla.
///
/// ── Por qué hace falta ───────────────────────────────────────────────────
///
/// La barra del lector (PC y Android) tiene poco ancho para el título —
/// comparte la fila con la flecha de volver, capítulo anterior/siguiente,
/// ajustes, detalle y episodios — y el nombre de una obra larga («Una Carta
/// De Amor Del Futuro Enviada Al Pasado Que Ya No Existe») queda cortado sin
/// ninguna forma de leerlo entero sin salir a la ficha.
///
/// ── Por qué se mide en vez de tocar siempre ────────────────────────────
///
/// Si el título entra entero, tocarlo no debería hacer nada — abrir un
/// diálogo vacío de sorpresa por tocar un texto que ya se lee bien sería
/// peor que el problema que resuelve. `TextPainter.didExceedMaxLines` mide
/// contra el ancho real disponible (el mismo que usa `Text` para decidir
/// dónde cortar), así que el toque solo hace algo cuando el "..." está de
/// verdad ahí.
class TituloExpandible extends StatelessWidget {
  const TituloExpandible(
    this.texto, {
    super.key,
    this.style,
    this.textAlign,
  });

  final String texto;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final estilo = style ?? DefaultTextStyle.of(context).style;
    final textoWidget = Text(
      texto,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: estilo,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return textoWidget;
        final painter = TextPainter(
          text: TextSpan(text: texto, style: estilo),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        if (!painter.didExceedMaxLines) return textoWidget;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _mostrarTituloCompleto(context, texto),
          child: textoWidget,
        );
      },
    );
  }
}

void _mostrarTituloCompleto(BuildContext context, String texto) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => Dialog(
      backgroundColor: HomeTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: HomeTheme.textPrimary,
          ),
        ),
      ),
    ),
  );
}
