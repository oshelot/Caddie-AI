# CaddieAI Design System

Cross-platform design system for iOS and Android. See `android/design-tokens.json` for styling tokens.

## Screen Structure

### Profile Screen
| Section | Type | Contents |
|---|---|---|
| Player Info | ElevatedCard | Handicap, Miss Tendency, Aggressiveness |
| Caddie Voice & Personality | ElevatedCard | Accent, Voice, Personality |
| Nav Links | NavLinkRow list | Your Bag, Swing Info, Tee Box Preference |
| Features | ElevatedCard | Enable Scorecard toggle, Image Analysis (Beta) toggle (Pro only) |
| Settings | ElevatedCard | API Settings nav link, Debug toggles (DEBUG only) |
| Contact Info | NavLinkRow standalone | Feedback / contact |

### Your Bag Screen
| Section | Contents |
|---|---|
| Club list | Swipe-to-delete, tap distance to edit, 13-club limit |
| Game Improvement Irons | Toggle + sub-type dialog (Regular/Super) + footer text |

### Swing Info Screen
| Section | Contents |
|---|---|
| Shot Shape | Woods, Irons, Hybrids — per-category stock shape pickers |
| Tendencies | Miss Tendency, Swing Tendency, Bunker Confidence, Wedge Confidence, Chip Style |

### Tee Box Preference Screen
| Section | Contents |
|---|---|
| Tee selector | 5-tier radio: Championship/Black, Blue, White, Gold/Silver, Red/Forward |
| Keyword matching | Auto-selects course tee by matching keywords against tee names |

### API Settings Screen
| Order | Section Header | Contents | Visibility |
|-------|---------------|----------|------------|
| 1 | "Subscription" | Tier display, upgrade/restore buttons | Always |
| 2 | "AI Provider" | Provider picker, model picker | Free tier only |
| 3 | "[Provider] API Key" | Key display with show/hide, paste, clear | Free tier only |
| 4 | "AI Configuration" | Managed model info | Paid tier only |
| 5 | "Telemetry" | Share Usage Data toggle | Always |
| 6 | "API Usage" | Token counts, rate limits, reset button | Always |

---

### Caddie Screen (Shot Input)

| Order | Section/Group | Contents |
|-------|--------------|----------|
| 1 | "Quick Input" | Voice recording button, photo picker (Pro+Beta), transcription field |
| 2 | "Shot Setup" | Distance (yards), Shot Type picker |
| 3 | "Conditions" | Lie, Wind Strength (with Live Weather button), Wind Direction, Slope |
| 4 | "Strategy" | Aggressiveness control, Hazard notes text field |
| 5 | Action | "Ask Caddie" button |

---

### Course Map Screen

Non-form UI — uses map overlays and floating controls.

| Element | Contents | Position |
|---------|----------|----------|
| Tee selector | Menu/dropdown with tee names + yardages | Top toolbar / top-right |
| Location button | Toggle user location on/off | Top-right overlay |
| Hole selector | "All" + numbered hole buttons in horizontal scroll | Bottom |
| Tap-to-distance | Distance + club recommendation label | Bottom overlay, above hole selector |
| Action buttons | "Ask Caddie" (green), "Analyze" (blue) | Below info bar |

---

### Contact Info Screen

| Order | Section Header | Contents |
|-------|---------------|----------|
| 1 | *(no header)* | Introductory text explaining purpose |
| 2 | "Your Info" | Name, Email, Phone fields |
| 3 | *(no header)* | Submit/Update button |
| 4 | *(conditional)* | "Remove My Info" destructive button (only when saved) |

---

### Shot History Screen

| Order | Contents |
|-------|----------|
| 1 | History list (club, distance, type, outcome) or empty state |

---

## Naming Conventions

These are the **exact strings** to use for section headers. Both platforms must match.

