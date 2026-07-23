import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// "Categorías" — mismas etiquetas fijas del diseño (Acción, Romance,
// Fantasía, Terror, Comedia, Deportes, Drama), siempre visibles. Al tocar
// una, filtra contenido real: coincidencia contra los géneros reales
// cacheados de tu biblioteca (HomePageController.entriesForCategory) — no
// hay catálogo de géneros unificado entre extensiones para buscar en vivo,
// así que esto filtra lo que ya tenés, igual que los chips de Géneros.
class HomeCategoryChips extends StatelessWidget {
  const HomeCategoryChips({
    super.key,
    required this.controller,
  });
  final HomePageController controller;

  void _openCategory(BuildContext context, String category) {
    final entries = controller.entriesForCategory(category);
    if (Platform.isAndroid) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: HomeTheme.bg,
        builder: (context) =>
            _CategoryResultsSheet(category: category, entries: entries),
      );
      return;
    }
    fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: Text(category),
        content: SizedBox(
          width: 600,
          height: 300,
          child: _CategoryResultsGrid(entries: entries),
        ),
        actions: [
          fluent.Button(
            child: Text('common.close'.i18n),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'home.categories'.i18n,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: HomeTheme.textPrimary,
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: HomePageController.fixedCategories.map((category) {
              return _CategoryChip(
                label: category,
                onTap: () => _openCategory(context, category),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatefulWidget {
  const _CategoryChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hover ? HomeTheme.accentPink : HomeTheme.border,
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: HomeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryResultsSheet extends StatelessWidget {
  const _CategoryResultsSheet({required this.category, required this.entries});
  final String category;
  final List<LibraryGenreEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: HomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: _CategoryResultsGrid(entries: entries),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryResultsGrid extends StatelessWidget {
  const _CategoryResultsGrid({required this.entries});
  final List<LibraryGenreEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'home.genre-empty'.i18n,
          style: const TextStyle(color: HomeTheme.textMuted),
        ),
      );
    }
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: HomeMediaCard(
            title: e.title,
            cover: e.cover,
          ),
        );
      },
    );
  }
}
