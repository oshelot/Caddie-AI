# Caddie AI

AI-powered golf caddie mobile app, built with [Flutter](https://flutter.dev) for unified iOS + Android.

## Repository structure

```
caddie-ai/
├── mobile-flutter/      # The Flutter app (active codebase)
├── DESIGN_SYSTEM.md     # Design system reference
├── LICENSE
└── .github/workflows/   # CI/CD
```

## Getting started

The Flutter app lives in [`mobile-flutter/`](mobile-flutter/). See [`mobile-flutter/README.md`](mobile-flutter/README.md) for full setup, build, and run instructions.

Quick start (requires Flutter SDK):

```bash
cd mobile-flutter
flutter pub get
flutter run
```

## History

CaddieAI began as separate native apps — iOS (Swift / SwiftUI) and Android (Kotlin / Jetpack Compose). After evaluating Flutter for performance feasibility (see git tag [`spike/kan-252-flutter-perf`](https://github.com/oshelot/Caddie-AI/releases/tag/spike/kan-252-flutter-perf)), the project migrated to a unified Flutter codebase (tracked as JIRA epic KAN-251). The legacy native projects were retired in April 2026.

If you encounter pre-migration commits referencing `ios/` or `android/` at the repo root, that's the prior native architecture — those directories no longer exist on the trunk.

## License

See [LICENSE](LICENSE).
