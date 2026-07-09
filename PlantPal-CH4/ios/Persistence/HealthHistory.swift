//
//  HealthHistory.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 30/06/26.
//

import Foundation
import SwiftData
internal import Combine

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthLogEntry
//
// One IoT sensor serves every plant, so a reading only means
// something once the user has physically moved it next to a
// plant and opened that plant's detail screen. Each such check-in
// is recorded here — this is the "today's log" of what got
// checked and when, not a continuous background feed.
// ══════════════════════════════════════════════════════════════

@Model
final class PlantHealthLogEntry {

    var timestamp: Date

    var temperature: Double
    var humidity: Double
    var soilMoisture: Double
    var lightIntensity: Double

    var status: String  // "healthy" | "warning" | "critical"

    var plant: PlantProfile?

    init(
        timestamp: Date,
        reading: SensorReading,
        status: String,
        plant: PlantProfile?
    ) {
        self.timestamp = timestamp
        self.temperature = reading.temperature
        self.humidity = reading.humidity
        self.soilMoisture = reading.soilMoisture
        self.lightIntensity = reading.lightIntensity
        self.status = status
        self.plant = plant
    }
}

extension PlantHealthLogEntry {

    var alertLevel: AlertLevel {
        switch status {
        case "critical": return .critical
        case "warning":  return .warning
        default:         return .healthy
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}
