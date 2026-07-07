import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — OnboardingView
//
// Shown once on first launch. One persistent screen — background,
// header, and card all stay put — whose content (mascot, bubble,
// title) swaps as `currentPage` advances, driven only by the
// Next/Skip buttons (no swipe paging). The mascot goes from
// flat/neutral to happy as the pages progress, since that's the
// emotional pitch: your plant has feelings, and this app is how
// you hear them.
// ══════════════════════════════════════════════════════════════

struct OnboardingView: View {

    var onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    // 0 is the welcome splash; 1...pages.count map to pages[0...pages.count-1].
    @State private var currentPage = 0

    private let pages = OnboardingPage.all

    private var page: OnboardingPage { pages[currentPage - 1] }

    var body: some View {
        ZStack {
            AppBackground { Color.clear }
                .ignoresSafeArea()

            if currentPage == 0 {
                welcomeScreen
            } else {
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
        }
    }

    // MARK: — Welcome screen (first screen, no card chrome)

    private var welcomeScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            Image("Mascot")
                .resizable()
                .scaledToFit()
                .frame(height: 260)
                .accessibilityHidden(true)

            Spacer(minLength: 32)

            VStack(spacing: 8) {
                Text("PlantPal")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.onboardingAccent)

                Text("Connecting you with your plant")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)

            Spacer(minLength: 32)

            Button {
                advance()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .background(AppTheme.Colors.onboardingAccent, in: Capsule())

            pageDots(
                activeColor: AppTheme.Colors.onboardingAccent,
                inactiveColor: AppTheme.Colors.onboardingAccent.opacity(0.35),
                activeIndex: 0
            )
                .padding(.top, 16)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 32)
    }

    // MARK: — Header (persistent)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            backButton
                .opacity(currentPage > 1 ? 1 : 0)
                .disabled(currentPage == 1)
                .accessibilityHidden(currentPage == 1)

            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome to")
                    .font(AppTheme.Typography.subtitle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("PlantPal")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backButton: some View {
        IconCircleButton(
            systemImage: "chevron.left",
            accessibilityLabel: "Back to start",
            accessibilityHint: "Returns to the first onboarding screen"
        ) {
            withAnimation {
                currentPage = 1
            }
        }
    }

    // MARK: — Mascot (content swaps in place)

    private var mascotArea: some View {
        ZStack(alignment: .top) {
            Image(page.mascotImageName)
                .resizable()
                .scaledToFit()
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .id(page.mascotImageName)
                .transition(.opacity)
                .accessibilityHidden(true)

            if let bubble = page.speechBubble {
                speechBubble(bubble)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: 100, alignment: .top)
                    .offset(x: -12, y: 44)
                    .id(bubble)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPage)
    }

    private func speechBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .frame(maxWidth: 150, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(AppTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 16))
            .appOutline(RoundedRectangle(cornerRadius: 16), colorScheme: colorScheme)
            .fixedSize()
    }

    // MARK: — Bottom card (persistent container, content swaps)

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(page.title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(page.title)
                    .transition(.opacity)

                Text(page.subtitle)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .id(page.subtitle)
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                Button {
                    advance()
                } label: {
                    Text(isLastPage ? "Let's Start" : "Next")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.onboardingPanel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .background(.white, in: Capsule())
                .appOutline(Capsule(), colorScheme: colorScheme)

                // Always present (never removed from the layout) so the
                // card's height stays identical across all three pages —
                // only hidden on the last page, instead of disappearing,
                // to avoid the resize jump that caused a weird shifting
                // animation when advancing to "Let's Start".
                Button {
                    onComplete()
                } label: {
                    Text("Skip")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .background(AppTheme.Colors.onboardingAccent, in: Capsule())
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
                .accessibilityHidden(isLastPage)
            }

            pageDots(activeColor: .white, inactiveColor: .white.opacity(0.5), activeIndex: currentPage - 1)
                .frame(maxWidth: .infinity, alignment: .center)
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
        .animation(.easeInOut(duration: 0.3), value: currentPage)
    }

    private func pageDots(activeColor: Color, inactiveColor: Color, activeIndex: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == activeIndex ? activeColor : inactiveColor)
                    .frame(width: index == activeIndex ? 22 : 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var isLastPage: Bool {
        currentPage == pages.count
    }

    private func advance() {
        if isLastPage {
            onComplete()
        } else {
            withAnimation {
                currentPage += 1
            }
        }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — OnboardingPage
// ══════════════════════════════════════════════════════════════

private struct OnboardingPage {
    let mascotImageName: String
    let speechBubble: String?
    let title: String
    let subtitle: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            mascotImageName: "Mascot 2",
            speechBubble: nil,
            title: "Your houseplants\nhave feelings too.",
            subtitle: "Understand what your plants need through AI-powered conversations."
        ),
        OnboardingPage(
            mascotImageName: "Mascot 2",
            speechBubble: "Hii! 😊",
            title: "Listen to\nyour plant.",
            subtitle: "Real-time environmental data becomes emotions and messages."
        ),
        OnboardingPage(
            mascotImageName: "Mascot 2",
            speechBubble: "Thank you for caring for me this far 😊",
            title: "Become a better\nplant parent.",
            subtitle: "Build a real bond with your plant through daily check-ins and care."
        ),
    ]
}

#Preview {
    OnboardingView(onComplete: {})
}
