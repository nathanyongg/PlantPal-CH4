import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — CSVLogger
//
// Writes every assessment (healthy and unhealthy) to a CSV file
// in the app's documents directory. This is your future training
// dataset — once you have a few weeks of real readings from your
// actual plant, this file is what you'll run through the SMOTE /
// GridSearchCV pipeline to train a real CoreML model.
//
// Uses DetectionResult.csvRow(reading:cause:) and .csvHeader,
// defined in Models/DetectionResult.swift, so the row format
// stays in sync with whatever fields DetectionResult has.
// ══════════════════════════════════════════════════════════════

@MainActor
enum CSVLogger {

    static var logURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("plant_readings.csv")
    }

    /// Call once on app launch — creates the file with a header
    /// row if it doesn't already exist. Safe to call multiple times.
    static func setup() {
        guard !FileManager.default.fileExists(atPath: logURL.path) else { return }
        try? DetectionResult.csvHeader.write(to: logURL, atomically: true, encoding: .utf8)
    }

    /// Appends one row per assessment cycle.
    static func log(reading: SensorReading, detection: DetectionResult, cause: String = "") {
        setup()  // safety net in case setup() was never called at launch

        let row = detection.csvRow(reading: reading, cause: cause)

        guard let data = row.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            // File handle failed to open — fall back to recreating it
            try? row.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: — Reading back the log
    //
    // Useful for a "export training data" button in Settings, or
    // for a trend chart that wants more than what HealthHistory
    // keeps in memory.

    static func readAllRows() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? DetectionResult.csvHeader
    }

    static var rowCount: Int {
        let content = readAllRows()
        // Subtract 1 for header, 1 for trailing newline producing an empty last line
        let lines = content.split(separator: "\n")
        return max(0, lines.count - 1)
    }

    /// Wipes the log — useful during development/testing only.
    static func reset() {
        try? FileManager.default.removeItem(at: logURL)
        setup()
    }
}
