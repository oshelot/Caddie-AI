# CaddieAI icon set

The CaddieAI app uses a custom 45-icon set rendered via [`flutter_svg`](https://pub.dev/packages/flutter_svg). This doc captures the icon inventory, sizing rules, color tinting, and the regeneration process. Decision rationale is in [ADR 0007](../adr/0007-icon-rendering-flutter-svg.md). The previous icon-font attempt is recorded in [ADR 0006 (Superseded)](../adr/0006-icon-rendering-strategy.md). Enforceable usage rule is **CONVENTIONS C-6**.

## How to use

Always import `CaddieIcons` and call the named helper:

```dart
import 'package:caddieai/core/icons/caddie_icons.dart';

CaddieIcons.flag()                                       // default 24 dp, original SVG color
CaddieIcons.flag(size: 32)                               // sized
CaddieIcons.flag(size: 24, color: Colors.greenAccent)    // sized + tinted
CaddieIcons.flag(
  size: 20,
  color: Theme.of(context).colorScheme.primary,
)                                                        // theme-tinted (preferred)
```

For dynamic / data-driven cases:

```dart
CaddieIcons.byName('flag', size: 24)                     // throws ArgumentError if unknown
```

**Never:**

```dart
Icon(Icons.flag)                                          // ❌ Material default
SvgPicture.asset('assets/icons/icon-flag.svg')            // ❌ bypasses the registry
Image.asset('assets/icons/icon-flag.png')                 // ❌ raw bitmap (and there's no PNG anyway)
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

Unlike Material's `Icon` widget (which inherits from `IconTheme`), `flutter_svg` requires an explicit `color:` argument when you want the icon tinted. Without `color:`, the icon renders in its source SVG color (which is `#000` for all 45 icons in this set — black on whatever background the parent provides).

```dart
// Theme color (preferred — adapts to dark mode automatically)
CaddieIcons.flag(size: 24, color: Theme.of(context).colorScheme.primary)

// Status color from the theme
CaddieIcons.error(size: 20, color: Theme.of(context).colorScheme.error)

// Untinted (renders in the SVG's source color, currently black)
CaddieIcons.flag(size: 24)
```

**Never hardcode a hex literal at the call site:**

```dart
CaddieIcons.flag(size: 24, color: Color(0xFFFF0000))   // ❌ no theme awareness
```

If you genuinely need a non-theme color (e.g. an in-map overlay where the color is data-driven, not theme-driven), pass it explicitly with a comment explaining why the theme path doesn't fit.

### How tinting works under the hood

`CaddieIcons.flag(color: c)` translates to:

```dart
SvgPicture.asset(
  'assets/icons/icon-flag.svg',
  width: size,
  height: size,
  colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
)
```

`BlendMode.srcIn` means "use the source (`c`) color wherever the destination (the rendered SVG) is opaque". Since the SVGs are stroked black-on-transparent, the result is the stroke painted in `c` instead of `#000`. The transparent areas stay transparent.

## Padding and spacing

| Context | Padding |
|---|---|
| Icon-only button | 8 dp around the icon (so a 24 dp icon → 40 dp button hit target) |
| Icon + text label (horizontal) | 4 dp spacing between icon and text |
| Icon + text label (vertical, e.g. tab bar) | 2 dp spacing |
| Icon as list-row leading | 16 dp leading inset, 12 dp trailing to text |

## The 45 icons

All paths under `assets/icons/`. Asset filename convention: `icon-{kebab-case-name}.svg`. The Dart helper name is the camelCase version (e.g. `chevron-left.svg` → `CaddieIcons.chevronLeft`).

### Navigation (8)

| Helper | Source SVG | Intended use |
|---|---|---|
| `home` | `icon-home.svg` | Generic home action — currently unused but reserved |
| `course` | `icon-course.svg` | Course tab in bottom nav, course-related list rows |
| `history` | `icon-history.svg` | History tab in bottom nav |
| `profile` | `icon-profile.svg` | Profile tab in bottom nav |
| `settings` | `icon-settings.svg` | Settings entry from Profile tab, gear icons |
| `back` | `icon-back.svg` | Back button in nav bars |
| `chevronLeft` | `icon-chevron-left.svg` | Carousels, paginators, leading affordances |
| `chevronRight` | `icon-chevron-right.svg` | List row trailing chevron, paginators |

### Actions (11)

| Helper | Source SVG | Intended use |
|---|---|---|
| `add` | `icon-add.svg` | Add a club, add a hole, add an item |
| `close` | `icon-close.svg` | Dismiss modals, sheets, banners |
| `delete` | `icon-delete.svg` | Destructive remove (shot history, club from bag) |
| `edit` | `icon-edit.svg` | Edit profile, edit shot notes |
| `send` | `icon-send.svg` | Submit feedback, send to caddie |
| `refresh` | `icon-refresh.svg` | Pull-to-refresh fallback, retry actions |
| `lock` | `icon-lock.svg` | Locked features (Pro-only gates) |
| `listen` | `icon-listen.svg` | TTS read-aloud trigger |
| `mic` | `icon-mic.svg` | Voice input trigger |
| `camera` | `icon-camera.svg` | Photo upload (Pro tier hole image analysis) |
| `chat` | `icon-chat.svg` | AI caddie chat entry |

### Status (6)

| Helper | Source SVG | Intended use |
|---|---|---|
| `error` | `icon-error.svg` | Error states, failed operations |
| `success` | `icon-success.svg` | Successful operations, checkmarks |
| `warning` | `icon-warning.svg` | Caution states, mild errors |
| `info` | `icon-info.svg` | Informational hints, tooltips, notices |
| `loading` | `icon-loading.svg` | Loading states (alt to `CircularProgressIndicator` for fixed-size slots) |
| `disabled` | `icon-disabled.svg` | Disabled-state indicators |

### Golf-specific (20)

| Helper | Source SVG | Intended use |
|---|---|---|
| `flag` | `icon-flag.svg` | Pin / hole flag — used on map markers and hole list rows |
| `pinTarget` | `icon-pin-target.svg` | Distance-to-pin indicator |
| `target` | `icon-target.svg` | Generic targeting / aim point |
| `dogleg` | `icon-dogleg.svg` | Hole shape indicator (dogleg left/right) |
| `golfer` | `icon-golfer.svg` | Player position marker, golfer profile |
| `club` | `icon-club.svg` | Club selection, bag entry |
| `tee` | `icon-tee.svg` | Tee box, tee selection |
| `fairway` | `icon-fairway.svg` | Lie type indicator (fairway) |
| `rough` | `icon-rough.svg` | Lie type indicator (rough) |
| `bunker` | `icon-bunker.svg` | Bunker / sand hazard |
| `water` | `icon-water.svg` | Water hazard, lake |
| `hazard` | `icon-hazard.svg` | Generic hazard indicator |
| `lie` | `icon-lie.svg` | Lie input field icon |
| `slope` | `icon-slope.svg` | Slope condition input |
| `elevation` | `icon-elevation.svg` | Elevation change indicator |
| `distance` | `icon-distance.svg` | Distance input field, yardage display |
| `wind` | `icon-wind.svg` | Wind condition input, wind direction overlay |
| `stance` | `icon-stance.svg` | Stance condition input |
| `tempo` | `icon-tempo.svg` | Swing tempo indicator |
| `green` | `icon-green.svg` | Green location, putting indicator |

## Regeneration

The icon set is rendered directly from the source SVGs at runtime — there is no codegen / font generation step. To add, remove, or modify icons:

1. **Update the source set** at `/home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/`. The SVGs should be:
   - **Stroke-based** (`fill: none; stroke: #000;`) — matches the existing set's style
   - **24 × 24 viewBox** — the standard mobile icon canvas
   - **Single-color** (black strokes) — flutter_svg can recolor at runtime via `colorFilter`, but the source should be neutral
2. **Mirror the change** into `mobile-flutter/assets/icons/`:
   ```bash
   cp /home/apatel/Caddie-AI-Iconagraphy/caddieai-icons/icon-newicon.svg \
     mobile-flutter/assets/icons/
   ```
3. **Update `lib/core/icons/caddie_icons.dart`**:
   - Add an entry to the `_paths` map (camelCase name → asset path)
   - Add a named static getter that delegates to `_render('newName', size, color)`
   - Place both in the appropriate category section (Navigation / Actions / Status / Golf-specific)
4. **Update this doc** with the new icon row in the table above.
5. **Update the registry test count** in `test/caddie_icons_test.dart` if you've added or removed icons (the `hasLength(45)` assertion).
6. **Run tests**:
   ```bash
   flutter analyze && flutter test
   ```
7. **Visual verification**: re-flash the scaffold on a device and confirm the new icon renders in the smoke test (you'll need to add it to `lib/app.dart`'s smoke test row temporarily, OR run KAN-271 onward where real screens use the new icon).

## Removing an icon

1. Delete the SVG from `mobile-flutter/assets/icons/` and from the source-of-truth dir
2. Remove the entry from `_paths`
3. Remove the named getter
4. Update the count in the registry test
5. Update this doc — remove the row, decrement the category count
6. Update `pubspec.yaml` if removing the last icon (which would be weird)

## License

The icon set is the property of CaddieAI / the project owner. The runtime SVGs (`assets/icons/`) are committed under the same license as the rest of the repo. The source `.ai` (Adobe Illustrator) file in `/home/apatel/Caddie-AI-Iconagraphy/Files/` is the design source-of-truth.
