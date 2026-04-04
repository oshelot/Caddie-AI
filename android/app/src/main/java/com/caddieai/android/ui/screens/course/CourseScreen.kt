package com.caddieai.android.ui.screens.course

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.GolfCourse
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.ui.screens.map.CourseMapScreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CourseScreen(viewModel: CourseViewModel = hiltViewModel(), onNavigateToCaddie: () -> Unit = {}) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // Location permission
    var hasLocationPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
                    == PackageManager.PERMISSION_GRANTED
        )
    }
    val locationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasLocationPermission = granted }
    LaunchedEffect(Unit) {
        if (!hasLocationPermission) {
            locationLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    // Show map when course is selected (from search or cache tap)
    val showMap = state.selectedCourse != null

    AnimatedContent(targetState = showMap, label = "CourseMapToggle") { isMap ->
        if (isMap && state.selectedCourse != null) {
            CourseMapScreen(
                course = state.selectedCourse!!,
                hasLocationPermission = hasLocationPermission,
                onBack = { viewModel.clearSelectedCourse() },
                onNavigateToCaddie = onNavigateToCaddie,
            )
        } else {
            CourseListScreen(
                state = state,
                onCourseNameChange = viewModel::onCourseNameChange,
                onLocationQueryChange = viewModel::onLocationQueryChange,
                onLocationSelected = viewModel::onLocationSelected,
                onSearch = viewModel::search,
                onSelectCourse = viewModel::selectAndIngestCourse,
                onToggleFavorite = viewModel::toggleFavorite,
                onSelectCachedCourse = viewModel::selectCachedCourse,
                onDeleteCourse = viewModel::deleteCachedCourse,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CourseListScreen(
    state: CourseSearchState,
    onCourseNameChange: (String) -> Unit,
    onLocationQueryChange: (String) -> Unit,
    onLocationSelected: (String) -> Unit,
    onSearch: () -> Unit,
    onSelectCourse: (com.caddieai.android.data.course.NominatimResult) -> Unit,
    onToggleFavorite: (String) -> Unit,
    onSelectCachedCourse: (com.caddieai.android.data.model.NormalizedCourse) -> Unit,
    onDeleteCourse: (String) -> Unit = {},
) {
    var selectedTab by remember { mutableStateOf(0) } // 0 = Search, 1 = Saved
    var courseToDelete by remember { mutableStateOf<com.caddieai.android.data.model.NormalizedCourse?>(null) }

    // Delete confirmation dialog
    courseToDelete?.let { course ->
        AlertDialog(
            onDismissRequest = { courseToDelete = null },
            title = { Text("Delete Course?") },
            text = { Text("Course data for ${course.name} is cached for faster loading. If you plan to play here again, consider keeping it.") },
            confirmButton = {
                TextButton(onClick = {
                    onDeleteCourse(course.id)
                    courseToDelete = null
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { courseToDelete = null }) { Text("Keep") }
            },
        )
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Courses") }) },
        bottomBar = { com.caddieai.android.ui.components.AdBannerView() },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // Segmented selector
            SegmentedButtonRow(
                selectedIndex = selectedTab,
                labels = listOf("Search", "Saved"),
                onSelected = { selectedTab = it },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            AnimatedVisibility(state.ingestionState is IngestionState.InProgress) {
                val progress = state.ingestionState as? IngestionState.InProgress
                CourseIngestionBanner(
                    step = progress?.step?.label ?: "",
                    progress = progress?.progress ?: 0f,
                )
            }

            // Interstitial ad during ingestion
            val adViewModel: com.caddieai.android.ui.components.AdViewModel = hiltViewModel()
            var interstitialTriggered by remember { mutableStateOf(false) }
            val activity = (LocalContext.current as? android.app.Activity)
            LaunchedEffect(state.ingestionState) {
                if (state.ingestionState is IngestionState.InProgress && !interstitialTriggered) {
                    interstitialTriggered = true
                    activity?.let { adViewModel.showInterstitial(it) {} }
                }
                if (state.ingestionState !is IngestionState.InProgress) interstitialTriggered = false
            }

            if (selectedTab == 0) {
                // ── Search Tab ──
                SearchTabContent(
                    state = state,
                    onCourseNameChange = onCourseNameChange,
                    onLocationQueryChange = onLocationQueryChange,
                    onLocationSelected = onLocationSelected,
                    onSearch = onSearch,
                    onSelectCourse = onSelectCourse,
                    onToggleFavorite = onToggleFavorite,
                    onSelectCachedCourse = onSelectCachedCourse,
                )
            } else {
                // ── Saved Tab ──
                SavedTabContent(
                    state = state,
                    onToggleFavorite = onToggleFavorite,
                    onSelectCachedCourse = onSelectCachedCourse,
                    onDeleteCourse = { courseToDelete = it },
                )
            }
        }
    }
}

@Composable
private fun SegmentedButtonRow(
    selectedIndex: Int,
    labels: List<String>,
    onSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(0.dp)) {
        labels.forEachIndexed { index, label ->
            val selected = index == selectedIndex
            FilledTonalButton(
                onClick = { onSelected(index) },
                modifier = Modifier.weight(1f),
                colors = if (selected) ButtonDefaults.filledTonalButtonColors()
                         else ButtonDefaults.outlinedButtonColors(),
                shape = if (index == 0) RoundedCornerShape(topStart = 8.dp, bottomStart = 8.dp)
                        else RoundedCornerShape(topEnd = 8.dp, bottomEnd = 8.dp),
            ) { Text(label, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal) }
        }
    }
}

@Composable
private fun SearchTabContent(
    state: CourseSearchState,
    onCourseNameChange: (String) -> Unit,
    onLocationQueryChange: (String) -> Unit,
    onLocationSelected: (String) -> Unit,
    onSearch: () -> Unit,
    onSelectCourse: (com.caddieai.android.data.course.NominatimResult) -> Unit,
    onToggleFavorite: (String) -> Unit,
    onSelectCachedCourse: (com.caddieai.android.data.model.NormalizedCourse) -> Unit,
) {
    val favCourses = state.cachedCourses.filter { it.id in state.favoriteIds }

    LazyColumn(modifier = Modifier.fillMaxSize()) {
        // Search fields
        item {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = state.courseName,
                    onValueChange = onCourseNameChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Golf course name") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    trailingIcon = if (state.courseName.isNotBlank()) {
                        { IconButton(onClick = { onCourseNameChange("") }) { Icon(Icons.Default.Close, contentDescription = "Clear") } }
                    } else null,
                    singleLine = true, label = { Text("Course Name") },
                )
                Box {
                    OutlinedTextField(
                        value = state.locationQuery,
                        onValueChange = onLocationQueryChange,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("City or region (optional)") },
                        leadingIcon = { Icon(Icons.Default.LocationOn, contentDescription = null) },
                        trailingIcon = if (state.locationQuery.isNotBlank()) {
                            { IconButton(onClick = { onLocationQueryChange("") }) { Icon(Icons.Default.Close, contentDescription = "Clear") } }
                        } else null,
                        singleLine = true, label = { Text("Location") },
                    )
                    DropdownMenu(
                        expanded = state.locationSuggestions.isNotEmpty(),
                        onDismissRequest = { onLocationSelected(state.locationQuery) },
                    ) {
                        state.locationSuggestions.forEach { suggestion ->
                            DropdownMenuItem(text = { Text(suggestion) }, onClick = { onLocationSelected(suggestion) })
                        }
                    }
                }
                Button(
                    onClick = onSearch,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = state.courseName.isNotBlank() && !state.isSearching,
                ) {
                    if (state.isSearching) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.Search, contentDescription = null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Search")
                    }
                }
            }
        }

        // Search results
        if (state.nominatimResults.isNotEmpty()) {
            item { SectionLabel("Search Results", Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) }
            items(state.nominatimResults) { result ->
                ListItem(
                    headlineContent = { Text(result.name.ifBlank { result.display_name.substringBefore(",") }) },
                    supportingContent = { Text(result.display_name, maxLines = 2) },
                    leadingContent = { Icon(Icons.Default.GolfCourse, null, tint = MaterialTheme.colorScheme.primary) },
                    modifier = Modifier.clickable { onSelectCourse(result) },
                )
                HorizontalDivider()
            }
        }

        if (state.hasSearched && state.nominatimResults.isEmpty() && !state.isSearching) {
            item {
                Text("No golf courses found. Try a different name or location.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
            }
        }

        // Favorites quick-access on Search tab
        if (favCourses.isNotEmpty()) {
            item { SectionLabel("Favorites", Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) }
            items(favCourses, key = { it.id }) { course ->
                CourseRow(course = course, isFav = true, onToggleFavorite = onToggleFavorite,
                    onClick = { onSelectCachedCourse(course) })
            }
        }
    }
}

@Composable
private fun SavedTabContent(
    state: CourseSearchState,
    onToggleFavorite: (String) -> Unit,
    onSelectCachedCourse: (com.caddieai.android.data.model.NormalizedCourse) -> Unit,
    onDeleteCourse: (com.caddieai.android.data.model.NormalizedCourse) -> Unit,
) {
    val favCourses = state.cachedCourses.filter { it.id in state.favoriteIds }
    val otherCourses = state.cachedCourses.filter { it.id !in state.favoriteIds }

    if (state.cachedCourses.isEmpty()) {
        EmptyCoursesPlaceholder()
        return
    }

    LazyColumn(modifier = Modifier.fillMaxSize()) {
        if (favCourses.isNotEmpty()) {
            item { SectionLabel("Favorites", Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) }
            items(favCourses, key = { it.id }) { course ->
                SwipeToDeleteCourseRow(
                    course = course, isFav = true,
                    onToggleFavorite = onToggleFavorite,
                    onClick = { onSelectCachedCourse(course) },
                    onDelete = { onDeleteCourse(course) },
                )
            }
        }

        if (otherCourses.isNotEmpty()) {
            item { SectionLabel("Other Courses", Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) }
            items(otherCourses, key = { it.id }) { course ->
                SwipeToDeleteCourseRow(
                    course = course, isFav = false,
                    onToggleFavorite = onToggleFavorite,
                    onClick = { onSelectCachedCourse(course) },
                    onDelete = { onDeleteCourse(course) },
                )
            }
        }

        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun CourseRow(
    course: com.caddieai.android.data.model.NormalizedCourse,
    isFav: Boolean,
    onToggleFavorite: (String) -> Unit,
    onClick: () -> Unit,
) {
    val relativeTime = remember(course.cachedAtMs) {
        val diff = System.currentTimeMillis() - course.cachedAtMs
        val days = diff / 86_400_000
        when {
            days < 1 -> "Saved today"
            days < 7 -> "Saved ${days}d ago"
            else -> "Saved ${days / 7}w ago"
        }
    }
    val confidenceColor = when {
        course.confidenceScore >= 0.8f -> Color(0xFF4CAF50)
        course.confidenceScore >= 0.55f -> Color(0xFFFFC107)
        else -> Color(0xFFF44336)
    }

    ListItem(
        headlineContent = { Text(course.name, fontWeight = FontWeight.Medium) },
        supportingContent = {
            Column {
                Text("${course.city}, ${course.state} • Par ${course.par} • ${course.totalYardage} yds")
                Text(relativeTime, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
            }
        },
        leadingContent = {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Default.GolfCourse, null, tint = MaterialTheme.colorScheme.primary)
                // Confidence dot
                Box(
                    Modifier.align(Alignment.BottomEnd)
                        .size(8.dp)
                        .background(confidenceColor, CircleShape)
                )
            }
        },
        trailingContent = {
            IconButton(onClick = { onToggleFavorite(course.id) }) {
                Icon(
                    if (isFav) Icons.Filled.Star else Icons.Filled.StarBorder,
                    contentDescription = "Favorite",
                    tint = if (isFav) Color(0xFFFFC107) else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        modifier = Modifier.clickable(onClick = onClick),
    )
    HorizontalDivider()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDeleteCourseRow(
    course: com.caddieai.android.data.model.NormalizedCourse,
    isFav: Boolean,
    onToggleFavorite: (String) -> Unit,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) { onDelete(); true } else false
        }
    )
    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(end = 16.dp),
                contentAlignment = Alignment.CenterEnd,
            ) { Icon(Icons.Default.Delete, "Delete", tint = MaterialTheme.colorScheme.onErrorContainer) }
        },
    ) {
        CourseRow(course = course, isFav = isFav, onToggleFavorite = onToggleFavorite, onClick = onClick)
    }
}

@Composable
private fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold,
        modifier = modifier)
}

@Composable
private fun CourseIngestionBanner(step: String, progress: Float) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(step, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun EmptyCoursesPlaceholder() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Default.GolfCourse,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
        )
        Spacer(Modifier.height(16.dp))
        Text("No courses yet", style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Text("Search for a course above to get started",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
    }
}
