# CaddieAI Cross-Platform Design System

> **Last updated**: 2026-04-06
> **Epic**: KAN-88 — Standardize Cross-Platform UI
> **Complements**: `android/design-tokens.json` (colors, typography, spacing, icons)

This document defines the **structural layout** of every screen — what sections exist, what they're called, what they contain, and in what order. It is the single source of truth for UI consistency between iOS and Android.

---

## Instructions for AI Agents

**Read this document before implementing any UI feature.**

### Before you code:
1. Check the screen-by-screen definitions below for where your feature belongs
2. Use the **exact section header strings** listed here — do not invent new names
3. If the feature doesn't fit an existing section, **update this document first** (in the same commit) before implementing
4. Reference `android/design-tokens.json` for colors, typography, spacing, and icon mappings

### Decision tree for new features:

| If the feature is... | It goes in... |
|-----------------------|---------------|
| A user-facing toggle (Scorecard, Image Analysis, etc.) | "Features" section on Profile screen |
| A developer/debug control | "Settings" section on Profile screen, inside `#if DEBUG` / `BuildConfig.DEBUG` |
| A navigation link to a sub-screen | Headerless nav section on Profile screen |
| Related to club/bag configuration | Your Bag screen |
| A swing/shot preference | Swing Info screen |
| An API key, subscription, or telemetry control | API Settings screen |
| A new input for the shot advisor | Caddie screen |

### When you add or change UI:
- Update this document in the same commit
- If you add a new section header to any screen, add it to the naming table below

---

## App Navigation Structure

```
Tab Bar
  |-- Caddie    -> ShotInputView (iOS) / CaddieScreen (Android)
  |-- Course    -> CourseSearchView (iOS) / CourseScreen (Android)
  |-- History   -> ShotHistoryView (iOS) / HistoryScreen (Android)
  |-- Profile   -> ProfileView (iOS) / ProfileScreen (Android)

Profile sub-screens:
  |-- Your Bag              (YourBagView / YourBagScreen)
  |-- Swing Info            (SwingInfoView / SwingInfoScreen)
  |-- Tee Box Preference    (TeeBoxPreferenceView / TeeBoxPreferenceScreen)
  |-- API Settings          (APISettingsView / ApiSettingsScreen)
  |-- Contact Info          (ContactInfoView / ContactInfoScreen)

Course sub-screens:
  |-- Course Map            (CourseMapView / CourseMapScreen)
  |-- Course Detail         (CourseDetailView / —)
```

---

## Screen-by-Screen Section Definitions

### Profile Screen

This is the primary source of cross-platform inconsistency. Follow this layout exactly.

| Order | Section Header | Contents | Platform Notes |
|-------|---------------|----------|----------------|
| 1 | "Player Info" | Handicap (number input), Miss Tendency (picker), Default Aggressiveness (picker) | |
| 2 | "Caddie Voice & Personality" | Accent (picker), Voice/Gender (picker), Personality (picker with descriptions) | |
| 3 | *(no header)* | Navigation links: Your Bag, Swing Info, Tee Box Preference | iOS: headerless `Section`. Android: `Column` of `NavLinkRow` cards |
| 4 | "Features" | Enable Scorecard toggle, Image Analysis toggle (Pro tier only) | Feature toggles for user-facing functionality. Not "Scoring", not "Settings" |
| 5 | "Settings" | API Settings navigation link, debug toggles (`DEBUG` only) | Only developer/technical controls |
| 6 | *(no header)* | Contact Info navigation link | |

**Rules:**
- All user-facing feature toggles go in "Features" (order 4), never in "Settings"
- "Settings" is reserved for API configuration links and debug-only controls
- The nav links section (order 3) has no visible header on either platform

---

### Your Bag Screen

| Order | Section Header | Contents | Platform Notes |
|-------|---------------|----------|----------------|
| 1 | "Clubs (N/13)" | Club list with editable carry distances, swipe-to-delete | Header shows dynamic count. Footer: "Swipe left on a club to remove it." |
| 2 | *(conditional)* | Add Club action | iOS: Button in a Section. Android: FloatingActionButton. Only shown when bag is not full |
| 3 | *(no header)* | Game Improvement Irons toggle | Toggle with sub-type text (GI/SGI). Footer explains impact on caddie recommendations |

---

### Swing Info Screen

| Order | Section Header | Contents |
|-------|---------------|----------|
| 1 | "Shot Shape" | Woods stock shape (picker), Irons stock shape (picker), Hybrids stock shape (picker) |
| 2 | "Tendencies" | Miss Tendency, Bunker Confidence, Wedge Confidence, Preferred Chip Style, Swing Tendency |

**Note:** Stock shapes must be per-category (woods, irons, hybrids) — not a single picker.

---

### Tee Box Preference Screen

| Order | Contents |
|-------|----------|
| 1 | "Average Driving Distance" — number input with "yds" suffix |
| 2 | "Or Choose a Tier" — selectable tier list (Long Hitter through Short Hitter) |
| 3 | "Ideal Course Yardage" — computed display (driving distance x 28) |
| 4 | Footer: explanatory text about auto-selection behavior |

---

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

Features that exist on one platform but not the other. Use this to track what needs catching up.

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
