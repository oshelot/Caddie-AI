package com.caddieai.android.data.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

const val PRO_PRODUCT_ID = "com.caddieai.pro.monthly"

sealed class BillingState {
    data object Disconnected : BillingState()
    data object Connected : BillingState()
    data class Error(val message: String) : BillingState()
}

data class SubscriptionStatus(
    val isPro: Boolean = false,
    val purchaseToken: String? = null,
    val isAcknowledged: Boolean = false,
)

@Singleton
class BillingService @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _billingState = MutableStateFlow<BillingState>(BillingState.Disconnected)
    val billingState: StateFlow<BillingState> = _billingState.asStateFlow()

    private val _subscriptionStatus = MutableStateFlow(SubscriptionStatus())
    val subscriptionStatus: StateFlow<SubscriptionStatus> = _subscriptionStatus.asStateFlow()

    private val _productDetails = MutableStateFlow<ProductDetails?>(null)
    val productDetails: StateFlow<ProductDetails?> = _productDetails.asStateFlow()

    private val purchasesUpdatedListener = PurchasesUpdatedListener { billingResult, purchases ->
        if (billingResult.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            scope.launch { handlePurchases(purchases) }
        }
    }

    private val billingClient = BillingClient.newBuilder(context)
        .setListener(purchasesUpdatedListener)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    fun connect() {
        if (billingClient.isReady) return
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    _billingState.value = BillingState.Connected
                    scope.launch {
                        queryProductDetails()
                        queryExistingPurchases()
                    }
                } else {
                    _billingState.value = BillingState.Error("Setup failed: ${result.debugMessage}")
                }
            }

            override fun onBillingServiceDisconnected() {
                _billingState.value = BillingState.Disconnected
            }
        })
    }

    private suspend fun queryProductDetails() {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(PRO_PRODUCT_ID)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                )
            )
            .build()

        val result = billingClient.queryProductDetails(params)
        if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            _productDetails.value = result.productDetailsList?.firstOrNull()
        }
    }

    private suspend fun queryExistingPurchases() {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()

        val result = billingClient.queryPurchasesAsync(params)
        if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            handlePurchases(result.purchasesList)
        }
    }

    private suspend fun handlePurchases(purchases: List<Purchase>) {
        val proPurchase = purchases.firstOrNull { purchase ->
            purchase.products.contains(PRO_PRODUCT_ID) &&
                    purchase.purchaseState == Purchase.PurchaseState.PURCHASED
        }

        if (proPurchase != null) {
            if (!proPurchase.isAcknowledged) {
                val ackParams = AcknowledgePurchaseParams.newBuilder()
                    .setPurchaseToken(proPurchase.purchaseToken)
                    .build()
                billingClient.acknowledgePurchase(ackParams)
            }
            _subscriptionStatus.value = SubscriptionStatus(
                isPro = true,
                purchaseToken = proPurchase.purchaseToken,
                isAcknowledged = true,
            )
        } else {
            _subscriptionStatus.value = SubscriptionStatus(isPro = false)
        }
    }

    fun launchBillingFlow(activity: Activity): Boolean {
        val details = _productDetails.value ?: return false
        val offerToken = details.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return false

        val productDetailsParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(details)
            .setOfferToken(offerToken)
            .build()

        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productDetailsParams))
            .build()

        val result = billingClient.launchBillingFlow(activity, flowParams)
        return result.responseCode == BillingClient.BillingResponseCode.OK
    }

    fun restorePurchases() {
        scope.launch { queryExistingPurchases() }
    }

    fun disconnect() {
        billingClient.endConnection()
        _billingState.value = BillingState.Disconnected
    }
}
