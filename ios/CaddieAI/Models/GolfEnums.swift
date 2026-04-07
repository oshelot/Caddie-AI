//
//  GolfEnums.swift
//  CaddieAI
//

import Foundation

// MARK: - User Tier

enum UserTier: String, CaseIterable, Codable, Identifiable, Sendable {
    case free
    case paid

    var id: Self { self }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .paid: return "Pro"
        }
    }
}

// MARK: - Club

enum Club: String, CaseIterable, Codable, Identifiable, Sendable {
    // Woods
    case driver
    case twoWood
    case threeWood
    case fourWood
    case fiveWood
    case sevenWood
    case nineWood
    // Hybrids
    case hybrid2
    case hybrid3
    case hybrid4
    case hybrid5
    case hybrid6
    // Irons
    case iron2
    case iron3
    case iron4
    case iron5
    case iron6
    case iron7
    case iron8
    case iron9
    // Wedges
    case pitchingWedge
    case wedge46
    case wedge48
    case wedge50
    case gapWedge       // 52°
    case wedge54
    case sandWedge      // 56°
    case wedge58
    case lobWedge       // 60°
    case wedge64
    // Putter
    case putter

    var id: Self { self }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .twoWood: return "2 Wood"
        case .threeWood: return "3 Wood"
        case .fourWood: return "4 Wood"
        case .fiveWood: return "5 Wood"
        case .sevenWood: return "7 Wood"
        case .nineWood: return "9 Wood"
        case .hybrid2: return "2 Hybrid"
        case .hybrid3: return "3 Hybrid"
        case .hybrid4: return "4 Hybrid"
        case .hybrid5: return "5 Hybrid"
        case .hybrid6: return "6 Hybrid"
        case .iron2: return "2 Iron"
        case .iron3: return "3 Iron"
        case .iron4: return "4 Iron"
        case .iron5: return "5 Iron"
        case .iron6: return "6 Iron"
        case .iron7: return "7 Iron"
        case .iron8: return "8 Iron"
        case .iron9: return "9 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .wedge46: return "46° Wedge"
        case .wedge48: return "48° Wedge"
        case .wedge50: return "50° Wedge"
        case .gapWedge: return "52° / Gap Wedge"
        case .wedge54: return "54° Wedge"
        case .sandWedge: return "56° / Sand Wedge"
        case .wedge58: return "58° Wedge"
        case .lobWedge: return "60° / Lob Wedge"
        case .wedge64: return "64° Wedge"
        case .putter: return "Putter"
        }
    }

    var shortName: String {
        switch self {
        case .driver: return "Driver"
        case .twoWood: return "2W"
        case .threeWood: return "3W"
        case .fourWood: return "4W"
        case .fiveWood: return "5W"
        case .sevenWood: return "7W"
        case .nineWood: return "9W"
        case .hybrid2: return "2H"
        case .hybrid3: return "3H"
        case .hybrid4: return "4H"
        case .hybrid5: return "5H"
        case .hybrid6: return "6H"
        case .iron2: return "2i"
        case .iron3: return "3i"
        case .iron4: return "4i"
        case .iron5: return "5i"
        case .iron6: return "6i"
        case .iron7: return "7i"
        case .iron8: return "8i"
        case .iron9: return "9i"
        case .pitchingWedge: return "PW"
        case .wedge46: return "46°"
        case .wedge48: return "48°"
        case .wedge50: return "50°"
        case .gapWedge: return "GW"
        case .wedge54: return "54°"
        case .sandWedge: return "SW"
        case .wedge58: return "58°"
        case .lobWedge: return "LW"
        case .wedge64: return "64°"
        case .putter: return "Putter"
        }
    }

    var defaultCarryYards: Int {
        switch self {
        case .driver: return 235
        case .twoWood: return 228
        case .threeWood: return 220
        case .fourWood: return 212
        case .fiveWood: return 205
        case .sevenWood: return 195
        case .nineWood: return 185
        case .hybrid2: return 210
        case .hybrid3: return 200
        case .hybrid4: return 195
        case .hybrid5: return 185
        case .hybrid6: return 175
        case .iron2: return 205
        case .iron3: return 195
        case .iron4: return 190
        case .iron5: return 185
        case .iron6: return 175
        case .iron7: return 165
        case .iron8: return 155
        case .iron9: return 143
        case .pitchingWedge: return 132
        case .wedge46: return 125
        case .wedge48: return 120
        case .wedge50: return 115
        case .gapWedge: return 110
        case .wedge54: return 102
        case .sandWedge: return 96
        case .wedge58: return 85
        case .lobWedge: return 78
        case .wedge64: return 65
        case .putter: return 0
        }
    }

    /// Clubs available for carry-distance-based selection (excludes putter)
    static var shotClubs: [Club] {
        allCases.filter { $0 != .putter }
    }

    /// The default bag: the 13 clubs most players carry (excludes putter)
    static var defaultBag: [Club] {
        [.driver, .threeWood, .fiveWood, .hybrid4,
         .iron5, .iron6, .iron7, .iron8, .iron9,
         .pitchingWedge, .gapWedge, .sandWedge, .lobWedge]
    }

    /// Ordering index for sorting (lower = longer club)
    var sortOrder: Int {
        switch self {
        case .driver: return 0
        case .twoWood: return 1
        case .threeWood: return 2
        case .fourWood: return 3
        case .fiveWood: return 4
        case .sevenWood: return 5
        case .nineWood: return 6
        case .hybrid2: return 7
        case .hybrid3: return 8
        case .hybrid4: return 9
        case .hybrid5: return 10
        case .hybrid6: return 11
        case .iron2: return 12
        case .iron3: return 13
        case .iron4: return 14
        case .iron5: return 15
        case .iron6: return 16
        case .iron7: return 17
        case .iron8: return 18
        case .iron9: return 19
        case .pitchingWedge: return 20
        case .wedge46: return 21
        case .wedge48: return 22
        case .wedge50: return 23
        case .gapWedge: return 24
        case .wedge54: return 25
        case .sandWedge: return 26
        case .wedge58: return 27
        case .lobWedge: return 28
        case .wedge64: return 29
        case .putter: return 30
        }
    }

    var category: ClubCategory {
        switch self {
        case .driver, .twoWood, .threeWood, .fourWood, .fiveWood, .sevenWood, .nineWood:
            return .woods
        case .hybrid2, .hybrid3, .hybrid4, .hybrid5, .hybrid6:
            return .hybrids
        default:
            return .irons
        }
    }
}

