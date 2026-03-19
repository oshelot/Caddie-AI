//
//  ShotContext.swift
//  CaddieAI
//

import Foundation

struct ShotContext: Codable, Sendable {
    var distanceYards: Int
    var shotType: ShotType
    var lieType: LieType
    var windStrength: WindStrength
    var windDirection: WindDirection
    var slope: Slope
    var aggressiveness: Aggressiveness
    var hazardNotes: String

    static var `default`: ShotContext {
        ShotContext(
            distanceYards: 150,
            shotType: .approach,
            lieType: .fairway,
            windStrength: .none,
            windDirection: .into,
            slope: .level,
            aggressiveness: .normal,
            hazardNotes: ""
        )
    }
}
