import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/media_item.dart';
import '../../data/services/extension/extension_service.dart';
import '../../shared/widgets/content_card.dart';
import 'home_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(HomeController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('PrismHub'),
        actions: [
          Obx(
            () => IconButton(
              icon: c.isLoading.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: c.isLoading.value ? null : c.loadLatest,
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value && c.sections.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!ExtensionService.hasAny) {
          return _EmptyHome();
        }

        if (c.sections.isEmpty) {
          return _EmptyContent();
        }

        return RefreshIndicator(
          onRefresh: c.loadLatest,
          child: ListView.builder(
            itemCount: c.sections.length,
            itemBuilder: (_, i) => _SectionRow(section: c.sections[i]),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila de sección (una extensión = una fila horizontal)
// ---------------------------------------------------------------------------

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.extensionName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.hPadding(context),
            ),
            itemCount: section.items.length,
            separatorBuilder: (ctx, i) =>
                SizedBox(width: Responsive.gap(context)),
            itemBuilder: (ctx, i) => ContentCard(
              item: section.items[i],
              width: Responsive.cardWidth(ctx),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Estados vacíos
// ---------------------------------------------------------------------------

class _EmptyHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_off_outlined, size: 72, color: cs.outline),
            const SizedBox(height: 16),
            const Text(
              'Sin extensiones instaladas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Instala extensiones para ver contenido',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.extension),
              label: const Text('Ir a Extensiones'),
              onPressed: () => context.go(AppRoutes.extensions),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text('Las extensiones no devolvieron contenido'),
        ],
      ),
    );
  }
}
