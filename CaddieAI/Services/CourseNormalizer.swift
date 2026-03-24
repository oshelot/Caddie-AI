//
//  CourseNormalizer.swift
//  CaddieAI
//
//  Converts parsed OSM features into canonical NormalizedCourse(s).
//  Detects multi-course facilities (e.g., main + par 3, 27-hole combos)
//  using spatial clustering when duplicate hole numbers are found.
//

import Foundation

struct CourseNormalizer {

    // MARK: - Public API

    /// Normalizes parsed features into one or more courses.
    /// Returns multiple courses when the facility has sub-courses
    /// (detected via duplicate hole numbers + spatial separation).
    static func normalizeAll(
        features: OSMParser.ParsedFeatures,
        courseName: String,
        osmCourseId: String,
        city: String? = nil,
        state: String? = nil
    ) -> [NormalizedCourse] {
        // Build all holes from raw features
        var allHoles = buildAllHoles(from: features)

        // Associate features to holes
        associateGreens(features.greens, to: &allHoles)
        associateTees(features.tees, to: &allHoles)
        associatePins(features.pins, to: &allHoles)
        associateBunkers(features.bunkers, to: &allHoles, maxDistanceMeters: 100)
        associateWater(features.waterFeatures, to: &allHoles, maxDistanceMeters: 150)

        // Score each hole
        for i in allHoles.indices {
            let breakdown = computeConfidence(for: allHoles[i])
            allHoles[i].confidenceBreakdown = breakdown
            allHoles[i].confidence = breakdown.weighted
        }

        // Cluster into sub-courses if duplicate hole numbers exist
        let clusters = clusterIntoSubCourses(allHoles)

        if clusters.count <= 1 {
            // Single course — normal path
            let course = buildCourse(
                holes: allHoles,
                courseName: courseName,
                subCourseName: nil,
                osmCourseId: osmCourseId,
                city: city,
                state: state,
                boundary: features.courseBoundary
            )
            return [course]
        }

        // Multiple sub-courses detected
        let namedClusters = nameSubCourses(clusters)

        return namedClusters.map { (name, holes) in
            buildCourse(
                holes: holes,
                courseName: "\(courseName) — \(name)",
                subCourseName: name,
                osmCourseId: osmCourseId,
                city: city,
                state: state,
                boundary: nil // sub-courses don't get the facility boundary
            )
        }
    }

    /// Single-course convenience (backward compatible). Returns the largest sub-course.
    static func normalize(
        features: OSMParser.ParsedFeatures,
        courseName: String,
        osmCourseId: String,
        city: String? = nil,
        state: String? = nil
    ) -> NormalizedCourse {
        let all = normalizeAll(
            features: features,
            courseName: courseName,
            osmCourseId: osmCourseId,
            city: city,
            state: state
        )
        return all.max(by: { $0.holes.count < $1.holes.count }) ?? all[0]
    }

    // MARK: - Build All Holes

    private static func buildAllHoles(from features: OSMParser.ParsedFeatures) -> [NormalizedHole] {
        var holes: [NormalizedHole] = features.holeLines
            .enumerated()
            .map { index, holeLine in
                NormalizedHole(
                    id: "hole_\(holeLine.osmId)",
                    number: holeLine.number ?? (index + 1),
                    par: holeLine.par,
                    confidence: 0.0,
                    lineOfPlay: holeLine.geometry,
                    teeAreas: [],
                    green: nil,
                    pin: nil,
                    bunkers: [],
                    water: [],
                    rawRefs: HoleRawRefs(
                        holeWayId: holeLine.osmId,
                        greenWayId: nil,
                        teeIds: []
                    )
                )
            }

        // If no hole lines but greens exist, create holes from greens
        if holes.isEmpty && !features.greens.isEmpty {
            holes = features.greens
                .enumerated()
                .map { index, green in
                    NormalizedHole(
                        id: "hole_green_\(green.osmId)",
                        number: green.holeNumber ?? (index + 1),
                        par: nil,
                        confidence: 0.0,
                        lineOfPlay: nil,
                        teeAreas: [],
                        green: green.geometry,
                        pin: nil,
                        bunkers: [],
                        water: [],
                        rawRefs: HoleRawRefs(
                            holeWayId: nil,
                            greenWayId: green.osmId,
                            teeIds: []
                        )
                    )
                }
        }

        return holes
    }

    // MARK: - Spatial Clustering

