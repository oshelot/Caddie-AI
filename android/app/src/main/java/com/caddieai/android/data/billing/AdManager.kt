package com.caddieai.android.data.billing

import android.app.Activity
import android.content.Context
import android.util.Log
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.gms.ads.initialization.InitializationStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

// Test ad unit IDs — replace with real ones from AdMob console before release
const val BANNER_AD_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"
const val INTERSTITIAL_AD_UNIT_ID = "ca-app-pub-3940256099942544/1033173712"

@Singleton
class AdManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val billingService: BillingService,
) {
    val subscriptionStatus: StateFlow<SubscriptionStatus> = billingService.subscriptionStatus

    val shouldShowAds: Boolean
        get() = !billingService.subscriptionStatus.value.isPro

    private var interstitialAd: InterstitialAd? = null
    private val _interstitialReady = MutableStateFlow(false)
    val interstitialReady: StateFlow<Boolean> = _interstitialReady.asStateFlow()

    private var interstitialShownThisSession = false

    fun initialize() {
        MobileAds.initialize(context) { status: InitializationStatus ->
            Log.d("AdManager", "MobileAds initialized: ${status.adapterStatusMap}")
            preloadInterstitial()
        }
    }

    fun preloadInterstitial() {
        if (interstitialAd != null || !shouldShowAds) return
        InterstitialAd.load(
            context,
            INTERSTITIAL_AD_UNIT_ID,
            AdRequest.Builder().build(),
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) {
                    interstitialAd = ad
                    _interstitialReady.value = true
                    Log.d("AdManager", "Interstitial loaded")
                }
                override fun onAdFailedToLoad(error: LoadAdError) {
                    interstitialAd = null
                    _interstitialReady.value = false
                    Log.d("AdManager", "Interstitial failed to load: ${error.message}")
                }
            }
        )
    }

    /** Show interstitial. Returns true if shown, false if not available. Calls onDismissed when ad closes. */
    fun showInterstitial(activity: Activity, onDismissed: () -> Unit): Boolean {
        val ad = interstitialAd
        if (ad == null || !shouldShowAds || interstitialShownThisSession) {
            return false
        }
        interstitialShownThisSession = true
        ad.fullScreenContentCallback = object : FullScreenContentCallback() {
            override fun onAdDismissedFullScreenContent() {
                interstitialAd = null
                _interstitialReady.value = false
                preloadInterstitial() // preload next one
                onDismissed()
            }
            override fun onAdFailedToShowFullScreenContent(error: com.google.android.gms.ads.AdError) {
                interstitialAd = null
                _interstitialReady.value = false
                preloadInterstitial()
                onDismissed()
            }
        }
        ad.show(activity)
        return true
    }

    fun buildAdRequest(): AdRequest = AdRequest.Builder().build()
}
