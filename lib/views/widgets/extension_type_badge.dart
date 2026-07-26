import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';

/// Small pill showing the content type (Video/Manga/Novela) — solo se usa en
/// Home (Continuar/Favoritos), donde una fila puede mezclar tipos distintos
/// y no queda claro de un vistazo qué es cada tarjeta.
class ExtensionTypeBadge extends StatelessWidget {
  const ExtensionTypeBadge({super.key, required this.type});
  final ExtensionType type;

  // Manga y novela comparten etiqueta ("Lectura") y por eso también color —
  // ver ExtensionUtils.typeToString. "mixed" no debería llegar acá en la
  // práctica (History/Favorite ya guardan el tipo RESUELTO por título vía
  // ExtensionUtils.resolveType, nunca el literal mixed) — el caso solo
  // existe porque el switch expression de Dart exige cubrir el enum entero.
  Color get _color => switch (type) {
        ExtensionType.bangumi => const Color(0xFF3B82F6), // azul — video
        ExtensionType.manga || ExtensionType.fikushon => const Color(0xFFA855F7), // violeta — lectura
        ExtensionType.mixed => const Color(0xFF10B981), // verde esmeralda — mixta
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
          ),
        ],
      ),
      child: Text(
        ExtensionUtils.typeToString(type),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
