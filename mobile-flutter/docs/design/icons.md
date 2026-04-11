# CaddieAI icon set

The CaddieAI app uses a custom 45-icon set integrated as a generated icon font. This doc captures the icon inventory, sizing rules, color tinting, and the regeneration process. Decision rationale is in [ADR 0006](../adr/0006-icon-rendering-strategy.md). Enforceable usage rule is **CONVENTIONS C-6**.

## How to use

Always import `CaddieIcons` and use the `Icon` widget:

```dart
import 'package:caddieai/core/icons/caddie_icons.dart';

Icon(CaddieIcons.flag, size: 24, color: Theme.of(context).colorScheme.primary)
```

**Never:**

```dart
Icon(Icons.flag)                                            // ❌ Material default
SvgPicture.asset('assets/icons/icon-flag.svg')              // ❌ runtime SVG
Image.asset('assets/icons/icon-flag.png')                   // ❌ raw PNG
Icon(IconData(0xF11B, fontFamily: 'CaddieIcons'))           // ❌ hardcoded glyph
```

If a UI story needs an icon that isn't in the set, **add it via the regeneration process below** — don't fall back to a Material default.

## Standard sizes

| Size (dp) | Use case |
|---|---|
| 16 | Compact — inline with body text, dense list rows, badges |
| 20 | Default — most icon-button uses, tab bar inactive states |
| 24 | Prominent — primary CTAs, tab bar active state, dialog headers |
| 32 | Hero — empty states, splash screens, error/success illustrations |

Don't invent sizes outside this set without a design discussion. If a screen needs a 28 dp or 36 dp icon, it's almost always wrong — pick one of the four above.

## Color tinting

Icons inherit color from `IconTheme.of(context).color` by default. To override at the call site, pass `color:` explicitly:

```dart
// Theme color (preferred — adapts to dark mode automatically)
Icon(CaddieIcons.flag, size: 24)

// Explicit theme reference
Icon(CaddieIcons.flag, size: 24, color: Theme.of(context).colorScheme.primary)

// Status color from the theme
Icon(CaddieIcons.error, size: 20, color: Theme.of(context).colorScheme.error)
```

**Never hardcode a hex literal at the call site:**

```dart
Icon(CaddieIcons.flag, color: Color(0xFFFF0000))   // ❌ no theme awareness
```

If you genuinely need a non-theme color (e.g. an in-map overlay where the color is data-driven, not theme-driven), pass it explicitly with a comment explaining why the theme path doesn't fit.

## Padding and spacing

| Context | Padding |
|---|---|
| Icon-only button | 8 dp around the icon (so a 24 dp icon → 40 dp button hit target) |
| Icon + text label (horizontal) | 4 dp spacing between icon and text |
| Icon + text label (vertical, e.g. tab bar) | 2 dp spacing |
| Icon as list-row leading | 16 dp leading inset, 12 dp trailing to text |

## The 45 icons

Codepoints are in the Unicode private-use area (U+F101..U+F12D). Auto-assigned by fantasticon in reverse-alphabetical-of-source-filename order, deterministic on the input set.

### Navigation (8)

| Constant | Source SVG | Codepoint | Intended use |
|---|---|---|---|
| `home` | `icon-home.svg` | U+F116 | Generic home action — currently unused but reserved |
| `course` | `icon-course.svg` | U+F124 | Course tab in bottom nav, course-related list rows |
| `history` | `icon-history.svg` | U+F117 | History tab in bottom nav |
| `profile` | `icon-profile.svg` | U+F10E | Profile tab in bottom nav |
| `settings` | `icon-settings.svg` | U+F10A | Settings entry from Profile tab, gear icons |
| `back` | `icon-back.svg` | U+F12C | Back button in nav bars |
| `chevronLeft` | `icon-chevron-left.svg` | U+F128 | Carousels, paginators, leading affordances |
| `chevronRight` | `icon-chevron-right.svg` | U+F127 | List row trailing chevron, paginators |

### Actions (11)

| Constant | Source SVG | Codepoint | Intended use |
|---|---|---|---|
| `add` | `icon-add.svg` | U+F12D | Add a club, add a hole, add an item |
| `close` | `icon-close.svg` | U+F126 | Dismiss modals, sheets, banners |
| `delete` | `icon-delete.svg` | U+F123 | Destructive remove (shot history, club from bag) |
| `edit` | `icon-edit.svg` | U+F11F | Edit profile, edit shot notes |
| `send` | `icon-send.svg` | U+F10B | Submit feedback, send to caddie |
| `refresh` | `icon-refresh.svg` | U+F10D | Pull-to-refresh fallback, retry actions |
| `lock` | `icon-lock.svg` | U+F111 | Locked features (Pro-only gates) |
| `listen` | `icon-listen.svg` | U+F113 | TTS read-aloud trigger |
| `mic` | `icon-mic.svg` | U+F110 | Voice input trigger |
| `camera` | `icon-camera.svg` | U+F12A | Photo upload (Pro tier hole image analysis) |
| `chat` | `icon-chat.svg` | U+F129 | AI caddie chat entry |

