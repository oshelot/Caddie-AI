//
//  AdManager.swift
//  CaddieAI
//
//  Gates ad visibility based on subscription status.
//  Pro subscribers never see ads.
//

import Foundation

@Observable
final class AdManager {

    /// Injected via environment wiring in CaddieAIApp
    var subscriptionManager: SubscriptionManager?

    /// Whether ads should be shown to the current user.
    var shouldShowAds: Bool {
        subscriptionManager?.tier == .free
    }

    // MARK: - Test Ad Unit IDs (Google-provided demo units)

    /// Banner ad unit for testing. Replace with real unit IDs before release.
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"
}
