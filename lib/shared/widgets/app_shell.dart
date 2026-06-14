import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    (icon: Icons.home_outlined, label: 'Inicio', route: AppRoutes.home),
    (icon: Icons.search, label: 'Buscar', route: AppRoutes.search),
    (icon: Icons.extension_outlined, label: 'Extensiones', route: AppRoutes.extensions),
    (icon: Icons.settings_outlined, label: 'Ajustes', route: AppRoutes.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _destinations.indexWhere(
        (d) => d.route == location);

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 720;

      if (isWide) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                onDestinationSelected: (i) =>
                    context.go(_destinations[i].route),
                labelType: NavigationRailLabelType.all,
                destinations: _destinations
                    .map((d) => NavigationRailDestination(
                          icon: Icon(d.icon),
                          label: Text(d.label),
                        ))
                    .toList(),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: child),
            ],
          ),
        );
      }

      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onDestinationSelected: (i) => context.go(_destinations[i].route),
          destinations: _destinations
              .map((d) => NavigationDestination(
                    icon: Icon(d.icon),
                    label: d.label,
                  ))
              .toList(),
        ),
      );
    });
  }
}
