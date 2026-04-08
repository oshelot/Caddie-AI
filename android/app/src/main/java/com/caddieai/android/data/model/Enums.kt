package com.caddieai.android.data.model

import kotlinx.serialization.Serializable

@Serializable
enum class Club(val displayName: String, val defaultCarryYards: Int) {
    DRIVER("Driver", 230),
    TWO_WOOD("2 Wood", 220),
    THREE_WOOD("3 Wood", 210),
    FOUR_WOOD("4 Wood", 200),
    FIVE_WOOD("5 Wood", 195),
    SEVEN_WOOD("7 Wood", 182),
    TWO_HYBRID("2 Hybrid", 205),
    THREE_HYBRID("3 Hybrid", 192),
    FOUR_HYBRID("4 Hybrid", 182),
    FIVE_HYBRID("5 Hybrid", 172),
    SIX_HYBRID("6 Hybrid", 162),
    ONE_IRON("1 Iron", 210),
    TWO_IRON("2 Iron", 195),
    THREE_IRON("3 Iron", 182),
    FOUR_IRON("4 Iron", 170),
    FIVE_IRON("5 Iron", 158),
    SIX_IRON("6 Iron", 148),
    SEVEN_IRON("7 Iron", 138),
    EIGHT_IRON("8 Iron", 128),
    NINE_IRON("9 Iron", 118),
    PITCHING_WEDGE("PW", 108),
    GAP_WEDGE("GW", 98),
    FIFTY_TWO_WEDGE("52°", 93),
    SAND_WEDGE("SW", 88),
    FIFTY_SIX_WEDGE("56°", 78),
    LOB_WEDGE("LW", 68),
    FIFTY_EIGHT_WEDGE("58°", 62),
    SIXTY_DEGREE("60°", 55),
    CHIPPER("Chipper", 35),
    PUTTER("Putter", 0),
}

@Serializable
enum class ShotType {
    FULL_SWING,
    APPROACH,
    CHIP,
    PITCH,
    FLOP,
    PUNCH,
    BUMP_AND_RUN,
    BUNKER,
    FAIRWAY_BUNKER,
    LAYUP,
    PUTT,
    DRIVER;

    /** Returns the set of valid lies for this shot type. Empty = picker hidden. */
    fun validLies(): List<LieType> = when (this) {
        DRIVER -> emptyList() // Tee shot — lie picker hidden
        PUTT -> listOf(LieType.GREEN, LieType.FRINGE)
        BUNKER -> listOf(LieType.BUNKER)
        FAIRWAY_BUNKER -> listOf(LieType.FAIRWAY_BUNKER)
        PUNCH -> listOf(LieType.ROUGH, LieType.DEEP_ROUGH, LieType.WET_ROUGH, LieType.HARDPAN, LieType.DIVOT)
        // All other shot types: standard non-bunker lies
        else -> listOf(
            LieType.FAIRWAY, LieType.ROUGH, LieType.DEEP_ROUGH, LieType.WET_ROUGH,
            LieType.HARDPAN, LieType.DIVOT, LieType.UPHILL, LieType.DOWNHILL,
            LieType.SIDEHILL_ABOVE, LieType.SIDEHILL_BELOW, LieType.FRINGE,
        )
    }

    /** Returns the default lie for this shot type. */
    fun defaultLie(): LieType = when (this) {
        DRIVER -> LieType.TEE_BOX
        PUTT -> LieType.GREEN
        BUNKER -> LieType.BUNKER
        FAIRWAY_BUNKER -> LieType.FAIRWAY_BUNKER
        PUNCH -> LieType.ROUGH
        CHIP, PITCH, FLOP, BUMP_AND_RUN -> LieType.FRINGE
        else -> LieType.FAIRWAY
    }
}

@Serializable
enum class LieType {
    TEE_BOX,
    FAIRWAY,
    ROUGH,
    DEEP_ROUGH,
    BUNKER,
    FAIRWAY_BUNKER,
    FRINGE,
    GREEN,
    HARDPAN,
    DIVOT,
    WET_ROUGH,
    UPHILL,
    DOWNHILL,
    SIDEHILL_ABOVE,
    SIDEHILL_BELOW,
}

