import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        languageCard
                        sizeCard
                        appearanceCard
                        workspaceCard
                        aboutCard
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: 560, height: 700)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(T("Settings"))
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.primaryText)
                Text("Packager \(version)")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.surfaceMuted))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Language

    private var languageCard: some View {
        section(
            title: T("Interface language"),
            subtitle: T("Changes apply immediately.")
        ) {
            HStack(spacing: 9) {
                languageOption(.en)
                languageOption(.zhHans)
            }
        }
    }

    private func languageOption(_ language: AppLanguage) -> some View {
        let selected = settings.language == language
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                settings.language = language
            }
        } label: {
            HStack(spacing: 9) {
                Text(language.shortName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? .white : Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.accentSoft))
                    )
                Text(language.displayName)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Theme.accentSoft : Theme.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Theme.accentLine : Theme.strokeSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Size

    private var sizeCard: some View {
        section(
            title: T("Interface size"),
            subtitle: T("Choose a window preset. You can also resize the window freely.")
        ) {
            VStack(spacing: 6) {
                ForEach(WindowPreset.allCases) { preset in
                    sizeRow(preset)
                }
            }
        }
    }

    private func sizeRow(_ preset: WindowPreset) -> some View {
        let selected = settings.windowPreset == preset
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                settings.windowPreset = preset
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .frame(width: 28, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? Theme.accentSoft : Theme.surfaceSunken)
                    )
                Text(preset.title)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(preset.sizeText)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.tertiaryText)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.accentSoft.opacity(0.65) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Theme.accentLine : Theme.strokeSoft, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        section(
            title: T("Appearance"),
            subtitle: T("Changes apply immediately.")
        ) {
            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases) { appearance in
                    appearanceOption(appearance)
                }
            }
        }
    }

    private func appearanceOption(_ appearance: AppAppearance) -> some View {
        let selected = settings.appearance == appearance
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                settings.appearance = appearance
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: appearance.symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(appearance.title)
                    .font(Theme.body(9.8, weight: .medium))
            }
            .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.accentSoft : Theme.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.accentLine : Theme.strokeSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Workspace

    private var workspaceCard: some View {
        section(
            title: T("Workspace"),
            subtitle: T("All unpacking happens here. The workspace is cleared when Packager quits.")
        ) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text(prettyPath(Workspace.root.path))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Button(T("Reveal")) {
                    NSWorkspace.shared.open(Workspace.root)
                }
                .buttonStyle(SoftButtonStyle(height: 25, horizontalPadding: 9))
                Button(T("Clear")) {
                    Workspace.cleanAll()
                }
                .buttonStyle(SoftButtonStyle(height: 25, horizontalPadding: 9))
            }
        }
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text("Packager")
                    .font(Theme.body(12, weight: .semibold))
                Spacer()
                Text(T("Version %@", version))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Text(T("Packager is a local installer workbench. Nothing is uploaded."))
                .font(Theme.body(9.5))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    settings.resetOnboarding()
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(T("Show the welcome screen again"))
                    }
                }
                .buttonStyle(SoftButtonStyle(height: 26, horizontalPadding: 10))

                Spacer()

                Link("GitHub", destination: URL(string: "https://github.com/Dirty-Octopus/packager")!)
                    .font(Theme.body(9.5, weight: .medium))
                    .foregroundStyle(Theme.accent)

                Text("MIT")
                    .font(Theme.body(9.5, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(subtitle)
                    .font(Theme.body(9.3))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.surface.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}
