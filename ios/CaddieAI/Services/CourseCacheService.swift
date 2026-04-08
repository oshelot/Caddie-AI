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

    /// In-memory LRU cache to avoid repeated disk reads for recently-accessed courses.
    private var memoryCache: [String: NormalizedCourse] = [:]
    private var memoryCacheOrder: [String] = []
    private static let memoryCacheLimit = 8

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
        // Update in-memory cache
        insertIntoMemoryCache(id: course.id, course: course)

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
            LoggingService.shared.error(.course, "Course cache save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Load

    func load(id: String) -> NormalizedCourse? {
        // Check in-memory cache first (avoids disk I/O)
        if let cached = memoryCache[id] {
            touchMemoryCacheEntry(id: id)
            return cached
        }

        guard let entry = index.entries.first(where: { $0.id == id }),
              entry.schemaVersion == NormalizedCourse.currentSchemaVersion else {
            return nil
        }

        let fileURL = Self.cacheDirectory.appendingPathComponent(entry.fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let course = try? decoder.decode(NormalizedCourse.self, from: data) else { return nil }

        // Promote to in-memory cache for subsequent access
        insertIntoMemoryCache(id: id, course: course)
        return course
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

    // MARK: - Proximity Query

    /// Returns cached courses within `radiusMeters` of the given coordinate,
    /// sorted by distance (nearest first).
    func coursesNear(latitude: Double, longitude: Double, radiusMeters: Double = 1500) -> [CourseCacheEntry] {
        let userPoint = GeoJSONPoint(latitude: latitude, longitude: longitude)
        return cachedCourses
            .filter { $0.centroid.distance(to: userPoint) <= radiusMeters }
            .sorted { $0.centroid.distance(to: userPoint) < $1.centroid.distance(to: userPoint) }
    }

    // MARK: - Favorites

    private static let favoritesKey = "favoriteCourseIDs"

    private(set) var favoriteIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }()

    func isFavorite(id: String) -> Bool {
        favoriteIDs.contains(id)
    }

    func toggleFavorite(id: String) {
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.favoritesKey)
    }

    var favoriteCourses: [CourseCacheEntry] {
        cachedCourses.filter { favoriteIDs.contains($0.id) }
    }

    // MARK: - Tee Selection

    func saveSelectedTee(_ tee: String, forCourse id: String) {
        guard let idx = index.entries.firstIndex(where: { $0.id == id }) else { return }
        index.entries[idx].selectedTee = tee
        saveIndex()
    }

    func selectedTee(forCourse id: String) -> String? {
        index.entries.first { $0.id == id }?.selectedTee
    }

    // MARK: - Invalidation

    func invalidate(id: String) {
        memoryCache.removeValue(forKey: id)
        memoryCacheOrder.removeAll { $0 == id }

        if let entry = index.entries.first(where: { $0.id == id }) {
            let fileURL = Self.cacheDirectory.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        index.entries.removeAll { $0.id == id }
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
            UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.favoritesKey)
        }
        saveIndex()
    }

    func invalidateAll() {
        memoryCache.removeAll()
        memoryCacheOrder.removeAll()
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

    // MARK: - In-Memory LRU Helpers

    private func insertIntoMemoryCache(id: String, course: NormalizedCourse) {
        memoryCacheOrder.removeAll { $0 == id }
        memoryCacheOrder.append(id)
        memoryCache[id] = course

        // Evict oldest if over limit
        while memoryCacheOrder.count > Self.memoryCacheLimit {
            let evicted = memoryCacheOrder.removeFirst()
            memoryCache.removeValue(forKey: evicted)
        }
    }

    private func touchMemoryCacheEntry(id: String) {
        memoryCacheOrder.removeAll { $0 == id }
        memoryCacheOrder.append(id)
    }
}
