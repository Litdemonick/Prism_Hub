import 'package:flutter/material.dart';

import '../../../data/models/extension_model.dart';

class ExtensionTypeBadge extends StatelessWidget {
  const ExtensionTypeBadge(this.type, {super.key});

  final ExtensionType type;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      ExtensionType.anime => ('Anime', Colors.purple),
      ExtensionType.manga => ('Manga', Colors.blue),
      ExtensionType.comic => ('Comic', Colors.orange),
      ExtensionType.novel => ('Novela', Colors.green),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