    /// Groups holes into sub-courses when duplicate hole numbers are detected.
    /// Uses single-linkage clustering: two holes are in the same cluster if
    /// any of their geometry points are within the threshold distance.
    private static func clusterIntoSubCourses(
        _ holes: [NormalizedHole]
    ) -> [[NormalizedHole]] {
        // Check for duplicate hole numbers
        let numberCounts = Dictionary(grouping: holes, by: \.number)
        let hasDuplicates = numberCounts.values.contains { $0.count > 1 }
        guard hasDuplicates else { return [holes] }

        // Distance threshold for same-cluster: 400m
        // Holes on the same course are typically within 200m of each other;
        // separate courses (e.g., main vs par 3) are usually 500m+ apart
        let clusterThreshold: Double = 400

        // Compute centroids for each hole
        let holeCentroids: [GeoJSONPoint] = holes.map { hole in
            if let line = hole.lineOfPlay {
                let points = line.points
                guard !points.isEmpty else { return hole.green?.centroid ?? GeoJSONPoint(latitude: 0, longitude: 0) }
                let midIdx = points.count / 2
                return points[midIdx]
            }
            return hole.green?.centroid ?? GeoJSONPoint(latitude: 0, longitude: 0)
        }

        // Union-Find for clustering
        var parent = Array(0..<holes.count)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        // Link holes that are within threshold distance
        for i in 0..<holes.count {
            for j in (i + 1)..<holes.count {
                let dist = holeCentroids[i].distance(to: holeCentroids[j])
                if dist < clusterThreshold {
                    union(i, j)
                }
            }
        }

        // Group by cluster root
        var clusterMap: [Int: [Int]] = [:]
        for i in 0..<holes.count {
            let root = find(i)
            clusterMap[root, default: []].append(i)
        }

        let clusters = clusterMap.values.map { indices in
            indices.map { holes[$0] }
        }

        // Only split if we actually get meaningful groups
        // (e.g., don't split a 9-hole course into 9 clusters of 1)
        let meaningfulClusters = clusters.filter { $0.count >= 3 }
        if meaningfulClusters.count <= 1 {
            return [holes]
        }

        return meaningfulClusters.sorted { $0.count > $1.count }
    }

    // MARK: - Name Sub-Courses

    /// Assigns descriptive names to each cluster.
    private static func nameSubCourses(
        _ clusters: [[NormalizedHole]]
    ) -> [(String, [NormalizedHole])] {
        // Sort clusters: largest first
        let sorted = clusters.sorted { $0.count > $1.count }

        return sorted.enumerated().map { index, holes in
            let holeCount = holes.count
            let sortedNumbers = holes.map(\.number).sorted()
            let hasPar3Only = holes.allSatisfy { ($0.par ?? 4) == 3 }

            let name: String
            if hasPar3Only && holeCount <= 9 {
                name = "Par 3 Course"
            } else if holeCount >= 15 {
                name = "Main Course"
            } else if holeCount == 9 {
                // Try to detect named nines by hole number range
                if let first = sortedNumbers.first, let last = sortedNumbers.last {
                    if first == 1 && last == 9 {
                        name = index == 0 ? "Front Nine" : "Back Nine"
                    } else if first == 10 && last == 18 {
                        name = "Back Nine"
                    } else {
                        name = "Course \(Character(UnicodeScalar(65 + index)!))" // A, B, C
                    }
                } else {
                    name = "Course \(Character(UnicodeScalar(65 + index)!))"
                }
            } else {
                name = "Course \(Character(UnicodeScalar(65 + index)!))"
            }

            // Re-number holes sequentially within each sub-course
            var renumbered = holes.sorted { $0.number < $1.number }
            for i in renumbered.indices {
                renumbered[i].id = "hole_\(i + 1)"
                renumbered[i].number = i + 1
            }

            return (name, renumbered)
        }
    }

    // MARK: - Build Course from Holes

