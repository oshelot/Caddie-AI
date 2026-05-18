// Main app shell with the 4-tab Material 3 bottom navigation. Wraps a
// `StatefulNavigationShell` from go_router so each tab has its own
// independent Navigator stack and state preservation across switches.
//
// Tab order, labels, and icons follow the canonical naming spec from
// **KAN-157** (closed Won't Do — spec preserved as authoritative
// reference): Caddie → Course → History → Profile, with **Course**
// as the default landing tab.
//
// KAN-434 (UI redesign Phase 1): the bottom navigation is hidden
// while the user is on the active-round map route, so the map runs
// immersive (full vertical real estate). The shell listens to the
// router delegate so it re-evaluates visibility on sub-route
// navigation within a branch — not just on tab switches.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/caddie_icons.dart';
import '../core/logging/log_event.dart';
import '../core/routing/app_router.dart';
import '../main.dart' show logger;

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  /// Provided by go_router's `StatefulShellRoute.indexedStack` builder.
  final StatefulNavigationShell navigationShell;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _tabNames = ['Caddie', 'Course', 'History', 'Profile'];

  int _tabEnteredAt = DateTime.now().millisecondsSinceEpoch;

  /// The router this shell listens to. Tracked so the listener can be
  /// detached in [dispose] and re-attached if it ever changes.
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_onRouteChanged);
      _router = router..routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  /// Rebuild on any route change — including navigation *within* a
  /// branch (e.g. /course → /course/map), which doesn't change the
  /// shell's `currentIndex` and so wouldn't otherwise rebuild us.
  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  /// True while on the active-round map route. The bottom nav is
  /// hidden here so the map can run full-height (immersive mode).
  bool get _isImmersiveRoute {
    final location =
        _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    return location == AppRoutes.courseMap;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: _isImmersiveRoute
          ? null
          : NavigationBar(
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
              destinations: [
                NavigationDestination(
                  icon: CaddieIcons.golfer(
                      size: 24, color: colors.onSurfaceVariant),
                  selectedIcon:
                      CaddieIcons.golfer(size: 24, color: colors.primary),
                  label: 'Caddie',
                ),
                NavigationDestination(
                  icon: CaddieIcons.course(
                      size: 24, color: colors.onSurfaceVariant),
                  selectedIcon:
                      CaddieIcons.course(size: 24, color: colors.primary),
                  label: 'Course',
                ),
                NavigationDestination(
                  icon: CaddieIcons.history(
                      size: 24, color: colors.onSurfaceVariant),
                  selectedIcon:
                      CaddieIcons.history(size: 24, color: colors.primary),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: CaddieIcons.profile(
                      size: 24, color: colors.onSurfaceVariant),
                  selectedIcon:
                      CaddieIcons.profile(size: 24, color: colors.primary),
                  label: 'Profile',
                ),
              ],
            ),
    );
  }

  void _onDestinationSelected(int index) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dwellMs = now - _tabEnteredAt;
    final previousTab = widget.navigationShell.currentIndex;
    logger.info(LogCategory.general, 'tab_dwell', metadata: {
      'dwellMs': '$dwellMs',
      'tab': _tabNames[previousTab],
    });
    _tabEnteredAt = now;

    // `goBranch` swaps to the requested branch but preserves the
    // current branch's navigation stack — re-tapping the active tab
    // pops to the root of that branch (`initialLocation: true`).
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }
}
