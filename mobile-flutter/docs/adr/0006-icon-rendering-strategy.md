# 0006. Icon rendering strategy

**Status:** Accepted
**Date proposed:** 2026-04-11
**Date accepted:** 2026-04-11 (KAN-270 planning pass)
**Affected stories:** KAN-291 (S0 icon foundation), all UI-touching stories (KAN-271 onward)

## Context

The CaddieAI app has a custom 45-icon set used across navigation, actions, status indicators, and golf-specific UI (flag, pin-target, dogleg, golfer, club, tee, fairway, bunker, water, hazard, etc). The full set lives in `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/` with both SVG and PNG variants for each icon.

The Flutter migration needs to integrate this icon set into the scaffold **before** any UI work starts (per the user's "no major UI without the icon set" rule). This ADR captures the rendering strategy.

Three credible options:

1. **Bundle SVGs**, render via `flutter_svg` (`SvgPicture.asset`)
2. **Bundle PNGs at 1x/2x/3x density variants**, render via `Image.asset`
3. **Generate an icon font** from the SVGs (via `fluttericon` or similar tooling), render via `Icon(CaddieIcons.flag)`

## Decision

**Use option (3) — generate an icon font from the SVG set.**

## Rationale

- **Idiomatic Flutter ergonomics.** `Icon(CaddieIcons.flag, size: 24, color: Colors.white)` is the canonical Flutter icon API. Every Flutter dev knows how to use it. SVG and PNG approaches require custom widgets at every call site.
- **Type-safe at every call site.** The `CaddieIcons` constants are compile-time-checked. Typos fail at build time, not at runtime. Material `Icons.material_icon_name` has the same property — we want our custom icons to behave the same way.
- **Smallest binary footprint.** A single font file containing 45 glyphs is smaller than 45 SVG strings or 45 PNG triples (1x/2x/3x). Particularly relevant for the Android arm64 release APK which is already 37 MB.
- **Tints via the standard `IconTheme`.** No special handling — the same `IconTheme.of(context).color` that works for Material icons works for ours. Theme switching (light/dark mode, accent color overrides) just works.
- **Fast and crisp at any size.** Font glyphs are vector-based but rendered through Flutter's existing icon rendering path. No runtime SVG parsing overhead (SVG option), no density-variant guessing (PNG option).
- **Plays well with `Riverpod` providers and theme observers.** No widget gymnastics around custom widgets — `Icon` works out of the box with `Theme.of(context)`.
- **Single source of truth.** The font file is the runtime artifact; the SVGs are checked in alongside it for traceability and future regeneration. One name, one glyph, one place to look.

## Alternatives considered

### (1) Bundle SVGs via `flutter_svg`

**Pros:**
- Renders the original SVG paths directly — no information loss from glyph conversion
- Multi-color SVGs (with multiple `fill` colors) preserve their original colors
- No codegen step

**Cons:**
- Runtime SVG parsing on every render (cached but not free)
- Custom widget at every call site: `SvgPicture.asset('assets/icons/flag.svg', width: 24, color: Colors.white)` — ugly and easy to misuse
- No type-safe constants — string asset paths are typo-prone
- Color tinting requires `colorFilter`, not the standard `Icon` color path
- Doesn't integrate with `IconTheme`

**Verdict:** The right choice IF the icon set has multi-color or gradient elements that an icon font can't represent. Re-checked the source SVGs in `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/` — they're single-color glyphs (the standard mobile-icon convention). No multi-color information to preserve. Option (3) wins.

### (2) Bundle PNGs at 1x/2x/3x density variants

**Pros:**
- No runtime parsing overhead at all
- No tooling step beyond exporting from the source `.ai` file at the right densities
- Works with existing Flutter `Image.asset` API

**Cons:**
- Largest binary footprint (45 icons × 3 density variants = 135 PNG files, each potentially 100s of bytes to a few KB)
- Color tinting requires `Image.asset(... color: ..., colorBlendMode: BlendMode.srcIn)` — clunky
- Crisp at exactly the bundled densities; blurry between (e.g. tablet 2.5x)
- Custom widget at every call site, no type safety
- Doesn't integrate with `IconTheme`

**Verdict:** Worst of both worlds. Skip.

## Consequences

### What this enables

- KAN-291 (S0 icon foundation) implements once: generate the font, write the constants class, ship
- All UI stories (KAN-271 onward) use `Icon(CaddieIcons.flag, size: 24)` — same API as Material icons
- Theme color and dark-mode switching just works via `IconTheme`
- Icon size changes are a single-arg edit, not a re-export at three densities

### What this commits us to

- A one-time icon font generation step for the SVG → font conversion. Done once during KAN-291; re-run only when icons are added or modified to the source set.
- The SVGs in the source set must be **single-color** glyphs (verified — they are). If a future icon needs multi-color or gradient rendering, that icon needs a separate path (a `flutter_svg` widget specifically for that one icon, OR a redesign to a single color).
- Adding a new icon means: drop the SVG into the source dir → re-run the font generator → update the `CaddieIcons` constants class → unit test confirms the new constant resolves. Three steps, all in one commit.

### What this prevents

- **No `Icons.material_icon_name` calls in feature code** (enforced by CONVENTIONS C-6, added by KAN-291). Every icon in the app comes from `CaddieIcons`. If a UI story needs an icon that isn't in the set, it has to add it to the set first.
- **No SVG-related dependencies** (`flutter_svg` and friends). Smaller dependency surface, faster builds.
- **No PNG density-variant guessing** or fuzzy intermediate-size rendering.

### Migration concerns

- The native iOS app uses SF Symbols (system fonts) and the native Android app uses Material Icons (Compose default). Neither maps 1:1 to the custom icon set this ADR adopts. **The visual difference between native and Flutter on icon-heavy screens is part of the migration's expected visual delta** — the Flutter app uses CaddieIcons throughout, the native apps used a mix of SF Symbols + the custom set. Flag this in design / product review of the migrated app before cutover (KAN-286 S16).

## References

- `fluttericon` web tool: https://www.fluttericon.com/
- Source icon set: `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/` (45 SVGs + 45 PNGs)
- KAN-291 (S0 icon foundation story) — implements this decision
- KAN-160 (Won't Do, superseded) — original platform-native iconography ticket
- KAN-165 (Won't Do, folded into KAN-291) — original "[Shared] Define Icon Spec In Code" subtask
- ADR 0001 (routing library) — go_router; `Icon` widgets work the same in any routing library
- ADR 0002 (state management) — Riverpod; theme provider integrates with `IconTheme` automatically
- CONVENTIONS C-6 (added by KAN-291) — enforceable rule that icons come from `CaddieIcons`
