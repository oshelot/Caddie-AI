//
//  HoleAnalysisEngine.swift
//  CaddieAI
//
//  Deterministic geometry analysis for golf holes.
//  Computes distances, detects doglegs, positions hazards,
//  and generates a plain-text strategic summary.
//

import Foundation

enum HoleAnalysisEngine {

    private static let metersToYards = 1.09361

    // MARK: - Main Analysis

    static func analyze(
        hole: NormalizedHole,
        course: NormalizedCourse,
        profile: PlayerProfile?,
        weatherContext: HoleWeatherContext? = nil
    ) -> HoleAnalysis {
        let totalDistMeters = hole.lineOfPlay?.totalDistance() ?? 0
        let totalDistYards = totalDistMeters > 0 ? Int(totalDistMeters * metersToYards) : nil

        let dogleg = detectDogleg(lineOfPlay: hole.lineOfPlay)
        let fairwayWidth = estimateFairwayWidth(hole: hole)
        let greenDims = measureGreen(hole: hole)
        let hazards = classifyHazards(hole: hole)

        let summary = buildSummary(
            hole: hole,
            totalDistYards: totalDistYards,
            dogleg: dogleg,
            fairwayWidthYards: fairwayWidth,
            greenDims: greenDims,
            hazards: hazards,
            profile: profile,
            weatherContext: weatherContext
        )

        return HoleAnalysis(
            holeNumber: hole.number,
            par: hole.par,
            totalDistanceYards: totalDistYards,
            yardagesByTee: hole.yardages,
            dogleg: dogleg,
            fairwayWidthAtLandingYards: fairwayWidth,
            greenDepthYards: greenDims?.depth,
            greenWidthYards: greenDims?.width,
            hazards: hazards,
            weather: weatherContext,
            strategicAdvice: nil,
            deterministicSummary: summary
        )
    }

    // MARK: - Weather Context for Hole

    /// Computes hole-specific weather context from raw weather data and hole geometry
    static func buildWeatherContext(
        weather: WeatherData,
        hole: NormalizedHole
    ) -> HoleWeatherContext? {
        guard let line = hole.lineOfPlay,
              let start = line.startPoint,
              let end = line.endPoint else {
            return nil
        }

        let holeBearing = start.bearing(to: end)
        let relativeWind = weather.relativeWindDirection(holeBearingDegrees: holeBearing)
        let cardinal = WeatherData.cardinalDirection(from: weather.windDirectionDegrees)

        return HoleWeatherContext(
            temperatureF: Int(weather.temperatureF),
            windSpeedMph: Int(weather.windSpeedMph),
            windCompassDirection: cardinal,
            windRelativeToHole: relativeWind,
            windStrength: weather.windStrength,
            conditionDescription: weather.conditionDescription,
            holeBearingDegrees: holeBearing
        )
    }

    // MARK: - Dogleg Detection

    /// Walks the line of play and detects significant bearing changes
    private static func detectDogleg(lineOfPlay: GeoJSONLineString?) -> DoglegInfo? {
        guard let line = lineOfPlay else { return nil }
        let pts = line.points
        guard pts.count >= 3 else { return nil }

        // Compute bearing for each segment
        var segments: [(bearing: Double, length: Double)] = []
        for i in 1..<pts.count {
            let bearing = pts[i - 1].bearing(to: pts[i])
            let length = pts[i - 1].distance(to: pts[i])
            segments.append((bearing, length))
        }

        // Find the largest single bearing change between consecutive segments
        var maxChange = 0.0
        var maxChangeIndex = 0
        for i in 1..<segments.count {
            var change = segments[i].bearing - segments[i - 1].bearing
            // Normalize to -180...180
            if change > 180 { change -= 360 }
            if change < -180 { change += 360 }
            if abs(change) > abs(maxChange) {
                maxChange = change
                maxChangeIndex = i
            }
        }

        // Need at least 15 degrees to count as a dogleg
        guard abs(maxChange) >= 15 else { return nil }

        // Distance from tee to the bend point
        var distToBend = 0.0
        for i in 0..<maxChangeIndex {
            distToBend += segments[i].length
        }

        let direction: DoglegDirection = maxChange > 0 ? .right : .left

        return DoglegInfo(
            direction: direction,
            distanceFromTeeYards: Int(distToBend * metersToYards),
            bendAngleDegrees: abs(maxChange)
        )
    }

    // MARK: - Fairway Width Estimation