    private static func buildCourse(
        holes: [NormalizedHole],
        courseName: String,
        subCourseName: String?,
        osmCourseId: String,
        city: String?,
        state: String?,
        boundary: GeoJSONPolygon?
    ) -> NormalizedCourse {
        let sortedHoles = holes.sorted { $0.number < $1.number }
        let centroid = computeCourseCentroid(holes: sortedHoles, boundary: boundary)
        let bbox = computeCourseBBox(holes: sortedHoles, boundary: boundary)
        let courseId = NormalizedCourse.generateId(name: courseName, centroid: centroid)

        let stats = CourseStats(
            holesDetected: sortedHoles.count,
            greensDetected: sortedHoles.filter { $0.green != nil }.count,
            teesDetected: sortedHoles.filter { !$0.teeAreas.isEmpty }.count,
            bunkersDetected: sortedHoles.flatMap(\.bunkers).count,
            waterFeaturesDetected: sortedHoles.flatMap(\.water).count,
            overallConfidence: sortedHoles.isEmpty
                ? 0
                : sortedHoles.map(\.confidence).reduce(0, +) / Double(sortedHoles.count)
        )

        return NormalizedCourse(
            id: courseId,
            source: CourseSource(
                provider: "osm",
                fetchedAt: .now,
                osmCourseId: osmCourseId
            ),
            name: courseName,
            city: city,
            state: state,
            centroid: centroid,
            boundingBox: bbox,
            holes: sortedHoles,
            courseBoundary: boundary,
            stats: stats,
            subCourseName: subCourseName
        )
    }

    // MARK: - Green Association

