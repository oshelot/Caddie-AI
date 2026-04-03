package com.caddieai.android.ui.screens.map

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
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
            mapView.mapboxMap.flyTo(
                CameraOptions.Builder()
                    .center(Point.fromLngLat(centroid.longitude, centroid.latitude))
                    .zoom(15.5)
                    .build(),
                MapAnimationOptions.mapAnimationOptions { duration(900L) }
            )
        } else {
            val hole = course.holes.firstOrNull { it.number == state.selectedHoleNumber }
            val target = hole?.teeBox ?: hole?.pin ?: return@LaunchedEffect
            mapView.mapboxMap.flyTo(
                CameraOptions.Builder()
                    .center(Point.fromLngLat(target.longitude, target.latitude))
                    .zoom(17.0)
                    .build(),
                MapAnimationOptions.mapAnimationOptions { duration(900L) }
            )
        }
    }

    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight = 130.dp,
        sheetContent = {
            val hole = course.holes.firstOrNull { it.number == state.selectedHoleNumber }
            val teeYardage = state.selectedTee?.let { tee ->
                state.analysis?.yardagesByTee?.get(tee)
            } ?: hole?.yardage

            if (!state.isAnalyzed) {
                // Peek row — shown before analysis
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (state.selectedHoleNumber != null) "Hole ${state.selectedHoleNumber}" else course.name,
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        hole?.let {
                            Spacer(Modifier.width(12.dp))
                            Text(
                                "Par ${it.par} • ${teeYardage ?: it.yardage} yds${state.selectedTee?.let { t -> " ($t)" } ?: ""}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    if (state.selectedHoleNumber != null) {
                        Spacer(Modifier.height(8.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            // Ask Caddie (green)
                            Button(
                                onClick = { state.selectedHoleNumber?.let { viewModel.askCaddie(course, it) } },
                                enabled = !state.isAskingCaddie,
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(0xFF2E7D32),
                                ),
                                modifier = Modifier.weight(1f),
                            ) {
                                if (state.isAskingCaddie) {
                                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp,
                                        color = Color.White)
                                } else {
                                    Icon(Icons.Default.GolfCourse, null, Modifier.size(16.dp))
                                    Spacer(Modifier.width(4.dp))
                                    Text("Ask Caddie")
                                }
                            }
                            // Analyze (blue)
                            Button(
                                onClick = { state.selectedHoleNumber?.let { viewModel.analyzeHole(course, it) } },
                                modifier = Modifier.weight(1f),
                            ) {
                                if (state.isLoadingLLM) {
                                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp,
                                        color = MaterialTheme.colorScheme.onPrimary)
                                } else {
                                    Icon(Icons.Default.Star, null, Modifier.size(16.dp))
                                    Spacer(Modifier.width(4.dp))
                                    Text("Analyze")
                                }
                            }
                        }
                    }
                }
            }

            if (state.isAnalyzed) {
                HoleAnalysisSheet(
                    state = state,
                    course = course,
                    onHoleSelected = { holeNum -> viewModel.selectHole(course, holeNum) },
                    onFollowUpChange = viewModel::onFollowUpChange,
                    onSendFollowUp = { viewModel.sendFollowUp(course) },
                    onDismissOffTopicDialog = viewModel::dismissOffTopicDialog,
                    onSpeakAdvice = viewModel::speakAdvice,
                    onStopSpeaking = viewModel::stopSpeaking,
                )
            }
        },
        topBar = {
            TopAppBar(
                title = { Text("Course Map") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (state.dedupedTees.size > 1) {
                        var expanded by remember { mutableStateOf(false) }
                        val currentDisplay = state.dedupedTees.firstOrNull { it.canonicalTee == state.selectedTee }?.displayName
                            ?: state.selectedTee ?: ""
                        Box {
                            FilterChip(
                                selected = false,
                                onClick = { expanded = true },
                                label = { Text(currentDisplay) },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Flag,
                                        contentDescription = null,
                                        modifier = Modifier.size(16.dp),
                                    )
                                },
                            )
                            DropdownMenu(
                                expanded = expanded,
                                onDismissRequest = { expanded = false },
                            ) {
                                state.dedupedTees.forEach { deduped ->
                                    DropdownMenuItem(
                                        text = { Text(deduped.displayName) },
                                        onClick = {
                                            viewModel.selectTee(course, deduped.canonicalTee)
                                            expanded = false
                                        },
                                        trailingIcon = if (deduped.canonicalTee == state.selectedTee) {
                                            { Icon(Icons.Default.Check, contentDescription = null) }
                                        } else null,
                                    )
                                }
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f)
                ),
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
                AndroidView(
                    factory = { mapView },
                    modifier = Modifier.fillMaxSize(),
                )
                // Weather badge overlay
                state.weatherBadge?.let { weather ->
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = Color.Black.copy(alpha = 0.6f),
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(start = 8.dp, top = 8.dp),
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text("${weather.tempF}°F", color = Color.White,
                                style = MaterialTheme.typography.labelSmall)
                            if (weather.windMph >= 5) {
                                Text("💨", style = MaterialTheme.typography.labelSmall)
                                Text("${weather.windMph}mph ${weather.windCompass}",
                                    color = Color.White,
                                    style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }
                }
            }

            // Tee reminder callout
            AnimatedVisibility(
                visible = state.showTeeReminder,
                enter = slideInVertically { -it },
                exit = slideOutVertically { -it },
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.92f),
                            RoundedCornerShape(8.dp),
                        )
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Default.Flag, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Tap the tee selector above to choose your tee box",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(
                        onClick = { viewModel.dismissTeeReminder() },
                        modifier = Modifier.size(24.dp),
                    ) {
                        Icon(Icons.Default.Close, contentDescription = "Dismiss", modifier = Modifier.size(16.dp))
                    }
                }
            }

            // Hole selector chips (below map)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                FilterChip(
                    selected = state.selectedHoleNumber == null,
                    onClick = { viewModel.selectAll() },
                    label = { Text("ALL") },
                )
                course.holes.forEach { hole ->
                    FilterChip(
                        selected = hole.number == state.selectedHoleNumber,
                        onClick = { viewModel.selectHole(course, hole.number) },
                        label = { Text("${hole.number}") },
                    )
                }
            }
        }
    }
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
