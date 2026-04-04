package com.caddieai.android.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.caddieai.android.data.billing.AdManager
import com.caddieai.android.data.billing.BANNER_AD_UNIT_ID
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

@HiltViewModel
class AdViewModel @Inject constructor(
    private val adManager: AdManager,
) : ViewModel() {
    val shouldShowAds: Boolean get() = adManager.shouldShowAds

    /** Show interstitial ad. Returns true if shown. onDismissed called when ad closes. */
    fun showInterstitial(activity: android.app.Activity, onDismissed: () -> Unit): Boolean {
        return adManager.showInterstitial(activity, onDismissed)
    }

    fun preloadInterstitial() = adManager.preloadInterstitial()
}

/**
 * Self-contained banner ad. Injects AdManager via Hilt.
 * Only renders for free-tier users.
 */
@Composable
fun AdBannerView(modifier: Modifier = Modifier) {
    val viewModel: AdViewModel = hiltViewModel()
    if (!viewModel.shouldShowAds) return

    AndroidView(
        modifier = modifier
            .fillMaxWidth()
            .height(60.dp),
        factory = { context ->
            AdView(context).apply {
                setAdSize(AdSize.BANNER)
                adUnitId = BANNER_AD_UNIT_ID
                loadAd(AdRequest.Builder().build())
            }
        },
    )
}
