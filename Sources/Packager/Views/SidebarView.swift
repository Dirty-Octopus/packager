import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            HStack(spacing: 10) {
                BrandMark(size: 29)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Packager")
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.primaryText)
                    Text(T("Installer workbench"))
                        .font(Theme.body(9.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)

            HStack {
                SectionLabel(text: T("Packages"))
                Spacer()
                if !model.projects.isEmpty {
                    Text("\(model.projects.count)")
                        .font(Theme.mono(9.5, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 7)

            if model.projects.isEmpty {
                emptyHint
                    .padding(.horizontal, 12)
                Spacer(minLength: 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(model.projects) { project in
                            SidebarRow(project: project, isSelected: model.selectedProjectID == project.id) {
                                model.selectedProjectID = project.id
                            }
                            .contextMenu {
                                Button(T("Reveal Original")) { project.revealSource() }
                                Button(T("Repackage")) { project.rebuild() }
                                    .disabled(!project.canRebuild)
                                Button(T("Reveal Workspace")) { project.revealWorkspace() }
                                Divider()
                                Button(T("Remove from Sidebar")) { model.remove(project) }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 8)
            workspaceCard
            footer
        }
        .frame(width: 252)
        .background(sidebarBackground.ignoresSafeArea(edges: .top))
    }

    private var sidebarBackground: some View {
        ZStack {
            Theme.sidebar
            LinearGradient(
                colors: [Theme.accent.opacity(0.09), .clear, Color(hex: 0xD08BFF).opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text(T("Drop a .pkg or .mpkg\nanywhere in this window"))
                .font(Theme.body(10.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.tertiaryText)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                Text(T("Workspace"))
                    .font(Theme.body(10.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                Button {
                    model.revealWorkspace()
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help(T("Reveal the workspace"))
            }
            Text(prettyPath(Workspace.root.path))
                .font(Theme.mono(8.5))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.strokeSoft, lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 8.5))
            Text(T("Local only · nothing uploaded"))
                .font(Theme.body(8.8))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                settings.toggleLanguage()
            } label: {
                Text(settings.language.shortName)
                    .font(Theme.body(8.8, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 20, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.surface.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
            .help(settings.language == .en ? "切换到简体中文" : "Switch to English")

            Button {
                NotificationCenter.default.post(name: .packagerOpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(T("Open Settings"))
        }
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 13)
    }
}

struct SidebarRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var project: PackageProject
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                PackageGlyph(format: project.inspection?.format, isBundle: project.isBundle, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(project.displayTitle)
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(Theme.body(9.3))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 8)
            .frame(height: 43)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Theme.surface : (hovering ? Theme.surface.opacity(0.5) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Theme.stroke : Color.clear, lineWidth: 1)
            )
            .shadow(color: isSelected ? Theme.shadow : Color.clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var statusLine: String {
        switch project.phase {
        case .inspecting: return L10n.t("Inspecting") + "…"
        case .failed: return T("Couldn’t inspect this package")
        case .ready: return project.subtitle
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if project.phase.isInspecting {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.72)
        } else if project.issueCount > 0 {
            Text("\(project.issueCount)")
                .font(Theme.mono(9, weight: .semibold))
                .foregroundStyle(Theme.critical)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(Capsule().fill(Theme.criticalSoft))
        }
    }
}
