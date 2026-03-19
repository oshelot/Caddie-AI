//
//  ExecutionEngine.swift
//  CaddieAI
//

import Foundation

struct ExecutionEngine {

    // MARK: - Primary Entry Point

    static func generateExecutionPlan(
        context: ShotContext,
        club: Club,
        effectiveDistance: Int,
        profile: PlayerProfile? = nil
    ) -> ExecutionPlan {
        let archetype = selectArchetype(
            context: context,
            club: club,
            effectiveDistance: effectiveDistance,
            profile: profile
        )
        var plan = template(for: archetype)

        // Apply situational adjustments
        plan = adjustForSlope(plan: plan, slope: context.slope)
        plan = adjustForWind(plan: plan, wind: context.windStrength, direction: context.windDirection)
        plan = adjustForLie(plan: plan, lie: context.lieType, archetype: archetype)

        // Apply player preference adjustments
        if let profile {
            plan = adjustForPlayerPreferences(plan: plan, profile: profile, archetype: archetype)
        }

        return plan
    }

    // MARK: - Archetype Selection

    static func selectArchetype(
        context: ShotContext,
        club: Club,
        effectiveDistance: Int,
        profile: PlayerProfile? = nil
    ) -> ExecutionArchetype {
        // Bunker shots
        if context.lieType == .greensideBunker {
            return .bunkerExplosion
        }
        if context.lieType == .fairwayBunker {
            return .fairwayBunkerShot
        }

        // Recovery shots
        if context.lieType == .treesObstructed {
            return .recoveryUnderTrees
        }
        if context.shotType == .punchRecovery {
            return .punchShot
        }
        if context.lieType == .deepRough {
            return .recoveryFromRough
        }

        // Tee shots
        if context.shotType == .tee {
            if club == .driver {
                return .teeDriver
            } else {
                return .teeFairwayWood
            }
        }

        // Short game by shot type — factor in player chip style preference
        if context.shotType == .chip {
            if let chipPref = profile?.preferredChipStyle {
                switch chipPref {
                case .bumpAndRun:
                    return .bumpAndRunChip
                case .lofted:
                    return .standardChip
                case .noPreference:
                    return effectiveDistance <= 20 ? .bumpAndRunChip : .standardChip
                }
            }
            return effectiveDistance <= 20 ? .bumpAndRunChip : .standardChip
        }
        if context.shotType == .pitch {
            if effectiveDistance <= 40 {
                return .softPitch
            }
            return .standardPitch
        }

        // Layup
        if context.shotType == .layup {
            return .layupSwing
        }

        // Partial wedge (30-70 yards)
        if effectiveDistance >= 30 && effectiveDistance <= 70 {
            return .partialWedge
        }

        // Knockdown (into wind or when player chooses lower trajectory)
        if context.windStrength == .strong && context.windDirection == .into {
            return .knockdownApproach
        }
        if context.windStrength == .moderate && context.windDirection == .into {
            return .knockdownApproach
        }

        // Default: stock full swing
        return .stockFullSwing
    }

    // MARK: - Archetype Templates