    /// Estimates fairway width at the typical landing zone
    private static func estimateFairwayWidth(hole: NormalizedHole) -> Int? {
        guard let line = hole.lineOfPlay else { return nil }
        let totalDist = line.totalDistance()
        guard totalDist > 0 else { return nil }

        // Landing zone: ~60% of hole for par 4, ~40% for par 5, ~70% for par 3
        let landingFraction: Double
        switch hole.par {
        case 3: landingFraction = 0.70
        case 5: landingFraction = 0.40
        default: landingFraction = 0.60 // par 4 or unknown
        }

        let landingDist = totalDist * landingFraction

        // Get the point and bearing at the landing zone
        guard let landingPoint = line.pointAtDistance(landingDist),
              let bearing = line.bearingAtDistance(landingDist) else {
            return nil
        }

        // Project perpendicular points to estimate width
        let perpBearing = bearing + 90
        let sampleDist = 50.0 // 50 meters each side (generous)
        let leftPoint = projectPoint(from: landingPoint, bearing: perpBearing, distanceMeters: sampleDist)
        let rightPoint = projectPoint(from: landingPoint, bearing: perpBearing + 180, distanceMeters: sampleDist)

        // The fairway width is approximate — use the perpendicular distance
        // Since we don't have actual fairway polygon boundaries, we use hole geometry
        // as a rough proxy. A typical fairway is 25-45 yards wide.
        let widthMeters = leftPoint.distance(to: rightPoint)
        let widthYards = Int(widthMeters * metersToYards)

        // Clamp to reasonable fairway widths
        return min(widthYards, 60)
    }

    /// Projects a point from an origin along a bearing at a given distance
    private static func projectPoint(
        from origin: GeoJSONPoint,
        bearing: Double,
        distanceMeters: Double
    ) -> GeoJSONPoint {
        let R = 6371000.0
        let bearingRad = bearing * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let d = distanceMeters / R

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(bearingRad))
        let lon2 = lon1 + atan2(
            sin(bearingRad) * sin(d) * cos(lat1),
            cos(d) - sin(lat1) * sin(lat2)
        )