| Canonical Header | iOS | Android |
|-----------------|-----|---------|
| "Player Info" | `Section("Player Info")` | `Text("Player Info")` in card |
| "Caddie Voice & Personality" | `Section("Caddie Voice & Personality")` | `Text("Caddie Voice & Personality")` in card |
| "Features" | `Section("Features")` | `Text("Features")` in card |
| "Settings" | `Section("Settings")` | `Text("Settings")` in card |
| "Shot Shape" | `Section("Shot Shape")` | Section header text |
| "Tendencies" | `Section("Tendencies")` | Section header text |
| "Subscription" | `Section("Subscription")` | Section header text |
| "AI Provider" | `Section("AI Provider")` | Section header text |
| "Telemetry" | `Section("Telemetry")` | Section header text |
| "API Usage" | `Section("API Usage")` | Section header text |
| "Your Info" | `Section("Your Info")` | Section header text |
| "Quick Input" | GroupBox/Section | Card header text |
| "Shot Setup" | GroupBox/Section | Card header text |
| "Conditions" | GroupBox/Section | Card header text |
| "Strategy" | GroupBox/Section | Card header text |

---

## Component Patterns

### Toggles
- Label text on the **left**, switch/toggle on the **right**
- Optional sub-text below the label in caption/secondary style
- Footer text below the toggle explaining its effect (when non-obvious)

### Navigation Links
- iOS: `NavigationLink` with `Label(text, systemImage:)`
- Android: `NavLinkRow` with icon, title, optional subtitle, chevron
- Always use platform-standard disclosure indicators

### Pickers / Dropdowns
- iOS: `Picker` with `.automatic` style (inline in Form)
- Android: `OutlinedTextField` + `DropdownMenu` (ProfileDropdown composable)

### Footer / Description Text
- iOS: `Section { } footer: { Text("...") }` — system caption styling
- Android: `Text(style = bodySmall, color = onSurfaceVariant)` below the card

### Buttons
- Primary action: iOS `.borderedProminent` / Android filled `Button`
- Destructive: iOS `Button(role: .destructive)` / Android red text button

---

## Styling Guidance

For **low-level styling** (colors, typography, spacing, corner radii, icons), see `android/design-tokens.json`. Both platforms should reference those tokens.

**Section headers:** Use platform default styling. iOS Form auto-styles headers. Android uses `titleSmall` + `SemiBold` + `primary` color.

**Section containers:** iOS uses `Section` inside `Form` (system-managed grouping). Android uses `ElevatedCard` with `CaddieShape.large` (16dp corners) and `Column` content.

These structural differences are **expected and acceptable** — they follow platform conventions.

---

## Iconography

CaddieAI uses a custom SVG icon library to ensure visual consistency across iOS and Android. All 45 icons are designed on a **24×24px grid** with **1.5px stroke**, **outline-only style**, and **`currentColor` fill** so they inherit the platform tint.

### Asset Specifications

| Property | Value |
|----------|-------|
| Grid | 24×24px, 2px padding (20×20 live area) |
| Stroke | 1.5px, round cap, round join |
| Style | Outline only — no filled variants |
| Color | `currentColor` (inherits from tint/theme) |
| Export | SVG, one file per icon |

### Platform Integration

| Aspect | iOS | Android |
|--------|-----|---------|
| Asset location | `Assets.xcassets` as template images | `res/drawable/` as `VectorDrawable` |
| Constants file | `AppIcons.swift` — static `Image` properties | `CaddieIcons.kt` — `ImageVector` or `@Composable` helpers |
| Rendering mode | `.renderingMode(.template)` | `tint = LocalContentColor.current` |
| Reference style | `AppIcons.golfSwing` | `CaddieIcons.GolfSwing` |

**Rule:** Always reference icons through the constants file. Never use raw SF Symbols or Material Icons for anything that has a custom equivalent.

### Icon Catalog

#### Golf Swing / Strategy

