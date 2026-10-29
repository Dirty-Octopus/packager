import SwiftUI

struct RebuildRail: View {
    @ObservedObject var project: PackageProject
    @State private var showCommand = false

    private var editable: Bool {
        project.phase.isReady && !project.buildState.isRunningOrAuthorizing
    }

    private var stats: InspectionStats {
        project.inspection?.stats ?? InspectionStats()
    }

    private var enabledCount: Int {
        var count = 0
        if project.options.removeVersionLimits { count += 1 }
        if project.options.removeRelocatable { count += 1 }
        if project.options.stripHighRiskScripts { count += 1 }
        return count
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 11) {
                modernizeCard
                outputCard
                repackageButton
                statusSection
                activityCard
                footnote
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: Modernize

    private var modernizeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(T("Modernize"))
                    .font(Theme.body(12.5, weight: .semibold))
                Spacer()
                Badge(text: T("%d selected", enabledCount), tint: Theme.accent, background: Theme.accentSoft)
            }

            Text(T("Edits are applied to a copy during repackaging."))
                .font(Theme.body(9.5))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 3)

            Hairline()
                .padding(.vertical, 6)

            OptionToggle(
                icon: "calendar.badge.minus",
                title: T("Remove OS version limits"),
                detail: stats.osConstraints > 0
                    ? P(T("%d gate(s) in Distribution", stats.osConstraints))
                    : T("No version gates detected"),
                isOn: versionBinding,
                enabled: editable && stats.osConstraints > 0,
                recommended: stats.osConstraints > 0
            )

            OptionToggle(
                icon: "arrow.triangle.branch",
                title: T("Clear relocatable flags"),
                detail: stats.relocatableComponents > 0
                    ? P(T("%d component(s) can relocate", stats.relocatableComponents))
                    : T("No relocatable components"),
                isOn: relocatableBinding,
                enabled: editable && stats.relocatableComponents > 0,
                recommended: stats.relocatableComponents > 0
            )

            OptionToggle(
                icon: "scissors",
                title: T("Strip high-risk scripts"),
                detail: stats.highRiskScripts > 0
                    ? P(T("%d script(s) with risky commands", stats.highRiskScripts))
                    : T("No high-risk scripts"),
                isOn: scriptsBinding,
                enabled: editable && stats.highRiskScripts > 0
            )
        }
        .card(padding: 13)
    }

    // MARK: Output

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(T("Output"))
                    .font(Theme.body(12.5, weight: .semibold))
                Spacer()
                Badge(text: "XAR", tint: Theme.secondaryText, mono: true)
            }

            Button {
                project.chooseOutputDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.accent.opacity(0.9))
                    Text(prettyPath(project.options.outputDirectory.path))
                        .font(Theme.mono(9.3))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.strokeSoft, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .help(T("Choose the output folder"))

            TextField(T("Package name"), text: $project.options.outputName)
                .textFieldStyle(.plain)
                .font(Theme.mono(9.8))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.strokeSoft, lineWidth: 1)
                )
                .disabled(!editable)
                .onSubmit {
                    project.options.outputName = PackageRebuilder.normalizedOutputName(
                        project.options.outputName,
                        fallbackSource: project.sourceURL
                    )
                }

            HStack(spacing: 4) {
                Image(systemName: "signature")
                    .font(.system(size: 8))
                Text(T("Signature is not preserved on rebuild"))
                    .font(Theme.body(8.8))
            }
            .foregroundStyle(Theme.tertiaryText)
        }
        .card(padding: 13)
    }

    // MARK: Action

    private var repackageButton: some View {
        VStack(spacing: 6) {
            Button {
                project.rebuild()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(actionTitle)
                    Spacer(minLength: 20)
                    Text("⌘R")
                        .font(Theme.mono(9.5))
                        .opacity(0.5)
                }
                .padding(.horizontal, 13)
            }
            .buttonStyle(GradientButtonStyle(height: 41, enabled: project.canRebuild))
            .disabled(!project.canRebuild)
            .help(T("Repackage"))

            if project.phase.isReady, let output = outputSummary {
                Text(output)
                    .font(Theme.body(8.8))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var actionTitle: String {
        switch project.buildState {
        case .running: return T("Repackaging…")
        case .authorization: return T("Waiting for authorization")
        default: return T("Repackage")
        }
    }

    private var actionSymbol: String {
        switch project.buildState {
        case .running: return "hourglass"
        case .authorization: return "lock.fill"
        default: return "shippingbox.fill"
        }
    }

    private var outputSummary: String? {
        guard project.phase.isReady else { return nil }
        let name = PackageRebuilder.normalizedOutputName(project.options.outputName, fallbackSource: project.sourceURL)
        return T("Saves %@ to %@", name, prettyPath(project.options.outputDirectory.path))
    }

    // MARK: Status

    @ViewBuilder
    private var statusSection: some View {
        switch project.buildState {
        case .idle:
            EmptyView()
        case .running(let step):
            runningCard(step)
        case .authorization(let request):
            authorizationCard(request)
        case .success(let result):
            successCard(result)
        case .failure(let message):
            failureCard(message)
        }
    }

    private func runningCard(_ step: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.78)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(T("Repackaging"))
                    .font(Theme.body(11, weight: .semibold))
                Text(step)
                    .font(Theme.body(9.3))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(T("Cancel")) {
                project.cancelBuild()
            }
            .buttonStyle(.plain)
            .font(Theme.body(9.3, weight: .medium))
            .foregroundStyle(Theme.critical)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.accentSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.accentLine, lineWidth: 1)
        )
    }

    private func authorizationCard(_ request: PrivilegeRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text(T("Administrator access"))
                    .font(Theme.body(11.3, weight: .semibold))
                Spacer()
            }

            Text(request.message)
                .font(Theme.body(9.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(T("macOS will ask for your password. Packager runs only the command below."))
                .font(Theme.body(8.8))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            if showCommand {
                Text(request.command)
                    .font(Theme.mono(8.2))
                    .foregroundStyle(Theme.logText.opacity(0.8))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.logBackground)
                    )
            }

            HStack(spacing: 6) {
                Button {
                    project.authorizeAndFinish(request)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "touchid")
                            .font(.system(size: 9, weight: .semibold))
                        Text(T("Authorize…"))
                    }
                }
                .buttonStyle(SoftButtonStyle(height: 27, horizontalPadding: 10, prominent: true))

                Button(T("Cancel")) {
                    showCommand = false
                    project.resetBuildState()
                }
                .buttonStyle(SoftButtonStyle(height: 27, horizontalPadding: 10))

                Spacer(minLength: 0)

                Button(showCommand ? T("Hide command") : T("Show command")) {
                    withAnimation(.snappy(duration: 0.15)) { showCommand.toggle() }
                }
                .buttonStyle(.plain)
                .font(Theme.body(8.8))
                .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.warningSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.28), lineWidth: 1)
        )
    }

    private func successCard(_ result: BuildResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Theme.success.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.success)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("Package rebuilt"))
                        .font(Theme.body(11.5, weight: .semibold))
                    Text(result.outputURL.lastPathComponent)
                        .font(Theme.mono(8.8))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Badge(text: T("Verified"), tint: Theme.success, icon: "checkmark.seal.fill")
            }

            HStack(spacing: 5) {
                MetaChip(text: Fmt.size(result.size), tint: Theme.secondaryText)
                MetaChip(text: Fmt.duration(result.duration), tint: Theme.secondaryText)
                if result.appliedFixCount > 0 {
                    MetaChip(text: T("%d fixes", result.appliedFixCount), tint: Theme.success)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Button(T("Reveal in Finder")) {
                    project.revealOutput()
                }
                .buttonStyle(SoftButtonStyle(height: 26, horizontalPadding: 10, prominent: true))

                Button(T("Done")) {
                    project.resetBuildState()
                }
                .buttonStyle(SoftButtonStyle(height: 26, horizontalPadding: 10))
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.successSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.success.opacity(0.26), lineWidth: 1)
        )
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.critical)
                Text(T("Repackage failed"))
                    .font(Theme.body(11.3, weight: .semibold))
                Spacer()
            }
            Text(message)
                .font(Theme.body(9.3))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Button(T("Try Again")) {
                    project.rebuild()
                }
                .buttonStyle(SoftButtonStyle(height: 26, horizontalPadding: 10, prominent: true))

                Button(T("Dismiss")) {
                    project.resetBuildState()
                }
                .buttonStyle(SoftButtonStyle(height: 26, horizontalPadding: 10))
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.criticalSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.critical.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: Activity

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(T("Activity"))
                    .font(Theme.body(11.3, weight: .semibold))
                Text(project.log.isEmpty ? T("No activity yet") : T("%d events", project.log.count))
                    .font(Theme.body(8.8))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                Button(project.showActivity ? T("Hide") : T("Show")) {
                    withAnimation(.snappy(duration: 0.16)) { project.showActivity.toggle() }
                }
                .buttonStyle(.plain)
                .font(Theme.body(8.8, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)

                Button(T("Workspace")) {
                    project.revealWorkspace()
                }
                .buttonStyle(.plain)
                .font(Theme.body(8.8, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.85))
            }

            if project.showActivity {
                LogConsole(project: project, height: 132)
            }
        }
        .card(padding: 11)
    }

    private var footnote: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 7.5))
            Text(T("Local pkgutil pipeline · workspace only"))
                .font(Theme.body(8.5))
        }
        .foregroundStyle(Theme.tertiaryText)
        .frame(maxWidth: .infinity)
        .padding(.top, 1)
    }

    // MARK: Bindings

    private var versionBinding: Binding<Bool> {
        Binding(
            get: { project.options.removeVersionLimits },
            set: { project.options.removeVersionLimits = $0 }
        )
    }

    private var relocatableBinding: Binding<Bool> {
        Binding(
            get: { project.options.removeRelocatable },
            set: { project.options.removeRelocatable = $0 }
        )
    }

    private var scriptsBinding: Binding<Bool> {
        Binding(
            get: { project.options.stripHighRiskScripts },
            set: { project.options.stripHighRiskScripts = $0 }
        )
    }
}
