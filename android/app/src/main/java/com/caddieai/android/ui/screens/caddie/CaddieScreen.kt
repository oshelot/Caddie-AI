package com.caddieai.android.ui.screens.caddie

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Camera
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GolfCourse
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.caddieai.android.data.billing.AdManager
import com.caddieai.android.data.llm.InputGuard
import com.caddieai.android.data.engine.ShotArchetype
import com.caddieai.android.data.model.Aggressiveness
import com.caddieai.android.data.model.LieType
import com.caddieai.android.data.model.NormalizedCourse
import com.caddieai.android.data.model.Slope
import com.caddieai.android.data.model.ShotRecommendation
import com.caddieai.android.data.model.ShotType
import com.caddieai.android.data.model.WindDirection
import com.caddieai.android.data.model.WindStrength
import com.caddieai.android.ui.components.AdBannerView
import com.caddieai.android.ui.theme.CaddieShape
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaddieScreen(
    viewModel: ShotAdvisorViewModel = hiltViewModel(),
    voiceViewModel: VoiceViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val shotContext by viewModel.shotContext.collectAsStateWithLifecycle()
    val state by viewModel.state.collectAsStateWithLifecycle()
    val voiceState by voiceViewModel.state.collectAsStateWithLifecycle()
    val profile by viewModel.profile.collectAsStateWithLifecycle()
    val activeCourse by viewModel.activeCourse.collectAsStateWithLifecycle()
    val activeHoleNumber by viewModel.activeHoleNumber.collectAsStateWithLifecycle()
    val autoDetectState by viewModel.autoDetectState.collectAsStateWithLifecycle()
    val isSpeaking by viewModel.isSpeaking.collectAsStateWithLifecycle()
    val canUseImageAnalysis = profile.effectiveTier == com.caddieai.android.data.model.UserTier.PRO &&
            profile.imageAnalysisBetaEnabled

    // Mic permission
    var hasMicPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                    == PackageManager.PERMISSION_GRANTED
        )
    }
    val micPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasMicPermission = granted
        voiceViewModel.onMicPermissionResult(granted)
    }
    LaunchedEffect(hasMicPermission) {
        voiceViewModel.onMicPermissionResult(hasMicPermission)
    }

    // Photo picker
    var selectedImageUri by remember { mutableStateOf<Uri?>(null) }
    var selectedImageBase64 by remember { mutableStateOf<String?>(null) }
    val photoPickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        selectedImageUri = uri
        uri?.let {
            selectedImageBase64 = uriToBase64Jpeg(context, it)
        }
    }

    // Apply voice-parsed input to shot context
    LaunchedEffect(voiceState.parsedInput) {
        val parsed = voiceState.parsedInput ?: return@LaunchedEffect
        val updated = voiceViewModel.applyToContext(shotContext)
        viewModel.updateContext { updated }
        voiceViewModel.clearParsedInput()
    }

    // Follow-up Q&A state
    var followUpText by remember { mutableStateOf("") }
    var conversation by remember { mutableStateOf<List<Pair<Boolean, String>>>(emptyList()) } // isUser, text
    var showOffTopicDialog by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // Bottom sheet state — opens as soon as analysis starts so we can show
    // the skeleton during the LLM round-trip (KAN-116, matches iOS).
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val showBottomSheet = state !is ShotAdvisorState.Idle
    val isLoadingPhase = state is ShotAdvisorState.Loading
    val isCompletePhase = state is ShotAdvisorState.Complete
    val isErrorPhase = state is ShotAdvisorState.Error
    val sheetRec = when (val s = state) {
        is ShotAdvisorState.Revealing -> s.recommendation
        is ShotAdvisorState.Complete -> s.recommendation
        is ShotAdvisorState.Error -> s.fallback
        else -> null
    }
    val sheetArchetype = when (val s = state) {
        is ShotAdvisorState.Revealing -> s.archetype
        is ShotAdvisorState.Complete -> s.archetype
        is ShotAdvisorState.Error -> s.archetype
        else -> null
    }
    // revealStep: 0 = nothing yet, 1 = hero, 2 = execution plan, 3 = rationale.
    // Complete and Error states show every section immediately.
    val revealStep = when (val s = state) {
        is ShotAdvisorState.Revealing -> s.revealStep
        is ShotAdvisorState.Complete, is ShotAdvisorState.Error -> 3
        else -> 0
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Caddie") },
                actions = {
                    TextButton(onClick = {
                        viewModel.reset()
                        selectedImageUri = null
                        selectedImageBase64 = null
                        conversation = emptyList()
                    }) { Text("New Shot") }
                }
            )
        },
        bottomBar = {
            AdBannerView()
        }
    ) { padding ->
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Auto Detect banner — shown when a course is loaded
            activeCourse?.let { course ->
                item {
                    AutoDetectBanner(
                        course = course,
                        selectedHole = activeHoleNumber,
                        autoDetectState = autoDetectState,
                        onHoleSelected = viewModel::setActiveHole,
                        onAutoDetect = viewModel::triggerAutoDetect,
                    )
                }
            }

            // Card 1: Quick Input — voice button
            item {
                SectionCard(title = "Quick Input") {
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        val micTint = if (voiceState.isListening) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.primary
                        IconButton(
                            onClick = {
                                if (!hasMicPermission) {
                                    micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                } else {
                                    voiceViewModel.toggleListening()
                                }
                            },
                            modifier = Modifier
                                .size(48.dp)
                                .background(
                                    color = if (voiceState.isListening)
                                        MaterialTheme.colorScheme.errorContainer
                                    else MaterialTheme.colorScheme.primaryContainer,
                                    shape = CircleShape
                                )
                        ) {
                            Icon(
                                if (voiceState.isListening) Icons.Default.MicOff else Icons.Default.Mic,
                                contentDescription = "Voice input",
                                tint = micTint,
                            )
                        }
                        Text(
                            if (voiceState.isListening) "Listening…"
                            else "Tap to describe your shot",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            // Card 2: Shot Setup — distance + shot type
            item {
                SectionCard(title = "Shot Setup") {
                    OutlinedTextField(
                        value = if (shotContext.distanceToPin == 0) "" else shotContext.distanceToPin.toString(),
                        onValueChange = { v ->
                            viewModel.updateContext { it.copy(distanceToPin = v.toIntOrNull() ?: 0) }
                        },
                        label = { Text("Distance (yards)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                    EnumDropdown(
                        label = "Shot Type",
                        selected = shotContext.shotType,
                        options = ShotType.entries,
                        displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                        onSelect = { newType ->
                            viewModel.updateContext { ctx ->
                                // Auto-reconcile lie if current lie is invalid for new shot type
                                val validLies = newType.validLies()
                                val newLie = if (validLies.isEmpty() || ctx.lie in validLies) ctx.lie
                                             else newType.defaultLie()
                                ctx.copy(shotType = newType, lie = newLie)
                            }
                        },
                    )
                }
            }

            // Card 2: Conditions
            item {
                SectionCard(title = "Conditions") {
                    val validLies = shotContext.shotType.validLies()
                    if (validLies.isNotEmpty()) {
                        EnumDropdown(
                            label = "Lie",
                            selected = shotContext.lie,
                            options = validLies,
                            displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                            onSelect = { viewModel.updateContext { ctx -> ctx.copy(lie = it) } },
                        )
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.weight(1f)) {
                            EnumDropdown(
                                label = "Wind",
                                selected = shotContext.windStrength,
                                options = WindStrength.entries,
                                displayName = { it.label },
                                onSelect = { viewModel.updateContext { ctx -> ctx.copy(windStrength = it) } },
                            )
                        }
                        Box(Modifier.weight(1f)) {
                            EnumDropdown(
                                label = "Direction",
                                selected = shotContext.windDirection,
                                options = WindDirection.entries,
                                displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                                onSelect = { viewModel.updateContext { ctx -> ctx.copy(windDirection = it) } },
                            )
                        }
                    }
                    EnumDropdown(
                        label = "Slope",
                        selected = shotContext.slope,
                        options = Slope.entries,
                        displayName = { slope ->
                            slope.name.replace('_', ' ').lowercase()
                                .replaceFirstChar { c -> c.uppercase() }
                                .replace("Flat", "Level")
                        },
                        onSelect = { viewModel.updateContext { ctx -> ctx.copy(slope = it) } },
                    )
                }
            }

            // Card 3: Strategy
            item {
                SectionCard(title = "Strategy") {
                    // Aggressiveness segmented control
                    Text("Aggressiveness", style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    val aggressivenessOptions = listOf(
                        Aggressiveness.CONSERVATIVE to "Conservative",
                        Aggressiveness.MODERATE to "Smart",
                        Aggressiveness.AGGRESSIVE to "Aggressive",
                    )
                    val selectedAgg = shotContext.aggressiveness
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        aggressivenessOptions.forEachIndexed { index, (value, label) ->
                            SegmentedButton(
                                selected = selectedAgg == value,
                                onClick = { viewModel.updateContext { ctx -> ctx.copy(aggressiveness = value) } },
                                shape = SegmentedButtonDefaults.itemShape(index = index, count = aggressivenessOptions.size),
                                label = { Text(label, maxLines = 1) },
                            )
                        }
                    }
                    OutlinedTextField(
                        value = shotContext.hazardNotes,
                        onValueChange = { viewModel.updateContext { ctx -> ctx.copy(hazardNotes = InputGuard.enforceLimit(it)) } },
                        label = { Text("Hazard Notes") },
                        placeholder = { Text("e.g. water left, OB right") },
                        modifier = Modifier.fillMaxWidth(),
                        maxLines = 2,
                        supportingText = if (shotContext.hazardNotes.length > InputGuard.MAX_CHARS - 100) {
                            { Text("${shotContext.hazardNotes.length}/${InputGuard.MAX_CHARS}") }
                        } else null,
                    )
                }
            }

            // Photo row (voice moved to Quick Input)
            if (canUseImageAnalysis) {
                item {
                    FilledTonalButton(
                        onClick = {
                            photoPickerLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Default.Photo, contentDescription = null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(if (selectedImageUri != null) "Photo selected" else "Add Lie Photo")
                    }
                }
            }

            // Partial voice transcript
            item {
                AnimatedVisibility(voiceState.partialTranscript.isNotBlank()) {
                    Text(
                        "\"${voiceState.partialTranscript}\"",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                }
            }

            // Selected photo thumbnail (only visible when image analysis is available)
            if (canUseImageAnalysis) selectedImageUri?.let { uri ->
                item {
                    Box {
                        AsyncImage(
                            model = uri,
                            contentDescription = "Lie photo",
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(140.dp)
                                .clip(RoundedCornerShape(8.dp)),
                            contentScale = ContentScale.Crop,
                        )
                        IconButton(
                            onClick = { selectedImageUri = null; selectedImageBase64 = null },
                            modifier = Modifier.align(Alignment.TopEnd)
                        ) {
                            Icon(Icons.Default.Close, contentDescription = "Remove photo",
                                tint = Color.White)
                        }
                    }
                }
            }

            // Analyze button
            item {
                Button(
                    onClick = { viewModel.analyze(selectedImageBase64) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = state !is ShotAdvisorState.Loading,
                ) {
                    if (state is ShotAdvisorState.Loading) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("Analyzing…")
                    } else {
                        Icon(Icons.Default.SmartToy, contentDescription = null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Ask Caddie")
                    }
                }
            }

            item { Spacer(Modifier.height(16.dp)) }
        }
    }

    // ModalBottomSheet — slides up once deterministic result is ready
    if (showBottomSheet) {
        ModalBottomSheet(
            onDismissRequest = {
                viewModel.reset()
                conversation = emptyList()
                followUpText = ""
            },
            sheetState = sheetState,
        ) {
            // Read Aloud / Stop button row
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FilledTonalButton(
                    onClick = { if (isSpeaking) viewModel.stopSpeaking() else viewModel.speakAdvice() },
                    enabled = sheetRec != null,
                ) {
                    Icon(
                        if (isSpeaking) Icons.Default.StopCircle else Icons.Default.VolumeUp,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(if (isSpeaking) "Stop" else "Read Aloud")
                }
            }

            val sheetListState = rememberLazyListState()
            LazyColumn(
                state = sheetListState,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // Loading skeleton — replaces the old "deterministic preview"
                // and "Enhancing with AI…" banner. The user only ever sees
                // either this skeleton or the final LLM recommendation.
                if (isLoadingPhase) {
                    item { ShotAdvisorSkeleton() }
                }

                // Recommendation sections — gated by revealStep so they fade
                // in one at a time during the Revealing phase. Complete and
                // Error states show every section immediately (revealStep=3).
                sheetRec?.let { rec ->
                    sheetArchetype?.let { arch ->
                        item {
                            androidx.compose.animation.AnimatedVisibility(
                                visible = revealStep >= 1,
                                enter = androidx.compose.animation.fadeIn() +
                                    androidx.compose.animation.expandVertically(),
                            ) {
                                RecommendationHeroCard(
                                    recommendation = rec,
                                    isEnhanced = isCompletePhase || state is ShotAdvisorState.Revealing,
                                )
                            }
                        }
                        item {
                            androidx.compose.animation.AnimatedVisibility(
                                visible = revealStep >= 2,
                                enter = androidx.compose.animation.fadeIn() +
                                    androidx.compose.animation.expandVertically(),
                            ) {
                                ExecutionPlanSection(arch)
                            }
                        }
                        item {
                            androidx.compose.animation.AnimatedVisibility(
                                visible = revealStep >= 3,
                                enter = androidx.compose.animation.fadeIn() +
                                    androidx.compose.animation.expandVertically(),
                            ) {
                                RecommendationRationaleSection(rec)
                            }
                        }
                    }
                }

                // Debug latency label (debug builds only)
                if (com.caddieai.android.BuildConfig.DEBUG) {
                    val (engineMs, llmMs) = when (val s = state) {
                        is ShotAdvisorState.Complete -> Pair(s.engineMs, s.llmMs)
                        is ShotAdvisorState.Revealing -> Pair(s.engineMs, s.llmMs)
                        else -> Pair(0L, 0L)
                    }
                    if (engineMs > 0 || llmMs > 0) {
                        fun fmt(ms: Long) = if (ms < 1000) "${ms}ms" else "${"%.1f".format(ms / 1000.0)}s"
                        item {
                            Text(
                                "Engine: ${fmt(engineMs)} · LLM: ${fmt(llmMs)}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 16.dp),
                            )
                        }
                    }
                }

                // Error banner (AI failed, showing analysis-only fallback)
                if (isErrorPhase) {
                    item {
                        Card(
                            shape = CaddieShape.medium,
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.errorContainer
                            ),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(Modifier.padding(12.dp)) {
                                Text(
                                    "AI unavailable — showing analysis-only recommendation",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onErrorContainer,
                                )
                                Text(
                                    (state as ShotAdvisorState.Error).message,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onErrorContainer,
                                )
                            }
                        }
                    }
                }

                // Follow-up Q&A — only available once the reveal is finished
                // (Complete) or the LLM failed (Error fallback shown).
                if (isCompletePhase || isErrorPhase) {
                    if (conversation.isNotEmpty()) {
                        items(conversation) { (isUser, text) ->
                            ConversationBubble(text = text, isUser = isUser)
                        }
                    }

                    item {
                        if (showOffTopicDialog) {
                            AlertDialog(
                                onDismissRequest = { showOffTopicDialog = false },
                                title = { Text("Golf questions only") },
                                text = { Text(viewModel.offTopicResponse) },
                                confirmButton = {
                                    TextButton(onClick = { showOffTopicDialog = false }) { Text("OK") }
                                },
                            )
                        }
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            OutlinedTextField(
                                value = followUpText,
                                onValueChange = { followUpText = InputGuard.enforceLimit(it) },
                                placeholder = { Text("Ask a follow-up question…") },
                                modifier = Modifier.weight(1f),
                                maxLines = 2,
                            )
                            IconButton(
                                onClick = {
                                    if (followUpText.isBlank()) return@IconButton
                                    if (!viewModel.isGolfRelated(followUpText)) {
                                        showOffTopicDialog = true
                                        return@IconButton
                                    }
                                    conversation = conversation + (true to followUpText)
                                    val reply = "Follow-up noted: \"$followUpText\". For a detailed answer, make sure your AI provider is configured in Profile settings."
                                    conversation = conversation + (false to reply)
                                    followUpText = ""
                                    scope.launch { sheetListState.animateScrollToItem(conversation.size + 10) }
                                }
                            ) {
                                Icon(
                                    Icons.Default.Send,
                                    contentDescription = "Send",
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                }

                item { Spacer(Modifier.height(32.dp)) }
            }
        }
    }
}

/**
 * Skeleton shown while the LLM is in flight (KAN-116). Mirrors iOS:
 * pulsing golf icon, headline, indeterminate spinner.
 */
@Composable
private fun ShotAdvisorSkeleton() {
    val infiniteTransition = androidx.compose.animation.core.rememberInfiniteTransition(label = "skeleton")
    val scale by infiniteTransition.animateFloat(
        initialValue = 0.95f,
        targetValue = 1.08f,
        animationSpec = androidx.compose.animation.core.infiniteRepeatable(
            animation = androidx.compose.animation.core.tween(
                durationMillis = 1200,
                easing = androidx.compose.animation.core.FastOutSlowInEasing,
            ),
            repeatMode = androidx.compose.animation.core.RepeatMode.Reverse,
        ),
        label = "skeleton-scale",
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(
            Icons.Default.GolfCourse,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .size(48.dp)
                .graphicsLayer(scaleX = scale, scaleY = scale),
        )
        Text(
            "Analyzing your shot…",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CircularProgressIndicator(
            modifier = Modifier.size(24.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

/**
 * Hero card — first section to fade in during the progressive reveal.
 * Club name + AI badge + target/risk/confidence row.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecommendationHeroCard(
    recommendation: ShotRecommendation,
    isEnhanced: Boolean,
) {
    Card(
        shape = CaddieShape.large,
        colors = CardDefaults.cardColors(
            containerColor = if (isEnhanced)
                MaterialTheme.colorScheme.primaryContainer
            else MaterialTheme.colorScheme.surfaceVariant
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    recommendation.recommendedClub.name.replace('_', ' '),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(Modifier.weight(1f))
                if (isEnhanced) {
                    Surface(
                        shape = RoundedCornerShape(8.dp),
                        color = MaterialTheme.colorScheme.primary,
                    ) {
                        Text(
                            "AI",
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                LabelValue("Target", "${recommendation.targetDistanceYards} yds")
                LabelValue("Risk", recommendation.riskLevel.name)
                LabelValue(
                    "Confidence",
                    "${(recommendation.confidenceScore * 100).toInt()}%"
                )
            }
        }
    }
}

/**
 * Rationale section — last to appear in the progressive reveal. Holds the
 * narrative copy that the LLM produces (target description, wind/slope
 * adjustments, execution plan, alternative club).
 */
@Composable
private fun RecommendationRationaleSection(recommendation: ShotRecommendation) {
    Card(
        shape = CaddieShape.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (recommendation.targetDescription.isNotBlank()) {
                Text(recommendation.targetDescription, style = MaterialTheme.typography.bodyMedium)
            }
            if (recommendation.windAdjustmentNote.isNotBlank()) {
                Text(
                    "Wind: ${recommendation.windAdjustmentNote}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (recommendation.slopeAdjustmentNote.isNotBlank()) {
                Text(
                    "Slope: ${recommendation.slopeAdjustmentNote}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (recommendation.executionPlan.isNotBlank()) {
                Text(recommendation.executionPlan, style = MaterialTheme.typography.bodySmall)
            }
            recommendation.alternativeClub?.let { alt ->
                Text(
                    "Alternative: ${alt.name.replace('_', ' ')} — ${recommendation.alternativeRationale}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ExecutionPlanSection(archetype: ShotArchetype) {
    Card(
        shape = CaddieShape.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Setup", style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(4.dp))
            LabelValue("Ball Position", archetype.ballPosition)
            LabelValue("Stance", archetype.stanceWidth)
            LabelValue("Weight", archetype.weightDistribution)
            LabelValue("Tempo", archetype.swingTempo)
            LabelValue("Target Line", archetype.targetLine)
            if (archetype.keyThoughts.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text("Key Thoughts", style = MaterialTheme.typography.labelMedium)
                archetype.keyThoughts.forEach { thought ->
                    Text("• $thought", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun LabelValue(label: String, value: String) {
    Column {
        Text(label, style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun ConversationBubble(text: String, isUser: Boolean) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(
                topStart = 12.dp, topEnd = 12.dp,
                bottomStart = if (isUser) 12.dp else 2.dp,
                bottomEnd = if (isUser) 2.dp else 12.dp,
            ),
            color = if (isUser) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.padding(vertical = 2.dp),
        ) {
            Text(
                text,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                style = MaterialTheme.typography.bodySmall,
                color = if (isUser) MaterialTheme.colorScheme.onPrimary
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun AutoDetectBanner(
    course: NormalizedCourse,
    selectedHole: Int?,
    autoDetectState: AutoDetectState,
    onHoleSelected: (Int) -> Unit,
    onAutoDetect: () -> Unit,
) {
    Card(shape = CaddieShape.medium, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                course.name,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Hole picker
                var holeExpanded by remember { mutableStateOf(false) }
                Box(Modifier.weight(1f)) {
                    OutlinedTextField(
                        value = selectedHole?.let { "Hole $it" } ?: "Select Hole",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Hole") },
                        trailingIcon = {
                            IconButton(onClick = { holeExpanded = true }) {
                                Icon(Icons.Default.ArrowDropDown, null)
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    DropdownMenu(expanded = holeExpanded, onDismissRequest = { holeExpanded = false }) {
                        (1..course.holes.size.coerceAtLeast(18)).forEach { n ->
                            DropdownMenuItem(
                                text = { Text("Hole $n") },
                                onClick = { onHoleSelected(n); holeExpanded = false },
                            )
                        }
                    }
                }
                // Auto Detect button
                FilledTonalButton(
                    onClick = onAutoDetect,
                    enabled = selectedHole != null && autoDetectState !is AutoDetectState.Loading,
                ) {
                    if (autoDetectState is AutoDetectState.Loading) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.MyLocation, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Ask Caddie")
                    }
                }
            }
            if (autoDetectState is AutoDetectState.Error) {
                Text(
                    (autoDetectState as AutoDetectState.Error).message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    ElevatedCard(
        shape = CaddieShape.large,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
            content()
        }
    }
}

@Composable
private fun <T> EnumDropdown(
    label: String,
    selected: T,
    options: List<T>,
    displayName: (T) -> String,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedTextField(
            value = displayName(selected),
            onValueChange = {},
            label = { Text(label) },
            readOnly = true,
            trailingIcon = {
                IconButton(onClick = { expanded = true }) {
                    Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(displayName(option)) },
                    onClick = { onSelect(option); expanded = false },
                )
            }
        }
    }
}

private fun uriToBase64Jpeg(context: Context, uri: Uri): String? {
    return try {
        val inputStream = context.contentResolver.openInputStream(uri) ?: return null
        val bitmap = BitmapFactory.decodeStream(inputStream)
        inputStream.close()
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 50, outputStream)
        Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
    } catch (e: Exception) {
        null
    }
}
