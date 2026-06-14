import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/utils/responsive.dart';
import '../../data/services/extension/extension_service.dart';
import '../../shared/widgets/content_card.dart';
import 'search_controller.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final ContentSearchController _c;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c = Get.put(ContentSearchController());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _textController,
          autofocus: false,
          decoration: const InputDecoration(
            hintText: 'Buscar anime, manga, comic...',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: _c.search,
        ),
        actions: [
          Obx(
            () => _textController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _textController.clear();
                      _c.search('');
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          _ExtensionFilter(c: _c),
          Expanded(child: _Body(c: _c)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chips para filtrar por extensión
// ---------------------------------------------------------------------------

class _ExtensionFilter extends StatelessWidget {
  const _ExtensionFilter({required this.c});
  final ContentSearchController c;

  @override
  Widget build(BuildContext context) {
    final runtimes = ExtensionService.allLoaded;
    if (runtimes.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: Obx(
        () => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: const Text('Todas'),
                selected: c.selectedPackage.value == null,
                onSelected: (_) => c.selectExtension(null),
              ),
            ),
            ...runtimes.map(
              (rt) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(rt.extension.name),
                  selected: c.selectedPackage.value == rt.extension.package,
                  onSelected: (_) => c.selectExtension(rt.extension.package),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cuerpo con estados
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.c});
  final ContentSearchController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isSearching.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (c.lastQuery.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              const Text('Escribe algo para buscar'),
            ],
          ),
        );
      }

      if (c.results.isEmpty) {
        return Center(
          child: Text('Sin resultados para "${c.lastQuery.value}"'),
        );
      }

      return Builder(
        builder: (context) {
          final cols = Responsive.gridColumns(context);
          final gap = Responsive.gap(context);
          final hp = Responsive.hPadding(context);
          return GridView.builder(
            padding: EdgeInsets.symmetric(horizontal: hp, vertical: 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 0.55,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
            ),
            itemCount: c.results.length,
            itemBuilder: (_, i) => ContentCard(item: c.results[i]),
          );
        },
      );
    });
  }
}