        return GeoJSONPoint(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    // MARK: - Green Measurement

    struct GreenDimensions {
        var depth: Int  // yards, front-to-back along play direction
        var width: Int  // yards, left-to-right perpendicular to play
    }

    private static func measureGreen(hole: NormalizedHole) -> GreenDimensions? {
        guard let green = hole.green else { return nil }
        let ring = green.outerRing
        guard ring.count >= 3 else { return nil }

        // Get the approach bearing (from last segment of line of play toward green)
        let approachBearing: Double
        if let line = hole.lineOfPlay, let endPoint = line.endPoint, line.points.count >= 2 {
            let secondLast = line.points[line.points.count - 2]
            approachBearing = secondLast.bearing(to: endPoint)
        } else {
            // Fall back to north-south
            approachBearing = 0
        }

        let perpBearing = approachBearing + 90
        let center = green.centroid

        // Project all ring points onto approach axis and perpendicular axis
        var minDepth = Double.greatestFiniteMagnitude
        var maxDepth = -Double.greatestFiniteMagnitude
        var minWidth = Double.greatestFiniteMagnitude
        var maxWidth = -Double.greatestFiniteMagnitude

        let approachRad = approachBearing * .pi / 180
        let perpRad = perpBearing * .pi / 180

        for point in ring {
            let dx = (point.longitude - center.longitude) * cos(center.latitude * .pi / 180)
            let dy = point.latitude - center.latitude

            // Project onto approach direction
            let depthProj = dx * sin(approachRad) + dy * cos(approachRad)
            let widthProj = dx * sin(perpRad) + dy * cos(perpRad)

            minDepth = min(minDepth, depthProj)
            maxDepth = max(maxDepth, depthProj)
            minWidth = min(minWidth, widthProj)
            maxWidth = max(maxWidth, widthProj)
        }

        // Convert degree differences to meters then yards
        let depthDeg = maxDepth - minDepth
        let widthDeg = maxWidth - minWidth
        // 1 degree latitude ≈ 111,139 meters
        let depthMeters = depthDeg * 111139
        let widthMeters = widthDeg * 111139

        let depthYards = max(1, Int(depthMeters * metersToYards))
        let widthYards = max(1, Int(widthMeters * metersToYards))

        return GreenDimensions(depth: depthYards, width: widthYards)
    }

    // MARK: - Hazard Classification

    private static func classifyHazards(hole: NormalizedHole) -> [HoleHazardInfo] {
        guard let line = hole.lineOfPlay else { return [] }
        let totalDist = line.totalDistance()
        guard totalDist > 0, line.points.count >= 2 else { return [] }

        var hazards: [HoleHazardInfo] = []

        let greenCenter = hole.green?.centroid
        let greensideThreshold = 27.432 // 30 yards in meters

        // Process bunkers
        for bunker in hole.bunkers {
            let info = classifySingleHazard(
                polygon: bunker,
                type: .bunker,
                line: line,
                totalDist: totalDist,
                greenCenter: greenCenter,
                greensideThreshold: greensideThreshold
            )
            hazards.append(info)
        }

        // Process water hazards
        for water in hole.water {
            let info = classifySingleHazard(
                polygon: water,
                type: .water,
                line: line,
                totalDist: totalDist,
                greenCenter: greenCenter,
                greensideThreshold: greensideThreshold
            )
            hazards.append(info)
        }

        // Sort by distance from tee
        hazards.sort { ($0.distanceFromTeeYards ?? 0) < ($1.distanceFromTeeYards ?? 0) }
        return hazards
    }

    private static func classifySingleHazard(
        polygon: GeoJSONPolygon,
        type: HazardType,
        line: GeoJSONLineString,
        totalDist: Double,
        greenCenter: GeoJSONPoint?,
        greensideThreshold: Double
    ) -> HoleHazardInfo {
        let center = polygon.centroid
        let distAlong = line.distanceAlongLine(toNearestPointFrom: center)
        let distYards = Int(distAlong * metersToYards)

        // Determine side
        let side: HazardSide
        if let gc = greenCenter, center.distance(to: gc) < greensideThreshold {
            side = .greenside
        } else if distAlong > totalDist * 0.90 {
            side = .frontOfGreen
        } else {
            // Use cross product to determine left/right
            guard let linePoint = line.pointAtDistance(distAlong) else {
                return HoleHazardInfo(
                    type: type,
                    side: .left,
                    distanceFromTeeYards: distYards,
                    description: "\(type.displayName) at \(distYards) yards"
                )
            }

            // Get line direction at this point
            let bearing = line.bearingAtDistance(distAlong) ?? 0
            let lookAhead = 10.0 // meters
            let directionPoint = projectPoint(
                from: linePoint,
                bearing: bearing,
                distanceMeters: lookAhead
            )

            let cross = crossProductSign(
                origin: linePoint,
                target: directionPoint,
                point: center
            )
            side = cross > 0 ? .left : .right
        }

        let description = buildHazardDescription(type: type, side: side, distYards: distYards)
        return HoleHazardInfo(
            type: type,
            side: side,
            distanceFromTeeYards: distYards,
            description: description
        )
    }

    private static func buildHazardDescription(
        type: HazardType,
        side: HazardSide,
        distYards: Int
    ) -> String {
        switch side {
        case .greenside:
            return "\(type.displayName) greenside"
        case .frontOfGreen:
            return "\(type.displayName) in front of green"
        case .crossing:
            return "\(type.displayName) crossing fairway at \(distYards) yards"
        default:
            return "\(type.displayName) \(side.displayName.lowercased()) at \(distYards) yards"
        }
    }

    // MARK: - Summary Builder

    private static func buildSummary(
        hole: NormalizedHole,
        totalDistYards: Int?,
        dogleg: DoglegInfo?,
        fairwayWidthYards: Int?,
        greenDims: GreenDimensions?,
        hazards: [HoleHazardInfo],
        profile: PlayerProfile?,
        weatherContext: HoleWeatherContext? = nil
    ) -> String {
        var parts: [String] = []

        // Opening: Hole description
        var opening = "Hole \(hole.number)"
        if let par = hole.par {
            opening += " is a par \(par)"
        }
        if let yardages = hole.yardages, !yardages.isEmpty {
            let yardList = yardages.sorted { $0.value > $1.value }
                .map { "\($0.value) yards (\($0.key))" }
                .joined(separator: ", ")
            opening += " playing \(yardList)"
        } else if let dist = totalDistYards {
            opening += " playing approximately \(dist) yards"
        }
        opening += "."
        parts.append(opening)

        // Dogleg info
        if let dogleg {
            parts.append("The fairway doglegs \(dogleg.direction.displayName) at about \(dogleg.distanceFromTeeYards) yards from the tee.")
        }

        // Fairway width
        if let width = fairwayWidthYards {
            let widthDesc: String
            if width < 25 { widthDesc = "narrow" }
            else if width < 35 { widthDesc = "average width" }
            else { widthDesc = "generous" }

            if let dogleg {
                parts.append("The fairway is approximately \(width) yards wide at the \(dogleg.distanceFromTeeYards)-yard mark — \(widthDesc).")
            } else {
                parts.append("The fairway is approximately \(width) yards wide at the landing zone — \(widthDesc).")
            }
        }

        // Green dimensions
        if let dims = greenDims {
            parts.append("The green is \(dims.depth) yards deep and \(dims.width) yards wide.")
        }

        // Weather conditions
        if let weather = weatherContext {
            parts.append(weather.summaryText + ".")
            if weather.windStrength != .none {
                switch weather.windRelativeToHole {
                case .into:
                    parts.append("Wind is in your face — expect reduced carry.")
                case .helping:
                    parts.append("Wind is helping — the ball will fly farther.")
                case .crossLeftToRight:
                    parts.append("Crosswind blowing left to right — allow for drift.")
                case .crossRightToLeft:
                    parts.append("Crosswind blowing right to left — allow for drift.")
                }
            }
        }

        // Hazards
        if !hazards.isEmpty {
            let hazardDescs = hazards.map { $0.description.lowercased() }
            if hazards.count == 1 {
                parts.append("Watch for \(hazardDescs[0]).")
            } else {
                let joined = hazardDescs.dropLast().joined(separator: ", ")
                parts.append("Hazards include \(joined), and \(hazardDescs.last!).")
            }
        }

        // Tee shot suggestion based on distance and profile
        if let par = hole.par, let dist = totalDistYards ?? hole.yardages?.values.max() {
            let teeShotAdvice = suggestTeeShot(
                par: par,
                distanceYards: dist,
                dogleg: dogleg,
                hazards: hazards,
                profile: profile
            )
            if !teeShotAdvice.isEmpty {
                parts.append(teeShotAdvice)
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Tee Shot Suggestion

    private static func suggestTeeShot(
        par: Int,
        distanceYards: Int,
        dogleg: DoglegInfo?,
        hazards: [HoleHazardInfo],
        profile: PlayerProfile?
    ) -> String {
        guard par >= 4 else {
            // Par 3: suggest club based on distance
            if let profile {
                if let club = suggestClub(distanceYards: distanceYards, profile: profile) {
                    return "Consider hitting \(club) to the green."
                }
            }
            return ""
        }

        var advice = ""

        // Determine if driver is appropriate
        let driverSafe: Bool
        if let dogleg, dogleg.distanceFromTeeYards < 240 {
            driverSafe = false
        } else if hazards.contains(where: { $0.distanceFromTeeYards ?? 999 < 260 && $0.type == .water }) {
            driverSafe = false
        } else {
            driverSafe = true
        }

        if driverSafe {
            advice = "Driver is a good play off the tee."
        } else if let dogleg {
            // Suggest laying up short of the dogleg
            let layupDist = dogleg.distanceFromTeeYards - 20
            if let profile, let club = suggestClub(distanceYards: layupDist, profile: profile) {
                advice = "Consider hitting \(club) to lay up short of the dogleg at \(dogleg.distanceFromTeeYards) yards."
            } else {
                advice = "Consider laying up short of the dogleg at \(dogleg.distanceFromTeeYards) yards."
            }
        }

        // Aim direction based on hazards
        let leftHazards = hazards.filter { $0.side == .left && ($0.distanceFromTeeYards ?? 999) < 280 }
        let rightHazards = hazards.filter { $0.side == .right && ($0.distanceFromTeeYards ?? 999) < 280 }

        if !leftHazards.isEmpty && rightHazards.isEmpty {
            advice += " Aim right of center to avoid the \(leftHazards[0].type.displayName.lowercased()) on the left."
        } else if !rightHazards.isEmpty && leftHazards.isEmpty {
            advice += " Aim left of center to avoid the \(rightHazards[0].type.displayName.lowercased()) on the right."
        }

        return advice
    }

    /// Suggests a club from the player's bag for a given distance
    private static func suggestClub(distanceYards: Int, profile: PlayerProfile) -> String? {
        let sorted = profile.clubDistances.sorted { $0.carryYards < $1.carryYards }
        // Find the club whose carry is closest to (but not much more than) the target
        var bestClub: ClubDistance?
        for club in sorted {
            if club.carryYards >= distanceYards - 10 {
                bestClub = club
                break
            }
        }
        return bestClub?.club.displayName ?? sorted.last?.club.displayName
    }
}
