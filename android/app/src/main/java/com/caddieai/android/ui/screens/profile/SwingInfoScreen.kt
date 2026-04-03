package com.caddieai.android.ui.screens.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.data.model.BunkerConfidence
import com.caddieai.android.data.model.ChipStyle
import com.caddieai.android.data.model.MissTendency
import com.caddieai.android.data.model.StockShape
import com.caddieai.android.data.model.SwingTendency
import com.caddieai.android.data.model.WedgeConfidence

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwingInfoScreen(
    onBack: () -> Unit,
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val profile by viewModel.profile.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Swing Info") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
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
            item {
                SwingInfoDropdown(
                    label = "Stock Shape",
                    selected = profile.stockShape,
                    options = StockShape.entries,
                    displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                    onSelect = viewModel::setStockShape,
                )
            }
            item {
                SwingInfoDropdown(
                    label = "Miss Tendency",
                    selected = profile.missTendency,
                    options = MissTendency.entries,
                    displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                    onSelect = viewModel::setMissTendency,
                )
            }
            item {
                SwingInfoDropdown(
                    label = "Swing Tendency",
                    selected = profile.swingTendency,
                    options = SwingTendency.entries,
                    displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                    onSelect = viewModel::setSwingTendency,
                )
            }
            item {
                SwingInfoDropdown(
                    label = "Bunker Confidence",
                    selected = profile.bunkerConfidence,
                    options = BunkerConfidence.entries,
                    displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                    onSelect = viewModel::setBunkerConfidence,
                )
            }
            item {
                SwingInfoDropdown(
                    label = "Wedge Confidence",
                    selected = profile.wedgeConfidence,
                    options = WedgeConfidence.entries,
                    displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                    onSelect = viewModel::setWedgeConfidence,
                )
            }
            item {
                SwingInfoDropdown(
                    label = "Chip Style",
                    selected = profile.chipStyle,
                    options = ChipStyle.entries,
                    displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                    onSelect = viewModel::setChipStyle,
                )
            }
        }
    }
}

@Composable
private fun <T> SwingInfoDropdown(
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
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(displayName(option)) },
                    onClick = { onSelect(option); expanded = false },
                )
            }
        }
    }
}
