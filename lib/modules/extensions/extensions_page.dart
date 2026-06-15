import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'extensions_controller.dart';
import 'widgets/extension_card.dart';

class ExtensionsPage extends StatelessWidget {
  const ExtensionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Registra el controller si no existe
    final c = Get.put(ExtensionsController());

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Extensiones'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.download_done), text: 'Instaladas'),
              Tab(icon: Icon(Icons.explore), text: 'Explorar'),
            ],
          ),
          actions: [
            // Botón añadir repo
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: 'Añadir repositorio',
              onPressed: () => _showAddRepoDialog(context, c),
            ),
            // Botón refrescar repos
            Obx(
              () => IconButton(
                icon: c.isLoadingAvailable.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Actualizar repositorios',
                onPressed: c.isLoadingAvailable.value ? null : c.fetchAvailable,
              ),
            ),
          ],
        ),
        body: TabBarView(children: [_InstalledTab(c), _ExploreTab(c)]),
      ),
    );
  }

  void _showAddRepoDialog(BuildContext context, ExtensionsController c) {
    final controller = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('Añadir repositorio'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://raw.githubusercontent.com/.../index.json',
            labelText: 'URL del repositorio',
          ),
          autofocus: true,
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              c.addRepo(controller.text);
              Get.back();
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Instaladas
// ---------------------------------------------------------------------------

class _InstalledTab extends StatelessWidget {
  const _InstalledTab(this.c);
  final ExtensionsController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isLoadingInstalled.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (c.installed.isEmpty) {
        return const _EmptyState(
          icon: Icons.extension_off,
          message: 'Sin extensiones instaladas',
          hint: 'Ve a "Explorar" para instalar desde un repositorio.',
        );
      }

      return RefreshIndicator(
        onRefresh: c.fetchAvailable,
        child: ListView.builder(
          itemCount: c.installed.length,
          itemBuilder: (context, i) {
            final ext = c.installed[i];

            // Busca si hay una versión más nueva en los repos
            final dtoInRepo = c.available.firstWhereOrNull(
              (d) => d.package == ext.package,
            );
            final updateAvailable =
                dtoInRepo != null && dtoInRepo.version != ext.version;

            return Obx(
              () => ExtensionCard.fromModel(
                ext,
                isBusy: c.isBusy(ext.package),
                onUpdate: updateAvailable
                    ? () => c.updateExtension(dtoInRepo)
                    : null,
                onUninstall: () => _confirmUninstall(context, c, ext),
              ),
            );
          },
        ),
      );
    });
  }

  void _confirmUninstall(
    BuildContext context,
    ExtensionsController c,
    dynamic ext,
  ) {
    Get.dialog(
      AlertDialog(
        title: const Text('Desinstalar extensión'),
        content: Text('¿Desinstalar "${ext.name}"?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Get.back();
              c.uninstall(ext);
            },
            child: const Text('Desinstalar'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Explorar (repos remotos)
// ---------------------------------------------------------------------------

class _ExploreTab extends StatelessWidget {
  const _ExploreTab(this.c);
  final ExtensionsController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.repos.isEmpty) {
        return const _EmptyState(
          icon: Icons.cloud_off,
          message: 'Sin repositorios',
          hint: 'El repositorio de Prism+ debería cargarse automáticamente.',
        );
      }

      if (c.isLoadingAvailable.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (c.available.isEmpty) {
        return const _EmptyState(
          icon: Icons.search_off,
          message: 'Repositorios vacíos',
          hint: 'Los repositorios no contienen extensiones todavía.',
        );
      }

      return Column(
        children: [
          // Lista de repos con opción de borrar
          _RepoChips(c),
          const Divider(height: 1),
          // Lista de extensiones disponibles
          Expanded(
            child: ListView.builder(
              itemCount: c.available.length,
              itemBuilder: (context, i) {
                final dto = c.available[i];
                final installed = c.isInstalled(dto.package);
                final updateAvail = c.hasUpdate(dto);

                return Obx(
                  () => ExtensionCard.fromDto(
                    dto,
                    isBusy: c.isBusy(dto.package),
                    onInstall: installed ? null : () => c.install(dto),
                    onUpdate: updateAvail ? () => c.updateExtension(dto) : null,
                    onUninstall: installed
                        ? () {
                            final model = c.installedModel(dto.package);
                            if (model != null) c.uninstall(model);
                          }
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _RepoChips extends StatelessWidget {
  const _RepoChips(this.c);
  final ExtensionsController c;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: c.repos.length,
        separatorBuilder: (ctx, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final url = c.repos[i];
          final host = Uri.tryParse(url)?.host ?? url;
          final builtIn = c.isBuiltIn(url);
          return Tooltip(
            message: builtIn ? 'Motor integrado — no se puede eliminar' : url,
            child: Chip(
              avatar: builtIn
                  ? const Icon(Icons.lock_outline, size: 14)
                  : null,
              label: Text(host, style: const TextStyle(fontSize: 12)),
              deleteIcon: builtIn ? null : const Icon(Icons.close, size: 16),
              onDeleted: builtIn ? null : () => c.removeRepo(url),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state genérico
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.hint,
  });

  final IconData icon;
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
