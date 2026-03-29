# CaddieAI

An AI-powered golf caddie for iOS. Get real-time club recommendations, tee shot strategy, and hole analysis — all powered by LLMs and open course data.

## Features

- **AI Hole Analysis** — Stand on the tee and get a caddie-style recommendation: what club to hit, where to aim, and what to avoid. Factors in wind, elevation, and your personal tendencies.
- **Shot Advisor** — Mid-round advice using your player profile, lie, and conditions.
- **Course Maps** — Interactive Mapbox-powered maps with hole outlines sourced from OpenStreetMap.
- **Voice I/O** — Ask your caddie questions by voice; hear advice spoken back with configurable accent and gender.
- **GPS Location** — See your position on the course map in real time.
- **Tee Box Selection** — Choose your tees and get yardages specific to your playing distance.
- **Player Profile** — Set your handicap, club distances, shot shape, and tendencies so recommendations are personalized.
- **Weather-Aware** — Pulls current conditions and adjusts club selection for wind and temperature.

## Requirements

- iOS 17+
- Xcode 16+
- A free [Mapbox](https://www.mapbox.com/) access token
- An LLM API key from **one** of:
  - [OpenAI](https://platform.openai.com/api-keys)
  - [Anthropic / Claude](https://console.anthropic.com/settings/keys)
  - [Google Gemini](https://aistudio.google.com/apikey)

Or subscribe to **CaddieAI Pro** ($4.99/mo) to skip the API key — the app routes through a hosted proxy with no key required.

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/oshelot/Caddie-AI.git
cd Caddie-AI
```

### 2. Add your API tokens

Create a file at `CaddieAI/Secrets.plist` (this path is gitignored):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>MapboxAccessToken</key>
    <string>YOUR_MAPBOX_TOKEN_HERE</string>
    <key>GolfCourseApiKey</key>
    <string>YOUR_GOLF_COURSE_API_KEY_HERE</string>
</dict>
</plist>
```

- **Mapbox** — free public access token from [mapbox.com](https://www.mapbox.com/)
- **Golf Course API** — optional, enriches courses with scorecard data (par, yardages, slope/rating). Get a key at [golfcourseapi.com](https://golfcourseapi.com/)

### 3. Open in Xcode

```bash
open CaddieAI.xcodeproj
```

The project uses Swift Package Manager. Xcode will resolve dependencies automatically.

### 4. Configure an LLM provider

Launch the app, go to **Settings > API Settings**, select your LLM provider (OpenAI, Claude, or Gemini), and paste your API key.

### 5. Build and run

Select an iOS 17+ simulator or device and hit **Cmd+R**.

## Project Structure

```
CaddieAI/
├── Models/          # Data models (PlayerProfile, CourseModel, HoleModel, etc.)
├── Services/        # LLM clients, course data, weather, TTS, speech recognition
├── ViewModels/      # CourseViewModel, HoleAnalysisViewModel, ShotAdvisorViewModel
├── Views/
│   ├── CourseTab/   # Course search, map, hole detail, Mapbox integration
│   └── ...          # Profile, shot input, recommendations, settings
└── Configuration/   # StoreKit config, secrets
```

## Free vs Pro

| Feature | Free (BYOK) | Pro ($4.99/mo) |
|---|---|---|
| Hole analysis | Your own API key | Hosted proxy, no key needed |
| LLM provider | OpenAI, Claude, or Gemini | GPT-4o-mini via proxy |
| Course maps | Included | Included |
| Voice caddie | Included | Included |
| GPS location | Included | Included |

## Tech Stack

- **SwiftUI** — UI framework
- **Mapbox Maps SDK** — Course map rendering and GPS puck
- **OpenStreetMap / Overpass API** — Open course geometry data
- **AVFoundation** — Text-to-speech and speech recognition
- **StoreKit 2** — In-app subscription management
- **Open-Meteo** — Current weather conditions for club adjustments

## License

Apache 2.0 — see [LICENSE](LICENSE).
