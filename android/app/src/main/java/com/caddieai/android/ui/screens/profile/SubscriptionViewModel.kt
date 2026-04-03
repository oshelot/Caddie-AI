package com.caddieai.android.ui.screens.profile

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.android.billingclient.api.ProductDetails
import com.caddieai.android.data.billing.BillingService
import com.caddieai.android.data.billing.BillingState
import com.caddieai.android.data.billing.SubscriptionStatus
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class SubscriptionViewModel @Inject constructor(
    private val billingService: BillingService,
) : ViewModel() {

    val subscriptionStatus: StateFlow<SubscriptionStatus> = billingService.subscriptionStatus
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SubscriptionStatus())

    val billingState: StateFlow<BillingState> = billingService.billingState
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), BillingState.Disconnected)

    val productDetails: StateFlow<ProductDetails?> = billingService.productDetails
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        billingService.connect()
    }

    fun subscribe(activity: Activity) {
        billingService.launchBillingFlow(activity)
    }

    fun restorePurchases() {
        billingService.restorePurchases()
    }
}
