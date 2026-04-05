//
//  Scorecard.swift
//  CaddieAI
//
//  Scorecard and per-hole score models with local persistence.
//

import Foundation
import SwiftUI

// MARK: - Hole Score

struct HoleScore: Codable, Sendable, Identifiable {
    var id: Int { holeNumber }
    var holeNumber: Int
    var par: Int
    var score: Int
    var putts: Int?
    var fairwayHit: FairwayResult?
}

enum FairwayResult: String, Codable, Sendable, CaseIterable, Identifiable {
    case hit
    case missed
    case skipped

    var id: Self { self }

    var displayName: String {
        switch self {
        case .hit: return "Hit"
        case .missed: return "Missed"
        case .skipped: return "N/A"
        }
    }
}

// MARK: - Scorecard

struct Scorecard: Codable, Sendable, Identifiable {
    var id: UUID
    var courseId: String
    var courseName: String
    var date: Date
    var playerIdentity: String  // phone or email from profile
    var teePlayed: String?
    var holeScores: [HoleScore]
    var status: ScorecardStatus

    init(
        id: UUID = UUID(),
        courseId: String,
        courseName: String,
        date: Date = .now,
        playerIdentity: String,
        teePlayed: String? = nil,
        holeScores: [HoleScore] = [],
        status: ScorecardStatus = .inProgress
    ) {
        self.id = id
        self.courseId = courseId
        self.courseName = courseName
        self.date = date
        self.playerIdentity = playerIdentity
        self.teePlayed = teePlayed
        self.holeScores = holeScores
        self.status = status
    }
}

enum ScorecardStatus: String, Codable, Sendable {
    case inProgress
    case completed
}

// MARK: - Computed Helpers

extension Scorecard {
    var totalScore: Int {
        holeScores.reduce(0) { $0 + $1.score }
    }

    var totalPar: Int {
        holeScores.reduce(0) { $0 + $1.par }
    }

    var relativeToPar: Int {
        totalScore - totalPar
    }

    var holesPlayed: Int {
        holeScores.count
    }

    var totalPutts: Int? {
        let putts = holeScores.compactMap(\.putts)
        return putts.isEmpty ? nil : putts.reduce(0, +)
    }

    var fairwaysHit: (hit: Int, total: Int)? {
        let eligible = holeScores.filter { $0.par >= 4 && $0.fairwayHit != nil && $0.fairwayHit != .skipped }
        guard !eligible.isEmpty else { return nil }
        let hit = eligible.filter { $0.fairwayHit == .hit }.count
        return (hit: hit, total: eligible.count)
    }

    func score(forHole number: Int) -> HoleScore? {
        holeScores.first { $0.holeNumber == number }
    }

    mutating func setScore(_ holeScore: HoleScore) {
        if let index = holeScores.firstIndex(where: { $0.holeNumber == holeScore.holeNumber }) {
            holeScores[index] = holeScore
        } else {
            holeScores.append(holeScore)
            holeScores.sort { $0.holeNumber < $1.holeNumber }
        }
    }
}

// MARK: - Scorecard Store

@Observable
final class ScorecardStore {
    private(set) var scorecards: [Scorecard] = []

    /// The currently active (in-progress) scorecard, if any.
    var activeScorecard: Scorecard? {
        scorecards.first { $0.status == .inProgress }
    }

    private let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("scorecards", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - CRUD

    func save(_ scorecard: Scorecard) {
        if let index = scorecards.firstIndex(where: { $0.id == scorecard.id }) {
            scorecards[index] = scorecard
        } else {
            scorecards.insert(scorecard, at: 0)
        }
        persist(scorecard)
    }

    func delete(_ scorecard: Scorecard) {
        scorecards.removeAll { $0.id == scorecard.id }
        let url = fileURL(for: scorecard.id)
        try? FileManager.default.removeItem(at: url)
    }

    /// Returns completed scorecards sorted by date (newest first).
    var completedScorecards: [Scorecard] {
        scorecards.filter { $0.status == .completed }.sorted { $0.date > $1.date }
    }

    // MARK: - Persistence

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func persist(_ scorecard: Scorecard) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(scorecard) else { return }
        try? data.write(to: fileURL(for: scorecard.id), options: .atomic)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        scorecards = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Scorecard.self, from: data)
            }
            .sorted { $0.date > $1.date }
    }
}
