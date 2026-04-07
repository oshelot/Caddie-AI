//
//  GolfLogicEngine.swift
//  CaddieAI
//

import Foundation

// MARK: - Supporting Types

struct TargetStrategy: Codable, Sendable {
    var target: String
    var preferredMiss: String
    var reasoning: String
}

struct DeterministicAnalysis: Codable, Sendable {
    var effectiveDistanceYards: Int
    var recommendedClub: Club
    var alternateClub: Club?
    var targetStrategy: TargetStrategy
    var adjustments: [String]
    var maxClubForLie: Club?
    var executionPlan: ExecutionPlan
}

// MARK: - Golf Logic Engine

struct GolfLogicEngine {

    // MARK: - Primary Entry Point

    static func analyze(
        context: ShotContext,
        profile: PlayerProfile
    ) -> DeterministicAnalysis {
        let effectiveDistance = calculateEffectiveDistance(context: context, ironType: profile.ironType)
        let clubLimit = maxClubForLie(context.lieType, ironType: profile.ironType)
        let recommendedClub = selectClub(
            effectiveDistance: effectiveDistance,
            clubDistances: profile.clubDistances,
            maxAllowedClub: clubLimit
        )
        let alternateClub = selectAlternateClub(
            effectiveDistance: effectiveDistance,
            primaryClub: recommendedClub,
            clubDistances: profile.clubDistances,
            maxAllowedClub: clubLimit
        )
        let targetStrategy = determineTargetStrategy(
            context: context,
            profile: profile,
            recommendedClub: recommendedClub
        )
        let adjustments = describeAdjustments(context: context, ironType: profile.ironType)

        let executionPlan = ExecutionEngine.generateExecutionPlan(
            context: context,
            club: recommendedClub,
            effectiveDistance: effectiveDistance,
            profile: profile
        )

        return DeterministicAnalysis(
            effectiveDistanceYards: effectiveDistance,
            recommendedClub: recommendedClub,
            alternateClub: alternateClub,
            targetStrategy: targetStrategy,
            adjustments: adjustments,
            maxClubForLie: clubLimit,
            executionPlan: executionPlan
        )
    }

    // MARK: - Effective Distance Calculation

    static func calculateEffectiveDistance(context: ShotContext, ironType: IronType? = nil) -> Int {
        var distance = Double(context.distanceYards)

        distance += windAdjustment(
            strength: context.windStrength,
            direction: context.windDirection,
            baseDistance: context.distanceYards
        )

        distance += lieAdjustment(lieType: context.lieType)

        distance += slopeAdjustment(
            slope: context.slope,
            baseDistance: context.distanceYards
        )

        // GI/SGI irons lose distance from challenging lies due to wide soles
        if let ironType {
            distance += ironTypeLieAdjustment(lieType: context.lieType, ironType: ironType)
        }

        return max(1, Int(distance.rounded()))
    }

    // MARK: - Wind Adjustment

    static func windAdjustment(
        strength: WindStrength,
        direction: WindDirection,
        baseDistance: Int
    ) -> Double {
        let factor: Double
        switch strength {
        case .none: return 0
        case .light: factor = 0.03
        case .moderate: factor = 0.07
        case .strong: factor = 0.12
        }

        let adjustment = Double(baseDistance) * factor

        switch direction {
        case .into: return adjustment
        case .helping: return -adjustment
        case .crossLeftToRight, .crossRightToLeft:
            return adjustment * 0.3
        }
    }

    // MARK: - Lie Adjustment

    static func lieAdjustment(lieType: LieType) -> Double {
        switch lieType {
        case .fairway: return 0
        case .firstCut: return 3
        case .rough: return 7
        case .deepRough: return 15
        case .greensideBunker: return 5
        case .fairwayBunker: return 10
        case .hardpan: return -3
        case .pineStraw: return 5
        case .treesObstructed: return 20
        }
    }

    // MARK: - Slope Adjustment

    static func slopeAdjustment(slope: Slope, baseDistance: Int) -> Double {
        let base = Double(baseDistance)
        switch slope {
        case .level: return 0
        case .uphill: return base * 0.05
        case .downhill: return -(base * 0.05)
        case .ballAboveFeet: return 3
        case .ballBelowFeet: return 3
        }
    }

    // MARK: - Iron Type Lie Adjustment

