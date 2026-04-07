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
| Section | Contents |
|---|---|
| Provider + Key | AI Provider dropdown, API key field |
| LLM Model | Model picker (gpt-4o, claude-sonnet, etc.) |
| Subscription | Tier display |
| Telemetry | Share Usage Data toggle |

## Feature Parity Checklist

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