| Icon Name | Replaces (iOS) | Replaces (Android) | Usage |
|-----------|----------------|-------------------|-------|
| `golf-swing` | `figure.golf` | `Icons.Filled.SmartToy` | Caddie tab, Ask Caddie button, recommendations, execution plan |
| `golf-bag` | `bag.fill` | `Icons.Default.GolfCourse` (in Profile) | Your Bag nav link, bag reminder |
| `golf-flag` | `flag.fill` | `Icons.Default.Flag` | Hole par indicator, tee selector, course map overlays |
| `golf-tee` | — | — | Tee Box Preference nav link and screen |
| `golf-ball` | — | `Icons.Default.SportsGolf` | Swing Info nav link |
| `target` | `target` | — | Recommended target in shot advice |
| `wind` | `wind` | — | Wind condition indicator on course map |
| `slope-uphill` | — | — | Uphill slope indicator in shot conditions |
| `slope-downhill` | — | — | Downhill slope indicator in shot conditions |
| `hazard-warning` | `exclamationmark.triangle(.fill)` | — | Error/warning states, hazard alerts |
| `distance-marker` | `ruler` | — | Yardage/distance measurement on course map |

#### Golf Surface / Course

| Icon Name | Usage |
|-----------|-------|
| `fairway` | Lie picker — fairway |
| `rough` | Lie picker — rough |
| `bunker` | Lie picker — bunker/sand |
| `green` | Lie picker — on the green |
| `water` | Lie picker — water hazard |
| `tree-line` | Hazard context — tree-lined |

These are **net-new** icons for the lie picker on the Caddie screen (ShotInputView / CaddieScreen). No existing system icons to replace.

#### Core Interaction

| Icon Name | Replaces (iOS) | Replaces (Android) | Usage |
|-----------|----------------|-------------------|-------|
| `microphone` | `mic` | `Icons.Default.Mic` | Voice input active |
| `microphone-off` | — | `Icons.Default.MicOff` | Voice input inactive |
| `camera` | `camera.circle.fill` | `Icons.Default.Photo` | Photo capture in shot input |
| `send` | — | `Icons.AutoMirrored.Filled.Send` | Send follow-up question |
| `clipboard` | `doc.on.clipboard` | — | Paste API key |
| `trash` | `trash` | `Icons.Default.Delete` | Delete/remove actions |
| `edit-pencil` | — | — | Edit club distances (net-new) |

#### Navigation / App Structure

| Icon Name | Replaces (iOS) | Replaces (Android) | Usage |
|-----------|----------------|-------------------|-------|
| `home` | — | — | Reserved for future use |
| `map-pin` | `mappin.circle` | `Icons.Default.LocationOn` | Course location indicator |
| `course-map` | `map` | `Icons.Filled.GolfCourse` | Course tab icon |
| `history-clock` | `clock.arrow.trianglehead.counterclockwise.rotate.90` | `Icons.Filled.History` | History tab, empty state |
| `profile-user` | `person.circle` | `Icons.Filled.Person` | Profile tab icon |
| `settings-gear` | `gearshape.2` | `Icons.Default.Settings` | API Settings nav link |
| `search` | — | `Icons.Default.Search` | Course search |
| `star-filled` | `star.fill` | `Icons.Filled.Star` | Favorite course (filled) |
| `star-outline` | `star` | `Icons.Filled.StarBorder` | Favorite course (outline) |

#### System / Navigation Controls

| Icon Name | Replaces (iOS) | Replaces (Android) | Usage |
|-----------|----------------|-------------------|-------|
| `chevron-right` | `chevron.right` | `Icons.AutoMirrored.Filled.KeyboardArrowRight` | Disclosure indicator |
| `chevron-down` | `chevron.up.chevron.down` | `Icons.Default.ArrowDropDown` | Dropdown/expand controls |
| `close-x` | `xmark` / `xmark.circle.fill` | `Icons.Default.Close` | Dismiss/close actions |
| `back-arrow` | *(system-managed)* | `Icons.AutoMirrored.Filled.ArrowBack` | Back navigation (Android only — iOS uses system back) |
| `plus` | `plus.circle` | `Icons.Default.Add` | Add club, add item |

#### Feedback / State

| Icon Name | Replaces (iOS) | Replaces (Android) | Usage |
|-----------|----------------|-------------------|-------|
| `checkmark` | `checkmark` / `checkmark.circle(.fill)` | `Icons.Default.Check` | Selection confirmation |
| `info-circle` | `info.circle(.fill)` | — | Information/detail buttons |
| `speaker-on` | — | `Icons.Default.VolumeUp` | Text-to-speech active |
| `speaker-off` | — | `Icons.Default.StopCircle` / `Stop` | Text-to-speech stopped |

