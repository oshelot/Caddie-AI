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

import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';
import 'core/theme/caddie_theme_builder.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/theme_palette.dart';

class CaddieApp extends StatelessWidget {
  CaddieApp({super.key});

  // The router instance is built once per CaddieApp lifetime. If the
  // app is hot-restarted (not just hot-reloaded), a new instance is
  // created. Don't make it static — that breaks state preservation
  // across hot restart and complicates the test setup.
  final _router = buildAppRouter();

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
