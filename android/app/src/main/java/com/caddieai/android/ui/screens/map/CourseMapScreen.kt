package com.caddieai.android.ui.screens.map

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GolfCourse
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.data.model.GeoPoint
import com.caddieai.android.data.model.HazardType
import com.caddieai.android.data.model.NormalizedCourse
import com.google.gson.JsonObject
import com.mapbox.geojson.Feature
import com.mapbox.geojson.FeatureCollection
import com.mapbox.geojson.LineString
import com.mapbox.geojson.Point
import com.mapbox.geojson.Polygon
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.Style
import com.mapbox.maps.extension.style.expressions.dsl.generated.eq
import com.mapbox.maps.extension.style.expressions.dsl.generated.get
import com.mapbox.maps.extension.style.expressions.dsl.generated.literal
import com.mapbox.maps.extension.style.layers.addLayer
import com.mapbox.maps.extension.style.layers.generated.fillLayer
import com.mapbox.maps.extension.style.layers.generated.lineLayer
import com.mapbox.maps.extension.style.layers.generated.symbolLayer
import com.mapbox.maps.extension.style.sources.addSource
import com.mapbox.maps.extension.style.sources.generated.geoJsonSource
import com.mapbox.maps.plugin.animation.MapAnimationOptions
import com.mapbox.maps.plugin.animation.flyTo
import com.mapbox.maps.plugin.gestures.addOnMapClickListener
import com.mapbox.maps.plugin.locationcomponent.location

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CourseMapScreen(
    course: NormalizedCourse,
    hasLocationPermission: Boolean,
    onBack: () -> Unit,
    onNavigateToCaddie: () -> Unit = {},
    viewModel: HoleAnalysisViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val scaffoldState = rememberBottomSheetScaffoldState()
    val context = LocalContext.current

    val centroid = remember(course) { computeCourseCentroid(course) }
    val mapView = remember { MapView(context) }

    // Initialize tee selection and fetch weather
    LaunchedEffect(course.id, course.teeNames) {
        viewModel.initTeeSelection(course)
        viewModel.fetchWeatherForBadge(course)
    }

    // Navigate to Caddie tab when Ask Caddie finishes
    var wasAskingCaddie by remember { mutableStateOf(false) }
    LaunchedEffect(state.isAskingCaddie) {
        if (wasAskingCaddie && !state.isAskingCaddie) {
            onNavigateToCaddie()
        }
        wasAskingCaddie = state.isAskingCaddie
    }

    // Tap-to-distance: listen for map taps
    LaunchedEffect(mapView) {
        mapView.mapboxMap.addOnMapClickListener { point ->
            viewModel.onMapTap(course, point.latitude(), point.longitude())
            true
        }
    }

    // Render tap-to-distance overlay
    LaunchedEffect(state.tappedPoint, state.selectedHoleNumber) {
        mapView.mapboxMap.getStyle { style ->
            renderTapDistanceOverlay(style, course, state.tappedPoint, state.selectedHoleNumber)
        }
    }

    // Setup map layers once when course is available
    LaunchedEffect(course) {
        val styleLoadStart = System.currentTimeMillis()
        mapView.mapboxMap.loadStyle(Style.SATELLITE_STREETS) { style ->
            val styleLoadMs = System.currentTimeMillis() - styleLoadStart
            viewModel.logMapStyleLoad(styleLoadMs, course.name)

            val layerStart = System.currentTimeMillis()
            addCourseOverlaysToStyle(style, course)
            val layerMs = System.currentTimeMillis() - layerStart
            viewModel.logLayerRender(layerMs, course.name, course.holes.size)
        }
        mapView.mapboxMap.setCamera(
            CameraOptions.Builder()
                .center(Point.fromLngLat(centroid.longitude, centroid.latitude))
                .zoom(15.5)
                .bearing(0.0)
                .pitch(0.0)
                .build()
        )
        if (hasLocationPermission) {
            mapView.location.updateSettings {
                enabled = true
                pulsingEnabled = false
            }
        }
    }

    // Animate camera — fly to hole or zoom out to full course on ALL
    LaunchedEffect(state.selectedHoleNumber) {
        if (state.selectedHoleNumber == null) {
            // ALL view — reset to north-up
            mapView.mapboxMap.flyTo(
                CameraOptions.Builder()
                    .center(Point.fromLngLat(centroid.longitude, centroid.latitude))
                    .zoom(15.5)
                    .bearing(0.0)
                    .build(),
                MapAnimationOptions.mapAnimationOptions { duration(900L) }
            )
        } else {
            val hole = course.holes.firstOrNull { it.number == state.selectedHoleNumber }
            val tee = hole?.teeBox
            val green = hole?.pin
            if (tee != null && green != null) {
                // Center on midpoint, rotate so tee is at bottom and green at top
                val midLat = (tee.latitude + green.latitude) / 2
                val midLon = (tee.longitude + green.longitude) / 2
                val bearing = forwardBearingDeg(tee.latitude, tee.longitude, green.latitude, green.longitude)
                mapView.mapboxMap.flyTo(
                    CameraOptions.Builder()
                        .center(Point.fromLngLat(midLon, midLat))
                        .zoom(16.0)
                        .bearing(bearing)
                        .build(),
                    MapAnimationOptions.mapAnimationOptions { duration(900L) }
                )
            } else {
                val target = tee ?: green ?: return@LaunchedEffect
                mapView.mapboxMap.flyTo(
                    CameraOptions.Builder()
                        .center(Point.fromLngLat(target.longitude, target.latitude))
                        .zoom(16.5)
                        .bearing(0.0)
                        .build(),
                    MapAnimationOptions.mapAnimationOptions { duration(900L) }
                )
            }
        }
    }

    // Fullscreen map with floating overlays (iOS parity)
    val hole = course.holes.firstOrNull { it.number == state.selectedHoleNumber }
    val teeYardage = state.selectedTee?.let { tee ->
        course.holeYardagesByTee[tee]?.get(state.selectedHoleNumber.toString())
            ?: state.analysis?.yardagesByTee?.get(tee)
    } ?: hole?.yardage

    Box(modifier = Modifier.fillMaxSize()) {
        // Map fills entire screen
        AndroidView(factory = { mapView }, modifier = Modifier.fillMaxSize())

        // ── Top floating controls ──
        // Back button (top-left)
        IconButton(
            onClick = onBack,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 8.dp, top = 40.dp)
                .size(40.dp)
                .background(Color.Black.copy(alpha = 0.4f), CircleShape),
        ) { Icon(Icons.Default.ArrowBack, "Back", tint = Color.White) }

        // Tee picker (top-right)
        if (state.dedupedTees.size > 1) {
            var expanded by remember { mutableStateOf(false) }
            val currentDisplay = state.dedupedTees.firstOrNull { it.canonicalTee == state.selectedTee }?.displayName
                ?: state.selectedTee ?: ""
            Box(modifier = Modifier.align(Alignment.TopEnd).padding(end = 8.dp, top = 40.dp)) {
                Surface(shape = RoundedCornerShape(16.dp), color = Color.Black.copy(alpha = 0.4f),
                    modifier = Modifier.clickable { expanded = true }) {
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Flag, null, Modifier.size(14.dp), tint = Color.White)
                        Spacer(Modifier.width(4.dp))
                        Text(currentDisplay, color = Color.White, style = MaterialTheme.typography.labelSmall)
                    }
                }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    state.dedupedTees.forEach { deduped ->
                        DropdownMenuItem(
                            text = { Text(deduped.displayName) },
                            onClick = { viewModel.selectTee(course, deduped.canonicalTee); expanded = false },
                            trailingIcon = if (deduped.canonicalTee == state.selectedTee) {
                                { Icon(Icons.Default.Check, null) }
                            } else null,
                        )
                    }
                }
            }
        }

        // Weather badge (below back button)
        state.weatherBadge?.let { weather ->
            Surface(shape = RoundedCornerShape(16.dp), color = Color.Black.copy(alpha = 0.6f),
                modifier = Modifier.align(Alignment.TopStart).padding(start = 8.dp, top = 88.dp)) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${weather.tempF}°F", color = Color.White, style = MaterialTheme.typography.bodySmall)
                    if (weather.windMph >= 5) {
                        Text("💨", style = MaterialTheme.typography.bodySmall)
                        Text("${weather.windMph}mph ${weather.windCompass}", color = Color.White, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        // Tap-to-distance card (top-right below tee picker)
        state.tapDistanceYds?.let { yds ->
            Surface(shape = RoundedCornerShape(12.dp), color = Color.Black.copy(alpha = 0.75f),
                modifier = Modifier.align(Alignment.TopEnd).padding(end = 8.dp, top = 88.dp)) {
                Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("$yds yds", color = Color.White, style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(6.dp))
                        IconButton(onClick = { viewModel.clearTapDistance() }, modifier = Modifier.size(20.dp)) {
                            Icon(Icons.Default.Close, "Clear", tint = Color.White, modifier = Modifier.size(16.dp))
                        }
                    }
                    state.tapRecommendedClub?.let { club ->
                        Text(club.name.replace('_', ' '), color = Color(0xFFFFEB3B),
                            style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

        // ── Bottom overlays ──
        Column(modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            // Tee reminder
            AnimatedVisibility(visible = state.showTeeReminder, enter = slideInVertically { it }, exit = slideOutVertically { it }) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(8.dp))
                    .padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Flag, null, Modifier.size(16.dp), tint = Color.White)
                    Spacer(Modifier.width(8.dp))
                    Text("Tap the tee button to choose your tee box", style = MaterialTheme.typography.bodySmall,
                        color = Color.White, modifier = Modifier.weight(1f))
                    IconButton(onClick = { viewModel.dismissTeeReminder() }, modifier = Modifier.size(24.dp)) {
                        Icon(Icons.Default.Close, "Dismiss", Modifier.size(16.dp), tint = Color.White)
                    }
                }
            }

            // Hole info + action buttons
            if (!state.isAnalyzed) {
                Surface(color = Color.LightGray.copy(alpha = 0.85f), modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                if (state.selectedHoleNumber != null) "Hole ${state.selectedHoleNumber}" else course.name,
                                style = MaterialTheme.typography.titleMedium, color = Color.Black, fontWeight = FontWeight.Bold)
                            hole?.let {
                                Spacer(Modifier.width(8.dp))
                                Text("Par ${it.par} • ${teeYardage ?: it.yardage} yds",
                                    style = MaterialTheme.typography.bodySmall, color = Color.Black.copy(alpha = 0.7f))
                            }
                        }
                        if (state.selectedHoleNumber != null) {
                            Spacer(Modifier.height(6.dp))
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = { state.selectedHoleNumber?.let { viewModel.askCaddie(course, it) } },
                                    enabled = !state.isAskingCaddie, modifier = Modifier.weight(1f),
                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32))) {
                                    if (state.isAskingCaddie) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                                    else { Icon(Icons.Default.GolfCourse, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("Ask Caddie") }
                                }
                                Button(onClick = { state.selectedHoleNumber?.let { viewModel.analyzeHole(course, it) } }, modifier = Modifier.weight(1f)) {
                                    if (state.isLoadingLLM) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                                    else { Icon(Icons.Default.Star, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("Analyze") }
                                }
                            }
                        }
                    }
                }
            }

            // Debug latency label (debug builds only)
            if (com.caddieai.android.BuildConfig.DEBUG && state.analysisLlmMs > 0) {
                Text(
                    "LLM: " + (if (state.analysisLlmMs < 1000) "${state.analysisLlmMs}ms" else "${"%.1f".format(state.analysisLlmMs / 1000.0)}s"),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    modifier = Modifier
                        .background(Color.Black.copy(alpha = 0.6f))
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }

            if (state.isAnalyzed) {
                HoleAnalysisSheet(state = state, course = course,
                    onHoleSelected = { holeNum -> viewModel.selectHole(course, holeNum) },
                    onFollowUpChange = viewModel::onFollowUpChange,
                    onSendFollowUp = { viewModel.sendFollowUp(course) },
                    onDismissOffTopicDialog = viewModel::dismissOffTopicDialog,
                    onSpeakAdvice = viewModel::speakAdvice, onStopSpeaking = viewModel::stopSpeaking)
            }

            // Hole selector
            Row(modifier = Modifier.fillMaxWidth()
                .background(Color.LightGray.copy(alpha = 0.85f))
                .padding(horizontal = 8.dp, vertical = 6.dp)
                .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                FilterChip(selected = state.selectedHoleNumber == null, onClick = { viewModel.selectAll() }, label = { Text("ALL") })
                course.holes.forEach { h ->
                    FilterChip(selected = h.number == state.selectedHoleNumber,
                        onClick = { viewModel.selectHole(course, h.number) }, label = { Text("${h.number}") })
                }
            }
        }
    }
}

