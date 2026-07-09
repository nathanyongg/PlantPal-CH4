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
    @State private var showingConnectDevice = false
    @State private var pendingDevice: ESP32BLEManager.ProvisionedDevice?

    /// Devices already dedicated to an existing plant — each plant needs
    /// its own sensor, so these are never offered again during pairing.
    private var linkedDeviceIDs: Set<String> {
        Set(plants.compactMap(\.linkedDeviceID))
    }

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
//                    searchField

                    if filteredPlants.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        searchField
                        plantList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $navigateToAddPlant) {
                PlantSetupView(
                    preselectedDeviceID: pendingDevice?.id.uuidString,
                    preselectedDeviceName: pendingDevice?.name,
                    preselectedSensorBaseURL: pendingDevice?.baseURL.absoluteString
                )
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
            .fullScreenCover(isPresented: $showingConnectDevice) {
                ConnectDeviceView(
                    excludedDeviceIDs: linkedDeviceIDs,
                    onDeviceSelected: { device in
                        pendingDevice = device
                        showingConnectDevice = false
                        navigateToAddPlant = true
                    },
                    onCancel: { showingConnectDevice = false }
                )
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer()

                IconCircleButton(systemImage: "plus", accessibilityLabel: "Add Plant") {
                    pendingDevice = nil
                    showingConnectDevice = true
                }

                IconCircleButton(systemImage: "gearshape.fill", accessibilityLabel: "Settings") {
                    showingSettings = true
                }
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
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.surface, in: Capsule())
        .appOutline(Capsule(), colorScheme: colorScheme)
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

        VStack(spacing: 40) {

            Image(systemName: "leaf.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.Colors.leafGreen)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Your Plant Collection is Empty")
                    .font(Font.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Add your first plant to start tracking it’s health and growth.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button {
                pendingDevice = nil
                showingConnectDevice = true
            } label: {
                Text("Add Your Plant")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 250)
                    .frame(height: 54)
            }
            .background(AppTheme.Colors.leafGreen, in: Capsule())

        }
        .padding(.top, -60)
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
            minLightLux: 40,
            maxLightLux: 80
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
            minLightLux: 25,
            maxLightLux: 70
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
            minLightLux: 65,
            maxLightLux: 100
        )
    )
    cactus.lastStatus = "healthy"

//    container.mainContext.insert(monstera)
//    container.mainContext.insert(pothos)
//    container.mainContext.insert(cactus)

    return RootTabView()
        .modelContainer(container)
}
