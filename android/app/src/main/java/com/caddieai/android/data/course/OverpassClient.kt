package com.caddieai.android.data.course

import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.model.GeoPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
data class OverpassElement(
    val type: String,
    val id: Long,
    val tags: Map<String, String> = emptyMap(),
    val geometry: List<OverpassGeometryPoint> = emptyList(),
    val nodes: List<Long> = emptyList(),
    val members: List<OverpassMember> = emptyList(),
    val lat: Double? = null,
    val lon: Double? = null,
)

@Serializable
data class OverpassGeometryPoint(
    val lat: Double,
    val lon: Double,
) {
    fun toGeoPoint() = GeoPoint(lat, lon)
}

@Serializable
data class OverpassMember(
    val type: String,
    val ref: Long,
    val role: String = "",
    val geometry: List<OverpassGeometryPoint> = emptyList(),
)

/** Parsed representation of a golf hole from OSM data. */
data class OSMHole(
    val number: Int,
    val par: Int?,
    val tee: List<GeoPoint>,
    val fairway: List<GeoPoint>,
    val green: List<GeoPoint>,
    val bunkers: List<List<GeoPoint>>,
    val water: List<List<GeoPoint>>,
)

@Singleton
class OverpassClient @Inject constructor(
    private val httpClient: OkHttpClient,
    private val logger: DiagnosticLogger,
) {
    companion object {
        private const val OVERPASS_PRIMARY_URL = "https://overpass.private.coffee/api/interpreter"
        private const val OVERPASS_FALLBACK_URL = "https://overpass-api.de/api/interpreter"
        private val RETRY_DELAYS_MS = listOf(2_000L, 4_000L)
        private val lenientJson = Json { ignoreUnknownKeys = true }
    }

    /**
     * Fetch all golf-related OSM elements within a bounding box.
     * Returns raw OSM elements for the normalizer to process.
     * Retries up to 2x on HTTP 429/504 with exponential backoff, then falls back to secondary endpoint.
     */
    suspend fun fetchGolfCourseData(
        name: String,
        osmId: Long? = null,
        bbox: String? = null, // "south,west,north,east"
    ): List<OverpassElement> = withContext(Dispatchers.IO) { runCatching {
        logger.log(LogLevel.INFO, LogCategory.API, "overpass_fetch_start", mapOf("name" to name))
        // Add ~200m (0.002 deg) buffer to bbox — matches iOS KAN-212 fix for incomplete hole geometry
        val bufferedBbox = bbox?.let { expandBbox(it, 0.002) } ?: bbox
        val query = buildOverpassQuery(name, osmId, bufferedBbox)
        val formBody = FormBody.Builder().add("data", query).build()

        val urls = listOf(OVERPASS_PRIMARY_URL, OVERPASS_PRIMARY_URL, OVERPASS_FALLBACK_URL)
        for ((attempt, url) in urls.withIndex()) {
            val request = Request.Builder().url(url).post(formBody).build()
            val (code, body) = httpClient.newCall(request).execute().use { response ->
                response.code to (response.body?.string() ?: "")
            }
            if (code == 429 || code == 504) {
                logger.log(LogLevel.WARN, LogCategory.API, "overpass_rate_limited", mapOf("attempt" to attempt, "status" to code))
                if (attempt < RETRY_DELAYS_MS.size) {
                    delay(RETRY_DELAYS_MS[attempt])
                    continue
                }
                return@runCatching emptyList()
            }
            if (code !in 200..299 || body.isBlank()) {
                logger.log(LogLevel.ERROR, LogCategory.API, "overpass_fetch_failed", mapOf("status" to code))
                return@runCatching emptyList()
            }
            val parseStart = System.currentTimeMillis()
            val elements = parseOverpassResponse(body)
            val parseMs = System.currentTimeMillis() - parseStart
            logger.log(LogLevel.INFO, LogCategory.MAP, "osm_parse",
                mapOf("latencyMs" to parseMs.toString(), "elementCount" to elements.size.toString()))
            logger.log(LogLevel.INFO, LogCategory.API, "overpass_fetch_success", mapOf("element_count" to elements.size))
            return@runCatching elements
        }
        emptyList()
    }.getOrElse { e ->
        logger.log(LogLevel.ERROR, LogCategory.API, "overpass_fetch_exception", mapOf("error" to (e.message ?: "unknown")))
        emptyList()
    } }

    /** Expand a "south,west,north,east" bbox by the given delta degrees on each side. */
    private fun expandBbox(bbox: String, deltaDeg: Double): String {
        val parts = bbox.split(",").mapNotNull { it.trim().toDoubleOrNull() }
        if (parts.size != 4) return bbox
        val (s, w, n, e) = listOf(parts[0] - deltaDeg, parts[1] - deltaDeg, parts[2] + deltaDeg, parts[3] + deltaDeg)
        return "$s,$w,$n,$e"
    }

    private fun buildOverpassQuery(name: String, osmId: Long?, bbox: String?): String {
        val areaQuery = when {
            osmId != null -> "area($osmId)->.searchArea;"
            name.isNotBlank() -> """area["name"~"${name.replace("\"", "\\\"",)}","i"]->.searchArea;"""
            else -> ""
        }
        val bboxFilter = bbox?.let { "($it)" } ?: if (areaQuery.isNotBlank()) "(area.searchArea)" else ""

        return """
            [out:json][timeout:45];
            $areaQuery
            (
              way["golf"="hole"]$bboxFilter;
              way["golf"="green"]$bboxFilter;
              way["golf"="tee"]$bboxFilter;
              node["golf"="pin"]$bboxFilter;
              way["golf"="bunker"]$bboxFilter;
              way["natural"="water"]$bboxFilter;
              relation["natural"="water"]$bboxFilter;
              way["golf"="fairway"]$bboxFilter;
            );
            out geom;
        """.trimIndent()
    }

    private fun parseOverpassResponse(json: String): List<OverpassElement> {
        val root = lenientJson.parseToJsonElement(json).jsonObject
        return root["elements"]?.jsonArray?.mapNotNull { element ->
            runCatching {
                val obj = element.jsonObject
                val type = obj["type"]?.jsonPrimitive?.content ?: return@mapNotNull null
                val id = obj["id"]?.jsonPrimitive?.content?.toLong() ?: 0L
                val tags = obj["tags"]?.jsonObject?.entries?.associate { (k, v) ->
                    k to v.jsonPrimitive.content
                } ?: emptyMap()
                val geometry = obj["geometry"]?.jsonArray?.map { g ->
                    val pt = g.jsonObject
                    OverpassGeometryPoint(
                        lat = pt["lat"]?.jsonPrimitive?.content?.toDouble() ?: 0.0,
                        lon = pt["lon"]?.jsonPrimitive?.content?.toDouble() ?: 0.0,
                    )
                } ?: emptyList()
                val lat = obj["lat"]?.jsonPrimitive?.content?.toDoubleOrNull()
                val lon = obj["lon"]?.jsonPrimitive?.content?.toDoubleOrNull()
                OverpassElement(type = type, id = id, tags = tags, geometry = geometry, lat = lat, lon = lon)
            }.getOrNull()
        } ?: emptyList()
    }
}
