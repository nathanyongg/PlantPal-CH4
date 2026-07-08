import SwiftData
import SwiftUI
internal import Combine

// ══════════════════════════════════════════════════════════════
// MARK: — PlantDetailView
//
// The "plant profile" screen — species, nickname, mood, today's
// message, sensor metrics, and an AI-generated insight. Fetches
// the latest sensor reading, then runs it through the real
// pipeline: PlantHealthDetector → PlantExplainer → PlantCardData.
// ══════════════════════════════════════════════════════════════

struct PlantDetailView: View {

    let profile: PlantProfile

    /// Preview/testing only — when set, skips the network fetch and
    /// the Foundation Model call entirely and renders this data
    /// directly, so the UI can be checked without either dependency.
    var previewCardData: PlantCardData? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel = PlantPipelineViewModel()
    @StateObject private var ble = ESP32BLEManager.shared

    @State private var isChecking = false
    @State private var checkErrorMessage: String?

    // Foundation Model calls only ever happen from an explicit user
    // action — pull-to-refresh or the header's refresh button, both of
    // which call `performCheck()` directly. Opening the screen just
    // shows whatever was last recorded; it never triggers a fresh
    // check or FM call on its own, and live BLE readings arriving in
    // the background don't either.
    var body: some View {
        mainContent
            .background(AppBackground { Color.clear })
            .ignoresSafeArea(edges: .bottom)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if let previewCardData {
                    viewModel.setPreviewData(previewCardData)
                } else {
                    viewModel.loadLastKnown(
                        profile: profile,
                        species: profile.name,
                        nickname: profile.nickname,
                        imageData: profile.imageData
                    )
                }
            }
    }

    // MARK: — Check conditions (explicit, one shared sensor)
    //
    // Opening this screen never touches the network on its own — the
    // sensor has to physically be moved next to this plant first, so
    // a reading only means something once the user confirms it's in
    // place by tapping "Check conditions".

    private func performCheck() async {
        guard previewCardData == nil else { return }
        isChecking = true
        checkErrorMessage = nil
        do {
            let freshReading = try await fetchLatestReading()
            render(reading: freshReading, shouldRecord: true)
        } catch {
            if let bleReading = ble.latestReading {
                render(reading: bleReading, shouldRecord: true)
                checkErrorMessage = "Showing the latest Bluetooth reading because the Wi-Fi sensor endpoint did not respond."
            } else {
                checkErrorMessage = error.localizedDescription
            }
        }
        isChecking = false
    }

    private func fetchLatestReading() async throws -> SensorReading {
        try await PlantDataService(profile: profile).fetchLatestReading()
    }

    private func render(reading: SensorReading, shouldRecord: Bool) {
        Task {
            await viewModel.refresh(
                reading: reading,
                profile: profile,
                species: profile.name,
                nickname: profile.nickname,
                imageData: profile.imageData
            )
            if shouldRecord {
                recordCheckIn(reading: reading)
            }
        }
    }

    // MARK: — Main content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                topBar
                header
                photoAndMoodRow

                // Shows as soon as a check starts (with a spinner) so it
                // doesn't pop in only once the Foundation Model finishes —
                // and stays hidden until either a check is in flight or a
                // genuine result (not the "last known" placeholder) exists.
                if isChecking || (viewModel.cardData?.isGenuineInsight == true) {
                    insightPanel(viewModel.cardData)
                }

                if let plant = viewModel.cardData {
                    metricsRow(plant)
                }

                if let checkErrorMessage {
                    errorBanner(checkErrorMessage)
                } else if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isChecking)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.cardData?.isGenuineInsight)
        }
        .refreshable {
            await performCheck()
        }
    }

    // MARK: — Check-in logging
    //
    // One shared sensor means a reading only means something once
    // it's been physically moved next to this plant and checked —
    // so each completed check is what gets logged, not a continuous
    // background feed.

    private func recordCheckIn(reading: SensorReading) {
        guard let level = viewModel.lastDetectionLevel else { return }
        let status = level == .critical ? "critical" : level == .warning ? "warning" : "healthy"

        let entry = PlantHealthLogEntry(
            timestamp: reading.timestamp,
            reading: reading,
            status: status,
            plant: profile
        )
        modelContext.insert(entry)

        profile.lastReadingAt = reading.timestamp
        profile.lastStatus = status
        profile.lastTemperatureC = reading.temperature
        profile.lastHumidityPercent = reading.humidity
        profile.lastSoilMoisturePercent = reading.soilMoisture
        profile.lastLightLux = reading.lightIntensity

        try? modelContext.save()
    }

    // MARK: — Top bar

    private var topBar: some View {
        HStack {
            IconCircleButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                dismiss()
            }

            Spacer()

            Button {
                Task { await performCheck() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.Colors.surface, in: Circle())
                    .appOutline(Circle(), colorScheme: colorScheme)
                    .rotationEffect(.degrees(isChecking ? 360 : 0))
                    .animation(
                        isChecking ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                        value: isChecking
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isChecking || previewCardData != nil)
            .accessibilityLabel("Refresh")
            .accessibilityHint("Reads the sensor now and records today's check-in")
        }
        .padding(.top, 8)
    }

    // MARK: — Header (species + name)

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.name)
                .font(AppTheme.Typography.subtitle.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.leafGreen)

            HStack(spacing: 6) {
                Text(profile.nickname)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("🌱")
                    .font(.system(size: 26))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: — Photo + mood/message

    private var photoAndMoodRow: some View {
        HStack(alignment: .top, spacing: 12) {
            plantPhoto
                .frame(width: 165, height: 220)

            VStack(alignment: .trailing, spacing: 10) {
                if let plant = viewModel.cardData {
                    moodPill(plant)
                    messageBubble(plant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var plantPhoto: some View {
        Group {
            if let imageData = profile.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                photoPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(8)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: 26, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 6)
    }

    private var photoPlaceholder: some View {
        ZStack {
            AppTheme.Colors.success.opacity(0.15)
            Image(systemName: "leaf.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.Colors.success)
        }
    }

    private func moodPill(_ plant: PlantCardData) -> some View {
        HStack(spacing: 6) {
            Text(plant.moodEmoji)
                .font(.system(size: 14))
            Text(plant.mood)
                .font(AppTheme.Typography.subtitle.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.secondaryAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.Colors.lavenderPanel, in: Capsule())
        .appOutline(Capsule(), colorScheme: colorScheme)
    }

    private func messageBubble(_ plant: PlantCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's message")
                .font(AppTheme.Typography.tiny)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("\u{201C}\(plant.todaysMessage)\u{201D}")
                .font(AppTheme.Typography.subtitle.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: 18, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: — Metric rows

    private func metricsRow(_ plant: PlantCardData) -> some View {
        VStack(spacing: 34) {
            ForEach(plant.metrics) { metric in
                MetricRow(metric: metric)
            }
        }
        .padding(20)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
        .padding(.top, 14)
    }

    // MARK: — Error banner (pipeline degraded but still showing data)

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.Colors.warning)
            Text(message)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(12)
        .background(AppTheme.Colors.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: — AI insight card (action + description, above the sensor readings)

    private func insightPanel(_ plant: PlantCardData?) -> some View {
        Group {
            if let plant {
                VStack(alignment: .leading, spacing: 10) {
                    Text(plant.aiInsightTitle)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(plant.aiInsight)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isChecking {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .frame(minHeight: 60)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.insightPanel, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
    }
}

// MARK: — Metric row

private struct MetricRow: View {
    let metric: PlantMetric

    private let thumbWidth: CGFloat = 64
    private let trackHeight: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.name)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                Text(metric.idealRangeText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Text(metric.statusLabel)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(metric.statusEmoji)
                        .font(.callout)
                }
            }

            GeometryReader { geo in
                let clampedProgress = min(max(metric.progress, 0), 1)
                let thumbX = thumbWidth / 2 + (geo.size.width - thumbWidth) * clampedProgress

                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.border)
                    Capsule()
                        .fill(metric.tint)
                        .frame(width: max(thumbWidth / 2, thumbX))

                    Text(metric.valueText)
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .frame(width: thumbWidth, height: trackHeight)
                        .background(metric.tint, in: Capsule())
                        .position(x: thumbX, y: geo.size.height / 2)
                }
            }
            .frame(height: trackHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.name), \(metric.statusLabel), \(metric.valueText), \(metric.idealRangeText)")
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — PlantPipelineViewModel
//
// Runs the real PlantHealthDetector → PlantExplainer pipeline
// (the same calls used in PlantHealthTestView) and turns the
// result into a PlantCardData for PlantDetailView to render.
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantPipelineViewModel: ObservableObject {

    @Published private(set) var cardData: PlantCardData?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastDetectionLevel: AlertLevel?

    private let detector = PlantHealthDetector()
    private let explainer = PlantExplainer()

    /// Preview/testing only — injects mock data without touching the
    /// network or Foundation Model.
    func setPreviewData(_ cardData: PlantCardData) {
        self.cardData = cardData
    }

    /// Renders whatever was recorded on the last "Check conditions" tap,
    /// straight from the persisted profile fields — no network, no FM
    /// call. Leaves `cardData` nil if this plant has never been checked.
    func loadLastKnown(profile: PlantProfile, species: String, nickname: String, imageData: Data?) {
        guard let lastReadingAt = profile.lastReadingAt,
              let temperature = profile.lastTemperatureC,
              let humidity = profile.lastHumidityPercent,
              let soilMoisture = profile.lastSoilMoisturePercent,
              let lightIntensity = profile.lastLightLux
        else { return }

        let reading = SensorReading(
            timestamp: lastReadingAt, temperature: temperature, humidity: humidity,
            soilMoisture: soilMoisture, lightIntensity: lightIntensity
        )
        let metrics = SensorKind.allCases.map { $0.metric(reading: reading, thresholds: profile.thresholds()) }
        let level = profile.alertLevel
        let (mood, emoji) = Self.mood(for: level)

        lastDetectionLevel = level
        cardData = PlantCardData(
            species: species, nickname: nickname, imageData: imageData,
            mood: mood, moodEmoji: emoji,
            todaysMessage: level == .healthy ? "I'm feeling good today!" : "Something doesn't feel quite right today.",
            aiInsightTitle: "Last check-in",
            aiInsight: "Last checked \(lastReadingAt.formatted(.relative(presentation: .named))). Pull down or tap refresh for a fresh reading.",
            metrics: metrics,
            isGenuineInsight: false
        )
    }

    func refresh(
        reading: SensorReading,
        profile: PlantProfile,
        species: String,
        nickname: String,
        imageData: Data?
    ) async {
        isLoading = true
        errorMessage = nil

        let statuses = detector.assess(reading, for: profile)
        let detection = DetectionResult(timestamp: reading.timestamp, statuses: statuses)
        let metrics = SensorKind.allCases.map { $0.metric(reading: reading, thresholds: profile.thresholds()) }

        lastDetectionLevel = detection.overallLevel
        cardData = fallbackCard(
            for: detection.overallLevel, species: species, nickname: nickname,
            imageData: imageData, metrics: metrics
        )

        guard PlantExplainer.isAvailable() else {
            // A missing FM only means a less personal message — not
            // worth alarming the user over when the plant is fine.
            errorMessage = detection.isHealthy ? nil : (PlantExplainer.unavailableReason() ?? "Apple Intelligence unavailable.")
            isLoading = false
            return
        }

        do {
            let explanation = try await explainer.explain(reading: reading, detection: detection, species: species)
            let (mood, emoji) = Self.mood(for: detection.overallLevel)
            cardData = PlantCardData(
                species: species, nickname: nickname, imageData: imageData,
                mood: mood, moodEmoji: emoji,
                todaysMessage: explanation.plantMessage,
                aiInsightTitle: explanation.action,
                aiInsight: detection.isHealthy
                    ? "All readings are within the ideal range — keep up the current care routine."
                    : explanation.caretakerInsight,
                metrics: metrics
            )
        } catch {
            errorMessage = detection.isHealthy ? nil : error.localizedDescription
            cardData = fallbackCard(
                for: detection.overallLevel, species: species, nickname: nickname,
                imageData: imageData, metrics: metrics
            )
        }

        isLoading = false
    }

    private func fallbackCard(
        for level: AlertLevel, species: String, nickname: String,
        imageData: Data?, metrics: [PlantMetric]
    ) -> PlantCardData {
        let (mood, emoji) = Self.mood(for: level)
        let message = level == .healthy
            ? "I'm feeling good today!"
            : "Something doesn't feel quite right today."
        let insight = level == .healthy
            ? "All readings are within the ideal range — keep up the current care routine."
            : "Couldn't generate a detailed explanation right now, but at least one reading is outside the ideal range."
        return PlantCardData(
            species: species, nickname: nickname, imageData: imageData,
            mood: mood, moodEmoji: emoji,
            todaysMessage: message,
            aiInsightTitle: level == .healthy ? "Looking great!" : "Needs attention",
            aiInsight: insight,
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
            name: displayName,
            systemImage: icon,
            tint: tint,
            statusLabel: label,
            statusEmoji: emoji,
            valueText: formattedValue(value),
            idealRangeText: "Ideal \(formattedBound(range.lowerBound)) - \(formattedBound(range.upperBound))",
            progress: progress
        )
    }

    private var displayName: String {
        switch self {
        case .temperature: return "Temperature"
        case .humidity:     return "Humidity"
        case .soilMoisture: return "Moisture"
        case .light:        return "Light"
        }
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
        case .light:        return thresholds.lightPercentRange
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
        case .temperature: return AppTheme.Colors.sensorTemperature
        case .humidity:     return AppTheme.Colors.sensorHumidity
        case .soilMoisture: return AppTheme.Colors.sensorSoil
        case .light:        return AppTheme.Colors.sensorLight
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
        case .light: return String(format: "%.0f%%", value)
        }
    }

    private func formattedBound(_ value: Double) -> String {
        switch self {
        case .temperature: return String(format: "%.0f°C", value)
        case .humidity, .soilMoisture: return String(format: "%.0f%%", value)
        case .light: return String(format: "%.0f%%", value)
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
    var imageData: Data?
    var mood: String
    var moodEmoji: String
    var todaysMessage: String
    var aiInsightTitle: String
    var aiInsight: String
    var metrics: [PlantMetric]
    /// False for `loadLastKnown`'s templated placeholder text — the
    /// insight panel only shows once there's a genuine result from an
    /// actual check (or an honest "couldn't generate" fallback for one).
    var isGenuineInsight: Bool = true
}

struct PlantMetric: Identifiable {
    let id = UUID()
    var name: String
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
        )
    )
    container.mainContext.insert(monstera)

    return NavigationStack {
        PlantDetailView(profile: monstera)
    }
    .modelContainer(container)
}

// Renders the fully-loaded UI directly — no network fetch, no
// Foundation Model call — so the layout/theme can be checked on its
// own without either dependency being available.
#Preview("Mock data — no network/FM") {
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
        )
    )
    container.mainContext.insert(monstera)

    let mockMetrics = [
        PlantMetric(
            name: "Moisture", systemImage: "drop.fill", tint: AppTheme.Colors.sensorSoil,
            statusLabel: "Too dry", statusEmoji: "🥺",
            valueText: "10%", idealRangeText: "Ideal 50% - 80%", progress: 0.1
        ),
        PlantMetric(
            name: "Light", systemImage: "sun.max.fill", tint: AppTheme.Colors.sensorLight,
            statusLabel: "Perfect", statusEmoji: "🤩",
            valueText: "60%", idealRangeText: "Ideal 40% - 80%", progress: 0.6
        ),
        PlantMetric(
            name: "Temperature", systemImage: "thermometer", tint: AppTheme.Colors.sensorTemperature,
            statusLabel: "Too hot", statusEmoji: "🥵",
            valueText: "28°C", idealRangeText: "Ideal 18°C - 26°C", progress: 0.9
        ),
    ]

    let mockCardData = PlantCardData(
        species: monstera.name,
        nickname: monstera.nickname,
        imageData: nil,
        mood: "Stressed",
        moodEmoji: "😣",
        todaysMessage: "I'm so thirsty! My leaves are wilting a bit.",
        aiInsightTitle: "Water it soon",
        aiInsight: "Monstera's soil has been dry for a few days. Water it soon to help it bounce back.",
        metrics: mockMetrics
    )

    return NavigationStack {
        PlantDetailView(profile: monstera, previewCardData: mockCardData)
    }
    .modelContainer(container)
}