    static func template(for archetype: ExecutionArchetype) -> ExecutionPlan {
        switch archetype {
        case .bumpAndRunChip:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball back, weight left, narrow stance.",
                ballPosition: "back of center",
                weightDistribution: "60-70% lead side",
                stanceWidth: "narrow",
                alignment: "slightly open",
                clubface: "square",
                shaftLean: "forward",
                backswingLength: "short",
                followThrough: "short controlled finish",
                tempo: "quiet and controlled",
                strikeIntention: "clip the ball cleanly and let it roll",
                swingThought: "putting stroke with loft",
                mistakeToAvoid: "do not try to help the ball into the air"
            )
        case .standardChip:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball center, lean toward target, compact motion.",
                ballPosition: "center",
                weightDistribution: "60% lead side",
                stanceWidth: "narrow",
                alignment: "slightly open",
                clubface: "square",
                shaftLean: "slight forward lean",
                backswingLength: "short to quarter",
                followThrough: "short, matching backswing length",
                tempo: "smooth and steady",
                strikeIntention: "brush the turf lightly after the ball",
                swingThought: "keep your hands ahead through impact",
                mistakeToAvoid: "do not flip the wrists at impact"
            )
        case .softPitch:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball center-forward, soft hands, use the loft.",
                ballPosition: "center to slightly forward of center",
                weightDistribution: "slightly favor lead side",
                stanceWidth: "narrow",
                alignment: "slightly open",
                clubface: "slightly open for more loft",
                shaftLean: "minimal forward lean",
                backswingLength: "waist high",
                followThrough: "full soft finish",
                tempo: "smooth with acceleration through",
                strikeIntention: "brush the turf and use the loft",
                swingThought: "let the club slide under with speed",
                mistakeToAvoid: "do not decelerate or quit on it"
            )
        case .standardPitch:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball center-forward, controlled backswing, full release.",
                ballPosition: "center to slightly forward",
                weightDistribution: "slightly favor lead side",
                stanceWidth: "narrow to medium",
                alignment: "slightly open",
                clubface: "square to slightly open",
                shaftLean: "minimal",
                backswingLength: "chest high",
                followThrough: "full soft finish",
                tempo: "smooth with acceleration through",
                strikeIntention: "brush the turf and use the bounce",
                swingThought: "match the backswing and follow-through length",
                mistakeToAvoid: "do not scoop or try to lift the ball"
            )
        case .partialWedge:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball center, controlled motion, commit to distance.",
                ballPosition: "center",
                weightDistribution: "balanced to slightly lead",
                stanceWidth: "medium",
                alignment: "square to slightly open",
                clubface: "square",
                shaftLean: "slight forward lean",
                backswingLength: "half to three-quarter",
                followThrough: "controlled finish matching backswing",
                tempo: "smooth and rhythmic",
                strikeIntention: "ball-first contact, consistent strike",
                swingThought: "control the length, commit to the swing",
                mistakeToAvoid: "do not try to add distance by swinging harder"
            )
        case .bunkerExplosion:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball forward, open stance, open face, splash the sand.",
                ballPosition: "forward of center",
                weightDistribution: "favor lead side and keep it there",
                stanceWidth: "stable, slightly wider than chip",
                alignment: "open stance, body left of target",
                clubface: "open",
                shaftLean: "neutral to slight backward feel",
                backswingLength: "half to three-quarter",
                followThrough: "full splash-through finish",
                tempo: "committed with speed through the sand",
                strikeIntention: "enter sand behind the ball and use the bounce",
                swingThought: "splash the sand, not the ball",
                mistakeToAvoid: "do not try to pick the ball clean"
            )
        case .fairwayBunkerShot:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball center, dig feet in, pick it clean.",
                ballPosition: "center",
                weightDistribution: "balanced, stable lower body",
                stanceWidth: "medium, dig feet slightly into sand",
                alignment: "square",
                clubface: "square",
                shaftLean: "slight forward lean",
                backswingLength: "three-quarter",
                followThrough: "controlled finish",
                tempo: "smooth and stable",
                strikeIntention: "pick the ball clean, ball first",
                swingThought: "quiet lower body, pick it clean",
                mistakeToAvoid: "do not hit behind the ball or take too much sand"
            )
        case .stockFullSwing:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Standard setup, ball slightly forward, committed swing.",
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
        case .knockdownApproach:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball slightly back, favor lead side, shorter finish.",
                ballPosition: "slightly back of normal",
                weightDistribution: "favor lead side",
                stanceWidth: "slightly narrower than full",
                alignment: "square to slightly open",
                clubface: "square",
                shaftLean: "slight forward lean",
                backswingLength: "three-quarter",
                followThrough: "abbreviated chest-high finish",
                tempo: "controlled and stable",
                strikeIntention: "flight it down with a compressed strike",
                swingThought: "shorter finish, hold the flight down",
                mistakeToAvoid: "do not try to swing harder to compensate for wind"
            )
        case .punchShot:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball back, hands ahead, low finish.",
                ballPosition: "back of center",
                weightDistribution: "60-65% lead side",
                stanceWidth: "medium",
                alignment: "square to escape route",
                clubface: "square to slightly closed",
                shaftLean: "forward lean",
                backswingLength: "half to three-quarter",
                followThrough: "hold-off finish, hands stay low",
                tempo: "firm and controlled",
                strikeIntention: "trap the ball and keep it low",
                swingThought: "hands low through and past impact",
                mistakeToAvoid: "do not let the club release and add loft"
            )
        case .layupSwing:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Controlled swing to a specific yardage.",
                ballPosition: "center to slightly forward",
                weightDistribution: "balanced",
                stanceWidth: "shoulder width",
                alignment: "square to layup target",
                clubface: "square",
                shaftLean: "natural",
                backswingLength: "three-quarter to full",
                followThrough: "full balanced finish",
                tempo: "smooth and controlled",
                strikeIntention: "solid contact to the safe zone",
                swingThought: "pick a specific target and commit",
                mistakeToAvoid: "do not try to squeeze extra distance"
            )
        case .teeDriver:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball forward, wide stance, swing through it.",
                ballPosition: "inside lead heel",
                weightDistribution: "balanced, slight tilt away from target",
                stanceWidth: "wider than shoulders",
                alignment: "square to target line",
                clubface: "square",
                shaftLean: "neutral, shaft and lead arm form a line",
                backswingLength: "full",
                followThrough: "full finish, belt buckle to target",
                tempo: "smooth and powerful",
                strikeIntention: "sweep the ball off the tee on the upswing",
                swingThought: "wide takeaway, full turn, trust the swing",
                mistakeToAvoid: "do not try to kill it — tempo wins"
            )
        case .teeFairwayWood:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball forward, tee it low, sweep it off the tee.",
                ballPosition: "forward of center, just inside lead heel",
                weightDistribution: "balanced",
                stanceWidth: "shoulder width",
                alignment: "square to target",
                clubface: "square",
                shaftLean: "natural",
                backswingLength: "full",
                followThrough: "full balanced finish",
                tempo: "smooth and rhythmic",
                strikeIntention: "sweep the ball off the low tee",
                swingThought: "smooth tempo, let the loft work",
                mistakeToAvoid: "do not try to help it up — trust the club"
            )
        case .recoveryFromRough:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball center, grip down, commit to the strike.",
                ballPosition: "center",
                weightDistribution: "slightly favor lead side",
                stanceWidth: "medium",
                alignment: "square to escape line",
                clubface: "slightly closed to fight the grass",
                shaftLean: "forward lean to reduce grab",
                backswingLength: "three-quarter",
                followThrough: "firm finish, fight through the grass",
                tempo: "firm and committed",
                strikeIntention: "drive through the rough, ball first",
                swingThought: "grip it firm and commit through impact",
                mistakeToAvoid: "do not take too much club — the rough kills distance"
            )
        case .recoveryUnderTrees:
            return ExecutionPlan(
                archetype: archetype,
                setupSummary: "Ball back, keep it low, punch to safety.",
                ballPosition: "back of center",
                weightDistribution: "60% lead side",
                stanceWidth: "medium",
                alignment: "toward the opening",
                clubface: "square to slightly closed",
                shaftLean: "strong forward lean",
                backswingLength: "half",
                followThrough: "hold-off finish, keep hands low",
                tempo: "controlled and firm",
                strikeIntention: "trap it low under the branches",
                swingThought: "low hands, low ball, find the fairway",
                mistakeToAvoid: "do not get greedy — take the safe line out"
            )
        }
    }

    // MARK: - Situational Adjustments

    static func adjustForSlope(plan: ExecutionPlan, slope: Slope) -> ExecutionPlan {
        var plan = plan
        switch slope {
        case .uphill:
            plan.ballPosition = adjustBallPosition(plan.ballPosition, toward: "slightly more forward")
            plan.weightDistribution = "favor lead side more to resist falling back"
            plan.strikeIntention += " — uphill lie adds loft, so expect higher flight"
        case .downhill:
            plan.ballPosition = adjustBallPosition(plan.ballPosition, toward: "slightly more back")
            plan.weightDistribution = "stay centered, resist falling toward target"
            plan.strikeIntention += " — downhill lie reduces loft, expect lower flight"
        case .ballAboveFeet:
            plan.alignment = "aim slightly right — ball above feet promotes a draw"
            plan.setupSummary += " Grip down slightly for control."
        case .ballBelowFeet:
            plan.alignment = "aim slightly left — ball below feet promotes a fade"
            plan.setupSummary += " Flex knees more and stay down through it."
        case .level:
            break
        }
        return plan
    }

    static func adjustForWind(plan: ExecutionPlan, wind: WindStrength, direction: WindDirection) -> ExecutionPlan {
        var plan = plan
        guard wind != .none else { return plan }

        if direction == .into && (wind == .moderate || wind == .strong) {
            plan.tempo = "smooth — do not swing harder into wind"
            plan.mistakeToAvoid = "do not swing harder to fight the wind — smooth tempo keeps spin down"
        }
        if direction == .helping {
            plan.strikeIntention += " — helping wind will add carry"
        }
        return plan
    }

    static func adjustForLie(plan: ExecutionPlan, lie: LieType, archetype: ExecutionArchetype) -> ExecutionPlan {
        var plan = plan
        switch lie {
        case .hardpan:
            plan.strikeIntention = "pick it clean — no room for fat contact on hardpan"
            plan.mistakeToAvoid = "do not hit behind the ball on hardpan"
        case .pineStraw:
            plan.setupSummary += " Don't ground the club."
            plan.mistakeToAvoid = "do not ground the club at address — hover it"
        case .firstCut:
            plan.strikeIntention += " — first cut may grab the hosel slightly"
        default:
            break
        }
        return plan
    }

    // MARK: - Player Preference Adjustments

    static func adjustForPlayerPreferences(
        plan: ExecutionPlan,
        profile: PlayerProfile,
        archetype: ExecutionArchetype
    ) -> ExecutionPlan {
        var plan = plan

        // Bunker confidence adjustments
        if archetype == .bunkerExplosion {
            switch profile.bunkerConfidence {
            case .low:
                plan.swingThought = "commit to the sand — trust the bounce and accelerate through"
                plan.setupSummary += " Stay confident: open the face and let the club do the work."
                plan.mistakeToAvoid = "do not decelerate through the sand — commit fully"
            case .high:
                break // Template is already good for confident bunker players
            case .average:
                break
            }
        }

        // Wedge confidence adjustments for partial wedges and pitches
        if archetype == .partialWedge || archetype == .softPitch || archetype == .standardPitch {
            switch profile.wedgeConfidence {
            case .low:
                plan.swingThought = "match your backswing and follow-through — smooth and simple"
                plan.mistakeToAvoid = "do not get too cute — pick a comfortable swing length and commit"
            case .high:
                break
            case .average:
                break
            }
        }

        // Swing tendency adjustments
        switch profile.swingTendency {
        case .steep:
            if archetype == .bunkerExplosion {
                plan.strikeIntention = "use your natural steep angle — enter the sand close behind the ball"
                plan.mistakeToAvoid = "do not dig too deep — let the bounce glide through"
            }
            if archetype == .bumpAndRunChip || archetype == .standardChip {
                plan.strikeIntention += " — your steep angle helps with clean contact"
            }
        case .shallow:
            if archetype == .bunkerExplosion {
                plan.setupSummary += " Open the face extra to use your shallow path."
                plan.strikeIntention = "splash wide and shallow — use the bounce of the club"
            }
            if archetype == .stockFullSwing || archetype == .knockdownApproach {
                plan.strikeIntention += " — stay down through the ball"
            }
        case .neutral:
            break
        }

        return plan
    }

    // MARK: - Helpers

    private static func adjustBallPosition(_ current: String, toward direction: String) -> String {
        "\(current), \(direction) for the slope"
    }
}
