//
//  PlantCardView.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//

import SwiftUI
import SwiftData

// ══════════════════════════════════════════════════════════════
// MARK: — PlantCardView
//
// One row in the Collections list. Sensor badges read "--" until
// the plant has been checked at least once — the shared sensor
// only produces a real reading once the user taps "Check
// conditions" on that plant's detail screen — and the trailing
// timestamp shows when that last happened.
// ══════════════════════════════════════════════════════════════

struct PlantCardView: View {

    let plant: PlantProfile

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {

        HStack(alignment: .top, spacing: 14) {

            thumbnail

            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plant.nickname)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)

                        Text(plant.name)
                            .font(.system(.subheadline, design: .rounded).italic())
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(lastCheckedText)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                sensorBadgesRow
            }
        }
        .padding(12)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plant.nickname), \(plant.name), \(statusText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens plant details")
    }

    // MARK: — Thumbnail

    private var thumbnail: some View {
        Group {
            if let imageData = plant.imageData,
               let uiImage = UIImage(data: imageData) {

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()

            } else {

                ZStack {
                    AppTheme.Colors.success.opacity(0.15)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppTheme.Colors.success)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: — Sensor badges

    private var sensorBadgesRow: some View {
        HStack(spacing: 8) {
            badge(icon: "drop.fill", tint: AppTheme.Colors.sensorSoil, value: soilText)
            badge(icon: "sun.max.fill", tint: AppTheme.Colors.sensorLight, value: lightText)
            badge(icon: "thermometer", tint: AppTheme.Colors.sensorTemperature, value: temperatureText)
        }
    }

    private func badge(icon: String, tint: Color, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.Colors.backgroundMuted, in: Capsule())
    }

    // MARK: — Value formatting ("--" until first check)

    private var soilText: String {
        guard plant.hasBeenChecked, let value = plant.lastSoilMoisturePercent else { return "--" }
        return "\(Int(value))%"
    }

    private var lightText: String {
        guard plant.hasBeenChecked, let value = plant.lastLightLux else { return "--" }
        return "\(Int(value)) lx"
    }

    private var temperatureText: String {
        guard plant.hasBeenChecked, let value = plant.lastTemperatureC else { return "--" }
        return "\(Int(value))°C"
    }

    private var lastCheckedText: String {
        guard let lastReadingAt = plant.lastReadingAt else { return "--" }
        guard Calendar.current.isDateInToday(lastReadingAt) else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM"
            return formatter.string(from: lastReadingAt)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH.mm"
        return formatter.string(from: lastReadingAt)
    }

    private var statusText: String {

        guard plant.hasBeenChecked else { return "Not checked yet" }

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

#Preview {
    PlantSetupView()
        .modelContainer(for: PlantProfile.self, inMemory: true)
}
