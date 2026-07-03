import SwiftUI
internal import Combine

// ══════════════════════════════════════════════════════════════
// MARK: — PlantLandingView
//
// The main "plant profile" landing screen. Unlike
// PlantHealthTestView (a debug harness with sliders — keep that
// as its own separate file), this view runs the REAL pipeline
// against a real SensorReading + PlantProfile and renders the
// result. No sliders, no nested NavigationStack — just data in,
// UI out.
//
// PlantHealthDetector → PlantExplainer → PlantCardData (display model)
// ══════════════════════════════════════════════════════════════

struct PlantLandingView: View {

    // Inputs — supply the latest reading + the plant's stored profile
    // (e.g. from your SwiftData store / ESP32 / cloud backend).
    let reading: SensorReading
    let profile: PlantProfile
    let species: String
    let nickname: String
    let imageAssetName: String

    var onBack: (() -> Void)? = nil
    var onOpenChat: (() -> Void)? = nil
    var onAskMore: (() -> Void)? = nil

    @StateObject private var viewModel = PlantPipelineViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            backgroundGradient

            if let plant = viewModel.cardData {
                landingContent(plant)
            } else {
                loadingView
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            await viewModel.refresh(
                reading: reading,
                profile: profile,
                species: species,
                nickname: nickname,
                imageAssetName: imageAssetName
            )
        }
    }

    // MARK: — Loading state

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading your plant…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Loaded content

    private func landingContent(_ plant: PlantCardData) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    header(plant)
                    photoAndMoodRow(plant)
                    metricsRow(plant)

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 140) // room for the insight panel
            }

            Color.clear.frame(height: 0)
        }
        .overlay(alignment: .bottom) {
            insightPanel(plant)
        }
    }

    // MARK: — Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "FCF6DA"), Color(hex: "FBEECB")],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: — Top bar

    private var topBar: some View {
        HStack {
            Button(action: { onBack?() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { onOpenChat?() }) {
                Image(systemName: "message.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "F0A868"), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: — Header (species + name)

    private func header(_ plant: PlantCardData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plant.species)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "7C9473"))

            HStack(spacing: 6) {
                Text(plant.nickname)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black.opacity(0.85))
                Text(plant.emoji)
                    .font(.system(size: 26))
            }
        }
    }

    // MARK: — Photo + mood/message

    private func photoAndMoodRow(_ plant: PlantCardData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            plantPhoto(plant)
                .frame(width: 165, height: 220)

            VStack(alignment: .trailing, spacing: 10) {
                moodPill(plant)
                messageBubble(plant)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func plantPhoto(_ plant: PlantCardData) -> some View {
        Group {
            #if canImport(UIKit)
            if let uiImage = UIImage(named: plant.imageAssetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                photoPlaceholder
            }
            #else
            photoPlaceholder
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(8)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 6)
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "DCEBD8"), Color(hex: "C7DFC1")],
                startPoint: .top, endPoint: .bottom
            )
            Image(systemName: "leaf.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func moodPill(_ plant: PlantCardData) -> some View {
        HStack(spacing: 6) {
            Text(plant.moodEmoji)
                .font(.system(size: 14))
            Text(plant.mood)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "9B5FBE"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: "F1D9F5"), in: Capsule())
    }

    private func messageBubble(_ plant: PlantCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's message")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\u{201C}\(plant.todaysMessage)\u{201D}")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.black.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: — Metric cards

    private func metricsRow(_ plant: PlantCardData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(plant.metrics) { metric in
                    MetricCard(metric: metric)
                        .frame(width: 108)
                }
            }
        }
        .padding(.top, 14)
    }

    // MARK: — Error banner (pipeline degraded but still showing data)

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.black.opacity(0.7))
        }
        .padding(12)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: — Bottom AI insight panel

    private func insightPanel(_ plant: PlantCardData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("AI insight")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white.opacity(0.9))

                Text(plant.aiInsight)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button(action: { onAskMore?() }) {
                        Text("Ask more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(
            Color(hex: "D7BFF0")
                .clipShape(RoundedCorner(radius: 34, corners: [.topLeft, .topRight]))
        )
    }
}

// MARK: — Metric card

