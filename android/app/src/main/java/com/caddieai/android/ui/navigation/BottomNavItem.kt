package com.caddieai.android.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GolfCourse
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.ui.graphics.vector.ImageVector

enum class BottomNavItem(
    val tab: Tab,
    val label: String,
    val icon: ImageVector,
) {
    CADDIE(Tab.Caddie, "Caddie", Icons.Filled.SmartToy),
    COURSE(Tab.Course, "Course", Icons.Filled.GolfCourse),
    HISTORY(Tab.History, "History", Icons.Filled.History),
    PROFILE(Tab.Profile, "Profile", Icons.Filled.Person),
}
