// SplashPage — route-level wrapper around `SplashScreen`. The leaf
// widget knows nothing about routing; this wrapper hands it an
// `onComplete` callback that navigates to the Course tab. The
// router-level `redirect` callback in `app_router.dart` then
// forwards first-run users on to `/onboarding` automatically, so
// we don't need to duplicate that gating logic here.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import 'splash_screen.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SplashScreen(
      onComplete: () {
        if (!context.mounted) return;
        context.go(AppRoutes.course);
      },
    );
  }
}
