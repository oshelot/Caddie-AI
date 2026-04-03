package com.caddieai.android.data.model

import kotlinx.serialization.Serializable

@Serializable
data class PlayerProfile(
    // Identity
    val name: String = "",
    val email: String = "",
    val phone: String = "",

    // Golf attributes
    val handicap: Float = 18.0f,
    val clubDistances: Map<Club, Int> = Club.entries.associate { it to it.defaultCarryYards },
    val bagClubs: Set<Club> = setOf(
        Club.DRIVER,
        Club.THREE_WOOD,
        Club.FIVE_WOOD,
        Club.FOUR_HYBRID,
        Club.FIVE_IRON,
        Club.SIX_IRON,
        Club.SEVEN_IRON,
        Club.EIGHT_IRON,
        Club.NINE_IRON,
        Club.PITCHING_WEDGE,
        Club.GAP_WEDGE,
        Club.SAND_WEDGE,
        Club.LOB_WEDGE,
    ),
    val stockShape: StockShape = StockShape.STRAIGHT,
    val missTendency: MissTendency = MissTendency.NONE,
    val aggressiveness: Aggressiveness = Aggressiveness.MODERATE,
    val bunkerConfidence: BunkerConfidence = BunkerConfidence.MEDIUM,
    val wedgeConfidence: WedgeConfidence = WedgeConfidence.MEDIUM,
    val chipStyle: ChipStyle = ChipStyle.BUMP_AND_RUN,
    val swingTendency: SwingTendency = SwingTendency.NEUTRAL,

    // App preferences
    val llmProvider: LLMProvider = LLMProvider.OPENAI,
    val userTier: UserTier = UserTier.FREE,
    val voiceEnabled: Boolean = true,
    val caddieGender: CaddieGender = CaddieGender.MALE,
    val caddieAccent: CaddieAccent = CaddieAccent.AMERICAN,
    val usesMetric: Boolean = false,

    // AI preferences
    val caddiePersona: CaddiePersona = CaddiePersona.PROFESSIONAL,
    val imageAnalysisBetaEnabled: Boolean = false,
    val includeClubAlternatives: Boolean = true,
    val includeWindAdjustment: Boolean = true,
    val includeSlopeAdjustment: Boolean = true,

    // API keys (stored locally, not synced)
    val openAiApiKey: String = "",
    val anthropicApiKey: String = "",
    val googleApiKey: String = "",

    // Onboarding state
    val setupNoticeSeen: Boolean = false,
    val contactPromptCount: Int = 0,
    val lastContactPromptMs: Long = 0L,
    val contactOptedIn: Boolean = false,

    // Debug overrides (debug builds only — never synced)
    val debugTierOverride: UserTier? = null,
    val debugLoggingEnabled: Boolean = false,

    // Metadata
    val createdAtMs: Long = System.currentTimeMillis(),
    val updatedAtMs: Long = System.currentTimeMillis(),
) {
    /** Effective tier — respects debug override when set. */
    val effectiveTier: UserTier get() = debugTierOverride ?: userTier

    fun withUpdatedAt(): PlayerProfile = copy(updatedAtMs = System.currentTimeMillis())
}
