package com.caddieai.android.ui.screens.profile

import com.caddieai.android.BuildConfig
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.GolfCourse
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SportsGolf
import androidx.compose.material.icons.filled.Support
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.data.model.Aggressiveness
import com.caddieai.android.data.model.CaddieAccent
import com.caddieai.android.data.model.CaddieGender
import com.caddieai.android.data.model.CaddiePersona
import com.caddieai.android.data.model.MissTendency
import com.caddieai.android.data.model.UserTier
import com.caddieai.android.ui.theme.CaddieShape
import com.caddieai.android.ui.theme.Spacing

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel(),
    subscriptionViewModel: SubscriptionViewModel = hiltViewModel(),
    onNavigateToYourBag: () -> Unit = {},
    onNavigateToSwingInfo: () -> Unit = {},
    onNavigateToTeePreference: () -> Unit = {},
    onNavigateToApiSettings: () -> Unit = {},
    onNavigateToStayInTouch: () -> Unit = {},
) {
    val profile by viewModel.profile.collectAsStateWithLifecycle()
    val subStatus by subscriptionViewModel.subscriptionStatus.collectAsStateWithLifecycle()

    Scaffold(
        topBar = { TopAppBar(title = { Text("Profile") }) },
        bottomBar = { com.caddieai.android.ui.components.AdBannerView() },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item { Spacer(Modifier.height(4.dp)) }

            // ── Player Info (ElevatedCard) ──────────────────────────────────
            item {
                ElevatedCard(shape = CaddieShape.large, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Player Info", style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                        var handicapText by remember(profile.handicap) {
                            mutableStateOf(String.format("%.1f", profile.handicap))
                        }
                        OutlinedTextField(
                            value = handicapText,
                            onValueChange = { v ->
                                handicapText = v
                                v.toFloatOrNull()?.coerceIn(0f, 54f)?.let(viewModel::setHandicap)
                            },
                            label = { Text("Handicap") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                        )
                        ProfileDropdown(
                            label = "Miss Tendency",
                            selected = profile.missTendency,
                            options = MissTendency.entries,
                            displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                            onSelect = viewModel::setMissTendency,
                        )
                        ProfileDropdown(
                            label = "Default Aggressiveness",
                            selected = profile.aggressiveness,
                            options = Aggressiveness.entries,
                            displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                            onSelect = viewModel::setAggressiveness,
                        )
                    }
                }
            }

            // ── Caddie Voice & Personality (ElevatedCard) ──────────────────
            item {
                ElevatedCard(shape = CaddieShape.large, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Caddie Voice & Personality", style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                        ProfileDropdown(
                            label = "Accent",
                            selected = profile.caddieAccent,
                            options = CaddieAccent.entries,
                            displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                            onSelect = viewModel::setCaddieAccent,
                        )
                        ProfileDropdown(
                            label = "Voice",
                            selected = profile.caddieGender,
                            options = CaddieGender.entries,
                            displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                            onSelect = viewModel::setCaddieGender,
                        )
                        PersonaDropdown(
                            selected = profile.caddiePersona,
                            onSelect = viewModel::setCaddiePersona,
                        )
                    }
                }
            }

            // ── Section 4: Navigation Links ────────────────────────────────
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NavLinkRow(
                        icon = Icons.Default.GolfCourse,
                        title = "Your Bag",
                        subtitle = "${profile.bagClubs.size}/13 clubs · Tap to manage",
                        onClick = onNavigateToYourBag,
                    )
                    NavLinkRow(
                        icon = Icons.Default.SportsGolf,
                        title = "Swing Info",
                        subtitle = "Shape, tendencies, short game",
                        onClick = onNavigateToSwingInfo,
                    )
                    NavLinkRow(
                        icon = Icons.Default.Flag,
                        title = "Tee Box Preference",
                        subtitle = profile.preferredTeeBox.displayName,
                        onClick = onNavigateToTeePreference,
                    )
                }
            }

            // ── Settings (ElevatedCard) ────────────────────────────────────
            item {
                ElevatedCard(shape = CaddieShape.large, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Settings", style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                        NavLinkRow(
                            icon = Icons.Default.Settings,
                            title = "API Settings",
                            subtitle = "Configure your AI provider and key",
                            onClick = onNavigateToApiSettings,
                        )
                        // Scoring toggle — binds scorecards to phone/email identity (KAN-225)
                        var showContactPrompt by remember { mutableStateOf(false) }
                        SwitchRow(
                            label = "Scoring",
                            checked = profile.scoringEnabled,
                            onCheckedChange = { enabled ->
                                if (enabled && profile.phone.isBlank() && profile.email.isBlank()) {
                                    showContactPrompt = true
                                } else {
                                    viewModel.setScoringEnabled(enabled)
                                }
                            },
                        )
                        Text(
                            "Track scores hole-by-hole during your round. Scorecards are tied to your contact info.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (showContactPrompt) {
                            var emailInput by remember { mutableStateOf("") }
                            var phoneInput by remember { mutableStateOf("") }
                            androidx.compose.material3.AlertDialog(
                                onDismissRequest = { showContactPrompt = false },
                                title = { Text("Add Contact Info") },
                                text = {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text("Scorecards need to be tied to a phone or email. Add one below:",
                                            style = MaterialTheme.typography.bodySmall)
                                        OutlinedTextField(
                                            value = phoneInput, onValueChange = { phoneInput = it },
                                            label = { Text("Phone") }, singleLine = true,
                                            modifier = Modifier.fillMaxWidth(),
                                        )
                                        OutlinedTextField(
                                            value = emailInput, onValueChange = { emailInput = it },
                                            label = { Text("Email") }, singleLine = true,
                                            modifier = Modifier.fillMaxWidth(),
                                        )
                                    }
                                },
                                confirmButton = {
                                    androidx.compose.material3.TextButton(
                                        onClick = {
                                            if (phoneInput.isNotBlank()) viewModel.setPhone(phoneInput)
                                            if (emailInput.isNotBlank()) viewModel.setEmail(emailInput)
                                            if (phoneInput.isNotBlank() || emailInput.isNotBlank()) {
                                                viewModel.setScoringEnabled(true)
                                            }
                                            showContactPrompt = false
                                        },
                                        enabled = phoneInput.isNotBlank() || emailInput.isNotBlank(),
                                    ) { Text("Save") }
                                },
                                dismissButton = {
                                    androidx.compose.material3.TextButton(
                                        onClick = { showContactPrompt = false }
                                    ) { Text("Cancel") }
                                },
                            )
                        }
                        if (profile.effectiveTier == UserTier.PRO) {
                            SwitchRow(
                                label = "Image Analysis (Beta)",
                                checked = profile.imageAnalysisBetaEnabled,
                                onCheckedChange = viewModel::setImageAnalysisBetaEnabled,
                            )
                            Text(
                                "Attach a photo of your lie for AI analysis. Experimental.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (BuildConfig.DEBUG) {
                            HorizontalDivider()
                            Text("Debug", style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.error)
                            SwitchRow(
                                label = "Override Tier → Pro",
                                checked = profile.debugTierOverride == UserTier.PRO,
                                onCheckedChange = viewModel::setDebugTierOverride,
                            )
                            Text(
                                "Effective tier: ${profile.effectiveTier.name}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            SwitchRow(
                                label = "Remote Logging",
                                checked = profile.debugLoggingEnabled,
                                onCheckedChange = viewModel::setDebugLoggingEnabled,
                            )
                        }
                    }
                }
            }

            // ── Section 6: Contact Info (standalone) ───────────────────────
            item {
                NavLinkRow(
                    icon = Icons.Default.Support,
                    title = "Contact Info",
                    subtitle = "Send feedback or report an issue",
                    onClick = onNavigateToStayInTouch,
                )
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun NavLinkRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        shape = CaddieShape.medium,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(28.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun PersonaDropdown(
    selected: CaddiePersona,
    onSelect: (CaddiePersona) -> Unit,
) {
    val subtitles = mapOf(
        CaddiePersona.PROFESSIONAL to "Data-driven, precise, no-nonsense",
        CaddiePersona.SUPPORTIVE_GRANDPARENT to "Encouraging, patient, warm",
        CaddiePersona.COLLEGE_BUDDY to "Casual, fun, keeps it light",
        CaddiePersona.DRILL_SERGEANT to "Tough love, direct, demanding",
        CaddiePersona.CHILL_SURFER to "Relaxed, positive, go-with-the-flow",
    )
    var expanded by remember { mutableStateOf(false) }
    androidx.compose.foundation.layout.Box {
        OutlinedTextField(
            value = selected.displayName,
            onValueChange = {},
            label = { Text("Personality") },
            supportingText = subtitles[selected]?.let { { Text(it) } },
            readOnly = true,
            trailingIcon = {
                IconButton(onClick = { expanded = true }) {
                    Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            CaddiePersona.entries.forEach { persona ->
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(persona.displayName, style = MaterialTheme.typography.bodyMedium)
                            subtitles[persona]?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    },
                    onClick = { onSelect(persona); expanded = false },
                )
            }
        }
    }
}

@Composable
internal fun SectionHeader(title: String) {
    Column {
        HorizontalDivider()
        Spacer(Modifier.height(Spacing.sm))
        Text(title, style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
internal fun SwitchRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
internal fun <T> ProfileDropdown(
    label: String,
    selected: T,
    options: List<T>,
    displayName: (T) -> String,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    androidx.compose.foundation.layout.Box {
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
