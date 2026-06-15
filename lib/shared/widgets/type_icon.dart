import 'package:flutter/material.dart';

import '../../data/models/extension_model.dart';

/// Mini chip de tipo para usar sobre portadas (ContentCard).
class MediaTypeChip extends StatelessWidget {
  const MediaTypeChip(this.type, {super.key});
  final ExtensionType type;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _typeData(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static (String, Color) _typeData(ExtensionType t) => switch (t) {
    ExtensionType.anime => ('ANIME', const Color(0xFF7C3AED)),
    ExtensionType.manga => ('MANGA', const Color(0xFF2563EB)),
    ExtensionType.comic => ('COMIC', const Color(0xFFD97706)),
    ExtensionType.novel => ('NOVEL', const Color(0xFF059669)),
    ExtensionType.movie => ('MOVIE', const Color(0xFFDC2626)),
    ExtensionType.series => ('SERIE', const Color(0xFFDB2777)),
    ExtensionType.documentary => ('DOC', const Color(0xFF0891B2)),
    ExtensionType.live => ('LIVE', const Color(0xFFEA580C)),
    ExtensionType.video => ('VIDEO', const Color(0xFF4F46E5)),
    ExtensionType.music => ('MUSIC', const Color(0xFF9333EA)),
    ExtensionType.podcast => ('CAST', const Color(0xFF65A30D)),
    ExtensionType.other => ('OTHER', const Color(0xFF6B7280)),
  };
}

/// Icono de tipo para usar en listas (EpisodeTile, etc.)
IconData mediaTypeIcon(ExtensionType t) => switch (t) {
  ExtensionType.manga ||
  ExtensionType.comic ||
  ExtensionType.novel => Icons.menu_book_rounded,
  ExtensionType.music => Icons.music_note_rounded,
  ExtensionType.podcast => Icons.podcasts_rounded,
  ExtensionType.live => Icons.live_tv_rounded,
  _ => Icons.play_arrow_rounded,
};