@Serializable
enum class WindStrength(val label: String, val mph: IntRange) {
    CALM("Calm", 0..5),
    LIGHT("Light", 6..10),
    MODERATE("Moderate", 11..15),
    STRONG("Strong", 16..20),
    VERY_STRONG("Very Strong", 21..50),
}

@Serializable
enum class WindDirection {
    NONE,
    HEADWIND,
    TAILWIND,
    LEFT_TO_RIGHT,
    RIGHT_TO_LEFT,
    CROSS_HEADWIND_LEFT,
    CROSS_HEADWIND_RIGHT,
    CROSS_TAILWIND_LEFT,
    CROSS_TAILWIND_RIGHT,
}

@Serializable
enum class Slope {
    FLAT,
    UPHILL_SLIGHT,
    UPHILL_MODERATE,
    UPHILL_STEEP,
    DOWNHILL_SLIGHT,
    DOWNHILL_MODERATE,
    DOWNHILL_STEEP,
}

@Serializable
enum class StockShape {
    STRAIGHT,
    DRAW,
    FADE,
    HIGH_DRAW,
    HIGH_FADE,
    LOW_DRAW,
    LOW_FADE,
    STINGER,
}

@Serializable
enum class MissTendency {
    NONE,
    PULL,
    PUSH,
    HOOK,
    SLICE,
    THIN,
    FAT,
    TOP,
}

@Serializable
enum class Aggressiveness {
    CONSERVATIVE,
    MODERATE,
    AGGRESSIVE,
}

@Serializable
enum class BunkerConfidence {
    LOW,
    MEDIUM,
    HIGH,
}

@Serializable
enum class WedgeConfidence {
    LOW,
    MEDIUM,
    HIGH,
}

@Serializable
enum class ChipStyle {
    BUMP_AND_RUN,
    LOFTED_CHIP,
    FLOP,
    PITCH_AND_RUN,
}

@Serializable
enum class SwingTendency {
    OVER_THE_TOP,
    INSIDE_OUT,
    NEUTRAL,
}

@Serializable
enum class CaddieGender {
    MALE,
    FEMALE,
    NEUTRAL,
}

@Serializable
enum class CaddieAccent {
    AMERICAN,
    BRITISH,
    SCOTTISH,
    IRISH,
    AUSTRALIAN,
}

@Serializable
enum class LLMProvider {
    OPENAI,
    ANTHROPIC,
    GOOGLE,
    BEDROCK,
}

@Serializable
enum class UserTier {
    FREE,
    PRO,
}

@Serializable
enum class Outcome(val displayName: String, val emoji: String) {
    GREAT("Great", "\uD83D\uDD25"),
    GOOD("Good", "\uD83D\uDC4D"),
    OKAY("Okay", "\uD83D\uDE10"),
    POOR("Poor", "\uD83D\uDC4E"),
    MISHIT("Mishit", "\uD83D\uDC80"),
    UNKNOWN("", "—"),
}

@Serializable
enum class CaddiePersona(val rawValue: String, val displayName: String) {
    PROFESSIONAL("professional", "Professional"),
    SUPPORTIVE_GRANDPARENT("supportiveGrandparent", "Supportive Grandparent"),
    COLLEGE_BUDDY("collegeBuddy", "College Buddy"),
    DRILL_SERGEANT("drillSergeant", "Drill Sergeant"),
    CHILL_SURFER("chillSurfer", "Chill Surfer"),
}

@Serializable
enum class TeeBoxPreference(val displayName: String, val matchKeywords: List<String>) {
    CHAMPIONSHIP("Black / Championship", listOf("championship", "black", "tiger")),
    BLUE("Blue", listOf("blue")),
    WHITE("White", listOf("white")),
    SENIOR("Gold / Silver", listOf("gold", "silver", "senior")),
    FORWARD("Red / Forward", listOf("red", "forward", "ladies")),
}

@Serializable
enum class IronType(val displayName: String) {
    GAME_IMPROVEMENT("Regular"),
    SUPER_GAME_IMPROVEMENT("Super"),
}
