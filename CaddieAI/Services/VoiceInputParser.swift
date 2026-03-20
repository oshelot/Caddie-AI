//
//  VoiceInputParser.swift
//  CaddieAI
//
//  Parses natural language voice transcriptions to extract shot context fields.
//  Unrecognized portions are preserved as voice notes for the LLM.
//

import Foundation

struct VoiceInputParser {

    struct ParseResult {
        var distance: Int?
        var shotType: ShotType?
        var lieType: LieType?
        var windStrength: WindStrength?
        var windDirection: WindDirection?
        var slope: Slope?
        var aggressiveness: Aggressiveness?
        var hazardNotes: String?
        var remainingNotes: String
    }

    static func parse(_ text: String) -> ParseResult {
        let lower = text.lowercased()

        return ParseResult(
            distance: parseDistance(lower),
            shotType: parseShotType(lower),
            lieType: parseLieType(lower),
            windStrength: parseWindStrength(lower),
            windDirection: parseWindDirection(lower),
            slope: parseSlope(lower),
            aggressiveness: parseAggressiveness(lower),
            hazardNotes: parseHazards(lower),
            remainingNotes: buildRemainingNotes(text)
        )
    }

    /// Apply parsed fields to a ShotContext, only overriding fields that were detected
    static func apply(_ result: ParseResult, to context: inout ShotContext, voiceNotes: inout String) {
        if let distance = result.distance {
            context.distanceYards = distance
        }
        if let shotType = result.shotType {
            context.shotType = shotType
        }
        if let lieType = result.lieType {
            context.lieType = lieType
        }
        if let windStrength = result.windStrength {
            context.windStrength = windStrength
        }
        if let windDirection = result.windDirection {
            context.windDirection = windDirection
        }
        if let slope = result.slope {
            context.slope = slope
        }
        if let aggressiveness = result.aggressiveness {
            context.aggressiveness = aggressiveness
        }
        if let hazards = result.hazardNotes, !hazards.isEmpty {
            if context.hazardNotes.isEmpty {
                context.hazardNotes = hazards
            } else {
                context.hazardNotes += ". " + hazards
            }
        }
        if !result.remainingNotes.isEmpty {
            voiceNotes = result.remainingNotes
        }
    }

    // MARK: - Distance

