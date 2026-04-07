package com.caddieai.android.ui.screens.profile

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.TextButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.data.model.Club

private const val MAX_BAG_CLUBS = 13

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YourBagScreen(
    onBack: () -> Unit,
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val profile by viewModel.profile.collectAsStateWithLifecycle()
    var showAddSheet by remember { mutableStateOf(false) }

    val bagClubs = Club.entries.filter { it != Club.PUTTER && it in profile.bagClubs }
    val isBagFull = bagClubs.size >= MAX_BAG_CLUBS
    val availableClubs = Club.entries.filter { it != Club.PUTTER && it !in profile.bagClubs }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Your Bag") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { if (!isBagFull) showAddSheet = true },
                containerColor = if (isBagFull)
                    MaterialTheme.colorScheme.surfaceVariant
                else
                    MaterialTheme.colorScheme.primaryContainer,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add club")
            }
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        if (isBagFull) "Bag is full — 13 club limit reached"
                        else "Swipe left to remove · Tap distance to edit",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (isBagFull)
                            MaterialTheme.colorScheme.error
                        else
                            MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        "${bagClubs.size}/$MAX_BAG_CLUBS",
                        style = MaterialTheme.typography.labelLarge,
                        color = if (isBagFull)
                            MaterialTheme.colorScheme.error
                        else
                            MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }

            items(bagClubs, key = { it.name }) { club ->
                val dismissState = rememberSwipeToDismissBoxState()
                LaunchedEffect(dismissState.currentValue) {
                    if (dismissState.currentValue == SwipeToDismissBoxValue.EndToStart) {
                        viewModel.removeClub(club)
                    }
                }
                SwipeToDismissBox(
                    state = dismissState,
                    enableDismissFromStartToEnd = false,
                    backgroundContent = {
                        val bgColor by animateColorAsState(
                            targetValue = if (dismissState.targetValue == SwipeToDismissBoxValue.EndToStart)
                                MaterialTheme.colorScheme.errorContainer
                            else
                                MaterialTheme.colorScheme.surface,
                            label = "swipe-bg",
                        )
                        Box(
                            Modifier
                                .fillMaxSize()
                                .background(bgColor)
                                .padding(end = 16.dp),
                            contentAlignment = Alignment.CenterEnd,
                        ) {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = "Remove ${club.displayName}",
                                tint = MaterialTheme.colorScheme.onErrorContainer,
                            )
                        }
                    },
                ) {
                    ClubRow(
                        club = club,
                        distance = profile.clubDistances[club] ?: club.defaultCarryYards,
                        onDistanceChange = { viewModel.setClubDistance(club, it) },
                    )
                }
            }

            // Game Improvement Iron toggle
            item {
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                var showGiDialog by remember { mutableStateOf(false) }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Game Improvement Irons", style = MaterialTheme.typography.bodyMedium,
                            fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
                        if (profile.ironType != null) {
                            Text(
                                profile.ironType!!.displayName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Switch(
                        checked = profile.ironType != null,
                        onCheckedChange = { enabled ->
                            if (enabled) showGiDialog = true
                            else viewModel.setIronType(null)
                        },
                    )
                }
                if (showGiDialog) {
                    AlertDialog(
                        onDismissRequest = { showGiDialog = false },
                        title = { Text("Game Improvement Type") },
                        text = { Text("Regular or Super Game Improvement?") },
                        confirmButton = {
                            TextButton(onClick = {
                                viewModel.setIronType(com.caddieai.android.data.model.IronType.GAME_IMPROVEMENT)
                                showGiDialog = false
                            }) { Text("Regular") }
                        },
                        dismissButton = {
                            TextButton(onClick = {
                                viewModel.setIronType(com.caddieai.android.data.model.IronType.SUPER_GAME_IMPROVEMENT)
                                showGiDialog = false
                            }) { Text("Super") }
                        },
                    )
                }
                Text(
                    "GI/SGI irons have wider soles and higher offset. The caddie will account for reduced versatility from bunkers, tight lies, and rough.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 12.dp),
                )
            }

            item { Spacer(Modifier.height(88.dp)) }
        }
    }

    if (showAddSheet) {
        ModalBottomSheet(
            onDismissRequest = { showAddSheet = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            Column(Modifier.padding(horizontal = 16.dp)) {
                Text(
                    "Add a Club",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
                LazyColumn {
                    items(availableClubs, key = { it.name }) { club ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable {
                                    viewModel.addClub(club)
                                    showAddSheet = false
                                }
                                .padding(vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(club.displayName, style = MaterialTheme.typography.bodyLarge)
                            Text(
                                "${profile.clubDistances[club] ?: club.defaultCarryYards} yds",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        HorizontalDivider()
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun ClubRow(
    club: Club,
    distance: Int,
    onDistanceChange: (Int) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            club.displayName,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
        )
        OutlinedTextField(
            value = distance.toString(),
            onValueChange = { v -> v.toIntOrNull()?.let { onDistanceChange(it) } },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            suffix = { Text("yds") },
            modifier = Modifier
                .weight(0.45f)
                .padding(start = 8.dp),
            singleLine = true,
        )
    }
}
