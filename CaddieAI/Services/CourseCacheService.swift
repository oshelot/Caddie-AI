//
//  CourseCacheService.swift
//  CaddieAI
//
//  File-based JSON cache for normalized course models.
//  Uses Documents/CourseCache/ directory with a separate index file.
//

import Foundation

@Observable
final class CourseCacheService {

    private(set) var index: CourseCacheIndex

    private static let cacheDirectoryName = "CourseCache"
    private static let indexFileName = "course_index.json"

    init() {
        self.index = Self.loadIndex() ?? CourseCacheIndex(entries: [])
    }

    // MARK: - Cache Directory

    private static var cacheDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(cacheDirectoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Save

    func save(_ course: NormalizedCourse) {
        let fileName = "course_\(course.id.hashValue).json"
        let fileURL = Self.cacheDirectory.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(course)
            try data.write(to: fileURL)

            // Update index (idempotent: remove old entry first)
            index.entries.removeAll { $0.id == course.id }
            index.entries.append(CourseCacheEntry(
                id: course.id,
                name: course.name,
                city: course.city,
                state: course.state,
                centroid: course.centroid,
                cachedAt: .now,
                schemaVersion: course.schemaVersion,
                fileName: fileName,
                overallConfidence: course.stats.overallConfidence
            ))
            saveIndex()
        } catch {
            print("[CourseCacheService] Save failed: \(error)")
        }
    }

    // MARK: - Load

    func load(id: String) -> NormalizedCourse? {
        guard let entry = index.entries.first(where: { $0.id == id }),
              entry.schemaVersion == NormalizedCourse.currentSchemaVersion else {
            return nil
        }

        let fileURL = Self.cacheDirectory.appendingPathComponent(entry.fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NormalizedCourse.self, from: data)
    }

    // MARK: - Lookup

    func isCached(id: String) -> Bool {
        index.entries.contains { $0.id == id && $0.schemaVersion == NormalizedCourse.currentSchemaVersion }
    }

    func isCached(osmId: String) -> Bool {
        index.entries.contains { $0.id.contains(osmId) }
    }

    var cachedCourses: [CourseCacheEntry] {
        index.entries
            .filter { $0.schemaVersion == NormalizedCourse.currentSchemaVersion }
            .sorted { $0.cachedAt > $1.cachedAt }
    }

    // MARK: - Invalidation

    func invalidate(id: String) {
        if let entry = index.entries.first(where: { $0.id == id }) {
            let fileURL = Self.cacheDirectory.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        index.entries.removeAll { $0.id == id }
        saveIndex()
    }

    func invalidateAll() {
        index.entries.removeAll()
        saveIndex()
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
    }

    // MARK: - Index Persistence

    private func saveIndex() {
        let fileURL = Self.cacheDirectory.appendingPathComponent(Self.indexFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(index) {
            try? data.write(to: fileURL)
        }
    }

    private static func loadIndex() -> CourseCacheIndex? {
        let fileURL = cacheDirectory.appendingPathComponent(indexFileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CourseCacheIndex.self, from: data)
    }
}
