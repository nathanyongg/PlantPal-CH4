//
//  PlantProfile.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 01/07/26.
//


import Foundation
import SwiftData

// ══════════════════════════════════════════════════════════════
// MARK: — PlantProfile
//
// One record per plant the user adds. Thresholds are fetched
// once from Gemini on setup and persisted here — the detector
// reads them at runtime without hitting the network again.
// ══════════════════════════════════════════════════════════════

@Model
final class PlantProfile {

    // User-supplied
    var name: String             // e.g. "Monstera deliciosa"
    var nickname: String         // e.g. "My living room plant"
    var addedAt: Date

    // Gemini-fetched thresholds — stored so runtime is offline
    var minTemperature: Double   // °C
    var maxTemperature: Double
    var minHumidity: Double      // %
    var maxHumidity: Double
    var minSoilMoisture: Double  // %
    var maxSoilMoisture: Double
    var minLight: Double         // lux
    var maxLight: Double

    // Last known sensor reading — used for dashboard display
    var lastReadingAt: Date?
    var lastStatus: String       // "healthy" | "warning" | "critical"

    init(
        name: String,
        nickname: String,
        thresholds: PlantThresholds
    ) {
        self.name         = name
        self.nickname     = nickname
        self.addedAt      = Date()
        self.lastStatus   = "healthy"

        self.minTemperature  = thresholds.minTemperature
        self.maxTemperature  = thresholds.maxTemperature
        self.minHumidity     = thresholds.minHumidity
        self.maxHumidity     = thresholds.maxHumidity
        self.minSoilMoisture = thresholds.minSoilMoisture
        self.maxSoilMoisture = thresholds.maxSoilMoisture
        self.minLight        = thresholds.minLight
        self.maxLight        = thresholds.maxLight
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantThresholds
//
// Intermediate struct used during setup — Gemini returns this,
// then it gets persisted into PlantProfile. Not a SwiftData
// model itself since it's transient.
// ══════════════════════════════════════════════════════════════

struct PlantThresholds: Codable {
    var minTemperature: Double
    var maxTemperature: Double
    var minHumidity: Double
    var maxHumidity: Double
    var minSoilMoisture: Double
    var maxSoilMoisture: Double
    var minLight: Double
    var maxLight: Double
}

// ══════════════════════════════════════════════════════════════
// MARK: — Convenience
// ══════════════════════════════════════════════════════════════

extension PlantProfile {

    var alertLevel: AlertLevel {
        switch lastStatus {
        case "critical": return .critical
        case "warning":  return .warning
        default:         return .healthy
        }
    }

    func thresholds() -> PlantThresholds {
        PlantThresholds(
            minTemperature:  minTemperature,
            maxTemperature:  maxTemperature,
            minHumidity:     minHumidity,
            maxHumidity:     maxHumidity,
            minSoilMoisture: minSoilMoisture,
            maxSoilMoisture: maxSoilMoisture,
            minLight:        minLight,
            maxLight:        maxLight
        )
    }
}