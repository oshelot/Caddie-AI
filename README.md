# CaddieAI

A personal iOS golf caddie app that combines deterministic golf logic with AI (OpenAI, Claude, or Gemini) to deliver club recommendations, target strategy, and shot execution guidance on the course.

## Features

### Shot Advisor
- Enter distance, shot type, lie, wind, slope, and hazard notes
- Deterministic engine calculates effective distance, wind/lie/slope adjustments, and selects the optimal club
- AI enriches recommendations with target strategy, risk assessment, and natural caddie-style phrasing
- Supports OpenAI (GPT-4o, GPT-4o mini, GPT-4 Turbo), Anthropic Claude (Sonnet, Haiku), and Google Gemini (2.0 Flash, 1.5 Pro)
- Falls back to deterministic-only analysis when the LLM is unavailable

### Execution Guidance
- 15 shot archetypes (bump & run, standard chip, bunker explosion, stock full swing, knockdown, etc.)
- Setup cues: ball position, weight distribution, stance width, alignment, clubface, shaft lean
- Swing cues: backswing length, follow-through, tempo, strike intention
- Swing thought and common mistake to avoid for each shot

### Course Map & Hole Analysis
- Search for courses via the Golf Course API and view interactive Mapbox satellite maps
- Tap a hole to zoom the camera to its geometry (tees, fairway, green, bunkers, water)
- AI-powered hole analysis with strategy breakdown and audio playback
- Follow-up questions for deeper hole-specific advice

### Voice & Image Input
- Voice recording via Apple Speech framework — transcribed notes are sent to the LLM
- Photo attachment for lie/stance analysis (sent as base64 JPEG to the active LLM's vision API)
- Text-to-speech reads recommendations and hole analysis aloud on the course
- Follow-up conversation with quick question chips and free-text input

### Customizable Club Bag
- Choose from 30+ clubs: woods, hybrids, irons, and degree wedges (46°–64°)
- Add and remove clubs with a 13-club bag limit
- Set custom carry distances for each club
- Bag auto-sorts by distance (longest first)

### Personalization
- Player profile: handicap, stock shape, miss tendency
- Short game preferences: bunker confidence, wedge confidence, preferred chip style, swing tendency
- Execution templates adapt based on player preferences (e.g., extra encouragement for low bunker confidence)
- Profile persisted via UserDefaults

### Real-Time Weather
- Fetches current conditions (temperature, wind speed/direction, precipitation) via Open-Meteo
- Wind direction calculated relative to the hole for accurate shot adjustments

### Shot History & Learning
- Every recommendation is automatically saved to history
- Log shot outcomes (great/good/okay/poor/mishit) and actual club used
- History view with detail editing and swipe-to-delete
- Learning engine analyzes club override patterns, outcome averages, and usage frequency
- Historical insights are fed into the LLM prompt so recommendations improve over time

### API Usage Tracking
- Tracks LLM token consumption (prompt, completion, total) per call across all providers
- Monitors Golf Course API usage with configurable monthly rate limit (default 300 calls)
- View stats and reset usage data from the API Settings page

### Telemetry
- Anonymous usage telemetry (API call counts, course plays) sent to a serverless backend
- AWS Lambda + API Gateway + S3 infrastructure (CloudFormation template in `infra/`)
- Batched uploads with retry on failure, periodic flush, and flush on app background
- User opt-out toggle in API Settings

## Architecture

```
Models/          Data types (enums, profiles, shot context, recommendations, weather, API usage)
Services/        Golf logic, execution engine, LLM services (OpenAI/Claude/Gemini), router, speech, TTS, weather, course API, cache, telemetry
ViewModels/      ShotAdvisorViewModel, CourseViewModel, HoleAnalysisViewModel
Views/           SwiftUI views (shot input, recommendation, course map, profile, history)
infra/           AWS CloudFormation template and Lambda handler for telemetry backend
```

- **iOS-only** — no backend server; direct LLM API calls via URLSession
- **SwiftUI + @Observable** (iOS 17+)
- **Hybrid approach**: deterministic logic runs first (instant, offline-capable), LLM enriches second
- **UserDefaults** persistence for profile, shot history, and API usage data
- **Mapbox Maps SDK** for satellite course visualization

## Setup

1. Open `CaddieAI.xcodeproj` in Xcode
2. Build and run on an iOS 17+ device or simulator
3. Go to **Profile → API Settings & Usage**, select your AI provider, and paste your API key
4. Add the following privacy keys in Xcode's Info tab (required for voice input):
   - `NSMicrophoneUsageDescription` — "CaddieAI uses the microphone for voice input"
   - `NSSpeechRecognitionUsageDescription` — "CaddieAI uses speech recognition to transcribe voice notes"

## Requirements

- iOS 17.0+
- Xcode 15+
- API key for at least one LLM provider: OpenAI, Anthropic Claude, or Google Gemini