#### Optional Enhancements

| Icon Name | Replaces (iOS) | Replaces (Android) | Usage |
|-----------|----------------|-------------------|-------|
| `crown-pro` | `crown` | — | Pro tier badge |
| `ai-brain` | `brain` / `brain.head.profile` | — | AI model indicator, analysis insights |

### Files Affected by Icon Migration

**iOS** (13 view files + 1 new constants file):

| File | Icons to replace | Count |
|------|-----------------|-------|
| `ContentView.swift` | Tab bar: `golf-swing`, `course-map`, `history-clock`, `profile-user` | 4 |
| `CourseMapView.swift` | `golf-flag`, `distance-marker`, `close-x`, `info-circle`, `checkmark`, `wind`, `golf-swing`, `hazard-warning`, + more | ~12 |
| `ProfileView.swift` | `golf-bag`, `golf-ball`, `golf-tee`, `info-circle`, `settings-gear`, `envelope` (Contact) | 5 |
| `APISettingsView.swift` | `settings-gear`, `crown-pro`, `clipboard`, `trash`, `ai-brain`, + more | 7 |
| `RecommendationView.swift` | `target`, `golf-swing`, `checkmark`, `ai-brain`, `hazard-warning` | 5 |
| `ShotInputView.swift` | `camera`, `checkmark`, `microphone` | 4 |
| `CourseSearchView.swift` | `map-pin`, `star-filled`, `star-outline`, `chevron-right` | 4 |
| `YourBagView.swift` | `plus`, `checkmark` | 2 |
| `SwingOnboardingView.swift` | `golf-swing`, `golf-flag`, `golf-bag` | 3–4 |
| `ExecutionPlanCard.swift` | `golf-swing`, `hazard-warning` | 2 |
| `ShotHistoryView.swift` | `history-clock` | 1 |
| `TeeBoxPreferenceView.swift` | `checkmark` | 1 |
| `BagReminderView.swift` | `golf-bag` | 1 |
| **NEW: `AppIcons.swift`** | Icon constants file | — |

**Android** (12 screen files + 1 new constants file):

| File | Icons to replace | Count |
|------|-----------------|-------|
| `BottomNavItem.kt` | `golf-swing`, `course-map`, `history-clock`, `profile-user` | 4 |
| `CaddieScreen.kt` | `camera`, `microphone`, `microphone-off`, `close-x`, `golf-swing`, `speaker-on`, `speaker-off`, `send`, `chevron-down` | ~10 |
| `CourseScreen.kt` | `search`, `close-x`, `map-pin`, `course-map`, `star-filled`, `star-outline`, `trash` | ~9 |
| `CourseMapScreen.kt` | `back-arrow`, `golf-flag`, `course-map`, `star-filled`, `checkmark`, `close-x`, `send`, `speaker-on`, `speaker-off` | ~9 |
| `ProfileScreen.kt` | `golf-bag`, `golf-ball`, `golf-tee`, `settings-gear`, `chevron-right`, `chevron-down` | ~7 |
| `HistoryScreen.kt` | `back-arrow`, `trash`, `history-clock` | 3 |
| `YourBagScreen.kt` | `back-arrow`, `plus`, `trash` | 3 |
| `FeedbackScreen.kt` | `back-arrow`, `clipboard`, `close-x` | 3 |
| `SwingInfoScreen.kt` | `back-arrow`, `chevron-down` | 2 |
| `ApiSettingsScreen.kt` | `back-arrow`, + visibility icons | 3 |
| `ShotDetailScreen.kt` | `back-arrow`, `chevron-down` | 2 |
| `TeeBoxPreferenceScreen.kt` | `back-arrow` | 1 |
| **NEW: `CaddieIcons.kt`** | Icon constants file | — |

### Implementation Phases

