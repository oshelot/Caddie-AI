//
//  ShotHistory.swift
//  CaddieAI
//

import Foundation
import SwiftUI

// MARK: - Shot Record

struct ShotRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var date: Date
    var context: ShotContext
    var recommendedClub: String
    var actualClubUsed: String?
    var effectiveDistance: Int
    var target: String
    var outcome: ShotOutcome?
    var notes: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        context: ShotContext,
        recommendedClub: String,
        actualClubUsed: String? = nil,
        effectiveDistance: Int,
        target: String,
        outcome: ShotOutcome? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.context = context
        self.recommendedClub = recommendedClub
        self.actualClubUsed = actualClubUsed
        self.effectiveDistance = effectiveDistance
        self.target = target
        self.outcome = outcome
        self.notes = notes
    }
}

// MARK: - Shot Outcome

enum ShotOutcome: String, CaseIterable, Codable, Identifiable, Sendable {
    case great
    case good
    case okay
    case poor
    case mishit

    var id: Self { self }

    var displayName: String {
        switch self {
        case .great: return "Great"
        case .good: return "Good"
        case .okay: return "Okay"
        case .poor: return "Poor"
        case .mishit: return "Mishit"
        }
    }

    var emoji: String {
        switch self {
        case .great: return "🔥"
        case .good: return "👍"
        case .okay: return "😐"
        case .poor: return "👎"
        case .mishit: return "💀"
        }
    }
}

// MARK: - Shot History Store

@Observable
final class ShotHistoryStore {
    var records: [ShotRecord] = []

    private static let storageKey = "shotHistory"

    init() {
        load()
    }

    func addRecord(_ record: ShotRecord) {
        records.insert(record, at: 0)
        save()
    }

    func updateRecord(_ record: ShotRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            save()
        }
    }

    func deleteRecord(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    // MARK: - Learning: Club Selection Stats

    /// Returns how often each club was actually used for a given shot type and distance range
    func clubUsageStats(
        shotType: ShotType,
        distanceRange: ClosedRange<Int>
    ) -> [(club: String, count: Int, averageOutcome: Double)] {
        let matching = records.filter { record in
            record.context.shotType == shotType
            && distanceRange.contains(record.effectiveDistance)
            && record.actualClubUsed != nil
        }

        let grouped = Dictionary(grouping: matching) { $0.actualClubUsed ?? "" }

        return grouped.map { club, shots in
            let outcomes = shots.compactMap { $0.outcome }
            let avgOutcome: Double
            if outcomes.isEmpty {
                avgOutcome = 0
            } else {
                avgOutcome = outcomes.reduce(0.0) { sum, outcome in
                    sum + outcomeScore(outcome)
                } / Double(outcomes.count)
            }
            return (club: club, count: shots.count, averageOutcome: avgOutcome)
        }.sorted { $0.count > $1.count }
    }

    /// Returns the player's average outcome score for a given club
    func averageOutcomeForClub(_ clubName: String) -> Double? {
        let matching = records.filter { $0.actualClubUsed == clubName && $0.outcome != nil }
        guard !matching.isEmpty else { return nil }
        let total = matching.reduce(0.0) { sum, record in
            sum + outcomeScore(record.outcome!)
        }
        return total / Double(matching.count)
    }

    /// Returns the most frequently chosen alternate club when the recommended one wasn't used
    func commonOverrides(for recommendedClub: String) -> [(club: String, count: Int)] {
        let overrides = records.filter {
            $0.recommendedClub == recommendedClub
            && $0.actualClubUsed != nil
            && $0.actualClubUsed != recommendedClub
        }
        let grouped = Dictionary(grouping: overrides) { $0.actualClubUsed ?? "" }
        return grouped.map { (club: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ShotRecord].self, from: data) {
            records = decoded
        }
    }

    // MARK: - Helpers

    private func outcomeScore(_ outcome: ShotOutcome) -> Double {
        switch outcome {
        case .great: return 5.0
        case .good: return 4.0
        case .okay: return 3.0
        case .poor: return 2.0
        case .mishit: return 1.0
        }
    }
}
