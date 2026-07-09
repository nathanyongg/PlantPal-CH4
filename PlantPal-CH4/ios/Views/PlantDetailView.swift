import SwiftData
import SwiftUI
internal import Combine

private enum SensorReadingPath: Equatable {
    case notChecked
    case wifi
    case bluetoothFallback(String)
    case failed(String)
}

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
    
    var previewReading: SensorReading? = nil

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
    @State private var isSensorDetailsExpanded = false
    @State private var sensorReadingPath: SensorReadingPath = .notChecked

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
            .task {
                await runLiveSensorUpdates()
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
            sensorReadingPath = .wifi
            render(reading: freshReading, shouldRecord: true)
        } catch {
            if let bleReading = ble.latestReading, bleReading.isValid {
                sensorReadingPath = .bluetoothFallback(error.localizedDescription)
                render(reading: bleReading, shouldRecord: true)
                checkErrorMessage = "Wi-Fi is not reachable right now, so PlantPal fell back to the latest Bluetooth sensor reading."
            } else {
                sensorReadingPath = .failed(error.localizedDescription)
                checkErrorMessage = error.localizedDescription
            }
        }
        isChecking = false
    }

    private func runLiveSensorUpdates() async {
        guard previewCardData == nil else { return }

        while !Task.isCancelled {
            await refreshLiveReading()
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    private func refreshLiveReading() async {
        do {
            let freshReading = try await fetchLatestReading(timeout: 1)
            sensorReadingPath = .wifi
            await applyLiveReading(freshReading)
        } catch {
            if let bleReading = ble.latestReading, bleReading.isValid {
                sensorReadingPath = .bluetoothFallback(error.localizedDescription)
                await applyLiveReading(bleReading)
            } else if viewModel.cardData == nil {
                sensorReadingPath = .failed(error.localizedDescription)
            }
        }
    }

    private func fetchLatestReading(timeout: TimeInterval = 6) async throws -> SensorReading {
        try await PlantDataService(profile: profile, timeout: timeout).fetchLatestReading()
    }

    private func render(reading: SensorReading, shouldRecord: Bool) {
        guard reading.isValid else {
            checkErrorMessage = PlantDataServiceError.invalidReading.localizedDescription
            return
        }

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

    private func applyLiveReading(_ reading: SensorReading) async {
        guard reading.isValid else { return }

        viewModel.applyLiveReading(
            reading: reading,
            profile: profile,
            species: profile.name,
            nickname: profile.nickname,
            imageData: profile.imageData
        )
        updateLastKnownReading(reading: reading)
    }

    // MARK: — Main content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                topBar
                photoAndSpeciesColumn

                // Shows as soon as a check starts and remains visible
                // for the last known card data, so the insight area does
                // not disappear between fresh sensor checks.
                if isChecking || viewModel.cardData != nil {
                    insightPanel(viewModel.cardData)
                }

                sensorDeviceCard

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
            .padding(.top, 12)
            .padding(.bottom, 40)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isChecking)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.cardData != nil)
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: isSensorDetailsExpanded)
        }
        .refreshable {
            await performCheck()
        }
        .onChange(of: isSensorDetailsExpanded) { _, isExpanded in
            if isExpanded {
                ble.refreshSignalStrength()
            }
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

        updateLastKnownReading(reading: reading, status: status)
    }

    private func updateLastKnownReading(reading: SensorReading, status: String? = nil) {
        let level = viewModel.lastDetectionLevel ?? .healthy
        profile.lastReadingAt = reading.timestamp
        profile.lastStatus = status ?? (level == .critical ? "critical" : level == .warning ? "warning" : "healthy")
        profile.lastTemperatureC = reading.temperature
        profile.lastHumidityPercent = reading.humidity
        profile.lastSoilMoisturePercent = reading.soilMoisture
        profile.lastLightLux = reading.lightIntensity

        do {
            try modelContext.save()
            Task {
                try? await FirestoreService.shared.uploadPlant(profile)
                try? await FirestoreService.shared.uploadHealthLog(entry, for: profile)
            }
        } catch {
            print("Failed to save check-in:", error)
        }
    }

    // MARK: — Top bar (back, centered nickname, refresh)

    private var topBar: some View {
        HStack {
            IconCircleButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                dismiss()
            }

            Spacer()

            Text(profile.nickname)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button {
                Task { await performCheck() }
            } label: {
                Image(systemName: "arrow.trianglehead.counterclockwise")
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

    // MARK: — Photo (centered, mood badge on the corner) + species name

    private var photoAndSpeciesColumn: some View {
        VStack(spacing: 10) {
            plantPhoto
                .frame(width: 160, height: 220)
                .overlay(alignment: .bottom) {
                    if let plant = viewModel.cardData {
                        moodPill(plant)
                    }
                }

            Text(profile.name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(6)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: 20, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 5)
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
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(AppTheme.Colors.surface, in: Capsule())
        .appOutline(Capsule(), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }

    // MARK: — Sensor device card

    private var sensorDeviceCard: some View {
        DisclosureGroup(isExpanded: $isSensorDetailsExpanded) {
            VStack(spacing: 12) {
                Divider()

                sensorDetailRow(
                    icon: "wifi",
                    title: "Wi-Fi",
                    value: wifiDetailText,
                    tint: wifiDetailTint
                )

                sensorDetailRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Bluetooth",
                    value: bluetoothDetailText,
                    tint: bluetoothDetailTint
                )

                sensorDetailRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Reading path",
                    value: readingPathDetailText,
                    tint: readingPathTint
                )

                if let baseURLText = sensorBaseURLText {
                    sensorDetailRow(
                        icon: "link",
                        title: "Endpoint",
                        value: baseURLText,
                        tint: AppTheme.Colors.textSecondary
                    )
                }
            }
            .padding(.top, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: sensorCardIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.Colors.textSecondary.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(sensorDeviceName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(signalText)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)
            }
        }
        .tint(AppTheme.Colors.textPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: 12, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
        .padding(.top, 4)
        .accessibilityLabel("Sensor connection")
        .accessibilityValue(signalText)
        .accessibilityHint("Shows Wi-Fi and Bluetooth signal details")
    }

    private func sensorDetailRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 190, alignment: .trailing)
        }
    }

    private var sensorDeviceName: String {
        profile.linkedDeviceName ?? ble.connectedDeviceName ?? "PlantPal Sensor"
    }

    private var sensorCardIcon: String {
        switch sensorReadingPath {
        case .bluetoothFallback:
            return "antenna.radiowaves.left.and.right"
        default:
            return "wifi"
        }
    }

    private var signalText: String {
        switch sensorReadingPath {
        case .wifi:
            return "Wi-Fi Connected"
        case .bluetoothFallback:
            return "Bluetooth Fallback"
        case .failed:
            return "Not connected"
        case .notChecked:
            if profile.sensorBaseURL != nil {
                return "Wi-Fi ready"
            }
            if ble.latestReading != nil {
                return "Bluetooth Available"
            }
            return "Not connected"
        }
    }

    private var wifiDetailText: String {
        switch sensorReadingPath {
        case .wifi:
            return "Reachable"
        case .bluetoothFallback:
            return "Unavailable"
        case .failed:
            return "Unavailable"
        case .notChecked:
            return profile.sensorBaseURL == nil ? "Not configured" : "Configured"
        }
    }

    private var wifiDetailTint: Color {
        switch sensorReadingPath {
        case .wifi:
            return AppTheme.Colors.success
        case .bluetoothFallback, .failed:
            return AppTheme.Colors.warning
        case .notChecked:
            return profile.sensorBaseURL == nil ? AppTheme.Colors.textSecondary : AppTheme.Colors.success
        }
    }

    private var bluetoothDetailText: String {
        if let rssi = ble.connectedRSSI {
            return "\(bluetoothSignalQuality(for: rssi)) (\(rssi) dBm)"
        }
        if ble.latestReading != nil {
            return "Reading available"
        }
        if ble.connectedDeviceName != nil {
            return "Connected"
        }
        return "Unavailable"
    }

    private var bluetoothDetailTint: Color {
        if ble.connectedRSSI != nil || ble.latestReading != nil || ble.connectedDeviceName != nil {
            return AppTheme.Colors.success
        }
        return AppTheme.Colors.textSecondary
    }

    private var readingPathDetailText: String {
        switch sensorReadingPath {
        case .wifi:
            return "Latest reading came from Wi-Fi."
        case .bluetoothFallback:
            return "Wi-Fi failed; using Bluetooth reading."
        case .failed(let message):
            return message
        case .notChecked:
            return profile.sensorBaseURL == nil
                ? "Wi-Fi not configured; Bluetooth will be used if available."
                : "Wi-Fi will be checked first."
        }
    }

    private var readingPathTint: Color {
        switch sensorReadingPath {
        case .wifi:
            return AppTheme.Colors.success
        case .bluetoothFallback:
            return AppTheme.Colors.warning
        case .failed:
            return AppTheme.Colors.critical
        case .notChecked:
            return AppTheme.Colors.textSecondary
        }
    }

    private var sensorBaseURLText: String? {
        guard let sensorBaseURL = profile.sensorBaseURL else { return nil }
        return URL(string: sensorBaseURL)?.host ?? sensorBaseURL
    }

    private func bluetoothSignalQuality(for rssi: Int) -> String {
        if rssi >= -60 {
            return "Strong"
        } else if rssi >= -75 {
            return "Fair"
        } else {
            return "Weak"
        }
    }

    // MARK: — Metric rows

    private var lastMetricUpdateText: String {
        guard let lastReadingAt = profile.lastReadingAt else {
            return "Updates after the next reading"
        }

        if lastReadingAt > Date().addingTimeInterval(60) {
            return "Waiting for live sensor time"
        }

        return "Updated \(lastReadingAt.formatted(.relative(presentation: .named)))"
    }

    private func metricsRow(_ plant: PlantCardData) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conditions")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(lastMetricUpdateText)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            ForEach(plant.metrics) { metric in
                MetricRow(metric: metric)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: 16, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 7)
        .padding(.top, 4)
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
        .background(insightBackgroundColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .appOutline(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous), colorScheme: colorScheme)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
    }

    /// Critical/endangered readings get a red insight panel instead of
    /// the default tone, so the most urgent state is unmissable at a
    /// glance — everything else (healthy, warning, no reading yet)
    /// keeps the standard panel color.
    private var insightBackgroundColor: Color {
        viewModel.lastDetectionLevel == .critical ? AppTheme.Colors.critical : AppTheme.Colors.insightPanel
    }
}

