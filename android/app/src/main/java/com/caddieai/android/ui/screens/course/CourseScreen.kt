package com.caddieai.android.ui.screens.course

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.filled.GolfCourse
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
fun CourseScreen(viewModel: CourseViewModel = hiltViewModel()) {
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
) {
    Scaffold(
        topBar = { TopAppBar(title = { Text("Courses") }) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = state.courseName,
                    onValueChange = onCourseNameChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Golf course name") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    singleLine = true,
                    label = { Text("Course Name") },
                )
                Box {
                    OutlinedTextField(
                        value = state.locationQuery,
                        onValueChange = onLocationQueryChange,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("City or region (optional)") },
                        leadingIcon = { Icon(Icons.Default.LocationOn, contentDescription = null) },
                        singleLine = true,
                        label = { Text("Location") },
                    )
                    DropdownMenu(
                        expanded = state.locationSuggestions.isNotEmpty(),
                        onDismissRequest = { },
                    ) {
                        state.locationSuggestions.forEach { suggestion ->
                            DropdownMenuItem(
                                text = { Text(suggestion, style = MaterialTheme.typography.bodyMedium) },
                                onClick = { onLocationSelected(suggestion) },
                            )
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

            AnimatedVisibility(state.ingestionState is IngestionState.InProgress) {
                val progress = state.ingestionState as? IngestionState.InProgress
                CourseIngestionBanner(
                    step = progress?.step?.label ?: "",
                    progress = progress?.progress ?: 0f,
                )
            }

            LazyColumn(modifier = Modifier.fillMaxSize()) {
                if (state.nominatimResults.isNotEmpty()) {
                    item {
                        Text(
                            "Search Results",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                        )
                    }
                    items(state.nominatimResults) { result ->
                        ListItem(
                            headlineContent = {
                                Text(result.name.ifBlank { result.display_name.substringBefore(",") })
                            },
                            supportingContent = { Text(result.display_name, maxLines = 2) },
                            leadingContent = {
                                Icon(Icons.Default.GolfCourse, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary)
                            },
                            modifier = Modifier.clickable { onSelectCourse(result) }
                        )
                        Divider()
                    }
                }

                if (state.cachedCourses.isNotEmpty()) {
                    item {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Your Courses",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                        )
                    }
                    items(state.cachedCourses, key = { it.id }) { course ->
                        val isFav = course.id in state.favoriteIds
                        ListItem(
                            headlineContent = { Text(course.name, fontWeight = FontWeight.Medium) },
                            supportingContent = {
                                Text("${course.city}, ${course.state} • Par ${course.par} • ${course.totalYardage} yds")
                            },
                            leadingContent = {
                                Icon(Icons.Default.GolfCourse, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary)
                            },
                            trailingContent = {
                                IconButton(onClick = { onToggleFavorite(course.id) }) {
                                    Icon(
                                        if (isFav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                                        contentDescription = "Favorite",
                                        tint = if (isFav) MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            },
                            modifier = Modifier.clickable { onSelectCachedCourse(course) }
                        )
                        Divider()
                    }
                }

                if (state.cachedCourses.isEmpty() && state.nominatimResults.isEmpty() && state.courseName.isBlank()) {
                    item { EmptyCoursesPlaceholder() }
                }
            }
        }
    }
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
