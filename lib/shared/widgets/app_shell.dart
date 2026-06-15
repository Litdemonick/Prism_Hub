import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/utils/responsive.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    (
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Inicio',
      route: AppRoutes.home,
    ),
    (
      icon: Icons.search_outlined,
      activeIcon: Icons.search_rounded,
      label: 'Buscar',
      route: AppRoutes.search,
    ),
    (
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Ajustes',
      route: AppRoutes.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _destinations.indexWhere((d) => d.route == location);
    final selected = idx < 0 ? 0 : idx;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!Responsive.isMobile(context)) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: (i) =>
                      context.go(_destinations[i].route),
                  labelType: NavigationRailLabelType.all,
                  destinations: _destinations
                      .map(
                        (d) => NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.activeIcon),
                          label: Text(d.label),
                        ),
                      )
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
            selectedIndex: selected,
            onDestinationSelected: (i) => context.go(_destinations[i].route),
            destinations: _destinations
                .map(
                  (d) => NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.activeIcon),
                    label: d.label,
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
