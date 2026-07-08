import CoreBluetooth
import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — DevicePairingView
//
// Pair with a plant sensor over Bluetooth and hand it Wi-Fi
// credentials. Also doubles as the device picker for Add Plant —
// when `onSelect` is set, tapping a device just reports it back
// and dismisses instead of connecting, since linking a device to
// a new plant doesn't need a live connection or Wi-Fi yet.
// ══════════════════════════════════════════════════════════════

struct DevicePairingView: View {

    /// Devices already linked to another plant — hidden here so two
    /// plants can't end up sharing one sensor.
    var excludedDeviceIDs: Set<String> = []

    /// When set, the user can continue into Add Plant after Wi-Fi
    /// provisioning succeeds and the ESP32 reports its HTTP endpoint.
    var onSelect: ((ESP32BLEManager.DiscoveredDevice) -> Void)? = nil
    var onProvisioned: ((ESP32BLEManager.ProvisionedDevice) -> Void)? = nil

    @StateObject private var ble = ESP32BLEManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var ssid = ""
    @State private var password = ""

    /// `leafGreen`'s dark variant is nearly the same shade as the Wi-Fi
    /// form's own material background, so the labels disappear in dark
    /// mode — swap to a brighter green there, same as PlantSetupView.
    private var formLabelColor: Color {
        colorScheme == .dark ? AppTheme.Colors.success : AppTheme.Colors.leafGreen
    }

    private var isSelectionMode: Bool { onSelect != nil && onProvisioned == nil }

    private var visibleDevices: [ESP32BLEManager.DiscoveredDevice] {
        ble.discoveredDevices.filter { !excludedDeviceIDs.contains($0.id.uuidString) }
    }

    var body: some View {
        NavigationStack {
            AppBackground {
                content
            }
            .navigationTitle(isSelectionMode ? "Select Device" : "Plant Sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            if ble.phase == .disconnected {
                ble.startScanning()
            }
        }
        .onDisappear {
            ble.stopScanning()
        }
    }

    // MARK: — Top-level state

