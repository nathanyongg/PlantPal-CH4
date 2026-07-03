//
//  SettingsView.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//

import SwiftUI

struct SettingsView: View {

    @AppStorage("textSize")
    private var textSize: TextSize = .medium

    @AppStorage("appearance")
    private var appearance: Appearance = .system

    @AppStorage("notificationsEnabled")
    private var notificationsEnabled = true

    @AppStorage("criticalAlerts")
    private var criticalAlerts = true

    @AppStorage("dailyReminder")
    private var dailyReminder = true

    var body: some View {
        NavigationStack {
            Form {

                Section("Appearance") {

                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }

                    Picker("Text Size", selection: $textSize) {
                        ForEach(TextSize.allCases) { size in
                            Text(size.title)
                                .tag(size)
                        }
                    }
                }

                Section("Notifications") {

                    Toggle(
                        "Enable Notifications",
                        isOn: $notificationsEnabled
                    )

                    if notificationsEnabled {

                        Toggle(
                            "Critical Plant Alerts",
                            isOn: $criticalAlerts
                        )

                        Toggle(
                            "Daily Care Reminder",
                            isOn: $dailyReminder
                        )
                    }
                }

                Section {

                    VStack(alignment: .leading, spacing: 6) {

                        Text("PlantPal")
                            .font(.headline)

                        Text("Version 1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }

    }
}