    /// Additional distance penalty for GI/SGI irons from challenging lies.
    /// Wide soles and high offset make these irons less effective from
    /// bunkers, tight lies, and thick rough.
    static func ironTypeLieAdjustment(lieType: LieType, ironType: IronType) -> Double {
        let multiplier: Double = ironType == .superGameImprovement ? 1.5 : 1.0
        switch lieType {
        case .fairwayBunker:    return 8 * multiplier   // wide sole digs, poor contact
        case .greensideBunker:  return 5 * multiplier   // harder to open face with offset
        case .hardpan:          return 5 * multiplier   // wide sole bounces off hardpan
        case .rough:            return 3 * multiplier   // grass grabs wide sole
        case .deepRough:        return 5 * multiplier   // even worse in heavy rough
        default:                return 0
        }
    }

    // MARK: - Club Selection

    static func selectClub(
        effectiveDistance: Int,
        clubDistances: [ClubDistance],
        maxAllowedClub: Club?
    ) -> Club {
        let sorted = clubDistances
            .filter { isClubAllowed($0.club, maxAllowed: maxAllowedClub) }
            .sorted { $0.carryYards > $1.carryYards }

        // Find the shortest club that still covers the distance
        var bestClub = sorted.last?.club ?? .pitchingWedge

        for cd in sorted {
            if cd.carryYards >= effectiveDistance {
                bestClub = cd.club
            } else {
                break
            }
        }

        return bestClub
    }

    // MARK: - Alternate Club

    static func selectAlternateClub(
        effectiveDistance: Int,
        primaryClub: Club,
        clubDistances: [ClubDistance],
        maxAllowedClub: Club?
    ) -> Club? {
        let sorted = clubDistances
            .filter { isClubAllowed($0.club, maxAllowed: maxAllowedClub) }
            .sorted { $0.club.sortOrder < $1.club.sortOrder }

        guard let primaryIndex = sorted.firstIndex(where: { $0.club == primaryClub }) else {
            return nil
        }

        // Check one club longer and one club shorter
        let longerIndex = primaryIndex - 1
        let shorterIndex = primaryIndex + 1

        if shorterIndex < sorted.count {
            let shorter = sorted[shorterIndex]
            let diff = abs(shorter.carryYards - effectiveDistance)
            if diff <= 10 {
                return shorter.club
            }
        }

        if longerIndex >= 0 {
            let longer = sorted[longerIndex]
            let diff = abs(longer.carryYards - effectiveDistance)
            if diff <= 10 {
                return longer.club
            }
        }

        return nil
    }

    // MARK: - Club Restrictions by Lie

    static func maxClubForLie(_ lieType: LieType, ironType: IronType? = nil) -> Club? {
        // Base limits
        var limit: Club?
        switch lieType {
        case .deepRough: limit = .iron7
        case .greensideBunker: limit = .sandWedge
        case .fairwayBunker: limit = .iron6
        case .treesObstructed: limit = .iron7
        case .pineStraw: limit = .iron5
        default: limit = nil
        }

        // GI/SGI irons need tighter limits from challenging lies
        if let ironType {
            switch lieType {
            case .fairwayBunker:
                // Wide sole makes long irons from bunkers very difficult
                limit = ironType == .superGameImprovement ? .iron8 : .iron7
            case .hardpan:
                // Wide sole bounces — restrict to shorter irons
                limit = ironType == .superGameImprovement ? .iron8 : .iron7
            default:
                break
            }
        }

        return limit
    }

    static func isClubAllowed(_ club: Club, maxAllowed: Club?) -> Bool {
        guard let max = maxAllowed else { return true }
        return club.sortOrder >= max.sortOrder
    }

    // MARK: - Target Strategy

