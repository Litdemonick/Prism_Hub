import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/utils/color.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';

// Shared tile for the History page (both the History and Favorite tabs):
// cover + title + optional subtitle, with an always-visible delete button —
// no right-click/long-press required to find it.
class HistoryItemCard extends StatelessWidget {
  const HistoryItemCard({
    super.key,
    required this.title,
    required this.onTap,
    required this.onDelete,
    this.cover,
    this.isLocalCover = false,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String? cover;
  // Video history covers are local screenshot files; manga/novel covers are
  // network URLs — same distinction HomeRecentCard already draws.
  final bool isLocalCover;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  Widget _buildCover() {
    if (cover == null) {
      return Container(color: ColorUtils.getColorByText(title));
    }
    if (isLocalCover) {
      return Image.file(
        File(cover!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/cardoffline.png',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    return CacheNetWorkImagePic(
      cover!,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(onTap: onTap, child: _buildCover()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(210),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withAlpha(150),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child:
                      Icon(Icons.delete_outline, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