private fun renderTapDistanceOverlay(
    style: com.mapbox.maps.Style,
    course: NormalizedCourse,
    tapped: GeoPoint?,
    holeNumber: Int?,
) {
    val srcId = "tap-distance-source"
    val lineLayerId = "layer-tap-distance-line"
    // Remove existing
    if (style.styleLayerExists(lineLayerId)) style.removeStyleLayer(lineLayerId)
    if (style.styleSourceExists(srcId)) style.removeStyleSource(srcId)
    if (tapped == null || holeNumber == null) return

    val hole = course.holes.firstOrNull { it.number == holeNumber } ?: return
    val target = hole.green?.outerRing?.takeIf { it.isNotEmpty() }?.let { ring ->
        GeoPoint(ring.map { it.latitude }.average(), ring.map { it.longitude }.average())
    } ?: hole.pin ?: hole.teeBox ?: return

    val linePoints = listOf(
        Point.fromLngLat(tapped.longitude, tapped.latitude),
        Point.fromLngLat(target.longitude, target.latitude),
    )
    val feat = com.mapbox.geojson.Feature.fromGeometry(
        com.mapbox.geojson.LineString.fromLngLats(linePoints)
    )
    style.addSource(geoJsonSource(srcId) {
        featureCollection(com.mapbox.geojson.FeatureCollection.fromFeature(feat))
    })
    style.addLayer(lineLayer(lineLayerId, srcId) {
        lineColor("#FFEB3B")
        lineWidth(4.0)
        lineOpacity(0.9)
    })
}

