import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/media_item.dart';
import '../../shared/widgets/content_card.dart';
import '../../shared/widgets/shimmer_box.dart';
import '../../shared/widgets/type_icon.dart';
import '../detail/detail_page.dart';
import 'home_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(HomeController());

    return Scaffold(
      body: Obx(() {
        if (c.isLoading.value) return const _HomeLoading();

        if (c.noConnection.value) {
          return _NoConnectionView(onRetry: c.loadLatest);
        }

        if (c.sections.isEmpty) {
          return _EmptyView(onRetry: c.loadLatest);
        }

        return RefreshIndicator(
          onRefresh: c.loadLatest,
          child: CustomScrollView(
            slivers: [
              _PrismAppBar(onRefresh: c.loadLatest),
              SliverToBoxAdapter(
                child: _HeroBanner(item: c.sections.first.items.first),
              ),
              for (final section in c.sections)
                SliverToBoxAdapter(child: _SectionRow(section: section)),
              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// AppBar flotante
// ---------------------------------------------------------------------------

class _PrismAppBar extends StatelessWidget {
  const _PrismAppBar({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      title: Row(
        children: [
          Image.asset(
            'assets/logo_prismhub.png',
            height: 26,
            errorBuilder: (_, _, _) => Icon(
              Icons.play_circle_fill_rounded,
              size: 26,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'PrismHub',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Actualizar',
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero Banner
// ---------------------------------------------------------------------------

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hp = Responsive.hPadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 16, hp, 4),
      child: GestureDetector(
        onTap: () => context.push(
          AppRoutes.detail,
          extra: DetailArgs(url: item.url, package: item.package, item: item),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 230,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Portada
                item.cover != null && item.cover!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.cover!,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 400),
                        errorWidget: (_, _, _) => _bgFallback(cs),
                      )
                    : _bgFallback(cs),

                // Gradiente
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: [0.0, 0.55, 1.0],
                      colors: [
                        Color(0xEE000000),
                        Color(0x77000000),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // Info
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MediaTypeChip(item.type),
                            const SizedBox(height: 8),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                shadows: [
                                  Shadow(blurRadius: 12, color: Colors.black87),
                                ],
                              ),
                            ),
                            if (item.year != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${item.year}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Ver'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () => context.push(
                          AppRoutes.detail,
                          extra: DetailArgs(
                            url: item.url,
                            package: item.package,
                            item: item,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Rating badge
                if (item.rating != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFBBF24),
                            size: 14,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bgFallback(ColorScheme cs) => Container(
    color: cs.surfaceContainerHighest,
    child: Center(
      child: Icon(Icons.movie_outlined, size: 64, color: cs.outline),
    ),
  );
}

// ---------------------------------------------------------------------------
// Fila de sección horizontal
// ---------------------------------------------------------------------------

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final hp = Responsive.hPadding(context);
    final gap = Responsive.gap(context);
    final cardWidth = Responsive.cardWidth(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hp, 24, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.extensionName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.search),
                child: const Text('Ver más'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: hp),
            itemCount: section.items.length,
            separatorBuilder: (_, _) => SizedBox(width: gap),
            itemBuilder: (_, i) =>
                ContentCard(item: section.items[i], width: cardWidth),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Estado de carga — shimmer
// ---------------------------------------------------------------------------

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    final hp = Responsive.hPadding(context);
    final gap = Responsive.gap(context);
    final cardWidth = Responsive.cardWidth(context);

    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        const SliverAppBar(
          floating: true,
          title: Text(
            'PrismHub',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 16, hp, 4),
            child: ShimmerBox(height: 230, borderRadius: 16),
          ),
        ),
        for (var i = 0; i < 2; i++) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 24, hp, 8),
              child: ShimmerBox(width: 170, height: 18, borderRadius: 6),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: hp),
                itemCount: 6,
                separatorBuilder: (_, _) => SizedBox(width: gap),
                itemBuilder: (_, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: cardWidth, height: 163),
                    const SizedBox(height: 6),
                    ShimmerBox(
                      width: cardWidth * 0.8,
                      height: 11,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 4),
                    ShimmerBox(
                      width: cardWidth * 0.55,
                      height: 9,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Estados de error
// ---------------------------------------------------------------------------

class _NoConnectionView extends StatelessWidget {
  const _NoConnectionView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 72, color: cs.outline),
            const SizedBox(height: 20),
            const Text(
              'Sin conexión con Prism+',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Verifica tu conexión a internet e intenta de nuevo.',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          const Text(
            'No hay contenido disponible',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Actualizar'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