### Status (6)

| Constant | Source SVG | Codepoint | Intended use |
|---|---|---|---|
| `error` | `icon-error.svg` | U+F11D | Error states, failed operations |
| `success` | `icon-success.svg` | U+F107 | Successful operations, checkmarks |
| `warning` | `icon-warning.svg` | U+F103 | Caution states, mild errors |
| `info` | `icon-info.svg` | U+F115 | Informational hints, tooltips, notices |
| `loading` | `icon-loading.svg` | U+F112 | Loading states (alt to `CircularProgressIndicator` for fixed-size slots) |
| `disabled` | `icon-disabled.svg` | U+F122 | Disabled-state indicators |

### Golf-specific (20)

| Constant | Source SVG | Codepoint | Intended use |
|---|---|---|---|
| `flag` | `icon-flag.svg` | U+F11B | Pin / hole flag — used on map markers and hole list rows |
| `pinTarget` | `icon-pin-target.svg` | U+F10F | Distance-to-pin indicator |
| `target` | `icon-target.svg` | U+F106 | Generic targeting / aim point |
| `dogleg` | `icon-dogleg.svg` | U+F120 | Hole shape indicator (dogleg left/right) |
| `golfer` | `icon-golfer.svg` | U+F11A | Player position marker, golfer profile |
| `club` | `icon-club.svg` | U+F125 | Club selection, bag entry |
| `tee` | `icon-tee.svg` | U+F105 | Tee box, tee selection |
| `fairway` | `icon-fairway.svg` | U+F11C | Lie type indicator (fairway) |
| `rough` | `icon-rough.svg` | U+F10C | Lie type indicator (rough) |
| `bunker` | `icon-bunker.svg` | U+F12B | Bunker / sand hazard |
| `water` | `icon-water.svg` | U+F102 | Water hazard, lake |
| `hazard` | `icon-hazard.svg` | U+F118 | Generic hazard indicator |
| `lie` | `icon-lie.svg` | U+F114 | Lie input field icon |
| `slope` | `icon-slope.svg` | U+F109 | Slope condition input |
| `elevation` | `icon-elevation.svg` | U+F11E | Elevation change indicator |
| `distance` | `icon-distance.svg` | U+F121 | Distance input field, yardage display |
| `wind` | `icon-wind.svg` | U+F101 | Wind condition input, wind direction overlay |
| `stance` | `icon-stance.svg` | U+F108 | Stance condition input |
| `tempo` | `icon-tempo.svg` | U+F104 | Swing tempo indicator |
| `green` | `icon-green.svg` | U+F119 | Green location, putting indicator |

## Regeneration

The icon font is generated from the SVG source set. To add, remove, or modify icons:

1. **Update the source set** at `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/`. SVGs only — single-color glyphs, no multi-color or gradient elements (icon fonts can't represent those).
2. **Mirror the change** into `mobile-flutter/assets/icons-source/` so the in-tree source matches the source-of-truth dir.
3. **Re-run fantasticon:**
   ```bash
   npx -y fantasticon /home/apatel/Caddie-AI-Iconagraphy/caddieai-icons \
     -o ~/caddieai-font \
     --name CaddieIcons \
     -t ttf \
     -g json html
   ```
4. **Copy the new font into the scaffold:**
   ```bash
   cp ~/caddieai-font/CaddieIcons.ttf mobile-flutter/assets/fonts/CaddieIcons.ttf
   ```
5. **Update `lib/core/icons/caddie_icons.dart`** with the new icon name(s) + codepoint(s) from `~/caddieai-font/CaddieIcons.json`. Add to the appropriate category section AND to the `all` map at the bottom.
6. **Update this doc** with the new icon row(s) in the table above.
7. **Add a unit test entry** in `test/caddie_icons_test.dart` if you've changed the count assertion.
8. **Run tests:**
   ```bash
   flutter analyze && flutter test
   ```

If fantasticon assigns a different codepoint to an existing icon (which shouldn't happen — its assignment is deterministic on the input set — but could on certain edits), update both `caddie_icons.dart` and this doc to keep them in sync.

## License

The icon set is the property of CaddieAI / the project owner. The runtime font file (`assets/fonts/CaddieIcons.ttf`) and the in-tree source SVGs (`assets/icons-source/`) are committed under the same license as the rest of the repo.
