import 'package:prismhub/views/widgets/detail/detail_finished_button.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/providers/tmdb_provider.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';

class DetailOverView extends StatelessWidget {
  const DetailOverView({
    super.key,
    this.tag,
  });

  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DetailPageController>(tag: tag);
    return Padding(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En celular el botón va acá y no en el hero: ahí ya conviven
            // "Continuar" y "Favorito" en un ancho justo, y en horizontal un
            // tercero los dejaba ilegibles. Acá además queda al lado del
            // estado que informa la extensión, que es con lo que dialoga.
            if (Platform.isAndroid) ...[
              DetailFinishedButton(tag: tag),
              const SizedBox(height: 16),
            ],
            Obx(() {
              if (c.tmdbDetail == null || c.tmdbDetail!.backdrop == null) {
                return const SizedBox();
              }
              final images = [c.tmdbDetail!.backdrop!, ...c.tmdbDetail!.images];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'tmdb.backdrops'.i18n,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final image = images[index];
                        final url = TmdbApi.getImageUrl(image);
                        if (url == null) {
                          return const SizedBox();
                        }
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          margin: const EdgeInsets.only(right: 8),
                          child: CacheNetWorkImagePic(
                            url,
                            height: 160,
                            canFullScreen: true,
                          ),
                        );
                      },
                      itemCount: images.length,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }),
            Obx(() {
              final desc = c.tmdbDetail?.overview ?? c.detail?.desc;
              final hasDesc = desc != null && desc.isNotEmpty;
              return SelectableText(
                hasDesc ? desc : "detail.no-description".i18n,
                style: const TextStyle(height: 2),
              );
            }),
            const SizedBox(height: 20),
            Obx(
              () {
                if (c.tmdbDetail == null) {
                  return const SizedBox();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'detail.additional-info'.i18n,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "${'tmdb.status'.i18n}: ${c.tmdbDetail!.status}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.genres'.i18n}: ${c.tmdbDetail!.genres.join(', ')}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.languages'.i18n}: ${c.tmdbDetail!.languages.join(', ')}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.release-date'.i18n}: ${c.tmdbDetail!.releaseDate}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.original-title'.i18n}: ${c.tmdbDetail!.originalTitle}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.runtime'.i18n}: ${c.tmdbDetail!.runtime}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
              },
            )
          ],
        ),
      ),
    );
  }
}
