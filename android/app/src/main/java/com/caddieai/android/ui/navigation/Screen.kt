package com.caddieai.android.ui.navigation

sealed class Screen(val route: String) {
    data object Splash : Screen("splash")
    data object SetupNotice : Screen("setup_notice")
    data object OnboardingContact : Screen("onboarding_contact")
    data object OnboardingHandicap : Screen("onboarding_handicap")
    data object OnboardingSwingCapture : Screen("onboarding_swing_capture")
    data object OnboardingShortGame : Screen("onboarding_short_game")
    data object Main : Screen("main")
}

sealed class Tab(val route: String) {
    data object Caddie : Tab("tab_caddie")
    data object Course : Tab("tab_course")
    data object History : Tab("tab_history")
    data object Profile : Tab("tab_profile")
}

sealed class HistoryScreen(val route: String) {
    data object Root : HistoryScreen("history_root")
    data object ShotDetail : HistoryScreen("history_shot_detail/{shotId}") {
        fun createRoute(shotId: String) = "history_shot_detail/$shotId"
    }
}

sealed class ProfileScreen(val route: String) {
    data object Root : ProfileScreen("profile_root")
    data object YourBag : ProfileScreen("profile_your_bag")
    data object SwingInfo : ProfileScreen("profile_swing_info")
    data object ApiSettings : ProfileScreen("profile_api_settings")
    data object StayInTouch : ProfileScreen("profile_stay_in_touch")
}
