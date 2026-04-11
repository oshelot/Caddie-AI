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

import '../../features/caddie/presentation/caddie_placeholder.dart';
import '../../features/course/presentation/course_placeholder.dart';
import '../../features/history/presentation/history_placeholder.dart';
import '../../features/profile/presentation/profile_placeholder.dart';
import '../../shell/main_shell.dart';

/// Top-level routes used by the bottom navigation. Exposed as constants
/// so feature code can `context.go(AppRoutes.caddie)` etc. without
/// stringly-typed paths scattered through the codebase.
abstract final class AppRoutes {
  AppRoutes._();

  static const caddie = '/caddie';
  static const course = '/course';
  static const history = '/history';
  static const profile = '/profile';
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
    initialLocation: AppRoutes.course,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // Branch 0: Caddie
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.caddie,
                builder: (context, state) => const CaddiePlaceholder(),
              ),
            ],
          ),
          // Branch 1: Course
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.course,
                builder: (context, state) => const CoursePlaceholder(),
              ),
            ],
          ),
          // Branch 2: History
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.history,
                builder: (context, state) => const HistoryPlaceholder(),
              ),
            ],
          ),
          // Branch 3: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfilePlaceholder(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
