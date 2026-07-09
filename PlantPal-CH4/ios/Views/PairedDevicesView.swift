import SwiftData
import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — PairedDevicesView
//
// Every plant with a linked sensor, shown alongside which plant
// it's attached to. Removing one here just unlinks it from that
// plant — the plant itself stays, and the device becomes
// available again the next time someone adds a new plant.
// ══════════════════════════════════════════════════════════════

struct PairedDevicesView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \PlantProfile.addedAt)
    private var plants: [PlantProfile]

    @State private var pendingRemoval: PlantProfile?
    @State private var selectedPlant: PlantProfile?

    private var pairedPlants: [PlantProfile] {
        plants.filter { $0.linkedDeviceID != nil }
    }

    var body: some View {
        AppBackground {
            Group {
                if pairedPlants.isEmpty {
                    emptyState
                } else {
                    Form {
                        Section {
                            ForEach(pairedPlants) { plant in
                                Button {
                                    selectedPlant = plant
                                } label: {
                                    row(for: plant)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppTheme.Colors.surface)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingRemoval = plant
                                    } label: {
                                        Label("Remove", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        } footer: {
                            Text("Tap a device to view its plant, or swipe to remove a pairing.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationDestination(item: $selectedPlant) { plant in
            PlantDetailView(profile: plant)
        }
        .navigationTitle("Paired Devices")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove This Pairing?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval {
                    unlink(pendingRemoval)
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text("\(pendingRemoval?.linkedDeviceName ?? "This device") will no longer send readings to \(pendingRemoval?.nickname ?? "this plant"). You can pair a new sensor to it later.")
        }
    }

    private func row(for plant: PlantProfile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.success.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "wifi")
                    .foregroundStyle(AppTheme.Colors.success)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(plant.linkedDeviceName ?? "Plant Sensor")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Attached to \(plant.nickname)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this plant. Swipe to remove the pairing.")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text("No Paired Devices")
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Sensors get paired to a plant from the Add Plant screen.")
                .font(AppTheme.Typography.subtitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func unlink(_ plant: PlantProfile) {
        plant.linkedDeviceID = nil
        plant.linkedDeviceName = nil
        plant.sensorBaseURL = nil
        try? modelContext.save()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: PlantProfile.self, PlantHealthLogEntry.self,
        configurations: config
    )

    let monstera = PlantProfile(
        name: "Monstera deliciosa",
        nickname: "My Mochi",
        thresholds: PlantThresholds(
            minTemperatureC: 18, maxTemperatureC: 26,
            minHumidityPercent: 40, maxHumidityPercent: 80,
            minSoilMoisturePercent: 50, maxSoilMoisturePercent: 80,
            minLightLux: 40, maxLightLux: 80
        ),
        linkedDeviceID: UUID().uuidString,
        linkedDeviceName: "PlantPal-001",
        sensorBaseURL: "http://192.168.1.50"
    )
    container.mainContext.insert(monstera)

    return NavigationStack {
        PairedDevicesView()
    }
    .modelContainer(container)
}
