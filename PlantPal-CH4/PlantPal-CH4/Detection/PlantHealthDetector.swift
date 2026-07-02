import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — PlantClassifier protocol
// ══════════════════════════════════════════════════════════════

protocol PlantClassifier: Sendable {
    func assess(_ reading: SensorReading, for profile: PlantProfile) -> [SensorStatus]
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthDetector
//
// Now reads thresholds from PlantProfile (which came from Gemini)
// instead of hardcoded values. Every plant gets its own species-
// specific ranges — a cactus and a fern are assessed differently.
// ══════════════════════════════════════════════════════════════

struct PlantHealthDetector: PlantClassifier, Sendable {

    func assess(_ reading: SensorReading, for profile: PlantProfile) -> [SensorStatus] {
        [
            assessSoilMoisture(reading.soilMoisture, profile: profile),
            assessTemperature(reading.temperature,   profile: profile),
            assessHumidity(reading.humidity,         profile: profile),
            assessLight(reading.lightIntensity,      profile: profile),
        ]
    }

    // MARK: — Soil moisture

    private func assessSoilMoisture(_ value: Double, profile: PlantProfile) -> SensorStatus {
        let level: AlertLevel
        let reason: String
        let warningBuffer = 10.0   // flag warning 10% before hitting the hard limit

        if value < profile.minSoilMoisturePercent - warningBuffer {
            level = .critical
            reason = "critically dry — below \(Int(profile.minSoilMoisturePercent))% minimum for \(profile.name)"
        } else if value < profile.minSoilMoisturePercent {
            level = .warning
            reason = "low — approaching dry threshold for \(profile.name)"
        } else if value > profile.maxSoilMoisturePercent + warningBuffer {
            level = .warning
            reason = "waterlogged — above \(Int(profile.maxSoilMoisturePercent))% maximum, risk of root rot"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minSoilMoisturePercent))–\(Int(profile.maxSoilMoisturePercent))%)"
        }

        return SensorStatus(name: "Soil moisture", value: value, unit: "%", level: level, reason: reason)
    }

    // MARK: — Temperature

    private func assessTemperature(_ value: Double, profile: PlantProfile) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value > profile.maxTemperatureC + 5 {
            level = .critical
            reason = "dangerously hot — above \(Int(profile.maxTemperatureC + 5))°C for \(profile.name)"
        } else if value > profile.maxTemperatureC {
            level = .warning
            reason = "warm — above ideal \(Int(profile.maxTemperatureC))°C maximum"
        } else if value < profile.minTemperatureC - 3 {
            level = .critical
            reason = "too cold — below \(Int(profile.minTemperatureC - 3))°C causes chill stress"
        } else if value < profile.minTemperatureC {
            level = .warning
            reason = "cool — below ideal \(Int(profile.minTemperatureC))°C minimum"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minTemperatureC))–\(Int(profile.maxTemperatureC))°C)"
        }

        return SensorStatus(name: "Temperature", value: value, unit: "°C", level: level, reason: reason)
    }

    // MARK: — Humidity

    private func assessHumidity(_ value: Double, profile: PlantProfile) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value < profile.minHumidityPercent {
            level = .warning
            reason = "dry air — below \(Int(profile.minHumidityPercent))% minimum for \(profile.name)"
        } else if value > profile.maxHumidityPercent {
            level = .warning
            reason = "too humid — above \(Int(profile.maxHumidityPercent))%, risk of fungal growth"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minHumidityPercent))–\(Int(profile.maxHumidityPercent))%)"
        }

        return SensorStatus(name: "Humidity", value: value, unit: "%", level: level, reason: reason)
    }

    // MARK: — Light

    private func assessLight(_ value: Double, profile: PlantProfile) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value < profile.minLightLux {
            level = .warning
            reason = "too dim — below \(Int(profile.minLightLux)) lux minimum for \(profile.name)"
        } else if value > profile.maxLightLux {
            level = .warning
            reason = "too bright — above \(Int(profile.maxLightLux)) lux, risk of leaf scorch"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minLightLux))–\(Int(profile.maxLightLux)) lux)"
        }

        return SensorStatus(name: "Light", value: value, unit: " lux", level: level, reason: reason)
    }
}