    static func determineTargetStrategy(
        context: ShotContext,
        profile: PlayerProfile,
        recommendedClub: Club
    ) -> TargetStrategy {
        var target = "Center of green"
        var miss = "Safe side of the green"
        var reasoning = ""

        let hasHazardNotes = !context.hazardNotes.trimmingCharacters(in: .whitespaces).isEmpty
        let hazardLower = context.hazardNotes.lowercased()

        // Adjust target based on player tendency and aggressiveness
        switch context.aggressiveness {
        case .conservative:
            target = "Center of the green, away from trouble"
            reasoning = "Conservative approach favors the widest part of the green."
        case .normal:
            target = "Center of the green"
            reasoning = "Standard approach targeting the middle of the green."
        case .aggressive:
            target = "Pin location"
            reasoning = "Aggressive play targeting the flag."
        }

        // Adjust miss side based on miss tendency
        switch profile.missTendency {
        case .right:
            miss = "Favor the left side — your miss tends right"
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Accounting for right miss tendency."
        case .left:
            miss = "Favor the right side — your miss tends left"
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Accounting for left miss tendency."
        case .thin:
            miss = "Club up to account for thin contact tendency"
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Thin misses lose distance."
        case .fat:
            miss = "Club up to account for heavy contact tendency"
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Heavy contact loses distance."
        case .straight:
            miss = "No major miss adjustment needed"
        }

        // Adjust for slope-induced shape changes
        let clubShape = profile.stockShapeForClub(recommendedClub)
        switch context.slope {
        case .ballBelowFeet:
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Ball below feet promotes a fade."
            if clubShape == .fade {
                miss = "Favor the left side — stance will exaggerate your fade"
            }
        case .ballAboveFeet:
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Ball above feet promotes a draw."
            if clubShape == .draw {
                miss = "Favor the right side — stance will exaggerate your draw"
            }
        default:
            break
        }

        // Adjust for wind crosswind
        switch context.windDirection {
        case .crossLeftToRight:
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Crosswind L→R will push the ball right."
            target += ", aiming slightly left to allow for wind"
        case .crossRightToLeft:
            if !reasoning.isEmpty { reasoning += " " }
            reasoning += "Crosswind R→L will push the ball left."
            target += ", aiming slightly right to allow for wind"
        default:
            break
        }

        // Factor in hazard notes
        if hasHazardNotes {
            if hazardLower.contains("water left") || hazardLower.contains("hazard left") {
                miss = "Miss right — water left"
                if !reasoning.isEmpty { reasoning += " " }
                reasoning += "Water left makes right the safe miss."
            } else if hazardLower.contains("water right") || hazardLower.contains("hazard right") {
                miss = "Miss left — water right"
                if !reasoning.isEmpty { reasoning += " " }
                reasoning += "Water right makes left the safe miss."
            }
            if hazardLower.contains("bunker short") {
                if !reasoning.isEmpty { reasoning += " " }
                reasoning += "Bunker short of green — make sure to take enough club."
            }
            if hazardLower.contains("ob") || hazardLower.contains("out of bounds") {
                if !reasoning.isEmpty { reasoning += " " }
                reasoning += "OB in play — favor the safe side."
            }
        }

        return TargetStrategy(
            target: target,
            preferredMiss: miss,
            reasoning: reasoning
        )
    }

    // MARK: - Describe Adjustments

    static func describeAdjustments(context: ShotContext, ironType: IronType? = nil) -> [String] {
        var adjustments: [String] = []

        let windAdj = windAdjustment(
            strength: context.windStrength,
            direction: context.windDirection,
            baseDistance: context.distanceYards
        )
        if abs(windAdj) > 0.5 {
            let sign = windAdj > 0 ? "+" : ""
            adjustments.append("Wind (\(context.windStrength.displayName) \(context.windDirection.displayName)): \(sign)\(Int(windAdj.rounded())) yards")
        }

        let lieAdj = lieAdjustment(lieType: context.lieType)
        if abs(lieAdj) > 0.5 {
            let sign = lieAdj > 0 ? "+" : ""
            adjustments.append("Lie (\(context.lieType.displayName)): \(sign)\(Int(lieAdj.rounded())) yards")
        }

        let slopeAdj = slopeAdjustment(slope: context.slope, baseDistance: context.distanceYards)
        if abs(slopeAdj) > 0.5 {
            let sign = slopeAdj > 0 ? "+" : ""
            adjustments.append("Slope (\(context.slope.displayName)): \(sign)\(Int(slopeAdj.rounded())) yards")
        }

        if let ironType {
            let giAdj = ironTypeLieAdjustment(lieType: context.lieType, ironType: ironType)
            if abs(giAdj) > 0.5 {
                adjustments.append("\(ironType.shortName) iron penalty (\(context.lieType.displayName)): +\(Int(giAdj.rounded())) yards")
            }
        }

        if adjustments.isEmpty {
            adjustments.append("No adjustments — clean conditions")
        }

        return adjustments
    }
}
