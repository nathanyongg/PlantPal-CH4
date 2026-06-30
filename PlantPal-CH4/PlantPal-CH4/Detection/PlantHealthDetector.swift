import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — PlantClassifier protocol
//
// Both PlantHealthDetector (rule-based, today) and CoreMLClassifier
// (trained model, later) conform to this. PlantHealthMonitor only
// ever talks to this protocol — swapping detectors later means
// changing one line of dependency injection, nothing else.
// ══════════════════════════════════════════════════════════════

protocol PlantClassifier: Sendable {
    func assess(_ reading: SensorReading) -> [SensorStatus]
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthDetector
//
// Rule-based classifier. Thresholds come from general houseplant
// agronomy plus the Decision Tree splits found when analyzing the
// training dataset (Soil_Moisture <= 70.68, Temp <= 28.47).
//
// Replace with CoreMLClassifier once you have real labelled data
// from your own plant — see Detection/CoreMLClassifier.swift.
// ══════════════════════════════════════════════════════════════

struct PlantHealthDetector: PlantClassifier, Sendable {

    func assess(_ reading: SensorReading) -> [SensorStatus] {
        [
            assessSoilMoisture(reading.soilMoisture),
            assessTemperature(reading.temperature),
            assessHumidity(reading.humidity),
            assessLight(reading.lightIntensity),
        ]
    }

    // MARK: — Soil moisture (highest feature importance: 0.275)

    private func assessSoilMoisture(_ value: Double) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value < 20 {
            level = .critical
            reason = "critically dry — below 20%, roots are water stressed"
        } else if value < 30 {
            level = .warning
            reason = "low — below 30%, approaching dry threshold"
        } else if value > 80 {
            level = .warning
            reason = "waterlogged — above 80%, risk of root rot"
        } else {
            level = .healthy
            reason = "within range"
        }

        return SensorStatus(name: "Soil moisture", value: value, unit: "%", level: level, reason: reason)
    }

    // MARK: — Temperature (Decision Tree split at 28.47°C)

    private func assessTemperature(_ value: Double) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value > 35 {
            level = .critical
            reason = "dangerously hot — above 35°C causes leaf damage"
        } else if value > 30 {
            level = .warning
            reason = "warm — above 30°C increases water demand"
        } else if value < 15 {
            level = .critical
            reason = "too cold — below 15°C causes chill stress"
        } else {
            level = .healthy
            reason = "within range"
        }

        return SensorStatus(name: "Temperature", value: value, unit: "°C", level: level, reason: reason)
    }

    // MARK: — Humidity

    private func assessHumidity(_ value: Double) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value < 35 {
            level = .warning
            reason = "dry air — below 35% causes leaf tip browning"
        } else if value > 85 {
            level = .warning
            reason = "very humid — above 85% promotes fungal growth"
        } else {
            level = .healthy
            reason = "within range"
        }

        return SensorStatus(name: "Humidity", value: value, unit: "%", level: level, reason: reason)
    }

    // MARK: — Light intensity (Decision Tree splits near 13,714 / 14,758 lux)

    private func assessLight(_ value: Double) -> SensorStatus {
        let level: AlertLevel
        let reason: String

        if value < 8_000 {
            level = .warning
            reason = "too dim — below 8,000 lux slows photosynthesis"
        } else if value > 28_000 {
            level = .warning
            reason = "too bright — above 28,000 lux risks leaf scorch"
        } else {
            level = .healthy
            reason = "within range"
        }

        return SensorStatus(name: "Light", value: value, unit: " lux", level: level, reason: reason)
    }
}
