import Foundation
import UserNotifications
import BackgroundTasks
import SwiftData

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthMonitor
//
// Orchestrator. Pulls the latest sensor reading from the cloud,
// checks it against PlantProfile thresholds (Gemini-fetched,
// persisted in SwiftData), and either stays silent (healthy)
// or invokes the Foundation Model for an explanation and fires
// a push notification (warning / critical).
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantHealthMonitor {

    static let shared = PlantHealthMonitor()

    private let dataService = PlantDataService()
    private let detector    = PlantHealthDetector()
    private let explainer   = PlantExplainer()

    private var lastProcessedTimestamp: Date?

    // Called per plant by BGAppRefreshTask or manually from the dashboard.
    // The caller loops over all PlantProfiles from SwiftData.
    func checkPlantHealth(for profile: PlantProfile) async {
        let reading: SensorReading
        do {
            reading = try await dataService.fetchLatestReading()
        } catch {
            await handleStaleData(error: error)
            return
        }

        guard reading.timestamp != lastProcessedTimestamp else { return }
        lastProcessedTimestamp = reading.timestamp

        guard reading.isValid else {
            print("Discarded invalid reading at \(reading.formattedTimestamp)")
            return
        }

        let statuses  = detector.assess(reading, for: profile)
        let detection = DetectionResult(timestamp: reading.timestamp, statuses: statuses)

        // Persist latest status into SwiftData so DashboardView updates
        profile.lastReadingAt = reading.timestamp
        profile.lastStatus    = detection.overallLevel == .critical ? "critical"
                              : detection.overallLevel == .warning  ? "warning"
                              : "healthy"

        // Healthy — nothing to do, SwiftData already updated above
        guard !detection.isHealthy else { return }

        await handleUnhealthy(reading: reading, detection: detection)
    }

    // MARK: — Unhealthy path

    private func handleUnhealthy(reading: SensorReading, detection: DetectionResult) async {
        guard PlantExplainer.isAvailable() else {
            await notifyFallback(detection: detection)
            return
        }

        do {
            let explanation = try await explainer.explain(reading: reading, detection: detection)
            await notify(detection: detection, explanation: explanation)
        } catch {
            await notifyFallback(detection: detection)
        }
    }

    // MARK: — Stale data handling
    //
    // If the ESP32 hasn't reported in a while (WiFi down, dead battery)
    // notify the user — separately from a plant health issue.

    private var lastFetchFailureNotified: Date?

    private func handleStaleData(error: Error) async {
        if let last = lastFetchFailureNotified,
           Date().timeIntervalSince(last) < 6 * 3600 { return }
        lastFetchFailureNotified = Date()

        let content       = UNMutableNotificationContent()
        content.title     = "Can't reach your plant sensor"
        content.body      = error.localizedDescription
        content.sound     = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: — Notifications

    private func notify(detection: DetectionResult, explanation: PlantExplanation) async {
        let content       = UNMutableNotificationContent()
        content.title     = explanation.notificationTitle
        content.body      = explanation.notificationBody
        content.sound     = explanation.isCritical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func notifyFallback(detection: DetectionResult) async {
        let content       = UNMutableNotificationContent()
        content.title     = detection.overallLevel == .critical
                            ? "Your plant needs help now"
                            : "Plant check-in"
        content.body      = detection.issuesSummary
            .replacingOccurrences(of: "- ", with: "")
        content.sound     = detection.overallLevel == .critical
                            ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
