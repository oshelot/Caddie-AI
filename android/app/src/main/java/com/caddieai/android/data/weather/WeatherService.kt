package com.caddieai.android.data.weather

import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.WindDirection
import com.caddieai.android.data.model.WindStrength
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class WeatherData(
    val temperatureFahrenheit: Float = 0f,
    val windSpeedMph: Float = 0f,
    val windDirectionDegrees: Int = 0,
    val precipitationMm: Float = 0f,
    val windStrength: WindStrength = WindStrength.CALM,
    val windDirection: WindDirection = WindDirection.NONE,
    val fetchedAtMs: Long = 0L,
    val fetchedLat: Double = 0.0,
    val fetchedLon: Double = 0.0,
)

private const val CACHE_TTL_MS = 15 * 60 * 1_000L // 15 minutes

@Singleton
class WeatherService @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val logger: DiagnosticLogger,
) {
    private var cache: WeatherData? = null

    suspend fun getWeather(lat: Double, lon: Double): Result<WeatherData> {
        val cached = cache
        if (cached != null &&
            System.currentTimeMillis() - cached.fetchedAtMs < CACHE_TTL_MS &&
            Math.abs(cached.fetchedLat - lat) < 0.01 &&
            Math.abs(cached.fetchedLon - lon) < 0.01) {
            logger.log(LogLevel.INFO, LogCategory.API, "weather_cache_hit")
            return Result.success(cached)
        }

        val fetchStart = System.currentTimeMillis()
        return try {
            val url = "https://api.open-meteo.com/v1/forecast" +
                    "?latitude=$lat&longitude=$lon" +
                    "&current=temperature_2m,wind_speed_10m,wind_direction_10m,weather_code" +
                    "&temperature_unit=fahrenheit" +
                    "&wind_speed_unit=mph"

            val request = Request.Builder().url(url).get().build()
            val responseBody = okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw Exception("Weather API error: ${response.code}")
                response.body?.string() ?: throw Exception("Empty weather response")
            }

            val json = JSONObject(responseBody)
            val current = json.getJSONObject("current")
            val tempF = current.getDouble("temperature_2m").toFloat()
            val windMph = current.getDouble("wind_speed_10m").toFloat()
            val windDeg = current.getInt("wind_direction_10m")

            val strength = when {
                windMph <= 3 -> WindStrength.CALM
                windMph <= 10 -> WindStrength.LIGHT
                windMph <= 15 -> WindStrength.MODERATE
                windMph <= 20 -> WindStrength.STRONG
                else -> WindStrength.VERY_STRONG
            }

            val data = WeatherData(
                temperatureFahrenheit = tempF,
                windSpeedMph = windMph,
                windDirectionDegrees = windDeg,
                windStrength = strength,
                windDirection = WindDirection.NONE, // direction is heading-relative; needs player heading
                fetchedAtMs = System.currentTimeMillis(),
                fetchedLat = lat,
                fetchedLon = lon,
            )
            cache = data
            logger.log(LogLevel.INFO, LogCategory.LIFECYCLE, "weather_fetch", mapOf(
                "latencyMs" to (System.currentTimeMillis() - fetchStart).toString(),
                "source" to "open-meteo",
            ))
            Result.success(data)
        } catch (e: Exception) {
            logger.log(LogLevel.ERROR, LogCategory.API, "weather_fetch_failed", mapOf("error" to (e.message ?: "unknown")))
            Result.failure(e)
        }
    }

    fun clearCache() { cache = null }
}
