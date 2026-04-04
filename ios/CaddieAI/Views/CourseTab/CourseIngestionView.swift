//
//  CourseIngestionView.swift
//  CaddieAI
//
//  Loading progress sheet displayed during course ingestion.
//  Free-tier users see an interstitial ad during loading;
//  Pro-tier users see the spinner only.
//

import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct CourseIngestionView: View {
    @Environment(CourseViewModel.self) private var viewModel
    @Environment(AdManager.self) private var adManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var adPresented = false

    var body: some View {
        VStack(spacing: 24) {
            if let error = viewModel.ingestionError {
                // Error state
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text("Ingestion Failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Dismiss") {
                    viewModel.ingestionError = nil
                }
                .buttonStyle(.borderedProminent)

            } else if let warning = viewModel.ingestionWarning {
                // Completed with warning (sparse data)
                Image(systemName: "map.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Limited Course Data")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(warning)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("View Course Map") {
                    viewModel.ingestionWarning = nil
                }
                .buttonStyle(.borderedProminent)

            } else {
                // Loading state
                ProgressView()
                    .controlSize(.large)

                Text(viewModel.ingestionStep)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Fetching course data from OpenStreetMap")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button("Cancel", role: .cancel) {
                    viewModel.cancelIngestion()
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
        }
        .padding(40)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            presentInterstitialIfNeeded()
        }
    }

    private func presentInterstitialIfNeeded() {
        guard !adPresented,
              viewModel.isIngesting,
              viewModel.ingestionError == nil,
              subscriptionManager.tier == .free,
              adManager.isInterstitialReady,
              !adManager.hasShownInterstitialThisSession else {
            // No ad to show — mark ad gate as complete so ingestion transitions normally
            return
        }

        #if canImport(GoogleMobileAds)
        adPresented = true
        viewModel.willShowInterstitialAd()

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            viewModel.adCompleted = true
            TelemetryService.shared.recordInterstitialSkipped(reason: "no_root_vc")
            return
        }

        // Find the topmost presented view controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let delegate = InterstitialAdDelegate(viewModel: viewModel)
        // Store delegate to prevent deallocation
        InterstitialAdDelegate.current = delegate
        adManager.presentInterstitialAd(from: topVC, delegate: delegate)
        #endif
    }
}

#if canImport(GoogleMobileAds)
/// Handles interstitial ad lifecycle callbacks and coordinates with CourseViewModel.
final class InterstitialAdDelegate: NSObject, FullScreenContentDelegate {
    /// Prevents premature deallocation during ad presentation.
    static var current: InterstitialAdDelegate?

    private let viewModel: CourseViewModel

    init(viewModel: CourseViewModel) {
        self.viewModel = viewModel
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        viewModel.didCompleteInterstitialAd()
        Self.current = nil
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        LoggingService.shared.error(.general, "Interstitial ad failed to present: \(error.localizedDescription)")
        TelemetryService.shared.recordInterstitialSkipped(reason: "present_failed")
        viewModel.adCompleted = true
        viewModel.isShowingInterstitialAd = false
        Self.current = nil
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        TelemetryService.shared.recordAdImpression(
            screen: "course_ingestion",
            adUnit: AdManager.interstitialAdUnitID
        )
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        TelemetryService.shared.recordAdClick(
            screen: "course_ingestion",
            adUnit: AdManager.interstitialAdUnitID
        )
    }
}
#endif
