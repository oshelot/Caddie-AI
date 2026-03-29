//
//  AdBannerView.swift
//  CaddieAI
//
//  Reusable SwiftUI wrapper around Google Mobile Ads BannerView.
//  Collapses to zero height when no ad fills or when ads are disabled.
//

import SwiftUI
import GoogleMobileAds

struct AdBannerView: UIViewRepresentable {

    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: AdSizeBanner)
        bannerView.adUnitID = adUnitID
        bannerView.delegate = context.coordinator
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        return bannerView
    }

    func updateUIView(_ bannerView: BannerView, context: Context) {
        if bannerView.rootViewController == nil,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootVC
            bannerView.load(Request())
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, @preconcurrency BannerViewDelegate {

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            TelemetryService.shared.recordAdImpression(
                screen: bannerView.adUnitID ?? "unknown",
                adUnit: bannerView.adUnitID ?? "unknown"
            )
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            TelemetryService.shared.recordAdLoadFailure(
                screen: bannerView.adUnitID ?? "unknown",
                error: error.localizedDescription
            )
        }

        func bannerViewDidRecordClick(_ bannerView: BannerView) {
            TelemetryService.shared.recordAdClick(
                screen: bannerView.adUnitID ?? "unknown",
                adUnit: bannerView.adUnitID ?? "unknown"
            )
        }
    }
}

/// Convenience view that only shows the banner for free-tier users.
struct AdBannerSection: View {
    @Environment(AdManager.self) private var adManager

    var body: some View {
        if adManager.shouldShowAds {
            AdBannerView(adUnitID: AdManager.bannerAdUnitID)
                .frame(height: 50)
        }
    }
}
