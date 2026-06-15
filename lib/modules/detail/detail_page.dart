import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/extension_model.dart';
import '../../data/models/media_item.dart';
import '../../shared/widgets/type_icon.dart';
import '../player/watch_args.dart';
import 'detail_controller.dart';

class DetailArgs {
  const DetailArgs({required this.url, required this.package, this.item});
  final String url;
  final String package;
  final MediaItem? item;
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
      if (_c.isLoading.value && _c.detail.value == null) {
        return _LoadingScaffold(preview: widget.args.item);
      }
      if (_c.error.value != null && _c.detail.value == null) {
        return _ErrorScaffold(message: _c.error.value!);
      }
      return _DetailScaffold(detail: _c.detail.value!);
    });
  }
}

// ---------------------------------------------------------------------------
// Scaffold principal
// ---------------------------------------------------------------------------

class _DetailScaffold extends StatefulWidget {
  const _DetailScaffold({required this.detail});
  final MediaDetail detail;

  @override
  State<_DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<_DetailScaffold> {
  int _selectedSeason = 0;

  MediaDetail get d => widget.detail;

  List<MediaEpisode> get _currentEpisodes {
    if (d.hasSeasonsData) {
      return d.seasons![_selectedSeason].episodes;
    }
    return d.episodes;
  }

  @override
  Widget build(BuildContext context) {
    final hasSeas = d.hasSeasonsData;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _CoverAppBar(title: d.title, cover: d.cover, type: d.type),
          SliverToBoxAdapter(child: _InfoSection(detail: d)),

          // Selector de temporada
          if (hasSeas)
            SliverToBoxAdapter(
              child: _SeasonSelector(
                seasons: d.seasons!.map((s) => s.title).toList(),
                selected: _selectedSeason,
                onSelected: (i) => setState(() => _selectedSeason = i),
              ),
            ),

          // Cabecera de episodios
          if (_currentEpisodes.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  _episodeLabel(d.type, _currentEpisodes.length),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // Lista de episodios
          if (_currentEpisodes.isNotEmpty)
            SliverList.separated(
              itemCount: _currentEpisodes.length,
              separatorBuilder: (ctx, i) =>
                  const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) => _EpisodeTile(
                episode: _currentEpisodes[i],
                number: _currentEpisodes.length - i,
                package: d.package,
                type: d.type,
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  String _episodeLabel(ExtensionType type, int count) {
    final word = switch (type) {
      ExtensionType.manga ||
      ExtensionType.comic ||
      ExtensionType.novel => 'Capítulos',
      ExtensionType.live  => 'Canales',
      ExtensionType.music => 'Tracks',
      ExtensionType.video => 'Vídeos',
      _                   => 'Episodios',
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
        background: Stack(
          fit: StackFit.expand,
          children: [
            cover != null && cover!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: cover!,
                    fit: BoxFit.cover,
                    errorWidget: (ctx, url, err) => _bg(cs),
                  )
                : _bg(cs),
            // Gradiente inferior para legibilidad del título
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bg(ColorScheme cs) => Container(
    color: cs.surfaceContainerHighest,
    child: Center(
      child: Icon(
        mediaTypeIcon(type),
        size: 72,
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila: año · rating · status
          _MetaRow(detail: detail),
          const SizedBox(height: 12),

          // Géneros
          if (detail.genres != null && detail.genres!.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: detail.genres!
                  .map(
                    (g) => Chip(
                      label: Text(g, style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Descripción
          if (detail.description != null && detail.description!.isNotEmpty) ...[
            _ExpandableText(text: detail.description!, cs: cs),
            const SizedBox(height: 12),
          ],

          // Extra key-value
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.detail});
  final MediaDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <Widget>[];

    if (detail.year != null) {
      items.add(_MetaPill(
        icon: Icons.calendar_today_outlined,
        label: '${detail.year}',
        cs: cs,
      ));
    }

    if (detail.rating != null) {
      items.add(_MetaPill(
        icon: Icons.star_rounded,
        label: detail.rating!.toStringAsFixed(1),
        color: const Color(0xFFFBBF24),
        cs: cs,
      ));
    }

    if (detail.status != null) {
      final (label, color) = _statusData(detail.status!);
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items,
    );
  }

  static (String, Color) _statusData(String s) => switch (s) {
    'ongoing'   => ('En emisión', const Color(0xFF16A34A)),
    'completed' => ('Completado', const Color(0xFF2563EB)),
    'upcoming'  => ('Próximamente', const Color(0xFF9333EA)),
    'hiatus'    => ('En pausa', const Color(0xFFD97706)),
    _           => (s, const Color(0xFF6B7280)),
  };
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.cs,
    this.color,
  });
  final IconData icon;
  final String label;
  final ColorScheme cs;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c,
          ),
        ),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text, required this.cs});
  final String text;
  final ColorScheme cs;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 4,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(color: widget.cs.onSurfaceVariant, height: 1.5),
        ),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded ? 'Menos' : 'Más',
            style: TextStyle(
              color: widget.cs.primary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Selector de temporadas
// ---------------------------------------------------------------------------

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.seasons,
    required this.selected,
    required this.onSelected,
  });
  final List<String> seasons;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: seasons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => FilterChip(
          label: Text(seasons[i]),
          selected: i == selected,
          onSelected: (_) => onSelected(i),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de episodio
// ---------------------------------------------------------------------------

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.number,
    required this.package,
    required this.type,
  });
  final MediaEpisode episode;
  final int number;
  final String package;
  final ExtensionType type;

  static bool _isPlayerType(ExtensionType t) => switch (t) {
    ExtensionType.manga ||
    ExtensionType.comic ||
    ExtensionType.novel => false,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isVideo = _isPlayerType(type);

    return ListTile(
      leading: episode.thumbnail != null && episode.thumbnail!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: episode.thumbnail!,
                width: 56,
                height: 40,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _numberAvatar(cs),
              ),
            )
          : _numberAvatar(cs),
      title: Text(
        episode.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (episode.airDate != null)
            Text(
              episode.airDate!,
              style: const TextStyle(fontSize: 11),
            ),
          if (episode.duration != null) ...[
            if (episode.airDate != null)
              const Text(' · ', style: TextStyle(fontSize: 11)),
            Text(
              _formatDuration(episode.duration!),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ],
      ),
      trailing: Icon(mediaTypeIcon(type)),
      onTap: () {
        final args = WatchArgs(
          episodeUrl: episode.url,
          package: package,
          title: episode.title,
          type: type,
        );
        context.push(isVideo ? AppRoutes.player : AppRoutes.reader, extra: args);
      },
    );
  }

  Widget _numberAvatar(ColorScheme cs) => CircleAvatar(
    backgroundColor: cs.primaryContainer,
    child: Text(
      '$number',
      style: TextStyle(
        fontSize: 12,
        color: cs.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m >= 60) {
      return '${m ~/ 60}h ${m % 60}m';
    }
    return '${m}m${s > 0 ? ' ${s}s' : ''}';
  }
}

// ---------------------------------------------------------------------------
// Estados
// ---------------------------------------------------------------------------

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({this.preview});
  final MediaItem? preview;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(preview?.title ?? '')),
    body: const Center(child: CircularProgressIndicator()),
  );
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
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
