package com.caddieai.android.data.engine

import com.caddieai.android.data.model.Aggressiveness
import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.LieType
import com.caddieai.android.data.model.MissTendency
import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext
import com.caddieai.android.data.model.ShotType
import com.caddieai.android.data.model.StockShape
import com.caddieai.android.data.model.WindStrength

data class ShotArchetype(
    val ballPosition: String,
    val stanceWidth: String,
    val weightDistribution: String,
    val swingTempo: String,
    val targetLine: String,
    val keyThoughts: List<String>,
)

/**
 * Deterministic engine that generates shot setup instructions (archetype)
 * based on the club and shot context, without an LLM call.
 */
object ExecutionEngine {

    fun buildArchetype(
        club: Club,
        context: ShotContext,
        profile: PlayerProfile,
    ): ShotArchetype = ShotArchetype(
        ballPosition = ballPosition(club, context.shotType, context.lie),
        stanceWidth = stanceWidth(club, context.shotType),
        weightDistribution = weightDistribution(context.lie, context.shotType),
        swingTempo = swingTempo(club, context.shotType, profile),
        targetLine = targetLine(context, profile),
        keyThoughts = keyThoughts(club, context, profile),
    )

    private fun ballPosition(club: Club, shotType: ShotType, lie: LieType): String = when {
        shotType == ShotType.PUTT -> "off left toe"
        shotType == ShotType.CHIP || shotType == ShotType.BUMP_AND_RUN -> "back of center"
        shotType == ShotType.FLOP -> "center to slightly forward"
        club == Club.DRIVER -> "off left heel"
        club in listOf(Club.THREE_WOOD, Club.FIVE_WOOD) -> "slightly inside left heel"
        club.ordinal <= Club.FIVE_IRON.ordinal -> "slightly forward of center"
        lie == LieType.DOWNHILL -> "slightly back of center"
        lie == LieType.UPHILL -> "slightly forward of center"
        else -> "center of stance"
    }

    private fun stanceWidth(club: Club, shotType: ShotType): String = when {
        shotType == ShotType.PUTT -> "feet together"
        shotType == ShotType.CHIP || shotType == ShotType.BUMP_AND_RUN -> "narrow"
        shotType == ShotType.FLOP -> "slightly open, shoulder-width"
        club == Club.DRIVER -> "just outside shoulder-width"
        club.ordinal <= Club.FIVE_IRON.ordinal -> "shoulder-width"
        else -> "slightly inside shoulder-width"
    }

    private fun weightDistribution(lie: LieType, shotType: ShotType): String = when {
        shotType == ShotType.CHIP || shotType == ShotType.BUMP_AND_RUN -> "70% front foot"
        lie == LieType.DOWNHILL -> "60% front foot to maintain balance"
        lie == LieType.UPHILL -> "60% back foot, let the hill be your friend"
        lie == LieType.SIDEHILL_ABOVE -> "50/50, sit into the hill"
        lie == LieType.SIDEHILL_BELOW -> "50/50, stand taller"
        else -> "50/50"
    }

    private fun swingTempo(club: Club, shotType: ShotType, profile: PlayerProfile): String = when {
        shotType == ShotType.PUTT -> "smooth, pendulum stroke"
        shotType == ShotType.FLOP -> "aggressive through-swing, slow backswing"
        shotType == ShotType.PUNCH -> "three-quarter backswing, controlled follow-through"
        shotType == ShotType.CHIP || shotType == ShotType.BUMP_AND_RUN -> "small controlled swing, lead with hands"
        club == Club.DRIVER -> when (profile.aggressiveness) {
            Aggressiveness.AGGRESSIVE -> "full, powerful swing"
            Aggressiveness.CONSERVATIVE -> "smooth 85%, stay in balance"
            else -> "smooth 90% swing"
        }
        else -> "smooth, balanced swing — don't force it"
    }

    private fun targetLine(context: ShotContext, profile: PlayerProfile): String {
        return when (context.shotType) {
            ShotType.PUTT -> "pick a spot 2 feet in front of ball on intended line"
            ShotType.CHIP, ShotType.BUMP_AND_RUN -> "aim at landing spot, let ball roll to pin"
            else -> when (profile.stockShape) {
                StockShape.DRAW -> "aim slightly right, let the draw work to target"
                StockShape.FADE -> "aim slightly left, let the fade work to target"
                StockShape.HIGH_DRAW -> "aim right, play high draw"
                StockShape.HIGH_FADE -> "aim left, play high fade"
                StockShape.STINGER -> "low trajectory, aim directly at target"
                else -> "aim directly at target"
            }
        }
    }

    private fun keyThoughts(club: Club, context: ShotContext, profile: PlayerProfile): List<String> {
        return when (context.shotType) {
            ShotType.PUTT -> listOf("Pace first, then line", "Keep head still through impact", "Accelerate through the ball")
            ShotType.CHIP, ShotType.BUMP_AND_RUN -> listOf("Hands lead at impact", "Quiet lower body", "Pick a landing spot")
            ShotType.FLOP -> listOf("Open club face first, then grip", "Swing left through the ball", "Commit — no deceleration")
            ShotType.BUNKER -> listOf("Hit the sand 2 inches before ball", "Full follow-through", "Open stance and club face")
            ShotType.PUNCH -> listOf("Three-quarter back", "Hands forward at impact", "Low finish")
            else -> buildList {
                add("Smooth tempo — don't force it")
                if (context.windStrength != WindStrength.CALM) add("Ball below the wind")
                when (profile.missTendency) {
                    MissTendency.SLICE -> add("Rotate through, finish high")
                    MissTendency.HOOK -> add("Hold the face through impact")
                    else -> add("Balanced finish")
                }
            }.take(3)
        }
    }
}
