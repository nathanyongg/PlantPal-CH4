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
    let reason: String   // human-readable, fed into the FM prompt

    var formattedValue: String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))\(unit)"
    }
}
