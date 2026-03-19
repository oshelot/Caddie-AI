# CaddieAI

A personal iOS golf caddie app that combines deterministic golf logic with OpenAI GPT-4o to deliver club recommendations, target strategy, and shot execution guidance on the course.

## Features

### Shot Advisor
- Enter distance, shot type, lie, wind, slope, and hazard notes
- Deterministic engine calculates effective distance, wind/lie/slope adjustments, and selects the optimal club
- GPT-4o enriches recommendations with target strategy, risk assessment, and natural caddie-style phrasing
- Falls back to deterministic-only analysis when the LLM is unavailable

### Execution Guidance
- 15 shot archetypes (bump & run, standard chip, bunker explosion, stock full swing, knockdown, etc.)
- Setup cues: ball position, weight distribution, stance width, alignment, clubface, shaft lean
- Swing cues: backswing length, follow-through, tempo, strike intention
- Swing thought and common mistake to avoid for each shot

### Voice & Image Input
- Voice recording via Apple Speech framework — transcribed notes are sent to the LLM
- Photo attachment for lie/stance analysis (sent as base64 JPEG to GPT-4o vision)
- Text-to-speech reads recommendations aloud on the course
- Follow-up conversation with quick question chips and free-text input

### Personalization
- Player profile: handicap, stock shape, miss tendency, club carry distances
- Short game preferences: bunker confidence, wedge confidence, preferred chip style, swing tendency
- Execution templates adapt based on player preferences (e.g., extra encouragement for low bunker confidence)
- Profile persisted via UserDefaults

### Shot History & Learning
- Every recommendation is automatically saved to history
- Log shot outcomes (great/good/okay/poor/mishit) and actual club used
- History view with detail editing and swipe-to-delete
- Learning engine analyzes club override patterns, outcome averages, and usage frequency
- Historical insights are fed into the LLM prompt so recommendations improve over time

## Architecture

```
Models/          Data types (enums, profiles, shot context, recommendations, history)
Services/        Golf logic engine, execution engine, OpenAI API, speech, TTS
ViewModels/      ShotAdvisorViewModel (coordinates logic + API + state)
Views/           SwiftUI views (input, recommendation, history, profile)
```

- **iOS-only** — no backend server; direct OpenAI API calls via URLSession
- **SwiftUI + @Observable** (iOS 17+)
- **Hybrid approach**: deterministic logic runs first (instant, offline-capable), LLM enriches second
- **UserDefaults** persistence for profile and shot history

## Setup

1. Open `CaddieAI.xcodeproj` in Xcode
2. Build and run on an iOS 17+ device or simulator
3. Go to the **Profile** tab and paste your OpenAI API key
4. Add the following privacy keys in Xcode's Info tab (required for voice input):
   - `NSMicrophoneUsageDescription` — "CaddieAI uses the microphone for voice input"
   - `NSSpeechRecognitionUsageDescription` — "CaddieAI uses speech recognition to transcribe voice notes"

## Requirements

- iOS 17.0+
- Xcode 15+
- OpenAI API key (GPT-4o)
