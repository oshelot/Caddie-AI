//
//  GolfEnums.swift
//  CaddieAI
//

import Foundation

// MARK: - Club

enum Club: String, CaseIterable, Codable, Identifiable, Sendable {
    case driver
    case threeWood
    case fiveWood
    case hybrid4
    case iron5
    case iron6
    case iron7
    case iron8
    case iron9
    case pitchingWedge
    case gapWedge
    case sandWedge
    case lobWedge
    case putter

    var id: Self { self }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .threeWood: return "3 Wood"
        case .fiveWood: return "5 Wood"
        case .hybrid4: return "4 Hybrid"
        case .iron5: return "5 Iron"
        case .iron6: return "6 Iron"
        case .iron7: return "7 Iron"
        case .iron8: return "8 Iron"
        case .iron9: return "9 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .gapWedge: return "Gap Wedge"
        case .sandWedge: return "Sand Wedge"
        case .lobWedge: return "Lob Wedge"
        case .putter: return "Putter"
        }
    }

    var shortName: String {
        switch self {
        case .driver: return "Driver"
        case .threeWood: return "3W"
        case .fiveWood: return "5W"
        case .hybrid4: return "4H"
        case .iron5: return "5i"
        case .iron6: return "6i"
        case .iron7: return "7i"
        case .iron8: return "8i"
        case .iron9: return "9i"
        case .pitchingWedge: return "PW"
        case .gapWedge: return "GW"
        case .sandWedge: return "SW"
        case .lobWedge: return "LW"
        case .putter: return "Putter"
        }
    }

    var defaultCarryYards: Int {
        switch self {
        case .driver: return 235
        case .threeWood: return 220
        case .fiveWood: return 205
        case .hybrid4: return 195
        case .iron5: return 185
        case .iron6: return 175
        case .iron7: return 165
        case .iron8: return 155
        case .iron9: return 143
        case .pitchingWedge: return 132
        case .gapWedge: return 118
        case .sandWedge: return 96
        case .lobWedge: return 78
        case .putter: return 0
        }
    }

    /// Clubs available for carry-distance-based selection (excludes putter)
    static var shotClubs: [Club] {
        allCases.filter { $0 != .putter }
    }

    /// Ordering index for sorting (lower = longer club)
    var sortOrder: Int {
        switch self {
        case .driver: return 0
        case .threeWood: return 1
        case .fiveWood: return 2
        case .hybrid4: return 3
        case .iron5: return 4
        case .iron6: return 5
        case .iron7: return 6
        case .iron8: return 7
        case .iron9: return 8
        case .pitchingWedge: return 9
        case .gapWedge: return 10
        case .sandWedge: return 11
        case .lobWedge: return 12
        case .putter: return 13
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
