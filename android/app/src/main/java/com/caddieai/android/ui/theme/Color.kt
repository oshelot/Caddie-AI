package com.caddieai.android.ui.theme

import androidx.compose.ui.graphics.Color

// --- Primary: System Blue (links, active elements, primary actions) ---
val SystemBlue = Color(0xFF1565C0)
val SystemBlueLight = Color(0xFF1E88E5)
val SystemBlueDark = Color(0xFF0D47A1)
val SystemBlueContainer = Color(0xFFBBDEFB)
val OnSystemBlueContainer = Color(0xFF001B3A)

// --- Success / Caddie / Low-risk: Green ---
val SuccessGreen = Color(0xFF2E7D32)
val SuccessGreenLight = Color(0xFF66BB6A)
val SuccessGreenDark = Color(0xFF1B5E20)
val SuccessGreenContainer = Color(0xFFC8E6C9)
val OnSuccessGreenContainer = Color(0xFF002106)

// --- Error / High-risk: Red ---
val ErrorRed = Color(0xFFB71C1C)
val ErrorRedLight = Color(0xFFEF5350)
val ErrorRedContainer = Color(0xFFFFCDD2)
val OnErrorRedContainer = Color(0xFF410002)

// --- Warning / Medium-risk: Orange ---
val WarningOrange = Color(0xFFE65100)
val WarningOrangeLight = Color(0xFFFF9800)
val WarningOrangeContainer = Color(0xFFFFE0B2)
val OnWarningOrangeContainer = Color(0xFF3E1100)

// --- Premium: Purple ---
val PremiumPurple = Color(0xFF6A1B9A)
val PremiumPurpleLight = Color(0xFFAB47BC)
val PremiumPurpleContainer = Color(0xFFE1BEE7)
val OnPremiumPurpleContainer = Color(0xFF21005D)

// --- Favorites: Yellow ---
val FavoriteYellow = Color(0xFFF9A825)
val FavoriteYellowLight = Color(0xFFFFD54F)
val FavoriteYellowContainer = Color(0xFFFFECB3)

// --- Semantic backgrounds (iOS systemBackground / secondarySystemBackground / systemGray6 equivalents) ---
val SystemBackground = Color(0xFFFFFFFF)
val SecondarySystemBackground = Color(0xFFF2F2F7)
val SystemGray6 = Color(0xFFE5E5EA)
val SystemGray5 = Color(0xFFAEAEB2)

// --- Card tint backgrounds (0.08–0.1 alpha applied at usage site) ---
// Used as: SuccessGreen.copy(alpha = 0.1f), SystemBlue.copy(alpha = 0.08f), etc.

// --- Dark theme surfaces ---
val DarkBackground = Color(0xFF0D1F0F)
val DarkSurface = Color(0xFF1A2E1C)
val DarkSurfaceVariant = Color(0xFF263829)
val OnDarkSurface = Color(0xFFE8F5E9)
val DarkSecondaryBackground = Color(0xFF1C1C1E)
val DarkSystemGray6 = Color(0xFF2C2C2E)