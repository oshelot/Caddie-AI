# Caddie AI

AI-powered golf caddie mobile app, built with [Flutter](https://flutter.dev) for unified iOS + Android.

KAN-251 Flutter migration replaced the original Swift/SwiftUI iOS app and Kotlin/Compose Android app with a single Flutter codebase that consumes the existing LLM proxy, course cache, and logging backends without changing them.

## Status

Active development on `main`. The `mobile-flutter/` wrapper directory was flattened to the repo root in 2026-04-30 — every Flutter file now lives directly at top level, matching standard Flutter project layout.

## Before you write any code

**Read [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md).** It's distilled from the KAN-252 Flutter feasibility spike and captures four enforceable rules that every story must follow — skipping them will cost you a half-day of debugging issues the spike already found.

The spike findings are preserved as git tag [`spike/kan-252-flutter-perf`](https://github.com/oshelot/Caddie-AI/releases/tag/spike/kan-252-flutter-perf) (the spike's branch was deleted after migration). The tag's commit message summarizes the GO/NO-GO conclusions; the 5 commits it points at have full per-platform measurement notes.

## Running

```bash
flutter pub get
flutter test
flutter run --profile -d <device-id> \
  --dart-define=MAPBOX_TOKEN=pk.xxx
```

For full build/run details and dart-define wiring, see [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md). Local helper scripts in [`tool/`](tool/) (notably `tool/run.sh`) handle dart-define injection automatically — they read tokens from environment variables, never from committed files.

`MAPBOX_TOKEN`, `LLM_PROXY_API_KEY`, `COURSE_CACHE_API_KEY`, `LOGGING_API_KEY`, and `GOLF_COURSE_API_KEY` come from your local environment. `tool/run-ios.sh` (gitignored) holds the active values for local-dev convenience — never commit it.

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
