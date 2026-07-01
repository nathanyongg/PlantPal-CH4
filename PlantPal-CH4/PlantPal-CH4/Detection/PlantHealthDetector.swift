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

        if value < profile.minSoilMoisture - warningBuffer {
            level = .critical
            reason = "critically dry — below \(Int(profile.minSoilMoisture))% minimum for \(profile.name)"
        } else if value < profile.minSoilMoisture {
            level = .warning
            reason = "low — approaching dry threshold for \(profile.name)"
        } else if value > profile.maxSoilMoisture + warningBuffer {
            level = .warning
            reason = "waterlogged — above \(Int(profile.maxSoilMoisture))% maximum, risk of root rot"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minSoilMoisture))–\(Int(profile.maxSoilMoisture))%)"
        }

        return SensorStatus(name: "Soil moisture", value: value, unit: "%", level: level, reason: reason)
    }

    // MARK: — Temperature

    private func assessTemperature(_ value: Double, profile: PlantProfile) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value > profile.maxTemperature + 5 {
            level = .critical
            reason = "dangerously hot — above \(Int(profile.maxTemperature + 5))°C for \(profile.name)"
        } else if value > profile.maxTemperature {
            level = .warning
            reason = "warm — above ideal \(Int(profile.maxTemperature))°C maximum"
        } else if value < profile.minTemperature - 3 {
            level = .critical
            reason = "too cold — below \(Int(profile.minTemperature - 3))°C causes chill stress"
        } else if value < profile.minTemperature {
            level = .warning
            reason = "cool — below ideal \(Int(profile.minTemperature))°C minimum"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minTemperature))–\(Int(profile.maxTemperature))°C)"
        }

        return SensorStatus(name: "Temperature", value: value, unit: "°C", level: level, reason: reason)
    }

    // MARK: — Humidity

    private func assessHumidity(_ value: Double, profile: PlantProfile) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value < profile.minHumidity {
            level = .warning
            reason = "dry air — below \(Int(profile.minHumidity))% minimum for \(profile.name)"
        } else if value > profile.maxHumidity {
            level = .warning
            reason = "too humid — above \(Int(profile.maxHumidity))%, risk of fungal growth"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minHumidity))–\(Int(profile.maxHumidity))%)"
        }

        return SensorStatus(name: "Humidity", value: value, unit: "%", level: level, reason: reason)
    }

    // MARK: — Light

    private func assessLight(_ value: Double, profile: PlantProfile) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value < profile.minLight {
            level = .warning
            reason = "too dim — below \(Int(profile.minLight)) lux minimum for \(profile.name)"
        } else if value > profile.maxLight {
            level = .warning
            reason = "too bright — above \(Int(profile.maxLight)) lux, risk of leaf scorch"
        } else {
            level = .healthy
            reason = "within range (\(Int(profile.minLight))–\(Int(profile.maxLight)) lux)"
        }

        return SensorStatus(name: "Light", value: value, unit: " lux", level: level, reason: reason)
    }
}
