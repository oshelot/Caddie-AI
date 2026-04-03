package com.caddieai.android.ui.screens.history

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.caddieai.android.data.model.Club
import com.caddieai.android.data.model.Outcome
import com.caddieai.android.data.model.ShotHistoryEntry
import com.caddieai.android.data.model.Slope
import com.caddieai.android.data.model.WindStrength
import com.caddieai.android.ui.theme.CaddieShape
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShotDetailScreen(
    shot: ShotHistoryEntry,
    onSave: (outcome: Outcome, actualClub: Club?, notes: String) -> Unit,
    onBack: () -> Unit,
) {
    var selectedOutcome by remember { mutableStateOf(shot.outcome.takeIf { it != Outcome.UNKNOWN }) }
    var selectedClub by remember {
        mutableStateOf(shot.actualClubUsed ?: shot.recommendation?.recommendedClub)
    }
    var notes by remember { mutableStateOf(shot.notes) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Shot Detail") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item { Spacer(Modifier.height(4.dp)) }

            // Section 1: Shot Info
            item { SectionLabel("Shot Info") }
            item {
                Card(shape = CaddieShape.medium, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        val dateStr = SimpleDateFormat("MMM d, yyyy, h:mm a", Locale.getDefault())
                            .format(Date(shot.timestampMs))
                        InfoRow("Date", dateStr)
                        InfoRow("Shot Type", shot.context.shotType.name.replace('_', ' ')
                            .lowercase().replaceFirstChar { it.uppercase() })
                        InfoRow("Distance", "${shot.context.distanceToPin} yds")
                        InfoRow("Lie", shot.context.lie.name.replace('_', ' ')
                            .lowercase().replaceFirstChar { it.uppercase() })
                        shot.recommendation?.let { rec ->
                            InfoRow("Recommended Club", rec.recommendedClub.name.replace('_', ' '))
                            if (rec.targetDescription.isNotBlank()) {
                                InfoRow("Target", rec.targetDescription)
                            }
                        }
                    }
                }
            }

            // Section 2: Conditions (conditional rows)
            val hasWind = shot.context.windStrength != WindStrength.CALM
            val hasSlope = shot.context.slope != Slope.FLAT
            val hasHazards = shot.context.hazardNotes.isNotBlank()
            if (hasWind || hasSlope || hasHazards) {
                item { SectionLabel("Conditions") }
                item {
                    Card(shape = CaddieShape.medium, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (hasWind) {
                                val windDir = shot.context.windDirection.name.replace('_', ' ')
                                    .lowercase().replaceFirstChar { it.uppercase() }
                                InfoRow("Wind", "${shot.context.windStrength.label} $windDir")
                            }
                            if (hasSlope) {
                                InfoRow("Slope", shot.context.slope.name.replace('_', ' ')
                                    .lowercase().replaceFirstChar { it.uppercase() }
                                    .replace("Flat", "Level"))
                            }
                            if (hasHazards) {
                                InfoRow("Hazards", shot.context.hazardNotes)
                            }
                        }
                    }
                }
            }

            // Section 3: Your Result
            item { SectionLabel("Your Result") }
            item {
                Card(shape = CaddieShape.medium, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        // Actual Club picker
                        Text("Actual Club Used", style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        ClubPicker(selected = selectedClub, onSelect = { selectedClub = it })

                        // Outcome buttons
                        Text("Outcome", style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Outcome.entries.filter { it != Outcome.UNKNOWN }.forEach { outcome ->
                                val isSelected = selectedOutcome == outcome
                                OutlinedCard(
                                    onClick = { selectedOutcome = outcome },
                                    shape = RoundedCornerShape(8.dp),
                                    border = BorderStroke(
                                        width = if (isSelected) 2.dp else 1.dp,
                                        color = if (isSelected) MaterialTheme.colorScheme.primary
                                                else MaterialTheme.colorScheme.outlineVariant,
                                    ),
                                    colors = CardDefaults.outlinedCardColors(
                                        containerColor = if (isSelected)
                                            MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
                                        else MaterialTheme.colorScheme.surface,
                                    ),
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Column(
                                        Modifier.padding(vertical = 8.dp).fillMaxWidth(),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                    ) {
                                        Text(outcome.emoji, style = MaterialTheme.typography.titleMedium)
                                        Text(
                                            outcome.displayName,
                                            style = MaterialTheme.typography.labelSmall,
                                            textAlign = TextAlign.Center,
                                            color = if (isSelected) MaterialTheme.colorScheme.primary
                                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }

                        // Notes
                        OutlinedTextField(
                            value = notes,
                            onValueChange = { notes = it },
                            placeholder = { Text("Notes (optional)") },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 2,
                            maxLines = 4,
                        )
                    }
                }
            }

            // Save button
            item {
                Button(
                    onClick = {
                        selectedOutcome?.let { onSave(it, selectedClub, notes) }
                        onBack()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = selectedOutcome != null,
                ) {
                    Text("Save Result")
                }
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun SectionLabel(title: String) {
    Column {
        HorizontalDivider()
        Spacer(Modifier.height(4.dp))
        Text(title, style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun ClubPicker(selected: Club?, onSelect: (Club) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    androidx.compose.foundation.layout.Box {
        OutlinedTextField(
            value = selected?.name?.replace('_', ' ') ?: "Select club",
            onValueChange = {},
            readOnly = true,
            trailingIcon = {
                IconButton(onClick = { expanded = true }) {
                    Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Club.entries.forEach { club ->
                DropdownMenuItem(
                    text = { Text(club.name.replace('_', ' ')) },
                    onClick = { onSelect(club); expanded = false },
                )
            }
        }
    }
}
