package com.caddieai.android.data.llm

import com.caddieai.android.data.model.PlayerProfile
import com.caddieai.android.data.model.ShotContext

object PromptBuilder {

    fun buildShotPrompt(context: ShotContext, profile: PlayerProfile): String = buildString {
        appendLine("## Shot Situation")
        appendLine("- Distance: ${context.distanceToPin} yards")
        appendLine("- Shot type: ${context.shotType.name.replace('_', ' ').lowercase().replaceFirstChar { it.uppercase() }}")
        appendLine("- Lie: ${context.lie.name.replace('_', ' ').lowercase().replaceFirstChar { it.uppercase() }}")
        appendLine("- Wind: ${context.windStrength.label} ${context.windDirection.name.replace('_', ' ').lowercase()}")
        appendLine("- Slope: ${context.slope.name.replace('_', ' ').lowercase()}")
        if (context.elevationChangeYards != 0) {
            val dir = if (context.elevationChangeYards > 0) "uphill" else "downhill"
            appendLine("- Elevation: ${kotlin.math.abs(context.elevationChangeYards)} yards $dir")
        }
        if (context.hazardNotes.isNotBlank()) appendLine("- Hazards: ${context.hazardNotes}")
        if (context.pinPosition.isNotBlank()) appendLine("- Pin position: ${context.pinPosition}")
        if (context.greenFirmness.isNotBlank()) appendLine("- Green firmness: ${context.greenFirmness}")
        context.holeNumber?.let { appendLine("- Hole: $it, Par ${context.par ?: "?"}") }

        appendLine()
        appendLine("## Player Profile")
        appendLine("- Handicap: ${profile.handicap}")
        appendLine("- Stock shot shape: ${profile.stockShape.name.lowercase()}")
        appendLine("- Miss tendency: ${profile.missTendency.name.lowercase()}")
        appendLine("- Aggressiveness: ${(context.aggressiveness ?: profile.aggressiveness).name.lowercase()}")
        appendLine("- Bunker confidence: ${profile.bunkerConfidence.name.lowercase()}")
        appendLine("- Chip style: ${profile.chipStyle.name.replace('_', ' ').lowercase()}")
        appendLine("- Caddie persona: ${profile.caddiePersona.displayName}")

        appendLine()
        appendLine("## Club Distances (yards)")
        profile.clubDistances.entries
            .sortedByDescending { it.value }
            .forEach { (club, yards) ->
                appendLine("- ${club.displayName}: $yards yards")
            }

        appendLine()
        appendLine("Provide your caddie recommendation as JSON only.")
    }
}
