import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Un texto que, cuando no entra, ofrece verlo completo.
///
/// ── El problema ─────────────────────────────────────────────────────────
///
/// Los nombres de las extensiones no siempre entran en su renglón, y lo que
/// queda son unos puntos suspensivos. Eso está bien para no romper la fila,
/// pero deja sin salida: no hay manera de saber qué decía. Y en una lista de
/// diecisiete, dos que empiezan igual y se cortan en el mismo punto se ven
/// idénticas.
///
/// ── Por qué un botón y no tocar el texto ────────────────────────────────
///
/// Porque la fila entera ya es tocable: tocar el nombre abre la extensión. Si
/// el texto se robara ese toque, tocar el nombre —que es justo donde uno toca—
/// dejaría de abrirla, y nadie esperaría eso. El botón es chiquito, aparece
/// SOLO cuando el texto está cortado, y no le saca el toque a nadie.
///
/// Es el mismo patrón que ya usa el título de la ficha, y a propósito: dos
/// maneras distintas de resolver lo mismo en la misma app se leen como dos
/// apps.
class TextoQueNoCabe extends StatelessWidget {
  const TextoQueNoCabe(
    this.texto, {
    super.key,
    required this.estilo,
    this.lineas = 1,
    this.tamanoDelBoton = 26,
  });

  final String texto;
  final TextStyle estilo;
  final int lineas;
  final double tamanoDelBoton;

  void _verCompleto(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: HomeTheme.cardSurface,
      showDragHandle: true,
      // Como el resto de las hojas de la app: en una tablet, un panel de lado a
      // lado para dos renglones de texto se ve perdido.
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
        child: SelectableText(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: HomeTheme.textPrimary,
            fontSize: 19,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linea = Text(
      texto,
      maxLines: lineas,
      overflow: TextOverflow.ellipsis,
      style: estilo,
    );

    if (texto.isEmpty) return linea;

    return LayoutBuilder(
      builder: (context, cons) {
        if (!cons.hasBoundedWidth) return linea;
        // Se mide con el ancho ENTERO: si ya no entra teniendo todo el lugar,
        // tampoco va a entrar dejándole sitio al botón. Al revés sí podría
        // fallar —medir con el hueco descontado haría aparecer el botón en
        // nombres que sí entraban—.
        final medidor = TextPainter(
          text: TextSpan(text: texto, style: estilo),
          maxLines: lineas,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: cons.maxWidth);
        final cortado = medidor.didExceedMaxLines;
        medidor.dispose();

        if (!cortado) return linea;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: linea),
            SizedBox(
              width: tamanoDelBoton,
              height: tamanoDelBoton,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: tamanoDelBoton * 0.72,
                // El propio texto como ayuda: mantener pulsado ya lo muestra,
                // sin abrir nada y sin inventar una cadena nueva que traducir.
                tooltip: texto,
                color: HomeTheme.textMuted,
                icon: const Icon(Icons.more_horiz_rounded),
                onPressed: () => _verCompleto(context),
              ),
            ),
          ],
        );
      },
    );
  }
}
