//
//  Secrets.swift
//  CaddieAI
//
//  Reads API tokens from Info.plist.
//

import Foundation

enum Secrets {
    /// Mapbox public access token from Info.plist
    static var mapboxAccessToken: String? {
        Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String
    }
}
