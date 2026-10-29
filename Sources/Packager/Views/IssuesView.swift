import SwiftUI

struct IssuesPanel: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var project: PackageProject

    private var issues: [PackageIssue] {
        project.inspection?.issues(for: settings.language) ?? []
    }

    private var grouped: [(severity: Severity, issues: [PackageIssue])] {
        [Severity.critical, .warning, .info].compactMap { severity in
            let matching = issues.filter { $0.severity == severity }
            return matching.isEmpty ? nil : (severity, matching)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if issues.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 9) {
                        ForEach(issues) { issue in
                            IssueCard(project: project, issue: issue)
                        }
                    }
                    .padding(13)
                }
            }
        }
        .panel()
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T("Review before repackaging"))
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(T("Modernization fixes are applied to a copy in your workspace."))
                    .font(Theme.body(9.5))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 8)

            ForEach(grouped, id: \.severity) { group in
                HStack(spacing: 4) {
                    Circle()
                        .fill(severityTint(group.severity))
                        .frame(width: 5, height: 5)
                    Text("\(group.issues.count)")
                        .font(Theme.mono(9.5, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(
                    Capsule()
                        .fill(Theme.surfaceMuted)
                )
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.successSoft)
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.success)
            }
            Text(T("No findings"))
                .font(Theme.body(13, weight: .semibold))
            Text(T("This package has no legacy gates or risky scripts. It can be repackaged as-is."))
                .font(Theme.body(10.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IssueCard: View {
    @ObservedObject var project: PackageProject
    let issue: PackageIssue

    private var tint: Color { severityTint(issue.severity) }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: issue.severity.symbol)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(P(issue.title))
                        .font(Theme.body(12.3, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)

                    Badge(text: T(issue.category.title), tint: issueTint(issue.category))
                    Spacer(minLength: 4)
                    Text(T(issue.severity.label))
                        .font(Theme.body(8.8, weight: .medium))
                        .foregroundStyle(tint.opacity(0.85))
                }

                Text(P(issue.message))
                    .font(Theme.body(10.8))
                    .foregroundStyle(Theme.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !issue.paths.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(Array(issue.paths.prefix(3).enumerated()), id: \.offset) { _, path in
                            Text(path)
                                .font(Theme.mono(8.8))
                                .foregroundStyle(Theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Theme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Theme.strokeSoft, lineWidth: 1)
                                )
                        }
                        if issue.paths.count > 3 {
                            Text("+\(issue.paths.count - 3)")
                                .font(Theme.mono(8.5))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }

                if let fix = issue.fix {
                    fixRow(fix)
                        .padding(.top, 1)
                }
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.strokeSoft, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func fixRow(_ fix: FixKind) -> some View {
        let enabled = isEnabled(fix)
        HStack(spacing: 6) {
            if enabled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.success)
                Text(T("Included in the next repackage"))
                    .font(Theme.body(9.5, weight: .medium))
                    .foregroundStyle(Theme.success)
                Button(T("Undo")) {
                    withAnimation(.snappy(duration: 0.15)) { setEnabled(fix, false) }
                }
                .buttonStyle(.plain)
                .font(Theme.body(9.5, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.15)) { setEnabled(fix, true) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(T(actionTitle(fix)))
                    }
                }
                .buttonStyle(SoftButtonStyle(height: 24, horizontalPadding: 9, prominent: true))
            }
            Spacer(minLength: 0)
        }
    }

    private func isEnabled(_ fix: FixKind) -> Bool {
        switch fix {
        case .versionLimits: return project.options.removeVersionLimits
        case .relocatable: return project.options.removeRelocatable
        case .scripts: return project.options.stripHighRiskScripts
        }
    }

    private func setEnabled(_ fix: FixKind, _ value: Bool) {
        switch fix {
        case .versionLimits: project.options.removeVersionLimits = value
        case .relocatable: project.options.removeRelocatable = value
        case .scripts: project.options.stripHighRiskScripts = value
        }
    }

    private func actionTitle(_ fix: FixKind) -> String {
        switch fix {
        case .versionLimits: return "Remove version gate"
        case .relocatable: return "Clear relocatable"
        case .scripts: return "Strip high-risk scripts"
        }
    }
}
