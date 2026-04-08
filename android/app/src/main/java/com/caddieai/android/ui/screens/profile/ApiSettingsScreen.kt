package com.caddieai.android.ui.screens.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.caddieai.android.data.model.LLMProvider

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ApiSettingsScreen(
    onBack: () -> Unit,
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val profile by viewModel.profile.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("API Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
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

            item {
                Text(
                    "Configure your AI provider and API key. The key is stored locally on this device.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            item {
                ProfileDropdown(
                    label = "AI Provider",
                    selected = profile.llmProvider,
                    options = LLMProvider.entries,
                    displayName = { it.name.lowercase().replaceFirstChar { c -> c.uppercase() } },
                    onSelect = viewModel::setLlmProvider,
                )
            }

            item {
                when (profile.llmProvider) {
                    LLMProvider.OPENAI -> ApiKeyField(
                        label = "OpenAI API Key",
                        value = profile.openAiApiKey,
                        onValueChange = viewModel::setOpenAiApiKey,
                        placeholder = "sk-…",
                    )
                    LLMProvider.ANTHROPIC -> ApiKeyField(
                        label = "Anthropic API Key",
                        value = profile.anthropicApiKey,
                        onValueChange = viewModel::setAnthropicApiKey,
                        placeholder = "sk-ant-…",
                    )
                    LLMProvider.GOOGLE -> ApiKeyField(
                        label = "Google API Key (Gemini + Maps + Places)",
                        value = profile.googleApiKey,
                        onValueChange = viewModel::setGoogleApiKey,
                        placeholder = "AIza…",
                    )
                    LLMProvider.BEDROCK -> Text(
                        "Bedrock proxy — managed server-side, no API key required.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // LLM Model picker
            item {
                val models = listOf("gpt-4o", "gpt-4o-mini", "claude-sonnet", "claude-haiku", "gemini-pro")
                ProfileDropdown(
                    label = "LLM Model",
                    selected = profile.llmModel,
                    options = models,
                    displayName = { it },
                    onSelect = viewModel::setLlmModel,
                )
            }

            // Subscription section
            item {
                androidx.compose.material3.HorizontalDivider()
                Text("Subscription", style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 8.dp))
            }
            item {
                Text(
                    "Current tier: ${profile.effectiveTier.name}",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            // Telemetry section
            item {
                androidx.compose.material3.HorizontalDivider()
                Text("Telemetry", style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 8.dp))
            }
            item {
                SwitchRow(
                    label = "Share Usage Data",
                    checked = profile.telemetryEnabled,
                    onCheckedChange = viewModel::setTelemetryEnabled,
                )
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun ApiKeyField(label: String, value: String, onValueChange: (String) -> Unit, placeholder: String) {
    var visible by remember { mutableStateOf(false) }
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        placeholder = { Text(placeholder) },
        singleLine = true,
        visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
        trailingIcon = {
            IconButton(onClick = { visible = !visible }) {
                Icon(
                    if (visible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                    contentDescription = "Toggle visibility",
                )
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}
