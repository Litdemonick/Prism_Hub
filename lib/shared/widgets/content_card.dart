import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/media_item.dart';
import '../../modules/detail/detail_page.dart';
import '../widgets/type_icon.dart';

class ContentCard extends StatelessWidget {
  const ContentCard({super.key, required this.item, this.width = 130});

  final MediaItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.detail,
        extra: DetailArgs(url: item.url, package: item.package, item: item),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Portada
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.cover != null && item.cover!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.cover!,
                            fit: BoxFit.cover,
                            errorWidget: (ctx, url, err) => _placeholder(cs),
                          )
                        : _placeholder(cs),
                  ),
                  // Badge tipo — esquina superior izquierda
                  Positioned(
                    top: 6,
                    left: 6,
                    child: MediaTypeChip(item.type),
                  ),
                  // Badge rating — esquina superior derecha
                  if (item.rating != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _RatingBadge(item.rating!),
                    ),
                  // Año — esquina inferior izquierda
                  if (item.year != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(8),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Text(
                          '${item.year}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Icon(Icons.movie_outlined, color: cs.outline, size: 32),
    ),
  );
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge(this.rating);
  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 11),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
