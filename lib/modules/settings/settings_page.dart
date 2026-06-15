import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/config/app_config.dart';
import 'settings_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(SettingsController());
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          // ── Apariencia ──────────────────────────────────────────────────
          _SectionHeader('Apariencia'),
          Obx(
            () => Column(
              children: [
                _ThemeTile(
                  title: 'Sistema',
                  subtitle: 'Sigue el tema del dispositivo',
                  icon: Icons.brightness_auto_outlined,
                  selected: c.themeMode.value == ThemeMode.system,
                  onTap: () => c.setTheme(ThemeMode.system),
                ),
                _ThemeTile(
                  title: 'Claro',
                  subtitle: 'Tema claro siempre',
                  icon: Icons.light_mode_outlined,
                  selected: c.themeMode.value == ThemeMode.light,
                  onTap: () => c.setTheme(ThemeMode.light),
                ),
                _ThemeTile(
                  title: 'Oscuro',
                  subtitle: 'Tema oscuro siempre',
                  icon: Icons.dark_mode_outlined,
                  selected: c.themeMode.value == ThemeMode.dark,
                  onTap: () => c.setTheme(ThemeMode.dark),
                ),
              ],
            ),
          ),

          const Divider(height: 32),

          // ── Motor de extensiones ─────────────────────────────────────────
          _SectionHeader('Motor de extensiones'),
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: const Text('Prism+'),
            subtitle: const Text('Repositorio oficial integrado'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF6D28D9).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6D28D9).withValues(alpha: 0.4),
                ),
              ),
              child: const Text(
                'Built-in',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6D28D9),
                ),
              ),
            ),
          ),

          const Divider(height: 32),

          // ── Acerca de ──────────────────────────────────────────────────
          _SectionHeader('Acerca de'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Image.asset(
                  'assets/logo_prismhub.png',
                  height: 72,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.apps_rounded,
                    size: 72,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppConfig.appName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'v${AppConfig.version}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'por Litdemonick',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('Código fuente'),
            subtitle: const Text('github.com/Litdemonick/Prism_Hub'),
            trailing: const Icon(Icons.open_in_new, size: 16),
          ),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Prism+ SDK'),
            subtitle: const Text('github.com/Litdemonick/prism-plus'),
            trailing: const Icon(Icons.open_in_new, size: 16),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? cs.primary : null,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: cs.primary)
          : const Icon(Icons.circle_outlined),
      onTap: onTap,
    );
  }
}
