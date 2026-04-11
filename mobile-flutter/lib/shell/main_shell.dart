// Main app shell with the 4-tab Material 3 bottom navigation. Wraps a
// `StatefulNavigationShell` from go_router so each tab has its own
// independent Navigator stack and state preservation across switches.
//
// Tab order, labels, and icons follow the canonical naming spec from
// **KAN-157** (closed Won't Do — spec preserved as authoritative
// reference): Caddie → Course → History → Profile, with **Course**
// as the default landing tab.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/caddie_icons.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  /// Provided by go_router's `StatefulShellRoute.indexedStack` builder.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          NavigationDestination(
            icon: CaddieIcons.golfer(size: 24, color: colors.onSurfaceVariant),
            selectedIcon: CaddieIcons.golfer(size: 24, color: colors.primary),
            label: 'Caddie',
          ),
          NavigationDestination(
            icon: CaddieIcons.course(size: 24, color: colors.onSurfaceVariant),
            selectedIcon: CaddieIcons.course(size: 24, color: colors.primary),
            label: 'Course',
          ),
          NavigationDestination(
            icon: CaddieIcons.history(size: 24, color: colors.onSurfaceVariant),
            selectedIcon: CaddieIcons.history(size: 24, color: colors.primary),
            label: 'History',
          ),
          NavigationDestination(
            icon: CaddieIcons.profile(size: 24, color: colors.onSurfaceVariant),
            selectedIcon: CaddieIcons.profile(size: 24, color: colors.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _onDestinationSelected(int index) {
    // `goBranch` swaps to the requested branch but preserves the
    // current branch's navigation stack — re-tapping the active tab
    // pops to the root of that branch (`initialLocation: true`).
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