// MARK: - Club Category

enum ClubCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case woods
    case hybrids
    case irons

    var id: Self { self }

    var displayName: String {
        switch self {
        case .woods: return "Woods"
        case .hybrids: return "Hybrids"
        case .irons: return "Irons"
        }
    }
}

// MARK: - Shot Type

enum ShotType: String, CaseIterable, Codable, Identifiable, Sendable {
    case tee
    case approach
    case chip
    case pitch
    case bunker
    case punchRecovery
    case layup

    var id: Self { self }

    var displayName: String {
        switch self {
        case .tee: return "Tee Shot"
        case .approach: return "Approach"
        case .chip: return "Chip"
        case .pitch: return "Pitch"
        case .bunker: return "Bunker"
        case .punchRecovery: return "Punch / Recovery"
        case .layup: return "Layup"
        }
    }
}

// MARK: - Lie Type

enum LieType: String, CaseIterable, Codable, Identifiable, Sendable {
    case fairway
    case firstCut
    case rough
    case deepRough
    case greensideBunker
    case fairwayBunker
    case hardpan
    case pineStraw
    case treesObstructed

    var id: Self { self }

    var displayName: String {
        switch self {
        case .fairway: return "Fairway"
        case .firstCut: return "First Cut"
        case .rough: return "Rough"
        case .deepRough: return "Deep Rough"
        case .greensideBunker: return "Greenside Bunker"
        case .fairwayBunker: return "Fairway Bunker"
        case .hardpan: return "Hardpan"
        case .pineStraw: return "Pine Straw"
        case .treesObstructed: return "Trees / Obstructed"
        }
    }
}

// MARK: - Wind Strength

enum WindStrength: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case light
    case moderate
    case strong

    var id: Self { self }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        }
    }
}

// MARK: - Wind Direction

