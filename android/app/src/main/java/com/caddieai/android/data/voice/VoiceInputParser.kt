package com.caddieai.android.data.voice

import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.LieType
import com.caddieai.android.data.model.Slope
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotType
import com.caddieai.android.data.model.WindDirection
import com.caddieai.android.data.model.WindStrength
import javax.inject.Inject
import javax.inject.Singleton

data class ParsedVoiceInput(
    val distanceToPin: Int? = null,
    val shotType: ShotType? = null,
    val lie: LieType? = null,
    val windStrength: WindStrength? = null,
    val windDirection: WindDirection? = null,
    val slope: Slope? = null,
    val elevationChangeYards: Int? = null,
    val holeNumber: Int? = null,
    val par: Int? = null,
    val hazardNotes: String = "",
    val suggestedClub: Club? = null,
    val rawText: String = "",
)

@Singleton
class VoiceInputParser @Inject constructor() {

    fun parse(text: String): ParsedVoiceInput {
        val lower = text.lowercase()

        return ParsedVoiceInput(
            rawText = text,
            distanceToPin = parseDistance(lower),
            shotType = parseShotType(lower),
            lie = parseLie(lower),
            windStrength = parseWindStrength(lower),
            windDirection = parseWindDirection(lower),
            slope = parseSlope(lower),
            elevationChangeYards = parseElevation(lower),
            holeNumber = parseHoleNumber(lower),
            par = parsePar(lower),
            hazardNotes = parseHazardNotes(lower),
            suggestedClub = parseClub(lower),
        )
    }

    /** Apply parsed voice input onto an existing ShotContext, keeping existing values where not parsed. */
    fun applyToCo(parsed: ParsedVoiceInput, existing: ShotContext): ShotContext = existing.copy(
        distanceToPin = parsed.distanceToPin ?: existing.distanceToPin,
        shotType = parsed.shotType ?: existing.shotType,
        lie = parsed.lie ?: existing.lie,
        windStrength = parsed.windStrength ?: existing.windStrength,
        windDirection = parsed.windDirection ?: existing.windDirection,
        slope = parsed.slope ?: existing.slope,
        elevationChangeYards = parsed.elevationChangeYards ?: existing.elevationChangeYards,
        holeNumber = parsed.holeNumber ?: existing.holeNumber,
        par = parsed.par ?: existing.par,
        hazardNotes = parsed.hazardNotes.ifBlank { existing.hazardNotes },
    )

    private fun parseDistance(text: String): Int? {
        // "150 yards", "one fifty", "about 175", "180 to the pin"
        val regex = Regex("""(\d{2,3})\s*(?:yards?|yds?|to the (?:pin|flag|green))?""")
        return regex.find(text)?.groupValues?.get(1)?.toIntOrNull()
            ?.takeIf { it in 10..600 }
    }

    private fun parseShotType(text: String): ShotType? = when {
        "putt" in text || "putting" in text -> ShotType.PUTT
        "chip" in text || "chipping" in text -> ShotType.CHIP
        "pitch" in text || "pitching" in text -> ShotType.PITCH
        "flop" in text -> ShotType.FLOP
        "punch" in text -> ShotType.PUNCH
        "bump" in text && "run" in text -> ShotType.BUMP_AND_RUN
        "bunker" in text && ("shot" in text || "sand" in text) -> ShotType.BUNKER
        "layup" in text || "lay up" in text -> ShotType.LAYUP
        "driver" in text || "tee shot" in text || "off the tee" in text -> ShotType.DRIVER
        "approach" in text -> ShotType.APPROACH
        else -> null
    }

    private fun parseLie(text: String): LieType? = when {
        "deep rough" in text || "heavy rough" in text -> LieType.DEEP_ROUGH
        "rough" in text -> LieType.ROUGH
        "wet rough" in text -> LieType.WET_ROUGH
        "fairway bunker" in text -> LieType.FAIRWAY_BUNKER
        "bunker" in text || "sand" in text -> LieType.BUNKER
        "fairway" in text -> LieType.FAIRWAY
        "tee box" in text || "tee" in text -> LieType.TEE_BOX
        "fringe" in text || "collar" in text -> LieType.FRINGE
        "green" in text -> LieType.GREEN
        "hardpan" in text || "hard pan" in text -> LieType.HARDPAN
        "divot" in text -> LieType.DIVOT
        "uphill lie" in text || "uphill slope" in text -> LieType.UPHILL
        "downhill lie" in text || "downhill slope" in text -> LieType.DOWNHILL
        "sidehill above" in text -> LieType.SIDEHILL_ABOVE
        "sidehill below" in text -> LieType.SIDEHILL_BELOW
        else -> null
    }

    private fun parseWindStrength(text: String): WindStrength? = when {
        "no wind" in text || "calm" in text || "still" in text -> WindStrength.CALM
        Regex("""(\d+)\s*mph""").find(text)?.let { m ->
            m.groupValues[1].toIntOrNull()
        }?.let { mph ->
            when {
                mph <= 5 -> WindStrength.CALM
                mph <= 10 -> WindStrength.LIGHT
                mph <= 15 -> WindStrength.MODERATE
                mph <= 20 -> WindStrength.STRONG
                else -> WindStrength.VERY_STRONG
            }
        } != null -> Regex("""(\d+)\s*mph""").find(text)?.let { m ->
            m.groupValues[1].toIntOrNull()
        }?.let { mph ->
            when {
                mph <= 5 -> WindStrength.CALM
                mph <= 10 -> WindStrength.LIGHT
                mph <= 15 -> WindStrength.MODERATE
                mph <= 20 -> WindStrength.STRONG
                else -> WindStrength.VERY_STRONG
            }
        }
        "light wind" in text || "light breeze" in text -> WindStrength.LIGHT
        "moderate wind" in text || "moderate breeze" in text -> WindStrength.MODERATE
        "strong wind" in text || "strong breeze" in text -> WindStrength.STRONG
        "very strong" in text || "gust" in text -> WindStrength.VERY_STRONG
        "wind" in text || "breeze" in text -> WindStrength.LIGHT
        else -> null
    }

