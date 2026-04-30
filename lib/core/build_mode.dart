// Dev mode flag — passed via --dart-define=DEV_MODE=true in the
// run scripts. Unlike kDebugMode (which is false in profile/release
// builds), this stays true in ALL sideload builds so the debug Pro
// toggle and ad suppression work in profile mode too.
//
// Production App Store / Play Store builds omit the flag, so
// isDevMode defaults to false and users see the real tier + ads.

const bool isDevMode = bool.fromEnvironment('DEV_MODE', defaultValue: false);
