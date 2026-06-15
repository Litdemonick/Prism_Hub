import 'package:flutter/material.dart';

import '../../../data/models/extension_model.dart';

class ExtensionTypeBadge extends StatelessWidget {
  const ExtensionTypeBadge(this.type, {super.key});

  final ExtensionType type;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      ExtensionType.anime        => ('Anime', const Color(0xFF7C3AED)),
      ExtensionType.manga        => ('Manga', const Color(0xFF2563EB)),
      ExtensionType.comic        => ('Comic', const Color(0xFFD97706)),
      ExtensionType.novel        => ('Novela', const Color(0xFF059669)),
      ExtensionType.movie        => ('Película', const Color(0xFFDC2626)),
      ExtensionType.series       => ('Serie', const Color(0xFFDB2777)),
      ExtensionType.documentary  => ('Documental', const Color(0xFF0891B2)),
      ExtensionType.live         => ('En vivo', const Color(0xFFEA580C)),
      ExtensionType.video        => ('Vídeo', const Color(0xFF4F46E5)),
      ExtensionType.music        => ('Música', const Color(0xFF9333EA)),
      ExtensionType.podcast      => ('Podcast', const Color(0xFF65A30D)),
      ExtensionType.other        => ('Otro', const Color(0xFF6B7280)),
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
