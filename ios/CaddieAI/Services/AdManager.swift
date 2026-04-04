//
//  AdManager.swift
//  CaddieAI
//
//  Gates ad visibility based on subscription status.
//  Pro subscribers never see ads.
//

import Foundation

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

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

    /// Interstitial ad unit for testing. Replace with real unit ID before release.
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    // MARK: - Interstitial Ad

    #if canImport(GoogleMobileAds)
    /// The preloaded interstitial ad, ready to present.
    private var interstitialAd: InterstitialAd?
    #endif

    /// Whether a preloaded interstitial is ready to show.
    var isInterstitialReady: Bool {
        #if canImport(GoogleMobileAds)
        return interstitialAd != nil
        #else
        return false
        #endif
    }

    /// Frequency cap: only show one interstitial per app session.
    var hasShownInterstitialThisSession = false

    /// Preloads an interstitial ad so it's ready when the user starts course loading.
    func loadInterstitialAd() {
        #if canImport(GoogleMobileAds)
        guard shouldShowAds, !hasShownInterstitialThisSession else { return }
        Task {
            do {
                let ad = try await InterstitialAd.load(
                    with: Self.interstitialAdUnitID,
                    request: Request()
                )
                self.interstitialAd = ad
            } catch {
                LoggingService.shared.error(.general, "Interstitial ad failed to load: \(error.localizedDescription)")
                TelemetryService.shared.recordInterstitialSkipped(reason: "load_failed")
            }
        }
        #endif
    }

    /// Presents the preloaded interstitial ad from the given view controller.
    /// Returns `true` if an ad was presented, `false` otherwise.
    @discardableResult
    func presentInterstitialAd(from viewController: UIViewController, delegate: AnyObject? = nil) -> Bool {
        #if canImport(GoogleMobileAds)
        guard let ad = interstitialAd, shouldShowAds, !hasShownInterstitialThisSession else {
            return false
        }
        if let delegate = delegate as? (any FullScreenContentDelegate) {
            ad.fullScreenContentDelegate = delegate
        }
        ad.present(from: viewController)
        interstitialAd = nil
        hasShownInterstitialThisSession = true
        TelemetryService.shared.recordInterstitialShown()
        return true
        #else
        return false
        #endif
    }

    /// Clears any preloaded interstitial (e.g. when ingestion is cancelled).
    func clearInterstitialAd() {
        #if canImport(GoogleMobileAds)
        interstitialAd = nil
        #endif
    }
}
