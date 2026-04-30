# 0004. Local storage library

**Status:** Accepted (depends on ADR 0003, also accepted)
**Date proposed:** 2026-04-11
**Date accepted:** 2026-04-11 (KAN-270 planning pass)
**Affected stories:** KAN-272 (S2 storage)

## Context

The KAN-251 Flutter migration needs local persistence for:

- Player profile (handicap, club distances, voice prefs, feature flags) — small, mutable, read-on-startup
- Shot history (append-only log) — see ADR 0003
- Scorecard entries — same shape considerations as shot history
- API keys for the LLM router — must go in **secure** storage, not the general profile bag (Keychain on iOS, EncryptedSharedPreferences on Android, via `flutter_secure_storage`)
- Course cache (recently fetched `NormalizedCourse` JSONs with TTL) — already covered by KAN-275 (S5) which will use its own disk cache scheme

This ADR is about the **non-secret structured storage layer** for profile + shot history + scorecard.

The Flutter ecosystem has three credible options:

1. **`hive_ce`** (the maintained fork of Hive — original is unmaintained) — fast key/value store with type-safe boxes, no SQL
2. **`drift`** — type-safe SQLite wrapper with compile-time-checked queries, codegen-based
3. **`shared_preferences` + manual JSON serialization** — minimal but loses type safety and performance

## Decision (proposed)

**Use `hive_ce` for structured storage (profile, shot history, scorecard) plus `flutter_secure_storage` for API keys.**

This decision is informed by ADR 0003 — because shot history doesn't need SQL queries, we don't need a database engine.

## Rationale

- **Right-sized for the working set.** Player profile is one object. Shot history is small enough to load in memory (per ADR 0003). Scorecard entries are similarly bounded. None of this needs a query optimizer.
- **No codegen step for the storage layer itself.** `hive_ce` adapters are codegen-based but the codegen is fast and only runs when models change. Compare to Drift's heavier codegen + schema migrations.
- **Plays well with `freezed`.** `freezed` models can be wrapped in a thin `HiveAdapter` (or hand-written `toJson`/`fromJson`) for storage. The epic already pre-commits to `freezed`, so this is the natural fit.
- **Migration importer is straightforward.** KAN-272 needs to read existing native `UserDefaults` (iOS) / `DataStore` (Android) blobs and upsert into the new store. With Hive, this is "parse the native blob → construct the freezed dataclass → put it in the box". With Drift, it would be "parse → INSERT INTO ... VALUES" and you have to keep the SQL schema in sync with the parser.
- **Cross-platform consistency.** `hive_ce` works identically on iOS and Android (and works on desktop/web for tests). Drift requires platform-specific SQLite setup.

## Alternatives considered

### Drift (SQLite)

**Pros:** Real SQL queries. Compile-time-checked. Indexes. Joins. The right answer for an app with serious local query needs.

**Cons:** Overkill given ADR 0003 (shot history doesn't need SQL). Schema migrations are recurring work. Heavier codegen footprint. Slower iteration on model changes.

**Verdict:** Reconsider only if a future story (a) reverses ADR 0003, OR (b) introduces a feature that genuinely needs SQL aggregation (cross-course analytics with windowing, etc.). Until then, the Drift maintenance tax isn't earning its keep.

### `shared_preferences` + manual JSON

**Pros:** Smallest dependency footprint. Already used implicitly by Flutter for some platform settings.

**Cons:** Type safety is manual (every `getString` returns `String?` and you parse). Performance degrades with large JSON blobs (every read deserializes the whole thing). Hard to test.

**Verdict:** Use `flutter_secure_storage` (which builds on the same platform APIs) for the **secrets-only** path. Don't use `shared_preferences` for structured storage.

## Consequences

### What this enables

- KAN-272 ships with a single `Hive.openBox<PlayerProfile>('profile')` plus parallel boxes for shot history and scorecard
- Schema evolution: add a nullable field to a `freezed` class, regen the Hive adapter, ship. No SQL migration file.
- Tests use Hive's in-memory box helpers — no SQLite setup, no platform channel mocking
- Migration importer (KAN-272 AC) reads native blobs once at first launch and writes to the appropriate box
- API keys land in `flutter_secure_storage` (separate package), NOT in the same box as the profile

### What this commits us to

- A `build_runner` codegen step for Hive adapters (similar tooling to Riverpod codegen and `freezed` — usually share the same `build_runner watch` invocation in the dev loop)
- If shot history grows past ~500k entries OR a future story needs SQL aggregation, this ADR gets superseded by an ADR that picks Drift. The migration path would be: read all from Hive on startup, write to Drift, drop the Hive boxes. Painful but bounded.

### Migration concerns

- **API keys must NOT land in the Hive box.** Test (per KAN-272 AC) that reading the raw Hive file does not leak any LLM API keys. Use `flutter_secure_storage` for those, period.
- **Hive's `box.values` is lazy** — be careful in the migration importer to fully iterate native data into the box, not just stream it through.

## References

- `hive_ce` docs: https://pub.dev/packages/hive_ce
- `flutter_secure_storage` docs: https://pub.dev/packages/flutter_secure_storage
- ADR 0003 (shot history query strategy) — informs this choice
- KAN-272 (S2 storage)
