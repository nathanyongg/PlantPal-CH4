import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — PlantHealthTestView
//
// A test harness, not a production screen. Lets you punch in
// fake sensor values and run them through the real pipeline:
// PlantHealthDetector → PlantExplainer (Foundation Model) →
// notification content — all without needing the ESP32 or your
// cloud backend running.
//
// Wire this in as a tab, or push it from a hidden debug menu,
// during development. Pull it (or gate it behind #if DEBUG)
// before shipping.
// ══════════════════════════════════════════════════════════════

struct PlantHealthTestView: View {

    // MARK: — Sliders bound to fake sensor values

    @State private var temperature: Double    = 25
    @State private var humidity: Double       = 60
    @State private var soilMoisture: Double   = 45
    @State private var lightIntensity: Double = 18_000

    // MARK: — Pipeline state

    @State private var isRunning = false
    @State private var detection: DetectionResult?
    @State private var explanation: PlantExplanation?
    @State private var errorMessage: String?
    @State private var fmAvailable = true

    private let detector  = PlantHealthDetector()
    private let explainer = PlantExplainer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    if !fmAvailable {
                        availabilityWarning
                    }

                    sensorControls
                    presetButtons
                    runButton

                    if let detection {
                        detectorResultView(detection)
                    }

                    if let explanation {
                        explanationResultView(explanation)
                    }

                    if let errorMessage {
                        errorView(errorMessage)
                    }
                }
                .padding()
            }
            .navigationTitle("Foundation Model test")
            .task {
                fmAvailable = PlantExplainer.isAvailable()
            }
        }
    }

    // MARK: — Availability banner

    private var availabilityWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Apple Intelligence unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
            if let reason = PlantExplainer.unavailableReason() {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: — Sliders

    private var sensorControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sensor inputs")
                .font(.headline)

            sliderRow(
                label: "Temperature",
                value: $temperature,
                range: 10...40,
                unit: "°C",
                format: "%.1f"
            )
            sliderRow(
                label: "Humidity",
                value: $humidity,
                range: 0...100,
                unit: "%",
                format: "%.0f"
            )
            sliderRow(
                label: "Soil moisture",
                value: $soilMoisture,
                range: 0...100,
                unit: "%",
                format: "%.0f"
            )
            sliderRow(
                label: "Light intensity",
                value: $lightIntensity,
                range: 0...35_000,
                unit: " lux",
                format: "%.0f"
            )
        }
    }

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "\(format)\(unit)", value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: — Presets — quick scenarios so you don't have to
    // hand-tune sliders for every test pass

    private var presetButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick scenarios")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    presetChip("Healthy", color: .green) {
                        temperature = 24; humidity = 60
                        soilMoisture = 50; lightIntensity = 18_000
                    }
                    presetChip("Dry soil", color: .orange) {
                        temperature = 26; humidity = 55
                        soilMoisture = 12; lightIntensity = 17_000
                    }
                    presetChip("Overwatered", color: .blue) {
                        temperature = 22; humidity = 70
                        soilMoisture = 92; lightIntensity = 16_000
                    }
                    presetChip("Heat stress", color: .red) {
                        temperature = 38; humidity = 30
                        soilMoisture = 40; lightIntensity = 26_000
                    }
                    presetChip("Too dark", color: .purple) {
                        temperature = 23; humidity = 58
                        soilMoisture = 48; lightIntensity = 3_000
                    }
                    presetChip("Multiple issues", color: .red) {
                        temperature = 36; humidity = 28
                        soilMoisture = 15; lightIntensity = 4_000
                    }
                }
            }
        }
    }

    private func presetChip(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: — Run button

    private var runButton: some View {
        Button {
            Task { await runPipeline() }
        } label: {
            HStack {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isRunning ? "Running…" : "Run pipeline")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.tint, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .disabled(isRunning)
    }

    // MARK: — Detector result

    private func detectorResultView(_ detection: DetectionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("1. Detector verdict")
                    .font(.headline)
                Spacer()
                levelBadge(detection.overallLevel)
            }

            ForEach(detection.statuses) { status in
                HStack {
                    Circle()
                        .fill(color(for: status.level))
                        .frame(width: 8, height: 8)
                    Text(status.name)
                        .font(.subheadline)
                    Spacer()
                    Text(status.formattedValue)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: — Foundation Model result

    private func explanationResultView(_ explanation: PlantExplanation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("2. Foundation Model explanation")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                labeledText("Notification title", explanation.notificationTitle)
                labeledText("Cause", explanation.cause)
                labeledText("Action", explanation.action)
                labeledText("Urgency", explanation.urgency)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Rendered notification")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(explanation.notificationTitle)
                        .font(.subheadline.bold())
                    Text(explanation.notificationBody)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func labeledText(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    // MARK: — Error display

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Pipeline error", systemImage: "xmark.octagon.fill")
                .font(.subheadline.bold())
            Text(message)
                .font(.caption)
        }
        .foregroundStyle(.red)
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: — Helpers

    private func levelBadge(_ level: AlertLevel) -> some View {
        Text(label(for: level))
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color(for: level).opacity(0.15), in: Capsule())
            .foregroundStyle(color(for: level))
    }

    private func label(for level: AlertLevel) -> String {
        switch level {
        case .healthy:  return "Healthy"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }

    private func color(for level: AlertLevel) -> Color {
        switch level {
        case .healthy:  return .green
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    // MARK: — Pipeline execution

    private func runPipeline() async {
        isRunning = true
        detection = nil
        explanation = nil
        errorMessage = nil

        let reading = SensorReading(
            timestamp: Date(),
            temperature: temperature,
            humidity: humidity,
            soilMoisture: soilMoisture,
            lightIntensity: lightIntensity
        )

        let statuses = detector.assess(reading)
        let result = DetectionResult(timestamp: reading.timestamp, statuses: statuses)
        detection = result

        guard !result.isHealthy else {
            isRunning = false
            return  // healthy — FM is intentionally not called, same as production behavior
        }

        guard PlantExplainer.isAvailable() else {
            errorMessage = PlantExplainer.unavailableReason() ?? "Apple Intelligence unavailable."
            isRunning = false
            return
        }

        do {
            explanation = try await explainer.explain(reading: reading, detection: result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }
}

// MARK: — Preview

#Preview {
    PlantHealthTestView()
}
