package com.caddieai.android.ui.navigation

import androidx.lifecycle.ViewModel
import com.caddieai.android.data.diagnostics.DiagnosticLogger
import com.caddieai.android.data.diagnostics.LogCategory
import com.caddieai.android.data.diagnostics.LogLevel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

@HiltViewModel
class NavigationViewModel @Inject constructor(
    private val logger: DiagnosticLogger,
) : ViewModel() {

    private var currentTab: String = "Caddie"
    private var tabEnteredAtMs: Long = System.currentTimeMillis()

    fun logTabSwitch(tabLabel: String) {
        val dwellMs = System.currentTimeMillis() - tabEnteredAtMs
        logger.log(
            level = LogLevel.INFO,
            category = LogCategory.NAVIGATION,
            event = "tab_dwell",
            message = "Spent ${dwellMs}ms on $currentTab tab",
            properties = mapOf("tab" to currentTab, "dwellMs" to dwellMs.toString()),
        )
        currentTab = tabLabel
        tabEnteredAtMs = System.currentTimeMillis()
        logger.log(
            level = LogLevel.INFO,
            category = LogCategory.NAVIGATION,
            event = "tab_switched",
            message = "User switched to $tabLabel tab",
            properties = mapOf("tab" to tabLabel),
        )
    }
}
