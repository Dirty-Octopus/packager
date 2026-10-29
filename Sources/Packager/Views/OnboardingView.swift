import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 30)

                BrandMark(size: 96)

                VStack(spacing: 9) {
                    Text(settings.language == .en ? "Choose your language" : "选择你的语言")
                        .font(.system(size: 32, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.primaryText)
                    Text(settings.language == .en ? "选择你的语言" : "Choose your language")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)

                    Text(settings.language == .en
                         ? "Packager will use this language across the app. You can change it later in Settings."
                         : "Packager 将使用此语言显示界面，之后可在设置中修改。")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                        .padding(.top, 4)
                }
                .padding(.top, 24)

                HStack(spacing: 14) {
                    LanguageCard(
                        code: "EN",
                        title: "English",
                        subtitle: "Continue in English",
                        action: { commit(.en) }
                    )
                    LanguageCard(
                        code: "中",
                        title: "简体中文",
                        subtitle: "使用中文界面",
                        action: { commit(.zhHans) }
                    )
                }
                .frame(maxWidth: 640)
                .padding(.top, 30)

                HStack(spacing: 7) {
                    Text(T("Inspect · Modernize · Repackage"))
                        .font(Theme.body(9.5, weight: .medium))
                        .tracking(0.4)
                    Text("·")
                    Text("pkgutil · pkgbuild")
                        .font(Theme.mono(9))
                }
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 26)

                Spacer(minLength: 26)

                HStack(spacing: 7) {
                    Text("Packager 1.0")
                    Text("·")
                    Link("GitHub", destination: URL(string: "https://github.com/Dirty-Octopus/packager")!)
                        .foregroundStyle(Theme.secondaryText)
                    Text("·")
                    Text("MIT")
                }
                .font(Theme.body(9))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commit(_ language: AppLanguage) {
        withAnimation(.easeInOut(duration: 0.25)) {
            settings.completeOnboarding(language: language)
        }
    }
}

private struct LanguageCard: View {
    let code: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Text(code)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Theme.gradient)
                    )
                    .shadow(color: Theme.accent.opacity(0.28), radius: 12, y: 6)

                VStack(spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(subtitle)
                        .font(Theme.body(10.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface.opacity(hovering ? 0.98 : 0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        hovering ? Theme.accent.opacity(0.42) : Theme.stroke,
                        lineWidth: hovering ? 1.6 : 1
                    )
            )
            .shadow(color: Theme.shadow, radius: hovering ? 20 : 12, y: 8)
            .scaleEffect(hovering ? 1.012 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.snappy(duration: 0.22)) {
                hovering = inside
            }
        }
    }
}
