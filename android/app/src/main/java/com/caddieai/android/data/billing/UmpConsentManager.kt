package com.caddieai.android.data.billing

import android.app.Activity
import android.util.Log
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton
import android.content.Context

enum class ConsentStatus { UNKNOWN, REQUIRED, NOT_REQUIRED, OBTAINED }

@Singleton
class UmpConsentManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val _consentStatus = MutableStateFlow(ConsentStatus.UNKNOWN)
    val consentStatus: StateFlow<ConsentStatus> = _consentStatus.asStateFlow()

    private val _canShowAds = MutableStateFlow(false)
    val canShowAds: StateFlow<Boolean> = _canShowAds.asStateFlow()

    fun requestConsentInfo(activity: Activity, onComplete: (Boolean) -> Unit = {}) {
        val params = ConsentRequestParameters.Builder()
            .setTagForUnderAgeOfConsent(false)
            .build()

        val consentInfo = UserMessagingPlatform.getConsentInformation(activity)
        consentInfo.requestConsentInfoUpdate(
            activity,
            params,
            {
                // Success — check if form needs showing
                if (consentInfo.isConsentFormAvailable &&
                    consentInfo.consentStatus == ConsentInformation.ConsentStatus.REQUIRED
                ) {
                    _consentStatus.value = ConsentStatus.REQUIRED
                    loadAndShowConsentForm(activity, consentInfo, onComplete)
                } else {
                    updateFromConsentInfo(consentInfo)
                    onComplete(true)
                }
            },
            { error ->
                Log.w("UmpConsentManager", "Consent info update failed: ${error.message}")
                _consentStatus.value = ConsentStatus.UNKNOWN
                _canShowAds.value = true // fail open for non-GDPR regions
                onComplete(false)
            }
        )
    }

    private fun loadAndShowConsentForm(
        activity: Activity,
        consentInfo: ConsentInformation,
        onComplete: (Boolean) -> Unit,
    ) {
        UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { error ->
            if (error != null) {
                Log.w("UmpConsentManager", "Consent form error: ${error.message}")
            }
            updateFromConsentInfo(consentInfo)
            onComplete(error == null)
        }
    }

    private fun updateFromConsentInfo(consentInfo: ConsentInformation) {
        _consentStatus.value = when (consentInfo.consentStatus) {
            ConsentInformation.ConsentStatus.OBTAINED -> ConsentStatus.OBTAINED
            ConsentInformation.ConsentStatus.NOT_REQUIRED -> ConsentStatus.NOT_REQUIRED
            ConsentInformation.ConsentStatus.REQUIRED -> ConsentStatus.REQUIRED
            else -> ConsentStatus.UNKNOWN
        }
        _canShowAds.value = consentInfo.canRequestAds()
    }
}
