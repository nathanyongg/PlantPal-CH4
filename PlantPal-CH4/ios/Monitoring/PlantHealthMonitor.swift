import Foundation
import BackgroundTasks
import SwiftData

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthMonitor
//
// Orchestrator. Pulls the latest sensor reading for a plant,
// checks it against PlantProfile thresholds (Gemini-fetched,
// persisted in SwiftData), records the check-in, and either stays
// silent (healthy) or invokes the Foundation Model for an
// explanation and fires a push notification (warning / critical).
//
// Called automatically by AutoRefreshScheduler every 15 minutes,
// and reachable manually from the dashboard (pull-to-refresh,
// "Check conditions") — each plant now has its own dedicated
// sensor, so there's no physical "move it over here" step blocking
// automatic checks anymore.
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantHealthMonitor {

    static let shared = PlantHealthMonitor()

    private let detector    = PlantHealthDetector()
    private let explainer   = PlantExplainer()

    /// Requests notification permission once — safe to call repeatedly.
    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        await NotificationManager.shared.requestAuthorization()
    }

    // Called per plant, either by the 15-minute AutoRefreshScheduler or
    // manually (pull-to-refresh / "Check conditions"). `notifyIfUnhealthy`
    // is false for manual checks — the user is already looking at the
    // result on screen, so a push notification would just be noise.
    func checkPlantHealth(
        for profile: PlantProfile,
        modelContext: ModelContext,
        notifyIfUnhealthy: Bool = true
    ) async {
        let reading: SensorReading
        do {
            reading = try await PlantDataService(profile: profile).fetchLatestReading()
        } catch {
            if notifyIfUnhealthy {
                await handleStaleData(error: error)
            }
            return
        }

        guard reading.isValid else {
            print("Discarded invalid reading at \(reading.formattedTimestamp)")
            return
        }

        let statuses  = detector.assess(reading, for: profile)
        let detection = DetectionResult(timestamp: reading.timestamp, statuses: statuses)
        let status = detection.overallLevel == .critical ? "critical"
                   : detection.overallLevel == .warning  ? "warning"
                   : "healthy"

        let entry = PlantHealthLogEntry(
            timestamp: reading.timestamp,
            reading: reading,
            status: status,
            plant: profile
        )
        modelContext.insert(entry)

        profile.lastReadingAt          = reading.timestamp
        profile.lastStatus             = status
        profile.lastTemperatureC       = reading.temperature
        profile.lastHumidityPercent    = reading.humidity
        profile.lastSoilMoisturePercent = reading.soilMoisture
        profile.lastLightLux           = reading.lightIntensity

        try? modelContext.save()
        try? await FirestoreService.shared.uploadPlant(profile)
        try? await FirestoreService.shared.uploadHealthLog(entry, for: profile)

        guard !detection.isHealthy, notifyIfUnhealthy else { return }

        await handleUnhealthy(reading: reading, detection: detection, species: profile.name)
    }

    // MARK: — Unhealthy path

    private func handleUnhealthy(reading: SensorReading, detection: DetectionResult, species: String) async {
        guard PlantExplainer.isAvailable() else {
            await notifyFallback(detection: detection)
            return
        }

        do {
            let explanation = try await explainer.explain(reading: reading, detection: detection, species: species)
            await notify(detection: detection, explanation: explanation)
        } catch {
            await notifyFallback(detection: detection)
        }
    }

    // MARK: — Stale data handling
    //
    // If a plant's sensor hasn't reported in a while (WiFi down, dead
    // battery) notify the user — separately from a plant health issue.

    private var lastFetchFailureNotified: Date?

    private func handleStaleData(error: Error) async {
        if let last = lastFetchFailureNotified,
           Date().timeIntervalSince(last) < 6 * 3600 { return }
        lastFetchFailureNotified = Date()

        await NotificationManager.shared.scheduleSensorStatusAlert(
            body: error.localizedDescription
        )
    }

    // MARK: — Notifications

    private func notify(detection: DetectionResult, explanation: PlantExplanation) async {
        await NotificationManager.shared.schedulePlantHealthAlert(
            title: explanation.notificationTitle,
            body: explanation.notificationBody,
            isCritical: explanation.isCritical
        )
    }

    private func notifyFallback(detection: DetectionResult) async {
        await NotificationManager.shared.schedulePlantHealthAlert(
            title: detection.overallLevel == .critical
                ? "Your plant needs help now"
                : "Plant check-in",
            body: detection.issuesSummary.replacingOccurrences(of: "- ", with: ""),
            isCritical: detection.overallLevel == .critical
        )
    }
}
