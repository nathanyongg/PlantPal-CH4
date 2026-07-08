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

    // The one IoT sensor dedicated to this plant — each plant needs its
    // own paired device, so this is what Add Plant enforces before the
    // rest of the form can be filled in.
    var linkedDeviceID: String?
    var linkedDeviceName: String?
    var sensorBaseURL: String?

    // Gemini-fetched thresholds — stored so runtime is offline
    var minTemperatureC: Double   // °C
    var maxTemperatureC: Double
    var minHumidityPercent: Double      // %
    var maxHumidityPercent: Double
    var minSoilMoisturePercent: Double  // %
    var maxSoilMoisturePercent: Double
    var minLightLux: Double         // Stored as light % for new plants; legacy rows may contain lux.
    var maxLightLux: Double

    // Last known sensor reading — used for dashboard display.
    // All nil until the user's first "Check conditions" tap.
    var lastReadingAt: Date?
    var lastStatus: String       // "healthy" | "warning" | "critical"
    var lastTemperatureC: Double?
    var lastHumidityPercent: Double?
    var lastSoilMoisturePercent: Double?
    var lastLightLux: Double?

    @Attribute(.externalStorage)
    var imageData: Data?

    init(
        name: String,
        nickname: String,
        thresholds: PlantThresholds,
        imageData: Data? = nil,
        linkedDeviceID: String? = nil,
        linkedDeviceName: String? = nil,
        sensorBaseURL: String? = nil
    ) {
        self.name         = name
        self.nickname     = nickname
        self.addedAt      = Date()
        self.lastStatus   = "healthy"
        self.linkedDeviceID   = linkedDeviceID
        self.linkedDeviceName = linkedDeviceName
        self.sensorBaseURL    = sensorBaseURL

        self.minTemperatureC  = thresholds.minTemperatureC
        self.maxTemperatureC  = thresholds.maxTemperatureC
        self.minHumidityPercent     = thresholds.minHumidityPercent
        self.maxHumidityPercent     = thresholds.maxHumidityPercent
        self.minSoilMoisturePercent = thresholds.minSoilMoisturePercent
        self.maxSoilMoisturePercent = thresholds.maxSoilMoisturePercent
        self.minLightLux        = thresholds.minLightLux
        self.maxLightLux      = thresholds.maxLightLux
        self.imageData = imageData
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantThresholds
//
// Intermediate struct used during setup — Gemini returns this,
// then it gets persisted into PlantProfile. Not a SwiftData
// model itself since it's transient.
// ══════════════════════════════════════════════════════════════

nonisolated struct PlantThresholds: Codable {
    let minTemperatureC: Double
    let maxTemperatureC: Double

    let minHumidityPercent: Double
    let maxHumidityPercent: Double

    let minSoilMoisturePercent: Double
    let maxSoilMoisturePercent: Double

    let minLightLux: Double
    let maxLightLux: Double
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

    var hasBeenChecked: Bool { lastReadingAt != nil }

    func thresholds() -> PlantThresholds {
        PlantThresholds(
            minTemperatureC:  minTemperatureC,
            maxTemperatureC:  maxTemperatureC,
            minHumidityPercent:     minHumidityPercent,
            maxHumidityPercent:     maxHumidityPercent,
            minSoilMoisturePercent: minSoilMoisturePercent,
            maxSoilMoisturePercent: maxSoilMoisturePercent,
            minLightLux:        minLightLux,
            maxLightLux:        maxLightLux
        )
    }
}

extension PlantThresholds {
    var lightPercentRange: ClosedRange<Double> {
        let lower = minLightLux
        let upper = maxLightLux

        guard (0...100).contains(lower), (0...100).contains(upper), lower <= upper else {
            return 40...80
        }

        return lower...upper
    }
}