    private static func associateGreens(
        _ greens: [OSMParser.ParsedGreen],
        to holes: inout [NormalizedHole]
    ) {
        for green in greens {
            if let refNum = green.holeNumber,
               let idx = holes.firstIndex(where: { $0.number == refNum && $0.green == nil }) {
                holes[idx].green = green.geometry
                holes[idx].rawRefs?.greenWayId = green.osmId
                continue
            }

            let greenCenter = green.geometry.centroid
            var bestIdx: Int?
            var bestDist = Double.greatestFiniteMagnitude

            for (i, hole) in holes.enumerated() {
                guard hole.green == nil else { continue }
                if let endPoint = hole.lineOfPlay?.endPoint {
                    let dist = greenCenter.distance(to: endPoint)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
            }

            if let idx = bestIdx, bestDist < 500 {
                holes[idx].green = green.geometry
                holes[idx].rawRefs?.greenWayId = green.osmId
            }
        }
    }

    // MARK: - Tee Association

    private static func associateTees(
        _ tees: [OSMParser.ParsedTee],
        to holes: inout [NormalizedHole]
    ) {
        for tee in tees {
            if let refNum = tee.holeNumber,
               let idx = holes.firstIndex(where: { $0.number == refNum }) {
                holes[idx].teeAreas.append(tee.geometry)
                holes[idx].rawRefs?.teeIds.append(tee.osmId)
                continue
            }

            let teeCenter = tee.geometry.centroid
            var bestIdx: Int?
            var bestDist = Double.greatestFiniteMagnitude

            for (i, hole) in holes.enumerated() {
                if let startPoint = hole.lineOfPlay?.startPoint {
                    let dist = teeCenter.distance(to: startPoint)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
            }

            if let idx = bestIdx, bestDist < 300 {
                holes[idx].teeAreas.append(tee.geometry)
                holes[idx].rawRefs?.teeIds.append(tee.osmId)
            }
        }
    }

    // MARK: - Pin Association

    private static func associatePins(
        _ pins: [OSMParser.ParsedPin],
        to holes: inout [NormalizedHole]
    ) {
        for pin in pins {
            if let refNum = pin.holeNumber,
               let idx = holes.firstIndex(where: { $0.number == refNum }) {
                holes[idx].pin = pin.location
                continue
            }

            var bestIdx: Int?
            var bestDist = Double.greatestFiniteMagnitude

            for (i, hole) in holes.enumerated() {
                guard hole.pin == nil else { continue }
                if let green = hole.green {
                    let dist = pin.location.distance(to: green.centroid)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
            }

            if let idx = bestIdx, bestDist < 100 {
                holes[idx].pin = pin.location
            }
        }
    }

    // MARK: - Bunker Association

    private static func associateBunkers(
        _ bunkers: [OSMParser.ParsedBunker],
        to holes: inout [NormalizedHole],
        maxDistanceMeters: Double
    ) {
        for bunker in bunkers {
            let bunkerCenter = bunker.geometry.centroid
            var bestIdx: Int?
            var bestDist = Double.greatestFiniteMagnitude

            for (i, hole) in holes.enumerated() {
                let dist = distanceToHoleCorridor(point: bunkerCenter, hole: hole)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = i
                }
            }

            if let idx = bestIdx, bestDist < maxDistanceMeters {
                holes[idx].bunkers.append(bunker.geometry)
            }
        }
    }

    // MARK: - Water Association

    private static func associateWater(
        _ water: [OSMParser.ParsedWater],
        to holes: inout [NormalizedHole],
        maxDistanceMeters: Double
    ) {
        for feature in water {
            let waterCenter = feature.geometry.centroid
            for i in holes.indices {
                let dist = distanceToHoleCorridor(point: waterCenter, hole: holes[i])
                if dist < maxDistanceMeters {
                    holes[i].water.append(feature.geometry)
                }
            }
        }
    }

    // MARK: - Confidence Scoring

    private static func computeConfidence(for hole: NormalizedHole) -> HoleConfidenceBreakdown {
        let holePath: Double = hole.lineOfPlay != nil ? 1.0 : 0.0
        let green: Double = hole.green != nil ? 1.0 : 0.0
        let tee: Double = hole.teeAreas.isEmpty ? 0.0 : 1.0
        let holeNumber: Double = hole.par != nil ? 1.0 : 0.5
        let hazards: Double = (!hole.bunkers.isEmpty || !hole.water.isEmpty) ? 1.0 : 0.3
        let geometryConsistency = validateGeometryConsistency(hole)

        return HoleConfidenceBreakdown(
            holePath: holePath,
            green: green,
            tee: tee,
            holeNumber: holeNumber,
            hazards: hazards,
            geometryConsistency: geometryConsistency
        )
    }

    private static func validateGeometryConsistency(_ hole: NormalizedHole) -> Double {
        guard let line = hole.lineOfPlay else { return 0.0 }
        var score = 0.5

        if let green = hole.green, let endPoint = line.endPoint {
            let dist = green.centroid.distance(to: endPoint)
            if dist < 100 { score += 0.25 }
        }

        if let tee = hole.teeAreas.first, let startPoint = line.startPoint {
            let dist = tee.centroid.distance(to: startPoint)
            if dist < 100 { score += 0.25 }
        }

        return min(score, 1.0)
    }

    // MARK: - Geometry Helpers

    private static func distanceToHoleCorridor(point: GeoJSONPoint, hole: NormalizedHole) -> Double {
        var minDist = Double.greatestFiniteMagnitude

        if let line = hole.lineOfPlay {
            for linePoint in line.points {
                let dist = point.distance(to: linePoint)
                minDist = min(minDist, dist)
            }
        }

        if let green = hole.green {
            let dist = point.distance(to: green.centroid)
            minDist = min(minDist, dist)
        }

        return minDist
    }

    private static func computeCourseCentroid(
        holes: [NormalizedHole],
        boundary: GeoJSONPolygon?
    ) -> GeoJSONPoint {
        if let boundary {
            return boundary.centroid
        }

        var allPoints: [GeoJSONPoint] = []
        for hole in holes {
            if let line = hole.lineOfPlay {
                allPoints.append(contentsOf: line.points)
            }
            if let green = hole.green {
                allPoints.append(green.centroid)
            }
        }

        guard !allPoints.isEmpty else {
            return GeoJSONPoint(latitude: 0, longitude: 0)
        }

        let avgLat = allPoints.map(\.latitude).reduce(0, +) / Double(allPoints.count)
        let avgLon = allPoints.map(\.longitude).reduce(0, +) / Double(allPoints.count)
        return GeoJSONPoint(latitude: avgLat, longitude: avgLon)
    }

    private static func computeCourseBBox(
        holes: [NormalizedHole],
        boundary: GeoJSONPolygon?
    ) -> CourseBoundingBox {
        var allPoints: [GeoJSONPoint] = []

        if let boundary {
            allPoints.append(contentsOf: boundary.outerRing)
        }

        for hole in holes {
            if let line = hole.lineOfPlay {
                allPoints.append(contentsOf: line.points)
            }
            if let green = hole.green {
                allPoints.append(contentsOf: green.outerRing)
            }
        }

        guard !allPoints.isEmpty else {
            return CourseBoundingBox(south: 0, west: 0, north: 0, east: 0)
        }

        let lats = allPoints.map(\.latitude)
        let lons = allPoints.map(\.longitude)

        return CourseBoundingBox(
            south: lats.min()!,
            west: lons.min()!,
            north: lats.max()!,
            east: lons.max()!
        )
    }
}
