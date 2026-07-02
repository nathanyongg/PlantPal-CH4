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