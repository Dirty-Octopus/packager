import SwiftUI

struct ProjectView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var project: PackageProject

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 11) {
                    tabBar
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                RebuildRail(project: project)
                    .frame(width: 326)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            PackageGlyph(
                format: project.inspection?.format,
                isBundle: project.isBundle,
                size: 50
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(project.displayTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)

                    if let inspection = project.inspection {
                        Badge(
                            text: T(inspection.format.rawValue),
                            tint: project.isBundle ? Color(hex: 0x2E8FB8) : Theme.accent,
                            icon: inspection.format.symbol
                        )
                        signatureBadge(inspection.signature)
                    } else if project.phase.isInspecting {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini).scaleEffect(0.68)
                            Text(T("Inspecting"))
                                .font(Theme.body(10, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text(prettyPath(project.sourceURL.path))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    dot
                    Text(Fmt.size(project.sourceSize))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.tertiaryText)

                    if let inspection = project.inspection {
                        dot
                        Text(P(T("%d component(s)", inspection.stats.components)))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.tertiaryText)
                        dot
                        Text(P(T("%d payload file(s)", inspection.stats.payloadFiles)))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                HeaderAction(symbol: "folder", help: T("Reveal the original package")) {
                    project.revealSource()
                }
                HeaderAction(symbol: "shippingbox", help: T("Reveal the workspace")) {
                    project.revealWorkspace()
                }
                HeaderAction(symbol: "gearshape", help: T("Open Settings")) {
                    NotificationCenter.default.post(name: .packagerOpenSettings, object: nil)
                }
                HeaderAction(symbol: "xmark", help: T("Remove from sidebar"), tint: Theme.secondaryText) {
                    model.remove(project)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func signatureBadge(_ signature: String) -> some View {
        if signature.localizedCaseInsensitiveContains("signed by") {
            Badge(text: T("Signed"), tint: Theme.success, icon: "checkmark.seal.fill")
                .help(signature)
        } else if signature.localizedCaseInsensitiveContains("unsigned") {
            Badge(text: T("Unsigned"), tint: Theme.tertiaryText, icon: "seal")
                .help(T("The original package is not signed"))
        }
    }

    private var dot: some View {
        Circle()
            .fill(Theme.tertiaryText.opacity(0.55))
            .frame(width: 2.5, height: 2.5)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .fixedSize()
    }

    private func tabButton(_ tab: DetailTab) -> some View {
        let isActive = project.tab == tab
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                project.tab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 9.5, weight: .medium))
                Text(tab.title)
                    .font(Theme.body(11.5, weight: .medium))

                if tab == .issues, project.issueCount > 0 {
                    Text("\(project.issueCount)")
                        .font(Theme.mono(8.5, weight: .semibold))
                        .foregroundStyle(isActive ? .white.opacity(0.9) : Theme.critical)
                        .padding(.horizontal, 4)
                        .frame(height: 14)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.white.opacity(0.18) : Theme.criticalSoft)
                        )
                }
            }
            .foregroundStyle(isActive ? Color.white : Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? Theme.accent : Color.clear)
            )
            .shadow(color: isActive ? Theme.accent.opacity(0.25) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch project.phase {
        case .inspecting:
            InspectingPanel(project: project)
        case .failed(let message):
            InspectionFailurePanel(project: project, message: message)
        case .ready:
            if project.tab == .structure {
                StructurePanel(project: project)
            } else {
                IssuesPanel(project: project)
            }
        }
    }
}

struct HeaderAction: View {
    var symbol: String
    var help: String
    var tint: Color = Theme.secondaryText
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? Theme.primaryText : tint)
                .frame(width: 29, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Theme.surface : Theme.surface.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Inspecting

struct InspectingPanel: View {
    @ObservedObject var project: PackageProject

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.accentSoft)
                    .frame(width: 54, height: 54)
                ProgressView()
                    .controlSize(.small)
            }
            Text(T("Inspecting package"))
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 14)
            Text(T("Unpacking into the workspace and walking every payload."))
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(project.log.suffix(4)) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.accent.opacity(0.55))
                            .frame(width: 3, height: 3)
                        Text(entry.text)
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.top, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }
}

struct InspectionFailurePanel: View {
    @ObservedObject var project: PackageProject
    var message: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.criticalSoft)
                    .frame(width: 54, height: 54)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.critical)
            }
            Text(T("Couldn’t inspect this package"))
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 14)
            Text(message)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .padding(.top, 6)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button(T("Try Again")) {
                    project.retryInspection()
                }
                .buttonStyle(SoftButtonStyle(height: 31, horizontalPadding: 14, prominent: true))

                Button(T("Reveal Workspace")) {
                    project.revealWorkspace()
                }
                .buttonStyle(SoftButtonStyle(height: 31, horizontalPadding: 14))
            }
            .padding(.top, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }
}
