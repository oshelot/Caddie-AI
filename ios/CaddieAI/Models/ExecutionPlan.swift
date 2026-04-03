//
//  ExecutionPlan.swift
//  CaddieAI
//

import Foundation

// MARK: - Execution Archetype

enum ExecutionArchetype: String, Codable, Sendable {
    case bumpAndRunChip
    case standardChip
    case softPitch
    case standardPitch
    case partialWedge
    case bunkerExplosion
    case fairwayBunkerShot
    case stockFullSwing
    case knockdownApproach
    case punchShot
    case layupSwing
    case teeDriver
    case teeFairwayWood
    case recoveryFromRough
    case recoveryUnderTrees

    var displayName: String {
        switch self {
        case .bumpAndRunChip: return "Bump & Run Chip"
        case .standardChip: return "Standard Chip"
        case .softPitch: return "Soft Pitch"
        case .standardPitch: return "Standard Pitch"
        case .partialWedge: return "Partial Wedge"
        case .bunkerExplosion: return "Bunker Explosion"
        case .fairwayBunkerShot: return "Fairway Bunker"
        case .stockFullSwing: return "Stock Full Swing"
        case .knockdownApproach: return "Knockdown"
        case .punchShot: return "Punch Shot"
        case .layupSwing: return "Layup"
        case .teeDriver: return "Tee Shot (Driver)"
        case .teeFairwayWood: return "Tee Shot (Wood/Hybrid)"
        case .recoveryFromRough: return "Recovery from Rough"
        case .recoveryUnderTrees: return "Recovery Under Trees"
        }
    }
}

// MARK: - Execution Plan

struct ExecutionPlan: Codable, Sendable {
    var archetype: ExecutionArchetype
    var setupSummary: String
    var ballPosition: String
    var weightDistribution: String
    var stanceWidth: String
    var alignment: String
    var clubface: String
    var shaftLean: String
    var backswingLength: String
    var followThrough: String
    var tempo: String
    var strikeIntention: String
    var swingThought: String
    var mistakeToAvoid: String

    static var mock: ExecutionPlan {
        ExecutionPlan(
            archetype: .stockFullSwing,
            setupSummary: "Standard setup, ball slightly forward of center.",
            ballPosition: "slightly forward of center",
            weightDistribution: "balanced to slightly lead side",
            stanceWidth: "shoulder width",
            alignment: "square to target line",
            clubface: "square",
            shaftLean: "natural athletic address",
            backswingLength: "full",
            followThrough: "full balanced finish",
            tempo: "committed and even",
            strikeIntention: "compress the ball with a centered strike",
            swingThought: "commit to the target and finish balanced",
            mistakeToAvoid: "do not decelerate through impact"
        )
    }
}
