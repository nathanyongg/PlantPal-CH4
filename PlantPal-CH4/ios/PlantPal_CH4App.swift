//
//  PlantPal_CH4App.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 30/06/26.
//

import SwiftData
import SwiftUI
import FirebaseCore

@main
struct PlantPalApp: App {

    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self)
    private var notificationAppDelegate

    @AppStorage("appearance")
    private var appearance: Appearance = .system

    @AppStorage("textSize")
    private var textSize: TextSize = .system

    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    // Built explicitly (rather than via the `.modelContainer(for:)` view
    // modifier) so AutoRefreshScheduler can share the exact same
    // container the UI observes — its background checks need to land
    // in the same store Collections/Detail are querying.
    private let modelContainerResult: Result<ModelContainer, Error> = Result {
        try ModelContainer(for: PlantProfile.self, PlantHealthLogEntry.self)
    }
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        if case .success = modelContainerResult {
            // Must be registered before the app finishes launching.
            AutoRefreshScheduler.shared.registerBackgroundTask()
        }
    }

    var body: some Scene {

        WindowGroup {
            switch modelContainerResult {
            case .success(let sharedModelContainer):
                Group {
                    if hasCompletedOnboarding {
                        RootTabView()
                    } else {
                        OnboardingView {
                            hasCompletedOnboarding = true
                        }
                    }
                }
                .preferredColorScheme(appearance.colorScheme)
                .appTextSize(textSize)
                .modelContainer(sharedModelContainer)
                .task {
                    AutoRefreshScheduler.shared.start(with: sharedModelContainer)
                    AutoRefreshScheduler.shared.scheduleBackgroundRefresh()
                }

            case .failure(let error):
                StartupFailureView(error: error)
            }
        }
    }
}

private struct StartupFailureView: View {

    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("PlantPal couldn't start")
                .font(.title2.bold())

            Text(error.localizedDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}
