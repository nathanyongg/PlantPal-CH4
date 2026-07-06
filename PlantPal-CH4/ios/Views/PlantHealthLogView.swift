import SwiftData
import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthLogView
//
// Today's check-ins for one plant. Since a single shared sensor
// only means something once it's been moved next to this plant
// and checked, this is a log of when that happened today and
// what the reading looked like each time — not a live feed.
// ══════════════════════════════════════════════════════════════

struct PlantHealthLogView: View {

    let profile: PlantProfile

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlantHealthLogEntry.timestamp, order: .reverse)
    private var allEntries: [PlantHealthLogEntry]

    private var todaysEntries: [PlantHealthLogEntry] {
        allEntries.filter {
            $0.plant === profile && Calendar.current.isDateInToday($0.timestamp)
        }
    }

    var body: some View {
        NavigationStack {
            AppBackground {
                Group {
                    if todaysEntries.isEmpty {
                        emptyState
                    } else {
                        List(todaysEntries) { entry in
                            row(for: entry)
                                .listRowBackground(AppTheme.Colors.surface)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Today's Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text("No Checks Yet Today")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("\(profile.nickname) hasn't been checked today yet. It checks in automatically, or open its details and tap \u{201C}Check conditions\u{201D} to check now.")
                .font(AppTheme.Typography.subtitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(for entry: PlantHealthLogEntry) -> some View {
        HStack(spacing: 14) {
            statusDot(for: entry.alertLevel)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.formattedTime)
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(summary(for: entry))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            Text(statusLabel(for: entry.alertLevel))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(color(for: entry.alertLevel))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func statusDot(for level: AlertLevel) -> some View {
        Circle()
            .fill(color(for: level))
            .frame(width: 10, height: 10)
    }

    private func summary(for entry: PlantHealthLogEntry) -> String {
        "\(Int(entry.temperature))°C · \(Int(entry.humidity))% humidity · \(Int(entry.soilMoisture))% soil · \(Int(entry.lightIntensity)) lux"
    }

    private func statusLabel(for level: AlertLevel) -> String {
        switch level {
        case .healthy:  return "Healthy"
        case .warning:  return "Needs Attention"
        case .critical: return "Critical"
        }
    }

    private func color(for level: AlertLevel) -> Color {
        switch level {
        case .healthy:  return AppTheme.Colors.success
        case .warning:  return AppTheme.Colors.warning
        case .critical: return AppTheme.Colors.critical
        }
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
            minLightLux: 10_000, maxLightLux: 25_000
        )
    )
    container.mainContext.insert(monstera)

    container.mainContext.insert(PlantHealthLogEntry(
        timestamp: Date(),
        reading: SensorReading(timestamp: Date(), temperature: 28, humidity: 60, soilMoisture: 10, lightIntensity: 18_000),
        status: "warning",
        plant: monstera
    ))

    return PlantHealthLogView(profile: monstera)
        .modelContainer(container)
}
