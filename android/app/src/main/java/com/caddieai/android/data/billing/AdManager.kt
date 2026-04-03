package com.caddieai.android.data.billing

import android.content.Context
import android.util.Log
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.admanager.AdManagerAdRequest
import com.google.android.gms.ads.initialization.InitializationStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

// Test ad unit IDs — replace with real ones from AdMob console before release
const val BANNER_AD_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"

@Singleton
class AdManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val billingService: BillingService,
) {
    val subscriptionStatus: StateFlow<SubscriptionStatus> = billingService.subscriptionStatus

    val shouldShowAds: Boolean
        get() = !billingService.subscriptionStatus.value.isPro

    fun initialize() {
        MobileAds.initialize(context) { status: InitializationStatus ->
            Log.d("AdManager", "MobileAds initialized: ${status.adapterStatusMap}")
        }
    }

    fun buildAdRequest(): AdRequest = AdRequest.Builder().build()
}
