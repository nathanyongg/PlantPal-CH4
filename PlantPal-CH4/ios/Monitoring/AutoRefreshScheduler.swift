import Foundation
import BackgroundTasks
import SwiftData

// ══════════════════════════════════════════════════════════════
// MARK: — AutoRefreshScheduler
//
// Each plant now has its own dedicated sensor (no more sharing one
// sensor across every plant), so checking on a plant no longer
// requires the user to physically move anything into place — the
// app can just check in on its own. This fires every 15 minutes
// while the app is open, independently of any single plant's
// screen being on screen, and best-effort in the background via
// BGAppRefreshTask (iOS doesn't guarantee background timing, so
// the foreground timer is what actually delivers the 15-minute
// cadence in practice).
//
// A manual check (the "Check conditions" button, or pulling down
// on a plant's detail screen) always wins over this cadence —
// it just runs immediately instead of waiting for the next tick.
// ══════════════════════════════════════════════════════════════

@MainActor
final class AutoRefreshScheduler {

    static let shared = AutoRefreshScheduler()

    static let refreshInterval: TimeInterval = 15 * 60

    private static let backgroundTaskIdentifier = "com.PlantPal.refresh"

    private var timer: Timer?
    private var modelContainer: ModelContainer?

    private init() {}

    // MARK: — Foreground timer

    func start(with container: ModelContainer) {
        modelContainer = container

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAllPlants(notifyIfUnhealthy: true)
            }
        }

        Task { await refreshAllPlants(notifyIfUnhealthy: true) }
    }

    private func refreshAllPlants(notifyIfUnhealthy: Bool) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        guard let profiles = try? context.fetch(FetchDescriptor<PlantProfile>()) else { return }

        for profile in profiles {
            await PlantHealthMonitor.shared.checkPlantHealth(
                for: profile,
                modelContext: context,
                notifyIfUnhealthy: notifyIfUnhealthy
            )
        }
    }

    // MARK: — Background best-effort (BGAppRefreshTask)
    //
    // Must be registered before the app finishes launching. iOS decides
    // if/when this actually runs — it's a supplement to the foreground
    // timer above, not a guarantee of the 15-minute cadence.

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh() // queue the next one regardless of outcome

        let refreshTask = Task {
            await refreshAllPlants(notifyIfUnhealthy: true)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }
}
