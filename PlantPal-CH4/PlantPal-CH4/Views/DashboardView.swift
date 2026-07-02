import SwiftData
import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — DashboardView
//
// Main screen. Shows all plants with their current status.
// Critical plants surface at the top. Summary bar shows counts
// at a glance — "2 healthy · 1 warning · 1 critical".
// ══════════════════════════════════════════════════════════════

struct DashboardView: View {

    @Query(sort: \PlantProfile.addedAt)
    private var plants: [PlantProfile]

    @State private var searchText = ""
    @State private var navigateToAddPlant = false

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
        GridItem(.flexible(), spacing: 20)
    ]
    
    var body: some View {

        NavigationStack {
            AppBackground {
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 16) {
                        if filteredPlants.isEmpty {

                            VStack {
                                Spacer()
                                emptyState
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        } else {

                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 24) {
                                    ForEach(filteredPlants) { plant in
                                        PlantCardView(plant: plant)
                                    }

                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 124)
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
                    }
                }
                .navigationDestination(isPresented: $navigateToAddPlant) {
                    PlantSetupView()
                }
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search plants"
                )
                .onAppear {
                    print("DashboardView: plants count =", plants.count)
                }
            }
        }
    }
}

// MARK: Header
extension DashboardView {
    fileprivate var emptyState: some View {

        VStack(spacing: 20) {

            Image(systemName: "leaf.circle")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("No Plants Yet")
                .font(.title2.bold())

            Text("Add your first plant to begin monitoring its health.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

        }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantCardView
// ══════════════════════════════════════════════════════════════

struct PlantCardView: View {

    let plant: PlantProfile

    var body: some View {

        VStack(spacing: 12) {

            Group {
                if let imageData = plant.imageData,
                   let uiImage = UIImage(data: imageData) {

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()

                } else {

                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.green.opacity(0.15))
                        .overlay {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)
                        }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Text(plant.nickname)
                .font(.title3.bold())
                .foregroundStyle(Color.green.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .padding(.horizontal, 8)

        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }


    private var statusColor: Color {

        switch plant.alertLevel {

        case .healthy:
            return .green

        case .warning:
            return .orange

        case .critical:
            return .red
        }
    }

    private var statusText: String {

        switch plant.alertLevel {

        case .healthy:
            return "Healthy"

        case .warning:
            return "Needs Attention"

        case .critical:
            return "Critical"
        }
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

    return DashboardView()
        .modelContainer(container)
}
