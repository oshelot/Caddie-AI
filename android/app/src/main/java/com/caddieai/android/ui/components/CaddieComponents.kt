package com.caddieai.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.caddieai.android.ui.theme.CaddieShape
import com.caddieai.android.ui.theme.ErrorRed
import com.caddieai.android.ui.theme.FavoriteYellow
import com.caddieai.android.ui.theme.PremiumPurple
import com.caddieai.android.ui.theme.PremiumPurpleLight
import com.caddieai.android.ui.theme.Spacing
import com.caddieai.android.ui.theme.SuccessGreen
import com.caddieai.android.ui.theme.SuccessGreenLight
import com.caddieai.android.ui.theme.SystemBlue
import com.caddieai.android.ui.theme.WarningOrange
import com.caddieai.android.ui.theme.WarningOrangeLight

// ---------------------------------------------------------------------------
// Risk / confidence color utility
// ---------------------------------------------------------------------------

enum class RiskLevel { LOW, MEDIUM, HIGH }

@Composable
fun riskColor(level: RiskLevel): Color {
    val isDark = MaterialTheme.colorScheme.background.red < 0.5f
    return when (level) {
        RiskLevel.LOW -> if (isDark) SuccessGreenLight else SuccessGreen
        RiskLevel.MEDIUM -> if (isDark) WarningOrangeLight else WarningOrange
        RiskLevel.HIGH -> if (isDark) com.caddieai.android.ui.theme.ErrorRedLight else ErrorRed
    }
}

// ---------------------------------------------------------------------------
// Tinted cards — match iOS card tint pattern (0.08–0.1 alpha background)
// ---------------------------------------------------------------------------

/** Green-tinted card for caddie responses / low-risk content */
@Composable
fun CaddieResponseCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val isDark = MaterialTheme.colorScheme.background.red < 0.5f
    val tint = if (isDark) SuccessGreenLight else SuccessGreen
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = CaddieShape.large,
        colors = CardDefaults.cardColors(containerColor = tint.copy(alpha = 0.10f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Box(modifier = Modifier.padding(Spacing.lg)) { content() }
    }
}

/** Blue-tinted card for user messages / primary info */
@Composable
fun UserMessageCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val tint = SystemBlue
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = CaddieShape.large,
        colors = CardDefaults.cardColors(containerColor = tint.copy(alpha = 0.08f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Box(modifier = Modifier.padding(Spacing.lg)) { content() }
    }
}

/** Red-tinted card for errors / high-risk / avoid sections */
@Composable
fun ErrorCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val isDark = MaterialTheme.colorScheme.background.red < 0.5f
    val tint = if (isDark) com.caddieai.android.ui.theme.ErrorRedLight else ErrorRed
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = CaddieShape.large,
        colors = CardDefaults.cardColors(containerColor = tint.copy(alpha = 0.10f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Box(modifier = Modifier.padding(Spacing.lg)) { content() }
    }
}

/** Orange/yellow-tinted card for warnings / medium-risk / caution */
@Composable
fun WarningCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val isDark = MaterialTheme.colorScheme.background.red < 0.5f
    val tint = if (isDark) WarningOrangeLight else WarningOrange
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = CaddieShape.medium,
        colors = CardDefaults.cardColors(containerColor = tint.copy(alpha = 0.10f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Box(modifier = Modifier.padding(Spacing.lg)) { content() }
    }
}

/** Purple-tinted card for Pro / premium feature callouts */
@Composable
fun PremiumCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val isDark = MaterialTheme.colorScheme.background.red < 0.5f
    val tint = if (isDark) PremiumPurpleLight else PremiumPurple
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = CaddieShape.large,
        colors = CardDefaults.cardColors(containerColor = tint.copy(alpha = 0.10f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Box(modifier = Modifier.padding(Spacing.lg)) { content() }
    }
}

/** Standard surface card with medium corner radius */
@Composable
fun SurfaceCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = CaddieShape.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Box(modifier = Modifier.padding(Spacing.lg)) { content() }
    }
}

// ---------------------------------------------------------------------------
// Buttons — matching iOS filled / outlined / text-only appearance
// ---------------------------------------------------------------------------

/** Filled primary button (iOS: .buttonStyle(.borderedProminent)) */
@Composable
fun CaddiePrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leadingIcon: ImageVector? = null,
) {
    Button(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        enabled = enabled,
        shape = CaddieShape.capsule,
        contentPadding = PaddingValues(horizontal = Spacing.xxl, vertical = Spacing.md),
    ) {
        if (leadingIcon != null) {
            Icon(
                imageVector = leadingIcon,
                contentDescription = null,
                modifier = Modifier
                    .padding(end = Spacing.sm)
                    .size(18.dp),
            )
        }
        Text(text = text, style = MaterialTheme.typography.titleSmall)
    }
}

/** Outlined secondary button (iOS: .buttonStyle(.bordered)) */
@Composable
fun CaddieOutlinedButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leadingIcon: ImageVector? = null,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        enabled = enabled,
        shape = CaddieShape.capsule,
        contentPadding = PaddingValues(horizontal = Spacing.xxl, vertical = Spacing.md),
    ) {
        if (leadingIcon != null) {
            Icon(
                imageVector = leadingIcon,
                contentDescription = null,
                modifier = Modifier
                    .padding(end = Spacing.sm)
                    .size(18.dp),
            )
        }
        Text(text = text, style = MaterialTheme.typography.titleSmall)
    }
}

/** Text-only tertiary button (iOS: .buttonStyle(.plain) or icon-only) */
@Composable
fun CaddieTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    color: Color? = null,
) {
    val resolvedColor = color ?: MaterialTheme.colorScheme.primary
    TextButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        colors = ButtonDefaults.textButtonColors(contentColor = resolvedColor),
    ) {
        Text(text = text, style = MaterialTheme.typography.titleSmall)
    }
}

// ---------------------------------------------------------------------------
// Badges & indicators
// ---------------------------------------------------------------------------

/** Pro/Premium badge pill (purple, iOS: purple label with capsule background) */
@Composable
fun ProBadge(modifier: Modifier = Modifier) {
    val isDark = MaterialTheme.colorScheme.background.red < 0.5f
    val tint = if (isDark) PremiumPurpleLight else PremiumPurple
    Surface(
        modifier = modifier,
        shape = CaddieShape.capsule,
        color = tint.copy(alpha = 0.15f),
    ) {
        Text(
            text = "PRO",
            modifier = Modifier.padding(horizontal = Spacing.sm, vertical = Spacing.xs),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = tint,
        )
    }
}

/** Favorite star color */
val favoriteColor: Color get() = FavoriteYellow

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

/** Section header row matching iOS list section header style */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    action: (@Composable RowScope.() -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.lg, vertical = Spacing.sm),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title.uppercase(),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        action?.invoke(this)
    }
}

// ---------------------------------------------------------------------------
// Risk color chip
// ---------------------------------------------------------------------------

/** Colored chip for shot risk level */
@Composable
fun RiskChip(level: RiskLevel, modifier: Modifier = Modifier) {
    val color = riskColor(level)
    val label = when (level) {
        RiskLevel.LOW -> "Low Risk"
        RiskLevel.MEDIUM -> "Caution"
        RiskLevel.HIGH -> "High Risk"
    }
    Surface(
        modifier = modifier,
        shape = CaddieShape.capsule,
        color = color.copy(alpha = 0.12f),
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = Spacing.md, vertical = Spacing.xs),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
    }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}