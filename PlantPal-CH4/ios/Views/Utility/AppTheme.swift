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

        /// The app's "outline theme" — a crisp border around cards and
        /// pill buttons. A plain black stroke only reads well against
        /// the light surfaces it was designed on; against this app's
        /// dark surfaces (`surface`, `background`) it disappears, so
        /// dark mode gets a translucent white stroke instead.
        static func outline(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .white.opacity(0.35) : .black
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
        static let large: CGFloat = 28
        static let medium: CGFloat = 20
        static let small: CGFloat = 14
    }

    enum Spacing {
        static let page: CGFloat = 16
        static let card: CGFloat = 14
        static let section: CGFloat = 18
    }
}