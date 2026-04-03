package com.caddieai.android.data.course

import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class NominatimResult(
    val place_id: Long,
    val osm_id: Long = 0L,
    val osm_type: String = "",
    val display_name: String,
    val name: String = "",
    val lat: String,
    val lon: String,
    val type: String = "",
    val extratags: Map<String, String> = emptyMap(),
    val address: Map<String, String> = emptyMap(),
) {
    val latitude: Double get() = lat.toDoubleOrNull() ?: 0.0
    val longitude: Double get() = lon.toDoubleOrNull() ?: 0.0
    val cityState: String get() = buildString {
        address["city"]?.let { append(it) }
        address["state"]?.let {
            if (isNotEmpty()) append(", ")
            append(it)
        }
    }
}

@Singleton
class NominatimClient @Inject constructor(
    private val httpClient: OkHttpClient,
    private val logger: DiagnosticLogger,
) {
    companion object {
        private const val BASE_URL = "https://nominatim.openstreetmap.org"
        private val lenientJson = Json { ignoreUnknownKeys = true }
    }

    /** Search for golf courses by name. */
    suspend fun searchGolfCourses(query: String, limit: Int = 15): List<NominatimResult> =
        withContext(Dispatchers.IO) { runCatching {
            logger.log(LogLevel.INFO, LogCategory.API, "nominatim_search_courses")
            val url = "$BASE_URL/search" +
                    "?q=${"golf course $query".urlEncode()}" +
                    "&format=json" +
                    "&limit=$limit" +
                    "&addressdetails=1" +
                    "&extratags=1"

            val request = Request.Builder()
                .url(url)
                .addHeader("User-Agent", "CaddieAI/1.0 (golf caddie app)")
                .build()

            val body = httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    logger.log(LogLevel.WARN, LogCategory.API, "nominatim_search_failed", mapOf("status" to response.code))
                    return@runCatching emptyList()
                }
                response.body?.string() ?: return@runCatching emptyList()
            }

            val results = lenientJson.decodeFromString<List<NominatimResult>>(body)
                .filter { result ->
                    result.type == "golf_course" ||
                        result.display_name.lowercase().let { name ->
                            name.contains("golf course") || name.contains("golf club") || name.contains("golf links")
                        }
                }
            logger.log(LogLevel.INFO, LogCategory.API, "nominatim_search_success", mapOf("result_count" to results.size))
            results
        }.getOrDefault(emptyList()) }

    /** Autocomplete city/region names for the location filter. */
    suspend fun searchCities(query: String, limit: Int = 5): List<String> =
        withContext(Dispatchers.IO) { runCatching {
            val url = "$BASE_URL/search" +
                    "?q=${query.urlEncode()}" +
                    "&format=json" +
                    "&limit=$limit" +
                    "&addressdetails=1" +
                    "&featuretype=city"

            val request = Request.Builder()
                .url(url)
                .addHeader("User-Agent", "CaddieAI Android/1.0 (contact@caddieai.app)")
                .build()

            val body = httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@runCatching emptyList()
                response.body?.string() ?: return@runCatching emptyList()
            }

            lenientJson.decodeFromString<List<NominatimResult>>(body)
                .mapNotNull { result ->
                    val city = result.address["city"]
                        ?: result.address["town"]
                        ?: result.address["village"]
                        ?: return@mapNotNull null
                    val state = result.address["state"] ?: result.address["county"] ?: ""
                    val country = result.address["country_code"]?.uppercase() ?: ""
                    buildString {
                        append(city)
                        if (state.isNotBlank()) append(", $state")
                        if (country.isNotBlank() && country != "US") append(", $country")
                    }
                }
                .distinct()
        }.getOrDefault(emptyList()) }

    /** Reverse geocode a lat/lon to find the nearest golf course. */
    suspend fun reverseGeocode(latitude: Double, longitude: Double): NominatimResult? =
        withContext(Dispatchers.IO) { runCatching {
            val url = "$BASE_URL/reverse" +
                    "?lat=$latitude&lon=$longitude" +
                    "&format=json" +
                    "&addressdetails=1"

            val request = Request.Builder()
                .url(url)
                .addHeader("User-Agent", "CaddieAI Android/1.0 (contact@caddieai.app)")
                .build()

            val body = httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@runCatching null
                response.body?.string() ?: return@runCatching null
            }

            lenientJson.decodeFromString<NominatimResult>(body)
        }.getOrNull() }

    private fun String.urlEncode(): String = java.net.URLEncoder.encode(this, "UTF-8")
}
