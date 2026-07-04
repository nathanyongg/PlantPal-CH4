import CoreBluetooth
import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — DevicePairingView
//
// Pair with the shared plant sensor over Bluetooth and hand it
// Wi-Fi credentials. One device for every plant — this screen is
// device setup, not per-plant setup, so it lives in Settings.
// ══════════════════════════════════════════════════════════════

struct DevicePairingView: View {

    @StateObject private var ble = ESP32BLEManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var ssid = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            AppBackground {
                content
            }
            .navigationTitle("Plant Sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
            statusMessage(
                icon: "wifi",
                title: "Setting Up Wi-Fi…",
                message: "Waiting for the sensor to join \"\(ssid)\".",
                showsSpinner: true
            )

        case .provisioned:
            statusMessage(
                icon: "checkmark.circle.fill",
                title: "Sensor Connected!",
                message: "Your plant sensor is on Wi-Fi and ready to take readings.",
                tint: AppTheme.Colors.success
            )

        case .failed(let message):
            failureView(message)
        }
    }

    // MARK: — Device list

    private var deviceList: some View {
        VStack(spacing: 20) {
            if ble.discoveredDevices.isEmpty {
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
                List(ble.discoveredDevices) { device in
                    Button {
                        ble.connect(to: device)
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
            }
            .padding(.top, 24)

            VStack(spacing: 0) {
                HStack {
                    Text("Wi-Fi Name")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.leafGreen)
                    Spacer()
                    TextField("Home Wi-Fi", text: $ssid)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Wi-Fi network name")
                }

                Divider().padding(.vertical, 14)

                HStack {
                    Text("Password")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.leafGreen)
                    Spacer()
                    SecureField("Required", text: $password)
                        .multilineTextAlignment(.trailing)
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
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppTheme.Colors.lavenderPanel)
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: — Failure

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