    @ViewBuilder
    private var content: some View {
        switch ble.bluetoothState {
        case .poweredOff:
            statusMessage(
                icon: "bolt.slash.fill",
                title: "Bluetooth Is Off",
                message: "Turn on Bluetooth to pair with your plant sensor."
            )
        case .unauthorized:
            statusMessage(
                icon: "hand.raised.fill",
                title: "Bluetooth Access Needed",
                message: "Allow Bluetooth access in Settings to pair with your plant sensor."
            )
        case .unsupported:
            statusMessage(
                icon: "exclamationmark.triangle.fill",
                title: "Bluetooth Unavailable",
                message: "This device doesn't support the Bluetooth connection PlantPal needs."
            )
        default:
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch ble.phase {
        case .disconnected, .scanning:
            deviceList

        case .connecting, .discoveringServices:
            statusMessage(
                icon: "antenna.radiowaves.left.and.right",
                title: "Connecting…",
                message: "Linking to \(ble.connectedDeviceName ?? "your sensor").",
                showsSpinner: true
            )

        case .readyToProvision:
            wifiForm

        case .sendingCredentials, .awaitingResult:
            provisioningProgressView

        case .provisioned:
            provisionedView

        case .failed(let message):
            failureView(message)
        }
    }

    // MARK: — Device list

    private var deviceList: some View {
        VStack(spacing: 20) {
            if visibleDevices.isEmpty {
                Spacer()
                ProgressView()
                Text("Looking for your plant sensor…")
                    .font(AppTheme.Typography.subtitle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text("Make sure it's powered on and nearby.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Spacer()
            } else {
                List(visibleDevices) { device in
                    Button {
                        if let onSelect {
                            onSelect(device)
                        } else {
                            ble.connect(to: device)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sensor.fill")
                                .foregroundStyle(AppTheme.Colors.leafGreen)

                            Text(device.name)
                                .foregroundStyle(AppTheme.Colors.textPrimary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .listRowBackground(AppTheme.Colors.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.top, 12)
    }

    // MARK: — Wi-Fi form

    private var wifiForm: some View {
        VStack(spacing: 20) {

            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.Colors.success)

                Text("Connected to \(ble.connectedDeviceName ?? "sensor")")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Live readings are coming over Bluetooth.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.top, 24)

            liveReadingCard

            VStack(spacing: 0) {
                HStack {
                    Text("Wi-Fi Name")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(formLabelColor)
                    Spacer()
                    TextField("Home Wi-Fi", text: $ssid)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityLabel("Wi-Fi network name")
                }

                Divider().padding(.vertical, 14)

                HStack {
                    Text("Password")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(formLabelColor)
                    Spacer()
                    SecureField("Required", text: $password)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityLabel("Wi-Fi password")
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))

            Button {
                ble.sendWiFiCredentials(ssid: ssid, password: password)
            } label: {
                Text("Connect to Wi-Fi")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.Colors.secondaryAccent)
            .disabled(ssid.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xlarge, style: .continuous)
                .fill(AppTheme.Colors.lavenderPanel)
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: — Live BLE reading

    @ViewBuilder
    private var liveReadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bluetooth Reading", systemImage: "dot.radiowaves.left.and.right")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                if ble.latestReading == nil {
                    ProgressView()
                }
            }

            if let reading = ble.latestReading {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    readingMetric("Temp", value: "\(Int(reading.temperature.rounded()))°C", icon: "thermometer")
                    readingMetric("Humidity", value: "\(Int(reading.humidity.rounded()))%", icon: "humidity.fill")
                    readingMetric("Soil", value: "\(Int(reading.soilMoisture.rounded()))%", icon: "drop.fill")
                    readingMetric("Light", value: "\(Int(reading.lightIntensity.rounded()))%", icon: "sun.max.fill")
                }

                Text("Updated \(reading.formattedTimestamp)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else if let error = ble.latestReadingError {
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.warning)
            } else {
                Text("Waiting for the ESP32 to send its first sensor packet.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding()
        .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
    }

    private func readingMetric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Colors.leafGreen)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(value)
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
    }

    // MARK: — Failure

    private var provisioningProgressView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()

            Image(systemName: "wifi")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text("Setting Up Wi-Fi…")
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Waiting for the sensor to join \"\(ssid)\". Use a 2.4 GHz Wi-Fi network, not the sensor's own PlantPal access point.")
                .font(AppTheme.Typography.subtitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Cancel") {
                ble.cancelProvisioning()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.warning)

            Text(message)
                .font(AppTheme.Typography.subtitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                ble.startScanning()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.Colors.secondaryAccent)

            Spacer()
            Spacer()
        }
    }

    private var provisionedView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.success)

            Text("Sensor Connected!")
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Your plant sensor is on Wi-Fi and ready to send readings to PlantPal.")
                .font(AppTheme.Typography.subtitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let url = ble.provisionedBaseURL {
                Text(url.absoluteString)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.Colors.surface, in: Capsule())
            }

            if let onProvisioned, let url = ble.provisionedBaseURL {
                Button {
                    onProvisioned(ESP32BLEManager.ProvisionedDevice(
                        id: ble.connectedPeripheralIdentifier ?? UUID(),
                        name: ble.connectedDeviceName ?? "Plant Sensor",
                        baseURL: url
                    ))
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(AppTheme.Colors.secondaryAccent)
                .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: — Generic status message

    private func statusMessage(
        icon: String,
        title: String,
        message: String,
        tint: Color = AppTheme.Colors.textSecondary,
        showsSpinner: Bool = false
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()

            if showsSpinner {
                ProgressView()
            }

            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(tint)

            Text(title)
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(message)
                .font(AppTheme.Typography.subtitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DevicePairingView()
}