private struct MetricCard: View {
    let metric: PlantMetric

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(metric.tint)
                    .frame(width: 40, height: 40)
                    .shadow(color: metric.tint.opacity(0.35), radius: 6, x: 0, y: 3)
                Image(systemName: metric.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .offset(y: -28)
            .padding(.bottom, -28)

            HStack(spacing: 4) {
                Text(metric.statusLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(metric.statusEmoji)
                    .font(.caption)
            }

            Text(metric.valueText)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(metric.tint)

            Text(metric.idealRangeText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ProgressTrack(progress: metric.progress, tint: metric.tint)
                .frame(height: 5)
        }
        .padding(.top, 30)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
    }
}

private struct ProgressTrack: View {
    let progress: Double // 0...1
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: "ECECEC"))
                Capsule()
                    .fill(tint)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .clipShape(Capsule())
    }
}

// MARK: — Rounded-corner helper (top corners only, for the insight panel)

private struct RoundedCorner: Shape {
    var radius: CGFloat = 20
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: — Color(hex:) convenience

private extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .whitespacesAndNewlines))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantPipelineViewModel
//
// Runs the real PlantHealthDetector → PlantExplainer pipeline
// (the same calls used in PlantHealthTestView) and turns the
// result into a PlantCardData for PlantLandingView to render.
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantPipelineViewModel: ObservableObject {

    @Published private(set) var cardData: PlantCardData?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let detector = PlantHealthDetector()
    private let explainer = PlantExplainer()

    func refresh(
        reading: SensorReading,
        profile: PlantProfile,
        species: String,
        nickname: String,
        imageAssetName: String
    ) async {
        isLoading = true
        errorMessage = nil

        let statuses = detector.assess(reading, for: profile)
        let detection = DetectionResult(timestamp: reading.timestamp, statuses: statuses)
        let metrics = SensorKind.allCases.map { $0.metric(reading: reading, thresholds: profile.thresholds()) }

        guard !detection.isHealthy else {
            cardData = PlantCardData(
                species: species, nickname: nickname, imageAssetName: imageAssetName,
                mood: "Happy", moodEmoji: "😊",
                todaysMessage: "Everything feels just right todayyy!",
                aiInsight: "All readings are within the ideal range — keep up the current care routine.",
                metrics: metrics
            )
            isLoading = false
            return
        }

        guard PlantExplainer.isAvailable() else {
            errorMessage = PlantExplainer.unavailableReason() ?? "Apple Intelligence unavailable."
            cardData = fallbackCard(
                for: detection.overallLevel, species: species, nickname: nickname,
                imageAssetName: imageAssetName, metrics: metrics
            )
            isLoading = false
            return
        }

        do {
            let explanation = try await explainer.explain(reading: reading, detection: detection)
            let (mood, emoji) = Self.mood(for: detection.overallLevel)
            cardData = PlantCardData(
                species: species, nickname: nickname, imageAssetName: imageAssetName,
                mood: mood, moodEmoji: emoji,
                todaysMessage: explanation.notificationBody,
                aiInsight: "\(explanation.cause) \(explanation.action)",
                metrics: metrics
            )
        } catch {
            errorMessage = error.localizedDescription
            cardData = fallbackCard(
                for: detection.overallLevel, species: species, nickname: nickname,
                imageAssetName: imageAssetName, metrics: metrics
            )
        }

        isLoading = false
    }

    private func fallbackCard(
        for level: AlertLevel, species: String, nickname: String,
        imageAssetName: String, metrics: [PlantMetric]
    ) -> PlantCardData {
        let (mood, emoji) = Self.mood(for: level)
        return PlantCardData(
            species: species, nickname: nickname, imageAssetName: imageAssetName,
            mood: mood, moodEmoji: emoji,
            todaysMessage: "Something's off — check my latest readings.",
            aiInsight: "Couldn't generate a detailed explanation right now, but at least one reading is outside the ideal range.",
            metrics: metrics
        )
    }

    private static func mood(for level: AlertLevel) -> (String, String) {
        switch level {
        case .healthy:  return ("Happy", "😊")
        case .warning:  return ("Uneasy", "😕")
        case .critical: return ("Stressed", "😣")
        }
    }
}

// MARK: — Sensor → metric card mapping
//
// Computed purely from the reading + the profile's thresholds, so
// it doesn't depend on any extra fields beyond what's already used
// in PlantHealthTestView (SensorReading, PlantThresholds).

private enum SensorKind: CaseIterable {
    case temperature, humidity, soilMoisture, light