| Phase | Scope | Description |
|-------|-------|-------------|
| 1 | Asset setup | Export 45 SVGs. Add to `xcassets` (iOS) and `res/drawable` (Android). Create `AppIcons.swift` and `CaddieIcons.kt` constants files. |
| 2 | High-impact replacements | Tab bar icons (4), `golf-swing` (14 uses), `golf-flag` (7 uses), `golf-bag` (4 uses), system controls (`close-x`, `checkmark`, `plus`, `trash`) |
| 3 | Golf surface icons | Add lie-type icons to Caddie screen: `fairway`, `rough`, `bunker`, `green`, `water`, `tree-line` |
| 4 | Remaining icons | `slope-uphill/downhill`, `speaker-on/off`, `crown-pro`, `ai-brain`, `send`, `edit-pencil`, `search`, etc. |

---

## Allowed Platform Divergence

| Aspect | iOS | Android | Why OK |
|--------|-----|---------|--------|
| Section grouping | `Form > Section` | `ElevatedCard` + `Column` | Platform-native patterns |
| Header text case | System auto-uppercases in Form | Manual `titleSmall` styling | Platform convention |
| Back navigation | System NavigationStack back button | Manual `IconButton` with back arrow | Platform convention |
| Add Club action | Button in a Section | FloatingActionButton | Material Design convention |
| Selection indicator | Checkmark icon | RadioButton | Platform convention |
| Ad placement | `.safeAreaInset(edge: .bottom)` | `bottomBar` in Scaffold | Platform API |

---

## Feature Parity Checklist

### Completed (both platforms)

| Feature | iOS | Android |
|---|---|---|
| Profile: Player Info card | Done | Done |
| Profile: Caddie Voice card | Done | Done |
| Profile: Features section (Scorecard + Image Analysis) | Done | Done |
| Profile: Settings section (API + Debug) | Done | Done |
| Your Bag: GI Iron toggle + footer | Done | Done |
| Swing Info: Per-category shot shape | Done | Done |
| Tee Box Preference: 5-tier keyword matching | Done | Done |
| API Settings: LLM Model picker | Done | Done |
| API Settings: Subscription section | Done | Done |
| API Settings: Telemetry toggle | Done | Done |
| Course Search: Search/Saved selector | Done | Done |
| Course Search: Favorites + star toggle | Done | Done |
| Course Search: Delete confirmation dialog | Done | Done |
| Course Map: Weather badge | Done | Done |
| Course Map: Tap-to-distance + club recommendation | Done | Done |
| Course Map: Ask Caddie + Analyze buttons | Done | Done |
| Course Map: Tee picker with dedup | Done | Done |
| Shot Detail: Outcome entry with emoji buttons | Done | Done |
| Banner ads on free-tier screens | Done | Done |
| Interstitial ad during course loading | Done | Done |
| Splash: Orbitron wordmark | N/A | Done |

### Remaining gaps

| Feature | iOS | Android | Gap |
|---------|-----|---------|-----|
| Iron Type (GI/SGI) toggle | YourBagView | Missing | Android needs to add |
| Per-category stock shapes (W/I/H) | SwingInfoView | Single picker | Android needs to split |
| Telemetry toggle | APISettingsView | Missing | Android needs to add |
| Subscription management UI | Full StoreKit | BillingService, limited UI | Android needs to expand |
| API Usage stats | APISettingsView | Missing | Android needs to add |
| LLM Model picker | APISettingsView | Missing | Android needs to add |
| Distance-based tee selection | TeeBoxPreferenceView | TeeBoxPreferenceScreen | Verify parity |
| Scorecard toggle | ProfileView "Features" | ProfileScreen "Settings" | Android needs to move to "Features" |
| Image Analysis toggle | ProfileView "Features" | ProfileScreen "Settings" | Android needs to move to "Features" |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-04-06 | Initial version. Defined all screen layouts, naming conventions, component patterns, parity checklist. Created under KAN-88 epic. |
| 2026-04-07 | Added Iconography section: 45-icon catalog with asset specs, platform integration, per-file migration plan, and phased rollout. Expanded design-tokens.json icon mappings. |
