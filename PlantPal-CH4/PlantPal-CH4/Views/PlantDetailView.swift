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

    var onAskMore: (() -> Void)? = nil

    /// Preview/testing only — when set, skips the network fetch and
    /// the Foundation Model call entirely and renders this data
    /// directly, so the UI can be checked without either dependency.
    var previewCardData: PlantCardData? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel = PlantPipelineViewModel()

    @State private var isChecking = false
    @State private var checkErrorMessage: String?
    @State private var showingLog = false

    var body: some View {
        mainContent
            .background(AppBackground { Color.clear })
            .ignoresSafeArea(edges: .bottom)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLog) {
                PlantHealthLogView(profile: profile)
            }
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
            let freshReading = try await PlantDataService().fetchLatestReading()
            await viewModel.refresh(
                reading: freshReading,
                profile: profile,
                species: profile.name,
                nickname: profile.nickname,
                imageData: profile.imageData
            )
            recordCheckIn(reading: freshReading)
        } catch {
            checkErrorMessage = error.localizedDescription
        }
        isChecking = false
    }

    // MARK: — Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    header
                    photoAndMoodRow

                    if let plant = viewModel.cardData {
                        metricsRow(plant)
                    }

                    checkConditionsButton

                    if let checkErrorMessage {
                        errorBanner(checkErrorMessage)
                    } else if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 140) // room for the insight panel
            }
            .refreshable {
                await performCheck()
            }

            Color.clear.frame(height: 0)
        }
        .overlay(alignment: .bottom) {
            // Only a genuine result (from an actual check, not the
            // "last known" placeholder) earns the "AI insight" label —
            // it slides up from below once the Foundation Model
            // actually finishes, rather than appearing instantly with
            // stale/templated text.
            if let plant = viewModel.cardData, plant.isGenuineInsight {
                insightPanel(plant)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.cardData?.isGenuineInsight)
    }

    // MARK: — Check conditions button

    private var checkConditionsButton: some View {
        Button {
            Task { await performCheck() }
        } label: {
            HStack(spacing: 10) {
                if isChecking {
                    ProgressView()
                } else {
                    Image(systemName: "magnifyingglass")
                }
                Text(isChecking ? "Checking…" : "Check conditions")
                    .font(AppTheme.Typography.cardTitle)
            }
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(PressableButtonStyle())
        .background(AppTheme.Colors.surface, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .disabled(isChecking || previewCardData != nil)
        .accessibilityLabel("Check conditions")
        .accessibilityHint("Reads the sensor now and records today's check-in")
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
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.Colors.surface, in: Circle())
                    .overlay {
                        Circle().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Back")

            Spacer()

            Button {
                showingLog = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.Colors.surface, in: Circle())
                    .overlay {
                        Circle().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Today's log")
            .accessibilityHint("Shows readings recorded for this plant today")
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
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
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
        .overlay {
            Capsule().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
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
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
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
                .foregroundStyle(AppTheme.Colors.warning)
            Text(message)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(12)
        .background(AppTheme.Colors.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
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
                    Button {
                        onAskMore?()
                    } label: {
                        Text("Ask more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(18)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(
            AppTheme.Colors.insightPanel
                .clipShape(RoundedCorner(radius: 34, corners: [.topLeft, .topRight]))
                .overlay {
                    RoundedCorner(radius: 34, corners: [.topLeft, .topRight])
                        .stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                }
        )
    }
}

// MARK: — Pressed-state feedback
//
// `.buttonStyle(.plain)` gives none by default, so these buttons felt
// unresponsive when tapped — a slight scale/opacity dip on press.

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
                    .foregroundStyle(AppTheme.Colors.textPrimary)
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
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ProgressTrack(progress: metric.progress, tint: metric.tint)
                .frame(height: 5)
        }
        .padding(.top, 30)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // No outline here — the icon badge intentionally overlaps the
        // top edge, and a full-perimeter stroke cuts an ugly line right
        // across it. The shadow alone gives the card enough definition.
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.statusLabel), \(metric.valueText), \(metric.idealRangeText)")
    }
}

private struct ProgressTrack: View {
    let progress: Double // 0...1
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.Colors.border)
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
            aiInsight: "Last checked \(lastReadingAt.formatted(.relative(presentation: .named))). Tap \u{201C}Check conditions\u{201D} for a fresh reading.",
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

        guard PlantExplainer.isAvailable() else {
            // A missing FM only means a less personal message — not
            // worth alarming the user over when the plant is fine.
            errorMessage = detection.isHealthy ? nil : (PlantExplainer.unavailableReason() ?? "Apple Intelligence unavailable.")
            cardData = fallbackCard(
                for: detection.overallLevel, species: species, nickname: nickname,
                imageData: imageData, metrics: metrics
            )
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
    var imageData: Data?
    var mood: String
    var moodEmoji: String
    var todaysMessage: String
    var aiInsight: String
    var metrics: [PlantMetric]
    /// False for `loadLastKnown`'s templated placeholder text — the
    /// insight panel only shows once there's a genuine result from an
    /// actual check (or an honest "couldn't generate" fallback for one).
    var isGenuineInsight: Bool = true
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
            minLightLux: 10_000, maxLightLux: 25_000
        )
    )
    container.mainContext.insert(monstera)

    let mockMetrics = [
        PlantMetric(
            systemImage: "drop.fill", tint: AppTheme.Colors.sensorSoil,
            statusLabel: "Too dry", statusEmoji: "🥺",
            valueText: "10%", idealRangeText: "Ideal 50% - 80%", progress: 0.1
        ),
        PlantMetric(
            systemImage: "sun.max.fill", tint: AppTheme.Colors.sensorLight,
            statusLabel: "Perfect", statusEmoji: "🤩",
            valueText: "60%", idealRangeText: "Ideal 40% - 80%", progress: 0.6
        ),
        PlantMetric(
            systemImage: "thermometer", tint: AppTheme.Colors.sensorTemperature,
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
        aiInsight: "Monstera's soil has been dry for a few days. Water it soon to help it bounce back.",
        metrics: mockMetrics
    )

    return NavigationStack {
        PlantDetailView(profile: monstera, previewCardData: mockCardData)
    }
    .modelContainer(container)
}

