//
//  PlantPal_CH4App.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 30/06/26.
//

import SwiftData
import SwiftUI

@main
struct PlantPalApp: App {

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
    private let sharedModelContainer: ModelContainer = {
        try! ModelContainer(for: PlantProfile.self, PlantHealthLogEntry.self)
    }()

    init() {
        // Must be registered before the app finishes launching.
        AutoRefreshScheduler.shared.registerBackgroundTask()
    }

    var body: some Scene {

        WindowGroup {
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
        }
    }
}
