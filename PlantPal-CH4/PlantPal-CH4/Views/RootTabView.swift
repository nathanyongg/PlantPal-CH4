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
        // Make tab bar and navigation bar fully transparent
        // so AppBackground shows through everywhere
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        navBarAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }

    var body: some View {

        TabView {

            Tab("Plants", systemImage: "leaf.fill") {
                DashboardView()
            }

            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
    }
}

struct DashboardView: View {

    @Query(sort: \PlantProfile.addedAt)
    private var plants: [PlantProfile]

    @State private var searchText = ""
    @State private var navigateToAddPlant = false
    @State private var selectedPlant: PlantProfile?

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

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
    ]

    var body: some View {
        NavigationStack {
            AppBackground {
                Group {
                    if filteredPlants.isEmpty {
                        VStack {
                            Spacer()
                            emptyState
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 24) {
                                ForEach(filteredPlants) { plant in
                                    PlantCardView(plant: plant)
                                        .onTapGesture {
                                            selectedPlant = plant
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                            .safeAreaPadding(.bottom, 100)
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigateToAddPlant = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Plant")
                }
            }
            .navigationDestination(isPresented: $navigateToAddPlant) {
                PlantSetupView()
            }
            .navigationDestination(item: $selectedPlant) { plant in
                PlantDetailView(profile: plant)
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search plants"
            )
            .scrollContentBackground(.hidden)
            .toolbarBackground(.clear, for: .navigationBar)
        }
    }
}

// MARK: Header
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

            Text("Add your first plant to begin monitoring its health.")
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