enum WindDirection: String, CaseIterable, Codable, Identifiable, Sendable {
    case into
    case helping
    case crossLeftToRight
    case crossRightToLeft

    var id: Self { self }

    var displayName: String {
        switch self {
        case .into: return "Into"
        case .helping: return "Helping"
        case .crossLeftToRight: return "Cross L→R"
        case .crossRightToLeft: return "Cross R→L"
        }
    }
}

// MARK: - Slope

enum Slope: String, CaseIterable, Codable, Identifiable, Sendable {
    case level
    case uphill
    case downhill
    case ballAboveFeet
    case ballBelowFeet

    var id: Self { self }

    var displayName: String {
        switch self {
        case .level: return "Level"
        case .uphill: return "Uphill"
        case .downhill: return "Downhill"
        case .ballAboveFeet: return "Ball Above Feet"
        case .ballBelowFeet: return "Ball Below Feet"
        }
    }
}

// MARK: - Aggressiveness

enum Aggressiveness: String, CaseIterable, Codable, Identifiable, Sendable {
    case conservative
    case normal
    case aggressive

    var id: Self { self }

    var displayName: String {
        switch self {
        case .conservative: return "Conservative"
        case .normal: return "Normal"
        case .aggressive: return "Aggressive"
        }
    }
}

// MARK: - Stock Shape

enum StockShape: String, CaseIterable, Codable, Identifiable, Sendable {
    case straight
    case fade
    case draw

    var id: Self { self }

    var displayName: String {
        switch self {
        case .straight: return "Straight"
        case .fade: return "Fade"
        case .draw: return "Draw"
        }
    }
}

// MARK: - Miss Tendency

enum MissTendency: String, CaseIterable, Codable, Identifiable, Sendable {
    case straight
    case left
    case right
    case thin
    case fat

    var id: Self { self }

    var displayName: String {
        switch self {
        case .straight: return "Straight"
        case .left: return "Left"
        case .right: return "Right"
        case .thin: return "Thin"
        case .fat: return "Fat"
        }
    }
}

// MARK: - Risk Level

enum RiskLevel: String, Codable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: Self { self }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

// MARK: - Confidence Level

enum ConfidenceLevel: String, Codable, Identifiable, Sendable {
    case high
    case medium
    case low

    var id: Self { self }

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

// MARK: - Self-Rated Confidence (for player preferences)

enum SelfConfidence: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case average
    case high

    var id: Self { self }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .average: return "Average"
        case .high: return "High"
        }
    }
}

// MARK: - Preferred Chip Style

enum ChipStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case bumpAndRun
    case lofted
    case noPreference

    var id: Self { self }

    var displayName: String {
        switch self {
        case .bumpAndRun: return "Bump & Run"
        case .lofted: return "Lofted"
        case .noPreference: return "No Preference"
        }
    }
}

// MARK: - Swing Tendency

enum SwingTendency: String, CaseIterable, Codable, Identifiable, Sendable {
    case steep
    case shallow
    case neutral

    var id: Self { self }

    var displayName: String {
        switch self {
        case .steep: return "Steep"
        case .shallow: return "Shallow"
        case .neutral: return "Neutral"
        }
    }
}

// MARK: - Tee Box Preference

/// Tee tier preference ordered longest → shortest.
/// Each case represents a yardage tier, not a literal color.
/// Matching uses tier order for fallback when a course doesn't have the exact name.
enum TeeBoxPreference: Int, CaseIterable, Codable, Identifiable, Sendable {
    case championship = 0  // Black / Championship — longest
    case blue = 1
    case white = 2
    case senior = 3        // Gold / Silver — forward-middle
    case forward = 4       // Red / Forward / Ladies — shortest

    var id: Self { self }

    var displayName: String {
        switch self {
        case .championship: return "Black / Championship"
        case .blue: return "Blue"
        case .white: return "White"
        case .senior: return "Gold / Silver"
        case .forward: return "Red / Forward"
        }
    }

    /// Keywords used to match against actual course tee names (case-insensitive).
    var matchKeywords: [String] {
        switch self {
        case .championship: return ["championship", "black", "tiger"]
        case .blue: return ["blue"]
        case .white: return ["white"]
        case .senior: return ["gold", "silver", "senior"]
        case .forward: return ["red", "forward", "ladies"]
        }
    }
}

