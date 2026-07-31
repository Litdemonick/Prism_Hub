import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Subtítulo de Ajustes con "+18" resaltado en rojo.
///
/// El texto llega como String desde muchos lugares, así que en vez de cambiar
/// todas esas firmas a Widget se resalta acá, en el único punto donde se
/// dibuja. Solo marca ese token: cualquier otro texto sale igual que siempre.
class SettingsSubtitle extends StatelessWidget {
  const SettingsSubtitle(this.text, {super.key, this.fontSize = 12});
  final String text;
  final double fontSize;

  static const _marca = '+18';

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, color: HomeTheme.textMuted);
    if (!text.contains(_marca)) return Text(text, style: base);

    final partes = text.split(_marca);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          for (var i = 0; i < partes.length; i++) ...[
            if (i > 0)
              const TextSpan(
                text: _marca,
                style: TextStyle(
                  color: HomeTheme.accentRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            TextSpan(text: partes[i]),
          ],
        ],
      ),
    );
  }
}
