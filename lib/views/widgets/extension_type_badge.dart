import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';

/// Small pill showing the content type (Video/Manga/Novela) — solo se usa en
/// Home (Continuar/Favoritos), donde una fila puede mezclar tipos distintos
/// y no queda claro de un vistazo qué es cada tarjeta.
class ExtensionTypeBadge extends StatelessWidget {
  const ExtensionTypeBadge({super.key, required this.type});
  final ExtensionType type;

  Color get _color => switch (type) {
        ExtensionType.bangumi => const Color(0xFF3B82F6), // azul — video
        ExtensionType.manga => const Color(0xFFA855F7), // violeta — manga
        ExtensionType.fikushon => const Color(0xFF22C55E), // verde — novela
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
