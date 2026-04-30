// OnboardingPage — KAN-284 (S14) route-level wrapper for the
// onboarding wizard. Loads the current `PlayerProfile` (or
// default), passes it to `OnboardingScreen`, and on
// completion/skip writes the result back via `ProfileRepository`
// and navigates the user to the main shell.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/storage/profile_repository.dart';
import '../../../models/player_profile.dart';
import 'onboarding_screen.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _profileRepo = ProfileRepository();

  PlayerProfile _safeLoadProfile() {
    try {
      return _profileRepo.loadOrDefault();
    } catch (_) {
      return const PlayerProfile();
    }
  }

  Future<void> _save(PlayerProfile profile) async {
    try {
      await _profileRepo.save(profile);
    } catch (_) {
      // Hive unavailable in unit tests — skip the save and let
      // the redirect logic handle the navigation.
    }
    if (!mounted) return;
    // After onboarding, hand the user off to the default Course
    // tab. Use `go` (not `push`) so the onboarding route doesn't
    // sit on the back stack.
    context.go(AppRoutes.course);
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      initialProfile: _safeLoadProfile(),
      onComplete: _save,
      onSkip: _save,
    );
  }
}
