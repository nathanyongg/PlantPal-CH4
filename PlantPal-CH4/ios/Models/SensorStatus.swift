import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — AlertLevel
//
// Shared across SensorStatus and DetectionResult. Order matters
// for Comparable — lets DetectionResult take the max() of all
// sensor levels to find the overall severity in one line.
// ══════════════════════════════════════════════════════════════

enum AlertLevel: Int, Comparable, Sendable {
    case healthy = 0
    case warning = 1
    case critical = 2

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — SensorDirection
//
// Which way a reading missed its healthy range. Computed once in
// PlantHealthDetector (deterministic, not left to the language
// model to infer) so the Foundation Model can't get "too little"
// and "too much" backwards — that mistake is the difference
// between "water it" and "let it dry out".
// ══════════════════════════════════════════════════════════════

enum SensorDirection: Sendable {
    case tooLow
    case tooHigh
    case none  // within range
}

// ══════════════════════════════════════════════════════════════
// MARK: — SensorStatus
//
// The detector's verdict on a single sensor reading. One of
// these is produced per sensor (temperature, humidity, soil
// moisture, light) every time `PlantHealthDetector.assess()` runs.
// ══════════════════════════════════════════════════════════════

struct SensorStatus: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let value: Double
    let unit: String
    let level: AlertLevel
    let direction: SensorDirection
    let reason: String   // human-readable, fed into the FM prompt

    var formattedValue: String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))\(unit)"
    }

    /// The correct fix, decided here in code rather than left to the
    /// language model — it only needs to phrase this warmly, never
    /// re-derive or second-guess the direction.
    var recommendedFix: String {
        switch (name, direction) {
        case ("Soil moisture", .tooLow):
            return "Water the plant soon — the soil needs more moisture."
        case ("Soil moisture", .tooHigh):
            return "Hold off watering and let the soil dry out — it's currently waterlogged."
        case ("Temperature", .tooLow):
            return "Move the plant somewhere warmer."
        case ("Temperature", .tooHigh):
            return "Move the plant somewhere cooler, out of direct heat."
        case ("Humidity", .tooLow):
            return "Increase humidity around the plant, e.g. a pebble tray or humidifier."
        case ("Humidity", .tooHigh):
            return "Improve airflow around the plant to bring humidity down."
        case ("Light", .tooLow):
            return "Move the plant to a brighter spot."
        case ("Light", .tooHigh):
            return "Move the plant out of direct or overly intense light."
        default:
            return "No action needed."
        }
    }
}
