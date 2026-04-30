// App router configuration. Single GoRouter instance for the whole
// app, built around a `StatefulShellRoute.indexedStack` so each of
// the four tabs maintains its own independent navigation state.
//
// Per **ADR 0001**: routing library is `go_router`. Per **KAN-157**'s
// preserved naming spec: tab order is Caddie → Course → History →
// Profile, with **Course** as the default landing tab.
//
// Route paths use plural-noun + verb-style nesting where it makes
// sense for future stories. The placeholder routes here are flat —
// real feature stories (KAN-279/280/281/282/283) will add nested
// routes as needed.

import 'package:go_router/go_router.dart';

import '../../features/caddie/presentation/caddie_page.dart';
import '../../features/course/presentation/course_placeholder.dart';
import '../../features/course/presentation/course_search_page.dart';
import '../../features/dev/presentation/theme_playground_page.dart';
import '../../features/history/presentation/history_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../models/normalized_course.dart';
import '../../shell/main_shell.dart';
import '../build_mode.dart';
import '../storage/profile_repository.dart';

/// Top-level routes used by the bottom navigation. Exposed as constants
/// so feature code can `context.go(AppRoutes.caddie)` etc. without
/// stringly-typed paths scattered through the codebase.
abstract final class AppRoutes {
  AppRoutes._();

  static const caddie = '/caddie';

  /// Course tab default — the search screen (KAN-S9). When the user
  /// taps a result, the search page navigates to [courseMap] with
  /// the resolved `NormalizedCourse` as the route's `extra`.
  static const course = '/course';

  /// Course map screen (KAN-S10). Pushed from the search screen
  /// with a `NormalizedCourse` as `extra`. If `extra` is null
  /// (e.g. deep link or hot-restart), the screen falls back to
  /// the bundled Sharp Park fixture.
  static const courseMap = '/course/map';

  static const history = '/history';
  static const profile = '/profile';

  /// First-run onboarding wizard (KAN-S14). The router-level
  /// `redirect` callback sends users with
  /// `PlayerProfile.hasCompletedSwingOnboarding == false` here on
  /// every navigation until they finish or skip the wizard.
  static const onboarding = '/onboarding';

  /// Cold-start splash (KAN-68 port). Set as the router's
  /// `initialLocation` so it shows on every fresh app launch. The
  /// router-level redirect explicitly bypasses this route so the
  /// first-run onboarding gate doesn't fire before the splash timer
  /// completes.
  static const splash = '/splash';

  /// Dev-only theme playground. The route is only registered when
  /// `isDevMode` is true; production builds 404 on this path.
  static const devThemePlayground = '/dev/theme';
}

/// Build the app's `GoRouter`. Called once from `lib/app.dart` and
/// passed to `MaterialApp.router`.
GoRouter buildAppRouter() {
  return GoRouter(
    // Per KAN-157, the canonical default tab is Course (not Caddie,
    // even though Caddie is leftmost in the bottom nav). The native
    // iOS app already defaults to `course`; Android originally
    // defaulted to `caddie` and was flagged as a parity bug in the
    // (now closed) KAN-157 audit.
    initialLocation: AppRoutes.splash,
    // KAN-S14 first-run gate. Per the AC, first-run detection uses
    // the profile store (NOT a separate flag) — the
    // `hasCompletedSwingOnboarding` field is the single source of
    // truth. Defensive try/catch covers the unit-test runtime
    // where Hive isn't initialized; in tests the redirect is a
    // no-op so the existing tab tests still work.
    redirect: (context, state) {
      // Don't redirect if we're already on the onboarding route
      // (otherwise we'd loop forever). Also bypass /splash so the
      // cold-start splash can run its timer before any first-run
      // gating kicks in — the splash's `onComplete` lands the user
      // on `/course`, and the redirect runs there normally.
      if (state.matchedLocation == AppRoutes.onboarding) return null;
      if (state.matchedLocation == AppRoutes.splash) return null;
      try {
        final profile = ProfileRepository().loadOrDefault();
        if (!profile.hasCompletedSwingOnboarding) {
          return AppRoutes.onboarding;
        }
      } catch (_) {
        // Hive not initialized (unit tests). Don't redirect.
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      // Dev-only theme palette playground. Only registered in dev
      // builds — production releases omit the DEV_MODE dart-define,
      // so `isDevMode` is false and this route isn't in the tree.
      if (isDevMode)
        GoRoute(
          path: AppRoutes.devThemePlayground,
          builder: (context, state) => const ThemePlaygroundPage(),
        ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // Branch 0: Caddie — KAN-281 (S11) wires the real
          // CaddiePage. The PlaceholderBody import stays for the
          // tests that still grep for the old subtitle text; the
          // route uses CaddiePage in production.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.caddie,
                builder: (context, state) => const CaddiePage(),
              ),
            ],
          ),
          // Branch 1: Course
          //
          // Two routes nested inside the Course tab branch:
          //   /course        → CourseSearchPage (KAN-S9, the new
          //                    default landing for the tab)
          //   /course/map    → CoursePlaceholder (KAN-S10 map),
          //                    pushed from the search page with
          //                    the resolved NormalizedCourse as
          //                    `extra`. The map page reads it from
          //                    `GoRouterState.extra`. Falls back to
          //                    the Sharp Park fixture if `extra`
          //                    is null (e.g. on hot-restart).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.course,
                builder: (context, state) => const CourseSearchPage(),
                routes: [
                  GoRoute(
                    path: 'map',
                    builder: (context, state) {
                      final extra = state.extra;
                      return CoursePlaceholder(
                        injectedCourse:
                            extra is NormalizedCourse ? extra : null,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 2: History
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.history,
                builder: (context, state) => const HistoryPage(),
              ),
            ],
          ),
          // Branch 3: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
