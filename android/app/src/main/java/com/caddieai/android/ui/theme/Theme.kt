package com.caddieai.android.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val LightColorScheme = lightColorScheme(
    primary = SystemBlue,
    onPrimary = Color.White,
    primaryContainer = SystemBlueContainer,
    onPrimaryContainer = OnSystemBlueContainer,
    secondary = SuccessGreen,
    onSecondary = Color.White,
    secondaryContainer = SuccessGreenContainer,
    onSecondaryContainer = OnSuccessGreenContainer,
    tertiary = PremiumPurple,
    onTertiary = Color.White,
    tertiaryContainer = PremiumPurpleContainer,
    onTertiaryContainer = OnPremiumPurpleContainer,
    error = ErrorRed,
    onError = Color.White,
    errorContainer = ErrorRedContainer,
    onErrorContainer = OnErrorRedContainer,
    background = SecondarySystemBackground,
    onBackground = Color(0xFF1C1C1E),
    surface = SystemBackground,
    onSurface = Color(0xFF1C1C1E),
    surfaceVariant = SystemGray6,
    onSurfaceVariant = Color(0xFF3C3C43),
    outline = SystemGray5,
)

private val DarkColorScheme = darkColorScheme(
    primary = SystemBlueLight,
    onPrimary = OnSystemBlueContainer,
    primaryContainer = SystemBlueDark,
    onPrimaryContainer = SystemBlueContainer,
    secondary = SuccessGreenLight,
    onSecondary = OnSuccessGreenContainer,
    secondaryContainer = SuccessGreenDark,
    onSecondaryContainer = SuccessGreenContainer,
    tertiary = PremiumPurpleLight,
    onTertiary = OnPremiumPurpleContainer,
    tertiaryContainer = PremiumPurple,
    onTertiaryContainer = PremiumPurpleContainer,
    error = ErrorRedLight,
    onError = OnErrorRedContainer,
    errorContainer = ErrorRed,
    onErrorContainer = ErrorRedContainer,
    background = DarkBackground,
    onBackground = OnDarkSurface,
    surface = DarkSurface,
    onSurface = OnDarkSurface,
    surfaceVariant = DarkSurfaceVariant,
    onSurfaceVariant = Color(0xFFAEAEB2),
    outline = Color(0xFF636366),
)

@Composable
fun CaddieAITheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        shapes = Shapes(
            extraSmall = CaddieShape.small,
            small = CaddieShape.small,
            medium = CaddieShape.medium,
            large = CaddieShape.large,
            extraLarge = CaddieShape.large,
        ),
        content = content
    )
}