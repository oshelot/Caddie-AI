# Caddie AI

AI-powered golf caddie mobile app, built with [Flutter](https://flutter.dev) for unified iOS + Android.

KAN-251 Flutter migration replaced the original Swift/SwiftUI iOS app and Kotlin/Compose Android app with a single Flutter codebase that consumes the existing LLM proxy, course cache, and logging backends without changing them.

## Status

Active development on `main`. The `mobile-flutter/` wrapper directory was flattened to the repo root in 2026-04-30 — every Flutter file now lives directly at top level, matching standard Flutter project layout.

## Before you write any code

**Read [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md).** It's distilled from the KAN-252 Flutter feasibility spike and captures four enforceable rules that every story must follow — skipping them will cost you a half-day of debugging issues the spike already found.

The spike findings are preserved as git tag [`spike/kan-252-flutter-perf`](https://github.com/oshelot/Caddie-AI/releases/tag/spike/kan-252-flutter-perf) (the spike's branch was deleted after migration). The tag's commit message summarizes the GO/NO-GO conclusions; the 5 commits it points at have full per-platform measurement notes.

## Running

All configuration — the Mapbox token, backend endpoints, and API keys — is
supplied at build time via `--dart-define`. **Nothing sensitive is committed;
you provide your own values.**

1. Copy the config template to the gitignored `android/local.properties` and
   fill in your own values:

   ```bash
   cp android/local.properties.example android/local.properties
   ```

   At minimum, set `MAPBOX_TOKEN` to a free [Mapbox](https://account.mapbox.com/access-tokens/)
   public token so the map renders. The backend and sign-in keys are optional —
   the comments in the file explain what each enables; without them the app
   runs in a degraded / guest-only mode.

2. Build and run with the helper script. It reads `android/local.properties`
   and injects every value as a `--dart-define` — the guaranteed wiring path
   for both Android and iOS:

   ```bash
   flutter pub get
   ./tool/run.sh                  # default device, debug
   ./tool/run.sh -d <device-id>   # a specific device
   ./tool/run.sh --release        # release build
   ```

   Unit tests need no device or config: `flutter test`.

`android/local.properties` is gitignored and must never be committed. For full
build/run details and dart-define wiring, see [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md).

## Project layout

```
caddie-ai/
├── lib/                     # Dart source
├── test/                    # Unit + widget tests
├── ios/                     # Flutter-managed iOS scaffolding
├── android/                 # Flutter-managed Android scaffolding
├── assets/                  # Images, fonts, branding
├── docs/                    # Conventions, ADRs, design system
│   ├── CONVENTIONS.md
│   ├── DESIGN_SYSTEM.md
│   ├── KAN-251-STORIES.md
│   └── adr/
├── tool/                    # Helper scripts (run.sh, etc.)
├── pubspec.yaml
├── README.md
├── LICENSE
└── .github/workflows/       # CI/CD (currently stale — Flutter rewrite is on the to-do list)
```

The `infrastructure/` directory is also present on disk as a **nested private git repo** (`github.com/oshelot/CaddieAI-infra`) holding all proprietary backend code (lambdas, scrapers, course-mapping pipeline). It's `.gitignore`'d from this public repo. You won't see it after a fresh `git clone`.

## License

See [LICENSE](LICENSE).
