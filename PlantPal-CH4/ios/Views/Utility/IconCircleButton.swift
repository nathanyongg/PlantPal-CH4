import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — IconCircleButton
//
// The 40x40 circular icon button (surface fill + themed outline) used
// for back/add/settings/refresh/delete affordances across the app —
// previously duplicated verbatim at every call site.
// ══════════════════════════════════════════════════════════════

struct IconCircleButton: View {
    let systemImage: String
    var tint: Color = AppTheme.Colors.textPrimary
    let accessibilityLabel: LocalizedStringKey
    var accessibilityHint: LocalizedStringKey? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(AppTheme.Colors.surface, in: Circle())
                .appOutline(Circle(), colorScheme: colorScheme)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalAccessibilityHint(hint: accessibilityHint))
    }
}

private struct OptionalAccessibilityHint: ViewModifier {
    let hint: LocalizedStringKey?

    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

// MARK: — Pressed-state feedback
//
// `.buttonStyle(.plain)` gives none by default, so buttons felt
// unresponsive when tapped — a slight scale/opacity dip on press.
// Shared so every button in the app gets the same feel instead of
// each view defining its own copy.

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
