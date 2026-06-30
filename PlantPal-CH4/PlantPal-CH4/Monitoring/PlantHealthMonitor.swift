import Foundation
import UserNotifications
import BackgroundTasks

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthMonitor
//
// Orchestrator. Previously triggered by a BLE read completing —
// now triggered by a scheduled pull from PlantDataService.
// Everything downstream of "I have a SensorReading" is unchanged.
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantHealthMonitor {

    static let shared = PlantHealthMonitor()

    private let dataService = PlantDataService()
    private let detector    = PlantHealthDetector()
    private let explainer   = PlantExplainer()

    private var lastProcessedTimestamp: Date?

    // Called by BGAppRefreshTask, or manually on pull-to-refresh
    func checkPlantHealth() async {
        let reading: SensorReading
        do {
            reading = try await dataService.fetchLatestReading()
        } catch {
            // ESP32 hasn't reported in — could be offline, WiFi down,
            // or dead battery. Worth surfacing after enough silence.
            await handleStaleData(error: error)
            return
        }

        // Skip if we've already processed this exact reading
        guard reading.timestamp != lastProcessedTimestamp else { return }
        lastProcessedTimestamp = reading.timestamp

        guard reading.isValid else {
            // Sensor glitch — log it but don't alert or run the FM on garbage data
            print("Discarded invalid reading at \(reading.formattedTimestamp)")
            return
        }

        let statuses = detector.assess(reading)
        let detection = DetectionResult(timestamp: reading.timestamp, statuses: statuses)

        if detection.isHealthy {
            CSVLogger.log(reading: reading, detection: detection)
            return
        }

        await handleUnhealthy(reading: reading, detection: detection)
    }

    // MARK: — Unhealthy path

    private func handleUnhealthy(reading: SensorReading, detection: DetectionResult) async {
        guard PlantExplainer.isAvailable() else {
            await notifyFallback(detection: detection)
            CSVLogger.log(reading: reading, detection: detection)
            return
        }

        do {
            let explanation = try await explainer.explain(reading: reading, detection: detection)
            await notify(detection: detection, explanation: explanation)
            CSVLogger.log(reading: reading, detection: detection, cause: explanation.cause)
        } catch {
            await notifyFallback(detection: detection)
            CSVLogger.log(reading: reading, detection: detection)
        }
    }

    // MARK: — Stale data handling
    //
    // If the ESP32 hasn't reported in a while, the WiFi connection
    // or device itself may have failed — that's worth telling the
    // user about too, separate from a plant health issue.

    private var lastFetchFailureNotified: Date?

    private func handleStaleData(error: Error) async {
        // Don't spam — only notify about connectivity once every 6 hours
        if let last = lastFetchFailureNotified, Date().timeIntervalSince(last) < 6 * 3600 {
            return
        }
        lastFetchFailureNotified = Date()

        let content = UNMutableNotificationContent()
        content.title = "Can't reach your plant sensor"
        content.body = error.localizedDescription
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: — Notifications

    private func notify(detection: DetectionResult, explanation: PlantExplanation) async {
        let content = UNMutableNotificationContent()
        content.title = explanation.notificationTitle
        content.body = explanation.notificationBody
        content.sound = explanation.isCritical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func notifyFallback(detection: DetectionResult) async {
        let content = UNMutableNotificationContent()
        content.title = detection.overallLevel == .critical
            ? "Your plant needs help now"
            : "Plant check-in"
        content.body = detection.issuesSummary.replacingOccurrences(of: "- ", with: "")
        content.sound = detection.overallLevel == .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Background Task Registration
//
// BGAppRefreshTask is opportunistic — iOS decides when to actually
// run it based on usage patterns, NOT a strict 15-minute clock.
// For real-time alerting, pair this with server-side push (see note
// in the Networking layer) rather than relying on this alone.
// ══════════════════════════════════════════════════════════════

// In your App struct or AppDelegate:
//
// func application(_ application: UIApplication,
//                  didFinishLaunchingWithOptions...) -> Bool {
//
//     CSVLogger.setup()
//
//     BGTaskScheduler.shared.register(
//         forTaskWithIdentifier: "com.yourapp.plantcheck",
//         using: nil
//     ) { task in
//         Task {
//             await PlantHealthMonitor.shared.checkPlantHealth()
//             task.setTaskCompleted(success: true)
//             scheduleNextPlantCheck()
//         }
//     }
//     scheduleNextPlantCheck()
//     return true
// }
//
// func scheduleNextPlantCheck() {
//     let request = BGAppRefreshTaskRequest(identifier: "com.yourapp.plantcheck")
//     request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
//     try? BGTaskScheduler.shared.submit(request)
// }