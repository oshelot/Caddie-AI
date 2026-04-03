//
//  LoggingService.swift
//  CaddieAI
//
//  Remote diagnostic logging client (v2). Batches structured log entries
//  and sends them to the CloudWatch-backed logging endpoint.
//  Complements TelemetryService (which tracks usage metrics) by
//  capturing diagnostic events useful for debugging.
//

import Foundation
import UIKit

final class LoggingService: Sendable {
    static let shared = LoggingService()

    // MARK: - Configuration

    /// Whether remote logging is enabled. Defaults to true when endpoint is configured.
    var isEnabled: Bool = true

    private let endpoint: URL?
    private let apiKey: String?
    private let deviceId: String
    let sessionId: String
    private let platform = "ios"
    private let deviceModel: String
    private let appVersion: String
    private let buildNumber: String

    // MARK: - Batching

    private let lock = NSLock()
    private var buffer: [LogEntry] = []
    private let maxBufferSize = 100
    private let flushThreshold = 50
    private let flushInterval: TimeInterval = 30
    private var flushTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        endpoint = Secrets.loggingEndpoint.flatMap { URL(string: $0) }
        apiKey = Secrets.loggingApiKey
        sessionId = UUID().uuidString

        // Reuse the same device ID as TelemetryService
        let key = "caddieai_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: key)
            deviceId = newId
        }

        // Device model via sysctl (e.g., "iPhone16,1")
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        deviceModel = String(cString: machine)

        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        startPeriodicFlush()
        observeAppLifecycle()
    }

    // MARK: - Public API

    func log(
        _ level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String] = [:]
    ) {
        guard isEnabled, endpoint != nil else { return }

        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            timestampMs: Int(Date().timeIntervalSince1970 * 1000),
            metadata: metadata
        )

        lock.lock()
        if buffer.count >= maxBufferSize {
            buffer.removeFirst()
        }
        buffer.append(entry)
        let count = buffer.count
        lock.unlock()

        if count >= flushThreshold {
            flush()
        }
    }

    // MARK: - Convenience Methods

    func info(_ category: LogCategory, _ message: String, metadata: [String: String] = [:]) {
        log(.info, category: category, message: message, metadata: metadata)
    }

    func warning(_ category: LogCategory, _ message: String, metadata: [String: String] = [:]) {
        log(.warning, category: category, message: message, metadata: metadata)
    }

    func error(_ category: LogCategory, _ message: String, metadata: [String: String] = [:]) {
        log(.error, category: category, message: message, metadata: metadata)
    }

    // MARK: - Flush

    func flush() {
        lock.lock()
        guard !buffer.isEmpty else {
            lock.unlock()
            return
        }
        let entriesToSend = buffer
        buffer = []
        lock.unlock()

        guard let endpoint, let apiKey else { return }

        let osVersion = UIDevice.current.systemVersion

        Task.detached(priority: .utility) { [deviceId, sessionId, platform, deviceModel, appVersion, buildNumber] in
            let entries: [[String: Any]] = entriesToSend.map { entry in
                var dict: [String: Any] = [
                    "level": entry.level.rawValue,
                    "category": entry.category.rawValue,
                    "message": entry.message,
                    "timestampMs": entry.timestampMs,
                ]
                if !entry.metadata.isEmpty {
                    dict["metadata"] = entry.metadata
                }
                return dict
            }

            let payload: [String: Any] = [
                "deviceId": deviceId,
                "platform": platform,
                "sessionId": sessionId,
                "appVersion": appVersion,
                "buildNumber": buildNumber,
                "osVersion": osVersion,
                "deviceModel": deviceModel,
                "entries": entries,
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
                if let http = response as? HTTPURLResponse, http.statusCode >= 500 {
                    // Re-queue on server error
                    self.lock.lock()
                    self.buffer.insert(contentsOf: entriesToSend, at: 0)
                    // Trim if over capacity
                    if self.buffer.count > self.maxBufferSize {
                        self.buffer = Array(self.buffer.suffix(self.maxBufferSize))
                    }
                    self.lock.unlock()
                }
            } catch {
                // Network failure — re-queue
                self.lock.lock()
                self.buffer.insert(contentsOf: entriesToSend, at: 0)
                if self.buffer.count > self.maxBufferSize {
                    self.buffer = Array(self.buffer.suffix(self.maxBufferSize))
                }
                self.lock.unlock()
            }
        }
    }

    // MARK: - Periodic Flush

    private func startPeriodicFlush() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.flushInterval ?? 30))
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

// MARK: - Types

struct LogEntry: Sendable {
    let level: LogLevel
    let category: LogCategory
    let message: String
    let timestampMs: Int
    let metadata: [String: String]
}

enum LogLevel: String, Sendable {
    case info
    case warning
    case error
}

enum LogCategory: String, Sendable {
    case llm = "llm"
    case network = "network"
    case analysis = "analysis"
    case course = "course"
    case weather = "weather"
    case subscription = "subscription"
    case map = "map"
    case general = "general"
}
