import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/media_item.dart';
import '../../data/models/extension_model.dart';
import 'detail_controller.dart';

/// Argumentos de navegación hacia DetailPage, pasados via GoRouter extra.
class DetailArgs {
  const DetailArgs({required this.url, required this.package, this.item});

  final String url;
  final String package;
  final MediaItem? item; // preview mientras carga
}

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.args});

  final DetailArgs args;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final DetailController _c;

  @override
  void initState() {
    super.initState();
    // Tag único por URL para no mezclar detalle de items distintos.
    _c = Get.put(DetailController(), tag: widget.args.url);
    _c.load(widget.args.url, widget.args.package);
  }

  @override
  void dispose() {
    Get.delete<DetailController>(tag: widget.args.url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Mientras carga y no hay datos previos, muestra skeleton.
      if (_c.isLoading.value && _c.detail.value == null) {
        return _LoadingScaffold(preview: widget.args.item);
      }

      if (_c.error.value != null && _c.detail.value == null) {
        return _ErrorScaffold(message: _c.error.value!);
      }

      final d = _c.detail.value!;
      return _DetailScaffold(detail: d);
    });
  }
}

// ---------------------------------------------------------------------------
// Scaffold principal
// ---------------------------------------------------------------------------

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.detail});
  final MediaDetail detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _CoverAppBar(
            title: detail.title,
            cover: detail.cover,
            type: detail.type,
          ),
          SliverToBoxAdapter(child: _InfoSection(detail: detail)),
          if (detail.episodes.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  _episodeLabel(detail.type, detail.episodes.length),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: detail.episodes.length,
              separatorBuilder: (ctx, i) =>
                  const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) => _EpisodeTile(
                episode: detail.episodes[i],
                number: detail.episodes.length - i,
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ],
      ),
    );
  }

  String _episodeLabel(ExtensionType type, int count) {
    final word = switch (type) {
      ExtensionType.anime => 'Episodios',
      ExtensionType.manga => 'Capítulos',
      ExtensionType.comic => 'Issues',
      ExtensionType.novel => 'Capítulos',
    };
    return '$word ($count)';
  }
}

// ---------------------------------------------------------------------------
// SliverAppBar con portada
// ---------------------------------------------------------------------------

class _CoverAppBar extends StatelessWidget {
  const _CoverAppBar({required this.title, this.cover, required this.type});

  final String title;
  final String? cover;
  final ExtensionType type;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        background: cover != null && cover!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: cover!,
                fit: BoxFit.cover,
                errorWidget: (ctx, url, err) => _bg(cs),
              )
            : _bg(cs),
      ),
    );
  }

  Widget _bg(ColorScheme cs) => Container(
    color: cs.surfaceContainerHighest,
    child: Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 64,
        color: cs.outline,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Sección de metadata
// ---------------------------------------------------------------------------

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.detail});
  final MediaDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.description != null && detail.description!.isNotEmpty) ...[
            Text(
              detail.description!,
              style: TextStyle(color: cs.onSurfaceVariant),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],
          if (detail.extra != null)
            ...detail.extra!.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: cs.onSurface, fontSize: 13),
                    children: [
                      TextSpan(
                        text: '${e.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: e.value),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de episodio
// ---------------------------------------------------------------------------

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.number});

  final MediaEpisode episode;
  final int number;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 12,
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(episode.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.play_arrow_rounded),
      onTap: () {
        // Bloque 3: navegar a player/reader
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Estados de carga y error
// ---------------------------------------------------------------------------

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({this.preview});
  final MediaItem? preview;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(preview?.title ?? '')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
