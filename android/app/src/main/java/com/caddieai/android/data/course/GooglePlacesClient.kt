package com.caddieai.android.data.course

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class PlacesSuggestion(
    val placeId: String,
    val description: String,
    val mainText: String,
    val secondaryText: String,
)

@Serializable
private data class PlacesAutocompleteResponse(
    val status: String,
    val predictions: List<PlacesPrediction> = emptyList(),
)

@Serializable
private data class PlacesPrediction(
    val place_id: String = "",
    val description: String = "",
    val structured_formatting: StructuredFormatting = StructuredFormatting(),
)

@Serializable
private data class StructuredFormatting(
    val main_text: String = "",
    val secondary_text: String = "",
)

@Singleton
class GooglePlacesClient @Inject constructor(
    private val httpClient: OkHttpClient
) {
    companion object {
        private const val BASE_URL = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
        private val lenientJson = Json { ignoreUnknownKeys = true }
    }

    /**
     * Autocomplete city names for course search.
     * Falls back to empty list if no API key or on error.
     */
    suspend fun autocompleteCity(query: String, apiKey: String): List<PlacesSuggestion> {
        if (apiKey.isBlank() || query.length < 2) return emptyList()
        return withContext(Dispatchers.IO) { runCatching {
            val url = "$BASE_URL" +
                    "?input=${query.urlEncode()}" +
                    "&types=(cities)" +
                    "&key=$apiKey"

            val request = Request.Builder().url(url).build()
            val body = httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@runCatching emptyList()
                response.body?.string() ?: return@runCatching emptyList()
            }

            val response = lenientJson.decodeFromString<PlacesAutocompleteResponse>(body)
            if (response.status != "OK") return@runCatching emptyList()
            response.predictions.map { p ->
                PlacesSuggestion(
                    placeId = p.place_id,
                    description = p.description,
                    mainText = p.structured_formatting.main_text,
                    secondaryText = p.structured_formatting.secondary_text,
                )
            }
        }.getOrDefault(emptyList()) }
    }

    /**
     * Autocomplete golf course names using Places API.
     */
    suspend fun autocompleteGolfCourse(query: String, apiKey: String): List<PlacesSuggestion> {
        if (apiKey.isBlank() || query.length < 2) return emptyList()
        return withContext(Dispatchers.IO) { runCatching {
            val url = "$BASE_URL" +
                    "?input=${query.urlEncode()} golf" +
                    "&types=establishment" +
                    "&key=$apiKey"

            val request = Request.Builder().url(url).build()
            val body = httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@runCatching emptyList()
                response.body?.string() ?: return@runCatching emptyList()
            }

            val response = lenientJson.decodeFromString<PlacesAutocompleteResponse>(body)
            if (response.status != "OK") return@runCatching emptyList()
            response.predictions
                .filter { it.description.contains("golf", ignoreCase = true) }
                .map { p ->
                    PlacesSuggestion(
                        placeId = p.place_id,
                        description = p.description,
                        mainText = p.structured_formatting.main_text,
                        secondaryText = p.structured_formatting.secondary_text,
                    )
                }
        }.getOrDefault(emptyList()) }
    }

    private fun String.urlEncode(): String = java.net.URLEncoder.encode(this, "UTF-8")
}
