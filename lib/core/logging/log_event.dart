// Log event data classes for the KAN-273 (S3) logging client.
//
// **Wire format compatibility.** The shape of `LogEntry.toJson()`
// matches the existing iOS native `LoggingService` payload exactly,
// because both apps POST to the same CloudWatch-backed endpoint
// (`prod/logs`) and the Lambda there parses the iOS shape. The
// keys (`level`, `category`, `message`, `timestampMs`, `metadata`)
// are not negotiable — the dashboards built on top of the existing
// CloudWatch metric filters look for those exact field names.
//
// **Categories** are restricted to the small set called out in the
// KAN-273 scope (`llm`, `network`, `general`, `lifecycle`, `map`),
// not the full set the iOS native LoggingService had. The native
// app accumulated categories over time as features were added
// (`analysis`, `course`, `weather`, `subscription`); the Flutter
// migration trims them down to the categories that have actual
// dashboards on the receiving end. If a future story needs another
// category, add it here AND add the matching CloudWatch metric
// filter on the server side — don't add it locally and lose the
// log routing.

/// Log severity. String wire values are lowercase to match the
/// iOS native `LogLevel` raw values.
enum LogLevel {
  info,
  warning,
  error;

  String get wireName => name;
}

/// Log category. The set is intentionally narrow — see the file
/// header for the policy on adding new categories.
enum LogCategory {
  /// LLM provider calls (OpenAI / Claude / Gemini / proxy).
  llm,

  /// HTTP / network calls that aren't LLM-specific (course API,
  /// weather API, server cache, telemetry POSTs themselves).
  network,

  /// Catch-all for anything not in the other categories. Use
  /// sparingly — adding a specific category is usually better.
  general,

  /// App lifecycle events (cold start, foreground/background, etc.).
  lifecycle,

  /// Map / Mapbox events (style load, layer add/drop, flyTo).
  map;

  String get wireName => name;
}

/// One structured log entry. Created by feature code via the
/// `LoggingService` convenience methods (`info`, `warning`, `error`)
/// and then queued for batched delivery.
class LogEntry {
  const LogEntry({
    required this.level,
    required this.category,
    required this.message,
    required this.timestampMs,
    this.metadata = const {},
  });

  final LogLevel level;
  final LogCategory category;
  final String message;
  final int timestampMs;

  /// Optional structured metadata. Keys and values are stringified
  /// because the receiving Lambda enforces a flat string-string
  /// metadata shape — no nested objects, no numeric values.
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'level': level.wireName,
      'category': category.wireName,
      'message': message,
      'timestampMs': timestampMs,
    };
    if (metadata.isNotEmpty) {
      json['metadata'] = metadata;
    }
    return json;
  }
}