// MARK: - Iron Type

/// Describes the player's iron construction type, which affects
/// performance from bunkers, tight lies, rough, and in wind.
enum IronType: String, CaseIterable, Codable, Identifiable, Sendable {
    case gameImprovement
    case superGameImprovement

    var id: Self { self }

    var displayName: String {
        switch self {
        case .gameImprovement: return "Game Improvement"
        case .superGameImprovement: return "Super Game Improvement"
        }
    }

    var shortName: String {
        switch self {
        case .gameImprovement: return "GI"
        case .superGameImprovement: return "SGI"
        }
    }
}

// MARK: - Caddie Voice Gender

enum CaddieVoiceGender: String, CaseIterable, Codable, Identifiable, Sendable {
    case male
    case female

    var id: Self { self }

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

// MARK: - Caddie Voice Accent

enum CaddieVoiceAccent: String, CaseIterable, Codable, Identifiable, Sendable {
    case american
    case british
    case australian
    case indian

    var id: Self { self }

    var displayName: String {
        switch self {
        case .american: return "American"
        case .british: return "British"
        case .australian: return "Australian"
        case .indian: return "Indian"
        }
    }

    var languageCode: String {
        switch self {
        case .american: return "en-US"
        case .british: return "en-GB"
        case .australian: return "en-AU"
        case .indian: return "en-IN"
        }
    }
}

// MARK: - Caddie Persona

enum CaddiePersona: String, CaseIterable, Codable, Identifiable, Sendable {
    case professional
    case supportiveGrandparent
    case collegeBuddy
    case drillSergeant
    case chillSurfer

    var id: Self { self }

    var displayName: String {
        switch self {
        case .professional: return "Professional"
        case .supportiveGrandparent: return "Supportive Grandparent"
        case .collegeBuddy: return "College Buddy"
        case .drillSergeant: return "Drill Sergeant"
        case .chillSurfer: return "Chill Surfer"
        }
    }

    var description: String {
        switch self {
        case .professional: return "Calm, authoritative tour caddie"
        case .supportiveGrandparent: return "You're the best, sweetie"
        case .collegeBuddy: return "Playful roasts, big hype"
        case .drillSergeant: return "Tough love, no excuses"
        case .chillSurfer: return "Laid back, go with the flow"
        }
    }
}

// MARK: - LLM Provider

enum LLMProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI
    case claude
    case gemini

    var id: Self { self }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    var availableModels: [LLMModel] {
        switch self {
        case .openAI: return [.gpt4o, .gpt4oMini, .gpt4Turbo]
        case .claude: return [.claudeSonnet4, .claudeHaiku35]
        case .gemini: return [.gemini20Flash, .gemini15Pro]
        }
    }

    var defaultModel: LLMModel {
        switch self {
        case .openAI: return .gpt4o
        case .claude: return .claudeSonnet4
        case .gemini: return .gemini20Flash
        }
    }
}

// MARK: - LLM Model

enum LLMModel: String, CaseIterable, Codable, Identifiable, Sendable {
    // OpenAI
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4Turbo = "gpt-4-turbo"
    // Claude
    case claudeSonnet4 = "claude-sonnet-4-20250514"
    case claudeHaiku35 = "claude-haiku-35-20241022"
    // Gemini
    case gemini20Flash = "gemini-2.0-flash"
    case gemini15Pro = "gemini-1.5-pro"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        case .gpt4Turbo: return "GPT-4 Turbo"
        case .claudeSonnet4: return "Claude Sonnet 4"
        case .claudeHaiku35: return "Claude Haiku 3.5"
        case .gemini20Flash: return "Gemini 2.0 Flash"
        case .gemini15Pro: return "Gemini 1.5 Pro"
        }
    }

    var provider: LLMProvider {
        switch self {
        case .gpt4o, .gpt4oMini, .gpt4Turbo: return .openAI
        case .claudeSonnet4, .claudeHaiku35: return .claude
        case .gemini20Flash, .gemini15Pro: return .gemini
        }
    }
}
