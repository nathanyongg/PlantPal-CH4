import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — ConnectDeviceView
//
// Shown before the Add Plant form. Each plant needs its own
// dedicated sensor, so this is a short tutorial-style intro
// (mirroring the onboarding screens' mascot + bottom card look)
// that hands off to the same device-picker sheet used from the
// main screen's Bluetooth button — one picker, two entry points.
// ══════════════════════════════════════════════════════════════

struct ConnectDeviceView: View {

    /// Device IDs already linked to other plants — never offered here,
    /// since each device may only belong to one plant at a time.
    var excludedDeviceIDs: Set<String> = []
    var onDeviceSelected: (ESP32BLEManager.DiscoveredDevice) -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDevicePicker = false

    var body: some View {
        ZStack {
            AppBackground { Color.clear }
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Spacer(minLength: 8)

                mascotArea
                    .padding(.horizontal, 24)

                Spacer(minLength: 8)

                bottomCard
            }
        }
        .sheet(isPresented: $showingDevicePicker) {
            DevicePairingView(excludedDeviceIDs: excludedDeviceIDs) { device in
                showingDevicePicker = false
                onDeviceSelected(device)
            }
        }
    }

    // MARK: — Header

    private var header: some View {
        HStack {
            IconCircleButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                onCancel()
            }

            Spacer()

            Text("Connect")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
    }

    // MARK: — Mascot

    private var mascotArea: some View {
        Image("Mascot")
            .resizable()
            .scaledToFit()
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: — Bottom card

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Let's connect your device")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Make sure the PlantPal device is powered on and nearby.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingDevicePicker = true
            } label: {
                Text("Start Pairing")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.onboardingPanel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .background(.white, in: Capsule())
            .appOutline(Capsule(), colorScheme: colorScheme)
        }
        .padding(24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: AppTheme.Radius.xlarge,
                topTrailingRadius: AppTheme.Radius.xlarge,
                style: .continuous
            )
            .fill(AppTheme.Colors.onboardingPanel)
            .appOutline(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppTheme.Radius.xlarge,
                    topTrailingRadius: AppTheme.Radius.xlarge,
                    style: .continuous
                ),
                colorScheme: colorScheme,
                lineWidth: 2
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

#Preview {
    ConnectDeviceView(onDeviceSelected: { _ in }, onCancel: {})
}
