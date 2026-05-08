// Top-level MaterialApp.router. Routes are defined in
// `core/routing/app_router.dart`; theme construction in
// `core/theme/caddie_theme_builder.dart`.
//
// The theme is driven by the global [themeController] (a
// ValueNotifier<ThemePalette>). The dev-only Theme Playground
// screen writes to it; this builder listens and rebuilds the whole
// MaterialApp when the palette changes. Production builds ignore
// that screen but still honor any palette the user previously
// selected in a dev build (persisted to Hive).
//
// KAN-382: CaddieApp is also the lifecycle hook that re-hydrates
// the active round from Hive when the app returns to foreground.
// Cold-start hydration runs in main() before runApp; this handles
// the "user backgrounded the app between holes" case where main()
// doesn't re-run.

import 'package:flutter/material.dart';

import 'core/round/active_round_controller.dart';
import 'core/routing/app_router.dart';
import 'core/theme/caddie_theme_builder.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/theme_palette.dart';

class CaddieApp extends StatefulWidget {
  const CaddieApp({super.key});

  @override
  State<CaddieApp> createState() => _CaddieAppState();
}

class _CaddieAppState extends State<CaddieApp> with WidgetsBindingObserver {
  // The router instance is built once per CaddieApp lifetime. If the
  // app is hot-restarted (not just hot-reloaded), a new instance is
  // created. Don't make it static — that breaks state preservation
  // across hot restart and complicates the test setup.
  final _router = buildAppRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read Hive on resume so the active-round in-memory state
    // matches what's persisted. This catches edge cases where Hive
    // was mutated in a non-main isolate (e.g. future background
    // location task) while the app was backgrounded.
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget — failures are swallowed inside hydrate()
      // (it returns null on a corrupt/missing record without
      // throwing). Trigger label distinguishes this from cold-
      // start hydrate in CloudWatch's `round_restore` events.
      activeRoundController.hydrate(trigger: 'foreground');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemePalette>(
      valueListenable: themeController,
      builder: (context, palette, _) {
        return MaterialApp.router(
          title: 'CaddieAI',
          debugShowCheckedModeBanner: false,
          theme: buildCaddieTheme(palette),
          routerConfig: _router,
        );
      },
    );
  }
}