    func metric(reading: SensorReading, thresholds: PlantThresholds) -> PlantMetric {
        let range = idealRange(thresholds: thresholds)
        let value = rawValue(reading: reading)
        let progress = range.upperBound > range.lowerBound
            ? min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            : 0.5
        let (label, emoji) = statusLabel(value: value, range: range)

        return PlantMetric(
            systemImage: icon,
            tint: tint,
            statusLabel: label,
            statusEmoji: emoji,
            valueText: formattedValue(value),
            idealRangeText: "Ideal \(formattedBound(range.lowerBound)) - \(formattedBound(range.upperBound))",
            progress: progress
        )
    }

    private func rawValue(reading: SensorReading) -> Double {
        switch self {
        case .temperature: return reading.temperature
        case .humidity:     return reading.humidity
        case .soilMoisture: return reading.soilMoisture
        case .light:        return reading.lightIntensity
        }
    }

    private func idealRange(thresholds: PlantThresholds) -> ClosedRange<Double> {
        switch self {
        case .temperature: return thresholds.minTemperatureC...thresholds.maxTemperatureC
        case .humidity:     return thresholds.minHumidityPercent...thresholds.maxHumidityPercent
        case .soilMoisture: return thresholds.minSoilMoisturePercent...thresholds.maxSoilMoisturePercent
        case .light:        return thresholds.minLightLux...thresholds.maxLightLux
        }
    }

    private var icon: String {
        switch self {
        case .temperature: return "thermometer"
        case .humidity:     return "humidity.fill"
        case .soilMoisture: return "drop.fill"
        case .light:        return "sun.max.fill"
        }
    }

    private var tint: Color {
        switch self {
        case .temperature: return Color(hex: "F16759") // red
        case .humidity:     return Color(hex: "4FA8E0") // blue
        case .soilMoisture: return Color(hex: "3EC0A6") // teal
        case .light:        return Color(hex: "F5A93F") // orange
        }
    }

    private func statusLabel(value: Double, range: ClosedRange<Double>) -> (String, String) {
        if value < range.lowerBound {
            switch self {
            case .temperature: return ("Too cold", "❄️")
            case .humidity:     return ("Too dry", "🥺")
            case .soilMoisture: return ("Too dry", "🥺")
            case .light:        return ("Too dark", "😴")
            }
        } else if value > range.upperBound {
            switch self {
            case .temperature: return ("Too hot", "🥵")
            case .humidity:     return ("Too humid", "💦")
            case .soilMoisture: return ("Overwatered", "🫗")
            case .light:        return ("Too bright", "🔆")
            }
        } else {
            return ("Perfect", "🤩")
        }
    }

    private func formattedValue(_ value: Double) -> String {
        switch self {
        case .temperature: return String(format: "%.0f°C", value)
        case .humidity, .soilMoisture: return String(format: "%.0f%%", value)
        case .light: return String(format: "%.0f lux", value)
        }
    }

    private func formattedBound(_ value: Double) -> String {
        switch self {
        case .temperature: return String(format: "%.0f°C", value)
        case .humidity, .soilMoisture: return String(format: "%.0f%%", value)
        case .light: return String(format: "%.0f lux", value)
        }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Display models
// ══════════════════════════════════════════════════════════════

struct PlantCardData {
    var species: String
    var nickname: String
    var emoji: String = "🌱"
    var imageAssetName: String
    var mood: String
    var moodEmoji: String
    var todaysMessage: String
    var aiInsight: String
    var metrics: [PlantMetric]
}

struct PlantMetric: Identifiable {
    let id = UUID()
    var systemImage: String
    var tint: Color
    var statusLabel: String
    var statusEmoji: String
    var valueText: String
    var idealRangeText: String
    var progress: Double // 0...1
}

// MARK: — Preview

#Preview {
    PlantLandingView(
        reading: SensorReading(
            timestamp: Date(),
            temperature: 24,
            humidity: 60,
            soilMoisture: 50,
            lightIntensity: 18_000
        ),
        profile: PlantProfile(
            name: "Monstera deliciosa",
            nickname: "My Mochi",
            thresholds: PlantThresholds(
                minTemperatureC: 18, maxTemperatureC: 26,
                minHumidityPercent: 40, maxHumidityPercent: 80,
                minSoilMoisturePercent: 50, maxSoilMoisturePercent: 80,
                minLightLux: 10_000, maxLightLux: 25_000
            )
        ),
        species: "Monstera deliciosa",
        nickname: "My Mochi",
        imageAssetName: "mochiPhoto"
    )
}
