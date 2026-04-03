package com.caddieai.android.ui.screens.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.GolfCourse
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.data.model.Aggressiveness
import com.caddieai.android.data.model.MissTendency
import com.caddieai.android.data.model.StockShape
import com.caddieai.android.data.model.SwingTendency
import com.caddieai.android.ui.screens.profile.ProfileViewModel

@Composable
fun OnboardingSwingCaptureScreen(
    onNext: () -> Unit,
    profileViewModel: ProfileViewModel = hiltViewModel(),
) {
    val profile by profileViewModel.profile.collectAsStateWithLifecycle()

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.GolfCourse,
                contentDescription = null,
                modifier = Modifier.size(72.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(modifier = Modifier.height(24.dp))
            Text(
                text = "Swing Profile",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.primary,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Step 2 of 3",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Tell your caddie how you swing so they can give better advice.",
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(modifier = Modifier.height(32.dp))
            OnboardingDropdown(
                label = "Stock Shape",
                selected = profile.stockShape,
                options = StockShape.entries,
                displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                onSelect = profileViewModel::setStockShape,
            )
            Spacer(modifier = Modifier.height(16.dp))
            OnboardingDropdown(
                label = "Miss Tendency",
                selected = profile.missTendency,
                options = MissTendency.entries,
                displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                onSelect = profileViewModel::setMissTendency,
            )
            Spacer(modifier = Modifier.height(16.dp))
            OnboardingDropdown(
                label = "Swing Tendency",
                selected = profile.swingTendency,
                options = SwingTendency.entries,
                displayName = { it.name.replace('_', ' ').lowercase().replaceFirstChar { c -> c.uppercase() } },
                onSelect = profileViewModel::setSwingTendency,
            )
            Spacer(modifier = Modifier.height(16.dp))
            OnboardingDropdown(
                label = "Aggressiveness",
                selected = profile.aggressiveness,
                options = Aggressiveness.entries,
                displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                onSelect = profileViewModel::setAggressiveness,
            )
            Spacer(modifier = Modifier.height(40.dp))
            Button(
                onClick = onNext,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Next")
            }
        }
    }
}

@Composable
private fun <T> OnboardingDropdown(
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
