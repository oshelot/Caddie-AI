// SplashScreen — Flutter port of the iOS `SplashScreenView.swift`
// (KAN-68). Layout from top to bottom:
//
//   1. Bolty mascot, ~260 px circular, top half of the screen
//      (its bottom edge sits at the vertical midpoint per KAN-68)
//   2. CaddieAI wordmark in the spacing between mascot and the
//      bottom brand band
//   3. Bottom band: "Brought to you by" + bold "Ryppl Golf" text
//
// **Branding update (post-KAN-251 cutover request):** the iOS
// native used a `SubcultureWordmark` image asset in the bottom
// band. The publisher is rebranding from "Subculture Golf" to
// "Ryppl Golf"; the new wordmark image isn't ready yet, so the
// bottom band uses **bold text "Ryppl Golf"** at exactly 2× the
// "Brought to you by" font size as a temporary placeholder. Once
// the new wordmark image lands, drop it into
// `assets/branding/` and replace the `_RypplBrandBand` widget
// below with an `Image.asset` call — the surrounding layout
// doesn't need to change.
//
// **Architecture: pure widget with constructor injection.** The
// screen takes an `onComplete` callback the page wrapper hands in.
// The wrapper navigates to the next route (course or onboarding,
// per the router redirect) when the splash duration elapses.
// The screen does NOT navigate by itself — same testability
// pattern as the rest of the migration's leaf widgets.

import 'dart:async';

import 'package:flutter/material.dart';

// Brand colors lifted from the iOS native splash:
// SplashScreenView.swift:26-27.
const Color _caddieColor = Color(0xFF23367D);
const Color _aiColor = Color(0xFFC5031A);
const Color _backgroundColor = Color(0xFFE8E9EB);

// Font sizes — 13 pt for "Brought to you by" matches the iOS
// native; 26 pt (2×) for "Ryppl Golf" per the post-cutover
// rebrand request.
const double _broughtToYouSize = 13;
const double _rypplGolfSize = 26;

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onComplete,
    this.splashDuration = const Duration(milliseconds: 1500),
  });

  /// Called once after [splashDuration] elapses. The page wrapper
  /// hooks this to navigate to the next route.
  final VoidCallback onComplete;

  /// How long the splash stays visible. Default 1.5 s — long
  /// enough for the fade-in animations to land, short enough that
  /// the user doesn't get bored. Tests pass `Duration.zero` to
  /// fire the timer instantly.
  final Duration splashDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<double> _brandOpacity;
  Timer? _completionTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Mascot: scale + fade-in over 0–600 ms.
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.66, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.66, curve: Curves.easeOut),
      ),
    );
    // CaddieAI wordmark: fade-in over 300–800 ms.
    _wordmarkOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.33, 0.88, curve: Curves.easeOut),
    );
    // "Brought to you by" + Ryppl Golf: fade-in over 500–900 ms.
    _brandOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );

    _controller.forward();

    // Schedule the completion callback. The animations run in
    // parallel, then the splash holds at 100% for the remainder
    // of `splashDuration`.
    _completionTimer = Timer(widget.splashDuration, () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            // Top half: bolty mascot anchored at the screen
            // midpoint (its bottom edge sits at 50%, matching the
            // KAN-68 spec).
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.topCenter,
                heightFactor: 0.5,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: child,
                        ),
                      );
                    },
                    child: const _BoltyMascot(size: 260),
                  ),
                ),
              ),
            ),
            // CaddieAI wordmark — sits just below the mascot
            // (~66% from top) so it has visual breathing room
            // from both the mascot and the bottom brand band.
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.topCenter,
                heightFactor: 0.66,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedBuilder(
                    animation: _wordmarkOpacity,
                    builder: (context, child) => Opacity(
                      opacity: _wordmarkOpacity.value,
                      child: child,
                    ),
                    child: const _CaddieAiWordmark(),
                  ),
                ),
              ),
            ),
            // Bottom band: "Brought to you by" + bold Ryppl Golf
            // text. The native used 60 px of bottom padding;
            // match that.
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: AnimatedBuilder(
                animation: _brandOpacity,
                builder: (context, child) => Opacity(
                  opacity: _brandOpacity.value,
                  child: child,
                ),
                child: const _RypplBrandBand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── presentational sub-widgets ─────────────────────────────────────

class _BoltyMascot extends StatelessWidget {
  const _BoltyMascot({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/branding/bolty.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Defensive fallback if the asset is missing in a test
        // bundle — render an empty circle so the layout still
        // measures correctly.
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade300,
        ),
      ),
    );
  }
}

class _CaddieAiWordmark extends StatelessWidget {
  const _CaddieAiWordmark();

  @override
  Widget build(BuildContext context) {
    // The native used Orbitron-ExtraBold at 38pt with letter
    // spacing 0.5. We don't bundle Orbitron in the Flutter
    // project so the system heavy weight stands in. Once the
    // brand font ships, register it under
    // `pubspec.yaml > flutter > fonts` and add
    // `fontFamily: 'Orbitron'` here.
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Caddie',
            style: TextStyle(color: _caddieColor),
          ),
          TextSpan(
            text: 'AI',
            style: TextStyle(color: _aiColor),
          ),
        ],
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      key: Key('splash-caddieai-wordmark'),
    );
  }
}

class _RypplBrandBand extends StatelessWidget {
  const _RypplBrandBand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Brought to you by',
          key: const Key('splash-brought-to-you-by'),
          style: TextStyle(
            fontSize: _broughtToYouSize,
            color: Colors.black.withValues(alpha: 0.45),
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Ryppl Golf',
          key: Key('splash-ryppl-golf-wordmark'),
          style: TextStyle(
            fontSize: _rypplGolfSize,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
