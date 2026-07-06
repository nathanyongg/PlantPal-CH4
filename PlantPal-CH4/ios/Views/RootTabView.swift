import SwiftData
import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — DashboardView
//
// Main screen. Shows all plants with their current status.
// Critical plants surface at the top. Summary bar shows counts
// at a glance — "2 healthy · 1 warning · 1 critical".
// ══════════════════════════════════════════════════════════════

struct RootTabView: View {

    init() {
        // Make navigation bar fully transparent so AppBackground
        // shows through everywhere.
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        navBarAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }

    var body: some View {
        DashboardView()
    }
}

struct DashboardView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \PlantProfile.addedAt)
    private var plants: [PlantProfile]

    @State private var searchText = ""
    @State private var navigateToAddPlant = false
    @State private var selectedPlant: PlantProfile?
    @State private var editingPlant: PlantProfile?
    @State private var showingSettings = false
    @State private var showingDevicePairing = false

    private var filteredPlants: [PlantProfile] {

        let sorted = plants.sorted {
            $0.alertLevel > $1.alertLevel
        }

        guard !searchText.isEmpty else {
            return sorted
        }

        return sorted.filter {
            $0.nickname.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            AppBackground {
                VStack(spacing: 16) {
                    header
                    searchField

                    if filteredPlants.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        plantList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $navigateToAddPlant) {
                PlantSetupView()
            }
            .navigationDestination(item: $selectedPlant) { plant in
                PlantDetailView(profile: plant)
            }
            .navigationDestination(item: $editingPlant) { plant in
                PlantSetupView(editingProfile: plant)
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingDevicePairing) {
                DevicePairingView()
            }
        }
    }

    // MARK: — Header (add/settings leading, title trailing)

    private var header: some View {
        HStack {
            HStack(spacing: 12) {

                Text("Collections")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer()

                Button {
                    navigateToAddPlant = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.Colors.surface, in: Circle())
                        .overlay {
                            Circle().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Plant")

                Button {
                    showingDevicePairing = true
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.Colors.surface, in: Circle())
                        .overlay {
                            Circle().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Test Plant Sensor Pairing")

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.Colors.surface, in: Circle())
                        .overlay {
                            Circle().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

        }
    }

    // MARK: — Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.Colors.textSecondary)
            TextField("Search plants", text: $searchText)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.surface, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: — Plant list

    private var plantList: some View {
        List {
            ForEach(filteredPlants) { plant in
                Button {
                    selectedPlant = plant
                } label: {
                    PlantCardView(plant: plant)
                }
                .buttonStyle(.plain)
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(plant)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        editingPlant = plant
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(AppTheme.Colors.secondaryAccent)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, 40)
    }

    private func delete(_ plant: PlantProfile) {
        modelContext.delete(plant)
        try? modelContext.save()
    }
}

// MARK: Empty state
extension DashboardView {
    fileprivate var emptyState: some View {

        VStack(spacing: 20) {

            Image(systemName: "leaf.circle")
                .font(.system(size: 80))
                .foregroundStyle(AppTheme.Colors.success)
                .accessibilityHidden(true)

            Text("No Plants Yet")
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Add your plant to begin monitoring its health.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

        }
        .accessibilityElement(children: .combine)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — AlertLevel Comparable (for sorting)
// ══════════════════════════════════════════════════════════════

// Already Comparable via rawValue in SensorStatus.swift — just
// needs to be accessible here for sortedPlants.

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: PlantProfile.self,
        PlantHealthLogEntry.self,
        configurations: config
    )

    let monstera = PlantProfile(
        name: "Monstera deliciosa",
        nickname: "Living room",
        thresholds: PlantThresholds(
            minTemperatureC: 18,
            maxTemperatureC: 30,
            minHumidityPercent: 50,
            maxHumidityPercent: 80,
            minSoilMoisturePercent: 40,
            maxSoilMoisturePercent: 70,
            minLightLux: 10000,
            maxLightLux: 25000
        )
    )
    monstera.lastStatus = "critical"

    let pothos = PlantProfile(
        name: "Epipremnum aureum",
        nickname: "Kitchen pothos",
        thresholds: PlantThresholds(
            minTemperatureC: 15,
            maxTemperatureC: 30,
            minHumidityPercent: 40,
            maxHumidityPercent: 70,
            minSoilMoisturePercent: 30,
            maxSoilMoisturePercent: 60,
            minLightLux: 5000,
            maxLightLux: 20000
        )
    )
    pothos.lastStatus = "warning"

    let cactus = PlantProfile(
        name: "Cereus hildmannianus",
        nickname: "Desk cactus",
        thresholds: PlantThresholds(
            minTemperatureC: 20,
            maxTemperatureC: 38,
            minHumidityPercent: 10,
            maxHumidityPercent: 40,
            minSoilMoisturePercent: 5,
            maxSoilMoisturePercent: 20,
            minLightLux: 20000,
            maxLightLux: 50000
        )
    )
    cactus.lastStatus = "healthy"

    container.mainContext.insert(monstera)
    container.mainContext.insert(pothos)
    container.mainContext.insert(cactus)

    return RootTabView()
        .modelContainer(container)
}
