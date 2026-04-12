// OnboardingScreen — KAN-284 (S14). 6-step wizard the first-run
// user walks through before reaching the main shell. Steps:
//
//   1. Setup notice — "what CaddieAI is" + privacy nudge
//   2. Contact info — name, email, phone (all optional)
//   3. Handicap — slider (1.0 increments, 0–36)
//   4. Short-game preferences — chip style + wedge confidence
//   5. Bag confirmation — accept defaults or skip to edit later
//   6. Tee box preference — championship / blue / white / senior / forward
//
// **Architecture: pure widget with constructor injection.** The
// screen takes:
//   - `initialProfile`: starting `PlayerProfile` (typically the
//     storage default for first-run; the page wrapper loads it)
//   - `onComplete`: called with the finished profile when the
//     user taps "Finish" on the last step. The page wrapper
//     persists via `ProfileRepository.save` AND sets
//     `hasCompletedSwingOnboarding = true` AND
//     `hasConfiguredBag = true` so the first-run gate flips off.
//   - `onSkip`: called when the user taps "Skip for now" on any
//     step. The page wrapper persists whatever progress was made
//     and STILL flips the first-run flags so the user isn't
//     trapped in the wizard on every launch.
//
// **First-run detection** uses `PlayerProfile.hasCompletedSwingOnboarding`
// from S2 — single source of truth, no separate "has-onboarded"
// flag. The router-level redirect (in `app_router.dart`'s
// `redirect` callback) sends users with `false` to `/onboarding`
// on every navigation until they finish or skip.
//
// **Skip is non-destructive:** any data the user entered before
// skipping is still saved. The flags just flip so the redirect
// stops firing.

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../models/player_profile.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.initialProfile,
    required this.onComplete,
    required this.onSkip,
  });

  final PlayerProfile initialProfile;
  final Future<void> Function(PlayerProfile profile) onComplete;
  final Future<void> Function(PlayerProfile profile) onSkip;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PlayerProfile _draft = widget.initialProfile;
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialProfile.name);
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialProfile.email);
  late final TextEditingController _phoneController =
      TextEditingController(text: widget.initialProfile.phone);

  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _saving = false;

  static const int _totalSteps = 6;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep >= _totalSteps - 1) {
      _finish();
      return;
    }
    setState(() => _currentStep++);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_currentStep == 0) return;
    setState(() => _currentStep--);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final updated = _commitTextFields(_draft).copyWith(
      hasCompletedSwingOnboarding: true,
      hasConfiguredBag: true,
    );
    await widget.onComplete(updated);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _skip() async {
    setState(() => _saving = true);
    // Save whatever the user entered so far PLUS flip the
    // first-run flags so the redirect stops firing on next
    // launch. Per the AC: skip is non-destructive.
    final partial = _commitTextFields(_draft).copyWith(
      hasCompletedSwingOnboarding: true,
      hasConfiguredBag: true,
    );
    await widget.onSkip(partial);
    if (mounted) setState(() => _saving = false);
  }

  /// Pulls the live text-controller values into the draft. Called
  /// before any save so unsaved keystrokes aren't lost. The other
  /// fields (handicap, dropdowns) write directly into `_draft`
  /// via `setState` as the user adjusts them.
  PlayerProfile _commitTextFields(PlayerProfile profile) {
    return profile.copyWith(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome to CaddieAI (${_currentStep + 1}/$_totalSteps)'),
        leading: _currentStep == 0
            ? null
            : IconButton(
                key: const Key('onboarding-back-button'),
                icon: const Icon(Icons.arrow_back),
                onPressed: _saving ? null : _back,
              ),
        actions: [
          TextButton(
            key: const Key('onboarding-skip-button'),
            onPressed: _saving ? null : _skip,
            child: const Text('Skip for now'),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            minHeight: 4,
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentStep = i),
              children: [
                _setupNoticeStep(theme),
                _contactStep(theme),
                _handicapStep(theme),
                _shortGameStep(theme),
                _bagStep(theme),
                _teeBoxStep(theme),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('onboarding-next-button'),
                onPressed: _saving ? null : _next,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _currentStep == _totalSteps - 1 ? 'Finish' : 'Next',
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── steps ───────────────────────────────────────────────────────

  Widget _setupNoticeStep(ThemeData theme) {
    return _stepScroll([
      Center(
        child: CaddieIcons.golfer(
          size: 96,
          color: theme.colorScheme.primary,
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Your AI golf caddie',
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Text(
        'CaddieAI gives you live shot recommendations, hole-by-hole '
        "satellite maps, and an AI commentary that explains why each "
        'club + target makes sense for your game.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Text(
        "We'll set up your handicap, bag, and voice persona in the "
        'next few steps. You can skip any of them and come back '
        'later from the Profile tab.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
        textAlign: TextAlign.center,
      ),
    ]);
  }

  Widget _contactStep(ThemeData theme) {
    return _stepScroll([
      Text('Stay in touch (optional)', style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        "We'll only contact you about major updates. Skip if you'd "
        'rather not.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('onboarding-name-field'),
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('onboarding-email-field'),
        controller: _emailController,
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('onboarding-phone-field'),
        controller: _phoneController,
        decoration: const InputDecoration(
          labelText: 'Phone',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.phone,
      ),
    ]);
  }

  Widget _handicapStep(ThemeData theme) {
    return _stepScroll([
      Text('Your handicap', style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        "Drag the slider to your current handicap. We'll use this to "
        'tune the AI recommendations.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      const SizedBox(height: 32),
      Center(
        child: Text(
          _draft.handicap.toStringAsFixed(1),
          style: theme.textTheme.displayMedium,
        ),
      ),
      Slider(
        key: const Key('onboarding-handicap-slider'),
        value: _draft.handicap.clamp(0, 36),
        min: 0,
        max: 36,
        divisions: 36,
        onChanged: (v) => setState(
          () => _draft = _draft.copyWith(handicap: v),
        ),
      ),
    ]);
  }

  Widget _shortGameStep(ThemeData theme) {
    return _stepScroll([
      Text('Short game', style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        'These help the AI tailor its execution plans to how you '
        'like to chip and pitch.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const Key('onboarding-chip-style'),
        initialValue: _draft.chipStyle,
        decoration: const InputDecoration(
          labelText: 'Preferred chip style',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'bumpAndRun', child: Text('Bump & run')),
          DropdownMenuItem(value: 'lofted', child: Text('Lofted')),
          DropdownMenuItem(
            value: 'noPreference',
            child: Text('No preference'),
          ),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _draft = _draft.copyWith(chipStyle: v));
          }
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const Key('onboarding-wedge-confidence'),
        initialValue: _draft.wedgeConfidence,
        decoration: const InputDecoration(
          labelText: 'Wedge confidence',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'low', child: Text('Low')),
          DropdownMenuItem(value: 'average', child: Text('Average')),
          DropdownMenuItem(value: 'high', child: Text('High')),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _draft = _draft.copyWith(wedgeConfidence: v));
          }
        },
      ),
    ]);
  }

  Widget _bagStep(ThemeData theme) {
    return _stepScroll([
      Text('Your bag', style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        "We'll start you with a standard 13-club bag and the AI will "
        'use sensible default carry distances. You can edit any club '
        'distance from the Profile tab once you know your real numbers.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sports_golf, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Standard bag',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Driver, 3W, 5W, 4H, 5–9 iron, PW, GW, SW, LW',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _teeBoxStep(ThemeData theme) {
    return _stepScroll([
      Text('Tee box', style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        'The AI uses this to pick the right yardage when a course has '
        'multiple tee sets. You can change it any time from the '
        'Profile tab.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const Key('onboarding-tee-box'),
        initialValue: _draft.preferredTeeBox,
        decoration: const InputDecoration(
          labelText: 'Preferred tee box',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: 'championship',
            child: Text('Championship / Black'),
          ),
          DropdownMenuItem(value: 'blue', child: Text('Blue')),
          DropdownMenuItem(value: 'white', child: Text('White')),
          DropdownMenuItem(value: 'senior', child: Text('Gold / Senior')),
          DropdownMenuItem(value: 'forward', child: Text('Red / Forward')),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _draft = _draft.copyWith(preferredTeeBox: v));
          }
        },
      ),
    ]);
  }

  Widget _stepScroll(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
