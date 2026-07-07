//
//  AppTheme.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 02/07/26.
//


import SwiftUI

enum AppTheme {

    enum Colors {
        static let background = Color("AppBackground")
        static let backgroundMuted = Color("AppBackgroundMuted")
        static let surface = Color("AppSurface")
        static let surfaceElevated = Color("AppSurfaceElevated")
        static let textPrimary = Color("AppTextPrimary")
        static let textSecondary = Color("AppTextSecondary")
        static let border = Color("AppBorder")

        static let primaryAccent = Color("AppAccentWarm")
        static let secondaryAccent = Color("AppAccentLavender")

        static let success = Color("AppSuccess")
        static let warning = Color("AppWarning")
        static let critical = Color("AppCritical")

        static let lavenderPanel = Color("AppLavender")
        static let leafGreen = Color("AppLeafGreen")

        static let insightPanel = Color("AppInsightPanel")
        static let onboardingPanel = Color("AppOnboardingPanel")

        static let sensorTemperature = Color("AppSensorTemperature")
        static let sensorHumidity = Color("AppSensorHumidity")
        static let sensorSoil = Color("AppSensorSoil")
        static let sensorLight = Color("AppSensorLight")

        /// Solid CTA green used for onboarding's filled pill buttons
        /// (Skip, Get Started) and the device-pairing flow. Fixed rather
        /// than light/dark adaptive since these buttons stay a solid
        /// green regardless of scheme.
        static let onboardingAccent = Color(red: 0x87 / 255, green: 0xC1 / 255, blue: 0x7E / 255)

        /// Light mode is borderless — cards and buttons are told apart
        /// by fill and shadow alone. Dark mode still needs a visible
        /// edge (its surfaces sit close in value to the background),
        /// so it keeps a translucent white stroke.
        static func outline(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .white.opacity(0.35) : .clear
        }
    }

    enum Typography {
        static let screenTitle: Font = .system(.largeTitle, design: .rounded).weight(.heavy)
        static let sectionTitle: Font = .system(.title2, design: .rounded).weight(.bold)
        static let cardTitle: Font = .system(.headline, design: .rounded).weight(.semibold)
        static let body: Font = .system(.body, design: .rounded)
        static let subtitle: Font = .system(.subheadline, design: .rounded)
        static let caption: Font = .system(.caption, design: .rounded).weight(.medium)
        static let tiny: Font = .system(.caption2, design: .rounded).weight(.semibold)
    }

    enum Radius {
        static let xlarge: CGFloat = 32
        static let large: CGFloat = 28
        static let card: CGFloat = 24
        static let medium: CGFloat = 20
        static let small: CGFloat = 14
    }

    enum Spacing {
        static let page: CGFloat = 16
        static let card: CGFloat = 14
        static let section: CGFloat = 18
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Shared card outline
//
// The repeated `.overlay { Shape().stroke(outline(for:), lineWidth: 1.5) }`
// pattern, factored into one modifier so every card/button applies the
// exact same stroke instead of re-typing it at each call site.
// ══════════════════════════════════════════════════════════════

extension View {
    func appOutline<S: Shape>(_ shape: S, colorScheme: ColorScheme, lineWidth: CGFloat = 1.5) -> some View {
        overlay {
            shape.stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: lineWidth)
        }
    }
}