    private static func parseDistance(_ text: String) -> Int? {
        // Match patterns like "170 yards", "170 yard", "170", "one seventy"
        let patterns: [(String, Int)] = [
            ("two hundred", 200), ("two fifty", 250), ("two forty", 240),
            ("two thirty", 230), ("two twenty", 220), ("two ten", 210),
            ("one hundred", 100), ("one fifty", 150), ("one forty", 140),
            ("one thirty", 130), ("one twenty", 120), ("one ten", 110),
            ("one sixty", 160), ("one seventy", 170), ("one eighty", 180),
            ("one ninety", 190),
        ]

        for (word, value) in patterns {
            if text.contains(word) { return value }
        }

        // Numeric patterns: "170 yards", "170 yard", "170 out", or just a 2-3 digit number
        let yardRegex = try? NSRegularExpression(pattern: #"(\d{2,3})\s*(?:yard|yards|out|yds)"#)
        if let match = yardRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let value = Int(text[range]) {
            return value
        }

        // Standalone number between 30-300 (likely a yardage)
        let numberRegex = try? NSRegularExpression(pattern: #"\b(\d{2,3})\b"#)
        if let match = numberRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let value = Int(text[range]),
           (30...300).contains(value) {
            return value
        }

        return nil
    }

    // MARK: - Shot Type

    private static func parseShotType(_ text: String) -> ShotType? {
        if text.contains("tee") || text.contains("tee shot") || text.contains("tee box") || text.contains("teeing") {
            return .tee
        }
        if text.contains("chip") || text.contains("chipping") {
            return .chip
        }
        if text.contains("pitch") || text.contains("pitching") {
            return .pitch
        }
        if text.contains("bunker") || text.contains("sand") || text.contains("trap") {
            return .bunker
        }
        if text.contains("punch") || text.contains("recovery") || text.contains("under the tree") || text.contains("under trees") {
            return .punchRecovery
        }
        if text.contains("layup") || text.contains("lay up") || text.contains("laying up") {
            return .layup
        }
        if text.contains("approach") {
            return .approach
        }
        return nil
    }

    // MARK: - Lie Type

    private static func parseLieType(_ text: String) -> LieType? {
        // Order matters — check more specific phrases first
        if text.contains("deep rough") || text.contains("thick rough") || text.contains("heavy rough") {
            return .deepRough
        }
        if text.contains("first cut") || text.contains("light rough") {
            return .firstCut
        }
        if text.contains("greenside bunker") || text.contains("green side bunker") {
            return .greensideBunker
        }
        if text.contains("fairway bunker") {
            return .fairwayBunker
        }
        if text.contains("bunker") || text.contains("sand") || text.contains("trap") {
            // Infer greenside vs fairway from distance if available
            return .greensideBunker
        }
        if text.contains("rough") {
            return .rough
        }
        if text.contains("hardpan") || text.contains("hard pan") || text.contains("bare") || text.contains("dirt") {
            return .hardpan
        }
        if text.contains("pine straw") || text.contains("pine needles") {
            return .pineStraw
        }
        if text.contains("tree") || text.contains("obstructed") || text.contains("blocked") {
            return .treesObstructed
        }
        if text.contains("fairway") {
            return .fairway
        }
        return nil
    }

    // MARK: - Wind

    private static func parseWindStrength(_ text: String) -> WindStrength? {
        if text.contains("no wind") || text.contains("calm") || text.contains("still") {
            return WindStrength.none
        }
        if text.contains("strong wind") || text.contains("heavy wind") || text.contains("really windy") || text.contains("very windy") {
            return .strong
        }
        if text.contains("moderate wind") || text.contains("medium wind") || text.contains("some wind") || text.contains("windy") {
            return .moderate
        }
        if text.contains("light wind") || text.contains("slight wind") || text.contains("little wind") || text.contains("breeze") {
            return .light
        }
        // Just "wind" with a direction implies at least light
        if text.contains("wind") || text.contains("into the wind") || text.contains("downwind") {
            return .moderate
        }
        return nil
    }

    private static func parseWindDirection(_ text: String) -> WindDirection? {
        if text.contains("into") || text.contains("in my face") || text.contains("headwind") || text.contains("into the wind") {
            return .into
        }
        if text.contains("helping") || text.contains("downwind") || text.contains("behind me") || text.contains("with the wind") || text.contains("at my back") {
            return .helping
        }
        if text.contains("left to right") || text.contains("left-to-right") {
            return .crossLeftToRight
        }
        if text.contains("right to left") || text.contains("right-to-left") {
            return .crossRightToLeft
        }
        return nil
    }

    // MARK: - Slope

    private static func parseSlope(_ text: String) -> Slope? {
        if text.contains("ball above") || text.contains("above my feet") || text.contains("above feet") {
            return .ballAboveFeet
        }
        if text.contains("ball below") || text.contains("below my feet") || text.contains("below feet") {
            return .ballBelowFeet
        }
        if text.contains("uphill") || text.contains("up hill") || text.contains("going up") {
            return .uphill
        }
        if text.contains("downhill") || text.contains("down hill") || text.contains("going down") {
            return .downhill
        }
        if text.contains("flat") || text.contains("level") {
            return .level
        }
        return nil
    }

    // MARK: - Aggressiveness

    private static func parseAggressiveness(_ text: String) -> Aggressiveness? {
        if text.contains("aggressive") || text.contains("go for it") || text.contains("attack") || text.contains("fire at") {
            return .aggressive
        }
        if text.contains("conservative") || text.contains("safe") || text.contains("play it safe") || text.contains("bail out") {
            return .conservative
        }
        return nil
    }

    // MARK: - Hazards

    private static func parseHazards(_ text: String) -> String? {
        var hazards: [String] = []

        if text.contains("water") || text.contains("lake") || text.contains("pond") || text.contains("creek") {
            let side = extractSide(from: text, near: ["water", "lake", "pond", "creek"])
            hazards.append("Water\(side)")
        }
        if text.contains("ob") || text.contains("out of bounds") || text.contains("o.b.") || text.contains("o b") {
            let side = extractSide(from: text, near: ["ob", "out of bounds", "o.b."])
            hazards.append("OB\(side)")
        }
        if text.contains("bunker") || text.contains("sand") || text.contains("trap") {
            // Only add as hazard note if lie is not already bunker
            let side = extractSide(from: text, near: ["bunker", "sand", "trap"])
            if !text.contains("in the bunker") && !text.contains("from the bunker") && !text.contains("in the sand") {
                hazards.append("Bunker\(side)")
            }
        }
        if text.contains("drop off") || text.contains("drop-off") || text.contains("falls off") {
            hazards.append("Drop-off")
        }

        return hazards.isEmpty ? nil : hazards.joined(separator: ", ")
    }

    private static func extractSide(from text: String, near keywords: [String]) -> String {
        for keyword in keywords {
            if let range = text.range(of: keyword) {
                let nearby = text[text.startIndex..<range.upperBound]
                let afterKeyword = text[range.upperBound...]

                let context = String(nearby) + " " + String(afterKeyword.prefix(30))

                if context.contains("right") { return " right" }
                if context.contains("left") { return " left" }
                if context.contains("front") || context.contains("short") { return " front" }
                if context.contains("behind") || context.contains("long") || context.contains("back") { return " behind" }
            }
        }
        return ""
    }

    // MARK: - Remaining Notes

    private static func buildRemainingNotes(_ text: String) -> String {
        // Keep the full transcription as notes — the LLM benefits from having the raw context
        // even after we've extracted structured fields
        text
    }
}
