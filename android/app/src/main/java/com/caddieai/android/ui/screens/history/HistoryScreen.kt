package com.caddieai.android.ui.screens.history

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.History
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.data.model.Outcome
import com.caddieai.android.data.model.ShotHistoryEntry
import com.caddieai.android.ui.theme.CaddieShape
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel = hiltViewModel(),
    onBack: (() -> Unit)? = null,
    onShotTapped: (String) -> Unit = {},
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("History") },
                navigationIcon = {
                    onBack?.let {
                        IconButton(onClick = it) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    }
                }
            )
        },
        bottomBar = { com.caddieai.android.ui.components.AdBannerView() },
    ) { padding ->
        if (state.shots.isEmpty()) {
            EmptyHistory(Modifier.padding(padding))
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Club usage
            if (state.clubUsage.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(4.dp))
                    Text("Club Usage (top 10)", style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.height(8.dp))
                    val maxCount = state.clubUsage.maxOf { it.count }.coerceAtLeast(1)
                    state.clubUsage.forEach { stat ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                stat.club.name.replace('_', ' '),
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.width(100.dp),
                            )
                            LinearProgressIndicator(
                                progress = { stat.count.toFloat() / maxCount },
                                modifier = Modifier
                                    .weight(1f)
                                    .height(8.dp),
                            )
                            Text(
                                " ${stat.count}",
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.width(24.dp),
                            )
                        }
                    }
                }
            }

            // Outcome breakdown
            if (state.outcomeBreakdown.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(4.dp))
                    Text("Outcome Breakdown", style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.height(4.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.outcomeBreakdown.entries
                            .sortedByDescending { it.value }
                            .take(5)
                            .forEach { (outcome, count) ->
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("$count", style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.Bold)
                                    Text(
                                        outcome.name.lowercase().replaceFirstChar { it.uppercase() },
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                                }
                            }
                    }
                }
            }

            item {
                Spacer(Modifier.height(4.dp))
                Text("Shot Log (${state.shots.size})", style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary)
            }

            items(state.shots, key = { it.id }) { shot ->
                SwipeToDeleteShotCard(
                    shot = shot,
                    onDelete = { viewModel.deleteShot(shot.id) },
                    onClick = { onShotTapped(shot.id) },
                )
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDeleteShotCard(shot: ShotHistoryEntry, onDelete: () -> Unit, onClick: () -> Unit) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                true
            } else false
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.errorContainer)
                    .padding(end = 16.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(Icons.Default.Delete, contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.onErrorContainer)
            }
        }
    ) {
        ShotCard(shot, onClick)
    }
}

@Composable
private fun ShotCard(shot: ShotHistoryEntry, onClick: () -> Unit) {
    val relativeTime = remember(shot.timestampMs) { formatRelativeTime(shot.timestampMs) }

    Card(
        onClick = onClick,
        shape = CaddieShape.medium,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    shot.recommendation?.recommendedClub?.name?.replace('_', ' ')
                        ?: "No recommendation",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text("${shot.context.distanceToPin} yds",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ShotChip(shot.context.shotType.name.replace('_', ' ')
                        .lowercase().replaceFirstChar { it.uppercase() })
                    Text(shot.context.lie.name.replace('_', ' ')
                        .lowercase().replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.height(2.dp))
                Text(relativeTime, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
            }
            Text(
                if (shot.outcome != Outcome.UNKNOWN) shot.outcome.emoji else "—",
                style = MaterialTheme.typography.titleLarge,
                color = if (shot.outcome == Outcome.UNKNOWN)
                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun ShotChip(label: String) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
    ) {
        Text(label, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSecondaryContainer)
    }
}

private fun formatRelativeTime(timestampMs: Long): String {
    val diff = System.currentTimeMillis() - timestampMs
    val minutes = diff / 60_000
    val hours = minutes / 60
    val days = hours / 24
    return when {
        minutes < 1 -> "Just now"
        minutes < 60 -> "${minutes}m ago"
        hours < 24 -> "${hours}h ago"
        days < 7 -> "${days}d ago"
        else -> SimpleDateFormat("MMM d", Locale.getDefault()).format(Date(timestampMs))
    }
}

@Composable
private fun EmptyHistory(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Default.History,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )
        Spacer(Modifier.height(16.dp))
        Text("No Shot History", style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Text("Your shots will appear here after you get advice from the caddie.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
    }
}
