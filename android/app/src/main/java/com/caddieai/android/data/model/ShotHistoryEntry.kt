package com.caddieai.android.data.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class ShotHistoryEntry(
    val id: String = UUID.randomUUID().toString(),
    val timestampMs: Long = System.currentTimeMillis(),
    val courseId: String? = null,
    val courseName: String = "",
    val context: ShotContext,
    val recommendation: ShotRecommendation? = null,
    val outcome: Outcome = Outcome.UNKNOWN,
    val actualClubUsed: Club? = null,
    val notes: String = "",
)

@Serializable
data class RoundSummary(
    val id: String = UUID.randomUUID().toString(),
    val courseId: String? = null,
    val courseName: String = "",
    val dateMs: Long = System.currentTimeMillis(),
    val holesPlayed: Int = 18,
    val totalScore: Int = 0,
    val totalPar: Int = 72,
    val shots: List<ShotHistoryEntry> = emptyList(),
) {
    val scoreToPar: Int get() = totalScore - totalPar
}
