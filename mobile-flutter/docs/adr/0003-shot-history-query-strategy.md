# 0003. Shot history query strategy

**Status:** Proposed — informs ADR 0004 (storage library), should be decided before KAN-272 (S2 storage) starts.
**Date proposed:** 2026-04-11
**Affected stories:** KAN-272 (S2 storage), KAN-282 (S12 history)

## Context

The native iOS and Android apps store **shot history** as an append-only local log. Each entry includes: timestamp, course, hole number, distance estimate, club used, AI recommendation, execution outcome, optional voice transcript, optional image.

The History tab (KAN-S12 / KAN-282) lets users browse this log. The native apps support **at least** these query patterns:

1. List all shots in reverse-chronological order (paginated)
2. Filter by date range
3. Filter by course
4. Filter by club
5. Filter by shot type / category

The question this ADR answers: **does the Flutter migration need a real query layer (a database) for shot history, or can we get away with loading the entire log into memory and filtering in Dart?**

The answer determines ADR 0004 (storage library): if we need real queries, we need Drift; if not, Hive is enough.

## Decision (proposed)

**In-memory filtering on top of a flat append-only file (Hive box).**

## Rationale

- **Working set is small.** Even a power user shooting 100 rounds a year (a generous estimate for a typical CaddieAI user) generates ~1,800 shots/year (avg 18 holes × 1 shot per hole — actually ~3-4 shots per hole if you count tee/approach/chip/putt, but the AI caddie use case is one shot per recommendation). Five years of data is well under 50k entries. Each entry is a few hundred bytes serialized. Total cap: a few MB. **The entire log fits comfortably in memory.**
- **Filter operations are O(n) but n is tiny.** Dart can iterate 50k objects and apply 5 filters in well under 16 ms (a single frame budget). No noticeable UI lag.
- **Pagination is for rendering, not for storage.** The History list view paginates output to the UI for memory efficiency, but the underlying log is loaded once.
- **Avoids the Drift schema-migration tax.** SQL schemas need migration scripts for every new column. Shot-history schema will evolve over time; in-memory dataclasses with `freezed` are easier to migrate (just add a nullable field with a default).
- **Matches the native iOS architecture.** The native iOS app stores shot history in `UserDefaults` and filters in-memory — same approach.
- **Keeps the storage abstraction simple.** A single `ShotHistoryRepository` over a Hive box, no SQL knowledge required.

## Alternatives considered

### SQL-backed via Drift

**Pros:** Real query optimizer. Indexes. Joins (if we ever want to join shots against courses). Type-safe SQL via codegen.

**Cons:** Schema migrations are real work and a recurring maintenance cost. The query power is **overkill for the working-set size** — we'd be using a sledgehammer for a flyweight problem. SQL on mobile is also slower to iterate on than dataclass changes.

**Verdict:** Reconsider only if (a) we add a feature that genuinely needs SQL joins (e.g. cross-course shot analytics with windowing), OR (b) the working set grows past ~500k entries (unlikely for this app).

### Hive box + Hive secondary indexes

**Pros:** Hive supports custom secondary indexes for fast lookups by indexed fields.

**Cons:** Adds API surface that's hard to reason about. The in-memory full-scan is fast enough that secondary indexes are unnecessary optimization.

**Verdict:** Don't bother. Use Hive as a key/value bag, do the filtering in Dart.

## Consequences

### What this enables

- ADR 0004 can choose Hive (lightweight, no codegen) instead of Drift
- KAN-272 (S2 storage) ships a simple `ShotHistoryRepository` with `Future<List<Shot>> all()` and Dart-side filter helpers
- KAN-282 (S12 history) renders the full filtered list with pagination at the UI layer only
- Schema evolution is just `freezed` field additions — no SQL migration files

### What this commits us to

- App startup loads the entire shot history into memory. **Measure this** — if cold-start latency increases noticeably, revisit. Cap based on the iPhone 12 / Android mid-tier cold-start budget.
- Future features that need cross-shot analytics (averages, trend lines) have to compute on the in-memory list, not via SQL aggregation. Probably fine; revisit if a future story needs heavy aggregation.

### Migration concerns

- The native apps' shot history must be readable by KAN-272's migration importer. `UserDefaults` (iOS) and `DataStore` (Android) shapes need to be inspected and parsed. This is already an AC on KAN-272.

## References

- Native iOS shot history storage: search `ios/CaddieAI/` for `ShotHistoryEntry`
- Native Android shot history storage: search `android/app/src/main/java/com/caddieai/android/` for `ShotHistoryEntry`
- ADR 0004 (storage library) — depends on this decision
- KAN-272 (S2 storage)
- KAN-282 (S12 history)
