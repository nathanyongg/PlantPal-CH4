import SwiftUI
import SwiftData

// ══════════════════════════════════════════════════════════════
// MARK: — DashboardView
//
// Main screen. Shows all plants with their current status.
// Critical plants surface at the top. Summary bar shows counts
// at a glance — "2 healthy · 1 warning · 1 critical".
// ══════════════════════════════════════════════════════════════

struct DashboardView: View {

    @Query(sort: \PlantProfile.addedAt) private var plants: [PlantProfile]
    @State private var showingAddPlant = false

    // Derived counts
    private var healthyCount:  Int { plants.filter { $0.alertLevel == .healthy  }.count }
    private var warningCount:  Int { plants.filter { $0.alertLevel == .warning  }.count }
    private var criticalCount: Int { plants.filter { $0.alertLevel == .critical }.count }

    // Sort: critical first, then warning, then healthy
    private var sortedPlants: [PlantProfile] {
        plants.sorted { $0.alertLevel > $1.alertLevel }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plants.isEmpty {
                    emptyState
                } else {
                    plantList
                }
            }
            .navigationTitle("PlantPal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddPlant = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddPlant) {
                PlantSetupView()
            }
        }
    }

    // MARK: — Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 64))
                .foregroundStyle(.green.opacity(0.6))
            Text("No plants yet")
                .font(.title2.bold())
            Text("Tap + to add your first plant.\nWe'll look up its ideal conditions automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add plant") { showingAddPlant = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: — Plant list

    private var plantList: some View {
        List {
            // Summary banner — only shown when something's wrong
            if warningCount > 0 || criticalCount > 0 {
                summaryBanner
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Plants — critical first
            ForEach(sortedPlants) { plant in
                PlantRowView(plant: plant)
                    .listRowBackground(
                        plant.alertLevel == .critical
                        ? Color.red.opacity(0.06)
                        : Color.clear
                    )
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: — Summary banner

    private var summaryBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if criticalCount > 0 {
                    summaryChip(
                        count: criticalCount,
                        label: criticalCount == 1 ? "needs help now" : "need help now",
                        color: .red
                    )
                }
                if warningCount > 0 {
                    summaryChip(
                        count: warningCount,
                        label: warningCount == 1 ? "needs attention" : "need attention",
                        color: .orange
                    )
                }
                if healthyCount > 0 {
                    summaryChip(
                        count: healthyCount,
                        label: healthyCount == 1 ? "is healthy" : "are healthy",
                        color: .green
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 16)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantRowView
// ══════════════════════════════════════════════════════════════

struct PlantRowView: View {

    let plant: PlantProfile

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.4), radius: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(plant.nickname)
                    .font(.headline)
                Text(plant.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(statusLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(statusColor)

                if let lastRead = plant.lastReadingAt {
                    Text(lastRead, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch plant.alertLevel {
        case .healthy:  return .green
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private var statusLabel: String {
        switch plant.alertLevel {
        case .healthy:  return "Healthy"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — AlertLevel Comparable (for sorting)
// ══════════════════════════════════════════════════════════════

// Already Comparable via rawValue in SensorStatus.swift — just
// needs to be accessible here for sortedPlants.

#Preview {
    let config    = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: PlantProfile.self, configurations: config)

    let monstera = PlantProfile(
        name: "Monstera deliciosa", nickname: "Living room",
        thresholds: PlantThresholds(minTemperature: 18, maxTemperature: 30, minHumidity: 50, maxHumidity: 80, minSoilMoisture: 40, maxSoilMoisture: 70, minLight: 10000, maxLight: 25000)
    )
    monstera.lastStatus = "critical"

    let pothos = PlantProfile(
        name: "Epipremnum aureum", nickname: "Kitchen pothos",
        thresholds: PlantThresholds(minTemperature: 15, maxTemperature: 30, minHumidity: 40, maxHumidity: 70, minSoilMoisture: 30, maxSoilMoisture: 60, minLight: 5000, maxLight: 20000)
    )
    pothos.lastStatus = "warning"

    let cactus = PlantProfile(
        name: "Cereus hildmannianus", nickname: "Desk cactus",
        thresholds: PlantThresholds(minTemperature: 20, maxTemperature: 38, minHumidity: 10, maxHumidity: 40, minSoilMoisture: 5, maxSoilMoisture: 20, minLight: 20000, maxLight: 50000)
    )
    cactus.lastStatus = "healthy"

    container.mainContext.insert(monstera)
    container.mainContext.insert(pothos)
    container.mainContext.insert(cactus)

    return DashboardView()
        .modelContainer(container)
}
