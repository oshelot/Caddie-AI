//
//  TelemetryService.swift
//  CaddieAI
//
//  Collects telemetry events (API calls, course plays) and batches
//  them to the CaddieAI telemetry endpoint. Events are queued in
//  memory and flushed periodically or when the batch reaches a threshold.
//

import Foundation
import UIKit

@Observable
final class TelemetryService {
    static let shared = TelemetryService()

    // MARK: - Configuration

    /// Whether telemetry collection is enabled (user opt-out toggle)
    var isEnabled: Bool = true

    private let endpoint: URL?
    private let apiKey: String?
    private let deviceId: String

    // MARK: - Batching

    private var pendingEvents: [[String: Any]] = []
    private let batchSize = 25
    private let flushInterval: TimeInterval = 60 // 1 minute
    private var flushTask: Task<Void, Never>?
    private let lock = NSLock()

    // MARK: - Init

    private init() {
        // Read endpoint and API key from Secrets.plist
        endpoint = Secrets.telemetryEndpoint.flatMap { URL(string: $0) }
        apiKey = Secrets.telemetryApiKey

        // Persist a stable device ID across launches
        let key = "caddieai_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: key)
            deviceId = newId
        }

        startPeriodicFlush()
        observeAppLifecycle()
    }

    // MARK: - Record Events

    /// Records a telemetry event. Call from any thread.
    func record(_ type: TelemetryEventType, properties: [String: Any] = [:]) {
        guard isEnabled, endpoint != nil else { return }

        var event: [String: Any] = [
            "type": type.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        for (key, value) in properties {
            event[key] = value
        }

        lock.lock()
        pendingEvents.append(event)
        let count = pendingEvents.count
        lock.unlock()

        if count >= batchSize {
            flush()
        }
    }

    // MARK: - Convenience Methods

    func recordLLMCall(
        provider: String,
        model: String,
        method: String,
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int
    ) {
        record(.llmCall, properties: [
            "provider": provider,
            "model": model,
            "method": method,
            "promptTokens": promptTokens,
            "completionTokens": completionTokens,
            "totalTokens": totalTokens,
        ])
    }

    func recordGolfAPICall(method: String) {
        record(.golfAPICall, properties: [
            "method": method,
        ])
    }

    func recordWeatherCall() {
        record(.weatherCall)
    }

    func recordMapboxCall() {
        record(.mapboxCall)
    }

    func recordCoursePlayed(courseName: String) {
        record(.coursePlayed, properties: [
            "courseName": courseName,
        ])
    }

    func recordAdImpression(screen: String, adUnit: String) {
        record(.adImpression, properties: [
            "screen": screen,
            "adUnit": adUnit,
        ])
    }

    func recordAdClick(screen: String, adUnit: String) {
        record(.adClick, properties: [
            "screen": screen,
            "adUnit": adUnit,
        ])
    }

    func recordAdLoadFailure(screen: String, error: String) {
        record(.adLoadFailure, properties: [
            "screen": screen,
            "error": error,
        ])
    }

    func recordInterstitialShown() {
        record(.adInterstitialShown)
    }

    func recordInterstitialCompleted() {
        record(.adInterstitialCompleted)
    }

    func recordInterstitialSkipped(reason: String) {
        record(.adInterstitialSkipped, properties: [
            "reason": reason,
        ])
    }

    func recordContactInfoSubmitted(name: String, email: String?, phone: String?) {
        var props: [String: Any] = ["name": name]
        if let email, !email.isEmpty { props["email"] = email }
        if let phone, !phone.isEmpty { props["phone"] = phone }
        record(.contactInfoSubmitted, properties: props)
    }

    // MARK: - Flush

    /// Sends all pending events to the telemetry endpoint.
    func flush() {
        lock.lock()
        guard !pendingEvents.isEmpty else {
            lock.unlock()
            return
        }
        let eventsToSend = pendingEvents
        pendingEvents = []
        lock.unlock()

        guard let endpoint, let apiKey else { return }

        Task.detached(priority: .utility) {
            let payload: [String: Any] = [
                "deviceId": self.deviceId,
                "events": eventsToSend,
            ]

            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.httpBody = body
            request.timeoutInterval = 15

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    // Re-queue on server error (non-client error)
                    if http.statusCode >= 500 {
                        self.lock.lock()
                        self.pendingEvents.insert(contentsOf: eventsToSend, at: 0)
                        self.lock.unlock()
                    }
                }
            } catch {
                // Network failure — re-queue events for next attempt
                self.lock.lock()
                self.pendingEvents.insert(contentsOf: eventsToSend, at: 0)
                self.lock.unlock()
            }
        }
    }

    // MARK: - Periodic Flush

    private func startPeriodicFlush() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.flushInterval ?? 60))
                self?.flush()
            }
        }
    }

    // MARK: - App Lifecycle

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flush()
        }
    }
}

// MARK: - Event Types

enum TelemetryEventType: String {
    case llmCall = "llm_call"
    case golfAPICall = "golf_api_call"
    case weatherCall = "weather_call"
    case mapboxCall = "mapbox_call"
    case coursePlayed = "course_played"
    case adImpression = "ad_impression"
    case adClick = "ad_click"
    case adLoadFailure = "ad_load_failure"
    case adInterstitialShown = "ad_interstitial_shown"
    case adInterstitialCompleted = "ad_interstitial_completed"
    case adInterstitialSkipped = "ad_interstitial_skipped"
    case contactInfoSubmitted = "contact_info_submitted"
}
