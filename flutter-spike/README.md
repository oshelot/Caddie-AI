# CaddieAI Flutter Spike — KAN-252

Time-boxed GO/NO-GO spike for migrating CaddieAI to Flutter using
`mapbox_maps_flutter`. Renders the 7-layer course overlay for **Wellshire
Golf Course, Denver** from a fixture `NormalizedCourse` JSON.

**This directory is discardable on NO-GO.** Nothing here is wired into the
production iOS or Android apps.

## Run

The Mapbox public token is injected via `--dart-define` and is **never**
committed. Read it from `android/local.properties` (`MAPBOX_API_KEY=...`):

```bash
# Android
flutter run -d <android-device> \
  --dart-define=MAPBOX_TOKEN=pk.xxx

# iOS (on a Mac)
flutter run -d <ios-device> \
  --dart-define=MAPBOX_TOKEN=pk.xxx
```

The Mapbox **downloads** token (`sk.xxx`) must also be configured so
gradle/pod can fetch the SDK:

- Android: `~/.gradle/gradle.properties` → `MAPBOX_DOWNLOADS_TOKEN=sk.xxx`
- iOS: `~/.netrc` → `machine api.mapbox.com login mapbox password sk.xxx`

## Success criteria

See `/home/apatel/.claude/plans/joyful-humming-pumpkin.md` for the full plan
and the GO/NO-GO thresholds. The deliverable is `SPIKE_REPORT.md` (written
on Day 5) with measured FPS on mid-tier iOS + Android.
