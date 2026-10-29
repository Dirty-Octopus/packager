import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            BrandMark(size: 72)
            Text("Packager")
                .font(.system(size: 33, weight: .semibold))
                .tracking(-1.0)
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 15)
            Text(T("Inspect, modernize, and repackage legacy macOS installers."))
                .font(Theme.body(14))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 5)
            Text(T("Unpacked in a private workspace, rebuilt as a clean XAR product."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 3)

            dropZone
                .frame(maxWidth: 620)
                .frame(height: 266)
                .padding(.top, 26)

            HStack(spacing: 10) {
                FeatureCard(
                    symbol: "eye.fill",
                    tint: Theme.info,
                    title: T("Inspect"),
                    text: T("Every component, script, and binary.")
                )
                FeatureCard(
                    symbol: "wand.and.stars",
                    tint: Theme.accent,
                    title: T("Modernize"),
                    text: T("Drop OS gates and relocatable flags.")
                )
                FeatureCard(
                    symbol: "shippingbox.fill",
                    tint: Theme.success,
                    title: T("Repackage"),
                    text: T("A fresh XAR product, saved locally.")
                )
            }
            .frame(maxWidth: 620)
            .padding(.top, 18)

            Spacer(minLength: 14)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8.5))
                Text(T("Nothing is installed — everything happens inside your Packager workspace."))
                    .font(Theme.body(9.5))
            }
            .foregroundStyle(Theme.tertiaryText)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 7) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        settings.toggleLanguage()
                    }
                } label: {
                    Text(settings.language.shortName)
                        .font(Theme.body(9.5, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 27, height: 25)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.surface.opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(settings.language == .en ? "切换到简体中文" : "Switch to English")

                Button {
                    NotificationCenter.default.post(name: .packagerOpenSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 27, height: 25)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.surface.opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(T("Open Settings"))
            }
            .padding(.top, 18)
            .padding(.trailing, 22)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface.opacity(hovering ? 0.94 : 0.74))

            if hovering {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.accent.opacity(0.04))
            }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.18), Theme.accent.opacity(0.07)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.bottom, 12)

                Text(T("Drop an installer here"))
                    .font(.system(size: 17.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.primaryText)

                Text(T("Flat .pkg · legacy .mpkg · bundle packages"))
                    .font(Theme.body(10.8))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, 4)

                Button {
                    model.openPackagePanel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text(T("Choose a package"))
                    }
                }
                .buttonStyle(SoftButtonStyle(height: 30, horizontalPadding: 13, prominent: true))
                .padding(.top, 16)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    hovering ? Theme.accent.opacity(0.55) : Theme.accent.opacity(0.26),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                )
        )
        .overlay(alignment: .topTrailing) {
            Text("⌘O")
                .font(Theme.mono(9, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.surfaceSunken)
                )
                .padding(14)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            model.openPackagePanel()
        }
        .onHover { value in
            withAnimation(.easeOut(duration: 0.18)) {
                hovering = value
            }
        }
        .shadow(color: hovering ? Theme.accent.opacity(0.13) : Color.clear, radius: 22, y: 8)
    }
}

struct FeatureCard: View {
    var symbol: String
    var tint: Color
    var title: String
    var text: String

    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: symbol, tint: tint, size: 29)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(text)
                    .font(Theme.body(9.4))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.strokeSoft, lineWidth: 1)
        )
    }
}