/** Forward bearing in degrees (0-360) from point A to point B. 0 = north. */
private fun forwardBearingDeg(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
    val phi1 = Math.toRadians(lat1)
    val phi2 = Math.toRadians(lat2)
    val dLon = Math.toRadians(lon2 - lon1)
    val y = Math.sin(dLon) * Math.cos(phi2)
    val x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLon)
    val brng = Math.toDegrees(Math.atan2(y, x))
    return (brng + 360) % 360
}

private fun computeCourseCentroid(course: NormalizedCourse): GeoPoint {
    val points = course.holes.flatMap { hole -> listOfNotNull(hole.teeBox, hole.pin) }
    if (points.isEmpty()) return GeoPoint(0.0, 0.0)
    return GeoPoint(points.map { it.latitude }.average(), points.map { it.longitude }.average())
}

private fun addCourseOverlaysToStyle(style: com.mapbox.maps.Style, course: NormalizedCourse) {
    val features = mutableListOf<Feature>()

    for (hole in course.holes) {
        val hn = hole.number

        // Fairway center line → holeLine layer
        hole.fairwayCenterLine?.let { line ->
            val pts = line.points.map { Point.fromLngLat(it.longitude, it.latitude) }
            features.add(Feature.fromGeometry(
                LineString.fromLngLats(pts),
                JsonObject().apply { addProperty("type", "holeLine"); addProperty("holeNumber", hn) }
            ))
        }

        // Green polygon → greens layer
        hole.green?.let { poly ->
            val ring = poly.outerRing.map { Point.fromLngLat(it.longitude, it.latitude) }
            features.add(Feature.fromGeometry(
                Polygon.fromLngLats(listOf(ring)),
                JsonObject().apply { addProperty("type", "green"); addProperty("holeNumber", hn) }
            ))
        }

        // Hole label point (at pin, or tee as fallback)
        (hole.pin ?: hole.teeBox)?.let { pt ->
            features.add(Feature.fromGeometry(
                Point.fromLngLat(pt.longitude, pt.latitude),
                JsonObject().apply {
                    addProperty("type", "holeLabel")
                    addProperty("holeNumber", hn)
                    addProperty("label", "$hn")
                }
            ))
        }

        // Hazard polygons → water / bunkers layers
        for (hazard in hole.hazards) {
            val featureType = when (hazard.type) {
                HazardType.WATER, HazardType.LATERAL_WATER -> "water"
                HazardType.BUNKER -> "bunker"
                else -> continue
            }
            hazard.boundary?.let { poly ->
                val ring = poly.outerRing.map { Point.fromLngLat(it.longitude, it.latitude) }
                features.add(Feature.fromGeometry(
                    Polygon.fromLngLats(listOf(ring)),
                    JsonObject().apply { addProperty("type", featureType); addProperty("holeNumber", hn) }
                ))
            }
        }
    }

    val sourceId = "course-source"
    val layerIds = listOf("layer-water", "layer-bunkers", "layer-hole-lines", "layer-greens", "layer-hole-labels")
    layerIds.forEach { id -> if (style.styleLayerExists(id)) style.removeStyleLayer(id) }
    if (style.styleSourceExists(sourceId)) style.removeStyleSource(sourceId)

    style.addSource(geoJsonSource(sourceId) {
        featureCollection(FeatureCollection.fromFeatures(features))
    })

    // Render order: bottom to top
    style.addLayer(fillLayer("layer-water", sourceId) {
        fillColor("#1565C0")
        fillOpacity(0.5)
        filter(eq { get("type"); literal("water") })
    })
    style.addLayer(fillLayer("layer-bunkers", sourceId) {
        fillColor("#E8D5B7")
        fillOpacity(0.7)
        filter(eq { get("type"); literal("bunker") })
    })
    style.addLayer(lineLayer("layer-hole-lines", sourceId) {
        lineColor("#FFFFFF")
        lineOpacity(0.8)
        lineWidth(2.0)
        lineDasharray(listOf(4.0, 3.0))
        filter(eq { get("type"); literal("holeLine") })
    })
    style.addLayer(fillLayer("layer-greens", sourceId) {
        fillColor("#4CAF50")
        fillOpacity(0.6)
        filter(eq { get("type"); literal("green") })
    })
    style.addLayer(symbolLayer("layer-hole-labels", sourceId) {
        textField(get("label"))
        textColor("#FFFFFF")
        textHaloColor("#000000")
        textHaloWidth(1.5)
        textSize(14.0)
        filter(eq { get("type"); literal("holeLabel") })
    })
}

