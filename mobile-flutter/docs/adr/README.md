# Architectural Decision Records — CaddieAI Flutter migration

This directory contains Architectural Decision Records (ADRs) for the
KAN-251 Flutter migration. Each ADR captures **one** framework or
library choice, the alternatives that were considered, the rationale
for the recommendation, and the current status (`Proposed` /
`Accepted` / `Superseded`).

ADRs are **lightweight by design**. Each one fits in ~80-120 lines
and is meant to be read in 2-3 minutes. If a decision needs more
detail than that, write a separate design doc and link to it from the
ADR.

## Index

| ADR | Title | Status | Affected stories |
|---|---|---|---|
| [0001](0001-routing-library.md) | Routing library | Proposed — needs sign-off before KAN-271 starts | KAN-271 (S1 app shell) |
| [0002](0002-state-management.md) | State management framework | Accepted — pre-decided in KAN-251 epic | All UI stories |
| [0003](0003-shot-history-query-strategy.md) | Shot history query strategy | Proposed — informs ADR 0004 | KAN-282 (S12 history), KAN-272 (S2 storage) |
| [0004](0004-storage-library.md) | Local storage library | Proposed — depends on ADR 0003 | KAN-272 (S2 storage) |
| [0005](0005-monetization-plugin.md) | Monetization plugin | Proposed — needs sign-off before KAN-285 starts | KAN-285 (S15 monetization) |

## How to update an ADR

1. Edit the ADR file directly. Don't create a new ADR for a small clarification.
2. If a decision is overturned, change the status to `Superseded by ADRNNNN` and create a new ADR with the new decision. Don't delete the old one.
3. If an ADR is accepted, change the status to `Accepted` and add the date.
4. Each PR that picks up an affected story should reference the ADR in its description.

## When to write a new ADR

Add an ADR when you're about to commit to:

- A new major package dependency (state mgmt, routing, storage, networking, navigation)
- A new architectural pattern (offline-first, event-sourcing, etc.)
- A cross-cutting convention that doesn't fit in `CONVENTIONS.md` (CONVENTIONS.md is for code rules; ADRs are for design choices)

Don't write an ADR for:

- Small package additions (e.g. adding `intl`)
- One-off tactical choices in a single story
- Things already documented in `CONVENTIONS.md`
