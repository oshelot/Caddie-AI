# 0007. Icon rendering — `flutter_svg`

**Status:** Accepted
**Date proposed:** 2026-04-11
**Date accepted:** 2026-04-11 (KAN-270 planning pass)
**Affected stories:** KAN-291 (S0 icon foundation), all UI-touching stories (KAN-271 onward)
**Supersedes:** [ADR 0006](0006-icon-rendering-strategy.md) (icon font from generated TTF — failed because the source SVGs are stroke-based and incompatible with TTF glyph rendering)

## Context

KAN-291 (S0 icon foundation) needs to integrate the 45-icon CaddieAI custom set into the Flutter scaffold so that UI stories (KAN-271 onward) can render icons that match the brand identity instead of falling back to Material defaults.

The first attempt (ADR 0006) tried to generate a TTF icon font from the source SVGs via `fantasticon`. **It failed visually** — most icons rendered as solid black geometric shapes or empty boxes. Root cause: the source SVGs use stroke-based paths (`fill: none; stroke: #000; stroke-width: 1.5px;`), and TTF glyphs only support fills. The font conversion dropped every stroke.

This ADR captures the corrected decision based on **actually inspecting the SVGs** this time.

## SVG inspection (the verification ADR 0006 should have done)

Sampled 5 SVGs from `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/`:

| File | Path style | Fill | Stroke | Closed regions |
|---|---|---|---|---|
| `icon-flag.svg` | `<path>`, `<line>` | `none` | `#000`, 1.5 px | 0 (lines + open curves only) |
| `icon-distance.svg` | `<path>` | `none` | `#000`, 1.5 px | 2 (M-shaped enclosed paths) |
| `icon-golfer.svg` | `<polyline>`, `<rect>`, `<path>`, `<line>` | `none` | `#000`, 1.5 px | 1 (rect for the head) |
| `icon-home.svg` | `<path>`, `<polyline>` | `none` | `#000`, 1.5 px | 0 |
| `icon-bunker.svg` | `<ellipse>`, `<line>` | `none` | `#000`, 1.5 px | 1 (the ellipse) |

Then I ran `grep -l "fill: none" *.svg | wc -l` against the full set: **45 / 45 SVGs use `fill: none;`**. The icon set is universally stroke-based line art, designed for outlined rendering — same visual style as Google Material's "Outlined" or Apple SF Symbols' outlined variants.

This is fundamentally incompatible with TTF icon fonts. TTF glyphs are filled regions; there is no concept of a stroke in the OpenType spec. When fantasticon (or any TTF generator) converts a stroked SVG, it has three bad options:

