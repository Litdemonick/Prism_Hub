import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Chips de género sacados de la biblioteca real del usuario (favoritos +
// historial de lectura, vía la caché local de detalle) — no hay catálogo de
// géneros unificado entre extensiones, así que esto filtra TU biblioteca en
// vez de buscar en las extensiones. Ver HomePageController.libraryGenres.
class HomeLibraryGenreChips extends StatelessWidget {
  const HomeLibraryGenreChips({
    super.key,
    required this.controller,
  });
  final HomePageController controller;

  void _openGenre(BuildContext context, String genre) {
    final entries = controller.entriesForGenre(genre);
    if (Platform.isAndroid) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: HomeTheme.bg,
        builder: (context) => _GenreResultsSheet(genre: genre, entries: entries),
      );
      return;
    }
    fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: Text(genre),
        content: SizedBox(
          width: 600,
          height: 300,
          child: _GenreResultsGrid(entries: entries),
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
    if (controller.libraryGenres.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'home.genres'.i18n,
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
            children: controller.libraryGenres.map((genre) {
              return _GenreChip(
                label: genre,
                onTap: () => _openGenre(context, genre),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _GenreChip extends StatefulWidget {
  const _GenreChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_GenreChip> createState() => _GenreChipState();
}

class _GenreChipState extends State<_GenreChip> {
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

class _GenreResultsSheet extends StatelessWidget {
  const _GenreResultsSheet({required this.genre, required this.entries});
  final String genre;
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
              genre,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: HomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: _GenreResultsGrid(entries: entries),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreResultsGrid extends StatelessWidget {
  const _GenreResultsGrid({required this.entries});
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
