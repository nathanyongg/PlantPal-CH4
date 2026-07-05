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

    /// The single issue to build the explanation around when multiple
    /// readings are flagged at once. Decided here, deterministically —
    /// picking "the most important one" by free-form reasoning is
    /// exactly where the Foundation Model tended to get confused and
    /// invert the fix, so the app decides and the model just phrases it.
    var primaryIssue: SensorStatus? {
        let issues = statuses.filter { $0.level != .healthy }
        guard !issues.isEmpty else { return nil }

        let priorityOrder = ["Soil moisture", "Temperature", "Humidity", "Light"]
        return issues.sorted { lhs, rhs in
            if lhs.level != rhs.level { return lhs.level > rhs.level }
            let lhsPriority = priorityOrder.firstIndex(of: lhs.name) ?? .max
            let rhsPriority = priorityOrder.firstIndex(of: rhs.name) ?? .max
            return lhsPriority < rhsPriority
        }.first
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
