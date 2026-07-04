//
//  SettingsView.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//

import SwiftUI

struct SettingsView: View {

    @AppStorage("textSize")
    private var textSize: TextSize = .system

    @AppStorage("appearance")
    private var appearance: Appearance = .system

    @AppStorage("spokenAnnouncements")
    private var spokenAnnouncements = true

    @AppStorage("notificationsEnabled")
    private var notificationsEnabled = true

    @AppStorage("criticalAlerts")
    private var criticalAlerts = true

    @AppStorage("dailyReminder")
    private var dailyReminder = true

    @StateObject private var ble = ESP32BLEManager.shared
    @State private var showingDevicePairing = false

    var body: some View {
        NavigationStack {
            AppBackground {
                Form {

                    Section {

                        Button {
                            showingDevicePairing = true
                        } label: {
                            HStack {
                                Text("Plant Sensor")
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Spacer()
                                Text(ble.hasPairedDevice ? "Paired" : "Not Paired")
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                    } header: {
                        Text("Device")
                    } footer: {
                        Text("One sensor works for every plant. Pair it once, then move it next to whichever plant you want to check.")
                    }

                    Section {

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
                    } header: {
                        Text("Appearance")
                    } footer: {
                        Text("\"System\" follows the theme and text size set in your device Settings, including larger accessibility sizes.")
                    }

                    Section {

                        Toggle(
                            "Spoken Announcements",
                            isOn: $spokenAnnouncements
                        )
                    } header: {
                        Text("Accessibility")
                    } footer: {
                        Text("Reads important updates aloud, such as when a plant is added. Works alongside VoiceOver.")
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbarBackground(.clear, for: .navigationBar)
            .sheet(isPresented: $showingDevicePairing) {
                DevicePairingView()
            }
        }
    }
}
