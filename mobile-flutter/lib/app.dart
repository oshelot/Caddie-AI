// Top-level MaterialApp.router. Routes are defined in
// `core/routing/app_router.dart`; theme in `core/theme/caddie_theme.dart`.
//
// The KAN-291 (S0) icon smoke test is no longer present here — the
// bottom navigation in the MainShell now exercises 4 CaddieIcons
// (golfer / course / history / profile) on every cold start, which is
// the same runtime confirmation the smoke test provided.

import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';
import 'core/theme/caddie_theme.dart';

class CaddieApp extends StatelessWidget {
  CaddieApp({super.key});

  // The router instance is built once per CaddieApp lifetime. If the
  // app is hot-restarted (not just hot-reloaded), a new instance is
  // created. Don't make it static — that breaks state preservation
  // across hot restart and complicates the test setup.
  final _router = buildAppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CaddieAI',
      debugShowCheckedModeBanner: false,
      theme: CaddieTheme.light,
      routerConfig: _router,
    );
  }
}
