# Caddie AI

AI-powered golf caddie app for iOS and Android.

## Repository Structure

```
├── ios/                 # iOS app (Swift / SwiftUI / Xcode)
├── android/             # Android app (Kotlin / Jetpack Compose)
├── infrastructure/      # Shared backend (AWS Lambda, Grafana, configs)
└── .github/workflows/   # CI/CD (GitHub Actions)
```

## Getting Started

### iOS
```bash
cd ios
open CaddieAI.xcodeproj
```
Requires Xcode 16+ and the vendored frameworks in `ios/Frameworks/` (not checked in — download separately).

### Android
```bash
cd android
./gradlew assembleDebug
```
Requires Android Studio and JDK 17.

## CI/CD

GitHub Actions runs automatically on push/PR to `main`:
- **iOS Tests** — triggered by changes in `ios/` (macOS runner)
- **Android Tests** — triggered by changes in `android/` (Linux runner)

Results visible at the [Actions dashboard](../../actions).
