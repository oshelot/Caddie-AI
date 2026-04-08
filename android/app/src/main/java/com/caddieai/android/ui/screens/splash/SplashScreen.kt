package com.caddieai.android.ui.screens.splash

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.caddieai.android.R
import com.caddieai.android.ui.screens.onboarding.OnboardingViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun SplashScreen(
    viewModel: OnboardingViewModel = hiltViewModel(),
    onReadyToNavigate: (showSetup: Boolean, showContact: Boolean) -> Unit
) {
    val logoAlpha = remember { Animatable(0f) }
    val logoScale = remember { Animatable(0.6f) }
    val textAlpha = remember { Animatable(0f) }
    val brandingAlpha = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        // Logo: scale 0.6→1.0 + fade in, 600ms, starts immediately
        launch {
            logoAlpha.animateTo(1f, animationSpec = tween(600, easing = FastOutSlowInEasing))
        }
        launch {
            logoScale.animateTo(1f, animationSpec = tween(600, easing = FastOutSlowInEasing))
        }
        // "CaddieAI" text: fade in, 500ms, 300ms delay
        delay(300)
        launch {
            textAlpha.animateTo(1f, animationSpec = tween(500, easing = FastOutSlowInEasing))
        }
        // Branding block: fade in, 400ms, 500ms total delay
        delay(200)
        launch {
            brandingAlpha.animateTo(1f, animationSpec = tween(400, easing = FastOutSlowInEasing))
        }
        // Navigate after 3 seconds total
        delay(2500)
        val state = viewModel.getOnboardingState()
        val showSetup = !state.hasSeenSetupNotice
        val showContact = !showSetup && viewModel.shouldShowContactPrompt(
            state.contactPromptCount,
            state.lastContactPromptMs
        )
        onReadyToNavigate(showSetup, showContact)
    }

    val orbitronFamily = FontFamily(Font(R.font.orbitron_extrabold, FontWeight.ExtraBold))
    val brandNavy = Color(0xFF0B2265)
    val splashBg = Color(0xFFE8E9EB)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(splashBg)
            .padding(bottom = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // 1. Flexible top spacer
        Spacer(modifier = Modifier.weight(1f))

        // 2. Bolty logo — 260dp frame, circular clip
        Image(
            painter = painterResource(id = R.drawable.bolty_syf),
            contentDescription = "Subculture Golf icon",
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(260.dp)
                .clip(CircleShape)
                .scale(logoScale.value)
                .alpha(logoAlpha.value)
        )

        // 3. Fixed 32dp spacer
        Spacer(modifier = Modifier.height(32.dp))

        // 4. "CaddieAI" wordmark — Orbitron ExtraBold, dual color
        val caddieColor = Color(0xFF23367D)
        val aiColor = Color(0xFFC5031A)
        Text(
            text = buildAnnotatedString {
                withStyle(SpanStyle(color = caddieColor)) { append("Caddie") }
                withStyle(SpanStyle(color = aiColor)) { append("AI") }
            },
            style = TextStyle(
                fontFamily = orbitronFamily,
                fontWeight = FontWeight.ExtraBold,
                fontSize = 44.sp,
                letterSpacing = 0.02.em,
            ),
            modifier = Modifier.alpha(textAlpha.value)
        )

        // 5. Flexible bottom spacer (equal weight with top spacer)
        Spacer(modifier = Modifier.weight(1f))

        // 6. Branding block — "Brought to you by" + Subculture Golf wordmark
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.alpha(brandingAlpha.value)
        ) {
            Text(
                text = "Brought to you by",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Black.copy(alpha = 0.45f)
            )
            Image(
                painter = painterResource(id = R.drawable.sgc_txt_black),
                contentDescription = "Subculture Golf",
                contentScale = ContentScale.Fit,
                modifier = Modifier.width(200.dp)
            )
        }
    }
}
