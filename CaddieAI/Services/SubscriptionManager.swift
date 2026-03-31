//
//  SubscriptionManager.swift
//  CaddieAI
//
//  Manages StoreKit 2 subscription state and exposes the user's current tier.
//

import Foundation
import StoreKit

@Observable
final class SubscriptionManager {

    // MARK: - Published State

    /// The user's current tier, derived from subscription status or debug override.
    var tier: UserTier {
        debugTierOverride ?? _tier
    }

    /// Debug-only override. When non-nil, `tier` returns this value instead of the real entitlement.
    var debugTierOverride: UserTier?

    private var _tier: UserTier = .free

    /// Available subscription products fetched from the App Store.
    private(set) var products: [Product] = []

    /// Whether a purchase is currently in progress.
    var isPurchasing = false

    /// Last error message for display purposes.
    var errorMessage: String?

    // MARK: - Constants

    /// Product identifier for the monthly Pro subscription.
    static let proMonthlyProductID = "com.caddieai.pro.monthly"

    /// All product identifiers the app supports.
    private static let productIDs: Set<String> = [proMonthlyProductID]

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await refreshTier()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    /// Fetch subscription products from the App Store.
    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    /// Purchase a product and update the tier.
    func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshTier()
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }

        isPurchasing = false
    }

    /// Restore purchases and refresh tier.
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshTier()
    }

    // MARK: - Tier Resolution

    /// Check current entitlements and set the tier accordingly.
    func refreshTier() async {
        var isPaid = false

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if Self.productIDs.contains(transaction.productID) {
                    isPaid = true
                }
            }
        }

        _tier = isPaid ? .paid : .free
    }

    // MARK: - Transaction Listener

    /// Listen for transaction updates (renewals, revocations, etc.)
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await transaction.finish()
                    await self?.refreshTier()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