@Composable
private fun HoleAnalysisSheet(
    state: HoleAnalysisState,
    course: NormalizedCourse,
    onHoleSelected: (Int) -> Unit,
    onFollowUpChange: (String) -> Unit,
    onSendFollowUp: () -> Unit,
    onDismissOffTopicDialog: () -> Unit,
    onSpeakAdvice: () -> Unit,
    onStopSpeaking: () -> Unit,
) {
    if (state.showOffTopicDialog) {
        AlertDialog(
            onDismissRequest = onDismissOffTopicDialog,
            title = { Text("Golf questions only") },
            text = { Text("I'm your AI golf caddie! I can only help with golf-related questions — club selection, shot strategy, course management, and more.") },
            confirmButton = {
                TextButton(onClick = onDismissOffTopicDialog) { Text("OK") }
            },
        )
    }
    val hole = course.holes.firstOrNull { it.number == state.selectedHoleNumber }
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        // Hole header
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Hole ${state.selectedHoleNumber}",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.width(12.dp))
            hole?.let {
                Text("Par ${it.par} • ${it.yardage} yds",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (state.isLoadingLLM) {
                Spacer(Modifier.width(12.dp))
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            }
        }
        Spacer(Modifier.height(8.dp))

        // Analysis conversation
        LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 200.dp)) {
            items(state.conversation) { msg ->
                val isUser = msg.role == MessageRole.USER
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 2.dp),
                    color = if (isUser) MaterialTheme.colorScheme.primaryContainer
                    else MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(8.dp),
                ) {
                    Text(
                        msg.content,
                        modifier = Modifier.padding(8.dp),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }

        // Listen / Stop button
        val adviceText = state.conversation.lastOrNull { it.role == MessageRole.CADDIE }?.content
            ?: state.analysis?.strategicAdvice
        if (adviceText != null) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                OutlinedButton(
                    onClick = if (state.isSpeaking) onStopSpeaking else onSpeakAdvice,
                ) {
                    Icon(
                        if (state.isSpeaking) Icons.Default.Stop else Icons.Default.VolumeUp,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(if (state.isSpeaking) "Stop" else "Read Aloud")
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        // Follow-up input
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = state.followUpInput,
                onValueChange = onFollowUpChange,
                placeholder = { Text("Ask your caddie…") },
                modifier = Modifier.weight(1f),
                singleLine = true,
                enabled = !state.isLoadingLLM,
            )
            Spacer(Modifier.width(8.dp))
            IconButton(
                onClick = onSendFollowUp,
                enabled = state.followUpInput.isNotBlank() && !state.isLoadingLLM,
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send",
                    tint = MaterialTheme.colorScheme.primary)
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}