// MARK: — Metric row

private struct MetricRow: View {
    let metric: PlantMetric

    private let thumbWidth: CGFloat = 42
    private let thumbHeight: CGFloat = 22
    private let trackHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.name)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text(metric.statusLabel)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(metric.statusEmoji)
                        .font(.system(size: 17))
                }
            }

            Text(metric.idealRangeText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 34)

            GeometryReader { geo in
                let valueProgress = min(max(metric.progress, 0), 1)
                let lowerProgress = min(max(metric.idealLowerProgress, 0), 1)
                let upperProgress = min(max(metric.idealUpperProgress, 0), 1)
                let availableWidth = max(geo.size.width - thumbWidth, 1)
                let thumbX = thumbWidth / 2 + availableWidth * valueProgress
                let idealStart = thumbWidth / 2 + availableWidth * min(lowerProgress, upperProgress)
                let idealEnd = thumbWidth / 2 + availableWidth * max(lowerProgress, upperProgress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.border.opacity(0.9))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(metric.tint.opacity(0.92))
                        .frame(width: max(thumbWidth * 0.45, idealEnd - idealStart), height: trackHeight)
                        .offset(x: idealStart)

                    Text(metric.valueText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .background(metric.tint, in: Capsule())
                        .position(x: thumbX, y: geo.size.height / 2)
                }
                .frame(height: geo.size.height, alignment: .bottom)
            }
            .frame(height: 30)
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

    func applyLiveReading(
        reading: SensorReading,
        profile: PlantProfile,
        species: String,
        nickname: String,
        imageData: Data?
    ) {
        let statuses = detector.assess(reading, for: profile)
        let detection = DetectionResult(timestamp: reading.timestamp, statuses: statuses)
        let metrics = SensorKind.allCases.map { $0.metric(reading: reading, thresholds: profile.thresholds()) }
        let (mood, emoji) = Self.mood(for: detection.overallLevel)

        lastDetectionLevel = detection.overallLevel

        guard var currentCardData = cardData else {
            cardData = fallbackCard(
                for: detection.overallLevel,
                species: species,
                nickname: nickname,
                imageData: imageData,
                metrics: metrics
            )
            return
        }

        currentCardData.species = species
        currentCardData.nickname = nickname
        currentCardData.imageData = imageData
        currentCardData.mood = mood
        currentCardData.moodEmoji = emoji
        currentCardData.metrics = metrics

        if !currentCardData.isGenuineInsight {
            currentCardData.todaysMessage = detection.isHealthy
                ? "I'm feeling good today!"
                : "Something doesn't feel quite right today."
            currentCardData.aiInsightTitle = detection.isHealthy ? "Looking great!" : "Needs attention"
            currentCardData.aiInsight = detection.isHealthy
                ? "Live readings are within the ideal range."
                : "A live sensor reading is outside the ideal range."
        }

        cardData = currentCardData
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
    case light, temperature, humidity, soilMoisture

    func metric(reading: SensorReading, thresholds: PlantThresholds) -> PlantMetric {
        let range = idealRange(thresholds: thresholds)
        let value = rawValue(reading: reading)
        let (label, emoji) = statusLabel(value: value, range: range)

        return PlantMetric(
            name: displayName,
            systemImage: icon,
            tint: tint,
            statusLabel: label,
            statusEmoji: emoji,
            valueText: formattedValue(value),
            idealRangeText: "Ideal \(formattedBound(range.lowerBound)) - \(formattedBound(range.upperBound))",
            progress: progress(for: value),
            idealLowerProgress: progress(for: range.lowerBound),
            idealUpperProgress: progress(for: range.upperBound)
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
            case .temperature: return ("Too Cold", "🥶")
            case .humidity:     return ("Too Dry", "😖")
            case .soilMoisture: return ("Too Dry", "😖")
            case .light:        return ("Too Dark", "😴")
            }
        } else if value > range.upperBound {
            switch self {
            case .temperature: return ("Too Hot", "🥵")
            case .humidity:     return ("Too Humid", "💦")
            case .soilMoisture: return ("Too Much", "😧")
            case .light:        return ("Too Bright", "🔆")
            }
        } else {
            return ("Perfect", "🤩")
        }
    }

    private func formattedValue(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private func formattedBound(_ value: Double) -> String {
        switch self {
        case .temperature: return String(format: "%.0f°C", value)
        case .humidity, .soilMoisture: return String(format: "%.0f%%", value)
        case .light: return String(format: "%.0f%%", value)
        }
    }

    private func progress(for value: Double) -> Double {
        switch self {
        case .temperature:
            return min(max((value - 0) / 50, 0), 1)
        case .humidity, .soilMoisture, .light:
            return min(max(value / 100, 0), 1)
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
    var idealLowerProgress: Double
    var idealUpperProgress: Double
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
        PlantDetailView(
            profile: monstera,
                previewReading: SensorReading(
                    timestamp: .now,
                    temperature: 27,
                    humidity: 60,
                    soilMoisture: 1,
                    lightIntensity: 18_000
                )
        )
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
            name: "Light", systemImage: "sun.max.fill", tint: AppTheme.Colors.sensorLight,
            statusLabel: "Perfect", statusEmoji: "🤩",
            valueText: "75", idealRangeText: "Ideal 70% - 80%", progress: 0.75,
            idealLowerProgress: 0.7, idealUpperProgress: 0.8
        ),
        PlantMetric(
            name: "Temperature", systemImage: "thermometer", tint: AppTheme.Colors.sensorTemperature,
            statusLabel: "Too Cold", statusEmoji: "🥶",
            valueText: "18", idealRangeText: "Ideal 20°C - 26°C", progress: 0.36,
            idealLowerProgress: 0.4, idealUpperProgress: 0.52
        ),
        PlantMetric(
            name: "Humidity", systemImage: "humidity.fill", tint: AppTheme.Colors.sensorHumidity,
            statusLabel: "Too Dry", statusEmoji: "😖",
            valueText: "40", idealRangeText: "Ideal 70% - 80%", progress: 0.4,
            idealLowerProgress: 0.7, idealUpperProgress: 0.8
        ),
        PlantMetric(
            name: "Moisture", systemImage: "drop.fill", tint: AppTheme.Colors.sensorSoil,
            statusLabel: "Too Much", statusEmoji: "😧",
            valueText: "90", idealRangeText: "Ideal 50% - 80%", progress: 0.9,
            idealLowerProgress: 0.5, idealUpperProgress: 0.8
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
