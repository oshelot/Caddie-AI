package com.caddieai.android.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.caddieai.android.data.billing.BANNER_AD_UNIT_ID

/**
 * Adaptive banner ad. Only render when shouldShow = true (i.e. free tier).
 */
@Composable
fun AdBannerView(
    shouldShow: Boolean,
    modifier: Modifier = Modifier,
) {
    if (!shouldShow) return

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
        update = { adView ->
            adView.loadAd(AdRequest.Builder().build())
        }
    )
}
