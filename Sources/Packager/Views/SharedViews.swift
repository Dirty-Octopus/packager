import SwiftUI

// MARK: - Brand

struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.gradient)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white.opacity(0.97))
                .offset(y: -size * 0.005)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.30), radius: size * 0.20, x: 0, y: size * 0.09)
    }
}

struct PackageGlyph: View {
    var format: PackageFormat?
    var isBundle: Bool
    var size: CGFloat = 50

    private var tint: Color {
        if isBundle { return Color(hex: 0x2E8FB8) }
        return Theme.accent
    }

    private var symbol: String {
        if isBundle { return "folder.fill" }
        return "shippingbox.fill"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Helpers

func prettyPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home { return "~" }
    if path.hasPrefix(home + "/") {
        return "~" + path.dropFirst(home.count)
    }
    return path
}

func nodeTint(_ node: PackageNode) -> Color {
    switch node.kind {
    case .product: return Theme.accent
    case .component: return Color(hex: 0x3E7BD6)
    case .payload, .payloadArchive: return Color(hex: 0x8B5CF6)
    case .folder: return Color(hex: 0x7C6E99)
    case .binary: return node.is32Bit ? Theme.critical : Color(hex: 0x2E9E6B)
    case .script: return node.risk == .high ? Theme.critical : Theme.warning
    case .distribution: return Color(hex: 0x3E7BD6)
    case .packageInfo: return Color(hex: 0x0F9488)
    case .bom: return Color(hex: 0xA1743F)
    case .resources: return Color(hex: 0x6366F1)
    case .file, .truncated, .check: return Theme.tertiaryText
    }
}

func severityTint(_ severity: Severity) -> Color {
    switch severity {
    case .critical: return Theme.critical
    case .warning: return Theme.warning
    case .info: return Theme.info
    }
}

func issueTint(_ category: IssueCategory) -> Color {
    switch category {
    case .architecture: return Theme.critical
    case .osVersion: return Theme.warning
    case .relocatable: return Theme.info
    case .scripts: return Theme.warning
    case .signature: return Theme.secondaryText
    case .integrity: return Theme.secondaryText
    }
}

func logTint(_ level: LogLevel) -> Color {
    switch level {
    case .info: return Theme.logText.opacity(0.82)
    case .success: return Color(hex: 0x5FD39B)
    case .warning: return Color(hex: 0xF0B44E)
    case .error: return Color(hex: 0xFF7A7E)
    case .command: return Color(hex: 0xB79CFF)
    }
}

enum TimeStamp {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func short(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

// MARK: - Log

struct LogConsole: View {
    @ObservedObject var project: PackageProject
    var height: CGFloat = 138

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if project.log.isEmpty {
                        Text(T("Waiting for activity…"))
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.logText.opacity(0.35))
                            .padding(4)
                    }
                    ForEach(project.log) { entry in
                        HStack(alignment: .top, spacing: 7) {
                            Text(TimeStamp.short(entry.date))
                                .font(Theme.mono(8.5))
                                .foregroundStyle(Theme.logText.opacity(0.30))
                            Text(entry.text)
                                .font(Theme.mono(9.5))
                                .foregroundStyle(logTint(entry.level))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id(entry.id)
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.logBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .onChange(of: project.log.count) { _, _ in
                if let last = project.log.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Small inputs

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Filter"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.primaryText)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 168, height: 27)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.strokeSoft, lineWidth: 1)
        )
    }
}

struct FilterChip: View {
    var title: String
    var symbol: String?
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                }
                Text(title).font(Theme.body(10.2, weight: .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(isActive ? Theme.accent : Theme.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? Theme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isActive ? Theme.accentLine : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PanelBackground: ViewModifier {
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: Theme.shadow, radius: 12, x: 0, y: 5)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func panel(radius: CGFloat = 16) -> some View {
        modifier(PanelBackground(radius: radius))
    }
}

struct MiniIconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hover ? Theme.primaryText : Theme.secondaryText)
                .frame(width: 27, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hover ? Theme.surfaceMuted : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
