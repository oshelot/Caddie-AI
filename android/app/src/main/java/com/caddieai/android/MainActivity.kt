package com.caddieai.android

import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import androidx.navigation.compose.rememberNavController
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import com.caddieai.android.data.review.ReviewPromptManager
import com.caddieai.android.ui.navigation.AppNavHost
import com.caddieai.android.ui.theme.CaddieAITheme
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject lateinit var reviewPromptManager: ReviewPromptManager
    @Inject lateinit var diagnosticLogger: DiagnosticLogger

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        lifecycleScope.launch {
            reviewPromptManager.recordLaunch()
            if (reviewPromptManager.isEligibleForPrompt()) {
                reviewPromptManager.triggerReviewFlow(this@MainActivity)
                reviewPromptManager.recordPromptShown()
            }
        }

        setContent {
            CaddieAITheme {
                val navController = rememberNavController()
                AppNavHost(navController = navController)
            }
        }

        val startupMs = SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime()
        diagnosticLogger.log(LogLevel.INFO, LogCategory.LIFECYCLE, "app_startup",
            message = "App launched on Android ${Build.VERSION.RELEASE} (${Build.MODEL})",
            properties = mapOf(
                "platform" to "android",
                "osVersion" to Build.VERSION.RELEASE,
                "deviceModel" to Build.MODEL,
                "appVersion" to BuildConfig.VERSION_NAME,
                "buildNumber" to BuildConfig.VERSION_CODE,
                "latencyMs" to startupMs.toString(),
            )
        )
    }

    override fun onStop() {
        super.onStop()
        diagnosticLogger.log(LogLevel.INFO, LogCategory.LIFECYCLE, "app_background")
        diagnosticLogger.flush()
    }
}