1. Drop the stroke and emit an empty glyph
2. Fill the path's enclosed area, producing a solid silhouette
3. Approximate the stroke as a thin outlined region (most generators don't do this)

The result we observed in KAN-291's first implementation matches option 2: solid black blobs where the original was a fine line drawing.

## Decision

**Use `flutter_svg` to render the original SVGs at runtime.**

The 45 SVGs are committed in-tree under `mobile-flutter/assets/icons/` and registered as Flutter assets. The `CaddieIcons` API exposes type-safe Widget-returning helpers (one per icon) plus a `byName()` factory and an `all` registry map for tests and dynamic enumeration:

```dart
abstract final class CaddieIcons {
  CaddieIcons._();

  // Internal source of truth — name (camelCase) → asset path.
  static const Map<String, String> _paths = { /* 45 entries */ };

  // Public registry — used by tests and any dynamic icon enumeration.
  static Map<String, String> get all => _paths;

  // Type-safe getters at the call site.
  static Widget flag({double size = 24, Color? color}) =>
      _render('flag', size, color);
  // ... 44 more

  // Render helper.
  static Widget _render(String name, double size, Color? color) {
    final path = _paths[name]!;
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      colorFilter:
          color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
    );
  }
}
```

Call site usage:

```dart
CaddieIcons.flag(size: 32, color: Theme.of(context).colorScheme.primary)
```

## Rationale

- **Visual fidelity is non-negotiable.** The whole point of having a custom icon set is brand consistency. ADR 0006's icon-font path destroys that. `flutter_svg` renders the SVG paths verbatim, including the strokes, line caps, and corner radii the designer specified.
- **Type safety is preserved.** The 45 named static getters (`CaddieIcons.flag(...)`) give compile-time checking at every call site. Typos fail at build time, exactly like Material's `Icons.flag`.
- **Color tinting works.** `ColorFilter.mode(color, BlendMode.srcIn)` paints the rendered SVG output in a single color, replacing the SVG's hardcoded `#000`. Theme integration is one-line.
- **Same single-source-of-truth pattern.** The `_paths` map is the only place asset filenames live; the named getters and the `all` registry both delegate via `_render`. Adding a new icon means one entry in `_paths` + one named getter (≤ 5 lines).
- **No tooling step.** ADR 0006 required `fantasticon` + an icon font regen step every time the icon set changed. This decision drops the tool entirely — the SVGs are the runtime artifact, not source for a downstream codegen.

## Trade-offs accepted

| | Icon font (rejected — ADR 0006) | `flutter_svg` (this decision) |
|---|---|---|
| Binary size (icon assets) | ~8 KB TTF | ~60 KB SVGs |
| Dependency footprint | None (font is just an asset) | `flutter_svg` ^2.0 + transitive (`vector_graphics`, `xml`) — ~200 KB |
| Runtime cost | Negligible (font glyph) | First-paint SVG parse per icon, then cached for the process lifetime |
| API at call site | `Icon(CaddieIcons.flag, size: 24)` | `CaddieIcons.flag(size: 24)` — slightly cleaner, no `Icon(...)` wrapper |
| Type safety | const `IconData` | `static Widget` functions |
| Color tinting | `IconTheme` automatic | `colorFilter` explicit at call site |
| Compatibility with stroke-based SVGs | ❌ broken | ✅ native |
| Visual fidelity | ❌ destroyed | ✅ pixel-perfect |

The visual fidelity row is decisive. It overrides every "size" or "performance" argument in the table.

The runtime SVG parse cost is real but small in absolute terms (microseconds per icon, once per process). flutter_svg caches parsed pictures internally; subsequent renders of the same icon at any size are essentially free. For a 45-icon set in a Flutter app, the total first-paint cost is bounded at a few ms.

The dependency footprint (~200 KB extra) is acceptable. The arm64 release APK is currently 37 MB (per KAN-252 spike measurements); a 0.5% increase is well below any threshold that matters.

## Consequences

### What this enables

- KAN-291 ships with the actual icon set rendered correctly. UI stories (KAN-271 onward) get visually-correct icons from day 1.
- Adding a new icon is a 2-line edit (plus the SVG file): one entry in `_paths`, one named getter. No codegen step. No regeneration ritual.
- The smoke test in `lib/app.dart` shows the real icons (flag, golfer, distance) rendered via flutter_svg — visually verifiable on any device.
- ADR 0006's "no Material defaults in feature code" rule (CONVENTIONS C-6) still holds, with the API updated to the Widget-getter form.

### What this commits us to

- A `flutter_svg` major version bump becomes a recurring maintenance event. Historically `flutter_svg` is well-maintained and breaking changes between majors are documented.
- The SVG source files become a runtime asset, not just source-of-truth. **Don't commit broken or experimental SVGs to `mobile-flutter/assets/icons/`** — they ship to production. Use a separate working dir for design iteration.
- Color tinting requires explicit `color:` at the call site (or `ColorFilter` at the parent widget). There's no automatic `IconTheme` integration. For most use cases this is a one-arg pass-through; for theme-driven coloring we recommend reading from `Theme.of(context).colorScheme.X` at the call site.

### What this prevents

- Same as ADR 0006 — no `Icons.material_*` calls in feature code (CONVENTIONS C-6). All icons go through `CaddieIcons`.
- No re-attempt at icon-font generation without first verifying the source SVGs are fill-based (and even then, only if there's a measurable binary size or render cost reason — currently there isn't).

## Migration concerns

- The native iOS app uses SF Symbols and the native Android app uses Material Compose icons. The Flutter app uses CaddieIcons throughout. The visual delta vs the native iOS app on icon-heavy screens is part of the migration's expected visual change — the original CaddieAI design system was already moving toward the custom set (per KAN-160's pre-migration intent), so flagging this to design / product is recommended but not blocking.
- KAN-271 (S1 app shell) uses `CaddieIcons.home`, `CaddieIcons.course`, `CaddieIcons.history`, `CaddieIcons.profile` for the bottom tab bar. These are already in the registry.

## References

- `flutter_svg` package: https://pub.dev/packages/flutter_svg
- Source icon set: `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/` (45 SVGs, all `fill: none; stroke: #000;`)
- Runtime asset path: `mobile-flutter/assets/icons/`
- KAN-291 (S0 icon foundation story) — implements this decision
- ADR 0006 (Superseded) — the failed icon-font attempt and post-mortem
- CONVENTIONS C-6 — enforceable rule that all icons come from `CaddieIcons`
