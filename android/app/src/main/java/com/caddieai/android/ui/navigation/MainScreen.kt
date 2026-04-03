package com.caddieai.android.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.caddieai.android.ui.screens.caddie.CaddieScreen
import com.caddieai.android.ui.screens.course.CourseScreen
import androidx.navigation.NavType
import androidx.navigation.navArgument
import com.caddieai.android.ui.screens.history.HistoryScreen
import com.caddieai.android.ui.screens.history.HistoryViewModel
import com.caddieai.android.ui.screens.history.ShotDetailScreen
import com.caddieai.android.ui.screens.profile.ApiSettingsScreen
import com.caddieai.android.ui.screens.profile.FeedbackScreen
import com.caddieai.android.ui.screens.profile.ProfileScreen
import com.caddieai.android.ui.screens.profile.SwingInfoScreen
import com.caddieai.android.ui.screens.profile.YourBagScreen

@Composable
fun MainScreen(
    viewModel: NavigationViewModel = hiltViewModel(),
) {
    // Caddie tab (index 0) is selected by default to match iOS behavior
    var selectedIndex by rememberSaveable { mutableIntStateOf(0) }
    val items = BottomNavItem.entries

    Scaffold(
        bottomBar = {
            NavigationBar {
                items.forEachIndexed { index, item ->
                    NavigationBarItem(
                        selected = selectedIndex == index,
                        onClick = {
                            if (index != selectedIndex) {
                                viewModel.logTabSwitch(item.label)
                            }
                            selectedIndex = index
                        },
                        icon = {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = item.label
                            )
                        },
                        label = { Text(item.label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when (selectedIndex) {
                0 -> CaddieScreen()
                1 -> CourseScreen(onNavigateToCaddie = { selectedIndex = 0 })
                2 -> HistoryNavHost()
                3 -> ProfileNavHost()
            }
        }
    }
}

@Composable
private fun HistoryNavHost() {
    val navController = rememberNavController()
    val historyViewModel: HistoryViewModel = hiltViewModel()

    NavHost(
        navController = navController,
        startDestination = com.caddieai.android.ui.navigation.HistoryScreen.Root.route,
    ) {
        composable(com.caddieai.android.ui.navigation.HistoryScreen.Root.route) {
            HistoryScreen(
                viewModel = historyViewModel,
                onShotTapped = { shotId ->
                    navController.navigate(
                        com.caddieai.android.ui.navigation.HistoryScreen.ShotDetail.createRoute(shotId)
                    )
                },
            )
        }
        composable(
            route = com.caddieai.android.ui.navigation.HistoryScreen.ShotDetail.route,
            arguments = listOf(navArgument("shotId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val shotId = backStackEntry.arguments?.getString("shotId") ?: return@composable
            val state = historyViewModel.state.collectAsStateWithLifecycle()
            val shot = state.value.shots.firstOrNull { it.id == shotId }
            if (shot != null) {
                ShotDetailScreen(
                    shot = shot,
                    onSave = { outcome, actualClub, notes ->
                        historyViewModel.updateShot(shotId, outcome, actualClub, notes)
                    },
                    onBack = { navController.popBackStack() },
                )
            }
        }
    }
}

@Composable
private fun ProfileNavHost() {
    val navController = rememberNavController()
    NavHost(
        navController = navController,
        startDestination = ProfileScreen.Root.route,
    ) {
        composable(ProfileScreen.Root.route) {
            ProfileScreen(
                onNavigateToYourBag = { navController.navigate(ProfileScreen.YourBag.route) },
                onNavigateToSwingInfo = { navController.navigate(ProfileScreen.SwingInfo.route) },
                onNavigateToApiSettings = { navController.navigate(ProfileScreen.ApiSettings.route) },
                onNavigateToStayInTouch = { navController.navigate(ProfileScreen.StayInTouch.route) },
            )
        }
        composable(ProfileScreen.YourBag.route) {
            YourBagScreen(onBack = { navController.popBackStack() })
        }
        composable(ProfileScreen.SwingInfo.route) {
            SwingInfoScreen(onBack = { navController.popBackStack() })
        }
        composable(ProfileScreen.ApiSettings.route) {
            ApiSettingsScreen(onBack = { navController.popBackStack() })
        }
        composable(ProfileScreen.StayInTouch.route) {
            FeedbackScreen(onBack = { navController.popBackStack() })
        }
    }
}