    private fun parseWindDirection(text: String): WindDirection? = when {
        "headwind" in text || "into the wind" in text || "wind in my face" in text -> WindDirection.HEADWIND
        "tailwind" in text || "wind at my back" in text || "downwind" in text -> WindDirection.TAILWIND
        "left to right" in text -> WindDirection.LEFT_TO_RIGHT
        "right to left" in text -> WindDirection.RIGHT_TO_LEFT
        "cross" in text && "head" in text && "left" in text -> WindDirection.CROSS_HEADWIND_LEFT
        "cross" in text && "head" in text && "right" in text -> WindDirection.CROSS_HEADWIND_RIGHT
        "cross" in text && "tail" in text && "left" in text -> WindDirection.CROSS_TAILWIND_LEFT
        "cross" in text && "tail" in text && "right" in text -> WindDirection.CROSS_TAILWIND_RIGHT
        "no wind" in text || "calm" in text -> WindDirection.NONE
        else -> null
    }

    private fun parseSlope(text: String): Slope? = when {
        "steeply uphill" in text || "steep uphill" in text -> Slope.UPHILL_STEEP
        "moderately uphill" in text -> Slope.UPHILL_MODERATE
        "slightly uphill" in text || "little uphill" in text -> Slope.UPHILL_SLIGHT
        "uphill" in text -> Slope.UPHILL_SLIGHT
        "steeply downhill" in text || "steep downhill" in text -> Slope.DOWNHILL_STEEP
        "moderately downhill" in text -> Slope.DOWNHILL_MODERATE
        "slightly downhill" in text || "little downhill" in text -> Slope.DOWNHILL_SLIGHT
        "downhill" in text -> Slope.DOWNHILL_SLIGHT
        "flat" in text || "level" in text -> Slope.FLAT
        else -> null
    }

    private fun parseElevation(text: String): Int? {
        val regex = Regex("""(\d+)\s*(?:yards?|yds?|feet|ft)?\s*(?:up|down|higher|lower|elevation)""")
        val match = regex.find(text) ?: return null
        val yards = match.groupValues[1].toIntOrNull() ?: return null
        return if ("down" in text || "lower" in text) -yards else yards
    }

    private fun parseHoleNumber(text: String): Int? {
        val regex = Regex("""hole\s+(?:number\s+)?(\d{1,2})|(?:on\s+)?hole\s+(\w+)""")
        val match = regex.find(text) ?: return null
        return match.groupValues[1].toIntOrNull()
            ?: wordToNumber(match.groupValues[2])
    }

    private fun parsePar(text: String): Int? {
        val regex = Regex("""par\s+(\d)""")
        return regex.find(text)?.groupValues?.get(1)?.toIntOrNull()?.takeIf { it in 3..5 }
    }

    private fun parseHazardNotes(text: String): String {
        val hazards = mutableListOf<String>()
        if ("water" in text || "lake" in text || "pond" in text) hazards.add("water")
        if ("tree" in text || "trees" in text || "woods" in text) hazards.add("trees")
        if ("out of bounds" in text || "ob" in text) hazards.add("OB")
        return hazards.joinToString(", ")
    }

    private fun parseClub(text: String): Club? = when {
        "driver" in text -> Club.DRIVER
        "three wood" in text || "3 wood" in text || "3-wood" in text -> Club.THREE_WOOD
        "five wood" in text || "5 wood" in text -> Club.FIVE_WOOD
        "three iron" in text || "3 iron" in text -> Club.THREE_IRON
        "four iron" in text || "4 iron" in text -> Club.FOUR_IRON
        "five iron" in text || "5 iron" in text -> Club.FIVE_IRON
        "six iron" in text || "6 iron" in text -> Club.SIX_IRON
        "seven iron" in text || "7 iron" in text -> Club.SEVEN_IRON
        "eight iron" in text || "8 iron" in text -> Club.EIGHT_IRON
        "nine iron" in text || "9 iron" in text -> Club.NINE_IRON
        "pitching wedge" in text || "pw" in text -> Club.PITCHING_WEDGE
        "gap wedge" in text || "gw" in text -> Club.GAP_WEDGE
        "sand wedge" in text || "sw" in text -> Club.SAND_WEDGE
        "lob wedge" in text || "lw" in text -> Club.LOB_WEDGE
        "putter" in text -> Club.PUTTER
        else -> null
    }

    private fun wordToNumber(word: String): Int? = when (word.trim()) {
        "one" -> 1; "two" -> 2; "three" -> 3; "four" -> 4; "five" -> 5
        "six" -> 6; "seven" -> 7; "eight" -> 8; "nine" -> 9; "ten" -> 10
        "eleven" -> 11; "twelve" -> 12; "thirteen" -> 13; "fourteen" -> 14
        "fifteen" -> 15; "sixteen" -> 16; "seventeen" -> 17; "eighteen" -> 18
        else -> null
    }
}
