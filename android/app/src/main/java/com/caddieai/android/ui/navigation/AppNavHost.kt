package com.caddieai.android.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.caddieai.android.ui.screens.onboarding.OnboardingContactScreen
import com.caddieai.android.ui.screens.onboarding.OnboardingHandicapScreen
import com.caddieai.android.ui.screens.onboarding.OnboardingShortGameScreen
import com.caddieai.android.ui.screens.onboarding.OnboardingSwingCaptureScreen
import com.caddieai.android.ui.screens.onboarding.SetupNoticeScreen
import com.caddieai.android.ui.screens.splash.SplashScreen

@Composable
fun AppNavHost(navController: NavHostController) {
    NavHost(
        navController = navController,
        startDestination = Screen.Splash.route
    ) {
        composable(Screen.Splash.route) {
            SplashScreen(
                onReadyToNavigate = { showSetup, showContact ->
                    val destination = when {
                        showSetup -> Screen.SetupNotice.route
                        showContact -> Screen.OnboardingContact.route
                        else -> Screen.Main.route
                    }
                    navController.navigate(destination) {
                        popUpTo(Screen.Splash.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.SetupNotice.route) {
            SetupNoticeScreen(
                onContinue = { showContact ->
                    val destination = if (showContact) Screen.OnboardingContact.route else Screen.Main.route
                    navController.navigate(destination) {
                        popUpTo(Screen.SetupNotice.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.OnboardingContact.route) {
            OnboardingContactScreen(
                onContinue = { showSwingCapture ->
                    if (showSwingCapture) {
                        navController.navigate(Screen.OnboardingHandicap.route) {
                            popUpTo(Screen.OnboardingContact.route) { inclusive = true }
                        }
                    } else {
                        navController.navigate(Screen.Main.route) {
                            popUpTo(Screen.OnboardingContact.route) { inclusive = true }
                        }
                    }
                }
            )
        }

        composable(Screen.OnboardingHandicap.route) {
            OnboardingHandicapScreen(
                onNext = {
                    navController.navigate(Screen.OnboardingSwingCapture.route)
                }
            )
        }

        composable(Screen.OnboardingSwingCapture.route) {
            OnboardingSwingCaptureScreen(
                onNext = {
                    navController.navigate(Screen.OnboardingShortGame.route)
                }
            )
        }

        composable(Screen.OnboardingShortGame.route) {
            OnboardingShortGameScreen(
                onFinish = {
                    navController.navigate(Screen.Main.route) {
                        popUpTo(Screen.OnboardingHandicap.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.Main.route) {
            MainScreen()
        }
    }
}
