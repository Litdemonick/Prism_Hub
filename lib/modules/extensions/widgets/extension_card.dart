import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../data/models/extension_dto.dart';
import '../../../data/models/extension_model.dart';
import 'extension_type_badge.dart';

/// Tarjeta de extensión disponible en un repo.
/// [onInstall] / [onUpdate] / [onUninstall] pueden ser null según el estado.
class ExtensionCard extends StatelessWidget {
  const ExtensionCard({
    super.key,
    required this.name,
    required this.package,
    required this.version,
    required this.author,
    required this.type,
    this.iconUrl,
    required this.isBusy,
    this.onInstall,
    this.onUpdate,
    this.onUninstall,
  });

  final String name;
  final String package;
  final String version;
  final String author;
  final ExtensionType type;
  final String? iconUrl;
  final bool isBusy;
  final VoidCallback? onInstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onUninstall;

  factory ExtensionCard.fromDto(
    ExtensionDto dto, {
    required bool isBusy,
    VoidCallback? onInstall,
    VoidCallback? onUpdate,
    VoidCallback? onUninstall,
  }) => ExtensionCard(
    name: dto.name,
    package: dto.package,
    version: dto.version,
    author: dto.author,
    type: dto.type,
    iconUrl: dto.iconUrl,
    isBusy: isBusy,
    onInstall: onInstall,
    onUpdate: onUpdate,
    onUninstall: onUninstall,
  );

  factory ExtensionCard.fromModel(
    ExtensionModel model, {
    required bool isBusy,
    VoidCallback? onUninstall,
    VoidCallback? onUpdate,
  }) => ExtensionCard(
    name: model.name,
    package: model.package,
    version: model.version,
    author: model.author,
    type: model.type,
    iconUrl: model.iconUrl,
    isBusy: isBusy,
    onUninstall: onUninstall,
    onUpdate: onUpdate,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _Icon(iconUrl: iconUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ExtensionTypeBadge(type),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v$version  •  $author',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  Text(
                    package,
                    style: TextStyle(fontSize: 11, color: cs.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              isBusy: isBusy,
              onInstall: onInstall,
              onUpdate: onUpdate,
              onUninstall: onUninstall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({this.iconUrl});
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (iconUrl != null && iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: iconUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorWidget: (ctx, url, err) => _placeholder(cs),
        ),
      );
    }
    return _placeholder(cs);
  }

  Widget _placeholder(ColorScheme cs) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.extension, color: cs.primary),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.isBusy,
    this.onInstall,
    this.onUpdate,
    this.onUninstall,
  });

  final bool isBusy;
  final VoidCallback? onInstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // Estado: tiene actualización disponible
    if (onUpdate != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            icon: const Icon(Icons.update, size: 20),
            tooltip: 'Actualizar',
            onPressed: onUpdate,
          ),
          if (onUninstall != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Desinstalar',
              onPressed: onUninstall,
              color: Theme.of(context).colorScheme.error,
            ),
        ],
      );
    }

    // Estado: instalada
    if (onUninstall != null) {
      return IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Desinstalar',
        onPressed: onUninstall,
        color: Theme.of(context).colorScheme.error,
      );
    }

    // Estado: no instalada
    if (onInstall != null) {
      return IconButton.filled(
        icon: const Icon(Icons.download),
        tooltip: 'Instalar',
        onPressed: onInstall,
      );
    }

    return const SizedBox.shrink();
  }
}
