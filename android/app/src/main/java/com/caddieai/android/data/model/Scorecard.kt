package com.caddieai.android.data.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class ScorecardStatus { IN_PROGRESS, COMPLETED }

@Serializable
data class HoleScore(
    val holeNumber: Int,
    val par: Int,
    val score: Int? = null,
    val putts: Int? = null,
    val fairwayHit: Boolean? = null,
)

@Serializable
data class Scorecard(
    val id: String = UUID.randomUUID().toString(),
    val courseId: String,
    val courseName: String,
    val dateMs: Long = System.currentTimeMillis(),
    /** Player's phone or email from profile — identity binding (see KAN-225). */
    val playerIdentity: String = "",
    val teePlayed: String = "",
    val holes: List<HoleScore> = emptyList(),
    val status: ScorecardStatus = ScorecardStatus.IN_PROGRESS,
) {
    val totalScore: Int get() = holes.mapNotNull { it.score }.sum()
    val totalPar: Int get() = holes.sumOf { it.par }
    val scoreToPar: Int get() = totalScore - holes.filter { it.score != null }.sumOf { it.par }
    val holesPlayed: Int get() = holes.count { it.score != null }
}
