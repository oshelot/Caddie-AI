package com.caddieai.android.data.model

import kotlinx.serialization.Serializable

@Serializable
data class ShotContext(
    val distanceToPin: Int = 150,
    val shotType: ShotType = ShotType.APPROACH,
    val lie: LieType = LieType.FAIRWAY,
    val windStrength: WindStrength = WindStrength.CALM,
    val windDirection: WindDirection = WindDirection.NONE,
    val slope: Slope = Slope.FLAT,
    val aggressiveness: Aggressiveness? = null, // null = use profile default
    val elevationChangeYards: Int = 0, // positive = uphill
    val hazardNotes: String = "",
    val holeNumber: Int? = null,
    val par: Int? = null,
    val currentScore: Int? = null,
    val pinPosition: String = "", // e.g. "front left", "back right"
    val greenFirmness: String = "", // e.g. "soft", "medium", "firm"
    val playerLocation: GeoPoint? = null,
    val pinLocation: GeoPoint? = null,
)
