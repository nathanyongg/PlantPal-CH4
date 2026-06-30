import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — DetectionResult
//
// The full output of one assessment cycle — all 4 SensorStatus
// values plus the derived overall level. This is what gets
// passed to PlantExplainer when something's wrong, and what
// gets logged to CSV either way.
// ══════════════════════════════════════════════════════════════

struct DetectionResult: Sendable {
    let timestamp: Date
    let statuses: [SensorStatus]

    var overallLevel: AlertLevel {
        statuses.map(\.level).max() ?? .healthy
    }

    var isHealthy: Bool { overallLevel == .healthy }

    /// Only the out-of-range sensors — this is what goes into
    /// the Foundation Model prompt as "flagged issues"
    var issuesSummary: String {
        let issues = statuses.filter { $0.level != .healthy }
        guard !issues.isEmpty else { return "None" }
        return issues
            .map { "- \($0.name): \($0.formattedValue) (\($0.reason))" }
            .joined(separator: "\n")
    }

    /// All readings regardless of status — full context for the FM
    var fullSummary: String {
        statuses
            .map { "- \($0.name): \($0.formattedValue)" }
            .joined(separator: "\n")
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — CSV row formatting
//
// Used by CSVLogger to write one line per assessment. Keeping
// this here (not in CSVLogger) means the row format stays in
// sync with whatever fields DetectionResult actually has.
// ══════════════════════════════════════════════════════════════

extension DetectionResult {

    func csvRow(reading: SensorReading, cause: String = "") -> String {
        let formatter = ISO8601DateFormatter()
        let healthStatus = isHealthy ? 1 : 0
        return [
            formatter.string(from: reading.timestamp),
            "\(reading.temperature)",
            "\(reading.humidity)",
            "\(reading.soilMoisture)",
            "\(reading.lightIntensity)",
            "\(healthStatus)",
            "\"\(cause)\"",
        ].joined(separator: ",") + "\n"
    }

    static let csvHeader = "timestamp,temperature,humidity,soil_moisture,light_intensity,health_status,fm_cause\n"
}
