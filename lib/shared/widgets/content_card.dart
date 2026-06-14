import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/media_item.dart';
import '../../modules/detail/detail_page.dart';

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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.cover != null && item.cover!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.cover!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (ctx, url, err) => _placeholder(cs),
                      )
                    : _placeholder(cs),
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
    color: cs.surfaceContainerHighest,
    child: Center(
      child: Icon(Icons.image_not_supported_outlined, color: cs.outline),
    ),
  );
}
